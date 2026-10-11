package app.blurr

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import kotlin.math.max

/**
 * Effet vidéo Media3 : floute (ou noircit) les ellipses du [MaskPlan] sur chaque image.
 *
 * Déroulé d'une image :
 *  1. si au moins un visage est à flouter, réduction de l'image en pyramide (niveaux 1/2, 1/4, ...), uniquement
 *     jusqu'au niveau dont les visages de l'image ont besoin ;
 *  2. copie de l'image source dans la sortie ;
 *  3. pour chaque ellipse, dessin d'un rectangle englobant, mélangé à la sortie : flou reconstruit depuis la pyramide
 *     (voir [BlurGeometry]) ou noir opaque, avec un bord adouci calculé analytiquement à la résolution de sortie.
 *
 * Les ellipses sont dessinées par niveau de flou croissant : là où deux ellipses se recouvrent, le flou le plus fort
 * l'emporte, et l'intérieur d'une ellipse n'est jamais moins flouté que son propre niveau.
 * Media3 fournit aux effets des images déjà redressées (le décodeur applique la rotation du fichier).
 */
@UnstableApi
class MaskEffect(private val plan: MaskPlan, private val style: MaskStyle) : GlEffect {

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        MaskShaderProgram(plan, style, useHdr)

    /** Nom lisible dans les journaux. */
    override fun toString(): String = "MaskEffect(${plan.frameCount} images, $style)"
}

@UnstableApi
private class MaskShaderProgram(
    private val plan: MaskPlan,
    private val style: MaskStyle,
    private val useHdr: Boolean,
) : BaseGlShaderProgram(/* useHighPrecisionColorComponents= */ useHdr, /* texturePoolCapacity= */ 1) {

    private val copyProgram: GlProgram
    private val faceProgram: GlProgram
    private val locRect: Int
    private val locEllipse: Int
    private val locMix: Int
    private val locSizes: Int
    private val locLevel0: Int
    private val locLevel1: Int

    private var width = 0
    private var height = 0

    /** Niveaux 1..n de la pyramide (indice k - 1), alloués à la demande. */
    private val levelTex = IntArray(BlurGeometry.MAX_LEVELS) { 0 }
    private val levelFbo = IntArray(BlurGeometry.MAX_LEVELS) { 0 }
    private val levelW = IntArray(BlurGeometry.MAX_LEVELS)
    private val levelH = IntArray(BlurGeometry.MAX_LEVELS)

    private val boundFbo = IntArray(1)
    private var firstExportPtsUs = Long.MIN_VALUE
    private var drawnFrames = 0
    private var maskedFrames = 0
    private var drawnEllipses = 0L

    // Tampons réutilisés : une ellipse = cx, cy (repère de texture, v vers le haut), rx, ry, niveau.
    private var faces = FloatArray(0)
    private var order = IntArray(0)

    init {
        try {
            copyProgram = GlProgram(MaskShaders.COPY_VERTEX_SHADER, MaskShaders.COPY_FRAGMENT_SHADER)
            copyProgram.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
            faceProgram = GlProgram(
                MaskShaders.FACE_VERTEX_SHADER,
                if (style == MaskStyle.BLUR) MaskShaders.BLUR_FRAGMENT_SHADER else MaskShaders.BLACK_FRAGMENT_SHADER,
            )
            faceProgram.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
            locRect = faceProgram.getUniformLocation("uRect")
            locEllipse = faceProgram.getUniformLocation("uEllipse")
            locMix = faceProgram.getUniformLocation("uMix")
            locSizes = faceProgram.getUniformLocation("uSizes")
            locLevel0 = faceProgram.getUniformLocation("uLevel0")
            locLevel1 = faceProgram.getUniformLocation("uLevel1")
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        if (inputWidth != width || inputHeight != height) {
            releasePyramid()
            width = inputWidth
            height = inputHeight
            for (k in 1..BlurGeometry.MAX_LEVELS) {
                levelW[k - 1] = BlurGeometry.levelSize(width, k)
                levelH[k - 1] = BlurGeometry.levelSize(height, k)
            }
        }
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            if (firstExportPtsUs == Long.MIN_VALUE) {
                firstExportPtsUs = presentationTimeUs
                val shift = plan.alignTo(presentationTimeUs)
                AppLog.i("Export : première image à $presentationTimeUs us, décalage appliqué $shift us, rendu $style")
            }
            val ellipses = plan.lookup(presentationTimeUs)
            val count = prepareFaces(ellipses)

            GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, boundFbo, 0)
            if (style == MaskStyle.BLUR && count > 0) {
                var maxLower = 1
                for (i in 0 until count) maxLower = max(maxLower, BlurGeometry.lowerLevel(faces[i * 5 + 4]))
                buildPyramid(inputTexId, minOf(maxLower + 1, BlurGeometry.MAX_LEVELS))
                GlUtil.focusFramebufferUsingCurrentContext(boundFbo[0], width, height)
            }

            // Copie de l'image source.
            copyProgram.use()
            copyProgram.setSamplerTexIdUniform("uTex", inputTexId, /* texUnitIndex= */ 0)
            copyProgram.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, /* first= */ 0, /* count= */ 4)

            if (count > 0) drawFaces(count)

            drawnFrames++
            if (count > 0) {
                maskedFrames++
                drawnEllipses += count
            }
            GlUtil.checkGlError()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    /** Convertit les ellipses du plan en paramètres de dessin, triés par niveau de flou croissant. Renvoie leur nombre. */
    private fun prepareFaces(ellipses: FloatArray): Int {
        val count = ellipses.size / 4
        if (count == 0) return 0
        if (faces.size < count * 5) {
            faces = FloatArray(count * 5)
            order = IntArray(count)
        }
        val padX = BlurGeometry.EDGE_PAD_PX / width
        val padY = BlurGeometry.EDGE_PAD_PX / height
        for (i in 0 until count) {
            val cx = ellipses[i * 4]
            val cy = ellipses[i * 4 + 1]
            val rx = ellipses[i * 4 + 2]
            val ry = ellipses[i * 4 + 3]
            faces[i * 5] = cx
            faces[i * 5 + 1] = 1f - cy // repère de texture : v = 0 en bas
            faces[i * 5 + 2] = rx + padX
            faces[i * 5 + 3] = ry + padY
            faces[i * 5 + 4] = BlurGeometry.level(rx * width, ry * height)
        }
        // Tri par insertion sur le niveau (quelques dizaines d'ellipses au plus en pratique).
        for (i in 0 until count) order[i] = i
        for (i in 1 until count) {
            val v = order[i]
            var j = i - 1
            while (j >= 0 && faces[order[j] * 5 + 4] > faces[v * 5 + 4]) {
                order[j + 1] = order[j]
                j--
            }
            order[j + 1] = v
        }
        return count
    }

    /** Remplit les niveaux 1..[levels] de la pyramide à partir de l'image source. */
    private fun buildPyramid(inputTexId: Int, levels: Int) {
        copyProgram.use()
        for (k in 1..levels) {
            if (levelTex[k - 1] == 0) {
                levelTex[k - 1] = GlUtil.createTexture(levelW[k - 1], levelH[k - 1], useHdr)
                levelFbo[k - 1] = GlUtil.createFboForTexture(levelTex[k - 1])
            }
            GlUtil.focusFramebufferUsingCurrentContext(levelFbo[k - 1], levelW[k - 1], levelH[k - 1])
            // Échantillonnage bilinéaire au centre de chaque pixel de sortie : moyenne du bloc 2 x 2 correspondant.
            copyProgram.setSamplerTexIdUniform("uTex", if (k == 1) inputTexId else levelTex[k - 2], 0)
            copyProgram.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
    }

    private fun drawFaces(count: Int) {
        GLES20.glEnable(GLES20.GL_BLEND)
        // Couleur mélangée selon l'opacité du masque ; alpha de la sortie inchangé.
        GLES20.glBlendFuncSeparate(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA, GLES20.GL_ZERO, GLES20.GL_ONE)
        faceProgram.use()
        var boundLower = -1
        if (style == MaskStyle.BLUR) {
            // GlProgram exige une texture pour chaque échantillonneur avant bindAttributesAndUniforms.
            boundLower = minOf(BlurGeometry.lowerLevel(faces[order[0] * 5 + 4]), BlurGeometry.MAX_LEVELS - 1)
            faceProgram.setSamplerTexIdUniform("uLevel0", levelTex[boundLower - 1], 0)
            faceProgram.setSamplerTexIdUniform("uLevel1", levelTex[boundLower], 1)
            faceProgram.setFloatsUniform(
                "uSizes",
                floatArrayOf(
                    levelW[boundLower - 1].toFloat(), levelH[boundLower - 1].toFloat(),
                    levelW[boundLower].toFloat(), levelH[boundLower].toFloat(),
                ),
            )
        }
        faceProgram.bindAttributesAndUniforms()
        for (n in 0 until count) {
            val i = order[n]
            val cx = faces[i * 5]
            val cv = faces[i * 5 + 1]
            val rx = faces[i * 5 + 2]
            val ry = faces[i * 5 + 3]
            if (style == MaskStyle.BLUR) {
                val level = faces[i * 5 + 4]
                val lower = minOf(BlurGeometry.lowerLevel(level), BlurGeometry.MAX_LEVELS - 1)
                if (lower != boundLower) {
                    bindLevel(GLES20.GL_TEXTURE0, locLevel0, 0, lower)
                    bindLevel(GLES20.GL_TEXTURE1, locLevel1, 1, lower + 1)
                    GLES20.glUniform4f(
                        locSizes,
                        levelW[lower - 1].toFloat(), levelH[lower - 1].toFloat(),
                        levelW[lower].toFloat(), levelH[lower].toFloat(),
                    )
                    boundLower = lower
                }
                GLES20.glUniform1f(locMix, (level - lower).coerceIn(0f, 1f))
            }
            GLES20.glUniform4f(locRect, cx - rx, cv - ry, cx + rx, cv + ry)
            GLES20.glUniform4f(locEllipse, cx, cv, rx, ry)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun bindLevel(unit: Int, location: Int, unitIndex: Int, k: Int) {
        GLES20.glActiveTexture(unit)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, levelTex[k - 1])
        GLES20.glUniform1i(location, unitIndex)
    }

    private fun releasePyramid() {
        for (k in levelTex.indices) {
            try {
                if (levelFbo[k] != 0) GlUtil.deleteFbo(levelFbo[k])
                if (levelTex[k] != 0) GlUtil.deleteTexture(levelTex[k])
            } catch (e: GlUtil.GlException) {
                AppLog.e("Libération de la pyramide", e)
            }
            levelFbo[k] = 0
            levelTex[k] = 0
        }
    }

    override fun release() {
        AppLog.i("Export : $drawnFrames images rendues, $maskedFrames avec au moins un masque, $drawnEllipses ellipses dessinées")
        super.release()
        releasePyramid()
        try {
            copyProgram.delete()
            faceProgram.delete()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
    }
}

/** Sources GLSL ES 1.00 de [MaskEffect] (aussi lues par le banc de test hors téléphone). */
internal object MaskShaders {
    const val PRECISION = """
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
"""

    // Opacité : 1 - smoothstep(EDGE_START, 1, r), voir BlurGeometry.coverage.
    const val COVERAGE = """
uniform vec4 uEllipse;
varying vec2 vUv;
float coverage() {
  float r = length((vUv - uEllipse.xy) / uEllipse.zw);
  return 1.0 - smoothstep(0.92, 1.0, r);
}
"""

    const val COPY_VERTEX_SHADER = """
attribute vec4 aFramePosition;
varying vec2 vTex;
void main() {
  gl_Position = aFramePosition;
  vTex = aFramePosition.xy * 0.5 + 0.5;
}
"""

    const val COPY_FRAGMENT_SHADER = PRECISION + """
uniform sampler2D uTex;
varying vec2 vTex;
void main() {
  gl_FragColor = texture2D(uTex, vTex);
}
"""

    // Rectangle uRect (u0, v0, u1, v1) en repère de texture ; la sortie est dessinée dans le même repère.
    const val FACE_VERTEX_SHADER = """
attribute vec4 aFramePosition;
uniform vec4 uRect;
varying vec2 vUv;
void main() {
  vec2 uv = mix(uRect.xy, uRect.zw, aFramePosition.xy * 0.5 + 0.5);
  vUv = uv;
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
"""

    const val BLACK_FRAGMENT_SHADER = PRECISION + COVERAGE + """
void main() {
  float a = coverage();
  if (a <= 0.0) discard;
  gl_FragColor = vec4(0.0, 0.0, 0.0, a);
}
"""

    // B-spline cubique en 4 lectures bilinéaires (Sigg et Hadwiger, GPU Gems 2, chap. 20).
    const val BLUR_FRAGMENT_SHADER = PRECISION + COVERAGE + """
uniform sampler2D uLevel0;
uniform sampler2D uLevel1;
uniform vec4 uSizes;
uniform float uMix;

vec4 bspline(sampler2D tex, vec2 uv, vec2 size) {
  vec2 x = uv * size - 0.5;
  vec2 i = floor(x);
  vec2 f = x - i;
  vec2 f2 = f * f;
  vec2 f3 = f2 * f;
  vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
  vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
  vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
  vec2 w3 = f3 / 6.0;
  vec2 g0 = w0 + w1;
  vec2 g1 = w2 + w3;
  vec2 h0 = (i - 0.5 + w1 / g0) / size;
  vec2 h1 = (i + 1.5 + w3 / g1) / size;
  vec4 a = texture2D(tex, vec2(h0.x, h0.y));
  vec4 b = texture2D(tex, vec2(h1.x, h0.y));
  vec4 c = texture2D(tex, vec2(h0.x, h1.y));
  vec4 d = texture2D(tex, vec2(h1.x, h1.y));
  return g0.y * (g0.x * a + g1.x * b) + g1.y * (g0.x * c + g1.x * d);
}

void main() {
  float a = coverage();
  if (a <= 0.0) discard;
  vec4 c0 = bspline(uLevel0, vUv, uSizes.xy);
  vec4 c1 = bspline(uLevel1, vUv, uSizes.zw);
  gl_FragColor = vec4(mix(c0.rgb, c1.rgb, uMix), a);
}
"""
}

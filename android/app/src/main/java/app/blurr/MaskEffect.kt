package app.blurr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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
import kotlin.math.min

/**
 * Effet vidéo Media3 : noircit les ellipses du [MaskPlan] sur chaque image.
 *
 * Les masques sont dessinés par Canvas dans un petit bitmap alpha (une résolution réduite suffit, les bords sont lissés
 * par le shader), envoyé en texture, puis mélangé à l'image vidéo. Le nombre d'ellipses n'est donc pas limité.
 * Media3 fournit aux effets des images déjà redressées (le décodeur applique la rotation du fichier).
 */
@UnstableApi
class MaskEffect(private val plan: MaskPlan) : GlEffect {

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        MaskShaderProgram(plan, useHdr)

    /** Nom lisible dans les journaux. */
    override fun toString(): String = "MaskEffect(${plan.frameCount} images)"
}

@UnstableApi
private class MaskShaderProgram(
    private val plan: MaskPlan,
    useHdr: Boolean,
) : BaseGlShaderProgram(/* useHighPrecisionColorComponents= */ useHdr, /* texturePoolCapacity= */ 1) {

    private val glProgram: GlProgram
    private val maskTexId: Int
    private var maskBitmap: Bitmap? = null
    private var maskCanvas: Canvas? = null
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.FILL
    }
    private var firstExportPtsUs = Long.MIN_VALUE
    private var drawnFrames = 0
    private var maskedFrames = 0

    init {
        try {
            glProgram = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            glProgram.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
            maskTexId = GlUtil.generateTexture()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        val mw = min(inputWidth, MASK_WIDTH)
        val mh = max(1, (mw.toLong() * inputHeight / inputWidth).toInt())
        val current = maskBitmap
        if (current == null || current.width != mw || current.height != mh) {
            current?.recycle()
            val bitmap = Bitmap.createBitmap(mw, mh, Bitmap.Config.ARGB_8888)
            maskBitmap = bitmap
            maskCanvas = Canvas(bitmap)
        }
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            if (firstExportPtsUs == Long.MIN_VALUE) {
                firstExportPtsUs = presentationTimeUs
                val shift = plan.alignTo(presentationTimeUs)
                AppLog.i("Export : première image à $presentationTimeUs us, décalage appliqué $shift us")
            }
            val bitmap = checkNotNull(maskBitmap)
            val canvas = checkNotNull(maskCanvas)

            bitmap.eraseColor(Color.TRANSPARENT)
            val ellipses = plan.lookup(presentationTimeUs)
            val w = bitmap.width.toFloat()
            val h = bitmap.height.toFloat()
            var i = 0
            while (i + 3 < ellipses.size) {
                val cx = ellipses[i] * w
                val cy = ellipses[i + 1] * h
                val rx = ellipses[i + 2] * w + EDGE_PAD_PX
                val ry = ellipses[i + 3] * h + EDGE_PAD_PX
                canvas.drawOval(cx - rx, cy - ry, cx + rx, cy + ry, paint)
                i += 4
            }
            drawnFrames++
            if (ellipses.isNotEmpty()) maskedFrames++

            GlUtil.setTexture(maskTexId, bitmap)

            glProgram.use()
            glProgram.setSamplerTexIdUniform("uVideo", inputTexId, /* texUnitIndex= */ 0)
            glProgram.setSamplerTexIdUniform("uMask", maskTexId, /* texUnitIndex= */ 1)
            glProgram.bindAttributesAndUniforms()
            // Le quadrilatère (strip de 4 sommets) couvre tout l'espace normalisé.
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, /* first= */ 0, /* count= */ 4)
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        AppLog.i("Export : $drawnFrames images rendues, $maskedFrames avec au moins un masque")
        super.release()
        try {
            glProgram.delete()
            GlUtil.deleteTexture(maskTexId)
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
        maskBitmap?.recycle()
        maskBitmap = null
    }

    private companion object {
        /** Largeur du bitmap de masque ; la hauteur suit le format de la vidéo. */
        const val MASK_WIDTH = 768

        /** Marge ajoutée au rayon pour que le lissage des bords ne découvre rien. */
        const val EDGE_PAD_PX = 1.5f

        const val VERTEX_SHADER = """
attribute vec4 aFramePosition;
varying vec2 vTexSamplingCoord;
void main() {
  gl_Position = aFramePosition;
  vTexSamplingCoord = vec2(aFramePosition.x * 0.5 + 0.5, aFramePosition.y * 0.5 + 0.5);
}
"""

        // Le bitmap de masque est stocké "haut en premier" (convention Android) alors que la texture vidéo
        // est en repère OpenGL (v = 0 en bas) : le masque est donc lu à (u, 1 - v).
        const val FRAGMENT_SHADER = """
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D uVideo;
uniform sampler2D uMask;
varying vec2 vTexSamplingCoord;
void main() {
  vec4 video = texture2D(uVideo, vTexSamplingCoord);
  float m = texture2D(uMask, vec2(vTexSamplingCoord.x, 1.0 - vTexSamplingCoord.y)).a;
  m = smoothstep(0.2, 0.6, m);
  gl_FragColor = vec4(mix(video.rgb, vec3(0.0), m), video.a);
}
"""
    }
}

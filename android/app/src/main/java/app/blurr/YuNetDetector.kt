package app.blurr

import android.content.Context
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.objdetect.FaceDetectorYN
import java.io.File

/**
 * Détecteur de visages YuNet (OpenCV Zoo, licence MIT) via OpenCV DNN. Le modèle est utilisé tel quel, sans entraînement.
 * Les boîtes renvoyées sont normalisées par la taille de l'image fournie.
 */
class YuNetDetector(context: Context, scoreThreshold: Float) : AutoCloseable {

    private val detector: FaceDetectorYN
    private val faces = Mat()
    private var inputWidth = 0
    private var inputHeight = 0

    init {
        val model = installModel(context)
        detector = FaceDetectorYN.create(
            model.absolutePath,
            "",
            Size(320.0, 320.0),
            scoreThreshold,
            NMS_THRESHOLD,
            TOP_K,
        )
    }

    fun detect(bgr: Mat): List<FaceBox> {
        val w = bgr.cols()
        val h = bgr.rows()
        if (w != inputWidth || h != inputHeight) {
            detector.setInputSize(Size(w.toDouble(), h.toDouble()))
            inputWidth = w
            inputHeight = h
        }
        detector.detect(bgr, faces)
        val count = faces.rows()
        if (faces.empty() || count == 0) return emptyList()

        val row = FloatArray(faces.cols())
        val out = ArrayList<FaceBox>(count)
        for (i in 0 until count) {
            faces.get(i, 0, row)
            // Colonnes YuNet : x, y, largeur, hauteur, 5 points de repère (10 valeurs), score.
            out.add(
                FaceBox(
                    x = row[0] / w,
                    y = row[1] / h,
                    w = row[2] / w,
                    h = row[3] / h,
                    score = row[row.size - 1],
                ),
            )
        }
        return out
    }

    override fun close() {
        faces.release()
    }

    private fun installModel(context: Context): File {
        val target = File(context.filesDir, MODEL_FILE)
        context.assets.open("models/$MODEL_FILE").use { input ->
            val bytes = input.readBytes()
            if (!target.exists() || target.length() != bytes.size.toLong()) {
                target.writeBytes(bytes)
            }
        }
        return target
    }

    companion object {
        const val MODEL_FILE = "face_detection_yunet_2023mar.onnx"
        private const val NMS_THRESHOLD = 0.3f
        private const val TOP_K = 5000
    }
}

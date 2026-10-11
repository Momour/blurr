package app.blurr

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.File
import java.io.IOException

/** Copie le fichier exporté dans la galerie, dossier Movies/blurr (aucune permission requise sur Android 10 et plus). */
object MediaStoreSaver {

    const val RELATIVE_PATH = "Movies/blurr"

    class Saved(val uri: Uri, val displayName: String, val sizeBytes: Long)

    fun save(context: Context, source: File, sourceName: String): Saved {
        val resolver = context.contentResolver
        val wantedName = outputName(sourceName)

        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, wantedName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, RELATIVE_PATH)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: throw IOException("La galerie a refusé la création du fichier")

        try {
            val out = resolver.openOutputStream(uri, "w") ?: throw IOException("Impossible d'écrire dans la galerie")
            out.use { stream -> source.inputStream().use { it.copyTo(stream, COPY_BUFFER) } }
            val done = ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw e
        }

        // Le système peut renommer le fichier en cas de doublon : on relit le nom réel.
        var finalName = wantedName
        try {
            resolver.query(uri, arrayOf(MediaStore.Video.Media.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0)?.let { finalName = it }
            }
        } catch (_: Exception) {
        }
        AppLog.i("Enregistré : $RELATIVE_PATH/$finalName (${source.length()} octets)")
        return Saved(uri, finalName, source.length())
    }

    /** "vacances.MOV" donne "vacances_blurr.mp4" ; les caractères interdits dans un nom de fichier sont retirés. */
    fun outputName(sourceName: String): String {
        val base = sourceName.substringAfterLast('/').substringBeforeLast('.', sourceName.substringAfterLast('/'))
        val cleaned = base
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
            .trim()
            .trim('.')
            .take(80)
            .ifEmpty { "video" }
        return "${cleaned}_blurr.mp4"
    }

    private const val COPY_BUFFER = 1 shl 16
}

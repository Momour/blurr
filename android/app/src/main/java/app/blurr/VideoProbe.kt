package app.blurr

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns

/** Lit les métadonnées de la piste vidéo (taille, rotation, durée, cadence, HDR). */
object VideoProbe {

    fun read(context: Context, uri: Uri): VideoInfo {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: throw IllegalArgumentException("Ce fichier ne contient pas de piste vidéo.")
            val format = extractor.getTrackFormat(track)

            var durationUs = format.longOr(MediaFormat.KEY_DURATION, 0L)
            var bitrate = format.intOr(MediaFormat.KEY_BIT_RATE, 0)
            var rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) format.intOr(MediaFormat.KEY_ROTATION, 0) else -1

            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                if (durationUs <= 0L) {
                    durationUs = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000L
                }
                if (bitrate <= 0) {
                    bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
                }
                if (rotation < 0) {
                    rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                }
            } catch (e: Exception) {
                AppLog.e("Lecture des métadonnées complémentaires impossible", e)
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {
                }
            }

            val transfer = format.intOr(MediaFormat.KEY_COLOR_TRANSFER, 0)
            val hasAudio = (0 until extractor.trackCount).any {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            return VideoInfo(
                name = displayName(context, uri),
                mime = format.getString(MediaFormat.KEY_MIME) ?: "video/?",
                codedWidth = format.intOr(MediaFormat.KEY_WIDTH, 0),
                codedHeight = format.intOr(MediaFormat.KEY_HEIGHT, 0),
                rotation = ((rotation % 360) + 360) % 360,
                durationUs = durationUs,
                frameRate = format.floatOr(MediaFormat.KEY_FRAME_RATE, 0f),
                bitrate = bitrate,
                isHdr = transfer == MediaFormat.COLOR_TRANSFER_ST2084 || transfer == MediaFormat.COLOR_TRANSFER_HLG,
                hasAudio = hasAudio,
            )
        } finally {
            extractor.release()
        }
    }

    private fun displayName(context: Context, uri: Uri): String {
        try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0)?.let { return it }
                }
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment ?: "video"
    }

    private fun MediaFormat.intOr(key: String, default: Int): Int {
        if (!containsKey(key)) return default
        return try {
            getInteger(key)
        } catch (_: Exception) {
            getNumber(key)?.toInt() ?: default
        }
    }

    private fun MediaFormat.longOr(key: String, default: Long): Long {
        if (!containsKey(key)) return default
        return try {
            getLong(key)
        } catch (_: Exception) {
            getNumber(key)?.toLong() ?: default
        }
    }

    private fun MediaFormat.floatOr(key: String, default: Float): Float {
        if (!containsKey(key)) return default
        return try {
            getFloat(key)
        } catch (_: Exception) {
            getNumber(key)?.toFloat() ?: default
        }
    }
}

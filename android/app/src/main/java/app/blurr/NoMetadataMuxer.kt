package app.blurr

import androidx.media3.common.Format
import androidx.media3.common.Metadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.muxer.BufferInfo
import androidx.media3.muxer.Muxer
import androidx.media3.transformer.DefaultMuxer
import com.google.common.collect.ImmutableList
import java.nio.ByteBuffer

/**
 * Fabrique de muxer qui n'écrit AUCUNE métadonnée héritée de la vidéo source.
 *
 * Par défaut, Media3 recopie dans le fichier exporté les métadonnées de la piste vidéo d'origine, dont la position GPS
 * (Mp4LocationData), les métadonnées de la caméra et le XMP. Cette fabrique les ignore toutes. L'orientation du
 * fichier n'est pas concernée : le muxer MP4 l'écrit lui-même à partir du format de la piste, sans passer par ici.
 */
@UnstableApi
class NoMetadataMuxerFactory(
    private val delegate: Muxer.Factory = DefaultMuxer.Factory(),
) : Muxer.Factory {

    override fun create(path: String): Muxer = NoMetadataMuxer(delegate.create(path))

    override fun getSupportedSampleMimeTypes(trackType: Int): ImmutableList<String> =
        delegate.getSupportedSampleMimeTypes(trackType)

    override fun supportsWritingNegativeTimestampsInEditList(): Boolean =
        delegate.supportsWritingNegativeTimestampsInEditList()
}

@UnstableApi
private class NoMetadataMuxer(private val delegate: Muxer) : Muxer {

    private val ignoredKinds = LinkedHashSet<String>()

    override fun addTrack(format: Format): Int = delegate.addTrack(format)

    override fun writeSampleData(trackId: Int, byteBuffer: ByteBuffer, bufferInfo: BufferInfo) {
        delegate.writeSampleData(trackId, byteBuffer, bufferInfo)
    }

    override fun addMetadataEntry(metadataEntry: Metadata.Entry) {
        // On ne journalise que le type de l'entrée, jamais son contenu (coordonnées, horodatages).
        ignoredKinds.add(metadataEntry.javaClass.simpleName)
    }

    override fun close() {
        AppLog.i(
            if (ignoredKinds.isEmpty()) {
                "Métadonnées : aucune entrée héritée de la source"
            } else {
                "Métadonnées de la source supprimées : ${ignoredKinds.joinToString()}"
            },
        )
        delegate.close()
    }
}

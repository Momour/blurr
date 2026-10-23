import AVFoundation
import CoreGraphics
import CoreVideo
import UIKit
import XCTest

/// Vidéos de test fabriquées en code (aucun média versionné) : fond texturé, visage optionnel qui se déplace
/// (découpé dans l'image d'exemple d'OpenCV téléchargée par la compilation), son sinusoïdal optionnel.
enum SyntheticVideo {

    /// Image du visage de test (Fixtures/face.jpg, téléchargée par la compilation, absente du dépôt), recadrée et
    /// agrandie à 220 x 220. Nil si l'image n'est pas disponible.
    static func faceImage() -> CGImage? {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "face", withExtension: "jpg", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "face", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage,
              image.width >= 296, image.height >= 170,
              let crop = image.cropping(to: CGRect(x: 186, y: 60, width: 110, height: 110)) else { return nil }
        let size = 220
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    struct Spec {
        var displayWidth = 640
        var displayHeight = 360
        var frames = 60
        var fps: Int32 = 30
        var face: CGImage?
        /// Quart de tour : image codée en portrait-paysage inversé, `preferredTransform` de 90°.
        var portrait = false
        var audio = true
    }

    /// Position du visage (repère affiché, pixels) sur l'image `i`.
    static func faceRect(_ spec: Spec, frame i: Int) -> CGRect {
        let x = 40.0 + Double(spec.displayWidth - 300) * Double(i) / Double(max(1, spec.frames - 1))
        return CGRect(x: x, y: 70, width: 220, height: 220)
    }

    static func make(_ spec: Spec, at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let codedW = spec.portrait ? spec.displayHeight : spec.displayWidth
        let codedH = spec.portrait ? spec.displayWidth : spec.displayHeight
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: codedW,
            AVVideoHeightKey: codedH,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        if spec.portrait {
            // Comme une vidéo filmée debout sur iPhone : l'image codée doit tourner d'un quart de tour horaire.
            input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(codedH), ty: 0)
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: codedW,
            kCVPixelBufferHeightKey as String: codedH,
        ])
        writer.add(input)

        var audioInput: AVAssetWriterInput?
        if spec.audio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ])
            a.expectsMediaDataInRealTime = false
            writer.add(a)
            audioInput = a
        }

        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "test", code: 1) }
        writer.startSession(atSourceTime: .zero)

        // Son et image entrelacés (un écrivain à deux entrées attend que les deux avancent ensemble).
        let totalAudio = Int(Double(spec.frames) / Double(spec.fps) * 44_100)
        var writtenAudio = 0
        func writeAudio(until frames: Int) throws {
            guard let audioInput else { return }
            while writtenAudio < min(frames, totalAudio) {
                try waitReady(audioInput, writer)
                let count = min(1_470, min(frames, totalAudio) - writtenAudio)
                let sample = try sineSamples(start: writtenAudio, count: count)
                guard audioInput.append(sample) else { throw writer.error ?? NSError(domain: "test", code: 5) }
                writtenAudio += count
            }
        }

        for i in 0..<spec.frames {
            try waitReady(input, writer)
            guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "test", code: 2) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let buffer = pb else { throw NSError(domain: "test", code: 3) }
            draw(spec, frame: i, into: buffer, codedWidth: codedW, codedHeight: codedH)
            let pts = CMTime(value: CMTimeValue(i), timescale: spec.fps)
            guard adaptor.append(buffer, withPresentationTime: pts) else { throw writer.error ?? NSError(domain: "test", code: 4) }
            try writeAudio(until: Int(Double(i + 1) / Double(spec.fps) * 44_100))
        }
        input.markAsFinished()
        try writeAudio(until: totalAudio)
        audioInput?.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "test", code: 6) }
    }

    /// Attend qu'une entrée accepte des données (10 s au plus).
    private static func waitReady(_ input: AVAssetWriterInput, _ writer: AVAssetWriter) throws {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error ?? NSError(domain: "test", code: 7) }
            Thread.sleep(forTimeInterval: 0.005)
            waited += 1
            if waited > 2_000 { throw NSError(domain: "test", code: 8, userInfo: [NSLocalizedDescriptionKey: "entrée bloquée"]) }
        }
    }

    /// Dessine l'image affichée (fond, visage), puis la place dans le tampon codé (tourné si portrait).
    private static func draw(_ spec: Spec, frame i: Int, into buffer: CVPixelBuffer, codedWidth: Int, codedHeight: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: codedWidth, height: codedHeight,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                  bitmapInfo: info) else { return }
        if spec.portrait {
            // Repère CoreGraphics (origine en bas à gauche) : on dessine l'image affichée tournée d'un quart de tour
            // antihoraire, pour qu'une rotation horaire la redresse.
            ctx.translateBy(x: CGFloat(codedWidth), y: 0)
            ctx.rotate(by: .pi / 2)
        }
        let w = CGFloat(spec.displayWidth)
        let h = CGFloat(spec.displayHeight)
        // Fond : dégradé et damier, pour que l'encodeur ait de la texture à coder.
        ctx.setFillColor(CGColor(srgbRed: 0.35, green: 0.45, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for y in stride(from: 0, to: Int(h), by: 20) {
            for x in stride(from: 0, to: Int(w), by: 20) where (x / 20 + y / 20 + i / 10) % 2 == 0 {
                ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.3, blue: 0.5, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 20, height: 20))
            }
        }
        if let face = spec.face {
            let r = faceRect(spec, frame: i)
            ctx.draw(face, in: CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height))
        }
    }

    /// Son mono 16 bits à 44,1 kHz (440 Hz).
    private static func sineSamples(start: Int, count: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                                    magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                    formatDescriptionOut: &format)
        guard status == noErr, let format else { throw NSError(domain: "test", code: Int(status)) }
        var samples = [Int16](repeating: 0, count: count)
        for k in 0..<count {
            samples[k] = Int16(8_000 * sin(2 * Double.pi * 440 * Double(start + k) / 44_100))
        }
        let bytes = count * 2
        var block: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
                                                    blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                    dataLength: bytes, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else { throw NSError(domain: "test", code: Int(status)) }
        samples.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44_100),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw NSError(domain: "test", code: Int(status)) }
        return sample
    }

    /// Image décodée (repère affiché, transformation de la piste appliquée) à l'instant `seconds`.
    static func frame(of url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// Moyenne et écart type de la luminance d'une zone (repère affiché, pixels).
    static func stats(_ image: CGImage, _ rect: CGRect) -> (mean: Double, std: Double) {
        let w = image.width
        let h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        var sum2 = 0.0
        var n = 0.0
        let r = rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                let p = (y * w + x) * 4
                let l = 0.299 * Double(data[p]) + 0.587 * Double(data[p + 1]) + 0.114 * Double(data[p + 2])
                sum += l
                sum2 += l * l
                n += 1
            }
        }
        guard n > 0 else { return (0, 0) }
        let mean = sum / n
        return (mean, max(0, sum2 / n - mean * mean).squareRoot())
    }
}

private final class BundleToken {}

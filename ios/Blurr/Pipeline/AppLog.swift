import Foundation
import os

/// Journal en mémoire, copiable depuis l'écran : sert à diagnostiquer un échec sur un appareil précis.
/// Ne contient ni image ni coordonnées GPS (portage de `AppLog.kt`, Android v0.2).
enum AppLog {
    private static let lock = NSLock()
    private static var buffer = ""
    private static let logger = Logger(subsystem: "io.github.momour.blurr", category: "blurr")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func i(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append("I", message)
    }

    static func e(_ message: String, _ error: Error? = nil) {
        let detail = error.map { "\(message) : \(describe($0))" } ?? message
        logger.error("\(detail, privacy: .public)")
        append("E", detail)
    }

    static func dump() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var text = ns.localizedDescription
        if ns.domain != "blurr" && ns.domain != "blurr.engine" {
            text += " (\(ns.domain) \(ns.code))"
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " ; cause : \(underlying.localizedDescription) (\(underlying.domain) \(underlying.code))"
        }
        return text
    }

    private static func append(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) \(level) \(message)\n"
        lock.lock()
        buffer += line
        if buffer.count > 80_000 { buffer.removeFirst(30_000) }
        lock.unlock()
    }
}

/// Erreur affichable telle quelle.
struct BlurrError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Annulation demandée par l'utilisateur.
struct CancelledError: Error {}

/// Drapeau d'annulation partagé entre l'interface et les passes de traitement.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func check() throws {
        if isCancelled { throw CancelledError() }
    }
}

import Foundation
import Observation
import GlasshouseCore

/// Holds imported App Privacy Report history, and persists it between launches.
///
/// The report keeps only a 7-day rolling window and switching it off in Settings
/// erases it, so the whole point of persisting is to build a history that
/// outlives the window.
@MainActor
@Observable
final class AttributionStore {
    private(set) var history = PrivacyReportHistory()
    private(set) var lastImport: PrivacyReportImport?
    private(set) var importError: String?

    private let decoder = PrivacyReportDecoder()

    init() {
        load()
    }

    // MARK: - Importing

    func importReport(from url: URL) {
        importError = nil

        // Files arriving from the share sheet or document picker are outside
        // the app's sandbox until access is explicitly claimed.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importError = "Couldn't read that file."
            return
        }

        let result = decoder.decode(text)
        lastImport = result

        guard result.schema != .unknown else {
            // Deliberately loud. This data cannot be re-fetched, so silently
            // importing nothing would be much worse than saying so.
            importError = """
                That file didn't match a format Glasshouse recognises. \
                Nothing was imported. \(result.failures.count) lines couldn't be read.
                """
            return
        }

        history.merge(result)
        save()

        // A recognised file can still be mostly undecodable — a schema that has
        // shifted under us, or a partially written export. Reporting only the
        // unrecognised-format case would let 500 failed lines out of 501 import
        // "successfully". The decoder records every failure; the UI has to show
        // them or the guarantee is only half kept.
        if !result.failures.isEmpty {
            let lines = result.failures.prefix(3).map { "line \($0.line): \($0.reason)" }
            importError = """
                Imported \(result.accesses.count + result.contacts.count) records, \
                but \(result.failures.count) line\(result.failures.count == 1 ? "" : "s") \
                couldn't be read — \(lines.joined(separator: "; "))
                """
        }
    }

    // MARK: - Persistence

    private var storeURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("attribution-history.json")
    }

    private func load() {
        guard let storeURL, let data = try? Data(contentsOf: storeURL) else { return }
        history = (try? JSONDecoder().decode(PrivacyReportHistory.self, from: data)) ?? PrivacyReportHistory()
    }

    private func save() {
        guard let storeURL, let data = try? JSONEncoder().encode(history) else { return }

        // This is other people's app activity, classified `intimate`. Written
        // with complete protection: unreadable while the device is locked, which
        // is acceptable because the app is only ever used in the foreground.
        try? data.write(to: storeURL, options: [.atomic, .completeFileProtection])
    }

    func deleteEverything() {
        history = PrivacyReportHistory()
        lastImport = nil
        importError = nil
        if let storeURL { try? FileManager.default.removeItem(at: storeURL) }
    }
}

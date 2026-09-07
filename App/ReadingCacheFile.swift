import Foundation
import GlasshouseCore

/// Persists the last set of readings so the app opens on something.
///
/// Written to Application Support with complete file protection — these are
/// real sensor values, including coordinates, and they get the same treatment
/// as everything else this app stores.
enum ReadingCacheFile {
    private static var url: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("last-readings.json")
    }

    static func load() -> ReadingCache? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReadingCache.self, from: data)
    }

    static func save(_ cache: ReadingCache) {
        guard let url, let data = try? JSONEncoder().encode(cache) else { return }
        // Best effort. A cache that fails to write costs a slower next launch
        // and nothing else, so it is not worth interrupting anyone over.
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

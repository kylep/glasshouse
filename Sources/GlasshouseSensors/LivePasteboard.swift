#if os(iOS)
import Foundation
import UIKit
import GlasshouseCore

/// Reads the *shape* of your clipboard without the "pasted from" banner.
///
/// This is the most instructive adapter in the app, and the one closest to the
/// project's whole thesis. Apple documents a specific set of pasteboard members
/// that do **not** notify the user, precisely because they do not read the
/// content: `numberOfItems`, `types`, `hasStrings`, `hasURLs`, `hasImages`,
/// `hasColors`, and the whole `detectPatterns(for:)` family.
///
/// So an app can learn that you have a URL on your clipboard — silently, with no
/// permission, no prompt, and no banner. Contrast this with
/// `LivePasteboardContentSource` below, which reads the same clipboard and does
/// trigger the banner. Showing both side by side is the point.
public struct LivePasteboardShapeSource: SensorSource {
    public let id: SensorID = "pasteboard.shape"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        // Every member touched here is on Apple's documented no-notification
        // list. Do not add `.string`, `.url`, or `.items` — those notify, and
        // conflating them would defeat the comparison this source exists to make.
        let board = await MainActor.run { UIPasteboard.general }

        var fields: [SensorField] = await MainActor.run {
            [
                SensorField("Items", .integer(board.numberOfItems)),
                SensorField("Contains text", .boolean(board.hasStrings)),
                SensorField("Contains a URL", .boolean(board.hasURLs)),
                SensorField("Contains an image", .boolean(board.hasImages)),
                SensorField("Contains a color", .boolean(board.hasColors)),
                SensorField("Types", .text(board.types.isEmpty ? "none" : board.types.joined(separator: ", "))),
            ]
        }

        // Pattern detection also avoids the banner: it reports what *kind* of
        // thing is on the clipboard without ever surfacing the value.
        let patterns = await Self.detectPatterns(on: board)
        fields.append(SensorField("Detected patterns",
                                  .text(patterns.isEmpty ? "none" : patterns.joined(separator: ", "))))

        fields.append(SensorField("You were notified", .boolean(false)))

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }

    /// Bridges the completion-handler API, which has no async variant.
    ///
    /// Returns human-readable names rather than raw pattern values, because
    /// `DetectionPattern` has no useful public description.
    private static func detectPatterns(on board: UIPasteboard) async -> [String] {
        let known: [(UIPasteboard.DetectionPattern, String)] = [
            (.probableWebURL, "a web link"),
            (.probableWebSearch, "a search query"),
            (.number, "a number"),
        ]

        let found: Set<UIPasteboard.DetectionPattern> = await withCheckedContinuation { continuation in
            board.detectPatterns(for: Set(known.map(\.0))) { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }

        return known.filter { found.contains($0.0) }.map(\.1)
    }
}

/// Reads the actual clipboard contents — and this one does notify you.
///
/// Deliberately never read automatically. The app must only invoke this when
/// the user explicitly asks to see the contrast, because triggering the system
/// banner without being asked would be exactly the behaviour this project
/// exists to criticise.
public struct LivePasteboardContentSource: SensorSource {
    public let id: SensorID = "pasteboard.contents"

    /// Whether the user has explicitly asked for the notifying read.
    private let userRequested: Bool

    public init(userRequested: Bool = false) {
        self.userRequested = userRequested
    }

    public func availability() async -> SensorAvailability {
        // Not "unavailable" in a technical sense — this is a deliberate refusal
        // to read personal data the user has not asked us to touch.
        userRequested ? .ready : .needsPermission
    }

    public func read() async -> SensorSample? {
        guard userRequested else { return nil }

        return await MainActor.run {
            let board = UIPasteboard.general
            var fields: [SensorField] = []

            if let text = board.string {
                let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text
                fields.append(SensorField("Text", .text(preview)))
                fields.append(SensorField("Length", .integer(text.count, unit: "characters")))
            }
            if let url = board.url {
                fields.append(SensorField("URL", .text(url.absoluteString)))
            }
            guard !fields.isEmpty else { return nil }

            fields.append(SensorField("You were notified", .boolean(true)))
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
        }
    }
}
#endif

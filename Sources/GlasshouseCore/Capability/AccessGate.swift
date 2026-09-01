/// What iOS does, if anything, before an app reads this.
///
/// Replaces an earlier `promptsUser` boolean, which collapsed four genuinely
/// different situations into two values and misdescribed at least one of them:
///
/// - The vendor identifier is ungated because iOS does not gate it.
/// - The ambient light sensor is ungated because *no* app may read it, so there
///   is nothing to ask for. Opposite meaning, identical label.
/// - Reading the clipboard's contents raises no permission dialog, so the flag
///   said "no prompt" — and then a banner appears anyway. The app promised
///   nothing would happen and something visibly did, which undercut the exact
///   comparison that pair of readings exists to make.
public enum AccessGate: String, Codable, Sendable, CaseIterable {
    /// No dialog, no entry under Settings → Privacy, no way to revoke it. Any
    /// app can read this the moment it launches and you would never know.
    ///
    /// This is the group the app opens on. It is not the alarming-sounding
    /// sensors that are interesting; it is the ones nobody had to ask for.
    case neverAsks = "never_asks"

    /// A system permission dialog, once, which you can grant or decline and
    /// later change in Settings. The familiar case.
    case asksOnce = "asks_once"

    /// No dialog, but iOS tells you after the fact — the "pasted from" banner
    /// being the only example on the device. Not consent: notification.
    case tellsYouAfter = "tells_you_after"

    /// No third-party app may read this at all, so no permission exists to
    /// grant. Recorded rather than hidden: a sensor your phone has that nothing
    /// is allowed to read is as instructive as any reading.
    case noAccessAtAll = "no_access_at_all"

    /// Short label for a list row. Deliberately plain language — this is the
    /// single most important thing the interface says.
    public var shortLabel: String {
        switch self {
        case .neverAsks: "never asks"
        case .asksOnce: "asks once"
        case .tellsYouAfter: "tells you after"
        case .noAccessAtAll: "off limits"
        }
    }

    /// Fuller explanation, for the detail screen.
    public var explanation: String {
        switch self {
        case .neverAsks:
            "iOS never asks. There is no dialog, nothing in Settings, and no way to turn it off."
        case .asksOnce:
            "iOS asks once. You can decline, and change your mind later in Settings."
        case .tellsYouAfter:
            "iOS doesn't ask, but it tells you afterwards — you'll see a banner."
        case .noAccessAtAll:
            "No app is allowed to read this, so there is nothing to permit."
        }
    }

    /// Whether a system permission dialog is involved.
    public var showsSystemDialog: Bool { self == .asksOnce }

    /// Whether this can be read with no consent step whatsoever. Note that
    /// `tellsYouAfter` is deliberately excluded: a banner is not consent, but it
    /// is not nothing either, and lumping it in here is what made the old
    /// boolean misleading.
    public var isCompletelyUngated: Bool { self == .neverAsks }
}

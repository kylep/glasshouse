/// How, and whether, one signal's readings are recorded.
///
/// Every signal starts off. Nothing is logged until someone turns it on, which
/// is the only defensible default for an app that reads health, location and
/// contacts — and the one it argues for elsewhere.
public struct LoggingPolicy: Sendable, Hashable, Codable {
    public var isEnabled: Bool
    public var capture: CaptureMode
    public var retention: Retention

    /// Whether iOS may be asked to wake the app and take a reading.
    ///
    /// Deliberately separate from `capture`, because it is a request rather
    /// than a schedule — see `CaptureMode.interval` for why.
    public var allowBackground: Bool

    public init(
        isEnabled: Bool = false,
        capture: CaptureMode = .onDemand,
        retention: Retention = .days(7),
        allowBackground: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.capture = capture
        self.retention = retention
        self.allowBackground = allowBackground
    }

    /// The default for every signal: off.
    public static let off = LoggingPolicy()
}

/// When a reading is taken.
public enum CaptureMode: Sendable, Hashable, Codable {
    /// Only when someone presses the button. No timers, no background work.
    case onDemand

    /// Every `seconds`, while the app is in the foreground.
    ///
    /// Foreground is not a caveat that can be engineered away. iOS grants no
    /// reliable periodic background execution: `BGAppRefreshTask` is
    /// opportunistic and the system may skip it for days, and the only
    /// dependable background wake is location. A UI promising "every 5 minutes"
    /// with the screen off would be lying, so the interval is documented as
    /// foreground-only and background is a separate, honestly-labelled request.
    case interval(seconds: Int)

    public var isPolling: Bool {
        if case .interval = self { return true }
        return false
    }

    public var seconds: Int? {
        if case let .interval(seconds) = self { return seconds }
        return nil
    }

    /// The choices offered in the UI. Nothing shorter than 10 seconds: below
    /// that the readings cost more battery than they are worth, and several
    /// sensors take seconds to answer anyway.
    public static let choices: [(label: String, seconds: Int)] = [
        ("Every 10 seconds", 10),
        ("Every 30 seconds", 30),
        ("Every minute", 60),
        ("Every 5 minutes", 300),
        ("Every 15 minutes", 900),
        ("Every hour", 3600),
    ]
}

/// How long readings are kept.
public enum Retention: Sendable, Hashable, Codable {
    case hours(Int)
    case days(Int)

    /// Kept until deleted by hand.
    ///
    /// Offered because it was asked for, but it is the one choice that turns a
    /// log into an archive. The UI says so rather than presenting it as
    /// equivalent to the others.
    case forever

    public var seconds: Double? {
        switch self {
        case let .hours(count): Double(count) * 3600
        case let .days(count): Double(count) * 86_400
        case .forever: nil
        }
    }

    public var label: String {
        switch self {
        case let .hours(count): count == 1 ? "1 hour" : "\(count) hours"
        case let .days(count): count == 1 ? "1 day" : "\(count) days"
        case .forever: "Indefinitely"
        }
    }

    public static let choices: [Retention] = [
        .hours(1), .hours(6), .days(1), .days(7), .days(30), .forever,
    ]

    /// The cutoff before which readings should be discarded, given now.
    public func cutoff(now: Double) -> Double? {
        seconds.map { now - $0 }
    }
}

/// The settings a signal gets when switched on in bulk.
///
/// Five minutes and a week are chosen to be defensible without being asked
/// about: frequent enough that a chart has shape within an hour, short enough
/// that a forgotten signal is not still accumulating months later.
public enum LoggingDefaults {
    public static let interval = 300
    public static let retention = Retention.days(7)

    public static func policy(polling: Bool = true) -> LoggingPolicy {
        LoggingPolicy(
            isEnabled: true,
            capture: polling ? .interval(seconds: interval) : .onDemand,
            retention: retention
        )
    }
}

/// Every signal's policy, with the defaults applied.
public struct LoggingPolicies: Sendable, Hashable, Codable {
    private var stored: [String: LoggingPolicy]

    public init(_ stored: [SensorID: LoggingPolicy] = [:]) {
        self.stored = Dictionary(uniqueKeysWithValues: stored.map { ($0.key.rawValue, $0.value) })
    }

    public subscript(id: SensorID) -> LoggingPolicy {
        get { stored[id.rawValue] ?? .off }
        set { stored[id.rawValue] = newValue }
    }

    /// Signals currently logging anything at all.
    public var enabled: [SensorID] {
        stored.filter(\.value.isEnabled).keys.map(SensorID.init(rawValue:)).sorted()
    }

    /// Signals on a timer, and how often.
    public var polling: [(id: SensorID, seconds: Int)] {
        stored
            .compactMap { key, policy in
                guard policy.isEnabled, let seconds = policy.capture.seconds else { return nil }
                return (SensorID(rawValue: key), seconds)
            }
            .sorted { $0.0 < $1.0 }
    }

    /// Whether anything at all has been switched on.
    public var isAnythingEnabled: Bool { stored.values.contains { $0.isEnabled } }

    /// Switches a set of signals on with the shared defaults.
    ///
    /// Existing settings are left alone: someone who set the barometer to every
    /// 30 seconds and then taps "record the charted signals" should not have
    /// that quietly reset to five minutes.
    public mutating func enable(_ ids: [SensorID]) {
        for id in ids where !self[id].isEnabled {
            self[id] = LoggingDefaults.policy()
        }
    }

    /// Switches everything off, keeping each signal's other settings.
    ///
    /// Deliberately preserves interval and retention rather than clearing them,
    /// so switching back on restores what was configured before.
    public mutating func disableAll() {
        for id in enabled {
            var policy = self[id]
            policy.isEnabled = false
            self[id] = policy
        }
    }
}

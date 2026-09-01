/// Where this build is actually running.
///
/// Every live sensor path is gated on this. The simulator can exercise roughly
/// two of the app's data sources for real, so the replay implementations are
/// the primary development surface rather than a testing convenience.
public enum RuntimeEnvironment: String, Sendable, Hashable, Codable, CaseIterable {
    /// A physical iPhone or iPad. The only place most sensors produce data.
    case device

    /// The iOS Simulator. Links every framework, signs nothing, and reports
    /// most hardware as unavailable.
    case simulator

    /// macOS, including `swift test`. Where the unit suite runs.
    case host

    /// The environment this binary was compiled for.
    public static let current: RuntimeEnvironment = {
        #if os(iOS)
            #if targetEnvironment(simulator)
            return .simulator
            #else
            return .device
            #endif
        #else
        return .host
        #endif
    }()

    /// Whether live sensor adapters can produce real readings here.
    ///
    /// False everywhere except a physical device, which is the entire reason
    /// the sensor protocol has fake and replay implementations.
    public var supportsLiveSensors: Bool {
        self == .device
    }

    /// Whether code signing and entitlements are enforced here.
    ///
    /// False in the simulator, which is why a build can appear to work while
    /// carrying capabilities the signing account could never obtain.
    public var enforcesEntitlements: Bool {
        self == .device
    }
}

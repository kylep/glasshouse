import GlasshouseCore

/// Live adapters over Apple's sensor frameworks.
///
/// Everything in this target is iOS-only and deliberately thin. It cannot be
/// unit tested on macOS, so it must contain no logic worth testing: parse,
/// transform, and decide in `GlasshouseCore`, and let this target do nothing
/// but hand raw framework output across the protocol boundary.
///
/// Each adapter is guarded:
///
/// ```swift
/// #if canImport(CoreMotion)
/// import CoreMotion
/// // ... adapter ...
/// #endif
/// ```
public enum GlasshouseSensors {
    /// Whether this build can install live adapters at all.
    ///
    /// On the simulator and on macOS this is false, and the registry serves
    /// replay implementations instead.
    public static var canInstallLiveAdapters: Bool {
        RuntimeEnvironment.current.supportsLiveSensors
    }
}

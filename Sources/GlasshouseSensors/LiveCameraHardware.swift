#if os(iOS)
import Foundation
import AVFoundation
import GlasshouseCore

/// What an app can learn about your cameras without asking to use them.
///
/// The permission gates *capturing frames*. Enumerating the hardware —
/// how many lenses, their focal lengths, apertures, ISO range, maximum photo
/// resolution — needs no authorization at all, and `AVCaptureDevice` will list
/// every one of them to any app that asks.
///
/// That gap is the reading. The precise combination of lens configurations is
/// also a near-exact device-model fingerprint, obtained without a dialog.
public struct LiveCameraHardwareSource: SensorSource {
    public let id: SensorID = "av.camera_hardware"

    public init() {}

    /// Deliberately does not consult `AVCaptureDevice.authorizationStatus`.
    /// Everything reported below is readable regardless of it, and gating on
    /// permission would misrepresent what the sandbox actually protects.
    public func availability() async -> SensorAvailability {
        Self.discovered().isEmpty
            ? .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
            : .ready
    }

    public func read() async -> SensorSample? {
        let devices = Self.discovered()
        guard !devices.isEmpty else { return nil }

        var fields: [SensorField] = [
            SensorField("Cameras", .integer(devices.count)),
            SensorField("Permission asked", .boolean(false)),
        ]

        let back = devices.filter { $0.position == .back }
        let front = devices.filter { $0.position == .front }
        fields.append(SensorField("Back", .integer(back.count)))
        fields.append(SensorField("Front", .integer(front.count)))

        // Focal lengths in 35mm-equivalent terms, which is the number a person
        // recognises. `nominalFocalLengthIn35mmFilm` is new in iOS 26 and
        // returns 0 for virtual (multi-lens) devices, so those are skipped.
        // The deployment target is iOS 18, hence the availability check rather
        // than assuming the newest SDK is the oldest supported OS.
        if #available(iOS 26.0, *) {
            let focalLengths = devices
                .map(\.nominalFocalLengthIn35mmFilm)
                .filter { $0 > 0 }
                .sorted()
            if !focalLengths.isEmpty {
                fields.append(SensorField(
                    "Focal lengths",
                    .text(focalLengths.map { "\($0)mm" }.joined(separator: ", "))
                ))
            }
        }

        let apertures = Set(devices.map { String(format: "f/%.1f", $0.lensAperture) }).sorted()
        if !apertures.isEmpty {
            fields.append(SensorField("Apertures", .text(apertures.joined(separator: ", "))))
        }

        if let best = devices.compactMap({ device -> (Int32, Int32)? in
            device.formats
                .map(\.supportedMaxPhotoDimensions)
                .flatMap { $0 }
                .map { ($0.width, $0.height) }
                .max { $0.0 * $0.1 < $1.0 * $1.1 }
        }).max(by: { $0.0 * $0.1 < $1.0 * $1.1 }) {
            let megapixels = Double(best.0) * Double(best.1) / 1_000_000
            fields.append(SensorField("Largest photo", .number(megapixels.rounded(), unit: "MP")))
        }

        if let sensitivity = devices.compactMap({ $0.activeFormat.maxISO }).max() {
            fields.append(SensorField("Max ISO", .integer(Int(sensitivity))))
        }

        let types = devices.map { Self.friendly($0.deviceType) }
        fields.append(SensorField("Lens types", .text(Set(types).sorted().joined(separator: ", "))))

        // Worth naming rather than leaving as a lens type: TrueDepth means an
        // app with camera permission can track fifty facial blend shapes, and
        // LiDAR means it can mesh the room you are standing in. Both facts are
        // readable here with no permission at all.
        let hasTrueDepth = devices.contains { $0.deviceType == .builtInTrueDepthCamera }
        let hasLiDAR = devices.contains { $0.deviceType == .builtInLiDARDepthCamera }
        fields.append(SensorField("Face-tracking hardware", .boolean(hasTrueDepth)))
        fields.append(SensorField("Room-scanning hardware", .boolean(hasLiDAR)))

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }

    /// Every camera the device exposes.
    ///
    /// Measured trap: this returns an EMPTY ARRAY rather than nil when there
    /// are no cameras, which is the Simulator's behaviour — so `devices.first!`
    /// would crash rather than reporting their absence.
    static func discovered() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInTrueDepthCamera,
                .builtInLiDARDepthCamera,
                .external,
            ],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func friendly(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInWideAngleCamera: "wide"
        case .builtInUltraWideCamera: "ultra-wide"
        case .builtInTelephotoCamera: "telephoto"
        case .builtInTrueDepthCamera: "TrueDepth"
        case .builtInLiDARDepthCamera: "LiDAR"
        case .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera: "combined"
        case .external: "external"
        default: type.rawValue
        }
    }
}

#endif

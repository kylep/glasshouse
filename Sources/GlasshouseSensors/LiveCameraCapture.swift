#if os(iOS)
import Foundation
import AVFoundation
import CoreImage
import GlasshouseCore

/// What the camera can actually see, as opposed to what it says about itself.
///
/// `av.camera_hardware` reports the lens specification and needs no permission.
/// This is the other half: opening a session, taking one frame, and deriving a
/// single number from it.
///
/// It reports **average brightness only** — never an image, never a thumbnail,
/// nothing stored. That is deliberate. Proving an app can see through your
/// camera does not require showing you the picture, and an app arguing about
/// surveillance should not casually display a frame of your room to make its
/// point. The frame exists for microseconds and is reduced to one Double.
///
/// Runs entirely off the MainActor with its own session, which is the third
/// time that has been necessary — Core Motion and audio both terminated the
/// process when driven from the main actor, and capture owns real-time threads
/// for the same reasons.
public struct LiveCameraCaptureSource: SensorSource {
    public let id: SensorID = "av.camera"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard !LiveCameraHardwareSource.discovered().isEmpty else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .ready
        @unknown default: .needsPermission
        }
    }

    public func requestAccess() async -> SensorAvailability {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return nil }
        guard let frame = await FrameGrabber.captureOne() else {
            // Authorized but no frame — the camera may be held by another app.
            // A fact about the moment, not a defect.
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Frame", .text("none — the camera may be in use elsewhere")),
            ])
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Brightness", .number((frame.brightness * 100).rounded(), unit: "%")),
            SensorField("Scene", .text(Self.describe(frame.brightness))),
            SensorField("Resolution", .text("\(frame.width) × \(frame.height)")),
            SensorField("Camera", .text(frame.position)),
            SensorField("Image kept", .boolean(false)),
        ])
    }

    static func describe(_ brightness: Double) -> String {
        switch brightness {
        case ..<0.06: "covered or dark"
        case ..<0.20: "dim"
        case ..<0.55: "indoor light"
        default: "bright"
        }
    }
}

/// Takes exactly one frame and throws the image away.
private enum FrameGrabber {
    struct Frame: Sendable {
        let brightness: Double
        let width: Int
        let height: Int
        let position: String
    }

    static func captureOne(timeout: Double = 4) async -> Frame? {
        await Task.detached(priority: .userInitiated) { () -> Frame? in
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ) ?? AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device)
            else { return nil }

            let session = AVCaptureSession()
            session.sessionPreset = .low          // enough for a brightness average
            guard session.canAddInput(input) else { return nil }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            let collector = FrameCollector()
            let queue = DispatchQueue(label: "fit.glasshouse.frame")
            output.setSampleBufferDelegate(collector, queue: queue)
            guard session.canAddOutput(output) else { return nil }
            session.addOutput(output)

            session.startRunning()
            defer { session.stopRunning() }

            // Poll rather than block: the first frames after start are often
            // black while exposure settles, so this waits for a real one.
            for _ in 0..<Int(timeout * 20) {
                if let brightness = collector.brightness {
                    return Frame(
                        brightness: brightness,
                        width: collector.width,
                        height: collector.height,
                        position: device.position == .front ? "front" : "back"
                    )
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return nil
        }.value
    }

    /// Reduces a frame to one number on the capture queue, so no image buffer
    /// ever leaves this file.
    private final class FrameCollector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Double?
        private(set) var width = 0
        private(set) var height = 0
        private var seen = 0

        var brightness: Double? {
            lock.lock(); defer { lock.unlock() }
            return stored
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Skip the first few frames: auto-exposure has not settled and they
            // read as black, which would report "covered" in a lit room.
            lock.lock()
            seen += 1
            let settled = seen > 5
            lock.unlock()
            guard settled else { return }

            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let pixels = base.assumingMemoryBound(to: UInt8.self)

            // Sample a sparse grid rather than every pixel — this is an average,
            // and touching 300k bytes on the capture queue is needless work.
            var total = 0
            var count = 0
            for y in stride(from: 0, to: h, by: 8) {
                for x in stride(from: 0, to: w, by: 8) {
                    total += Int(pixels[y * bytesPerRow + x])
                    count += 1
                }
            }
            guard count > 0 else { return }

            lock.lock()
            stored = Double(total) / Double(count) / 255.0
            width = w
            height = h
            lock.unlock()
        }
    }
}
#endif

#if os(iOS)
import Foundation
import AVFoundation
import Speech
import GlasshouseCore

/// The ambient sound level, measured without recording anything.
///
/// Worth being precise about what this does and does not do. It opens the
/// microphone and reads the *amplitude* of what arrives, then throws the audio
/// away — no buffer is retained, nothing is written to disk, and nothing is
/// transcribed. But iOS cannot tell the difference, and neither can you: the
/// orange dot in the status bar looks identical whether an app is measuring
/// loudness or recording every word.
///
/// That indistinguishability is the reading.
@MainActor
final class MicrophoneMeter {
    static let shared = MicrophoneMeter()

    private init() {}

    /// Kill switch while the post-grant crash is diagnosed.
    ///
    /// Granting the microphone made the app terminate on every launch, because
    /// availability then reports .ready and read() runs the meter on each
    /// refresh. One sensor must not take down an app built to show forty.
    nonisolated static let meteringEnabled = true

    var permission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Listens for a moment and returns peak and average amplitude, 0...1.
    ///
    /// Deliberately `nonisolated` on a detached task with its own engine, which
    /// is the same shape the pedometer needed. Driving Core Motion from a
    /// `@MainActor` context terminated the process there; audio capture is the
    /// other framework in this app that owns real-time threads, and it crashed
    /// the same way once the permission was granted and this path first ran.
    ///
    /// The engine is local and held alive for the duration, then torn down —
    /// leaving it running would keep the microphone open and the orange
    /// indicator lit indefinitely.
    nonisolated func measure(seconds: Double = 1.0) async -> (peak: Float, average: Float)? {
        guard await permission == .granted, Self.meteringEnabled else { return nil }

        return await Task.detached(priority: .userInitiated) { () -> (peak: Float, average: Float)? in
            let engine = AVAudioEngine()
            defer { engine.stop() }

            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.record, mode: .measurement, options: [])
            try? session.setActive(true)
            defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { return nil }

            let samples = Meter()
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                var peak: Float = 0
                var sum: Float = 0
                let count = Int(buffer.frameLength)
                for i in 0..<count {
                    let magnitude = abs(channel[i])
                    peak = max(peak, magnitude)
                    sum += magnitude
                }
                samples.record(peak: peak, mean: count > 0 ? sum / Float(count) : 0)
            }

            engine.prepare()
            do {
                try engine.start()
            } catch {
                // Reported as no reading rather than crashing. A microphone
                // that will not start is a fact about the device, not a fault.
                input.removeTap(onBus: 0)
                return nil
            }

            try? await Task.sleep(for: .seconds(seconds))
            input.removeTap(onBus: 0)
            return samples.result
        }.value
    }

    /// Accumulates tap callbacks, which arrive on an audio thread.
    private final class Meter: @unchecked Sendable {
        private let lock = NSLock()
        private var peak: Float = 0
        private var meanTotal: Float = 0
        private var buffers = 0

        func record(peak newPeak: Float, mean: Float) {
            lock.lock()
            defer { lock.unlock() }
            peak = max(peak, newPeak)
            meanTotal += mean
            buffers += 1
        }

        var result: (peak: Float, average: Float)? {
            lock.lock()
            defer { lock.unlock() }
            guard buffers > 0 else { return nil }
            return (peak, meanTotal / Float(buffers))
        }
    }
}

public struct LiveMicrophoneSource: SensorSource {
    public let id: SensorID = "av.microphone"

    public init() {}

    public func availability() async -> SensorAvailability {
        // Reported honestly rather than as .ready — claiming readiness and
        // returning nothing is the silent failure this project forbids.
        guard MicrophoneMeter.meteringEnabled else {
            return .unavailable(reason: .knownDefect)
        }
        return switch await MicrophoneMeter.shared.permission {
        case .undetermined: .needsPermission
        case .denied: .denied
        case .granted: .ready
        @unknown default: .needsPermission
        }
    }

    public func requestAccess() async -> SensorAvailability {
        _ = await MicrophoneMeter.shared.request()
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard let level = await MicrophoneMeter.shared.measure() else { return nil }

        // Decibels relative to full scale: 0 is the loudest the hardware can
        // represent, and quiet rooms sit around -50.
        let decibels = level.peak > 0 ? 20 * log10(Double(level.peak)) : -160

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Peak level", .number(decibels.rounded(), unit: "dBFS")),
            SensorField("Loudness", .text(Self.describe(decibels))),
            SensorField("Average amplitude", .number(Double(level.average), unit: "")),
            SensorField("Audio kept", .boolean(false)),
            SensorField("Looks identical to recording", .boolean(true)),
        ])
    }

    static func describe(_ decibels: Double) -> String {
        switch decibels {
        case ..<(-55): "silent"
        case ..<(-40): "quiet room"
        case ..<(-25): "conversation nearby"
        case ..<(-12): "loud"
        default: "very loud"
        }
    }
}

/// Whether speech can be turned into text, and where that happens.
///
/// The reading is less the capability than its shape: on-device recognition
/// keeps audio local, while server-based recognition sends it to Apple. An app
/// chooses which, and the permission dialog does not distinguish them.
public struct LiveSpeechRecognitionSource: SensorSource {
    public let id: SensorID = "speech.recognition"

    public init() {}

    public func availability() async -> SensorAvailability {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .ready
        @unknown default: .needsPermission
        }
    }

    public func requestAccess() async -> SensorAvailability {
        // SingleResume carries an optional payload, so this waits on a Bool
        // rather than Void — the value is ignored; the point is resuming once.
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let once = SingleResume(continuation)
            SFSpeechRecognizer.requestAuthorization { _ in once.resume(true) }
        }
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return nil }
        guard let recognizer = SFSpeechRecognizer() else {
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Recogniser", .text("unavailable for this locale")),
            ])
        }

        let locales = SFSpeechRecognizer.supportedLocales().count

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Available", .boolean(recognizer.isAvailable)),
            SensorField("Locale", .text(recognizer.locale.identifier)),
            SensorField("Languages supported", .integer(locales)),
            SensorField("Can work on-device", .boolean(recognizer.supportsOnDeviceRecognition)),
            // The distinction the permission dialog does not draw.
            SensorField("Otherwise audio goes to Apple", .boolean(!recognizer.supportsOnDeviceRecognition)),
        ])
    }
}
#endif

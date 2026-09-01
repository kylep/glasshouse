extension CapabilityLedger {
    /// Camera, microphone, photo library, on-device analysis, and speech.
    ///
    /// The photo library is the most valuable source the Simulator can offer:
    /// six seeded assets carrying real GPS coordinates and full EXIF, present
    /// even on a never-booted device. That makes the "map of everywhere your
    /// camera roll has been" demo fully buildable without hardware.
    static let media: [Capability] = [
        Capability(
            id: "photos.library",
            displayName: "Photo library",
            framework: "Photos",
            reveals: "Every photo and video you have taken, when each was taken, whether you favourited it, and which are of the same person.",
            plistKeys: ["NSPhotoLibraryUsageDescription"],
            simulator: .worksFully,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/photokit/phauthorizationstatus + measured: 6 seeded assets present",
            verified: "2026-08-30",
            notes: "The key is NSPhotoLibraryUsageDescription for read/write; NSPhotoLibraryAddUsageDescription (not ...AddOnly...) is the add-only variant. `.limited` is a distinct third authorization state that must be handled separately from denied and authorized. Measured trap: `simctl privacy grant photos` writes TCC but PhotoKit still reads .notDetermined — drive the real prompt."
        ),
        Capability(
            id: "photos.asset_location",
            displayName: "Photo locations",
            framework: "Photos",
            reveals: "Where each photo was taken. A camera roll is a location history that most people forget they are carrying — years of coordinates, timestamped, including home and workplace.",
            plistKeys: ["NSPhotoLibraryUsageDescription"],
            simulator: .worksFully,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/photos/phasset/location + measured: seeded assets carry GPS",
            verified: "2026-08-30",
            notes: "PHAsset.location needs no location permission of its own — it comes with library access. The seeded simulator assets carry real coordinates (Iceland, San Francisco, Marin) plus full EXIF including camera make and model, and one carries a -180,-180 sentinel for the no-GPS case. This is the single most visceral demo in the app."
        ),
        Capability(
            id: "av.camera",
            displayName: "Camera",
            framework: "AVFoundation",
            reveals: "Live video from front and back cameras, plus depth data, and hardware detail like lens aperture, focal length, and ISO.",
            plistKeys: ["NSCameraUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription + measured: 0 video devices discovered",
            verified: "2026-08-30",
            notes: "Discovery returns an EMPTY ARRAY, not nil — `devices.first!` crashes rather than reporting no camera. The audio device that does appear is a stub with no formats. `simctl privacy camera` works despite being absent from the help text."
        ),
        Capability(
            id: "av.microphone",
            displayName: "Microphone",
            framework: "AVFoundation",
            reveals: "Live audio, and the ambient sound level even when nothing is being recorded or transcribed.",
            plistKeys: ["NSMicrophoneUsageDescription"],
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/avfaudio/avaudioapplication + measured: AVAudioEngine captured real host audio",
            verified: "2026-08-30",
            notes: "Genuinely works in the Simulator, routed from the Mac's microphone — measured non-zero amplitude. Use AVAudioApplication.requestRecordPermission (iOS 17+); the AVAudioSession method is deprecated."
        ),
        Capability(
            id: "av.audio_route",
            displayName: "Audio route",
            framework: "AVFoundation",
            reveals: "What you are listening through — speaker, wired headphones, or a named Bluetooth device. iOS never asks.",
            simulator: .worksWithCaveats,
            sensitivity: .identifying,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/avfaudio/avaudiosession + measured: MicrophoneBuiltIn / Speaker, 48kHz",
            verified: "2026-08-30",
            notes: "No usage key and no prompt. The Simulator reports a simulated route rather than the Mac's real headphone or Bluetooth state, so route *changes* are not meaningfully testable here."
        ),
        Capability(
            id: "vision.text",
            displayName: "Text in images",
            framework: "Vision",
            reveals: "Every word visible in your photos — signs, documents, whiteboards, screenshots of private messages — turned into searchable text.",
            simulator: .worksFully,
            sensitivity: .personal,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/vision + measured: RecognizeTextRequest succeeded in simulator",
            verified: "2026-08-30",
            notes: "Vision needs no permission of its own; getting the images does. Use the iOS 18+ Swift API (RecognizeTextRequest) rather than the legacy VNRequest form. This is the one Vision path that works in a Simulator."
        ),
        Capability(
            id: "vision.faces",
            displayName: "Faces in images",
            framework: "Vision",
            reveals: "How many people are in each photo, where their faces are, and facial landmarks — computed entirely on device, with no permission beyond the photos themselves.",
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/vision + measured: 'Could not create inference context'",
            verified: "2026-08-30",
            notes: "Every neural-engine-backed Vision request fails in the Simulator — faces, barcodes, saliency, body pose — while text recognition works. Observed on one Apple Silicon Mac; worth confirming elsewhere."
        ),
        Capability(
            id: "speech.recognition",
            displayName: "Speech recognition",
            framework: "Speech",
            reveals: "Spoken words turned into text. Historically this meant sending audio to Apple's servers; the on-device path avoids that but needs downloaded models.",
            plistKeys: ["NSSpeechRecognitionUsageDescription"],
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/speech/sfspeechrecognizer + measured: isAvailable == true, supportsOnDeviceRecognition inconsistent",
            verified: "2026-08-30",
            notes: "SFSpeechRecognizer is not deprecated. The iOS 26 replacement, SpeechAnalyzer/SpeechTranscriber, reports isAvailable == false with zero supported locales in a Simulator — model assets are not provisioned. supportsOnDeviceRecognition varied between simulators, so treat it as non-deterministic here."
        ),
    ]
}

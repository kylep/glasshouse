extension CapabilityLedger {
    /// Radios, networking, and spatial sensing.
    ///
    /// Almost nothing here can be exercised in a Simulator — there is no
    /// Bluetooth stack, no baseband, no UWB, and no camera for ARKit. Several
    /// entries are also the clearest examples of the sandbox tightening over
    /// time rather than loosening.
    static let connectivity: [Capability] = [
        Capability(
            id: "bluetooth.scan",
            displayName: "Bluetooth devices nearby",
            framework: "CoreBluetooth",
            reveals: "Every Bluetooth device around you — headphones, watches, cars, fitness trackers, other people's phones — with signal strength that estimates distance. A rolling census of who and what is near you.",
            plistKeys: ["NSBluetoothAlwaysUsageDescription"],
            simulator: .unavailable,
            sensitivity: .personal,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/corebluetooth/cbcentralmanager + measured: CBCentralManager.state == .unsupported",
            verified: "2026-08-30",
            notes: "Needs no entitlement, which makes it the highest-value sensor available to a free account — and it is completely unavailable in a Simulator (no bluetoothd in the runtime). Measured trap: CBManager.authorization reports .allowedAlways while state is .unsupported, so ALWAYS gate on state. MAC addresses are never exposed; peers get rotating per-app UUIDs."
        ),
        Capability(
            id: "network.path",
            displayName: "Network connection",
            framework: "Network",
            reveals: "Whether you are on Wi-Fi or cellular, whether the connection is metered, and whether you are in Low Data Mode. No permission, no prompt.",
            simulator: .worksWithCaveats,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/network/nwpathmonitor",
            verified: "2026-08-30",
            notes: "Reports the host Mac's network in a Simulator, so cellular is never observed. Cheap, silent, and a decent proxy for whether someone is at home or out."
        ),
        Capability(
            id: "network.local",
            displayName: "Devices on your network",
            framework: "Network",
            reveals: "Other machines on your home or office network — printers, TVs, speakers, laptops — which fingerprints the network itself and therefore the place.",
            plistKeys: ["NSLocalNetworkUsageDescription"],
            simulator: .unavailable,
            sensitivity: .personal,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy",
            verified: "2026-08-30",
            notes: "TN3179 states plainly that the Simulator does not support local network privacy — it uses the Mac's stack with no prompt and no permission model. Browsing arbitrary Bonjour service types additionally needs the multicast entitlement, which is paid plus Apple approval. Introduced iOS 14; contrary to a common belief, iOS 26 changed nothing here."
        ),
        Capability(
            id: "telephony.radio_technology",
            displayName: "Cellular technology",
            framework: "CoreTelephony",
            reveals: "Which cellular technology you are connected on — LTE, 5G, and so on. Carrier identity used to be readable here and no longer is.",
            simulator: .returnsNothing,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo",
            verified: "2026-08-30",
            notes: "serviceCurrentRadioAccessTechnology still works on device. Measured trap: in a Simulator it returns an EMPTY DICTIONARY inside a non-nil Optional, so unwrapping succeeds and yields nothing. Included partly to show the sandbox closing: CTCarrier was deprecated in iOS 16 with no replacement and now returns literal '--' and MCC/MNC 65535."
        ),
        Capability(
            id: "arkit.face_tracking",
            displayName: "Face tracking",
            framework: "ARKit",
            reveals: "The geometry of your face in real time — over fifty blend shapes tracking eye, mouth, and brow movement. Detailed enough to read expression, and to drive a convincing puppet of you.",
            plistKeys: ["NSCameraUsageDescription"],
            simulator: .unavailable,
            sensitivity: .intimate,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/arkit/arfacetrackingconfiguration + measured: isSupported == false",
            verified: "2026-08-30",
            notes: "ARKit links in the Simulator SDK but every configuration reports isSupported == false — guard, do not crash. Since iOS 14 face tracking needs only a Neural Engine rather than TrueDepth. Apple requires a privacy policy covering face data if this ships."
        ),
        Capability(
            id: "arkit.scene_reconstruction",
            displayName: "Room scanning",
            framework: "ARKit",
            reveals: "A three-dimensional mesh of the room you are standing in, built from the LiDAR scanner — the shape and dimensions of your home.",
            plistKeys: ["NSCameraUsageDescription"],
            simulator: .unavailable,
            sensitivity: .intimate,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:) + measured: false",
            verified: "2026-08-30",
            notes: "Requires LiDAR-equipped Pro hardware in addition to a device. Gate on supportsSceneReconstruction(_:), not on device model."
        ),
        Capability(
            id: "nearby_interaction.ranging",
            displayName: "Precise nearby ranging",
            framework: "NearbyInteraction",
            reveals: "Distance and direction to another Apple device to within centimetres, using ultra-wideband.",
            plistKeys: ["NSNearbyInteractionUsageDescription"],
            simulator: .unavailable,
            sensitivity: .personal,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/nearbyinteraction + measured: all deviceCapabilities false",
            verified: "2026-08-30",
            notes: "Needs UWB hardware AND a second consenting device, so even on hardware this cannot be verified alone. Check NISession.deviceCapabilities; NISession.isSupported is deprecated as of iOS 16."
        ),
        Capability(
            id: "wifi.ssid",
            displayName: "Wi-Fi network name",
            framework: "NetworkExtension",
            reveals: "The name and hardware address of the Wi-Fi network you are on, which maps to a physical place via public wardriving databases.",
            plistKeys: ["NSLocationWhenInUseUsageDescription"],
            entitlement: "com.apple.developer.networking.wifi-info",
            tier: .paid,
            simulator: .unavailable,
            sensitivity: .personal,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:)",
            verified: "2026-08-30",
            notes: "Requires the $99 program for the entitlement AND precise location authorization — both, not either. Returns nil without the entitlement rather than failing. CNCopyCurrentNetworkInfo is deprecated since iOS 14. Not reachable on the current free tier."
        ),
        Capability(
            id: "nfc.tag_reading",
            displayName: "NFC tags",
            framework: "CoreNFC",
            reveals: "Data from NFC tags and cards held near the phone.",
            plistKeys: ["NFCReaderUsageDescription"],
            entitlement: "com.apple.developer.nfc.readersession.formats",
            tier: .paid,
            simulator: .unavailable,
            sensitivity: .personal,
            promptsUser: true,
            source: "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats",
            verified: "2026-08-30",
            notes: "Requires the $99 program. CoreNFC is not functional in the Simulator and has historically failed to link there at all. Not reachable on the current free tier."
        ),
    ]
}

import Testing
import Foundation
@testable import GlasshouseCore

/// Invariants enforced against the source tree itself.
///
/// The README, the threat model, and every usage-description string in the app
/// promise that nothing leaves the device. These tests make that promise
/// checkable rather than aspirational — a claim about privacy that is not
/// enforced is just marketing.
@Suite("Project invariants")
struct ProjectInvariantTests {
    /// Repository root, derived from this file's own path.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // GlasshouseCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    static func swiftFiles(under directory: String) -> [URL] {
        let base = root.appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: nil
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("The test can actually see the source tree")
    func sourceTreeIsReachable() {
        // Guards the guard: a path mistake would make every check below vacuous.
        let sources = Self.swiftFiles(under: "Sources")
        #expect(sources.count > 10, "expected to find the source tree at \(Self.root.path)")
    }

    @Test("Nothing in the project can reach the network")
    func noNetworkEgress() throws {
        // Phase 1 has no network stack at all, so Phase 2 must add one
        // deliberately rather than inherit an open port. See
        // docs/phase-2-boundary.md.
        let forbidden = [
            "URLSession",
            "URLRequest",
            "import Network",
            "NWConnection",
            "NWBrowser",
            "CFStream",
            "Socket(",
            "URLDownload",
        ]

        var violations: [String] = []

        for directory in ["Sources", "App"] {
            for file in Self.swiftFiles(under: directory) {
                // NWPathMonitor is deliberately allowed: it observes what kind
                // of connection exists without opening one, which is itself a
                // capability worth demonstrating.
                let contents = try String(contentsOf: file, encoding: .utf8)
                let name = file.lastPathComponent

                for token in forbidden where contents.contains(token) {
                    violations.append("\(name): \(token)")
                }
            }
        }

        #expect(violations.isEmpty, """
            Network access found. Phase 1 must have no egress:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("There are no third-party dependencies")
    func zeroDependencies() throws {
        let manifest = try String(
            contentsOf: Self.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        // A dependency would be a supply-chain path into the most sensitive
        // data on the phone. Zero is the target; each addition needs a reason
        // recorded in docs/DECISIONS.md.
        #expect(!manifest.contains(".package("), "Package.swift declares an external dependency")
    }

    @Test("No analytics or crash reporting")
    func noTelemetry() throws {
        let forbidden = ["Firebase", "Crashlytics", "Sentry", "Amplitude",
                         "Mixpanel", "AppsFlyer", "Adjust", "Bugsnag"]
        var violations: [String] = []

        for directory in ["Sources", "App"] {
            for file in Self.swiftFiles(under: directory) {
                let contents = try String(contentsOf: file, encoding: .utf8)
                for token in forbidden where contents.contains(token) {
                    violations.append("\(file.lastPathComponent): \(token)")
                }
            }
        }
        #expect(violations.isEmpty, "\(violations.joined(separator: ", "))")
    }

    @Test("GlasshouseCore imports no Apple sensor framework")
    func coreStaysPortable() throws {
        // Core Motion does not exist on macOS, so a single import here would
        // permanently break the fast test loop that the whole architecture is
        // built around.
        let forbidden = ["import CoreMotion", "import CoreLocation", "import HealthKit",
                         "import AVFoundation", "import Photos", "import Contacts",
                         "import EventKit", "import UIKit", "import CoreBluetooth",
                         "import ARKit", "import Vision", "import SensorKit"]

        var violations: [String] = []
        for file in Self.swiftFiles(under: "Sources/GlasshouseCore") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden where contents.contains(token) {
                violations.append("\(file.lastPathComponent): \(token)")
            }
        }

        #expect(violations.isEmpty, """
            GlasshouseCore must stay platform-free:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("Every live adapter implements a capability the ledger knows")
    func adaptersMatchTheLedger() throws {
        // The ledger IS the registry, so an adapter for an unknown identifier
        // means someone bypassed it.
        var declared: Set<String> = []
        let pattern = try Regex(#"SensorID = "([a-z_]+\.[a-z_]+)""#)

        for file in Self.swiftFiles(under: "Sources/GlasshouseSensors") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for match in contents.matches(of: pattern) {
                declared.insert(String(match.output[1].substring ?? ""))
            }
        }

        let known = Set(CapabilityLedger.all.map(\.id.rawValue))
        let unknown = declared.subtracting(known).sorted()

        #expect(unknown.isEmpty, "adapters for capabilities not in the ledger: \(unknown)")
        #expect(declared.count >= 15, "expected to find the adapters, found \(declared.count)")
    }

    @Test("Captured personal data cannot be committed")
    func gitignoreCoversCaptures() throws {
        let gitignore = try String(
            contentsOf: Self.root.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        // The likeliest breach of a public repo about harvesting your own data
        // is a real sensor trace or App Privacy Report export committed by
        // accident.
        for pattern in ["*.ndjson", "captures/", "*.gpx", ".env", "*.mobileprovision", "*.p8"] {
            #expect(gitignore.contains(pattern), ".gitignore is missing '\(pattern)'")
        }
    }
}

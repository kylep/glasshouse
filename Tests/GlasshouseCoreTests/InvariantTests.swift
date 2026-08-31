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

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            // This file names every banned API in order to ban it. Scanning
            // itself would be a guaranteed false positive.
            .filter { $0.lastPathComponent != "InvariantTests.swift" }
    }

    /// Source with comments removed.
    ///
    /// The guard must judge code, not prose. Without this, documenting *why* an
    /// API is forbidden — which is exactly where that explanation belongs —
    /// trips the rule that forbids it.
    /// Handles ordinary string literals, so that a `//` inside a URL is not
    /// mistaken for the start of a comment. (Raw strings — `#"..."#` — are not
    /// modelled; none appear in the scanned sources, and treating their
    /// contents as code errs toward false positives, which is the safe
    /// direction for a security guard.)
    static func codeOnly(_ source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inBlockComment = false
        var inString = false
        var escaped = false

        while index < source.endIndex {
            let character = source[index]
            let rest = source[index...]

            if inBlockComment {
                if rest.hasPrefix("*/") {
                    inBlockComment = false
                    index = source.index(index, offsetBy: 2)
                } else {
                    index = source.index(after: index)
                }
                continue
            }

            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = source.index(after: index)
                continue
            }

            if rest.hasPrefix("/*") {
                inBlockComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }

            if rest.hasPrefix("//") {
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }

            if character == "\"" { inString = true }
            output.append(character)
            index = source.index(after: index)
        }

        return output
    }

    @Test("The test can actually see the source tree")
    func sourceTreeIsReachable() {
        // Guards the guard: a path mistake would make every check below vacuous.
        let sources = Self.swiftFiles(under: "Sources")
        #expect(sources.count > 10, "expected to find the source tree at \(Self.root.path)")
    }

    /// APIs capable of moving bytes off the device.
    ///
    /// Note what is NOT here: `import Network` on its own. Banning the import
    /// was a proxy for the wrong thing — `NWPathMonitor` observes the shape of
    /// connectivity without opening a connection, and it is a capability the
    /// app exists to demonstrate. What must not exist is *egress*, so the
    /// egress types are banned instead, everywhere and without exception.
    static let egressAPIs = [
        "URLSession", "URLRequest", "NSURLConnection", "URLDownload",
        "NWConnection", "NWListener", "NWBrowser",
        "CFStream", "CFSocket", "CFNetwork",
        "MultipeerConnectivity", "WKWebView", "SFSafariViewController",
        "UIApplication.shared.open",
    ]

    /// APIs that can fetch a remote URL but are legitimately used on local
    /// files. Allowed only in the named file, with the reason recorded.
    static let localFileOnlyAPIs: [(token: String, allowedIn: String, reason: String)] = [
        ("String(contentsOf:", "AttributionStore.swift",
         "reads the user-chosen NDJSON from fileImporter, which yields file:// URLs only"),
        ("Data(contentsOf:", "AttributionStore.swift",
         "reads the persisted history from Application Support"),
    ]

    @Test("Nothing in the project can reach the network")
    func noNetworkEgress() throws {
        // The app promises, in its README, its threat model, and every
        // permission dialog it shows, that nothing leaves the device. This is
        // what makes that checkable. See docs/phase-2-boundary.md.
        var violations: [String] = []

        // Scans the tool and the scripts too, not just shipping code: an
        // exfiltration path in a build script is still an exfiltration path.
        for directory in ["Sources", "App", "Tests"] {
            for file in Self.swiftFiles(under: directory) {
                let contents = Self.codeOnly(try String(contentsOf: file, encoding: .utf8))
                let name = file.lastPathComponent

                for token in Self.egressAPIs where contents.contains(token) {
                    violations.append("\(name): \(token)")
                }

                for entry in Self.localFileOnlyAPIs
                where contents.contains(entry.token) && name != entry.allowedIn {
                    violations.append("\(name): \(entry.token) (allowed only in \(entry.allowedIn))")
                }
            }
        }

        #expect(violations.isEmpty, """
            Network access found. This project must have no egress:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("Only the path monitor may import Network")
    func networkImportIsConfinedToOneFile() throws {
        // NWPathMonitor needs the framework; nothing else does. Confining the
        // import keeps the exemption visible instead of letting it spread.
        var importers: [String] = []

        for directory in ["Sources", "App", "Tests"] {
            for file in Self.swiftFiles(under: directory) {
                let contents = Self.codeOnly(try String(contentsOf: file, encoding: .utf8))
                if contents.contains("import Network") {
                    importers.append(file.lastPathComponent)
                }
            }
        }

        #expect(importers.sorted() == ["LiveNetworkPath.swift"],
                "unexpected importers of Network: \(importers.sorted())")
    }

    @Test("The egress guard actually catches something")
    func egressGuardIsNotVacuous() {
        // Guards the guard. A typo in a path or a token list that never matches
        // would make the check above pass silently forever.
        let sample = "let task = URLSession.shared.dataTask(with: request)"
        let caught = Self.egressAPIs.filter { sample.contains($0) }
        #expect(caught == ["URLSession"])
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
                let contents = Self.codeOnly(try String(contentsOf: file, encoding: .utf8))
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

@Suite("The invariant scanner itself")
struct InvariantScannerTests {
    @Test("Comments are stripped, code is not")
    func stripsComments() {
        let source = """
            // URLSession must never appear
            let a = 1
            /* NWConnection is banned
               across multiple lines */
            let b = URLSession.shared
            """
        let code = ProjectInvariantTests.codeOnly(source)

        #expect(!code.contains("must never appear"))
        #expect(!code.contains("NWConnection"))
        #expect(code.contains("let a = 1"))
        // The real usage on the last line must survive, or the guard is blind.
        #expect(code.contains("URLSession.shared"))
    }

    @Test("A URL inside a string literal is not mistaken for a comment")
    func doesNotEatStringContents() {
        // Without string-literal awareness the "//" in a URL truncates the rest
        // of the line, which could hide a real call sitting after it.
        let source = "let s = \"https://example.com/path\"\nlet t = URLSession.shared"
        let code = ProjectInvariantTests.codeOnly(source)

        #expect(code.contains("example.com"))
        #expect(code.contains("URLSession.shared"), "code after a URL literal must survive")
    }
}

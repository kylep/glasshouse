import Foundation

/// Which shape an App Privacy Report export uses.
///
/// **Apple documents the report's contents but never documents the export
/// format.** Research turned up two different schemas in circulation, so the
/// decoder detects rather than assumes, and reports which it found.
public enum PrivacyReportSchema: String, Sendable, Hashable, Codable {
    /// Keyed on `type` (`access` / `networkActivity`) with `category` and
    /// `intervalBegin`/`intervalEnd` pairs joined by a shared UUID. Believed
    /// current; matches exports seen through at least 2022 and the behaviour of
    /// App Store apps still reading these files in 2026.
    case v4

    /// Keyed on `stream` and `tccService` (`kTCCServiceCamera` and friends),
    /// with `version: 3`. Appears to be an iOS 15 beta format preserved in a
    /// community parser. Decoded anyway, because the cost of supporting it is
    /// small and the cost of rejecting a real file is not.
    case v3

    /// Neither shape recognised.
    case unknown
}

/// Turns an App Privacy Report NDJSON export into normalised activity.
///
/// Design constraints that come from the format rather than from taste:
///
/// - **Never throw away a line silently.** A schema change must surface as a
///   visible failure, because this data cannot be re-fetched — the report keeps
///   a 7-day rolling window and switching it off erases it.
/// - **Accesses arrive as pairs.** `intervalBegin` and `intervalEnd` share a
///   UUID and must be joined. Unterminated intervals at the window edge are
///   normal, not corrupt.
/// - **Decode per line.** One malformed record must not lose the rest of a file.
public struct PrivacyReportDecoder: Sendable {
    public init() {}

    public func decode(_ text: String) -> PrivacyReportImport {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        var openIntervals: [String: (bundleID: String, resource: AccessedResource, began: Double)] = [:]
        var accesses: [ResourceAccess] = []
        var contacts: [NetworkContact] = []
        var failures: [DecodingFailure] = []
        var detected: PrivacyReportSchema?

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                failures.append(DecodingFailure(line: lineNumber, reason: "not valid JSON"))
                continue
            }

            let schema = Self.schema(of: object)
            if detected == nil || detected == .unknown { detected = schema }

            switch schema {
            case .v4:
                decodeV4(object, line: lineNumber,
                         openIntervals: &openIntervals, accesses: &accesses,
                         contacts: &contacts, failures: &failures)
            case .v3:
                decodeV3(object, line: lineNumber, accesses: &accesses, failures: &failures)
            case .unknown:
                failures.append(DecodingFailure(
                    line: lineNumber,
                    reason: "unrecognised record shape — keys: \(object.keys.sorted().prefix(6).joined(separator: ", "))"
                ))
            }
        }

        // Intervals still open when the export was taken are expected: the
        // report is a snapshot, and an app may have been mid-access.
        // Sorted by key first, because dictionary iteration order varies
        // between processes and the output must be reproducible.
        for key in openIntervals.keys.sorted() {
            guard let open = openIntervals[key] else { continue }
            accesses.append(ResourceAccess(
                bundleID: open.bundleID, resource: open.resource,
                began: open.began, ended: nil
            ))
        }

        return PrivacyReportImport(
            // `sorted(by:)` is not stable, so ties are broken explicitly rather
            // than left to vary between runs.
            accesses: accesses.sorted {
                ($0.began, $0.bundleID, $0.resource.rawValue)
                    < ($1.began, $1.bundleID, $1.resource.rawValue)
            },
            contacts: contacts.sorted {
                ($0.lastSeen, $0.bundleID, $0.domain) < ($1.lastSeen, $1.bundleID, $1.domain)
            },
            failures: failures,
            schema: detected ?? .unknown
        )
    }

    // MARK: - Schema detection

    static func schema(of object: [String: Any]) -> PrivacyReportSchema {
        if let type = object["type"] as? String,
           type == "access" || type == "networkActivity" {
            return .v4
        }
        if object["tccService"] != nil || (object["stream"] as? String)?.contains("privacy.accounting") == true {
            return .v3
        }
        return .unknown
    }

    // MARK: - v4

    private func decodeV4(
        _ object: [String: Any],
        line: Int,
        openIntervals: inout [String: (bundleID: String, resource: AccessedResource, began: Double)],
        accesses: inout [ResourceAccess],
        contacts: inout [NetworkContact],
        failures: inout [DecodingFailure]
    ) {
        switch object["type"] as? String {
        case "access":
            guard let accessor = object["accessor"] as? [String: Any],
                  let bundleID = accessor["identifier"] as? String,
                  let rawCategory = object["category"] as? String,
                  let timestamp = Self.parseDate(object["timeStamp"])
            else {
                failures.append(DecodingFailure(line: line, reason: "access record missing accessor, category, or timeStamp"))
                return
            }

            guard let resource = Self.resource(fromCategory: rawCategory) else {
                failures.append(DecodingFailure(line: line, reason: "unknown category '\(rawCategory)'"))
                return
            }

            // Records without a pairing UUID are treated as instantaneous.
            guard let key = object["identifier"] as? String else {
                accesses.append(ResourceAccess(bundleID: bundleID, resource: resource,
                                               began: timestamp, ended: timestamp))
                return
            }

            switch object["kind"] as? String {
            case "intervalBegin":
                // Two begins for one UUID means one of them can never be
                // paired. Overwriting silently would drop a real access, which
                // this decoder does not do.
                if let displaced = openIntervals[key] {
                    failures.append(DecodingFailure(
                        line: line,
                        reason: "duplicate intervalBegin for '\(key)'; the earlier one is unpairable"
                    ))
                    accesses.append(ResourceAccess(bundleID: displaced.bundleID,
                                                   resource: displaced.resource,
                                                   began: displaced.began, ended: nil))
                }
                openIntervals[key] = (bundleID, resource, timestamp)
            case "intervalEnd":
                if let open = openIntervals.removeValue(forKey: key) {
                    accesses.append(ResourceAccess(bundleID: open.bundleID, resource: open.resource,
                                                   began: open.began, ended: timestamp))
                } else {
                    // An end with no beginning: the access started before the
                    // window opened, so its duration is UNKNOWN rather than
                    // zero. Encoding it as `began == ended` would silently
                    // claim an app used your microphone for 0 seconds. `nil`
                    // is the same encoding used for an interval still open at
                    // the other edge, and for the same reason.
                    accesses.append(ResourceAccess(bundleID: bundleID, resource: resource,
                                                   began: timestamp, ended: nil))
                }
            default:
                accesses.append(ResourceAccess(bundleID: bundleID, resource: resource,
                                               began: timestamp, ended: timestamp))
            }

        case "networkActivity":
            guard let bundleID = object["bundleID"] as? String,
                  let domain = object["domain"] as? String,
                  let last = Self.parseDate(object["timeStamp"])
            else {
                failures.append(DecodingFailure(line: line, reason: "network record missing bundleID, domain, or timeStamp"))
                return
            }

            let owner = (object["domainOwner"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            contacts.append(NetworkContact(
                bundleID: bundleID,
                domain: domain,
                hits: object["hits"] as? Int ?? 1,
                // Apple's own flag: 1 means identified as tracking across apps.
                flaggedAsTracker: (object["domainType"] as? Int) == 1,
                appInitiated: (object["initiatedType"] as? String) == "AppInitiated",
                owner: owner,
                firstSeen: Self.parseDate(object["firstTimeStamp"]) ?? last,
                lastSeen: last
            ))

        default:
            failures.append(DecodingFailure(line: line, reason: "unknown v4 record type"))
        }
    }

    // MARK: - v3

    private func decodeV3(
        _ object: [String: Any],
        line: Int,
        accesses: inout [ResourceAccess],
        failures: inout [DecodingFailure]
    ) {
        guard let accessor = object["accessor"] as? [String: Any],
              let bundleID = accessor["identifier"] as? String,
              let service = object["tccService"] as? String,
              // Note the lower-case 's': v3 spells this differently from v4,
              // which is the kind of detail that makes a tolerant decoder worth
              // having. Accept either.
              let timestamp = Self.parseDate(object["timestamp"] ?? object["timeStamp"])
        else {
            failures.append(DecodingFailure(line: line, reason: "v3 record missing accessor, tccService, or timestamp"))
            return
        }

        guard let resource = Self.resource(fromTCCService: service) else {
            failures.append(DecodingFailure(line: line, reason: "unknown TCC service '\(service)'"))
            return
        }

        // v3 records are point events rather than intervals.
        accesses.append(ResourceAccess(bundleID: bundleID, resource: resource,
                                       began: timestamp, ended: timestamp))
    }

    // MARK: - Vocabulary

    static func resource(fromCategory category: String) -> AccessedResource? {
        switch category {
        case "camera": .camera
        case "microphone": .microphone
        case "photos": .photos
        case "contacts": .contacts
        case "location": .location
        case "mediaLibrary": .mediaLibrary
        case "screenRecording": .screenRecording
        case "calendar": .calendar
        case "reminders": .reminders
        default: nil
        }
    }

    static func resource(fromTCCService service: String) -> AccessedResource? {
        switch service {
        case "kTCCServiceCamera": .camera
        case "kTCCServiceMicrophone": .microphone
        case "kTCCServicePhotos", "kTCCServicePhotosAdd": .photos
        case "kTCCServiceAddressBook": .contacts
        case "kTCCServiceLocation", "kTCCServiceLiverpool": .location
        case "kTCCServiceMediaLibrary": .mediaLibrary
        case "kTCCServiceScreenCapture": .screenRecording
        case "kTCCServiceCalendar": .calendar
        case "kTCCServiceReminders": .reminders
        default: nil
        }
    }

    /// Parses the ISO 8601 timestamps the report uses, which carry fractional
    /// seconds and a local UTC offset.
    static func parseDate(_ value: Any?) -> Double? {
        guard let text = value as? String else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date.timeIntervalSince1970 }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)?.timeIntervalSince1970
    }
}

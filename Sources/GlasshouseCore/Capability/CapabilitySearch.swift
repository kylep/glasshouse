public extension Capability {
    /// Whether this capability matches a search query.
    ///
    /// Searches what a sensor **reveals**, not just what it is called. Someone
    /// typing "who is near me" is looking for Bluetooth, and "where have I
    /// been" for photo locations — neither of which contains those words in its
    /// name. The `reveals` text is written in plain language for exactly this
    /// kind of reading, so it is the most useful field to match against.
    ///
    /// Every word in the query must appear somewhere, in any field and any
    /// order. That makes narrowing predictable: adding a word never widens the
    /// result, which is the behaviour people expect from a search box even when
    /// they could not state the rule.
    func matches(_ query: String) -> Bool {
        let words = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return true }

        let haystack = [
            displayName,
            id.rawValue.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " "),
            framework,
            reveals,
            notes ?? "",
            // The consent state is searchable in words people actually use —
            // "never asks" is the thing someone wants to filter on, and it
            // appears nowhere else in the text.
            gate.shortLabel,
            sensitivity.rawValue,
        ].joined(separator: " ").lowercased()

        return words.allSatisfy { haystack.contains($0) }
    }
}

public extension CapabilityLedger {
    /// Capabilities matching a query, in ledger order.
    static func search(_ query: String, within rows: [Capability] = all) -> [Capability] {
        rows.filter { $0.matches(query) }
    }
}

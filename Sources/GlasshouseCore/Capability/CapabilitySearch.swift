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
        let typed = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { !$0.isEmpty }

        guard !typed.isEmpty else { return true }

        // Question words are dropped before matching. The doc above promised
        // that "who is near me" finds Bluetooth, and it did not: every word had
        // to appear, and no capability's text contains "who" or "me". The
        // search box even suggests that exact phrase as a placeholder, so the
        // app's own example returned "No Results".
        //
        // Dropping them costs nothing — none of these words distinguishes one
        // capability from another, so they could only ever narrow a result set
        // to nothing.
        let filtered = typed.filter { !Self.questionWords.contains(String($0)) }
        let words = filtered.isEmpty ? typed : filtered

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

extension Capability {
    /// Words that carry no signal about which capability is wanted.
    ///
    /// Deliberately only grammar — no domain words. Dropping "location" or
    /// "near" would make the search worse, not better.
    ///
    /// "where", "when", "how" and "what" are deliberately NOT here: they read
    /// like grammar but carry meaning in this ledger, where a capability
    /// describes itself as "Where each photo was taken". Dropping "where" would
    /// break "where have I been", which is the other example the docs promise.
    static let questionWords: Set<String> = [
        "a", "am", "an", "and", "any", "anything", "are", "be", "been", "by",
        "can", "could", "did", "do", "does", "for", "from", "has", "have",
        "i", "in", "is", "it", "its", "me", "my", "of", "on", "or",
        "s", "the", "there", "they", "this", "to", "was",
        "who", "whose", "will", "with", "you", "your",
    ]
}

public extension CapabilityLedger {
    /// Capabilities matching a query, in ledger order.
    static func search(_ query: String, within rows: [Capability] = all) -> [Capability] {
        rows.filter { $0.matches(query) }
    }
}

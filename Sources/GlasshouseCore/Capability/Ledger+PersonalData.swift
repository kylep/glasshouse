extension CapabilityLedger {
    /// Contacts, calendar, and reminders.
    ///
    /// These are the only capabilities where the data subject is largely
    /// *someone else*. Your address book is a social graph of people who never
    /// installed this app and never consented to it, and your calendar names
    /// who you met and when. They get stricter defaults for that reason.
    ///
    /// All three are richly seeded in the Simulator, which makes them the best
    /// sources to develop against without hardware.
    static let personalData: [Capability] = [
        Capability(
            id: "contacts.all",
            displayName: "Contacts",
            framework: "Contacts",
            reveals: "Everyone you know: names, phone numbers, emails, street addresses, birthdays, employers, and relationships. This is data about other people, and none of them agreed to it.",
            plistKeys: ["NSContactsUsageDescription"],
            simulator: .worksFully,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/contacts/cnauthorizationstatus/limited + measured: 6 seeded contacts with phones, emails, addresses",
            verified: "2026-08-30",
            notes: "iOS 18 added `.limited`, where the user picks specific contacts — a distinct third state that must not be collapsed into authorized or denied. Both paths are scriptable: `simctl privacy` exposes `contacts` and `contacts-limited` separately. Simulator ships the classic Kate Bell / John Appleseed set."
        ),
        Capability(
            id: "calendar.events",
            displayName: "Calendar",
            framework: "EventKit",
            reveals: "Where you were and who you were with, past and future. Titles, attendees, locations, and recurrence — a diary that is often more revealing than location history.",
            plistKeys: ["NSCalendarsFullAccessUsageDescription"],
            simulator: .worksFully,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsusagedescription + measured: ~90 seeded events across several calendars",
            verified: "2026-08-30",
            notes: "iOS 17 split the old NSCalendarsUsageDescription (now deprecated) into full-access and write-only keys. Write-only genuinely means write-only: reads return nothing, including for events the app itself created. The richest seeded source in the Simulator."
        ),
        Capability(
            id: "calendar.write_only",
            displayName: "Calendar (write-only)",
            framework: "EventKit",
            reveals: "The ability to add events to your calendar without being able to read any of it — a genuinely narrower permission that most apps could use instead of full access, and few do.",
            plistKeys: ["NSCalendarsWriteOnlyAccessUsageDescription"],
            simulator: .worksFully,
            sensitivity: .ambient,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/eventkit/ekauthorizationstatus",
            verified: "2026-08-30",
            notes: "iOS 17+. Included in the ledger as a teaching example rather than a data source: showing the user that a least-privilege option exists is part of the point. Note that presenting EKEventEditViewController on iOS 17+ needs no calendar access at all."
        ),
        Capability(
            id: "reminders.all",
            displayName: "Reminders",
            framework: "EventKit",
            reveals: "Your to-do lists, including location-triggered reminders that reveal the places you care about.",
            plistKeys: ["NSRemindersFullAccessUsageDescription"],
            simulator: .worksFully,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/eventkit/ekauthorizationstatus",
            verified: "2026-08-30",
            notes: "iOS 17 split key, replacing the deprecated NSRemindersUsageDescription. If events were requested before authorization, call EKEventStore.reset() afterwards or the store keeps returning nothing."
        ),
    ]
}

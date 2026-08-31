#if os(iOS)
import Foundation
import Contacts
import EventKit
import GlasshouseCore

/// How much of other people's information your address book holds.
///
/// Worth stating plainly in the UI: this is the one category where the data
/// subject is largely someone else. None of those people installed this app.
public struct LiveContactsSource: SensorSource {
    public let id: SensorID = "contacts.all"

    public init() {}

    public func availability() async -> SensorAvailability {
        Self.map(CNContactStore.authorizationStatus(for: .contacts))
    }

    public func requestAccess() async -> SensorAvailability {
        let store = CNContactStore()
        _ = try? await store.requestAccess(for: .contacts)
        return Self.map(CNContactStore.authorizationStatus(for: .contacts))
    }

    public func read() async -> SensorSample? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || status == .limited else { return nil }

        let store = CNContactStore()
        let keys: [any CNKeyDescriptor] = [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        var people = 0
        var phones = 0
        var emails = 0
        var addresses = 0
        var birthdays = 0
        var organisations = 0

        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            people += 1
            phones += contact.phoneNumbers.count
            emails += contact.emailAddresses.count
            addresses += contact.postalAddresses.count
            if contact.birthday != nil { birthdays += 1 }
            if !contact.organizationName.isEmpty { organisations += 1 }
        }

        guard people > 0 else { return nil }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("People", .integer(people)),
            SensorField("Phone numbers", .integer(phones)),
            SensorField("Email addresses", .integer(emails)),
            SensorField("Street addresses", .integer(addresses)),
            SensorField("Birthdays", .integer(birthdays)),
            SensorField("Employers", .integer(organisations)),
            SensorField("Access", .text(status == .limited ? "a selection you chose" : "everyone")),
        ])
    }

    static func map(_ status: CNAuthorizationStatus) -> SensorAvailability {
        switch status {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        // iOS 18+. A genuinely distinct state: the user picked specific people,
        // and `CNContactStore` silently returns only those.
        case .limited: .limited
        case .authorized: .ready
        @unknown default: .needsPermission
        }
    }
}

/// Where you have been and who you were with — often more revealing than a
/// location history, because it is annotated.
public struct LiveCalendarSource: SensorSource {
    public let id: SensorID = "calendar.events"

    public init() {}

    public func availability() async -> SensorAvailability {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    public func requestAccess() async -> SensorAvailability {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToEvents()
        return Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    public func read() async -> SensorSample? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        let store = EKEventStore()
        // If events were requested before authorization was granted, the store
        // keeps returning nothing until it is reset.
        store.reset()

        let calendars = store.calendars(for: .event)
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-365 * 86_400),
            end: now.addingTimeInterval(365 * 86_400),
            calendars: nil
        )
        let events = store.events(matching: predicate)

        var withLocation = 0
        var withAttendees = 0
        var attendees = 0
        for event in events {
            if !(event.location ?? "").isEmpty { withLocation += 1 }
            if let people = event.attendees, !people.isEmpty {
                withAttendees += 1
                attendees += people.count
            }
        }

        return SensorSample(sensor: id, timestamp: now.timeIntervalSince1970, fields: [
            SensorField("Calendars", .integer(calendars.count)),
            SensorField("Events (±1 year)", .integer(events.count)),
            SensorField("With a location", .integer(withLocation)),
            SensorField("With other people", .integer(withAttendees)),
            SensorField("Attendee records", .integer(attendees)),
        ])
    }

    static func map(_ status: EKAuthorizationStatus) -> SensorAvailability {
        switch status {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .fullAccess: .ready
        // Write-only genuinely reads nothing back, including events this app
        // created itself — so it is not partial access, it is no read access.
        case .writeOnly: .limited
        @unknown default: .needsPermission
        }
    }
}

/// Plain counts extracted from reminders, because `EKReminder` is not Sendable
/// and must not cross a concurrency boundary.
private struct ReminderTally: Sendable {
    let total: Int
    let completed: Int
    let withAlarms: Int
    let locationTriggered: Int
}

/// Reminders, including the location-triggered ones that reveal which places
/// matter to you.
public struct LiveRemindersSource: SensorSource {
    public let id: SensorID = "reminders.all"

    public init() {}

    public func availability() async -> SensorAvailability {
        LiveCalendarSource.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    public func requestAccess() async -> SensorAvailability {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToReminders()
        return LiveCalendarSource.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    public func read() async -> SensorSample? {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }

        let store = EKEventStore()
        store.reset()
        let lists = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: nil)

        // EKReminder is not Sendable, so the objects themselves must not cross
        // the continuation. Reduce to plain counts inside the callback instead.
        let tally: ReminderTally = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let reminders = reminders ?? []
                continuation.resume(returning: ReminderTally(
                    total: reminders.count,
                    completed: reminders.filter(\.isCompleted).count,
                    withAlarms: reminders.filter { !($0.alarms ?? []).isEmpty }.count,
                    locationTriggered: reminders.filter {
                        ($0.alarms ?? []).contains { $0.structuredLocation != nil }
                    }.count
                ))
            }
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Lists", .integer(lists.count)),
            SensorField("Reminders", .integer(tally.total)),
            SensorField("Completed", .integer(tally.completed)),
            SensorField("With alarms", .integer(tally.withAlarms)),
            SensorField("Tied to a place", .integer(tally.locationTriggered)),
        ])
    }
}
#endif

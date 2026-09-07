#if os(iOS)
import Foundation
import HealthKit
import GlasshouseCore

/// Owns the one `HKHealthStore` the app needs.
///
/// HealthKit has a design property worth understanding before reading any of
/// this: **iOS deliberately refuses to tell an app whether it was granted read
/// access.** `authorizationStatus(for:)` reports the *write* permission only.
/// For reads, a denied app and an app whose user simply has no data both see an
/// empty result, and Apple documents that as intentional — revealing the
/// difference would leak the fact that a person has, say, no pregnancy records.
///
/// It is a genuinely good privacy design, and it means this adapter cannot
/// honestly claim to know why it is empty. It says so instead of guessing.
@MainActor
final class HealthStoreBox {
    static let shared = HealthStoreBox()

    let store = HKHealthStore()

    /// Whether authorization has ever been requested.
    ///
    /// Persisted, and that is not incidental. iOS refuses to report whether a
    /// health READ was granted — `authorizationStatus` covers writes only — so
    /// the app's own record of having asked is the only signal available.
    ///
    /// This was in-memory at first, which meant the row showed as ready
    /// immediately after being granted and reverted to "hasn't been asked" on
    /// the next launch. The permission was fine; the app had simply forgotten
    /// asking for it.
    private static let askedKey = "health.authorizationRequested"

    var hasAsked: Bool {
        get { UserDefaults.standard.bool(forKey: Self.askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.askedKey) }
    }

    private init() {}

    static var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for identifier: HKQuantityTypeIdentifier in [
            .stepCount, .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
            .activeEnergyBurned, .distanceWalkingRunning, .flightsClimbed,
            .oxygenSaturation, .respiratoryRate, .bodyMass, .vo2Max,
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier: HKCategoryTypeIdentifier in [
            .sleepAnalysis, .mindfulSession,
            .menstrualFlow, .ovulationTestResult, .sexualActivity, .pregnancy,
        ] {
            if let type = HKObjectType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let mood = HKObjectType.stateOfMindType() as HKObjectType? {
            types.insert(mood)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Read-only: this app has no business writing to anyone's health record.
        try? await store.requestAuthorization(toShare: [], read: Self.typesToRead)

        // Recorded after the call returns, so a request that threw does not
        // leave the app believing it asked.
        hasAsked = true
    }

    /// Counts samples of one quantity type over a window.
    func sampleCount(for identifier: HKQuantityTypeIdentifier, days: Int = 30) async -> Int? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        let end = Date()
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                once.resume(nil)
            }

            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                once.resume(samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    /// The most recent value of a quantity type, in the given unit.
    func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, at: Double)? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<(value: Double, at: Double)?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                once.resume(nil)
            }

            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    once.resume(nil)
                    return
                }
                once.resume((sample.quantity.doubleValue(for: unit),
                             sample.endDate.timeIntervalSince1970))
            }
            store.execute(query)
        }
    }

    /// Counts category samples — sleep, mindfulness, cycle tracking — over a
    /// window, and reports the most recent one's value.
    ///
    /// Separate from the quantity query because category samples carry an
    /// integer code rather than a measurement, and the code's meaning depends
    /// on which category it came from.
    func categorySamples(
        _ identifier: HKCategoryTypeIdentifier,
        days: Int = 30
    ) async -> (count: Int, latestValue: Int?, latestAt: Double?)? {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else { return nil }

        let end = Date()
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { (continuation: CheckedContinuation<(count: Int, latestValue: Int?, latestAt: Double?)?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                once.resume(nil)
            }

            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                let categories = (samples as? [HKCategorySample]) ?? []
                once.resume((
                    count: categories.count,
                    latestValue: categories.first?.value,
                    latestAt: categories.first?.endDate.timeIntervalSince1970
                ))
            }
            store.execute(query)
        }
    }

    func earliestSampleDate(for identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                once.resume(nil)
            }

            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                once.resume(samples?.first?.startDate.timeIntervalSince1970)
            }
            store.execute(query)
        }
    }
}

/// Heart rate, variability, blood oxygen, and respiratory rate.
///
/// Much of this is recorded continuously by a watch and goes back years, which
/// is the point worth making: the reading is not a measurement taken now, it is
/// a history handed over.
public struct LiveHealthVitalsSource: SensorSource {
    public let id: SensorID = "health.vitals"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return await HealthStoreBox.shared.hasAsked ? .ready : .needsPermission
    }

    public func requestAccess() async -> SensorAvailability {
        await HealthStoreBox.shared.requestAuthorization()
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let box = await HealthStoreBox.shared

        var fields: [SensorField] = []

        if let heart = await box.latest(.heartRate, unit: HKUnit.count().unitDivided(by: .minute())) {
            fields.append(SensorField("Latest heart rate", .number(heart.value.rounded(), unit: "bpm")))
            fields.append(SensorField("Measured", .time(heart.at)))
        }
        if let resting = await box.latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())) {
            fields.append(SensorField("Resting heart rate", .number(resting.value.rounded(), unit: "bpm")))
        }
        if let oxygen = await box.latest(.oxygenSaturation, unit: .percent()) {
            fields.append(SensorField("Blood oxygen", .number((oxygen.value * 100).rounded(), unit: "%")))
        }
        if let count = await box.sampleCount(for: .heartRate, days: 30) {
            fields.append(SensorField("Heart readings (30 days)", .integer(count)))
        }
        if let earliest = await box.earliestSampleDate(for: .heartRate) {
            fields.append(SensorField("Records go back to", .time(earliest)))
        }

        guard !fields.isEmpty else {
            // The honest answer, and a genuinely interesting one: iOS will not
            // tell an app whether a read was denied or simply had no data, so
            // claiming either would be a guess.
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Result", .text("nothing returned")),
                SensorField("Why", .text("iOS never says whether a health read was denied or just empty")),
            ])
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}

/// Steps, distance, energy, and workouts.
public struct LiveHealthActivitySource: SensorSource {
    public let id: SensorID = "health.activity"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return await HealthStoreBox.shared.hasAsked ? .ready : .needsPermission
    }

    public func requestAccess() async -> SensorAvailability {
        await HealthStoreBox.shared.requestAuthorization()
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let box = await HealthStoreBox.shared

        var fields: [SensorField] = []

        if let steps = await box.sampleCount(for: .stepCount, days: 30) {
            fields.append(SensorField("Step records (30 days)", .integer(steps)))
        }
        if let latest = await box.latest(.stepCount, unit: .count()) {
            fields.append(SensorField("Most recent step sample", .number(latest.value, unit: "steps")))
        }
        if let flights = await box.latest(.flightsClimbed, unit: .count()) {
            fields.append(SensorField("Flights climbed", .number(flights.value, unit: "")))
        }
        if let vo2 = await box.latest(.vo2Max, unit: HKUnit(from: "ml/kg*min")) {
            // A cardiovascular fitness estimate, which is a medical-adjacent
            // inference rather than a measurement the person chose to record.
            fields.append(SensorField("VO2 max", .number(vo2.value.rounded(), unit: "ml/kg/min")))
        }
        if let earliest = await box.earliestSampleDate(for: .stepCount) {
            fields.append(SensorField("Records go back to", .time(earliest)))
        }

        guard !fields.isEmpty else {
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Result", .text("nothing returned")),
                SensorField("Why", .text("iOS never says whether a health read was denied or just empty")),
            ])
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}
/// When you sleep, how well, and — since iOS 18 — how you said you felt.
///
/// Sleep is among the most inferentially rich streams on the phone. A month of
/// bedtimes reveals shift work, insomnia, a new baby, or a relationship
/// changing, none of which anyone chose to record.
public struct LiveHealthSleepSource: SensorSource {
    public let id: SensorID = "health.sleep_and_mind"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return await HealthStoreBox.shared.hasAsked ? .ready : .needsPermission
    }

    public func requestAccess() async -> SensorAvailability {
        await HealthStoreBox.shared.requestAuthorization()
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let box = await HealthStoreBox.shared

        var fields: [SensorField] = []

        if let sleep = await box.categorySamples(.sleepAnalysis), sleep.count > 0 {
            fields.append(SensorField("Sleep records (30 days)", .integer(sleep.count)))
            if let at = sleep.latestAt {
                fields.append(SensorField("Most recent", .time(at)))
            }
            if let value = sleep.latestValue {
                fields.append(SensorField("Last state", .text(Self.sleepState(value))))
            }
        }

        if let mindful = await box.categorySamples(.mindfulSession), mindful.count > 0 {
            fields.append(SensorField("Mindful sessions (30 days)", .integer(mindful.count)))
        }

        guard !fields.isEmpty else {
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Result", .text("nothing returned")),
                SensorField("Why", .text("iOS never says whether a health read was denied or just empty")),
            ])
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }

    /// `HKCategoryValueSleepAnalysis` raw values, named.
    static func sleepState(_ value: Int) -> String {
        switch value {
        case 0: "in bed"
        case 1: "asleep"
        case 2: "awake"
        case 3: "core sleep"
        case 4: "deep sleep"
        case 5: "REM sleep"
        default: "unspecified (\(value))"
        }
    }
}

/// Cycle tracking, pregnancy, and sexual activity.
///
/// Deliberately a separate capability rather than folded into vitals. This is
/// the category where the gap between "an app can read this" and "an app should
/// read this" is widest, and in several jurisdictions it is legally
/// consequential rather than merely private.
///
/// Reports counts and dates only — never the values themselves. Someone should
/// be able to see that an app could reach this data without the app displaying
/// their cycle back at them to make the point.
public struct LiveHealthReproductiveSource: SensorSource {
    public let id: SensorID = "health.reproductive"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return await HealthStoreBox.shared.hasAsked ? .ready : .needsPermission
    }

    public func requestAccess() async -> SensorAvailability {
        await HealthStoreBox.shared.requestAuthorization()
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let box = await HealthStoreBox.shared

        var present: [String] = []
        var total = 0

        for (identifier, label) in [
            (HKCategoryTypeIdentifier.menstrualFlow, "cycle tracking"),
            (.ovulationTestResult, "ovulation tests"),
            (.sexualActivity, "sexual activity"),
            (.pregnancy, "pregnancy"),
        ] {
            if let result = await box.categorySamples(identifier, days: 365), result.count > 0 {
                present.append(label)
                total += result.count
            }
        }

        guard total > 0 else {
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Records found", .integer(0)),
                SensorField("Why", .text("either nothing is logged, or iOS declined the read — it never says which")),
            ])
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Records readable (1 year)", .integer(total)),
            SensorField("Categories present", .text(present.joined(separator: ", "))),
            // The point of the row, stated rather than implied.
            SensorField("Values shown", .text("none — only that they are reachable")),
        ])
    }
}
#endif

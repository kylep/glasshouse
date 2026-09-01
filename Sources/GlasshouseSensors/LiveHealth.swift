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

    /// Whether authorization has been requested this launch. HealthKit will not
    /// say, so the app tracks its own asking rather than inferring.
    private(set) var hasAsked = false

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
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        hasAsked = true
        // Read-only: this app has no business writing to anyone's health record.
        try? await store.requestAuthorization(toShare: [], read: Self.typesToRead)
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
#endif

#if os(iOS)
import Foundation

/// Runs `work`, giving up and returning nil after `seconds`.
///
/// Several Apple sensor APIs deliver results through a completion handler that
/// may simply never fire — a barometer that errors on its first callback, a
/// permission dialog the user backgrounds without answering, a query whose
/// owning object was released. Without a bound, one of those stalls the whole
/// app: `SensorRegistry.snapshotAll` awaits a task group over every capability,
/// so a single hung child means the sensor list never populates again for the
/// life of the process.
///
/// This does not rescue a leaked continuation — that memory stays lost until
/// the process exits. It bounds the damage to one sensor rather than all of
/// them, which is the difference between a row saying "reported nothing" and
/// an app that appears to have frozen.
func withTimeout<T: Sendable>(
    seconds: Double,
    _ work: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// Wraps a completion-handler API so its continuation resumes exactly once.
///
/// `CMAltimeter` and friends can call their handler repeatedly, or never. A
/// bare `withCheckedContinuation` around one of those either traps on a double
/// resume or leaks on none, and both failures are silent in release builds.
final class SingleResume<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T?, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    /// Resumes if nothing has yet. Returns whether this call was the one that did.
    @discardableResult
    func resume(_ value: T?) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()

        pending?.resume(returning: value)
        return pending != nil
    }
}
#endif

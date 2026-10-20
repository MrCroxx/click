import Foundation

/// A manual pause cancels recovery; duplicate sleep/wake notifications are harmless.
struct SleepRecovery {
    private(set) var shouldResume = false
    mutating func sleep(active: Bool) { shouldResume = shouldResume || active }
    mutating func cancel() { shouldResume = false }
    mutating func wake() -> Bool {
        defer { shouldResume = false }
        return shouldResume
    }
}

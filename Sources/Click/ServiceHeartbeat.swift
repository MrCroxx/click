import AppKit

enum ServiceHeartbeat {
    /// Menus and open/save panels run nested loops. Their continued UI activity
    /// must not look like a crashed agent to the daemon's five-second lease.
    @MainActor static func schedule(interval: TimeInterval = 1, tick: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        for mode: RunLoop.Mode in [.common, .eventTracking, .modalPanel] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return timer
    }
}

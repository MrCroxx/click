import AppKit
import XCTest
@testable import Click

final class ServiceHeartbeatTests: XCTestCase {
    @MainActor func testHeartbeatContinuesInMenuAndModalLoops() {
        var ticks = 0
        let timer = ServiceHeartbeat.schedule(interval: 0.01) { ticks += 1 }
        defer { timer.invalidate() }
        for mode: RunLoop.Mode in [.eventTracking, .modalPanel] {
            let previous = ticks
            let deadline = Date().addingTimeInterval(0.15)
            while ticks == previous && Date() < deadline {
                RunLoop.main.run(mode: mode, before: deadline)
            }
            XCTAssertGreaterThan(ticks, previous, "Heartbeat stopped in \(mode)")
        }
        timer.invalidate()
        let stopped = ticks
        RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.03))
        XCTAssertEqual(ticks, stopped)
    }
}

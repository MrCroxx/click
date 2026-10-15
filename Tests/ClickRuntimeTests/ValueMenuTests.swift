import AppKit
import XCTest
@testable import Click

final class ValueMenuTests: XCTestCase {
    @MainActor func testNativeMenuDispatchesNestedSelectionAndUpdatedActions() {
        // swift test has no application entry point. NSMenu dispatches actions
        // through NSApp, so initialize it explicitly on the main actor.
        _ = NSApplication.shared
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        let coordinator = ValueMenu.Coordinator()
        var selection = "Caps Lock"
        ValueMenu(title: selection, entries: [
            .init(title: "Letters", children: [.init(title: "A", action: { selection = "A" })])
        ]).update(button, coordinator: coordinator)
        let submenu = button.menu!.item(at: 1)!.submenu!
        submenu.performActionForItem(at: 0)
        XCTAssertEqual(selection, "A")
        ValueMenu(title: selection, entries: [
            .init(title: "Key", action: { selection = "Key" }),
            .init(title: "Macro", action: { selection = "Macro" })
        ]).update(button, coordinator: coordinator)
        XCTAssertEqual(button.title, "A")
        button.menu!.performActionForItem(at: 2)
        XCTAssertEqual(selection, "Macro")
    }
    @MainActor func testRefreshDoesNotDismissTrackingMenuOrReleaseItsAction() async {
        // swift test has no application entry point. NSMenu dispatches actions
        // through NSApp, so initialize it explicitly on the main actor.
        _ = NSApplication.shared
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        let coordinator = ValueMenu.Coordinator()
        var selected = false
        ValueMenu(title: "Key", entries: [.init(title: "Macro", action: { selected = true })])
            .update(button, coordinator: coordinator)
        let openMenu = button.menu!
        coordinator.menuWillOpen(openMenu)
        for _ in 0..<5 {
            ValueMenu(title: "Updated", entries: []).update(button, coordinator: coordinator)
        }
        XCTAssertTrue(button.menu === openMenu)
        XCTAssertEqual(button.title, "Key")
        openMenu.performActionForItem(at: 1)
        XCTAssertTrue(selected)
        coordinator.menuDidClose(openMenu)
        await Task.yield()
        XCTAssertFalse(coordinator.tracking)
    }

}

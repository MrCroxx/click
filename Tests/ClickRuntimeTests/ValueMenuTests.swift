import AppKit
import XCTest
@testable import Click

final class ValueMenuTests: XCTestCase {
    @MainActor func testNativeMenuDispatchesNestedSelectionAndUpdatedActions() {
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
}

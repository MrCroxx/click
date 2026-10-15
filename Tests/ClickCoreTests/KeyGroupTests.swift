import XCTest
@testable import ClickCore

final class KeyGroupTests: XCTestCase {
    func testEverySupportedKeyAppearsInExactlyOneGroup() {
        for allowsFn in [false, true] {
            let grouped = KeyCatalog.groups(allowsFn: allowsFn).flatMap(\.keys).map(\.id)
            let expected = (allowsFn ? KeyCatalog.outputKeys : KeyCatalog.keys).map(\.id)
            XCTAssertEqual(grouped.sorted(), expected.sorted())
            XCTAssertEqual(Set(grouped).count, grouped.count)
        }
    }
    func testFunctionKeysAndOutputOnlyFn() {
        XCTAssertEqual(KeyCatalog.groups().first { $0.id == "Function Keys" }?.keys.map(\.name), (1...20).map { "F\($0)" })
        XCTAssertFalse(KeyCatalog.groups().flatMap(\.keys).contains { $0.id == KeyCatalog.fnOutputID })
        XCTAssertTrue(KeyCatalog.groups(allowsFn: true).first { $0.id == "Modifiers" }!.keys.contains { $0.id == KeyCatalog.fnOutputID })
    }
}

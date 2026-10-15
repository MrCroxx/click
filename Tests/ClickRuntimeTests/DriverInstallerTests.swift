import XCTest
import ClickCore
@testable import Click

final class DriverInstallerTests: XCTestCase {
    func testRejectsNonPackageBeforeLaunchingInstaller() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not an installer".utf8).write(to: file)
        do { try await DriverInstaller.verifyPackage(file); XCTFail("Untrusted input accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("verification failed")) }
    }
    func testOfficialPackageSignatureWhenFixtureProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["CLICK_DRIVER_TEST_PACKAGE"] else {
            throw XCTSkip("Set CLICK_DRIVER_TEST_PACKAGE to verify a downloaded official package without installing it.")
        }
        try await DriverInstaller.verifyPackage(URL(fileURLWithPath: path))
    }
    func testProcessResultIncludesExitStatus() async throws {
        let result = try await DriverInstaller.run("/usr/bin/false", [])
        XCTAssertNotEqual(result.code, 0)
    }
    @MainActor func testRejectsUnrelatedApplicationSignature() {
        XCTAssertThrowsError(try DriverInstaller.verifyApplication(at: "/System/Applications/TextEdit.app", identifier: "org.pqrs.Karabiner-VirtualHIDDevice-Manager"))
    }
}

import XCTest
@testable import ClickCore

final class DriverPackageTests: XCTestCase {
    func testOnlyKnownProtocolCompatiblePackagesAreAccepted() {
        XCTAssertTrue(DriverPackage.supports("8.5.0"))
        XCTAssertTrue(DriverPackage.supports("8.6.0"))
        for version in [nil, "8.4.0", "8.7.0", "9.0.0", ""] as [String?] {
            XCTAssertFalse(DriverPackage.supports(version))
        }
    }
    func testTruncatedAndTamperedDownloadsAreRejected() {
        XCTAssertThrowsError(try DriverPackage.verify(Data()))
        XCTAssertThrowsError(try DriverPackage.verify(Data(repeating: 0, count: DriverPackage.byteCount)))
    }
    func testDownloadIsPinnedToOfficialVersion() {
        XCTAssertEqual(DriverPackage.downloadURL.host, "github.com")
        XCTAssertTrue(DriverPackage.downloadURL.path.contains("/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v8.6.0/"))
        XCTAssertEqual(DriverPackage.sha256.count, 64)
    }
}

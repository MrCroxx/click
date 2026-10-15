import XCTest
@testable import ClickCore

final class ConfigurationTests: XCTestCase {
    func fixture() -> Configuration {
        var config = Configuration()
        let macro = Macro(name: "Open Notes", steps: [MacroStep(kind: .shortcut)])
        config.macros = [macro]
        var profile = DeviceProfile(name: "Keyboard", device: .init(vendor: 1, product: 2, location: 3))
        profile.enabled = true
        var key = KeyBinding(); key.source = 57; key.destination = 41
        var trigger = KeyBinding(); trigger.source = 58; trigger.kind = .macro; trigger.macroID = macro.id
        profile.bindings = [key, trigger]; config.profiles = [profile]
        return config
    }
    func testRoundTrip() throws {
        let original = fixture()
        XCTAssertEqual(try Configuration.decode(original.encoded()), original)
    }
    func testDuplicateSourceRejected() {
        var config = fixture(); config.profiles[0].bindings[1].source = 57
        XCTAssertThrowsError(try config.validate())
    }
    func testMissingMacroRejectedEvenWhenDisabled() {
        var config = fixture(); config.macros = []; config.profiles[0].enabled = false
        XCTAssertThrowsError(try config.validate())
    }
    func testModifierMacroRejected() {
        var config = fixture(); config.profiles[0].bindings[1].source = 227
        XCTAssertThrowsError(try config.validate())
    }
    func testUnknownVersionRejected() throws {
        var config = fixture(); config.version = 2
        XCTAssertThrowsError(try Configuration.decode(JSONEncoder().encode(config)))
    }
    func testBadStepRejected() {
        var config = fixture()
        var delay = MacroStep(kind: .delay); delay.milliseconds = -1
        config.macros[0].steps = [delay]
        XCTAssertThrowsError(try config.validate())
        delay.milliseconds = 60001; config.macros[0].steps = [delay]
        XCTAssertThrowsError(try config.validate())
        config.macros[0].steps = []
        XCTAssertThrowsError(try config.validate())
    }
    func testDuplicateProfileIdentitiesRejected() {
        var config = fixture(); var profile = config.profiles[0]; profile.id = UUID()
        config.profiles.append(profile)
        XCTAssertThrowsError(try config.validate())
    }
    func testSerialSurvivesPortChange() {
        let a = DeviceIdentity(vendor: 1, product: 2, serial: "test", location: 1)
        let b = DeviceIdentity(vendor: 1, product: 2, serial: "test", location: 9)
        XCTAssertTrue(a.matches(b))
        XCTAssertFalse(DeviceIdentity(vendor: 1, product: 2, location: 1).matches(b))
    }
    func testAtomicStoreDoesNotReplaceValidConfigOnFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("config.json"))
        let valid = fixture(); try store.save(valid)
        var invalid = valid; invalid.version = 99
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), valid)
    }
    func testCorruptConfigNotSilentlyReset() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("bad json".utf8).write(to: file)
        XCTAssertThrowsError(try ConfigurationStore(url: file).load())
    }
    func testKeyCatalogHasUniqueUsagesAndCorrectFunctionSlots() {
        XCTAssertEqual(Set(KeyCatalog.keys.map(\.id)).count, KeyCatalog.keys.count)
        XCTAssertEqual(KeyCatalog.virtual(104), 105)
        XCTAssertEqual(KeyCatalog.virtual(111), 90)
        XCTAssertEqual(KeyCatalog.virtual(227), 55)
    }
    func testOversizedImportRejected() {
        XCTAssertThrowsError(try Configuration.decode(Data(repeating: 32, count: 2_000_001)))
    }
}

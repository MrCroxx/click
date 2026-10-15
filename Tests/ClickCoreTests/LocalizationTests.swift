import XCTest
@testable import ClickCore

final class LocalizationTests: XCTestCase {
    func testEveryLanguageHasTheSameKeysAndFormatArguments() throws {
        let english = try XCTUnwrap(L10n.translations["en"])
        XCTAssertGreaterThan(english.count, 100)
        let expression = try NSRegularExpression(pattern: "%[@df]")
        func placeholders(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }
        }
        for language in AppLanguage.allCases {
            let values = try XCTUnwrap(L10n.translations[language.rawValue])
            XCTAssertEqual(Set(values.keys), Set(english.keys))
            for (key, value) in values {
                XCTAssertFalse(value.isEmpty, key)
                XCTAssertEqual(placeholders(key), placeholders(value), key)
            }
        }
    }
    func testLanguageLookupAndFallback() {
        XCTAssertEqual(L10n.text("Mappings", language: .english), "Mappings")
        XCTAssertEqual(L10n.text("Mappings", language: .simplifiedChinese), "按键映射")
        XCTAssertEqual(L10n.text("External error", language: .simplifiedChinese), "External error")
    }
    func testDefaultIsEnglishAndSavedChoiceIsRespected() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: L10n.preferenceKey)
        defer {
            if let original { defaults.set(original, forKey: L10n.preferenceKey) }
            else { defaults.removeObject(forKey: L10n.preferenceKey) }
        }
        defaults.removeObject(forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.language, .english)
        defaults.set("zh-Hans", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.language, .simplifiedChinese)
        XCTAssertEqual(ClickError("Invalid source key.").localizedDescription, "输入键无效。")
        defaults.set("unknown", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.language, .english)
    }
}

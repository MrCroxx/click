import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", simplifiedChinese = "zh-Hans"
    public var id: String { rawValue }
    public var name: String { self == .english ? "English" : "简体中文" }
}

public enum L10n {
    public static let preferenceKey = "interfaceLanguage"
    public static let didChange = Notification.Name("ClickInterfaceLanguageChanged")
    public static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "en") ?? .english
    }
    public static let translations: [String: [String: String]] = {
        // 不同 SwiftPM 版本的 Bundle.module 搜索路径不同，优先定位安装后的应用资源。
        let embedded = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("Click_ClickCore.bundle")) }
        let resources = embedded ?? Bundle.module
        guard let url = resources.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            assertionFailure("Missing localization resource")
            return [:]
        }
        return result
    }()
    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        translations[(language ?? self.language).rawValue]?[key] ?? key
    }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

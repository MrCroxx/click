import Foundation
public struct ConfigurationStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        return try Configuration.decode(Data(contentsOf: url))
    }
    public func save(_ configuration: Configuration) throws {
        let data = try configuration.encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

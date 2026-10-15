import AppKit
import Security
import ServiceManagement
import IOKit
import ClickCore

/// Installation remains in Apple's Installer and the signed pqrs extension
/// manager. Click never asks for a password or runs an elevated shell.
@MainActor
final class DriverInstaller: ObservableObject {
    @Published private(set) var version: String?
    @Published private(set) var extensionActive = false
    @Published private(set) var serviceAvailable = false
    @Published private(set) var serviceStatus = SMAppService.Status.notRegistered
    @Published private(set) var busy = false
    @Published private(set) var checking = false
    @Published private(set) var activity: String?
    @Published var error: String?
    private var operation: Task<Void, Never>?
    var prepareChange: () throws -> Void = {}
    var supported: Bool { DriverPackage.supports(version) }
    var packageStatus: String { version.map { DriverPackage.supports($0) ? "Installed" : "Unsupported version" } ?? "Not installed" }

    func refresh() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            let daemonInfo = URL(fileURLWithPath: DriverPackage.daemonPath).appendingPathComponent("Contents/Info.plist")
            let managerInfo = URL(fileURLWithPath: DriverPackage.managerPath).appendingPathComponent("Contents/Info.plist")
            let daemon = NSDictionary(contentsOf: daemonInfo)?["CFBundleShortVersionString"] as? String
            let manager = NSDictionary(contentsOf: managerInfo)?["CFBundleShortVersionString"] as? String
            version = daemon == manager ? daemon : nil
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("org_pqrs_Karabiner_DriverKit_VirtualHIDDeviceRoot"))
            extensionActive = service != 0
            if service != 0 { IOObjectRelease(service) }
            serviceStatus = SMAppService.daemon(plistName: DriverPackage.daemonPlist).status
            // Read launchd's actual shared job, rather than assuming an installed
            // package or another app's registration means its daemon is running.
            let result = try? await Self.run("/bin/launchctl", ["print", "system/" + DriverPackage.daemonPlist.replacingOccurrences(of: ".plist", with: "")])
            serviceAvailable = result?.code == 0 && result?.output.contains("state = running") == true
        }
    }

    func install() {
        guard !busy else { return }
        busy = true; error = nil; activity = "Downloading driver…"
        operation = Task {
            defer { busy = false; operation = nil; refresh() }
            do {
                let session = URLSession(configuration: {
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
                    return config
                }())
                defer { session.invalidateAndCancel() }
                let (download, response) = try await session.download(from: DriverPackage.downloadURL)
                defer { try? FileManager.default.removeItem(at: download) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClickError("The driver download failed. Try again.") }
                try Task.checkCancellation()
                activity = "Verifying driver…"
                try await Self.verifyPackage(download)
                try Task.checkCancellation()
                // A unique directory avoids replacing a package still open in Installer.
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.mrcroxx.click/DriverInstallers/" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let package = directory.appendingPathComponent(DriverPackage.fileName)
                try FileManager.default.copyItem(at: download, to: package)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: package.path)
                try prepareChange()
                guard NSWorkspace.shared.open(package) else { throw ClickError("Unable to open the macOS Installer.") }
                activity = "Complete installation in Installer, then activate the driver."
            } catch is CancellationError { activity = nil }
            catch let error as URLError where error.code == .cancelled { activity = nil }
            catch { self.error = error.localizedDescription; activity = nil }
        }
    }
    func cancelDownload() { operation?.cancel() }

    func activate() {
        guard supported, !busy else { return }
        busy = true; error = nil; activity = "Approve the driver in System Settings if requested."
        operation = Task {
            defer { busy = false; operation = nil; refresh() }
            do {
                try prepareChange()
                try Self.verifyApplication(at: DriverPackage.managerPath, identifier: "org.pqrs.Karabiner-VirtualHIDDevice-Manager")
                let result = try await Self.run(DriverPackage.managerPath + "/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager", ["activate"], timeout: 120)
                guard result.code == 0 else { throw ClickError("Driver activation did not complete. Check System Settings and try again.") }
                activity = result.output.contains("requires reboot") ? "Restart your Mac to finish activating the driver." : nil
            } catch { self.error = error.localizedDescription }
        }
    }
    func enableService() {
        guard supported, !busy, !serviceAvailable else { return }
        error = nil
        let service = SMAppService.daemon(plistName: DriverPackage.daemonPlist)
        do {
            try Self.verifyApplication(at: DriverPackage.daemonPath, identifier: "org.pqrs.Karabiner-VirtualHIDDevice-Daemon")
            try service.register()
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else { self.error = error.localizedDescription }
        }
        refresh()
    }
    static func verifyApplication(at path: String, identifier: String) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(DriverPackage.teamID)\" and identifier \"\(identifier)\""
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw ClickError("The installed driver signature could not be verified. Reinstall the official driver.")
        }
    }
    nonisolated static func verifyPackage(_ url: URL) async throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == DriverPackage.byteCount else { throw ClickError("Driver download verification failed. Try again.") }
        try DriverPackage.verify(Data(contentsOf: url))
        let result = try await run("/usr/sbin/pkgutil", ["--check-signature", url.path])
        guard result.code == 0,
              result.output.contains("Developer ID Installer: Fumihiko Takayama (\(DriverPackage.teamID))") else {
            throw ClickError("The driver installer signature could not be verified.")
        }
    }
    struct Result: Sendable { let code: Int32; let output: String }
    nonisolated static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) async throws -> Result {
        try await Task.detached {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ClickError("Unable to create a temporary file.") }
            defer { try? FileManager.default.removeItem(at: file) }
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
            process.standardOutput = output; process.standardError = output
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            if process.isRunning {
                process.terminate()
                throw ClickError("The operation timed out. Check System Settings and try again.")
            }
            let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
            return Result(code: process.terminationStatus, output: String(data: try input.read(upToCount: 65536) ?? Data(), encoding: .utf8) ?? "")
        }.value
    }
}

import Foundation
import ServiceManagement

struct LaunchAtLoginServiceEnvironment {
    var serviceManagementStatus: () -> SMAppService.Status
    var registerMainApp: () throws -> Void
    var unregisterMainApp: () throws -> Void
    var plistURL: URL
    var executableURL: () -> URL?
    var runLaunchctl: ([String]) throws -> Void
    var userID: () -> uid_t
    var fileManager: FileManager
    var replaceItemAt: (URL, URL) throws -> Void
}

enum LaunchAtLoginService {
    private static let launchAgentIdentifier = "top.ygsgdbd.ListenBar"
    private static let launchAgentPlistName = "\(launchAgentIdentifier).plist"
    private static let launchAgentStagingDirectoryName = ".\(launchAgentIdentifier).staging"

    private static var liveEnvironment: LaunchAtLoginServiceEnvironment {
        LaunchAtLoginServiceEnvironment(
            serviceManagementStatus: { SMAppService.mainApp.status },
            registerMainApp: { try SMAppService.mainApp.register() },
            unregisterMainApp: { try SMAppService.mainApp.unregister() },
            plistURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
                .appendingPathComponent(launchAgentPlistName),
            executableURL: { Bundle.main.executableURL },
            runLaunchctl: runLaunchctl,
            userID: { getuid() },
            fileManager: .default,
            replaceItemAt: { originalItemURL, newItemURL in
                _ = try FileManager.default.replaceItemAt(
                    originalItemURL,
                    withItemAt: newItemURL,
                )
            },
        )
    }

    static var status: LaunchAtLoginStatus {
        status(environment: liveEnvironment)
    }

    static func status(environment: LaunchAtLoginServiceEnvironment) -> LaunchAtLoginStatus {
        let fallbackEnabled = fallbackLaunchAgentIsEnabled(environment: environment)

        switch environment.serviceManagementStatus() {
        case .enabled:
            if fallbackEnabled {
                removeFallbackLaunchAgent(environment: environment)
            }
            return .enabled
        case .notRegistered:
            return fallbackEnabled ? .enabled : .disabled
        case .requiresApproval:
            return fallbackEnabled ? .enabled : .requiresApproval
        case .notFound:
            return fallbackEnabled ? .enabled : .unavailable
        @unknown default:
            return fallbackEnabled ? .enabled : .unavailable
        }
    }

    static func setLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginStatus {
        setLaunchAtLogin(enabled, environment: liveEnvironment)
    }

    static func setLaunchAtLogin(
        _ enabled: Bool,
        environment: LaunchAtLoginServiceEnvironment,
    ) -> LaunchAtLoginStatus {
        if enabled {
            enableLaunchAtLogin(environment: environment)
        } else {
            disableLaunchAtLogin(environment: environment)
        }

        return status(environment: environment)
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private extension LaunchAtLoginService {
    static func enableLaunchAtLogin(environment: LaunchAtLoginServiceEnvironment) {
        if environment.serviceManagementStatus() == .enabled {
            removeFallbackLaunchAgent(environment: environment)
            return
        }

        do {
            try environment.registerMainApp()
            if environment.serviceManagementStatus() == .enabled {
                removeFallbackLaunchAgent(environment: environment)
                return
            }
        } catch {
            print("Failed to register ListenBar as a login item: \(error.localizedDescription)")
            if environment.serviceManagementStatus() == .enabled {
                removeFallbackLaunchAgent(environment: environment)
                return
            }
        }

        do {
            try installFallbackLaunchAgent(environment: environment)
        } catch {
            print("Failed to install ListenBar LaunchAgent: \(error.localizedDescription)")
        }
    }

    static func disableLaunchAtLogin(environment: LaunchAtLoginServiceEnvironment) {
        do {
            try environment.unregisterMainApp()
        } catch {
            print("Failed to unregister ListenBar login item: \(error.localizedDescription)")
        }

        removeFallbackLaunchAgent(environment: environment)
    }

    static func fallbackLaunchAgentIsEnabled(
        environment: LaunchAtLoginServiceEnvironment,
    ) -> Bool {
        guard
            let executableURL = environment.executableURL(),
            let arguments = fallbackProgramArguments(
                plistURL: environment.plistURL,
                fileManager: environment.fileManager,
            ),
            let executablePath = arguments.first
        else {
            return false
        }

        return normalizedPath(executablePath) == normalizedPath(executableURL.path)
    }

    static func fallbackProgramArguments(
        plistURL: URL,
        fileManager: FileManager,
    ) -> [String]? {
        guard
            fileManager.fileExists(atPath: plistURL.path),
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil,
            ) as? [String: Any]
        else {
            return nil
        }

        return plist["ProgramArguments"] as? [String]
    }

    static func installFallbackLaunchAgent(
        environment: LaunchAtLoginServiceEnvironment,
    ) throws {
        guard let executableURL = environment.executableURL() else {
            throw NSError(
                domain: "ListenBar.LaunchAtLogin",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot resolve ListenBar executable path"],
            )
        }

        try environment.fileManager.createDirectory(
            at: environment.plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let stagingDirectoryURL = environment.plistURL.deletingLastPathComponent()
            .appendingPathComponent(launchAgentStagingDirectoryName, isDirectory: true)
        let stagingPlistURL = stagingDirectoryURL.appendingPathComponent(launchAgentPlistName)
        try environment.fileManager.createDirectory(
            at: stagingDirectoryURL,
            withIntermediateDirectories: true,
        )

        let plist: [String: Any] = [
            "Label": launchAgentIdentifier,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0,
        )
        try data.write(to: stagingPlistURL, options: .atomic)

        let domain = "gui/\(environment.userID())"
        let serviceTarget = "\(domain)/\(launchAgentIdentifier)"
        try? environment.runLaunchctl(["bootout", serviceTarget])
        do {
            try environment.runLaunchctl(["bootstrap", domain, stagingPlistURL.path])
            try commitFallbackLaunchAgent(
                stagingPlistURL: stagingPlistURL,
                environment: environment,
            )
        } catch {
            cleanUpFailedFallbackInstallation(
                stagingDirectoryURL: stagingDirectoryURL,
                serviceTarget: serviceTarget,
                environment: environment,
            )
            throw error
        }

        removeStagingDirectory(
            stagingDirectoryURL,
            fileManager: environment.fileManager,
        )
    }

    static func removeFallbackLaunchAgent(environment: LaunchAtLoginServiceEnvironment) {
        let serviceTarget = "gui/\(environment.userID())/\(launchAgentIdentifier)"
        try? environment.runLaunchctl(["bootout", serviceTarget])
        try? environment.fileManager.removeItem(at: environment.plistURL)
    }

    static func commitFallbackLaunchAgent(
        stagingPlistURL: URL,
        environment: LaunchAtLoginServiceEnvironment,
    ) throws {
        if environment.fileManager.fileExists(atPath: environment.plistURL.path) {
            try environment.replaceItemAt(
                environment.plistURL,
                stagingPlistURL,
            )
        } else {
            try environment.fileManager.moveItem(
                at: stagingPlistURL,
                to: environment.plistURL,
            )
        }
    }

    static func cleanUpFailedFallbackInstallation(
        stagingDirectoryURL: URL,
        serviceTarget: String,
        environment: LaunchAtLoginServiceEnvironment,
    ) {
        do {
            try environment.runLaunchctl(["bootout", serviceTarget])
        } catch {
            print("Failed to clean up ListenBar LaunchAgent service: \(error.localizedDescription)")
        }

        removeStagingDirectory(
            stagingDirectoryURL,
            fileManager: environment.fileManager,
        )

        if environment.fileManager.fileExists(atPath: environment.plistURL.path) {
            do {
                try environment.fileManager.removeItem(at: environment.plistURL)
            } catch {
                print("Failed to remove ListenBar LaunchAgent plist after rollback: \(error.localizedDescription)")
            }
        }
    }

    static func removeStagingDirectory(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            print("Failed to remove ListenBar LaunchAgent staging files: \(error.localizedDescription)")
        }
    }

    static func runLaunchctl(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ListenBar.LaunchAtLogin",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "launchctl \(arguments.joined(separator: " ")) failed",
                ],
            )
        }
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

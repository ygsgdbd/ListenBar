import Foundation
@testable import ListenBar
import ServiceManagement
import XCTest

final class LaunchAtLoginServiceTests: XCTestCase {
    func testStatusUsesFallbackLaunchAgentWhenExecutableMatches() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)

        let status = LaunchAtLoginService.status(environment: fixture.environment())

        XCTAssertEqual(status, .enabled)
    }

    func testStatusIgnoresFallbackLaunchAgentWithStaleExecutablePath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(
            executablePath: "/Applications/OldListenBar.app/Contents/MacOS/ListenBar",
        )

        let status = LaunchAtLoginService.status(environment: fixture.environment())

        XCTAssertEqual(status, .disabled)
    }

    func testStatusPreservesServiceManagementApprovalAndUnavailableStates() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        XCTAssertEqual(
            LaunchAtLoginService.status(
                environment: fixture.environment(serviceManagementStatus: { .requiresApproval }),
            ),
            .requiresApproval,
        )
        XCTAssertEqual(
            LaunchAtLoginService.status(
                environment: fixture.environment(serviceManagementStatus: { .notFound }),
            ),
            .unavailable,
        )
    }

    func testSetLaunchAtLoginCommitsFallbackWhenServiceManagementRequiresApproval() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .requiresApproval },
                runLaunchctl: { launchctlCalls.append($0) },
            ),
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
            ],
        )
        XCTAssertEqual(try fixture.programArguments(), [fixture.executableURL.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectoryURL.path))
    }

    func testSetLaunchAtLoginLeavesNoFilesWhenFirstInstallationBootstrapFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .requiresApproval },
                runLaunchctl: { arguments in
                    launchctlCalls.append(arguments)
                    if arguments.first == "bootstrap" || arguments.first == "bootout" {
                        throw NSError(domain: "test", code: 1)
                    }
                },
            ),
        )

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
                ["bootout", fixture.serviceTarget],
            ],
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectoryURL.path))
    }

    func testSetLaunchAtLoginIgnoresResidualStagingWhenBootstrapAndDeletionFail() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fileManager = TestFileManager()
        fileManager.removeItemErrorURL = fixture.stagingDirectoryURL
        var launchctlCalls: [[String]] = []

        let environment = fixture.environment(
            serviceManagementStatus: { .requiresApproval },
            runLaunchctl: { arguments in
                launchctlCalls.append(arguments)
                if arguments.first == "bootstrap" {
                    throw NSError(domain: "bootstrap", code: 1)
                }
            },
            fileManager: fileManager,
        )
        let status = LaunchAtLoginService.setLaunchAtLogin(true, environment: environment)

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertEqual(LaunchAtLoginService.status(environment: environment), .requiresApproval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.stagingPlistURL.path))
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
                ["bootout", fixture.serviceTarget],
            ],
        )
    }

    func testSetLaunchAtLoginRollsBackWhenCommittingStagingFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fileManager = TestFileManager()
        fileManager.moveItemError = NSError(domain: "move", code: 1)
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .requiresApproval },
                runLaunchctl: { launchctlCalls.append($0) },
                fileManager: fileManager,
            ),
        )

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectoryURL.path))
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
                ["bootout", fixture.serviceTarget],
            ],
        )
    }

    func testSetLaunchAtLoginRollsBackWhenReplacingExistingPlistFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(
            executablePath: fixture.executableURL.path,
            additionalProperties: ["PreservedValue": "original"],
        )
        let originalPlistData = try Data(contentsOf: fixture.plistURL)
        let fileManager = TestFileManager()
        var launchctlCalls: [[String]] = []

        let environment = fixture.environment(
            serviceManagementStatus: { .requiresApproval },
            runLaunchctl: { launchctlCalls.append($0) },
            fileManager: fileManager,
            replaceItemAt: { originalItemURL, _ in
                try fileManager.removeItem(at: originalItemURL)
                throw NSError(domain: "replace", code: 1)
            },
        )
        let status = LaunchAtLoginService.setLaunchAtLogin(true, environment: environment)

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), originalPlistData)
        XCTAssertEqual(try fixture.programArguments(), [fixture.executableURL.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectoryURL.path))
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.plistURL.path],
            ],
        )
    }

    func testSetLaunchAtLoginRestoresExistingPlistWhenStagingBootstrapFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let originalExecutablePath = "/Applications/OriginalListenBar.app/Contents/MacOS/ListenBar"
        try fixture.writeLaunchAgent(
            executablePath: originalExecutablePath,
            additionalProperties: ["PreservedValue": ["nested", "value"]],
        )
        let originalPlistData = try Data(contentsOf: fixture.plistURL)
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .requiresApproval },
                runLaunchctl: { arguments in
                    launchctlCalls.append(arguments)
                    if arguments == ["bootstrap", "gui/501", fixture.stagingPlistURL.path] {
                        throw NSError(domain: "bootstrap", code: 1)
                    }
                },
            ),
        )

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), originalPlistData)
        XCTAssertEqual(try fixture.programArguments(), [originalExecutablePath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectoryURL.path))
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.plistURL.path],
            ],
        )
    }

    func testSetLaunchAtLoginPreservesExistingPlistWhenRecoveryBootstrapFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(
            executablePath: fixture.executableURL.path,
            additionalProperties: ["PreservedValue": "original"],
        )
        let originalPlistData = try Data(contentsOf: fixture.plistURL)
        let fileManager = TestFileManager()
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .requiresApproval },
                runLaunchctl: { arguments in
                    launchctlCalls.append(arguments)
                    if arguments == ["bootstrap", "gui/501", fixture.plistURL.path] {
                        throw NSError(domain: "recovery-bootstrap", code: 1)
                    }
                },
                fileManager: fileManager,
                replaceItemAt: { originalItemURL, _ in
                    try fileManager.removeItem(at: originalItemURL)
                    throw NSError(domain: "replace", code: 1)
                },
            ),
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), originalPlistData)
        XCTAssertEqual(try fixture.programArguments(), [fixture.executableURL.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectoryURL.path))
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.stagingPlistURL.path],
                ["bootout", fixture.serviceTarget],
                ["bootstrap", "gui/501", fixture.plistURL.path],
            ],
        )
    }

    func testSetLaunchAtLoginFallsBackWhenRegistrationThrows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                registerMainApp: {
                    throw NSError(domain: "test", code: 1)
                },
            ),
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(try fixture.programArguments(), [fixture.executableURL.path])
    }

    func testStatusRemovesFallbackWhenServiceManagementBecomesEnabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.status(
            environment: fixture.environment(
                serviceManagementStatus: { .enabled },
                runLaunchctl: { launchctlCalls.append($0) },
            ),
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(launchctlCalls, [["bootout", fixture.serviceTarget]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
    }

    func testSetLaunchAtLoginTrueRemovesFallbackWhenServiceManagementIsEnabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .enabled },
                registerMainApp: {
                    XCTFail("Already-enabled ServiceManagement should not register again")
                },
                runLaunchctl: { launchctlCalls.append($0) },
            ),
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(launchctlCalls, [["bootout", fixture.serviceTarget]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
    }

    func testSetLaunchAtLoginFalseUnregistersAndRemovesFallbackLaunchAgent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeLaunchAgent(executablePath: fixture.executableURL.path)
        var didUnregister = false
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            false,
            environment: fixture.environment(
                unregisterMainApp: { didUnregister = true },
                runLaunchctl: { launchctlCalls.append($0) },
            ),
        )

        XCTAssertEqual(status, .disabled)
        XCTAssertTrue(didUnregister)
        XCTAssertEqual(launchctlCalls, [["bootout", fixture.serviceTarget]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
    }
}

private struct Fixture {
    let directoryURL: URL
    let plistURL: URL
    let stagingDirectoryURL: URL
    let stagingPlistURL: URL
    let executableURL = URL(fileURLWithPath: "/Applications/ListenBar.app/Contents/MacOS/ListenBar")
    let serviceTarget = "gui/501/top.ygsgdbd.ListenBar"

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenBarTests-\(UUID().uuidString)", isDirectory: true)
        plistURL = directoryURL.appendingPathComponent("top.ygsgdbd.ListenBar.plist")
        stagingDirectoryURL = directoryURL
            .appendingPathComponent(".top.ygsgdbd.ListenBar.staging", isDirectory: true)
        stagingPlistURL = stagingDirectoryURL
            .appendingPathComponent("top.ygsgdbd.ListenBar.plist")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func environment(
        serviceManagementStatus: @escaping () -> SMAppService.Status = { .notRegistered },
        registerMainApp: @escaping () throws -> Void = {},
        unregisterMainApp: @escaping () throws -> Void = {},
        runLaunchctl: @escaping ([String]) throws -> Void = { _ in },
        fileManager: FileManager = .default,
        replaceItemAt: ((URL, URL) throws -> Void)? = nil,
    ) -> LaunchAtLoginServiceEnvironment {
        LaunchAtLoginServiceEnvironment(
            serviceManagementStatus: serviceManagementStatus,
            registerMainApp: registerMainApp,
            unregisterMainApp: unregisterMainApp,
            plistURL: plistURL,
            executableURL: { executableURL },
            runLaunchctl: runLaunchctl,
            userID: { 501 },
            fileManager: fileManager,
            replaceItemAt: replaceItemAt ?? { originalItemURL, newItemURL in
                _ = try fileManager.replaceItemAt(
                    originalItemURL,
                    withItemAt: newItemURL,
                )
            },
        )
    }

    func writeLaunchAgent(
        executablePath: String,
        additionalProperties: [String: Any] = [:],
    ) throws {
        var plist: [String: Any] = [
            "Label": "top.ygsgdbd.ListenBar",
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
        ]
        for (key, value) in additionalProperties {
            plist[key] = value
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0,
        )
        try data.write(to: plistURL)
    }

    func programArguments() throws -> [String]? {
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
        )
        return plist["ProgramArguments"] as? [String]
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private final class TestFileManager: FileManager, @unchecked Sendable {
    var moveItemError: Error?
    var removeItemErrorURL: URL?

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let moveItemError {
            throw moveItemError
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == removeItemErrorURL?.standardizedFileURL {
            throw NSError(domain: "remove", code: 1)
        }
        try super.removeItem(at: URL)
    }
}

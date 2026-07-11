import Foundation
import ServiceManagement
import XCTest
@testable import ListenBar

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
            executablePath: "/Applications/OldListenBar.app/Contents/MacOS/ListenBar"
        )

        let status = LaunchAtLoginService.status(environment: fixture.environment())

        XCTAssertEqual(status, .disabled)
    }

    func testStatusPreservesServiceManagementApprovalAndUnavailableStates() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        XCTAssertEqual(
            LaunchAtLoginService.status(
                environment: fixture.environment(serviceManagementStatus: { .requiresApproval })
            ),
            .requiresApproval
        )
        XCTAssertEqual(
            LaunchAtLoginService.status(
                environment: fixture.environment(serviceManagementStatus: { .notFound })
            ),
            .unavailable
        )
    }

    func testSetLaunchAtLoginFallsBackWhenServiceManagementRequiresApproval() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var launchctlCalls: [[String]] = []

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                serviceManagementStatus: { .requiresApproval },
                runLaunchctl: { launchctlCalls.append($0) }
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(
            launchctlCalls,
            [
                ["bootout", "gui/501", fixture.plistURL.path],
                ["bootstrap", "gui/501", fixture.plistURL.path]
            ]
        )
        XCTAssertEqual(try fixture.programArguments(), [fixture.executableURL.path])
    }

    func testSetLaunchAtLoginFallsBackWhenRegistrationThrows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let status = LaunchAtLoginService.setLaunchAtLogin(
            true,
            environment: fixture.environment(
                registerMainApp: {
                    throw NSError(domain: "test", code: 1)
                }
            )
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
                runLaunchctl: { launchctlCalls.append($0) }
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(launchctlCalls, [["bootout", "gui/501", fixture.plistURL.path]])
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
                runLaunchctl: { launchctlCalls.append($0) }
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(launchctlCalls, [["bootout", "gui/501", fixture.plistURL.path]])
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
                runLaunchctl: { launchctlCalls.append($0) }
            )
        )

        XCTAssertEqual(status, .disabled)
        XCTAssertTrue(didUnregister)
        XCTAssertEqual(launchctlCalls, [["bootout", "gui/501", fixture.plistURL.path]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
    }
}

private struct Fixture {
    let directoryURL: URL
    let plistURL: URL
    let executableURL = URL(fileURLWithPath: "/Applications/ListenBar.app/Contents/MacOS/ListenBar")

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenBarTests-\(UUID().uuidString)", isDirectory: true)
        plistURL = directoryURL.appendingPathComponent("top.ygsgdbd.ListenBar.plist")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func environment(
        serviceManagementStatus: @escaping () -> SMAppService.Status = { .notRegistered },
        registerMainApp: @escaping () throws -> Void = {},
        unregisterMainApp: @escaping () throws -> Void = {},
        runLaunchctl: @escaping ([String]) throws -> Void = { _ in }
    ) -> LaunchAtLoginServiceEnvironment {
        LaunchAtLoginServiceEnvironment(
            serviceManagementStatus: serviceManagementStatus,
            registerMainApp: registerMainApp,
            unregisterMainApp: unregisterMainApp,
            plistURL: plistURL,
            executableURL: { executableURL },
            runLaunchctl: runLaunchctl,
            userID: { 501 },
            fileManager: .default
        )
    }

    func writeLaunchAgent(executablePath: String) throws {
        let plist: [String: Any] = [
            "Label": "top.ygsgdbd.ListenBar",
            "ProgramArguments": [executablePath],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)
    }

    func programArguments() throws -> [String]? {
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
        return plist["ProgramArguments"] as? [String]
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

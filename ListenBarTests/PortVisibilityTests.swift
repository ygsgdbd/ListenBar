@testable import ListenBar
import XCTest

final class PortVisibilityTests: XCTestCase {
    func testFilteringApplicationMatchesBundleIdentifierAcrossPIDChanges() {
        let ignoredPort = port(pid: 202, command: "Example Helper", port: 3000)
        let visiblePort = port(pid: 303, command: "node", port: 3001)
        let metadata = [
            ignoredPort.pid: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
            ),
            visiblePort.pid: PortProcessMetadata.executable(
                name: "node",
                path: "/Users/example/bin/node",
            ),
        ]
        let original = snapshot([ignoredPort, visiblePort], metadata: metadata)

        let visibility = PortVisibility(
            snapshot: original,
            ignoredProcesses: [
                .application(
                    bundleIdentifier: "com.example.App",
                    displayName: "Old Example Name",
                ),
            ],
        )

        XCTAssertEqual(visibility.visibleSnapshot.ports, [visiblePort])
        XCTAssertEqual(visibility.visibleSnapshot.processGroups.map(\.id), ["process:303:node"])
        XCTAssertEqual(visibility.visibleSnapshot.metadataByPID, [visiblePort.pid: metadata[visiblePort.pid]!])
    }

    func testFilteringExecutableMatchesPathButNotCommandName() {
        let ignoredPort = port(pid: 202, command: "node", port: 3000)
        let visiblePort = port(pid: 303, command: "node", port: 3001)
        let metadata = [
            ignoredPort.pid: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
            ),
            visiblePort.pid: PortProcessMetadata.executable(
                name: "node",
                path: "/Users/example/bin/node",
            ),
        ]
        let original = snapshot([ignoredPort, visiblePort], metadata: metadata)

        let visibility = PortVisibility(
            snapshot: original,
            ignoredProcesses: [
                .executable(
                    path: "/opt/homebrew/bin/node",
                    displayName: "node",
                ),
            ],
        )

        XCTAssertEqual(visibility.visibleSnapshot.ports, [visiblePort])
        XCTAssertEqual(visibility.visibleSnapshot.processGroups.map(\.id), ["process:303:node"])
        XCTAssertEqual(visibility.visibleSnapshot.metadataByPID, [visiblePort.pid: metadata[visiblePort.pid]!])
    }

    func testRestoringRulesPreservesSnapshotOrderMetadataAndClassification() {
        let systemPort = port(pid: 101, command: "system-listener")
        let userPort = port(pid: 202, command: "node", port: 3001)
        let metadata = [
            systemPort.pid: PortProcessMetadata.executable(
                name: "system-listener",
                path: "/usr/sbin/system-listener",
                classification: .systemOrOtherUser,
            ),
            userPort.pid: PortProcessMetadata.executable(name: "node", path: "/opt/homebrew/bin/node"),
        ]
        let original = snapshot([systemPort, userPort], metadata: metadata)
        let ignoredItem = IgnoredProcessItem.executable(path: "/usr/sbin/system-listener", displayName: "System")
        var visibility = PortVisibility(snapshot: original)

        for _ in 0 ..< 2 {
            visibility.apply(ignoredProcesses: [ignoredItem])
            XCTAssertEqual(visibility.visibleSnapshot.ports, [userPort])
            XCTAssertEqual(visibility.ignoredProcessGroupCount, 1)

            visibility.apply(ignoredProcesses: [])
            XCTAssertEqual(visibility.visibleSnapshot, original)
            XCTAssertEqual(visibility.ignoredProcessGroupCount, 0)
        }
    }

    func testExecutableRuleDoesNotHideApplicationUsingTheSameExecutable() {
        let appPort = port(pid: 101, command: "node")
        let cliPort = port(pid: 202, command: "node", port: 3001)
        let metadata = [
            appPort.pid: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
                executablePath: "/opt/homebrew/bin/node",
            ),
            cliPort.pid: PortProcessMetadata.executable(name: "node", path: "/opt/homebrew/bin/node"),
        ]
        let visibility = PortVisibility(
            snapshot: snapshot([appPort, cliPort], metadata: metadata),
            ignoredProcesses: [.executable(path: "/opt/homebrew/bin/node", displayName: "node")],
        )

        XCTAssertEqual(visibility.visibleSnapshot.ports, [appPort])
        XCTAssertEqual(visibility.visibleSnapshot.metadataByPID, [appPort.pid: metadata[appPort.pid]!])
        XCTAssertEqual(visibility.visibleSnapshot.processGroups.map(\.id), ["app:com.example.App"])
        XCTAssertEqual(visibility.ignoredProcessGroupCount, 1)
    }

    private func snapshot(
        _ ports: [PortEntry],
        metadata: [Int: PortProcessMetadata] = [:],
    ) -> PortScanSnapshot {
        PortScanSnapshot(
            ports: ports,
            metadataByPID: metadata,
            processGroups: PortProcessGroupingService.groups(
                for: ports,
                metadataByPID: metadata,
            ),
        )
    }

    private func port(
        pid: Int,
        command: String,
        port: Int = 3000,
    ) -> PortEntry {
        PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: port,
            pid: pid,
            command: command,
            user: "501",
        )
    }
}

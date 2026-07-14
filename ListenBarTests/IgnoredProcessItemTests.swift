@testable import ListenBar
import XCTest

final class IgnoredProcessItemTests: XCTestCase {
    func testCreatesApplicationIdentityFromBundleIdentifier() throws {
        let port = self.port(pid: 101, command: "Example")
        let metadata = [
            port.pid: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
            ),
        ]
        let group = try XCTUnwrap(snapshot([port], metadata: metadata).processGroups.first)

        XCTAssertEqual(
            IgnoredProcessItem(group: group, metadataByPID: metadata),
            .application(
                bundleIdentifier: "com.example.App",
                displayName: "Example",
            ),
        )
    }

    func testCreatesExecutableIdentityFromPath() throws {
        let port = self.port(pid: 101, command: "node")
        let metadata = [
            port.pid: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
            ),
        ]
        let group = try XCTUnwrap(snapshot([port], metadata: metadata).processGroups.first)

        XCTAssertEqual(
            IgnoredProcessItem(group: group, metadataByPID: metadata),
            .executable(
                path: "/opt/homebrew/bin/node",
                displayName: "node",
            ),
        )
    }

    func testCannotIgnoreProcessWithoutExecutablePath() throws {
        let port = self.port(pid: 101, command: "node")
        let group = try XCTUnwrap(snapshot([port]).processGroups.first)

        XCTAssertNil(IgnoredProcessItem(group: group, metadataByPID: [:]))
    }

    func testCannotIgnoreProcessWithoutAbsoluteExecutablePath() throws {
        for path in ["", " ", "node"] {
            let port = self.port(pid: 101, command: "node")
            let metadata = [
                port.pid: PortProcessMetadata.executable(
                    name: "node",
                    path: path,
                ),
            ]
            let group = try XCTUnwrap(snapshot([port], metadata: metadata).processGroups.first)

            XCTAssertNil(IgnoredProcessItem(group: group, metadataByPID: metadata))
        }
    }

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

        let filtered = original.filtering(
            ignoredProcesses: [
                .application(
                    bundleIdentifier: "com.example.App",
                    displayName: "Old Example Name",
                ),
            ],
        )

        XCTAssertEqual(filtered.ports, [visiblePort])
        XCTAssertEqual(filtered.processGroups.map(\.id), ["process:303:node"])
        XCTAssertEqual(filtered.metadataByPID, [visiblePort.pid: metadata[visiblePort.pid]!])
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

        let filtered = original.filtering(
            ignoredProcesses: [
                .executable(
                    path: "/opt/homebrew/bin/node",
                    displayName: "node",
                ),
            ],
        )

        XCTAssertEqual(filtered.ports, [visiblePort])
        XCTAssertEqual(filtered.processGroups.map(\.id), ["process:303:node"])
        XCTAssertEqual(filtered.metadataByPID, [visiblePort.pid: metadata[visiblePort.pid]!])
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

final class IgnoredProcessMenuLabelsTests: XCTestCase {
    func testUsesSpecificIgnoreTitlesForAppsAndProcesses() {
        XCTAssertEqual(
            IgnoredProcessMenuLabels.ignoreTitle(isApplication: true),
            "忽略此 App",
        )
        XCTAssertEqual(
            IgnoredProcessMenuLabels.ignoreTitle(isApplication: false),
            "忽略此进程",
        )
    }

    func testFormatsIgnoredItemsMenuCount() {
        XCTAssertEqual(
            IgnoredProcessMenuLabels.menuTitle(count: 2),
            "已忽略项目（2）",
        )
        XCTAssertEqual(
            IgnoredProcessMenuLabels.restoreHint,
            "点击项目以恢复显示",
        )
    }

    func testUsesExplicitEmptyStateWhenAllListenersAreIgnored() {
        XCTAssertEqual(
            IgnoredProcessMenuLabels.emptyState(hasIgnoredMatches: true),
            "所有监听项目均已忽略",
        )
        XCTAssertEqual(
            IgnoredProcessMenuLabels.emptyState(hasIgnoredMatches: false),
            "未发现监听端口",
        )
    }
}

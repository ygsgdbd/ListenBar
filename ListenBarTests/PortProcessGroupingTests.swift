import XCTest
@testable import ListenBar

final class PortProcessGroupingTests: XCTestCase {
    func testGroupsPortsByAppMetadataWhenAvailable() {
        let firstPort = port(port: 3001, pid: 10, command: "Example Helper")
        let secondPort = port(port: 3000, pid: 11, command: "Example Helper")

        let groups = PortProcessGroupingService.groups(
            for: [firstPort, secondPort],
            metadataByPID: [
                10: PortProcessMetadata(
                    bundleIdentifier: "com.example.App",
                    name: "Example",
                    path: "/Applications/Example.app"
                ),
                11: PortProcessMetadata(
                    bundleIdentifier: "com.example.App",
                    name: "Example",
                    path: "/Applications/Example.app"
                )
            ]
        )

        XCTAssertEqual(
            groups,
            [
                PortProcessGroup(
                    id: "app:com.example.App",
                    displayName: "Example",
                    subtitle: "3000, 3001",
                    icon: .application(path: "/Applications/Example.app"),
                    ports: [secondPort, firstPort]
                )
            ]
        )
    }

    func testFallsBackToPIDGroupingForCommandLineProcesses() {
        let firstPort = port(port: 3000, pid: 10, command: "node")
        let secondPort = port(port: 3001, pid: 11, command: "node")

        let groups = PortProcessGroupingService.groups(
            for: [secondPort, firstPort],
            metadataByPID: [:]
        )

        XCTAssertEqual(groups.map(\.id), ["process:10:node", "process:11:node"])
        XCTAssertEqual(groups.map(\.displayName), ["node (PID 10)", "node (PID 11)"])
        XCTAssertEqual(groups.map(\.ports), [[firstPort], [secondPort]])
    }

    func testSubtitleDeduplicatesAndSortsPorts() {
        let ports = [
            port(networkProtocol: .tcp, port: 3001, pid: 10, command: "node"),
            port(networkProtocol: .udp, port: 3000, pid: 10, command: "node"),
            port(networkProtocol: .tcp, port: 3000, pid: 10, command: "node")
        ]

        let groups = PortProcessGroupingService.groups(for: ports, metadataByPID: [:])

        XCTAssertEqual(groups.first?.subtitle, "3000, 3001")
        XCTAssertEqual(groups.first?.ports.map(\.port), [3000, 3000, 3001])
        XCTAssertEqual(groups.first?.ports.map(\.networkProtocol), [.tcp, .udp, .tcp])
    }

    private func port(
        networkProtocol: NetworkProtocol = .tcp,
        address: String = "*",
        port: Int,
        pid: Int,
        command: String
    ) -> PortEntry {
        PortEntry(
            networkProtocol: networkProtocol,
            address: address,
            port: port,
            pid: pid,
            command: command,
            user: "501"
        )
    }
}

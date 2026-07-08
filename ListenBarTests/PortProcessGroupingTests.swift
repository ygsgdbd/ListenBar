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
        XCTAssertEqual(groups.map(\.icon), [.process, .process])
        XCTAssertEqual(groups.map(\.ports), [[firstPort], [secondPort]])
    }

    func testUsesExecutableIconWithoutMergingCommandLineProcesses() {
        let firstPort = port(port: 3000, pid: 10, command: "node")
        let secondPort = port(port: 3001, pid: 11, command: "node")

        let groups = PortProcessGroupingService.groups(
            for: [secondPort, firstPort],
            metadataByPID: [
                10: .executable(name: "node", path: "/opt/homebrew/bin/node"),
                11: .executable(name: "node", path: "/Users/example/.local/bin/node")
            ]
        )

        XCTAssertEqual(
            groups,
            [
                PortProcessGroup(
                    id: "process:10:node",
                    displayName: "node (PID 10)",
                    subtitle: "3000",
                    icon: .executable(path: "/opt/homebrew/bin/node"),
                    ports: [firstPort]
                ),
                PortProcessGroup(
                    id: "process:11:node",
                    displayName: "node (PID 11)",
                    subtitle: "3001",
                    icon: .executable(path: "/Users/example/.local/bin/node"),
                    ports: [secondPort]
                )
            ]
        )
    }

    func testGroupsHelperProcessUnderOwnerAppWithDetailSubtitle() {
        let helperPort = port(
            port: 61305,
            pid: 22749,
            command: "GitHub Desktop Helper (Renderer)"
        )

        let groups = PortProcessGroupingService.groups(
            for: [helperPort],
            metadataByPID: [
                22749: PortProcessMetadata(
                    bundleIdentifier: "com.github.GitHubClient",
                    name: "GitHub Desktop",
                    path: "/Applications/GitHub Desktop.app",
                    processDetailName: "Helper (Renderer)"
                )
            ]
        )

        XCTAssertEqual(
            groups,
            [
                PortProcessGroup(
                    id: "app:com.github.GitHubClient",
                    displayName: "GitHub Desktop",
                    subtitle: "Helper (Renderer) · 61305",
                    icon: .application(path: "/Applications/GitHub Desktop.app"),
                    ports: [helperPort],
                    portProcessDetails: [helperPort.id: "Helper (Renderer)"]
                )
            ]
        )
    }

    func testGroupsMultipleHelperProcessesUnderOwnerApp() {
        let rendererPort = port(
            port: 61305,
            pid: 20,
            command: "GitHub Desktop Helper (Renderer)"
        )
        let gpuPort = port(
            port: 61306,
            pid: 21,
            command: "GitHub Desktop Helper (GPU)"
        )

        let groups = PortProcessGroupingService.groups(
            for: [gpuPort, rendererPort],
            metadataByPID: [
                20: PortProcessMetadata(
                    bundleIdentifier: "com.github.GitHubClient",
                    name: "GitHub Desktop",
                    path: "/Applications/GitHub Desktop.app",
                    processDetailName: "Helper (Renderer)"
                ),
                21: PortProcessMetadata(
                    bundleIdentifier: "com.github.GitHubClient",
                    name: "GitHub Desktop",
                    path: "/Applications/GitHub Desktop.app",
                    processDetailName: "Helper (GPU)"
                )
            ]
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, "app:com.github.GitHubClient")
        XCTAssertEqual(groups.first?.displayName, "GitHub Desktop")
        XCTAssertEqual(groups.first?.subtitle, "2 个子进程 · 61305, 61306")
        XCTAssertEqual(groups.first?.ports, [rendererPort, gpuPort])
        XCTAssertEqual(
            groups.first?.portProcessDetails,
            [
                rendererPort.id: "Helper (Renderer)",
                gpuPort.id: "Helper (GPU)"
            ]
        )
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

final class PortMenuLabelsTests: XCTestCase {
    func testSinglePIDGroupHidesPID() {
        let port = self.port(port: 20017, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertFalse(PortMenuLabels.showsPID(for: [port]))
        XCTAssertEqual(labels.title, "20017")
        XCTAssertEqual(labels.subtitle, "TCP 127.0.0.1:20017 · Local only")
    }

    func testMultiplePIDGroupShowsPID() {
        let firstPort = port(port: 20017, pid: 51487)
        let secondPort = port(port: 20018, pid: 51488)
        let labels = PortMenuLabels(port: firstPort, showsPID: true)

        XCTAssertTrue(PortMenuLabels.showsPID(for: [firstPort, secondPort]))
        XCTAssertEqual(labels.title, "20017")
        XCTAssertEqual(labels.subtitle, "TCP 127.0.0.1:20017 · Local only · PID 51487")
    }

    func testPortAndPIDLabelsDoNotUseThousandsSeparators() {
        let port = self.port(port: 20017, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: true)

        XCTAssertFalse(labels.title.contains(","))
        XCTAssertFalse(labels.subtitle.contains(","))
    }

    func testPortLabelCanShowHelperProcessName() {
        let port = self.port(
            port: 61305,
            pid: 22749,
            command: "GitHub Desktop Helper (Renderer)"
        )
        let labels = PortMenuLabels(
            port: port,
            showsPID: true,
            processName: "GitHub Desktop Helper (Renderer)"
        )

        XCTAssertEqual(
            labels.subtitle,
            "TCP 127.0.0.1:61305 · Local only · PID 22749 · GitHub Desktop Helper (Renderer)"
        )
    }

    func testLabelsClassifyAllInterfacesAndExposeLocalhostURL() {
        let port = self.port(address: "0.0.0.0", port: 3000, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertEqual(labels.subtitle, "TCP 0.0.0.0:3000 · All interfaces")
        XCTAssertEqual(labels.localhostURLString, "http://localhost:3000")
        XCTAssertEqual(labels.lsofCommand, "/usr/sbin/lsof -nP -iTCP:3000 -sTCP:LISTEN")
    }

    func testLabelsClassifyIPv6LoopbackAndWildcard() {
        let loopbackLabels = PortMenuLabels(
            port: port(address: "[::1]", port: 9090, pid: 1),
            showsPID: false
        )
        let wildcardLabels = PortMenuLabels(
            port: port(address: "[::]", port: 9091, pid: 2),
            showsPID: false
        )

        XCTAssertEqual(loopbackLabels.subtitle, "TCP [::1]:9090 · Local only")
        XCTAssertEqual(wildcardLabels.subtitle, "TCP [::]:9091 · All interfaces")
    }

    func testLabelsClassifySpecificInterfaceAndHideLocalhostURL() {
        let port = self.port(address: "192.168.1.5", port: 8080, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertEqual(labels.subtitle, "TCP 192.168.1.5:8080 · Specific interface")
        XCTAssertNil(labels.localhostURLString)
    }

    func testUDPLabelDoesNotExposeLocalhostURL() {
        let port = self.port(
            networkProtocol: .udp,
            address: "*",
            port: 5353,
            pid: 51487
        )
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertEqual(labels.subtitle, "UDP *:5353 · All interfaces")
        XCTAssertNil(labels.localhostURLString)
        XCTAssertEqual(labels.lsofCommand, "/usr/sbin/lsof -nP -iUDP:5353")
    }

    private func port(
        networkProtocol: NetworkProtocol = .tcp,
        address: String = "127.0.0.1",
        port: Int,
        pid: Int,
        command: String = "Example"
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

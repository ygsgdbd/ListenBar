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

    func testClassifiesRootProcessWithoutMetadataAsSystemOrOtherUser() {
        let port = port(port: 22, pid: 10, command: "sshd", user: "0")

        let groups = PortProcessGroupingService.groups(for: [port], metadataByPID: [:])

        XCTAssertEqual(groups.first?.classification, .systemOrOtherUser)
    }

    func testGroupClassificationUsesMetadataAndPromotesMixedAppGroupToSystem() {
        let userPort = port(port: 3000, pid: 10, command: "Example Helper")
        let systemPort = port(port: 3001, pid: 11, command: "Example Helper")

        let groups = PortProcessGroupingService.groups(
            for: [userPort, systemPort],
            metadataByPID: [
                10: PortProcessMetadata(
                    bundleIdentifier: "com.example.App",
                    name: "Example",
                    path: "/Applications/Example.app",
                    classification: .user
                ),
                11: PortProcessMetadata(
                    bundleIdentifier: "com.example.App",
                    name: "Example",
                    path: "/Applications/Example.app",
                    classification: .systemOrOtherUser
                )
            ]
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.classification, .systemOrOtherUser)
    }

    private func port(
        networkProtocol: NetworkProtocol = .tcp,
        address: String = "*",
        port: Int,
        pid: Int,
        command: String,
        user: String = "501"
    ) -> PortEntry {
        PortEntry(
            networkProtocol: networkProtocol,
            address: address,
            port: port,
            pid: pid,
            command: command,
            user: user
        )
    }
}

final class PortMenuLabelsTests: XCTestCase {
    func testSinglePIDGroupHidesPID() {
        let port = self.port(port: 20017, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertFalse(PortMenuLabels.showsPID(for: [port]))
        XCTAssertEqual(labels.title, "20017")
        XCTAssertEqual(labels.subtitle, "TCP 127.0.0.1:20017 · 仅本机")
    }

    func testMultiplePIDGroupShowsPID() {
        let firstPort = port(port: 20017, pid: 51487)
        let secondPort = port(port: 20018, pid: 51488)
        let labels = PortMenuLabels(port: firstPort, showsPID: true)

        XCTAssertTrue(PortMenuLabels.showsPID(for: [firstPort, secondPort]))
        XCTAssertEqual(labels.title, "20017")
        XCTAssertEqual(labels.subtitle, "TCP 127.0.0.1:20017 · 仅本机 · PID 51487")
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
            "TCP 127.0.0.1:61305 · 仅本机 · PID 22749 · GitHub Desktop Helper (Renderer)"
        )
    }

    func testLabelsClassifyAllInterfacesAndExposeLocalhostURL() {
        let port = self.port(address: "0.0.0.0", port: 3000, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertEqual(labels.subtitle, "TCP 0.0.0.0:3000 · 所有网络接口")
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

        XCTAssertEqual(loopbackLabels.subtitle, "TCP [::1]:9090 · 仅本机")
        XCTAssertEqual(wildcardLabels.subtitle, "TCP [::]:9091 · 所有网络接口")
    }

    func testLabelsClassifySpecificInterfaceAndHideLocalhostURL() {
        let port = self.port(address: "192.168.1.5", port: 8080, pid: 51487)
        let labels = PortMenuLabels(port: port, showsPID: false)

        XCTAssertEqual(labels.subtitle, "TCP 192.168.1.5:8080 · 指定网络接口")
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

        XCTAssertEqual(labels.subtitle, "UDP *:5353 · 所有网络接口")
        XCTAssertNil(labels.localhostURLString)
        XCTAssertEqual(labels.lsofCommand, "/usr/sbin/lsof -nP -iUDP:5353")
    }

    func testProcessInfoLabelsShowSourcePathAndCommandSummary() {
        let labels = PortProcessInfoLabels(
            metadata: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
                commandLine: "/opt/homebrew/bin/node server.js",
                commandLineSummary: "/opt/homebrew/bin/node server.js",
                redactedCommandLine: "/opt/homebrew/bin/node server.js",
                redactedCommandLineSummary: "/opt/homebrew/bin/node server.js",
                residentMemoryBytes: 5_452_595,
                sources: [.executable, .homebrew, .visualStudioCode]
            )
        )

        XCTAssertTrue(labels.hasDetails)
        XCTAssertEqual(labels.source, "来源：可执行文件 • Homebrew • VS Code")
        XCTAssertEqual(labels.memory, "常驻内存：5.2 MB")
        XCTAssertEqual(labels.path, "/opt/homebrew/bin/node")
        XCTAssertEqual(labels.commandLineSummary, "/opt/homebrew/bin/node server.js")
        XCTAssertEqual(labels.redactedCommandLineSummary, "/opt/homebrew/bin/node server.js")
    }

    func testMemoryFormatterUsesBinaryUnits() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(PortMemoryFormatter.string(bytes: 1_024, locale: locale), "1.0 KB")
        XCTAssertEqual(PortMemoryFormatter.string(bytes: 5_452_595, locale: locale), "5.2 MB")
        XCTAssertEqual(PortMemoryFormatter.string(bytes: 2_147_483_648, locale: locale), "2.0 GB")
    }

    func testSectionLabelsCountUniqueProcessesAndPorts() {
        let first = self.port(port: 3000, pid: 101, command: "node")
        let second = self.port(port: 3001, pid: 101, command: "node")
        let third = self.port(port: 5432, pid: 202, command: "postgres")
        let groups = PortProcessGroupingService.groups(
            for: [first, second, third],
            metadataByPID: [:]
        )

        XCTAssertEqual(
            PortProcessSectionLabels.title(classification: .user, groups: groups),
            "用户进程（2 进程 · 3 端口）"
        )
    }

    func testPortListFormatterOutputsCompleteInformation() throws {
        let port = self.port(port: 3000, pid: 101, command: "node")
        let metadata = [
            101: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
                sources: [.executable, .homebrew]
            )
        ]
        let groups = PortProcessGroupingService.groups(
            for: [port],
            metadataByPID: metadata
        )

        XCTAssertEqual(
            PortListFormatter.text(groups: groups, metadataByPID: metadata),
            """
            group 'node (PID 101)' processes=1 ports=1 source='可执行文件 • Homebrew'
            TCP 127.0.0.1 3000 pid=101 command=node source='可执行文件 • Homebrew' url=http://localhost:3000 path=/opt/homebrew/bin/node
            """
        )
    }

    func testPortListFormatterOutputsOneGroupOnly() throws {
        let nodePort = self.port(port: 3000, pid: 101, command: "node")
        let postgresPort = self.port(port: 5432, pid: 202, command: "postgres")
        let groups = PortProcessGroupingService.groups(
            for: [postgresPort, nodePort],
            metadataByPID: [:]
        )
        let nodeGroup = try XCTUnwrap(groups.first { $0.ports.contains(nodePort) })

        XCTAssertEqual(
            PortListFormatter.text(group: nodeGroup, metadataByPID: [:]),
            """
            group 'node (PID 101)' processes=1 ports=1 source=未知来源
            TCP 127.0.0.1 3000 pid=101 command=node url=http://localhost:3000
            """
        )
    }

    func testPortListFormatterOutputsUniqueSortedSpaceSeparatedPorts() throws {
        let ports = [
            self.port(port: 7000, pid: 101, command: "node"),
            self.port(port: 5000, pid: 101, command: "node"),
            self.port(
                networkProtocol: .udp,
                address: "*",
                port: 5000,
                pid: 101,
                command: "node"
            )
        ]
        let group = try XCTUnwrap(
            PortProcessGroupingService.groups(for: ports, metadataByPID: [:]).first
        )

        XCTAssertEqual(PortListFormatter.portsText(group: group), "5000 7000")
    }

    func testProcessInfoItemsDeduplicateRepeatedPIDPorts() throws {
        let firstPort = self.port(port: 5037, pid: 63759, command: "adb")
        let secondPort = self.port(
            networkProtocol: .udp,
            address: "*",
            port: 5353,
            pid: 63759,
            command: "adb"
        )
        let metadata = [
            63759: PortProcessMetadata.executable(
                name: "adb",
                path: "/Users/rainbow/Library/Android/sdk/platform-tools/adb",
                commandLine: "adb -L tcp:5037 fork-server server --reply-fd 4",
                commandLineSummary: "adb -L tcp:5037 fork-server server --reply-fd 4",
                sources: [.executable, .launchd]
            )
        ]
        let group = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [secondPort, firstPort],
                metadataByPID: metadata
            ).first
        )

        let items = PortProcessInfoItems(
            group: group,
            metadataByPID: metadata
        )

        XCTAssertEqual(items.items.map(\.pid), [63759])
        XCTAssertEqual(items.singleItem?.title, "PID 63759")
        XCTAssertEqual(
            items.singleItem?.labels.path,
            "/Users/rainbow/Library/Android/sdk/platform-tools/adb"
        )
        XCTAssertEqual(
            items.singleItem?.labels.commandLineSummary,
            "adb -L tcp:5037 fork-server server --reply-fd 4"
        )
    }

    func testProcessInfoItemsCreateSeparateEntriesForMultipleAppPIDs() throws {
        let rendererPort = self.port(
            port: 61305,
            pid: 20,
            command: "GitHub Desktop Helper (Renderer)"
        )
        let gpuPort = self.port(
            port: 61306,
            pid: 21,
            command: "GitHub Desktop Helper (GPU)"
        )
        let metadata = [
            20: PortProcessMetadata(
                bundleIdentifier: "com.github.GitHubClient",
                name: "GitHub Desktop",
                path: "/Applications/GitHub Desktop.app",
                processDetailName: "Helper (Renderer)",
                executablePath: "/Applications/GitHub Desktop.app/Contents/Frameworks/GitHub Desktop Helper (Renderer).app/Contents/MacOS/GitHub Desktop Helper (Renderer)",
                commandLine: "renderer --type=renderer",
                commandLineSummary: "renderer --type=renderer"
            ),
            21: PortProcessMetadata(
                bundleIdentifier: "com.github.GitHubClient",
                name: "GitHub Desktop",
                path: "/Applications/GitHub Desktop.app",
                processDetailName: "Helper (GPU)",
                executablePath: "/Applications/GitHub Desktop.app/Contents/Frameworks/GitHub Desktop Helper (GPU).app/Contents/MacOS/GitHub Desktop Helper (GPU)",
                commandLine: "gpu --type=gpu-process",
                commandLineSummary: "gpu --type=gpu-process"
            )
        ]
        let group = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [gpuPort, rendererPort],
                metadataByPID: metadata
            ).first
        )

        let items = PortProcessInfoItems(
            group: group,
            metadataByPID: metadata
        )

        XCTAssertNil(items.singleItem)
        XCTAssertEqual(items.items.map(\.pid), [20, 21])
        XCTAssertEqual(
            items.items.map(\.title),
            [
                "Helper (Renderer) · PID 20",
                "Helper (GPU) · PID 21"
            ]
        )
        XCTAssertEqual(
            items.items.map(\.labels.commandLineSummary),
            [
                "renderer --type=renderer",
                "gpu --type=gpu-process"
            ]
        )
    }

    func testProcessInfoItemsShowFallbackMetadataForUnreadablePID() throws {
        let port = self.port(port: 3000, pid: 10)
        let metadata = PortProcessMetadataService.fallbackMetadata(
            for: port,
            processName: nil,
            uid: nil,
            residentMemoryBytes: nil
        )
        let group = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [port],
                metadataByPID: [port.pid: metadata]
            ).first
        )

        let items = PortProcessInfoItems(
            group: group,
            metadataByPID: [port.pid: metadata]
        )

        XCTAssertEqual(items.items.map(\.pid), [port.pid])
        XCTAssertEqual(items.singleItem?.labels.source, "来源：未知来源")
        XCTAssertEqual(items.singleItem?.labels.memory, "常驻内存：不可用")
    }

    func testProcessInfoLabelsHideMissingMetadata() {
        let labels = PortProcessInfoLabels(metadata: nil)

        XCTAssertFalse(labels.hasDetails)
        XCTAssertEqual(labels.source, "")
        XCTAssertNil(labels.memory)
        XCTAssertNil(labels.path)
        XCTAssertNil(labels.commandLineSummary)
    }

    func testProcessInfoLabelsShowUnavailableMemoryWhenMetadataExists() {
        let labels = PortProcessInfoLabels(
            metadata: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: nil
            )
        )

        XCTAssertTrue(labels.hasDetails)
        XCTAssertEqual(labels.source, "来源：App")
        XCTAssertEqual(labels.memory, "常驻内存：不可用")
        XCTAssertNil(labels.path)
        XCTAssertNil(labels.commandLineSummary)
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

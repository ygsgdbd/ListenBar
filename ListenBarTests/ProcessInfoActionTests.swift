import ComposableArchitecture
@testable import ListenBar
import XCTest

@MainActor
final class ProcessInfoActionTests: XCTestCase {
    func testCopyDetailsUsesFullCommandsForSelectedPID() async throws {
        let appPort = port(pid: 101)
        let cliPort = port(pid: 51_487)
        let rawCommand = "Example --port 3000 --token secret --verbose"
        let redactedCommand = "Example --port 3000 --token <redacted> --verbose"
        let executablePath = "/Applications/Example.app/Contents/MacOS/Example"
        let metadata = [
            appPort.pid: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
                executablePath: executablePath,
                commandLine: rawCommand,
                commandLineSummary: "Example --port 3000 …",
                redactedCommandLine: redactedCommand,
                redactedCommandLineSummary: "Example --token <redacted> …",
            ),
            cliPort.pid: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
                commandLine: "node server.js",
                commandLineSummary: "node …",
            ),
        ]
        let recorder = ProcessInfoActionRecorder()
        let store = makeStore(ports: [appPort, cliPort], metadata: metadata, recorder: recorder)
        let group = try XCTUnwrap(store.state.processGroups.first { $0.applicationBundleIdentifier != nil })
        let item = try XCTUnwrap(PortProcessInfoItems(group: group, metadataByPID: metadata).singleItem)
        XCTAssertEqual(item.details.commandLineSummary, "Example --port 3000 …")
        XCTAssertEqual(item.details.redactedCommandLineSummary, "Example --token <redacted> …")

        let actions: [AppFeature.ViewAction] = [
            .copyProcessPathTapped(pid: appPort.pid),
            .copyCommandLineTapped(pid: appPort.pid),
            .copyRedactedCommandLineTapped(pid: appPort.pid),
            .revealProcessPathTapped(pid: appPort.pid),
            .copyProcessPathTapped(pid: cliPort.pid),
            .copyCommandLineTapped(pid: cliPort.pid),
            .copyPIDTapped(pid: cliPort.pid),
        ]
        for action in actions {
            await store.send(.view(action)).finish()
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [
            .copy(executablePath), .copy(rawCommand), .copy(redactedCommand), .reveal(executablePath),
            .copy("/opt/homebrew/bin/node"), .copy("node server.js"), .copy("51487"),
        ])
    }

    func testProcessPathActionsUseApplicationPathFallback() async {
        let port = port(pid: 101)
        let metadata = [
            port.pid: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
            ),
        ]
        let recorder = ProcessInfoActionRecorder()
        let store = makeStore(ports: [port], metadata: metadata, recorder: recorder)

        await store.send(.view(.copyProcessPathTapped(pid: port.pid))).finish()
        await store.send(.view(.revealProcessPathTapped(pid: port.pid))).finish()

        let calls = await recorder.values()
        XCTAssertEqual(calls, [.copy("/Applications/Example.app"), .reveal("/Applications/Example.app")])
    }

    func testMissingProcessDetailsDoNotCopyOrReveal() async {
        let port = port(pid: 101)
        let metadata = [
            port.pid: PortProcessMetadata(bundleIdentifier: "com.example.App", name: "Example", path: nil),
        ]
        let recorder = ProcessInfoActionRecorder()
        let store = makeStore(ports: [port], metadata: metadata, recorder: recorder)

        for pid in [port.pid, 999] {
            await store.send(.view(.copyProcessPathTapped(pid: pid))).finish()
            await store.send(.view(.copyCommandLineTapped(pid: pid))).finish()
            await store.send(.view(.copyRedactedCommandLineTapped(pid: pid))).finish()
            await store.send(.view(.revealProcessPathTapped(pid: pid))).finish()
        }
        await store.send(.view(.copyPIDTapped(pid: 999))).finish()

        let calls = await recorder.values()
        XCTAssertEqual(calls, [.copy("999")])
    }

    func testApplicationRevealRequiresUniqueMatchingPath() async {
        let ports = [port(pid: 101), port(pid: 102)]
        let appGroup = PortProcessGroup(
            id: "app:com.example.App", displayName: "Example", subtitle: "3000", icon: .process, ports: ports,
        )
        let cliGroup = PortProcessGroup(
            id: "process:101:node", displayName: "node", subtitle: "3000", icon: .process, ports: ports,
        )
        let app = PortProcessMetadata(
            bundleIdentifier: "com.example.App", name: "Example", path: "/Applications/Example.app",
            executablePath: "/Applications/Example.app/Contents/MacOS/Example",
        )
        let otherLocation = PortProcessMetadata(
            bundleIdentifier: "com.example.App", name: "Example", path: "/Users/example/Applications/Example.app",
        )
        let missingPath = PortProcessMetadata(bundleIdentifier: "com.example.App", name: "Example", path: nil)
        let otherApp = PortProcessMetadata(bundleIdentifier: "com.example.Other", name: "Other", path: "/Applications/Other.app")
        let executable = PortProcessMetadata.executable(name: "node", path: "/opt/homebrew/bin/node")
        let cases: [(PortProcessGroup, [Int: PortProcessMetadata], String?)] = [
            (appGroup, [101: app, 102: app], "/Applications/Example.app"),
            (appGroup, [101: app], "/Applications/Example.app"),
            (appGroup, [101: app, 102: missingPath], "/Applications/Example.app"),
            (appGroup, [101: app, 102: otherLocation], nil),
            (appGroup, [101: missingPath], nil),
            (appGroup, [101: otherApp], nil),
            (appGroup, [101: executable], nil),
            (cliGroup, [101: executable], nil),
            (appGroup, [:], nil),
        ]

        for (group, metadata, expectedPath) in cases {
            let recorder = ProcessInfoActionRecorder()
            let store = makeStore(ports: ports, metadata: metadata, recorder: recorder)
            await store.send(.view(.revealApplicationPathTapped(group))).finish()

            let calls = await recorder.values()
            XCTAssertEqual(calls, expectedPath.map { [.reveal($0)] } ?? [])
        }
    }

    func testCopyInformationActionsExportOnlyVisibleProcesses() async throws {
        let visiblePort = port(pid: 101)
        let hiddenPort = port(pid: 202)
        let metadata = [
            visiblePort.pid: PortProcessMetadata.executable(
                name: "node", path: "/opt/homebrew/bin/node",
                commandLine: "node --token secret", sources: [.executable, .homebrew],
            ),
            hiddenPort.pid: PortProcessMetadata.executable(name: "node", path: "/Users/example/bin/node"),
        ]
        let recorder = ProcessInfoActionRecorder()
        let store = makeStore(
            ports: [visiblePort, hiddenPort], metadata: metadata, recorder: recorder,
            ignoredProcesses: [.executable(path: "/Users/example/bin/node", displayName: "node")],
        )
        let group = try XCTUnwrap(store.state.processGroups.first)
        let expectedText = """
        group 'node (PID 101)' processes=1 ports=1 source='可执行文件 • Homebrew'
        TCP 127.0.0.1 3000 pid=101 command=node source='可执行文件 • Homebrew' url=http://localhost:3000 path=/opt/homebrew/bin/node
        """

        await store.send(.view(.copyFullInformationTapped)).finish()
        await store.send(.view(.copyProcessInformationTapped(group))).finish()
        await store.send(.view(.copyGroupPortsTapped(group))).finish()
        await store.send(.view(.copyURLTapped(visiblePort))).finish()

        let calls = await recorder.values()
        XCTAssertEqual(calls, [.copy(expectedText), .copy(expectedText), .copy("3000"), .copy("http://localhost:3000")])
    }

    private func makeStore(
        ports: [PortEntry],
        metadata: [Int: PortProcessMetadata],
        recorder: ProcessInfoActionRecorder,
        ignoredProcesses: [IgnoredProcessItem] = [],
    ) -> TestStoreOf<AppFeature> {
        var state = AppFeature.State()
        state.portVisibility = PortVisibility(
            snapshot: PortScanSnapshot(
                ports: ports,
                metadataByPID: metadata,
                processGroups: PortProcessGroupingService.groups(for: ports, metadataByPID: metadata),
            ),
            ignoredProcesses: ignoredProcesses,
        )
        state.$settings.withLock { $0.ignoredProcesses = ignoredProcesses }
        let store = TestStore(initialState: state) { AppFeature() }
        store.dependencies.processInfoActions = ProcessInfoActionsClient(
            copyText: { await recorder.record(.copy($0)) },
            revealPath: { await recorder.record(.reveal($0)) },
        )
        return store
    }

    private func port(pid: Int) -> PortEntry {
        PortEntry(networkProtocol: .tcp, address: "127.0.0.1", port: 3000, pid: pid, command: "node", user: "501")
    }
}

private enum ProcessInfoActionCall: Equatable, Sendable {
    case copy(String)
    case reveal(String)
}

private actor ProcessInfoActionRecorder {
    private var calls: [ProcessInfoActionCall] = []

    func record(_ call: ProcessInfoActionCall) {
        calls.append(call)
    }

    func values() -> [ProcessInfoActionCall] {
        calls
    }
}

import ComposableArchitecture
import XCTest
@testable import ListenBar

@MainActor
final class AppFeatureTests: XCTestCase {
    func testTaskLoadsPortsAndUpdatesTimestamp() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let ports = [
            PortEntry(
                networkProtocol: .tcp,
                address: "*",
                port: 8080,
                pid: 123,
                command: "node",
                user: "501"
            )
        ]
        let snapshot = makeSnapshot(ports)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portScanner.scan = { ports }

        await store.send(.task) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portsLoaded(.success(snapshot)))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = snapshot.metadataByPID
            $0.ports = ports
            $0.processGroups = snapshot.processGroups
        }
    }

    func testScanFailureKeepsExistingPortsAndStoresError() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 5037,
            pid: 63759,
            command: "adb",
            user: "501"
        )
        var initialState = AppFeature.State()
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.portScanner.scan = {
            throw PortScannerFailure(message: "lsof failed")
        }

        await store.send(.task) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portsLoaded(.failure(.init(message: "lsof failed"))))) {
            $0.isLoading = false
            $0.errorMessage = "lsof failed"
        }

        XCTAssertEqual(store.state.ports, [oldPort])
        XCTAssertEqual(store.state.processGroups, initialState.processGroups)
    }

    func testLastUpdatedRelativeStringIncludesSeconds() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertEqual(
            PortLastUpdatedFormatter.relativeString(
                from: now.addingTimeInterval(-5),
                to: now
            ),
            "5 秒前"
        )
        XCTAssertEqual(
            PortLastUpdatedFormatter.relativeString(
                from: now.addingTimeInterval(-65),
                to: now
            ),
            "1 分 5 秒前"
        )
        XCTAssertEqual(
            PortLastUpdatedFormatter.relativeString(
                from: now.addingTimeInterval(-3_661),
                to: now
            ),
            "1 小时 1 分 1 秒前"
        )
        XCTAssertEqual(
            PortLastUpdatedFormatter.relativeString(
                from: now.addingTimeInterval(-90_061),
                to: now
            ),
            "1 天 1 小时 1 分 1 秒前"
        )
        XCTAssertEqual(
            PortLastUpdatedFormatter.relativeString(
                from: now.addingTimeInterval(1),
                to: now
            ),
            "刚刚"
        )
        XCTAssertEqual(
            PortLastUpdatedFormatter.relativeString(
                from: now.addingTimeInterval(-0.5),
                to: now
            ),
            "刚刚"
        )
    }

    func testOnlyForceKillIsDestructive() {
        XCTAssertFalse(PortKillMode.quit.isDestructive)
        XCTAssertTrue(PortKillMode.force.isDestructive)
    }

    func testConfirmationDialogsOnlyUseDestructiveRoleForForceKill() throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let group = try XCTUnwrap(makeSnapshot([port]).processGroups.first)

        XCTAssertNil(
            PortKillRequest(port: port, mode: .quit)
                .confirmationDialog(warnings: [.systemProcess])
                .buttons.last?.role
        )
        XCTAssertEqual(
            PortKillRequest(port: port, mode: .force)
                .confirmationDialog(warnings: [.forceKill])
                .buttons.last?.role,
            .destructive
        )
        XCTAssertNil(
            PortGroupKillRequest(group: group, mode: .quit)
                .confirmationDialog(warnings: [.multipleProcesses(1)])
                .buttons.last?.role
        )
        XCTAssertEqual(
            PortGroupKillRequest(group: group, mode: .force)
                .confirmationDialog(warnings: [.forceKill])
                .buttons.last?.role,
            .destructive
        )
    }

    func testQuitPortTerminatesPidThenRefreshesPorts() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "*",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let refreshedPort = PortEntry(
            networkProtocol: .tcp,
            address: "*",
            port: 4000,
            pid: 202,
            command: "server",
            user: "501"
        )
        let now = Date(timeIntervalSince1970: 3_000)
        let recorder = KillRecorder()
        var initialState = AppFeature.State()
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups
        let refreshedSnapshot = makeSnapshot([refreshedPort])

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        let scans = PortScanSequence([[oldPort], [refreshedPort]])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        let request = PortKillRequest(port: oldPort, mode: .quit)
        await store.send(.view(.killPortTapped(oldPort, .quit))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.success(request: request))))
        await store.receive(.response(.portsLoaded(.success(refreshedSnapshot)))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = refreshedSnapshot.metadataByPID
            $0.ports = [refreshedPort]
            $0.processGroups = refreshedSnapshot.processGroups
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [.init(pid: oldPort.pid, mode: .quit)])
    }

    func testKillPortFailureKeepsExistingPortsAndStoresError() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 5037,
            pid: 63759,
            command: "adb",
            user: "501"
        )
        var initialState = AppFeature.State()
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 4_000))
        store.dependencies.portKiller.terminate = { _, _ in
            throw PortKillerFailure(message: "permission denied")
        }
        store.dependencies.portScanner.scan = { [oldPort] }

        await store.send(.view(.killPortTapped(oldPort, .quit))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.failure(request: PortKillRequest(port: oldPort, mode: .quit), failure: .init(message: "permission denied"))))) {
            $0.isLoading = false
            $0.errorMessage = "permission denied"
        }

        XCTAssertEqual(store.state.ports, [oldPort])
        XCTAssertEqual(store.state.processGroups, initialState.processGroups)
    }

    func testForceKillRequiresConfirmationThenKills() async {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let recorder = KillRecorder()
        var initialState = AppFeature.State()
        initialState.ports = [port]
        initialState.processGroups = makeSnapshot([port]).processGroups
        let now = Date(timeIntervalSince1970: 5_000)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        let scans = PortScanSequence([[port], []])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        let request = PortKillRequest(port: port, mode: .force)
        await store.send(.view(.killPortTapped(port, .force))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.forceKill])
        }
        await store.send(.confirmationDialog(.presented(.confirmKill(request)))) {
            $0.confirmationDialog = nil
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.success(request: request))))
        await store.receive(.response(.portsLoaded(.success(makeSnapshot([]))))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = [:]
            $0.ports = []
            $0.processGroups = []
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [.init(pid: port.pid, mode: .force)])
    }

    func testSystemProcessQuitRequiresConfirmation() async {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "0.0.0.0",
            port: 22,
            pid: 222,
            command: "sshd",
            user: "0"
        )
        let metadata = [
            port.pid: PortProcessMetadata.executable(
                name: "sshd",
                path: "/usr/sbin/sshd"
            )
        ]
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = [port]
        initialState.processGroups = makeSnapshot([port], metadata: metadata).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        let request = PortKillRequest(
            port: port,
            mode: .quit,
            processName: "sshd",
            expectedExecutablePath: "/usr/sbin/sshd"
        )
        await store.send(.view(.killPortTapped(port, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.systemProcess])
        }
    }

    func testAppMainProcessQuitRequiresConfirmation() async {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 14013,
            pid: 333,
            command: "WeChat",
            user: "501"
        )
        let metadata = [
            port.pid: PortProcessMetadata(
                bundleIdentifier: "com.tencent.xinWeChat",
                name: "WeChat",
                path: "/Applications/WeChat.app"
            )
        ]
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = [port]
        initialState.processGroups = makeSnapshot([port], metadata: metadata).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        let request = PortKillRequest(
            port: port,
            mode: .quit,
            processName: "WeChat",
            expectedExecutablePath: "/Applications/WeChat.app"
        )
        await store.send(.view(.killPortTapped(port, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.appMainProcess])
        }
    }

    func testProcessPathAndCommandLineSelectorsUsePIDMetadata() {
        let metadata = [
            101: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
                executablePath: "/Applications/Example.app/Contents/MacOS/Example",
                commandLine: "Example --port 3000",
                commandLineSummary: "Example --port 3000",
                redactedCommandLine: "Example --port 3000",
                redactedCommandLineSummary: "Example --port 3000"
            ),
            102: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
                commandLine: "node server.js",
                commandLineSummary: "node server.js",
                redactedCommandLine: "node server.js",
                redactedCommandLineSummary: "node server.js"
            )
        ]

        XCTAssertEqual(
            AppFeature.processPath(forPID: 101, metadataByPID: metadata),
            "/Applications/Example.app/Contents/MacOS/Example"
        )
        XCTAssertEqual(
            AppFeature.commandLine(forPID: 101, metadataByPID: metadata),
            "Example --port 3000"
        )
        XCTAssertEqual(
            AppFeature.processPath(forPID: 102, metadataByPID: metadata),
            "/opt/homebrew/bin/node"
        )
        XCTAssertEqual(
            AppFeature.commandLine(forPID: 102, metadataByPID: metadata),
            "node server.js"
        )
        XCTAssertEqual(
            AppFeature.redactedCommandLine(forPID: 102, metadataByPID: metadata),
            "node server.js"
        )
        XCTAssertNil(AppFeature.processPath(forPID: 999, metadataByPID: metadata))
        XCTAssertNil(AppFeature.commandLine(forPID: 999, metadataByPID: metadata))
        XCTAssertNil(AppFeature.redactedCommandLine(forPID: 999, metadataByPID: metadata))
    }

    func testKillPortAbortsWhenFreshScanNoLongerMatches() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let newPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 202,
            command: "node",
            user: "501"
        )
        let refreshedSnapshot = makeSnapshot([newPort])
        let recorder = KillRecorder()
        var initialState = AppFeature.State()
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portScanner.scan = { [newPort] }

        let request = PortKillRequest(port: oldPort, mode: .quit)
        await store.send(.view(.killPortTapped(oldPort, .quit))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.aborted(request: request, refreshedSnapshot: refreshedSnapshot, failure: .staleTarget)))) {
            $0.isLoading = false
            $0.errorMessage = PortKillerFailure.staleTarget.message
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = Date(timeIntervalSince1970: 0)
            $0.metadataByPID = [:]
            $0.ports = [newPort]
            $0.processGroups = refreshedSnapshot.processGroups
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [])
    }

    func testKillPortAbortsWhenExecutablePathChanges() async {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let oldMetadata = [
            101: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node"
            )
        ]
        let newMetadata = [
            101: PortProcessMetadata.executable(
                name: "node",
                path: "/Users/example/bin/node"
            )
        ]
        let refreshedSnapshot = makeSnapshot([port], metadata: newMetadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = oldMetadata
        initialState.ports = [port]
        initialState.processGroups = makeSnapshot([port], metadata: oldMetadata).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portScanner.scan = { [port] }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return newMetadata.filter { pids.contains($0.key) }
        }

        let request = PortKillRequest(
            port: port,
            mode: .quit,
            processName: "node",
            expectedExecutablePath: "/opt/homebrew/bin/node"
        )
        await store.send(.view(.killPortTapped(port, .quit))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.aborted(request: request, refreshedSnapshot: refreshedSnapshot, failure: .staleTarget)))) {
            $0.isLoading = false
            $0.errorMessage = PortKillerFailure.staleTarget.message
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = Date(timeIntervalSince1970: 0)
            $0.metadataByPID = newMetadata
            $0.ports = [port]
            $0.processGroups = refreshedSnapshot.processGroups
        }
    }

    func testAutoRefreshStartsImmediatelyTicksAndCanBeCancelled() async {
        let clock = TestClock()
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let snapshot = makeSnapshot([port])

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.continuousClock = clock
        store.dependencies.portScanner.scan = { [port] }

        await store.send(.view(.autoRefreshIntervalTapped(.fiveSeconds))) {
            $0.autoRefreshInterval = .fiveSeconds
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.portsLoaded(.success(snapshot)))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = Date(timeIntervalSince1970: 0)
            $0.metadataByPID = [:]
            $0.ports = [port]
            $0.processGroups = snapshot.processGroups
        }
        await clock.advance(by: .seconds(5))
        await store.receive(.autoRefreshTick) {
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.portsLoaded(.success(snapshot)))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = Date(timeIntervalSince1970: 0)
            $0.metadataByPID = [:]
            $0.ports = [port]
            $0.processGroups = snapshot.processGroups
        }
        await store.send(.view(.autoRefreshIntervalTapped(.off))) {
            $0.autoRefreshInterval = .off
        }
    }

    func testKillGroupRequiresConfirmationThenTerminatesUniquePIDsAndRefreshes() async throws {
        let firstPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let secondPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3001,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let thirdPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3002,
            pid: 202,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101, 202])
        let initialSnapshot = makeSnapshot(
            [firstPort, secondPort, thirdPort],
            metadata: metadata
        )
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = initialSnapshot.ports
        initialState.processGroups = initialSnapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = PortGroupKillRequest(
            group: group,
            mode: .quit,
            metadataByPID: metadata
        )
        let now = Date(timeIntervalSince1970: 6_000)
        let recorder = KillRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return metadata.filter { pids.contains($0.key) }
        }
        let scans = PortScanSequence([[firstPort, secondPort, thirdPort], []])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        await store.send(.view(.killGroupTapped(group, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.multipleProcesses(2)])
        }
        await store.send(.confirmationDialog(.presented(.confirmKillGroup(request)))) {
            $0.confirmationDialog = nil
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.portGroupKillFinished(.init(request: request, failures: []))))
        await store.receive(.response(.portsLoaded(.success(makeSnapshot([]))))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = [:]
            $0.ports = []
            $0.processGroups = []
        }

        let calls = await recorder.values()
        XCTAssertEqual(
            calls,
            [
                .init(pid: 101, mode: .quit),
                .init(pid: 202, mode: .quit)
            ]
        )
    }

    func testKillGroupAbortsWhenFreshScanNoLongerMatchesGroup() async throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101])
        let initialSnapshot = makeSnapshot([port], metadata: metadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = initialSnapshot.ports
        initialState.processGroups = initialSnapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = PortGroupKillRequest(
            group: group,
            mode: .quit,
            metadataByPID: metadata
        )
        let refreshedSnapshot = makeSnapshot([port], metadata: [:])
        let recorder = KillRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portScanner.scan = { [port] }
        store.dependencies.portProcessMetadata.resolve = { _ in [:] }

        await store.send(.view(.killGroupTapped(group, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [])
        }
        await store.send(.confirmationDialog(.presented(.confirmKillGroup(request)))) {
            $0.confirmationDialog = nil
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(
            .response(
                .portGroupKillFinished(
                    PortGroupKillResult(
                        request: request,
                        failures: [.init(pid: 0, message: PortKillerFailure.staleTarget.message)],
                        refreshedSnapshot: refreshedSnapshot
                    )
                )
            )
        ) {
            $0.isLoading = false
            $0.errorMessage = PortKillerFailure.staleTarget.message
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = Date(timeIntervalSince1970: 0)
            $0.metadataByPID = [:]
            $0.ports = [port]
            $0.processGroups = refreshedSnapshot.processGroups
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [])
    }

    func testKillGroupAbortsWhenFreshGroupHasAdditionalEndpoint() async throws {
        let originalPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let additionalPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3001,
            pid: 202,
            command: "Example Helper",
            user: "501"
        )
        let originalMetadata = appMetadata(for: [101])
        let refreshedMetadata = appMetadata(for: [101, 202])
        let initialSnapshot = makeSnapshot([originalPort], metadata: originalMetadata)
        let refreshedSnapshot = makeSnapshot([originalPort, additionalPort], metadata: refreshedMetadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = originalMetadata
        initialState.ports = initialSnapshot.ports
        initialState.processGroups = initialSnapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = PortGroupKillRequest(
            group: group,
            mode: .quit,
            metadataByPID: originalMetadata
        )
        let recorder = KillRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portScanner.scan = { [originalPort, additionalPort] }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return refreshedMetadata.filter { pids.contains($0.key) }
        }

        await store.send(.view(.killGroupTapped(group, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [])
        }
        await store.send(.confirmationDialog(.presented(.confirmKillGroup(request)))) {
            $0.confirmationDialog = nil
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(
            .response(
                .portGroupKillFinished(
                    PortGroupKillResult(
                        request: request,
                        failures: [.init(pid: 0, message: PortKillerFailure.staleTarget.message)],
                        refreshedSnapshot: refreshedSnapshot
                    )
                )
            )
        ) {
            $0.isLoading = false
            $0.errorMessage = PortKillerFailure.staleTarget.message
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = Date(timeIntervalSince1970: 0)
            $0.metadataByPID = refreshedMetadata
            $0.ports = [originalPort, additionalPort]
            $0.processGroups = refreshedSnapshot.processGroups
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [])
    }

    func testKillGroupPartialFailureShowsErrorAfterRefresh() async throws {
        let firstPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let secondPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3001,
            pid: 202,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101, 202])
        let initialSnapshot = makeSnapshot([firstPort, secondPort], metadata: metadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = initialSnapshot.ports
        initialState.processGroups = initialSnapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = PortGroupKillRequest(
            group: group,
            mode: .quit,
            metadataByPID: metadata
        )
        let failure = PortKillPIDFailure(pid: 202, message: "permission denied")
        let result = PortGroupKillResult(request: request, failures: [failure])
        let now = Date(timeIntervalSince1970: 7_000)
        let recorder = KillRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
            if pid == 202 {
                throw PortKillerFailure(message: "permission denied")
            }
        }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return metadata.filter { pids.contains($0.key) }
        }
        let scans = PortScanSequence([[firstPort, secondPort], []])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        await store.send(.view(.killGroupTapped(group, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.multipleProcesses(2)])
        }
        await store.send(.confirmationDialog(.presented(.confirmKillGroup(request)))) {
            $0.confirmationDialog = nil
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.portGroupKillFinished(result))) {
            $0.postRefreshErrorMessage = result.failureMessage
        }
        await store.receive(.response(.portsLoaded(.success(makeSnapshot([]))))) {
            $0.isLoading = false
            $0.errorMessage = result.failureMessage
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = [:]
            $0.ports = []
            $0.processGroups = []
        }

        let calls = await recorder.values()
        XCTAssertEqual(
            calls,
            [
                .init(pid: 101, mode: .quit),
                .init(pid: 202, mode: .quit)
            ]
        )
    }

    func testDismissConfirmationDoesNotKill() async {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let recorder = KillRecorder()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }

        let request = PortKillRequest(port: port, mode: .force)
        await store.send(.view(.killPortTapped(port, .force))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.forceKill])
        }
        await store.send(.confirmationDialog(.dismiss)) {
            $0.confirmationDialog = nil
        }

        let calls = await recorder.values()
        XCTAssertEqual(calls, [])
    }
}

private func makeSnapshot(
    _ ports: [PortEntry],
    metadata: [Int: PortProcessMetadata] = [:]
) -> PortScanSnapshot {
    PortScanSnapshot(
        ports: ports,
        metadataByPID: metadata,
        processGroups: PortProcessGroupingService.groups(
            for: ports,
            metadataByPID: metadata
        )
    )
}

private func appMetadata(for pids: [Int]) -> [Int: PortProcessMetadata] {
    Dictionary(
        uniqueKeysWithValues: pids.map { pid in
            (
                pid,
                PortProcessMetadata(
                    bundleIdentifier: "com.example.App",
                    name: "Example",
                    path: "/Applications/Example.app"
                )
            )
        }
    )
}

private struct KillCall: Equatable {
    let pid: Int
    let mode: PortKillMode
}

private actor KillRecorder {
    private var calls: [KillCall] = []

    func record(pid: Int, mode: PortKillMode) {
        calls.append(.init(pid: pid, mode: mode))
    }

    func values() -> [KillCall] {
        calls
    }
}

private actor PortScanSequence {
    private var values: [[PortEntry]]

    init(_ values: [[PortEntry]]) {
        self.values = values
    }

    func next() -> [PortEntry] {
        guard !values.isEmpty else {
            return []
        }
        return values.removeFirst()
    }
}

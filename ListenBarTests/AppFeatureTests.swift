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

    func testRefreshReplacesPorts() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "*",
            port: 3000,
            pid: 11,
            command: "old",
            user: nil
        )
        let newPort = PortEntry(
            networkProtocol: .udp,
            address: "*",
            port: 5353,
            pid: 22,
            command: "new",
            user: "501"
        )
        let now = Date(timeIntervalSince1970: 2_000)
        var initialState = AppFeature.State()
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portScanner.scan = { [newPort] }
        let snapshot = makeSnapshot([newPort])

        await store.send(.view(.refreshTapped)) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portsLoaded(.success(snapshot)))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = snapshot.metadataByPID
            $0.ports = [newPort]
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

        await store.send(.view(.refreshTapped)) {
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
        store.dependencies.portScanner.scan = { [refreshedPort] }

        let request = PortKillRequest(port: oldPort, mode: .quit)
        await store.send(.view(.killPortTapped(oldPort, .quit))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.success(request))))
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

        await store.send(.view(.killPortTapped(oldPort, .quit))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.failure(.init(message: "permission denied"))))) {
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
        store.dependencies.portScanner.scan = { [] }

        let request = PortKillRequest(port: port, mode: .force)
        await store.send(.view(.killPortTapped(port, .force))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.forceKill])
        }
        await store.send(.confirmationDialog(.presented(.confirmKill(request)))) {
            $0.confirmationDialog = nil
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.success(request))))
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

        let request = PortKillRequest(port: port, mode: .quit, processName: "sshd")
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

        let request = PortKillRequest(port: port, mode: .quit, processName: "WeChat")
        await store.send(.view(.killPortTapped(port, .quit))) {
            $0.confirmationDialog = request.confirmationDialog(warnings: [.appMainProcess])
        }
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

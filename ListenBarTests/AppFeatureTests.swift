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

    func testKillPortTerminatesPidThenRefreshesPorts() async {
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
        let recorder = PIDRecorder()
        var initialState = AppFeature.State()
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups
        let refreshedSnapshot = makeSnapshot([refreshedPort])

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portKiller.terminate = { pid in
            await recorder.record(pid)
        }
        store.dependencies.portScanner.scan = { [refreshedPort] }

        await store.send(.view(.killPortTapped(oldPort))) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(.response(.portKillFinished(.success(oldPort))))
        await store.receive(.response(.portsLoaded(.success(refreshedSnapshot)))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.lastUpdated = now
            $0.ports = [refreshedPort]
            $0.processGroups = refreshedSnapshot.processGroups
        }

        let terminatedPIDs = await recorder.values()
        XCTAssertEqual(terminatedPIDs, [oldPort.pid])
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
        store.dependencies.portKiller.terminate = { _ in
            throw PortKillerFailure(message: "permission denied")
        }

        await store.send(.view(.killPortTapped(oldPort))) {
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
}

private func makeSnapshot(
    _ ports: [PortEntry],
    metadata: [Int: PortProcessMetadata] = [:]
) -> PortScanSnapshot {
    PortScanSnapshot(
        ports: ports,
        processGroups: PortProcessGroupingService.groups(
            for: ports,
            metadataByPID: metadata
        )
    )
}

private actor PIDRecorder {
    private var pids: [Int] = []

    func record(_ pid: Int) {
        pids.append(pid)
    }

    func values() -> [Int] {
        pids
    }
}

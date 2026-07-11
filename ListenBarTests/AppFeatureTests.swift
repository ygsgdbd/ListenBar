import AppKit
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

    func testMenuPresentedDefersRefreshUntilDismissed() async {
        let now = Date(timeIntervalSince1970: 2_000)
        let ports = [
            PortEntry(
                networkProtocol: .tcp,
                address: "127.0.0.1",
                port: 8080,
                pid: 456,
                command: "miniserve",
                user: "501"
            )
        ]
        let snapshot = makeSnapshot(ports)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portScanner.scan = { ports }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.refreshPending = true
        }
        await store.send(.menuPresented)
        await store.send(.menuDismissed) {
            $0.isMenuPresented = false
            $0.refreshPending = false
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
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

    func testAutoRefreshTickWhileMenuPresentedQueuesRefresh() async {
        var initialState = AppFeature.State()
        initialState.isMenuPresented = true

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.autoRefreshTick) {
            $0.refreshPending = true
        }
        await store.send(.autoRefreshTick)
    }

    func testPortsLoadedSuccessWhileMenuPresentedIsDeferredUntilDismissed() async {
        let now = Date(timeIntervalSince1970: 2_500)
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 8080,
            pid: 456,
            command: "miniserve",
            user: "501"
        )
        let snapshot = makeSnapshot([port])
        var initialState = AppFeature.State()
        initialState.isLoading = true
        initialState.isMenuPresented = true

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)

        await store.send(.response(.portsLoaded(.success(snapshot)))) {
            $0.deferredMenuUpdate = .portsLoaded(.success(snapshot))
        }
        await store.send(.menuDismissed) {
            $0.deferredMenuUpdate = nil
            $0.isLoading = false
            $0.isMenuPresented = false
            $0.lastUpdated = now
            $0.metadataByPID = snapshot.metadataByPID
            $0.ports = [port]
            $0.processGroups = snapshot.processGroups
        }
    }

    func testPortsLoadedFailureWhileMenuPresentedIsDeferredUntilDismissed() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 5037,
            pid: 63759,
            command: "adb",
            user: "501"
        )
        var initialState = AppFeature.State()
        initialState.isLoading = true
        initialState.isMenuPresented = true
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        let failure = PortScannerFailure(message: "lsof failed")

        await store.send(.response(.portsLoaded(.failure(failure)))) {
            $0.deferredMenuUpdate = .portsLoaded(.failure(failure))
        }
        await store.send(.menuDismissed) {
            $0.deferredMenuUpdate = nil
            $0.isLoading = false
            $0.isMenuPresented = false
            $0.errorMessage = "lsof failed"
        }

        XCTAssertEqual(store.state.ports, [oldPort])
        XCTAssertEqual(store.state.processGroups, initialState.processGroups)
    }

    func testPortKillFailureWhileMenuPresentedIsDeferredUntilDismissed() async {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 5037,
            pid: 63759,
            command: "adb",
            user: "501"
        )
        var initialState = AppFeature.State()
        initialState.isLoading = true
        initialState.isMenuPresented = true
        initialState.ports = [port]
        initialState.processGroups = makeSnapshot([port]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        let failure = PortKillerFailure(message: "permission denied")
        let result = PortKillResult.failure(
            request: PortKillRequest(port: port, mode: .quit),
            failure: failure
        )

        await store.send(.response(.portKillFinished(result))) {
            $0.deferredMenuUpdate = .portKillFinished(result)
        }

        await store.send(.menuDismissed) {
            $0.deferredMenuUpdate = nil
            $0.isLoading = false
            $0.isMenuPresented = false
            $0.errorMessage = failure.message
        }
    }

    func testPortKillSnapshotWhileMenuPresentedIsDeferredUntilDismissed() async {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let refreshedPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 8080,
            pid: 202,
            command: "miniserve",
            user: "501"
        )
        let refreshedSnapshot = makeSnapshot([refreshedPort])
        var initialState = AppFeature.State()
        initialState.isLoading = true
        initialState.isMenuPresented = true
        initialState.ports = [oldPort]
        initialState.processGroups = makeSnapshot([oldPort]).processGroups

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        let now = Date(timeIntervalSince1970: 4_000)
        store.dependencies.date = .constant(now)
        let result = PortKillResult.aborted(
            request: PortKillRequest(port: oldPort, mode: .quit),
            refreshedSnapshot: refreshedSnapshot,
            failure: .staleTarget
        )

        await store.send(.response(.portKillFinished(result))) {
            $0.deferredMenuUpdate = .portKillFinished(result)
        }

        await store.send(.menuDismissed) {
            $0.deferredMenuUpdate = nil
            $0.isLoading = false
            $0.isMenuPresented = false
            $0.errorMessage = PortKillerFailure.staleTarget.message
            $0.lastUpdated = now
            $0.metadataByPID = refreshedSnapshot.metadataByPID
            $0.ports = refreshedSnapshot.ports
            $0.processGroups = refreshedSnapshot.processGroups
        }
    }

    func testPortGroupKillSnapshotWhileMenuPresentedIsDeferredUntilDismissed() async throws {
        let oldPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let refreshedPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 8080,
            pid: 202,
            command: "miniserve",
            user: "501"
        )
        let initialSnapshot = makeSnapshot([oldPort])
        let refreshedSnapshot = makeSnapshot([refreshedPort])
        var initialState = AppFeature.State()
        initialState.isLoading = true
        initialState.isMenuPresented = true
        initialState.ports = initialSnapshot.ports
        initialState.processGroups = initialSnapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let result = PortGroupKillResult(
            request: PortGroupKillRequest(
                group: group,
                mode: .quit,
                metadataByPID: initialState.metadataByPID
            ),
            failures: [.init(pid: 0, message: PortKillerFailure.staleTarget.message)],
            refreshedSnapshot: refreshedSnapshot
        )

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        let now = Date(timeIntervalSince1970: 5_000)
        store.dependencies.date = .constant(now)

        await store.send(.response(.portGroupKillFinished(result))) {
            $0.deferredMenuUpdate = .portGroupKillFinished(result)
        }

        await store.send(.menuDismissed) {
            $0.deferredMenuUpdate = nil
            $0.isLoading = false
            $0.isMenuPresented = false
            $0.errorMessage = result.failureMessage
            $0.lastUpdated = now
            $0.metadataByPID = refreshedSnapshot.metadataByPID
            $0.ports = refreshedSnapshot.ports
            $0.processGroups = refreshedSnapshot.processGroups
        }
    }

    func testMenuDismissedAppliesDeferredResultAndStartsSinglePendingRefresh() async {
        let firstPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let secondPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 8080,
            pid: 202,
            command: "miniserve",
            user: "501"
        )
        let firstSnapshot = makeSnapshot([firstPort])
        let secondSnapshot = makeSnapshot([secondPort])
        var initialState = AppFeature.State()
        initialState.isLoading = true
        initialState.isMenuPresented = true
        initialState.refreshPending = true

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 3_000))
        store.dependencies.portScanner.scan = { [secondPort] }

        await store.send(.response(.portsLoaded(.success(firstSnapshot)))) {
            $0.deferredMenuUpdate = .portsLoaded(.success(firstSnapshot))
        }
        await store.send(.menuDismissed) {
            $0.deferredMenuUpdate = nil
            $0.isMenuPresented = false
            $0.isLoading = true
            $0.lastUpdated = Date(timeIntervalSince1970: 3_000)
            $0.ports = [firstPort]
            $0.processGroups = firstSnapshot.processGroups
            $0.refreshPending = false
        }
        await store.receive(.response(.portsLoaded(.success(secondSnapshot)))) {
            $0.isLoading = false
            $0.lastUpdated = Date(timeIntervalSince1970: 3_000)
            $0.ports = [secondPort]
            $0.processGroups = secondSnapshot.processGroups
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

    func testMenuTrackingNotificationOnlyAcceptsRootMenu() {
        let rootMenu = NSMenu()
        let submenu = NSMenu()
        let submenuItem = NSMenuItem(title: "Submenu", action: nil, keyEquivalent: "")
        rootMenu.addItem(submenuItem)
        rootMenu.setSubmenu(submenu, for: submenuItem)

        XCTAssertTrue(
            MenuBarView.isRootMenuTrackingNotification(
                Notification(name: NSMenu.didBeginTrackingNotification, object: rootMenu)
            )
        )
        XCTAssertFalse(
            MenuBarView.isRootMenuTrackingNotification(
                Notification(name: NSMenu.didEndTrackingNotification, object: submenu)
            )
        )
        XCTAssertFalse(
            MenuBarView.isRootMenuTrackingNotification(
                Notification(name: NSMenu.didEndTrackingNotification, object: NSObject())
            )
        )
    }

    func testOnlyForceKillIsDestructive() {
        XCTAssertFalse(PortKillMode.quit.isDestructive)
        XCTAssertTrue(PortKillMode.force.isDestructive)
    }

    func testPortKillMenuTitlesAreConcise() {
        XCTAssertEqual(PortKillMode.quit.menuTitle, "终止进程")
        XCTAssertEqual(PortKillMode.force.menuTitle, "强制终止进程…")
        XCTAssertEqual(PortKillMode.quit.groupMenuTitle, "终止全部监听进程…")
        XCTAssertEqual(PortKillMode.force.groupMenuTitle, "强制终止全部监听进程…")
    }

    func testConfirmationsOnlyMarkForceKillAsDestructive() throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "node",
            user: "501"
        )
        let group = try XCTUnwrap(makeSnapshot([port]).processGroups.first)

        XCTAssertFalse(
            PortKillRequest(port: port, mode: .quit)
                .confirmation(warnings: [.systemProcess])
                .isDestructive
        )
        XCTAssertTrue(
            PortKillRequest(port: port, mode: .force)
                .confirmation(warnings: [.forceKill])
                .isDestructive
        )
        XCTAssertFalse(
            PortGroupKillRequest(group: group, mode: .quit)
                .confirmation(warnings: [.multipleProcesses(1)])
                .isDestructive
        )
        XCTAssertTrue(
            PortGroupKillRequest(group: group, mode: .force)
                .confirmation(warnings: [.forceKill])
                .isDestructive
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
        let notificationRecorder = NotificationRecorder()
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
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
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
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(notifications, [PortKillResult.success(request: request).notification])
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
        let notificationRecorder = NotificationRecorder()
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 4_000))
        store.dependencies.portKiller.terminate = { _, _ in
            throw PortKillerFailure(message: "permission denied")
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
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
        let failureResult = PortKillResult.failure(
            request: PortKillRequest(port: oldPort, mode: .quit),
            failure: .init(message: "permission denied")
        )
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(notifications, [failureResult.notification])
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
        let confirmationRecorder = ConfirmationRecorder(result: true)
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
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        let scans = PortScanSequence([[port], []])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        let request = PortKillRequest(port: port, mode: .force)
        await store.send(.view(.killPortTapped(port, .force)))
        await store.receive(.portKillConfirmationResponse(request, confirmed: true)) {
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
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
        let confirmations = await confirmationRecorder.values()
        XCTAssertEqual(confirmations, [request.confirmation(warnings: [.forceKill])])
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
        let confirmationRecorder = ConfirmationRecorder(result: false)
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }

        let request = PortKillRequest(
            port: port,
            mode: .quit,
            processName: "sshd",
            expectedExecutablePath: "/usr/sbin/sshd"
        )
        await store.send(.view(.killPortTapped(port, .quit)))
        await store.receive(.portKillConfirmationResponse(request, confirmed: false))
        let confirmations = await confirmationRecorder.values()
        XCTAssertEqual(confirmations, [request.confirmation(warnings: [.systemProcess])])
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
        let confirmationRecorder = ConfirmationRecorder(result: false)
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }

        let request = PortKillRequest(
            port: port,
            mode: .quit,
            processName: "WeChat",
            expectedExecutablePath: "/Applications/WeChat.app"
        )
        await store.send(.view(.killPortTapped(port, .quit)))
        await store.receive(.portKillConfirmationResponse(request, confirmed: false))
        let confirmations = await confirmationRecorder.values()
        XCTAssertEqual(confirmations, [request.confirmation(warnings: [.appMainProcess])])
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
        let notificationRecorder = NotificationRecorder()
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
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
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
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(
            notifications,
            [
                PortKillResult.aborted(
                    request: request,
                    refreshedSnapshot: refreshedSnapshot,
                    failure: .staleTarget
                ).notification
            ]
        )
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

    func testAutoRefreshIntervalTappedWhileMenuPresentedDefersRefresh() async {
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
        var initialState = AppFeature.State()
        initialState.isMenuPresented = true

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.continuousClock = clock
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portScanner.scan = { [port] }

        await store.send(.view(.autoRefreshIntervalTapped(.fiveSeconds))) {
            $0.autoRefreshInterval = .fiveSeconds
            $0.refreshPending = true
        }
        await clock.advance(by: .seconds(5))
        await store.receive(.autoRefreshTick)
        await store.send(.menuDismissed) {
            $0.isMenuPresented = false
            $0.refreshPending = false
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

    func testForceKillGroupRequiresConfirmationThenTerminatesUniquePIDsAndRefreshes() async throws {
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
            mode: .force,
            metadataByPID: metadata
        )
        let now = Date(timeIntervalSince1970: 6_000)
        let recorder = KillRecorder()
        let confirmationRecorder = ConfirmationRecorder(result: true)
        let notificationRecorder = NotificationRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return metadata.filter { pids.contains($0.key) }
        }
        let scans = PortScanSequence([[firstPort, secondPort, thirdPort], []])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        await store.send(.view(.killGroupTapped(group, .force)))
        await store.receive(.portGroupKillConfirmationResponse(request, confirmed: true)) {
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
                .init(pid: 101, mode: .force),
                .init(pid: 202, mode: .force)
            ]
        )
        let confirmations = await confirmationRecorder.values()
        XCTAssertEqual(
            confirmations,
            [request.confirmation(warnings: [.forceKill, .multipleProcesses(2)])]
        )
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(
            notifications,
            [PortGroupKillResult(request: request, failures: []).notification]
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
        let confirmationRecorder = ConfirmationRecorder(result: true)
        let notificationRecorder = NotificationRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }
        store.dependencies.portScanner.scan = { [port] }
        store.dependencies.portProcessMetadata.resolve = { _ in [:] }

        await store.send(.view(.killGroupTapped(group, .quit)))
        await store.receive(.portGroupKillConfirmationResponse(request, confirmed: true)) {
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
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(
            notifications,
            [
                PortGroupKillResult(
                    request: request,
                    failures: [.init(pid: 0, message: PortKillerFailure.staleTarget.message)],
                    refreshedSnapshot: refreshedSnapshot
                ).notification
            ]
        )
    }

    func testKillGroupPreflightScanFailureNotifiesAndShowsError() async throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example",
            user: "501"
        )
        let metadata = appMetadata(for: [101])
        let snapshot = makeSnapshot([port], metadata: metadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = snapshot.ports
        initialState.processGroups = snapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = PortGroupKillRequest(
            group: group,
            mode: .quit,
            metadataByPID: metadata
        )
        let failure = PortScannerFailure(message: "lsof failed")
        let result = PortGroupKillResult(
            request: request,
            failures: [.init(pid: 0, message: failure.message)]
        )
        let confirmationRecorder = ConfirmationRecorder(result: true)
        let notificationRecorder = NotificationRecorder()
        let killRecorder = KillRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }
        store.dependencies.portKiller.terminate = { pid, mode in
            await killRecorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portScanner.scan = {
            throw failure
        }

        await store.send(.view(.killGroupTapped(group, .quit)))
        await store.receive(.portGroupKillConfirmationResponse(request, confirmed: true)) {
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.portGroupKillFinished(result))) {
            $0.postRefreshErrorMessage = failure.message
        }
        await store.receive(.response(.portsLoaded(.failure(failure)))) {
            $0.isLoading = false
            $0.errorMessage = failure.message
            $0.postRefreshErrorMessage = nil
        }

        let calls = await killRecorder.values()
        XCTAssertEqual(calls, [])
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(notifications, [result.notification])
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
        let confirmationRecorder = ConfirmationRecorder(result: true)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portScanner.scan = { [originalPort, additionalPort] }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return refreshedMetadata.filter { pids.contains($0.key) }
        }

        await store.send(.view(.killGroupTapped(group, .quit)))
        await store.receive(.portGroupKillConfirmationResponse(request, confirmed: true)) {
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
        let confirmationRecorder = ConfirmationRecorder(result: true)
        let notificationRecorder = NotificationRecorder()

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
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }
        store.dependencies.portProcessMetadata.resolve = { ports in
            let pids = Set(ports.map(\.pid))
            return metadata.filter { pids.contains($0.key) }
        }
        let scans = PortScanSequence([[firstPort, secondPort], []])
        store.dependencies.portScanner.scan = {
            await scans.next()
        }

        await store.send(.view(.killGroupTapped(group, .quit)))
        await store.receive(.portGroupKillConfirmationResponse(request, confirmed: true)) {
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
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(notifications, [result.notification])
        XCTAssertEqual(result.notification.title, "部分进程发送 SIGTERM 失败")
        XCTAssertTrue(result.notification.body.contains("成功 1/2"))
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
        let confirmationRecorder = ConfirmationRecorder(result: false)
        let notificationRecorder = NotificationRecorder()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.portKiller.terminate = { pid, mode in
            await recorder.record(pid: pid, mode: mode)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }

        let request = PortKillRequest(port: port, mode: .force)
        await store.send(.view(.killPortTapped(port, .force)))
        await store.receive(.portKillConfirmationResponse(request, confirmed: false))

        let calls = await recorder.values()
        XCTAssertEqual(calls, [])
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(notifications, [])
    }

    func testNormalApplicationQuitDoesNotConfirmAndRefreshesPorts() async throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101])
        let snapshot = makeSnapshot([port], metadata: metadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = snapshot.ports
        initialState.processGroups = snapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = try XCTUnwrap(
            ApplicationQuitRequest(
                group: group,
                mode: .normal,
                metadataByPID: metadata
            )
        )
        let attempt = ApplicationQuitAttempt(
            matchedInstanceCount: 1,
            acceptedInstanceCount: 1
        )
        let result = ApplicationQuitResult(request: request, attempt: attempt)
        let now = Date(timeIntervalSince1970: 8_000)
        let quitRecorder = ApplicationQuitRecorder(attempt: attempt)
        let confirmationRecorder = ConfirmationRecorder(result: true)
        let notificationRecorder = NotificationRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.applicationQuitter.request = { request in
            await quitRecorder.request(request)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }
        store.dependencies.portScanner.scan = { [] }

        await store.send(.view(.quitApplicationTapped(group, .normal))) {
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.applicationQuitFinished(result)))
        await store.receive(.response(.portsLoaded(.success(makeSnapshot([]))))) {
            $0.isLoading = false
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
            $0.lastUpdated = now
            $0.metadataByPID = [:]
            $0.ports = []
            $0.processGroups = []
        }

        let requests = await quitRecorder.values()
        let confirmations = await confirmationRecorder.values()
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(requests, [request])
        XCTAssertEqual(confirmations, [])
        XCTAssertEqual(notifications, [result.notification])
    }

    func testForceApplicationQuitRequiresConfirmationAndCancellationStopsRequest() async throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101])
        let snapshot = makeSnapshot([port], metadata: metadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = snapshot.ports
        initialState.processGroups = snapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = try XCTUnwrap(
            ApplicationQuitRequest(
                group: group,
                mode: .force,
                metadataByPID: metadata
            )
        )
        let quitRecorder = ApplicationQuitRecorder(
            attempt: .init(matchedInstanceCount: 1, acceptedInstanceCount: 1)
        )
        let confirmationRecorder = ConfirmationRecorder(result: false)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.applicationQuitter.request = { request in
            await quitRecorder.request(request)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }

        await store.send(.view(.quitApplicationTapped(group, .force)))
        await store.receive(.applicationQuitConfirmationResponse(request, confirmed: false))

        let requests = await quitRecorder.values()
        let confirmations = await confirmationRecorder.values()
        XCTAssertEqual(requests, [])
        XCTAssertEqual(confirmations, [request.confirmation])
    }

    func testConfirmedForceApplicationQuitReportsPartialFailureAndRefreshesPorts() async throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101])
        let snapshot = makeSnapshot([port], metadata: metadata)
        var initialState = AppFeature.State()
        initialState.metadataByPID = metadata
        initialState.ports = snapshot.ports
        initialState.processGroups = snapshot.processGroups
        let group = try XCTUnwrap(initialState.processGroups.first)
        let request = try XCTUnwrap(
            ApplicationQuitRequest(
                group: group,
                mode: .force,
                metadataByPID: metadata
            )
        )
        let attempt = ApplicationQuitAttempt(
            matchedInstanceCount: 2,
            acceptedInstanceCount: 1
        )
        let result = ApplicationQuitResult(request: request, attempt: attempt)
        let now = Date(timeIntervalSince1970: 9_000)
        let quitRecorder = ApplicationQuitRecorder(attempt: attempt)
        let confirmationRecorder = ConfirmationRecorder(result: true)
        let notificationRecorder = NotificationRecorder()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.applicationQuitter.request = { request in
            await quitRecorder.request(request)
        }
        store.dependencies.portKillConfirmation.confirm = { confirmation in
            await confirmationRecorder.confirm(confirmation)
        }
        store.dependencies.portKillNotification.send = { notification in
            await notificationRecorder.record(notification)
        }
        store.dependencies.portScanner.scan = { [] }

        await store.send(.view(.quitApplicationTapped(group, .force)))
        await store.receive(.applicationQuitConfirmationResponse(request, confirmed: true)) {
            $0.isLoading = true
            $0.errorMessage = nil
            $0.postRefreshErrorMessage = nil
        }
        await store.receive(.response(.applicationQuitFinished(result))) {
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

        let requests = await quitRecorder.values()
        let confirmations = await confirmationRecorder.values()
        let notifications = await notificationRecorder.values()
        XCTAssertEqual(requests, [request])
        XCTAssertEqual(confirmations, [request.confirmation])
        XCTAssertEqual(notifications, [result.notification])
    }

    func testApplicationQuitResultReportsMissingRejectedAndPartialRequests() throws {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper",
            user: "501"
        )
        let metadata = appMetadata(for: [101])
        let group = try XCTUnwrap(makeSnapshot([port], metadata: metadata).processGroups.first)
        let request = try XCTUnwrap(
            ApplicationQuitRequest(
                group: group,
                mode: .force,
                metadataByPID: metadata
            )
        )

        let missing = ApplicationQuitResult(
            request: request,
            attempt: .init(matchedInstanceCount: 0, acceptedInstanceCount: 0)
        )
        let rejected = ApplicationQuitResult(
            request: request,
            attempt: .init(matchedInstanceCount: 2, acceptedInstanceCount: 0)
        )
        let partial = ApplicationQuitResult(
            request: request,
            attempt: .init(matchedInstanceCount: 2, acceptedInstanceCount: 1)
        )

        XCTAssertNotNil(missing.failureMessage)
        XCTAssertNotNil(rejected.failureMessage)
        XCTAssertNotNil(partial.failureMessage)
        XCTAssertTrue(missing.notification.title.contains("失败"))
        XCTAssertTrue(rejected.notification.title.contains("失败"))
        XCTAssertTrue(partial.notification.title.contains("部分"))
        XCTAssertTrue(partial.notification.body.contains("1/2"))
    }

    func testApplicationQuitRequestRejectsProcessGroupsAndCollectsMatchingBundlePaths() throws {
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
        let metadata = [
            101: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app"
            ),
            202: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Users/example/Applications/Example.app"
            )
        ]
        let appGroup = try XCTUnwrap(
            makeSnapshot([firstPort, secondPort], metadata: metadata).processGroups.first
        )
        let request = try XCTUnwrap(
            ApplicationQuitRequest(
                group: appGroup,
                mode: .normal,
                metadataByPID: metadata
            )
        )
        let processGroup = try XCTUnwrap(makeSnapshot([firstPort]).processGroups.first)

        XCTAssertEqual(request.bundleIdentifier, "com.example.App")
        XCTAssertEqual(
            request.bundlePaths,
            [
                "/Applications/Example.app",
                "/Users/example/Applications/Example.app"
            ]
        )
        XCTAssertNil(
            ApplicationQuitRequest(
                group: processGroup,
                mode: .normal,
                metadataByPID: [:]
            )
        )
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

private actor ConfirmationRecorder {
    private let result: Bool
    private var confirmations: [PortKillConfirmation] = []

    init(result: Bool) {
        self.result = result
    }

    func confirm(_ confirmation: PortKillConfirmation) -> Bool {
        confirmations.append(confirmation)
        return result
    }

    func values() -> [PortKillConfirmation] {
        confirmations
    }
}

private actor NotificationRecorder {
    private var notifications: [PortKillNotification] = []

    func record(_ notification: PortKillNotification) {
        notifications.append(notification)
    }

    func values() -> [PortKillNotification] {
        notifications
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

private actor ApplicationQuitRecorder {
    private let attempt: ApplicationQuitAttempt
    private var requests: [ApplicationQuitRequest] = []

    init(attempt: ApplicationQuitAttempt) {
        self.attempt = attempt
    }

    func request(_ request: ApplicationQuitRequest) -> ApplicationQuitAttempt {
        requests.append(request)
        return attempt
    }

    func values() -> [ApplicationQuitRequest] {
        requests
    }
}

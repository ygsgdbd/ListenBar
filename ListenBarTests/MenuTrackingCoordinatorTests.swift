import AppKit
import Combine
import ComposableArchitecture
@testable import ListenBar
import Sparkle
import XCTest

@MainActor
final class MenuTrackingCoordinatorTests: XCTestCase {
    func testRootMenuEventsReleaseBothPathsInTheOriginalOrder() {
        let center = NotificationCenter()
        let original = snapshot(pid: 101)
        let refreshed = snapshot(pid: 202)
        let store = makeStore(snapshot: original)
        let monitor = SparkleUpdateMonitor()
        let coordinator = MenuTrackingCoordinator(store: store, updateMonitor: monitor, notificationCenter: center)
        defer { withExtendedLifetime(coordinator) {} }
        let menu = NSMenu()
        let update = SUAppcastItem.empty()
        var publishedStatuses: [SparkleUpdateMonitor.Status] = []
        var wasMenuPresentedAtPublication: [Bool] = []
        let subscription = monitor.$status.dropFirst().sink { status in
            XCTAssertTrue(Thread.isMainThread)
            publishedStatuses.append(status)
            wasMenuPresentedAtPublication.append(store.withState { $0.isMenuPresented })
        }
        defer { subscription.cancel() }

        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        XCTAssertTrue(store.withState { $0.isMenuPresented })

        store.send(.response(.portsLoaded(.success(refreshed))))
        monitor.handleScheduledUpdate(update)
        XCTAssertEqual(store.withState { $0.ports }, original.ports)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(publishedStatuses, [])

        center.post(name: NSMenu.didEndTrackingNotification, object: menu)

        XCTAssertFalse(store.withState { $0.isMenuPresented })
        XCTAssertEqual(store.withState { $0.ports }, refreshed.ports)
        XCTAssertEqual(monitor.status, .updateAvailable(version: update.displayVersionString))
        XCTAssertEqual(publishedStatuses, [.updateAvailable(version: update.displayVersionString)])
        XCTAssertEqual(wasMenuPresentedAtPublication, [true])
    }

    func testNonRootBeginNotificationsDoNotFreezeEitherPath() {
        let center = NotificationCenter()
        let store = makeStore(snapshot: snapshot(pid: 101))
        let monitor = SparkleUpdateMonitor()
        let coordinator = MenuTrackingCoordinator(store: store, updateMonitor: monitor, notificationCenter: center)
        defer { withExtendedLifetime(coordinator) {} }
        let rootMenu = NSMenu()
        let submenu = addSubmenu(to: rootMenu)
        let mainMenu = NSMenu()
        let originalMainMenu = NSApp.mainMenu
        NSApp.mainMenu = mainMenu
        defer { NSApp.mainMenu = originalMainMenu }

        for object: Any in [mainMenu, submenu, NSObject()] {
            center.post(name: NSMenu.didBeginTrackingNotification, object: object)
        }
        let refreshed = snapshot(pid: 202)
        let update = SUAppcastItem.empty()
        store.send(.response(.portsLoaded(.success(refreshed))))
        monitor.handleScheduledUpdate(update)

        XCTAssertFalse(store.withState { $0.isMenuPresented })
        XCTAssertEqual(store.withState { $0.ports }, refreshed.ports)
        XCTAssertEqual(monitor.status, .updateAvailable(version: update.displayVersionString))
    }

    func testNonRootEndNotificationsDoNotReleaseEitherPath() {
        let center = NotificationCenter()
        let original = snapshot(pid: 101)
        let refreshed = snapshot(pid: 202)
        let store = makeStore(snapshot: original)
        let monitor = SparkleUpdateMonitor()
        let coordinator = MenuTrackingCoordinator(store: store, updateMonitor: monitor, notificationCenter: center)
        defer { withExtendedLifetime(coordinator) {} }
        let rootMenu = NSMenu()
        let submenu = addSubmenu(to: rootMenu)
        let mainMenu = NSMenu()
        let originalMainMenu = NSApp.mainMenu
        NSApp.mainMenu = mainMenu
        defer { NSApp.mainMenu = originalMainMenu }
        let update = SUAppcastItem.empty()

        center.post(name: NSMenu.didBeginTrackingNotification, object: rootMenu)
        store.send(.response(.portsLoaded(.success(refreshed))))
        monitor.handleScheduledUpdate(update)
        for object: Any in [mainMenu, submenu, NSObject()] {
            center.post(name: NSMenu.didEndTrackingNotification, object: object)
        }

        XCTAssertTrue(store.withState { $0.isMenuPresented })
        XCTAssertEqual(store.withState { $0.ports }, original.ports)
        XCTAssertEqual(monitor.status, .idle)

        center.post(name: NSMenu.didEndTrackingNotification, object: rootMenu)
        XCTAssertFalse(store.withState { $0.isMenuPresented })
        XCTAssertEqual(store.withState { $0.ports }, refreshed.ports)
        XCTAssertEqual(monitor.status, .updateAvailable(version: update.displayVersionString))
    }

    func testRepeatedEndStillAppliesCurrentVisibilityRules() {
        let center = NotificationCenter()
        let original = snapshot(pid: 101)
        let store = makeStore(snapshot: original)
        let coordinator = MenuTrackingCoordinator(
            store: store, updateMonitor: SparkleUpdateMonitor(), notificationCenter: center,
        )
        defer { withExtendedLifetime(coordinator) {} }
        let menu = NSMenu()

        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        store.withState { state in
            state.$settings.withLock {
                $0.ignore(.executable(path: "/opt/homebrew/bin/node", displayName: "node"))
            }
        }
        XCTAssertEqual(store.withState { $0.ports }, original.ports)

        center.post(name: NSMenu.didEndTrackingNotification, object: menu)

        XCTAssertEqual(store.withState { $0.ports }, [])
        XCTAssertEqual(store.withState { $0.ignoredProcessGroupCount }, 1)
    }

    func testReadmeAppearanceAppliesToSubmenuBeforeRootFiltering() throws {
        let center = NotificationCenter()
        let store = makeStore(snapshot: snapshot(pid: 101))
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let coordinator = MenuTrackingCoordinator(
            store: store, updateMonitor: SparkleUpdateMonitor(), readmeMenuAppearance: appearance,
            notificationCenter: center,
        )
        defer { withExtendedLifetime(coordinator) {} }
        let rootMenu = NSMenu()
        let submenu = addSubmenu(to: rootMenu)
        let childMenu = addSubmenu(to: submenu)
        rootMenu.appearance = NSAppearance(named: .aqua)
        submenu.appearance = NSAppearance(named: .aqua)
        childMenu.appearance = NSAppearance(named: .aqua)

        center.post(name: NSMenu.didBeginTrackingNotification, object: submenu)

        XCTAssertEqual(rootMenu.appearance?.name, .aqua)
        XCTAssertEqual(submenu.appearance?.name, .darkAqua)
        XCTAssertEqual(childMenu.appearance?.name, .darkAqua)
        XCTAssertFalse(store.withState { $0.isMenuPresented })
    }

    func testReleasingCoordinatorRemovesBothObservers() {
        let center = NotificationCenter()
        let original = snapshot(pid: 101)
        let refreshed = snapshot(pid: 202)
        let store = makeStore(snapshot: original)
        let monitor = SparkleUpdateMonitor()
        var coordinator: MenuTrackingCoordinator? = MenuTrackingCoordinator(
            store: store, updateMonitor: monitor, notificationCenter: center,
        )
        weak var weakCoordinator = coordinator
        let menu = NSMenu()
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        XCTAssertTrue(store.withState { $0.isMenuPresented })
        coordinator = nil
        XCTAssertNil(weakCoordinator)

        store.send(.response(.portsLoaded(.success(refreshed))))
        monitor.handleScheduledUpdate(.empty())
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        XCTAssertTrue(store.withState { $0.isMenuPresented })
        XCTAssertEqual(store.withState { $0.ports }, original.ports)
        XCTAssertEqual(monitor.status, .idle)

        monitor.menuTrackingDidEnd()
        store.send(.menuDismissed)
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        XCTAssertFalse(store.withState { $0.isMenuPresented })
    }

    private func makeStore(snapshot: PortScanSnapshot) -> StoreOf<AppFeature> {
        var state = AppFeature.State()
        state.portVisibility = PortVisibility(snapshot: snapshot)
        state.$settings.withLock {
            $0.autoRefresh = .off
            $0.ignoredProcesses = []
        }
        return Store(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_000))
        }
    }

    private func snapshot(pid: Int) -> PortScanSnapshot {
        let port = PortEntry(networkProtocol: .tcp, address: "127.0.0.1", port: 3000, pid: pid, command: "node", user: "501")
        let metadata = [pid: PortProcessMetadata.executable(name: "node", path: "/opt/homebrew/bin/node")]
        return PortScanSnapshot(
            ports: [port], metadataByPID: metadata,
            processGroups: PortProcessGroupingService.groups(for: [port], metadataByPID: metadata),
        )
    }

    private func addSubmenu(to menu: NSMenu) -> NSMenu {
        let submenu = NSMenu()
        let item = NSMenuItem(title: "Submenu", action: nil, keyEquivalent: "")
        menu.addItem(item)
        menu.setSubmenu(submenu, for: item)
        return submenu
    }
}

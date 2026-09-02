@testable import ListenBar
import Sparkle
import XCTest

@MainActor
final class SparkleUpdateMonitorTests: XCTestCase {
    func testStartSilentCheckBeginsProbingAndDisablesMenuAction() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 1)
        XCTAssertEqual(monitor.status, .checking)
        XCTAssertFalse(monitor.isMenuActionEnabled)
        XCTAssertEqual(monitor.menuTitle, String(localized: "正在检查更新…", bundle: .main))
    }

    func testStartSilentCheckSkipsActiveUpdaterSession() {
        let updater = SparkleUpdaterSpy(sessionInProgress: true)
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 0)
        XCTAssertEqual(monitor.status, .idle)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testFoundUpdateShowsDisplayVersionAfterInformationCheckFinishes() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.startSilentCheck(using: updater)

        monitor.updater(delegateUpdater, didFindValidUpdate: update)

        XCTAssertEqual(monitor.status, .checking)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)

        XCTAssertEqual(monitor.status, .updateAvailable(version: update.displayVersionString))
        XCTAssertEqual(
            monitor.menuTitle,
            String(
                format: String(localized: "新版本 %@ 可用…", bundle: .main),
                locale: Locale.current,
                update.displayVersionString,
            ),
        )
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testSuccessfulCheckWithoutUpdateRestoresIdleState() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: noUpdateError,
        )

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertEqual(monitor.menuTitle, String(localized: "检查更新…", bundle: .main))
    }

    func testNoUpdateClearsPreviouslyKnownUpdate() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.updater(delegateUpdater, didFindValidUpdate: .empty())
        monitor.startSilentCheck(using: updater)

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: noUpdateError,
        )

        XCTAssertEqual(monitor.status, .idle)
    }

    func testFailedCheckPreservesPreviouslyKnownUpdate() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()
        monitor.updater(delegateUpdater, didFindValidUpdate: update)
        monitor.startSilentCheck(using: updater)

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: TestError(),
        )

        XCTAssertEqual(monitor.status, .updateAvailable(version: update.displayVersionString))
    }

    func testFailedCheckDoesNotPublishPendingUpdate() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)
        monitor.updater(delegateUpdater, didFindValidUpdate: .empty())

        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updateInformation,
            error: TestError(),
        )

        XCTAssertEqual(monitor.status, .idle)
    }

    func testScheduledUpdateUsesGentleReminderAndUpdatesMenuState() {
        let monitor = SparkleUpdateMonitor()
        let update = SUAppcastItem.empty()

        XCTAssertNoThrow(try monitor.updater(delegateUpdater, mayPerform: .updatesInBackground))
        XCTAssertEqual(monitor.status, .checking)
        XCTAssertFalse(monitor.isMenuActionEnabled)

        monitor.updater(delegateUpdater, didFindValidUpdate: update)

        let standardDriverHandlesUpdate = monitor.standardUserDriverShouldHandleShowingScheduledUpdate(
            update,
            andInImmediateFocus: true,
        )

        XCTAssertTrue(monitor.supportsGentleScheduledUpdateReminders)
        XCTAssertFalse(standardDriverHandlesUpdate)
        monitor.handleScheduledUpdate(update)

        XCTAssertEqual(monitor.status, .updateAvailable(version: update.displayVersionString))
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testScheduledNoUpdateRestoresIdleState() {
        let monitor = SparkleUpdateMonitor()

        XCTAssertNoThrow(try monitor.updater(delegateUpdater, mayPerform: .updatesInBackground))
        monitor.updater(
            delegateUpdater,
            didFinishUpdateCycleFor: .updatesInBackground,
            error: noUpdateError,
        )

        XCTAssertEqual(monitor.status, .idle)
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testUserCheckUsesCanCheckForUpdatesEvenWhenSessionIsActive() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()
        monitor.startSilentCheck(using: updater)

        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userInitiatedCheckCount, 0)

        monitor.updater(delegateUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        updater.sessionInProgress = true
        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userInitiatedCheckCount, 1)

        updater.canCheckForUpdates = false
        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userInitiatedCheckCount, 1)
    }

    private var delegateUpdater: SPUUpdater {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        ).updater
    }

    private var noUpdateError: NSError {
        NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue),
        )
    }
}

private struct TestError: Error {}

@MainActor
private final class SparkleUpdaterSpy: SparkleUpdateChecking {
    var canCheckForUpdates: Bool
    var sessionInProgress: Bool
    private(set) var informationCheckCount = 0
    private(set) var userInitiatedCheckCount = 0

    init(canCheckForUpdates: Bool = true, sessionInProgress: Bool = false) {
        self.canCheckForUpdates = canCheckForUpdates
        self.sessionInProgress = sessionInProgress
    }

    func checkForUpdateInformation() {
        informationCheckCount += 1
    }

    func checkForUpdates() {
        userInitiatedCheckCount += 1
    }
}

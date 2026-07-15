@testable import ListenBar
import XCTest

@MainActor
final class SparkleUpdateMonitorTests: XCTestCase {
    func testSilentCheckUsesInformationProbeAndDisablesMenuUntilFinished() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        XCTAssertEqual(monitor.menuTitle, "检查更新…")
        XCTAssertTrue(monitor.isMenuActionEnabled)

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 1)
        XCTAssertEqual(updater.userInitiatedCheckCount, 0)
        XCTAssertEqual(monitor.menuTitle, "检查更新…")
        XCTAssertFalse(monitor.isMenuActionEnabled)
    }

    func testActiveUpdateSessionSkipsSilentCheckAndKeepsMenuEnabled() {
        let updater = SparkleUpdaterSpy()
        updater.sessionInProgress = true
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)

        XCTAssertEqual(updater.informationCheckCount, 0)
        XCTAssertEqual(monitor.menuTitle, "检查更新…")
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testFoundUpdateChangesMenuOnlyAfterSilentCheckFinishes() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)
        monitor.recordFoundUpdate()

        XCTAssertEqual(monitor.menuTitle, "检查更新…")
        XCTAssertFalse(monitor.isMenuActionEnabled)

        monitor.finishSilentCheck()

        XCTAssertEqual(monitor.menuTitle, "发现新版本…")
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testNoUpdateRestoresDefaultMenuState() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)
        monitor.finishSilentCheck()

        XCTAssertEqual(monitor.menuTitle, "检查更新…")
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testFailureDoesNotReportAnUpdateEvenIfOneWasFoundEarlier() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)
        monitor.recordFoundUpdate()
        monitor.finishSilentCheck(error: TestError())

        XCTAssertEqual(monitor.menuTitle, "检查更新…")
        XCTAssertTrue(monitor.isMenuActionEnabled)
    }

    func testUserInitiatedCheckOnlyRunsWhenSilentCheckIsFinished() {
        let updater = SparkleUpdaterSpy()
        let monitor = SparkleUpdateMonitor()

        monitor.startSilentCheck(using: updater)
        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userInitiatedCheckCount, 0)

        monitor.finishSilentCheck()
        monitor.showUpdate(using: updater)

        XCTAssertEqual(updater.userInitiatedCheckCount, 1)
    }
}

private struct TestError: Error {}

@MainActor
private final class SparkleUpdaterSpy: SparkleUpdateChecking {
    var sessionInProgress = false
    private(set) var informationCheckCount = 0
    private(set) var userInitiatedCheckCount = 0

    func checkForUpdateInformation() {
        informationCheckCount += 1
    }

    func checkForUpdates() {
        userInitiatedCheckCount += 1
    }
}

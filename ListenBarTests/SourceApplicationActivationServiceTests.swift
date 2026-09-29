@testable import ListenBar
import XCTest

final class SourceApplicationActivationServiceTests: XCTestCase {
    func testOnlyMatchingRunningInstanceIsActivated() {
        let target = source()
        var activations = 0
        let result = SourceApplicationActivationService.activate(
            target, current: source(name: "Localized name"), canActivate: true,
            performActivation: { activations += 1; return true },
        )
        XCTAssertEqual(result, .success)
        XCTAssertEqual(activations, 1)
    }

    func testMissingOrReplacedInstanceNeverActivates() {
        let target = source()
        let cases: [SourceApplication?] = [
            nil,
            source(pid: 202),
            source(bundleIdentifier: "com.example.Other"),
            source(bundlePath: "/Users/example/Applications/Editor.app"),
            source(launchDate: Date(timeIntervalSince1970: 200)),
        ]
        for current in cases {
            let result = SourceApplicationActivationService.activate(
                target, current: current, canActivate: true,
                performActivation: { XCTFail("Must not activate a stale instance"); return true },
            )
            XCTAssertEqual(result, .stale)
        }
    }

    func testNonActivatableApplicationDoesNotAttemptActivation() {
        let result = SourceApplicationActivationService.activate(
            source(), current: source(), canActivate: false,
            performActivation: { XCTFail("Must not activate prohibited applications"); return true },
        )
        XCTAssertEqual(result, .failed)
    }

    func testRejectedActivationReturnsFailure() {
        let result = SourceApplicationActivationService.activate(
            source(), current: source(), canActivate: true,
            performActivation: { false },
        )
        XCTAssertEqual(result, .failed)
    }

    private func source(
        name: String = "Editor",
        pid: Int = 101,
        bundleIdentifier: String = "com.example.Editor",
        bundlePath: String = "/Applications/Editor.app",
        launchDate: Date = Date(timeIntervalSince1970: 100),
    ) -> SourceApplication {
        SourceApplication(name: name, pid: pid, bundleIdentifier: bundleIdentifier, bundlePath: bundlePath, launchDate: launchDate)
    }
}

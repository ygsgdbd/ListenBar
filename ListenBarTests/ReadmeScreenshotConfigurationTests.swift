import AppKit
import ComposableArchitecture
@testable import ListenBar
import XCTest

final class ReadmeScreenshotConfigurationTests: XCTestCase {
    func testArgumentsWithoutReadmeDemoDisableScreenshotMode() {
        XCTAssertNil(
            ReadmeScreenshotConfiguration(arguments: ["ListenBar"]),
        )
    }

    func testArgumentsSelectRequestedAppearance() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: [
                    "ListenBar",
                    "--readme-demo",
                    "--readme-appearance",
                    "dark",
                ],
            ),
        )

        XCTAssertEqual(configuration.appearance, .dark)
        XCTAssertEqual(configuration.colorScheme, .dark)
    }

    func testMissingAppearanceDefaultsToLight() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: ["ListenBar", "--readme-demo"],
            ),
        )

        XCTAssertEqual(configuration.appearance, .light)
    }

    func testArgumentsSelectRequestedDisplay() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: [
                    "ListenBar",
                    "--readme-demo",
                    "--readme-display-id",
                    "42",
                ],
            ),
        )

        XCTAssertEqual(configuration.requestedDisplayID, 42)
    }

    func testHighestResolutionDisplayUsesPixelArea() {
        let displays = [
            ReadmeScreenshotConfiguration.Display(id: 1, pixelWidth: 2560, pixelHeight: 1440),
            ReadmeScreenshotConfiguration.Display(id: 2, pixelWidth: 3840, pixelHeight: 2160),
            ReadmeScreenshotConfiguration.Display(id: 3, pixelWidth: 3008, pixelHeight: 1692),
        ]

        XCTAssertEqual(
            ReadmeScreenshotConfiguration.highestResolutionDisplayID(in: displays),
            2,
        )
    }

    @MainActor
    func testDarkAppearanceCanBeAppliedToNativeMenus() throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: [
                    "ListenBar",
                    "--readme-demo",
                    "--readme-appearance",
                    "dark",
                ],
            ),
        )
        let menu = NSMenu(title: "")

        configuration.applyAppearance(to: menu)

        XCTAssertEqual(menu.appearance?.name, .darkAqua)
    }

    func testDemoStateIsDeterministicAndCoversPrimaryMenuContent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: ["ListenBar", "--readme-demo"],
            ),
        )

        let state = configuration.initialState(now: now)

        XCTAssertEqual(state.lastUpdated, now)
        XCTAssertTrue(state.isReadmeDemo)
        XCTAssertEqual(state.ports.count, 4)
        XCTAssertEqual(state.processGroups.count, 3)
        XCTAssertEqual(
            Set(state.processGroups.map(\.classification)),
            [.user, .systemOrOtherUser],
        )

        let applicationGroup = try XCTUnwrap(
            state.processGroups.first { $0.id == "app:com.apple.Terminal" },
        )
        XCTAssertEqual(applicationGroup.displayName, "Terminal")
        XCTAssertEqual(applicationGroup.ports.map(\.port), [3000, 5173])
        XCTAssertTrue(applicationGroup.ports.allSatisfy { $0.localhostURL != nil })

        XCTAssertEqual(Set(state.metadataByPID.keys), Set(state.ports.map(\.pid)))
        XCTAssertTrue(
            state.metadataByPID.values.allSatisfy {
                $0.path?.contains("/Users/") != true
                    && $0.commandLine?.contains("/Users/") != true
            },
        )
    }

    @MainActor
    func testDemoStateIgnoresLiveTaskAndActions() async throws {
        let configuration = try XCTUnwrap(
            ReadmeScreenshotConfiguration(
                arguments: ["ListenBar", "--readme-demo"],
            ),
        )
        let state = configuration.initialState(now: Date())
        let port = try XCTUnwrap(state.ports.first)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.launchAtLoginClient.status = {
                XCTFail("README demo mode must not read login item state")
                return .disabled
            }
            $0.launchAtLoginClient.setEnabled = { _ in
                XCTFail("README demo mode must not change login item state")
                return .disabled
            }
            $0.portScanner.scan = {
                XCTFail("README demo mode must not scan live ports")
                return []
            }
            $0.portKiller.terminate = { _, _ in
                XCTFail("README demo mode must not terminate live processes")
            }
        }

        await store.send(.task)
        await store.send(.menuPresented) {
            $0.isMenuPresented = true
        }
        await store.send(.view(.setLaunchAtLogin(true)))
        await store.send(.view(.killPortTapped(port, .quit)))
    }
}

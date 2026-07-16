import Dependencies
import Foundation
@testable import ListenBar
import Sharing
import XCTest

final class AppSettingsTests: XCTestCase {
    func testUsesBundleScopedApplicationSupportPath() {
        XCTAssertTrue(
            AppSettings.storageURL.path.hasSuffix(
                "/Library/Application Support/top.ygsgdbd.ListenBar/settings.json",
            ),
        )
    }

    func testEncodesOnMenuOpenWithExactJSON() throws {
        let settings = AppSettings(autoRefresh: .onMenuOpen)

        XCTAssertEqual(
            try encodedJSON(settings),
            #"{"autoRefresh":{"type":"onMenuOpen"},"ignoredProcesses":[]}"#,
        )
    }

    func testEncodesFixedSecondsAsNumberWithoutLegacyCaseName() throws {
        let settings = AppSettings(autoRefresh: .fixed(seconds: 2))

        let json = try encodedJSON(settings)

        XCTAssertEqual(
            json,
            #"{"autoRefresh":{"seconds":2,"type":"fixed"},"ignoredProcesses":[]}"#,
        )
        XCTAssertFalse(json.contains("twoSeconds"))
    }

    func testEncodesOffWithExactJSON() throws {
        let settings = AppSettings(autoRefresh: .off)

        XCTAssertEqual(
            try encodedJSON(settings),
            #"{"autoRefresh":{"type":"off"},"ignoredProcesses":[]}"#,
        )
    }

    func testEncodingNonPositiveFixedSecondsFallsBackToOnMenuOpen() throws {
        for seconds in [0, -1] {
            XCTAssertEqual(
                try encodedJSON(AppSettings(autoRefresh: .fixed(seconds: seconds))),
                #"{"autoRefresh":{"type":"onMenuOpen"},"ignoredProcesses":[]}"#,
            )
        }
    }

    func testMissingAutoRefreshFallsBackToOnMenuOpen() throws {
        let settings = try decodeSettings(from: #"{}"#)

        XCTAssertEqual(settings.autoRefresh, .onMenuOpen)
        XCTAssertEqual(settings.ignoredProcesses, [])
    }

    func testIgnoredProcessesRoundTripAndDeduplicateByStableIdentity() throws {
        let settings = AppSettings(
            autoRefresh: .off,
            ignoredProcesses: [
                .application(
                    bundleIdentifier: "com.example.App",
                    displayName: "Example",
                ),
                .application(
                    bundleIdentifier: "com.example.App",
                    displayName: "Renamed Example",
                ),
                .executable(
                    path: "/opt/homebrew/bin/node",
                    displayName: "node",
                ),
                .executable(
                    path: "node",
                    displayName: "invalid node",
                ),
            ],
        )

        XCTAssertEqual(
            try encodedJSON(settings),
            #"{"autoRefresh":{"type":"off"},"ignoredProcesses":[{"displayName":"Example","identifier":"com.example.App","kind":"application"},{"displayName":"node","identifier":"\/opt\/homebrew\/bin\/node","kind":"executable"}]}"#,
        )
    }

    func testInvalidIgnoredProcessesAreDiscardedWhenDecoding() throws {
        let settings = try decodeSettings(
            from: #"{"ignoredProcesses":[{"displayName":"Invalid","identifier":"node","kind":"executable"},{"displayName":"Example","identifier":"com.example.App","kind":"application"}]}"#,
        )

        XCTAssertEqual(
            settings.ignoredProcesses,
            [
                .application(
                    bundleIdentifier: "com.example.App",
                    displayName: "Example",
                ),
            ],
        )
    }

    func testIgnoreAndRestoreUseStableIdentity() {
        var settings = AppSettings()
        let original = IgnoredProcessItem.application(
            bundleIdentifier: "com.example.App",
            displayName: "Example",
        )
        let renamed = IgnoredProcessItem.application(
            bundleIdentifier: "com.example.App",
            displayName: "Renamed Example",
        )

        settings.ignore(original)
        settings.ignore(renamed)
        XCTAssertEqual(settings.ignoredProcesses, [original])

        settings.restore(renamed)
        XCTAssertEqual(settings.ignoredProcesses, [])
    }

    func testUnknownAutoRefreshTypeFallsBackToOnMenuOpen() throws {
        let settings = try decodeSettings(
            from: #"{"autoRefresh":{"type":"futureMode"}}"#,
        )

        XCTAssertEqual(settings.autoRefresh, .onMenuOpen)
    }

    func testNonPositiveFixedSecondsFallBackToOnMenuOpen() throws {
        for seconds in [0, -1] {
            let settings = try decodeSettings(
                from: #"{"autoRefresh":{"type":"fixed","seconds":\#(seconds)}}"#,
            )

            XCTAssertEqual(settings.autoRefresh, .onMenuOpen)
        }
    }

    func testFileStoragePersistsStructuredSettingsAndReloadsThem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(component: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try withDependencies {
            $0.defaultFileStorage = .fileSystem
        } operation: {
            @Shared(.fileStorage(url)) var settings = AppSettings()
            $settings.withLock {
                $0.autoRefresh = .fixed(seconds: 2)
            }

            XCTAssertEqual(
                try encodedJSON(JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))),
                #"{"autoRefresh":{"seconds":2,"type":"fixed"},"ignoredProcesses":[]}"#,
            )
        }
    }

    func testCorruptFileStorageFallsBackWithoutCrashing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(component: "settings.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        withDependencies {
            $0.defaultFileStorage = .fileSystem
        } operation: {
            @Shared(.fileStorage(url)) var settings = AppSettings()

            XCTAssertEqual(settings, AppSettings())
            XCTAssertNotNil($settings.loadError)
        }
    }

    private func encodedJSON(_ settings: AppSettings) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(settings), encoding: .utf8))
    }

    private func decodeSettings(from json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }
}

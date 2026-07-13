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
            #"{"autoRefresh":{"type":"onMenuOpen"}}"#,
        )
    }

    func testEncodesFixedSecondsAsNumberWithoutLegacyCaseName() throws {
        let settings = AppSettings(autoRefresh: .fixed(seconds: 2))

        let json = try encodedJSON(settings)

        XCTAssertEqual(
            json,
            #"{"autoRefresh":{"seconds":2,"type":"fixed"}}"#,
        )
        XCTAssertFalse(json.contains("twoSeconds"))
    }

    func testEncodesOffWithExactJSON() throws {
        let settings = AppSettings(autoRefresh: .off)

        XCTAssertEqual(
            try encodedJSON(settings),
            #"{"autoRefresh":{"type":"off"}}"#,
        )
    }

    func testEncodingNonPositiveFixedSecondsFallsBackToOnMenuOpen() throws {
        for seconds in [0, -1] {
            XCTAssertEqual(
                try encodedJSON(AppSettings(autoRefresh: .fixed(seconds: seconds))),
                #"{"autoRefresh":{"type":"onMenuOpen"}}"#,
            )
        }
    }

    func testMissingAutoRefreshFallsBackToOnMenuOpen() throws {
        let settings = try decodeSettings(from: #"{}"#)

        XCTAssertEqual(settings.autoRefresh, .onMenuOpen)
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
                #"{"autoRefresh":{"seconds":2,"type":"fixed"}}"#,
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

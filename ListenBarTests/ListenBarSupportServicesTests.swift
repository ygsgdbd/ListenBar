import Foundation
@testable import ListenBar
import XCTest

final class ListenBarSupportServicesTests: XCTestCase {
    func testAppInfoServiceCentralizesListenBarSupportURLs() throws {
        XCTAssertEqual(AppInfoService.githubAccount, "ygsgdbd")
        XCTAssertEqual(AppInfoService.githubRepository, "ygsgdbd/ListenBar")
        XCTAssertEqual(
            try XCTUnwrap(AppInfoService.githubProfileURL).absoluteString,
            "https://github.com/ygsgdbd",
        )
        XCTAssertEqual(
            try XCTUnwrap(AppInfoService.githubRepositoryURL).absoluteString,
            "https://github.com/ygsgdbd/ListenBar",
        )
        XCTAssertEqual(
            try XCTUnwrap(AppInfoService.helpURL).absoluteString,
            "https://github.com/ygsgdbd/ListenBar#readme",
        )
        XCTAssertEqual(
            try XCTUnwrap(AppInfoService.issueReportURL).absoluteString,
            "https://github.com/ygsgdbd/ListenBar/issues/new",
        )
        XCTAssertNil(AppInfoService.issueReportURL?.query)
    }

    func testSupportDiagnosticsReportsOnlyLowSensitivityEnvironmentFields() {
        let diagnostics = SupportDiagnostics(
            version: "1.2.3",
            build: "45",
            operatingSystemVersion: "Version 15.6 (Build 24G84)",
            architecture: "arm64",
            appLanguage: "zh-Hans",
            localeIdentifier: "zh_CN",
        )

        XCTAssertEqual(
            diagnostics.reportText,
            """
            Version: 1.2.3
            Build: 45
            macOS: Version 15.6 (Build 24G84)
            Architecture: arm64
            App Language: zh-Hans
            Locale: zh_CN
            """,
        )
        XCTAssertEqual(diagnostics.reportText.components(separatedBy: "\n").count, 6)

        let forbiddenLabels = ["Port:", "PID:", "Path:", "Command:"]
        for label in forbiddenLabels {
            XCTAssertFalse(diagnostics.reportText.contains(label), label)
        }
    }

    func testSupportDiagnosticsUsesPlaceholderForMissingOrBlankValues() {
        let diagnostics = SupportDiagnostics(
            version: nil,
            build: "",
            operatingSystemVersion: "  ",
            architecture: "\n",
            appLanguage: nil,
            localeIdentifier: "\t",
        )

        XCTAssertEqual(diagnostics.version, "–")
        XCTAssertEqual(diagnostics.build, "–")
        XCTAssertEqual(diagnostics.operatingSystemVersion, "–")
        XCTAssertEqual(diagnostics.architecture, "–")
        XCTAssertEqual(diagnostics.appLanguage, "–")
        XCTAssertEqual(diagnostics.localeIdentifier, "–")
    }

    func testCurrentSupportDiagnosticsPopulatesAllFields() {
        let diagnostics = SupportDiagnostics.current()

        XCTAssertFalse(diagnostics.version.isEmpty)
        XCTAssertFalse(diagnostics.build.isEmpty)
        XCTAssertFalse(diagnostics.operatingSystemVersion.isEmpty)
        XCTAssertFalse(diagnostics.architecture.isEmpty)
        XCTAssertFalse(diagnostics.appLanguage.isEmpty)
        XCTAssertFalse(diagnostics.localeIdentifier.isEmpty)
    }
}

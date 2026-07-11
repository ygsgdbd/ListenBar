import XCTest

@MainActor
final class SparkleConfigurationTests: XCTestCase {
    func testSparkleInfoPlistConfiguration() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://github.com/ygsgdbd/ListenBar/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "J+ZJPF3atcveHHVhQk2hXnQwfNiAzfUNUflfBKpQKgc="
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool,
            false
        )
    }

    func testSwiftUIAppDoesNotDeclareMainStoryboard() {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "NSMainStoryboardFile")
        )
    }

    func testEnglishProcessDetailsLocalization() throws {
        let localizationURL = try XCTUnwrap(
            Bundle.main.url(forResource: "en", withExtension: "lproj")
        )
        let englishBundle = try XCTUnwrap(Bundle(url: localizationURL))

        XCTAssertEqual(
            englishBundle.localizedString(
                forKey: "进程详情",
                value: nil,
                table: nil
            ),
            "Process Details"
        )
    }
}

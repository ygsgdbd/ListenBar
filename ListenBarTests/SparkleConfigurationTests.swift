import XCTest

@MainActor
final class SparkleConfigurationTests: XCTestCase {
    func testSparkleInfoPlistConfiguration() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://github.com/ygsgdbd/ListenBar/releases/latest/download/appcast.xml",
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "J+ZJPF3atcveHHVhQk2hXnQwfNiAzfUNUflfBKpQKgc=",
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool,
            false,
        )
    }

    func testSwiftUIAppDoesNotDeclareMainStoryboard() {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "NSMainStoryboardFile"),
        )
    }

    func testEnglishProcessDetailsLocalization() throws {
        let localizationURL = try XCTUnwrap(
            Bundle.main.url(forResource: "en", withExtension: "lproj"),
        )
        let englishBundle = try XCTUnwrap(Bundle(url: localizationURL))

        XCTAssertEqual(
            englishBundle.localizedString(
                forKey: "进程详情",
                value: nil,
                table: nil,
            ),
            "Process Details",
        )
    }

    func testEnglishMenuCountLocalizationsUseSingularAndPluralUnits() throws {
        let localizationURL = try XCTUnwrap(
            Bundle.main.url(forResource: "en", withExtension: "lproj"),
        )
        let englishBundle = try XCTUnwrap(Bundle(url: localizationURL))

        XCTAssertEqual(localizedCount("%lld 个监听进程", count: 1, bundle: englishBundle), "1 Listening Process")
        XCTAssertEqual(localizedCount("%lld 个监听进程", count: 2, bundle: englishBundle), "2 Listening Processes")
        XCTAssertEqual(localizedCount("%lld 个进程", count: 1, bundle: englishBundle), "1 process")
        XCTAssertEqual(localizedCount("%lld 个进程", count: 2, bundle: englishBundle), "2 processes")
        XCTAssertEqual(localizedCount("%lld 个端口", count: 1, bundle: englishBundle), "1 port")
        XCTAssertEqual(localizedCount("%lld 个端口", count: 2, bundle: englishBundle), "2 ports")
    }

    private func localizedCount(_ key: String, count: Int64, bundle: Bundle) -> String {
        String(
            format: bundle.localizedString(forKey: key, value: nil, table: nil),
            locale: Locale(identifier: "en"),
            count,
        )
    }
}

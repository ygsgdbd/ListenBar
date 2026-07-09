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
}

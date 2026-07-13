import Foundation
import XCTest

final class LocalizationCatalogTests: XCTestCase {
    func testCatalogContainsEverySupportedLocalization() throws {
        let strings = try Self.catalogStrings()

        XCTAssertEqual(strings.count, 90)
        XCTAssertNil(strings["进程"])

        for (key, entry) in strings {
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "Missing localizations for \(key)")
            XCTAssertEqual(Set(localizations.keys), ["en", "zh-Hans", "zh-Hant"], "Unexpected localizations for \(key)")

            for localization in ["en", "zh-Hans", "zh-Hant"] {
                let localizedValue = try XCTUnwrap(localizations[localization], "Missing \(localization) localization for \(key)")
                let stringUnits = Self.stringUnits(in: localizedValue)

                XCTAssertFalse(stringUnits.isEmpty, "Missing string unit for \(localization) localization of \(key)")
                for stringUnit in stringUnits {
                    XCTAssertEqual(stringUnit["state"] as? String, "translated", "Untranslated \(localization) localization for \(key)")
                    XCTAssertFalse((stringUnit["value"] as? String)?.isEmpty ?? true, "Empty \(localization) localization for \(key)")
                }
            }
        }
    }

    func testLocalizedPlaceholdersMatchSourceKeys() throws {
        for (key, entry) in try Self.catalogStrings() {
            let expectedPlaceholders = Self.placeholders(in: key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])

            for (localization, localizedValue) in localizations {
                for stringUnit in Self.stringUnits(in: localizedValue) {
                    let value = try XCTUnwrap(stringUnit["value"] as? String)
                    XCTAssertEqual(
                        Self.placeholders(in: value),
                        expectedPlaceholders,
                        "Placeholder signature differs for \(localization) localization of \(key)",
                    )
                }
            }
        }
    }

    func testSimplifiedChineseValuesMatchSourceKeys() throws {
        for (key, entry) in try Self.catalogStrings() {
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let simplifiedChinese = try XCTUnwrap(localizations["zh-Hans"])
            let values = Self.stringUnits(in: simplifiedChinese).compactMap { $0["value"] as? String }

            XCTAssertEqual(values, [key], "Simplified Chinese source value differs for \(key)")
        }
    }

    func testEnglishCopyUsesSharedMenuConventions() throws {
        let expectedValues = [
            "正在扫描…": "Scanning…",
            "复制 lsof 命令": "Copy lsof Command",
            "复制全部端口": "Copy All Ports",
            "复制启动命令": "Copy Launch Command",
            "复制脱敏启动命令": "Copy Redacted Launch Command",
            "自动刷新：%@": "Auto Refresh: %@",
            "终止进程 (SIGTERM)": "Terminate Process (SIGTERM)",
            "终止全部监听进程 (SIGTERM)": "Terminate All Listening Processes (SIGTERM)",
            "强制终止进程…": "Force Kill Process…",
            "强制终止全部监听进程…": "Force Kill All Listening Processes…",
            "SIGKILL 无法由进程处理。": "SIGKILL cannot be handled by the process.",
        ]

        try Self.assertLocalizedValues(expectedValues, localization: "en")
    }

    func testTraditionalChineseUsesTaiwanTerminology() throws {
        let expectedValues = [
            "登录时打开": "登入時開啟",
            "打开登录项设置": "開啟登入項目設定",
            "请前往“系统设置”>“通用”>“登录项”允许 ListenBar。": "請前往「系統設定」>「一般」>「登入項目」允許 ListenBar。",
            "GitHub 仓库": "GitHub 儲存庫",
            "仅本机": "僅限本機",
            "所有网络接口": "所有網路介面",
            "指定网络接口": "指定網路介面",
            "%lld 个监听进程": "%lld 個監聽程序",
            "%lld 个进程": "%lld 個程序",
            "%lld 个端口": "%lld 個連接埠",
            "终止进程 (SIGTERM)": "終止程序 (SIGTERM)",
            "强制终止进程…": "強制終止程序…",
        ]

        try Self.assertLocalizedValues(expectedValues, localization: "zh-Hant")
    }

    func testTraditionalChineseBundleIsBuilt() throws {
        XCTAssertTrue(Bundle.main.localizations.contains("zh-Hant"))

        let localizationURL = try XCTUnwrap(Bundle.main.url(forResource: "zh-Hant", withExtension: "lproj"))
        let traditionalChineseBundle = try XCTUnwrap(Bundle(url: localizationURL))

        XCTAssertEqual(
            traditionalChineseBundle.localizedString(forKey: "进程详情", value: nil, table: nil),
            "程序詳細資訊",
        )
    }

    private static func assertLocalizedValues(
        _ expectedValues: [String: String],
        localization: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let strings = try catalogStrings()

        for (key, expectedValue) in expectedValues {
            let entry = try XCTUnwrap(strings[key], "Missing catalog key \(key)", file: file, line: line)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], file: file, line: line)
            let localizedValue = try XCTUnwrap(localizations[localization], file: file, line: line)
            let values = stringUnits(in: localizedValue).compactMap { $0["value"] as? String }
            XCTAssertTrue(values.contains(expectedValue), "Unexpected \(localization) localization for \(key): \(values)", file: file, line: line)
        }
    }

    private static func catalogStrings() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: [String: Any]])
    }

    private static func stringUnits(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var units: [[String: Any]] = []
            if let stringUnit = dictionary["stringUnit"] as? [String: Any] {
                units.append(stringUnit)
            }
            for nestedValue in dictionary.values {
                units.append(contentsOf: stringUnits(in: nestedValue))
            }
            return units
        }
        if let array = value as? [Any] {
            return array.flatMap(stringUnits(in:))
        }
        return []
    }

    private static func placeholders(in value: String) -> [String] {
        let pattern = #"%(?:lld|d|@)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let placeholderRange = Range(match.range, in: value) else { return nil }
            return String(value[placeholderRange])
        }
    }

    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ListenBar/Resources/Localizable.xcstrings")
    }
}

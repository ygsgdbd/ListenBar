import Foundation

struct SupportDiagnostics: Equatable {
    let version: String
    let build: String
    let operatingSystemVersion: String
    let architecture: String
    let appLanguage: String
    let localeIdentifier: String

    init(
        version: String?,
        build: String?,
        operatingSystemVersion: String?,
        architecture: String?,
        appLanguage: String?,
        localeIdentifier: String?,
    ) {
        self.version = Self.valueOrPlaceholder(version)
        self.build = Self.valueOrPlaceholder(build)
        self.operatingSystemVersion = Self.valueOrPlaceholder(operatingSystemVersion)
        self.architecture = Self.valueOrPlaceholder(architecture)
        self.appLanguage = Self.valueOrPlaceholder(appLanguage)
        self.localeIdentifier = Self.valueOrPlaceholder(localeIdentifier)
    }

    static func current() -> Self {
        let bundle = Bundle.main

        return Self(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            appLanguage: bundle.preferredLocalizations.first,
            localeIdentifier: Locale.current.identifier,
        )
    }

    var reportText: String {
        [
            "Version: \(version)",
            "Build: \(build)",
            "macOS: \(operatingSystemVersion)",
            "Architecture: \(architecture)",
            "App Language: \(appLanguage)",
            "Locale: \(localeIdentifier)",
        ].joined(separator: "\n")
    }

    private static func valueOrPlaceholder(_ value: String?) -> String {
        guard let value else { return "–" }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? "–" : trimmedValue
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}

import ProjectDescription

let appVersion = Environment.appVersion.getString(default: "0.0.0")
let buildVersion = Environment.buildVersion.getString(default: "0")

let project = Project(
    name: "ListenBar",
    options: .options(
        defaultKnownRegions: ["zh-Hans", "en"],
        developmentRegion: "zh-Hans"
    ),
    packages: [
        .remote(
            url: "https://github.com/pointfreeco/swift-case-paths",
            requirement: .upToNextMajor(from: "1.7.3")
        ),
        .remote(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            requirement: .upToNextMajor(from: "1.25.5")
        ),
        .remote(
            url: "https://github.com/pointfreeco/swift-clocks",
            requirement: .upToNextMajor(from: "1.1.0")
        ),
        .remote(
            url: "https://github.com/pointfreeco/swift-dependencies",
            requirement: .upToNextMajor(from: "1.12.0")
        ),
        .remote(
            url: "https://github.com/pointfreeco/swift-perception",
            requirement: .upToNextMajor(from: "2.0.10")
        ),
        .remote(
            url: "https://github.com/pointfreeco/swift-sharing",
            requirement: .upToNextMajor(from: "2.0.0")
        ),
        .remote(
            url: "https://github.com/pointfreeco/swift-navigation",
            requirement: .upToNextMajor(from: "2.10.3")
        ),
        .remote(
            url: "https://github.com/sparkle-project/Sparkle",
            requirement: .upToNextMajor(from: "2.9.4")
        ),
        .remote(
            url: "https://github.com/SwifterSwift/SwifterSwift",
            requirement: .upToNextMajor(from: "8.0.0")
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "DEVELOPMENT_LANGUAGE": "zh-Hans",
            "MARKETING_VERSION": SettingValue(stringLiteral: appVersion),
            "CURRENT_PROJECT_VERSION": SettingValue(stringLiteral: buildVersion),
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ENABLE_MACROS": "YES",
            "SWIFT_MACRO_DEBUGGING": "YES"
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ]
    ),
    targets: [
        .target(
            name: "ListenBar",
            destinations: .macOS,
            product: .app,
            bundleId: "top.ygsgdbd.ListenBar",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "CFBundleDevelopmentRegion": "zh-Hans",
                "CFBundleLocalizations": ["zh-Hans", "en"],
                "LSApplicationCategoryType": "public.app-category.utilities",
                "LSMinimumSystemVersion": "14.0",
                "NSHumanReadableCopyright": "Copyright © 2026 ygsgdbd. All rights reserved.",
                "CFBundleShortVersionString": .string(appVersion),
                "CFBundleVersion": .string(buildVersion),
                "SUFeedURL": "https://github.com/ygsgdbd/ListenBar/releases/latest/download/appcast.xml",
                "SUPublicEDKey": "J+ZJPF3atcveHHVhQk2hXnQwfNiAzfUNUflfBKpQKgc=",
                "SUEnableAutomaticChecks": false
            ]),
            sources: ["ListenBar/Sources/**"],
            resources: ["ListenBar/Resources/**"],
            dependencies: [
                .package(product: "CasePaths"),
                .package(product: "ComposableArchitecture"),
                .package(product: "Dependencies"),
                .package(product: "PerceptionCore"),
                .package(product: "Sharing"),
                .package(product: "Sparkle"),
                .package(product: "SwiftNavigation"),
                .package(product: "SwifterSwift")
            ],
            settings: .settings(
                base: [
                    "OTHER_CODE_SIGN_FLAGS": "--deep",
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "ENABLE_MACROS": "YES",
                    "SWIFT_MACRO_DEBUGGING": "YES",
                    "SWIFT_MACRO_EXPANSION": "YES"
                ],
                configurations: [
                    .debug(name: "Debug"),
                    .release(name: "Release")
                ]
            )
        ),
        .target(
            name: "ListenBarTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "top.ygsgdbd.ListenBarTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ListenBarTests/**"],
            dependencies: [
                .package(product: "CasePaths"),
                .package(product: "Clocks"),
                .target(name: "ListenBar"),
                .package(product: "ComposableArchitecture"),
                .package(product: "Dependencies"),
                .package(product: "Sharing"),
                .package(product: "SwiftNavigation")
            ],
            settings: .settings(
                base: [
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "SWIFT_VERSION": "5.9",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ListenBar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ListenBar",
                    "TEST_TARGET_NAME": "ListenBar"
                ],
                configurations: [
                    .debug(name: "Debug"),
                    .release(name: "Release")
                ]
            )
        )
    ]
)

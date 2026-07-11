import Darwin
import XCTest
@testable import ListenBar

final class PortProcessMetadataServiceTests: XCTestCase {
    func testApplicationBundleResolutionReturnsOwnerAndProcessAppsForNestedHelperPath() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let resolution = PortProcessMetadataService.applicationBundleResolution(forExecutablePath: path)

        XCTAssertEqual(
            resolution?.ownerBundleURL.path,
            "/Applications/Google Chrome.app"
        )
        XCTAssertEqual(
            resolution?.processBundleURL.path,
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app"
        )
        XCTAssertEqual(
            PortProcessMetadataService.applicationBundleURL(forExecutablePath: path)?.path,
            "/Applications/Google Chrome.app"
        )
    }

    func testApplicationBundleURLReturnsAppForMainExecutablePath() {
        let path = "/Applications/Example.app/Contents/MacOS/Example"

        XCTAssertEqual(
            PortProcessMetadataService.applicationBundleURL(forExecutablePath: path)?.path,
            "/Applications/Example.app"
        )
    }

    func testApplicationBundleURLIgnoresRegularExecutablePath() {
        let path = "/opt/homebrew/bin/node"

        XCTAssertNil(PortProcessMetadataService.applicationBundleURL(forExecutablePath: path))
    }

    func testApplicationBundleURLIgnoresFilesOutsideContentsMacOS() {
        let path = "/Applications/Example.app/Contents/Resources/tool"

        XCTAssertNil(PortProcessMetadataService.applicationBundleURL(forExecutablePath: path))
    }

    func testProcessDetailNameStripsOwnerAppName() {
        XCTAssertEqual(
            PortProcessMetadataService.processDetailName(
                processName: "GitHub Desktop Helper (Renderer)",
                ownerName: "GitHub Desktop"
            ),
            "Helper (Renderer)"
        )
        XCTAssertEqual(
            PortProcessMetadataService.processDetailName(
                processName: "Google Chrome Helper",
                ownerName: "Google Chrome"
            ),
            "Helper"
        )
    }

    func testProcessDetailNameReturnsNilForOwnerProcess() {
        XCTAssertNil(
            PortProcessMetadataService.processDetailName(
                processName: "GitHub Desktop",
                ownerName: "GitHub Desktop"
            )
        )
    }

    func testCommandLineStringQuotesArgumentsAndSummarizesLongCommands() {
        let commandLine = PortProcessMetadataService.commandLineString(
            arguments: [
                "/opt/homebrew/bin/node",
                "server.js",
                "--name",
                "hello world"
            ]
        )

        XCTAssertEqual(
            commandLine,
            "/opt/homebrew/bin/node server.js --name 'hello world'"
        )
        XCTAssertEqual(
            PortProcessMetadataService.commandLineSummary(for: "1234567890", limit: 8),
            "12345..."
        )
    }

    func testRedactedCommandLineStringRedactsSensitiveArguments() {
        let commandLine = PortProcessMetadataService.redactedCommandLineString(
            arguments: [
                "/opt/homebrew/bin/node",
                "server.js",
                "--token",
                "abc123",
                "--password=secret value",
                "API_KEY=private",
                "--name",
                "hello"
            ]
        )

        XCTAssertEqual(
            commandLine,
            "/opt/homebrew/bin/node server.js --token <redacted> --password=<redacted> API_KEY=<redacted> --name hello"
        )
    }

    func testInferredSourcesCombineBasePackageManagerAndLauncher() {
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/opt/homebrew/bin/node",
                applicationPath: nil,
                parentProcessNames: ["Terminal"]
            ),
            [.executable, .homebrew, .terminal]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/Users/example/.nvm/node",
                applicationPath: nil,
                parentProcessNames: ["Code Helper", "Visual Studio Code"]
            ),
            [.executable, .visualStudioCode]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/usr/libexec/exampled",
                applicationPath: nil,
                parentProcessNames: ["launchd"]
            ),
            [.system]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/Applications/Example.app/Contents/MacOS/Example",
                applicationPath: "/Applications/Example.app",
                parentProcessNames: ["launchd"]
            ),
            [.application]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: nil,
                applicationPath: nil,
                parentProcessNames: []
            ),
            [.unknown]
        )
    }

    func testInferredSourcesRecognizePackageManagerPathsWithoutTreatingUsrLocalBinAsHomebrew() {
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/usr/local/Cellar/postgresql/17/bin/postgres",
                applicationPath: nil,
                parentProcessNames: []
            ),
            [.executable, .homebrew]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/opt/local/bin/nginx",
                applicationPath: nil,
                parentProcessNames: []
            ),
            [.executable, .macPorts]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/nix/store/example-node/bin/node",
                applicationPath: nil,
                parentProcessNames: []
            ),
            [.executable, .nix]
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: "/usr/local/bin/custom-tool",
                applicationPath: nil,
                parentProcessNames: []
            ),
            [.executable]
        )
    }

    func testInferredSourcesResolvePackageManagerSymlinks() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("node")
        try FileManager.default.createSymbolicLink(
            atPath: executableURL.path,
            withDestinationPath: "/nix/store/example-node/bin/node"
        )

        XCTAssertEqual(
            PortProcessMetadataService.inferredSources(
                executablePath: executableURL.path,
                applicationPath: nil,
                parentProcessNames: []
            ),
            [.executable, .nix]
        )
    }

    func testResidentMemoryBytesRequiresCompleteTaskInfo() {
        var taskInfo = proc_taskinfo()
        taskInfo.pti_resident_size = 5_452_595

        XCTAssertEqual(
            PortProcessMetadataService.residentMemoryBytes(
                from: taskInfo,
                result: Int32(MemoryLayout<proc_taskinfo>.size)
            ),
            5_452_595
        )
        XCTAssertNil(
            PortProcessMetadataService.residentMemoryBytes(
                from: taskInfo,
                result: 0
            )
        )
    }

    func testResidentMemoryBytesReadsCurrentProcess() {
        XCTAssertNotNil(
            PortProcessMetadataService.residentMemoryBytes(for: Int(getpid()))
        )
    }

    func testFallbackMetadataKeepsUnreadablePIDVisible() {
        let port = PortEntry(
            networkProtocol: .tcp,
            address: "*",
            port: 80,
            pid: 1,
            command: "launchd",
            user: "0"
        )

        let metadata = PortProcessMetadataService.fallbackMetadata(
            for: port,
            processName: nil,
            uid: nil,
            residentMemoryBytes: nil
        )

        XCTAssertEqual(metadata.name, "launchd")
        XCTAssertNil(metadata.path)
        XCTAssertNil(metadata.residentMemoryBytes)
        XCTAssertEqual(metadata.sources, [.unknown])
        XCTAssertEqual(metadata.classification, .systemOrOtherUser)
    }

    func testProcessClassificationUsesUIDAndSystemPaths() {
        XCTAssertEqual(
            PortProcessMetadataService.processClassification(
                uid: 501,
                executablePath: "/Users/example/bin/server",
                applicationPath: nil,
                currentUID: 501
            ),
            .user
        )
        XCTAssertEqual(
            PortProcessMetadataService.processClassification(
                uid: 0,
                executablePath: "/Users/example/bin/server",
                applicationPath: nil,
                currentUID: 501
            ),
            .systemOrOtherUser
        )
        XCTAssertEqual(
            PortProcessMetadataService.processClassification(
                uid: 502,
                executablePath: "/Users/example/bin/server",
                applicationPath: nil,
                currentUID: 501
            ),
            .systemOrOtherUser
        )
        XCTAssertEqual(
            PortProcessMetadataService.processClassification(
                uid: 501,
                executablePath: "/usr/sbin/sshd",
                applicationPath: nil,
                currentUID: 501
            ),
            .systemOrOtherUser
        )
    }

    func testProcessClassificationRecognizesProtectedMacOSContentRoots() {
        let systemPaths = [
            "/Library/Apple/System/Library/PrivateFrameworks/RemotePairing.framework/Versions/A/XPCServices/remotepairingd.xpc/Contents/MacOS/remotepairingd",
            "/Library/Apple/usr/libexec/rpmuxd",
            "/usr/bin/python3",
            "/usr/libexec/rapportd",
            "/usr/sbin/sshd",
            "/bin/zsh",
            "/sbin/mount",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari"
        ]

        for path in systemPaths {
            XCTAssertEqual(
                PortProcessMetadataService.processClassification(
                    uid: 501,
                    executablePath: path,
                    applicationPath: nil,
                    currentUID: 501
                ),
                .systemOrOtherUser,
                path
            )
        }
    }

    func testProcessClassificationExcludesUsrLocalFromProtectedUsrRoot() {
        XCTAssertEqual(
            PortProcessMetadataService.processClassification(
                uid: 501,
                executablePath: "/usr/local/bin/custom-tool",
                applicationPath: nil,
                currentUID: 501
            ),
            .user
        )
    }

    func testInferredSourcesRecognizeAppleManagedContentRootsAsSystem() {
        let systemPaths = [
            "/Library/Apple/System/Library/PrivateFrameworks/RemotePairing.framework/Versions/A/XPCServices/remotepairingd.xpc/Contents/MacOS/remotepairingd",
            "/Library/Apple/usr/libexec/rpmuxd",
            "/usr/bin/python3"
        ]

        for path in systemPaths {
            XCTAssertEqual(
                PortProcessMetadataService.inferredSources(
                    executablePath: path,
                    applicationPath: nil,
                    parentProcessNames: ["launchd"]
                ),
                [.system],
                path
            )
        }
    }
}

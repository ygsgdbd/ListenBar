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

    func testInferredSourceUsesPathAndParentProcessNames() {
        XCTAssertEqual(
            PortProcessMetadataService.inferredSource(
                executablePath: "/opt/homebrew/bin/node",
                applicationPath: nil,
                parentProcessNames: ["Terminal"]
            ),
            .homebrew
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSource(
                executablePath: "/Users/example/.nvm/node",
                applicationPath: nil,
                parentProcessNames: ["Code Helper", "Visual Studio Code"]
            ),
            .visualStudioCode
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSource(
                executablePath: "/usr/libexec/exampled",
                applicationPath: nil,
                parentProcessNames: []
            ),
            .system
        )
        XCTAssertEqual(
            PortProcessMetadataService.inferredSource(
                executablePath: nil,
                applicationPath: nil,
                parentProcessNames: []
            ),
            .unknown
        )
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
}

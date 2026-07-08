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
}

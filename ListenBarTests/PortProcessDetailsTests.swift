@testable import ListenBar
import XCTest

final class PortProcessDetailsTests: XCTestCase {
    func testApplicationPathSelectorReturnsOneUnambiguousOuterAppPath() throws {
        let rendererPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 101,
            command: "Example Helper (Renderer)",
            user: "501",
        )
        let gpuPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3001,
            pid: 102,
            command: "Example Helper (GPU)",
            user: "501",
        )
        let electronMetadata = [
            101: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
                processDetailName: "Helper (Renderer)",
                executablePath: "/Applications/Example.app/Contents/Frameworks/Example Helper (Renderer).app/Contents/MacOS/Example Helper (Renderer)",
            ),
            102: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
                processDetailName: "Helper (GPU)",
                executablePath: "/Applications/Example.app/Contents/Frameworks/Example Helper (GPU).app/Contents/MacOS/Example Helper (GPU)",
            ),
        ]
        let electronGroup = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [rendererPort, gpuPort],
                metadataByPID: electronMetadata,
            ).first,
        )

        XCTAssertEqual(
            PortProcessInfoItems(group: electronGroup, metadataByPID: electronMetadata).applicationPath,
            "/Applications/Example.app",
        )
        XCTAssertEqual(
            PortProcessDetails(metadata: electronMetadata[rendererPort.pid]).path,
            "/Applications/Example.app/Contents/Frameworks/Example Helper (Renderer).app/Contents/MacOS/Example Helper (Renderer)",
        )

        let mainPort = PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 4000,
            pid: 201,
            command: "Ordinary",
            user: "501",
        )
        let mainMetadata = [
            201: PortProcessMetadata(
                bundleIdentifier: "com.example.Ordinary",
                name: "Ordinary",
                path: "/Applications/Ordinary.app",
                executablePath: "/Applications/Ordinary.app/Contents/MacOS/Ordinary",
            ),
        ]
        let mainGroup = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [mainPort],
                metadataByPID: mainMetadata,
            ).first,
        )

        XCTAssertEqual(
            PortProcessInfoItems(group: mainGroup, metadataByPID: mainMetadata).applicationPath,
            "/Applications/Ordinary.app",
        )

        let cliMetadata = [
            201: PortProcessMetadata.executable(
                name: "node",
                path: "/opt/homebrew/bin/node",
            ),
        ]
        let cliGroup = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [mainPort],
                metadataByPID: cliMetadata,
            ).first,
        )
        XCTAssertNil(PortProcessInfoItems(group: cliGroup, metadataByPID: cliMetadata).applicationPath)

        let missingPathMetadata = [
            201: PortProcessMetadata(
                bundleIdentifier: "com.example.Ordinary",
                name: "Ordinary",
                path: nil,
            ),
        ]
        let missingPathGroup = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [mainPort],
                metadataByPID: missingPathMetadata,
            ).first,
        )
        XCTAssertNil(PortProcessInfoItems(group: missingPathGroup, metadataByPID: missingPathMetadata).applicationPath)

        let conflictingMetadata = [
            101: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Applications/Example.app",
            ),
            102: PortProcessMetadata(
                bundleIdentifier: "com.example.App",
                name: "Example",
                path: "/Users/example/Applications/Example.app",
            ),
        ]
        let conflictingGroup = try XCTUnwrap(
            PortProcessGroupingService.groups(
                for: [rendererPort, gpuPort],
                metadataByPID: conflictingMetadata,
            ).first,
        )
        XCTAssertNil(PortProcessInfoItems(group: conflictingGroup, metadataByPID: conflictingMetadata).applicationPath)
    }
}

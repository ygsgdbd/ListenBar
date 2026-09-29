@testable import ListenBar
import XCTest

final class PortProcessDetailsTests: XCTestCase {
    func testSourceApplicationActionUsesEachPIDWithoutChangingSourceLabels() {
        let sources = [
            SourceApplication(name: "Editor One", pid: 501, bundleIdentifier: "com.example.one", bundlePath: "/Applications/One.app", launchDate: Date(timeIntervalSince1970: 1)),
            SourceApplication(name: "Editor Two", pid: 502, bundleIdentifier: "com.example.two", bundlePath: "/Applications/Two.app", launchDate: Date(timeIntervalSince1970: 2)),
        ]
        let ports = [101, 102].map {
            PortEntry(networkProtocol: .tcp, address: "127.0.0.1", port: 3000, pid: $0, command: "node", user: "501")
        }
        var metadata: [Int: PortProcessMetadata] = [:]
        for (port, source) in zip(ports, sources) {
            var value = PortProcessMetadata.executable(name: "node", path: "/opt/homebrew/bin/node", sources: [.homebrew])
            value.sourceApplication = source
            metadata[port.pid] = value
        }
        let group = PortProcessGroup(id: "test", displayName: "node", subtitle: "3000", icon: .process, ports: ports)
        let items = PortProcessInfoItems(group: group, metadataByPID: metadata).items
        XCTAssertEqual(items.map(\.details.sourceApplication), sources.map(Optional.some))
        for item in items {
            XCTAssertEqual(item.details.source, PortProcessDetails(metadata: .executable(name: "node", path: nil, sources: [.homebrew])).source)
            XCTAssertTrue(item.details.openSourceApplicationTitle?.contains(item.details.sourceApplication!.name) == true)
        }
        XCTAssertNil(PortProcessDetails(metadata: nil).openSourceApplicationTitle)
        XCTAssertNil(PortProcessDetails(metadata: .executable(name: "node", path: nil)).openSourceApplicationTitle)
    }

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

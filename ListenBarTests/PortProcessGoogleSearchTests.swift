@testable import ListenBar
import XCTest

final class PortProcessGoogleSearchTests: XCTestCase {
    func testApplicationQueryIncludesDisplayNameAndBundleIdentifier() {
        let group = applicationGroup(
            displayName: "Example App",
            bundleIdentifier: "com.example.App",
        )

        XCTAssertEqual(
            PortProcessGoogleSearch.query(group: group, metadataByPID: [:]),
            "Example App com.example.App macOS process",
        )
    }

    func testApplicationQueryDoesNotDuplicateBundleIdentifierFallbackName() {
        let group = applicationGroup(
            displayName: "COM.EXAMPLE.APP",
            bundleIdentifier: "com.example.App",
        )

        XCTAssertEqual(
            PortProcessGoogleSearch.query(group: group, metadataByPID: [:]),
            "com.example.App macOS process",
        )
    }

    func testExecutableQueryPrefersMetadataNameWithoutSensitiveDetails() throws {
        let port = port(command: "fallback-command", user: "alice")
        let group = executableGroup(port: port)
        let metadata = PortProcessMetadata.executable(
            name: "Node & 工具 + #",
            path: "/Users/alice/private-project/node",
            commandLine: "node --token secret",
        )

        let query = try XCTUnwrap(
            PortProcessGoogleSearch.query(
                group: group,
                metadataByPID: [port.pid: metadata],
            ),
        )

        XCTAssertEqual(query, "Node & 工具 + # macOS process")
        XCTAssertFalse(query.contains(String(port.pid)))
        XCTAssertFalse(query.contains(String(port.port)))
        XCTAssertFalse(query.contains("alice"))
        XCTAssertFalse(query.contains("private-project"))
        XCTAssertFalse(query.contains("secret"))
    }

    func testExecutableQueryFallsBackToNormalizedCommand() {
        let port = port(command: "  rapportd\t helper  ")
        let group = executableGroup(port: port)

        XCTAssertEqual(
            PortProcessGoogleSearch.query(group: group, metadataByPID: [:]),
            "rapportd helper macOS process",
        )
    }

    func testURLUsesGoogleHTTPSAndPreservesReservedCharacters() throws {
        let port = port(command: "Node & 工具 + #")
        let group = executableGroup(port: port)

        let url = try XCTUnwrap(
            PortProcessGoogleSearch.url(group: group, metadataByPID: [:]),
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false),
        )

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(
            components.queryItems,
            [URLQueryItem(name: "q", value: "Node & 工具 + # macOS process")],
        )
    }

    func testEmptyExecutableNameDoesNotProduceURL() {
        let port = port(command: " \t ")
        let group = executableGroup(port: port)

        XCTAssertNil(PortProcessGoogleSearch.url(group: group, metadataByPID: [:]))
    }

    private func applicationGroup(
        displayName: String,
        bundleIdentifier: String,
    ) -> PortProcessGroup {
        let port = port(command: displayName)
        return PortProcessGroup(
            id: "app:\(bundleIdentifier)",
            displayName: displayName,
            subtitle: String(port.port),
            icon: .application(path: nil),
            ports: [port],
        )
    }

    private func executableGroup(port: PortEntry) -> PortProcessGroup {
        PortProcessGroup(
            id: "process:\(port.pid):\(port.command)",
            displayName: "\(port.command) (PID \(port.pid))",
            subtitle: String(port.port),
            icon: .process,
            ports: [port],
        )
    }

    private func port(
        command: String,
        user: String = "501",
    ) -> PortEntry {
        PortEntry(
            networkProtocol: .tcp,
            address: "127.0.0.1",
            port: 3_000,
            pid: 42,
            command: command,
            user: user,
        )
    }
}

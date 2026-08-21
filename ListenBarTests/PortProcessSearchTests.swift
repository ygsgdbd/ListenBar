@testable import ListenBar
import XCTest

final class PortProcessSearchTests: XCTestCase {
    func testProvidersUseExpectedOrderAndDisplayNames() {
        XCTAssertEqual(PortProcessSearchProvider.allCases, [.google, .bing, .baidu])
        XCTAssertEqual(
            PortProcessSearchProvider.allCases.map(\.displayName),
            ["Google", "Bing", "百度"],
        )
    }

    func testApplicationQueryIncludesDisplayNameAndBundleIdentifier() {
        let group = applicationGroup(
            displayName: "Example App",
            bundleIdentifier: "com.example.App",
        )

        XCTAssertEqual(
            PortProcessSearch.query(group: group, metadataByPID: [:]),
            "Example App com.example.App macOS process",
        )
    }

    func testApplicationQueryDoesNotDuplicateBundleIdentifierFallbackName() {
        let group = applicationGroup(
            displayName: "COM.EXAMPLE.APP",
            bundleIdentifier: "com.example.App",
        )

        XCTAssertEqual(
            PortProcessSearch.query(group: group, metadataByPID: [:]),
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
            PortProcessSearch.query(
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
            PortProcessSearch.query(group: group, metadataByPID: [:]),
            "rapportd helper macOS process",
        )
    }

    func testProviderURLsUseHTTPSAndPreserveReservedCharacters() throws {
        let query = "Node & 工具 + # macOS process"
        let cases: [(PortProcessSearchProvider, String, String, String)] = [
            (.google, "www.google.com", "/search", "q"),
            (.bing, "www.bing.com", "/search", "q"),
            (.baidu, "www.baidu.com", "/s", "wd"),
        ]

        for (provider, host, path, queryName) in cases {
            let url = try XCTUnwrap(provider.url(query: query))
            let components = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false),
            )

            XCTAssertEqual(components.scheme, "https", provider.displayName)
            XCTAssertEqual(components.host, host, provider.displayName)
            XCTAssertEqual(components.path, path, provider.displayName)
            XCTAssertEqual(
                components.queryItems,
                [URLQueryItem(name: queryName, value: query)],
                provider.displayName,
            )
        }
    }

    func testEmptyExecutableNameDoesNotProduceQuery() {
        let port = port(command: " \t ")
        let group = executableGroup(port: port)

        XCTAssertNil(PortProcessSearch.query(group: group, metadataByPID: [:]))
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

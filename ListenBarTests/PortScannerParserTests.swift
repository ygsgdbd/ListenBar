@testable import ListenBar
import XCTest

final class PortScannerParserTests: XCTestCase {
    func testExecutesProcessWhileDrainingLargeStandardOutputAndError() async throws {
        let byteCount = 1_048_576
        let result = try await PortScannerService.executeProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: [
                "-e",
                #"$SIG{ALRM} = sub { die "alarm\n" }; alarm 3; print STDOUT "o" x 1048576; print STDERR "e" x 1048576; alarm 0;"#,
            ],
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput, Data(repeating: Character("o").asciiValue!, count: byteCount))
        XCTAssertEqual(result.standardError, Data(repeating: Character("e").asciiValue!, count: byteCount))
    }

    func testExecutesManyProcessesWhileDrainingLargeStandardOutputAndError() async throws {
        executionTimeAllowance = 15
        let processCount = ProcessInfo.processInfo.activeProcessorCount
        let byteCount = 1_048_576

        let results = try await withThrowingTaskGroup(of: PortScannerProcessResult.self) { group in
            for _ in 0 ..< processCount {
                group.addTask {
                    try await PortScannerService.executeProcess(
                        executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                        arguments: [
                            "-e",
                            #"$SIG{ALRM} = sub { die "alarm\n" }; alarm 12; print STDOUT "o" x 1048576; print STDERR "e" x 1048576; alarm 0;"#,
                        ],
                    )
                }
            }

            var results: [PortScannerProcessResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(results.count, processCount)
        for result in results {
            XCTAssertEqual(result.terminationStatus, 0)
            XCTAssertEqual(result.standardOutput.count, byteCount)
            XCTAssertEqual(result.standardError.count, byteCount)
        }
    }

    func testExecuteProcessReturnsWhenProcessFailsToRun() async {
        executionTimeAllowance = 3

        do {
            _ = try await PortScannerService.executeProcess(
                executableURL: URL(fileURLWithPath: "/path/that/does/not/exist"),
                arguments: [],
            )
            XCTFail("Expected process.run() to fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testRejectsParseableOutputWhenLsofExitsNonzero() {
        let result = PortScannerProcessResult(
            terminationStatus: 1,
            standardOutput: Data(Self.parseableLsofOutput.utf8),
            standardError: Data("permission denied\n".utf8),
        )

        XCTAssertThrowsError(try PortScannerService.interpretLsofResult(result)) { error in
            XCTAssertEqual(
                error as? PortScannerError,
                .lsofFailed(status: 1, message: "permission denied"),
            )
        }
    }

    func testInterpretsParseableOutputWhenLsofExitsSuccessfully() throws {
        let result = PortScannerProcessResult(
            terminationStatus: 0,
            standardOutput: Data(Self.parseableLsofOutput.utf8),
            standardError: Data(),
        )

        XCTAssertEqual(
            try PortScannerService.interpretLsofResult(result),
            [
                PortEntry(
                    networkProtocol: .tcp,
                    address: "*",
                    port: 8081,
                    pid: 24106,
                    command: "node",
                    user: "501",
                ),
            ],
        )
    }

    func testUsesStatusFallbackWhenLsofExitsNonzeroWithoutStandardError() {
        let result = PortScannerProcessResult(
            terminationStatus: 9,
            standardOutput: Data(),
            standardError: Data(),
        )

        XCTAssertThrowsError(try PortScannerService.interpretLsofResult(result)) { error in
            let scannerError = error as? PortScannerError
            XCTAssertEqual(scannerError, .lsofFailed(status: 9, message: ""))
            XCTAssertEqual(scannerError?.errorDescription?.contains("9"), true)
        }
    }

    func testParsesTcpAndLoopbackPorts() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p24106
            cnode
            u501
            f31
            PTCP
            n*:8081
            p63759
            cadb
            u501
            f8
            PTCP
            n127.0.0.1:5037
            """,
        )

        XCTAssertEqual(
            ports,
            [
                PortEntry(
                    networkProtocol: .tcp,
                    address: "127.0.0.1",
                    port: 5037,
                    pid: 63759,
                    command: "adb",
                    user: "501",
                ),
                PortEntry(
                    networkProtocol: .tcp,
                    address: "*",
                    port: 8081,
                    pid: 24106,
                    command: "node",
                    user: "501",
                ),
            ],
        )
    }

    func testParsesUdpPortsAndFiltersWildcardOnlyUdp() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p960
            cidentityservicesd
            u501
            f13
            PUDP
            n*:*
            p2433
            cGoogle Chrome Helper
            u501
            f35
            PUDP
            n*:5353
            """,
        )

        XCTAssertEqual(
            ports,
            [
                PortEntry(
                    networkProtocol: .udp,
                    address: "*",
                    port: 5353,
                    pid: 2433,
                    command: "Google Chrome Helper",
                    user: "501",
                ),
            ],
        )
    }

    func testParsesConnectedUdpUsingLocalEndpointPort() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p42
            cdns-proxy
            u501
            f9
            PUDP
            n127.0.0.1:53000->127.0.0.1:53
            """,
        )

        XCTAssertEqual(
            ports,
            [
                PortEntry(
                    networkProtocol: .udp,
                    address: "127.0.0.1",
                    port: 53000,
                    pid: 42,
                    command: "dns-proxy",
                    user: "501",
                ),
            ],
        )
    }

    func testParsesConnectedIPv6UdpUsingLocalEndpointPort() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p43
            cdns-proxy
            u501
            f9
            PUDP
            n[::1]:53000->[::1]:53
            """,
        )

        XCTAssertEqual(ports.first?.address, "[::1]")
        XCTAssertEqual(ports.first?.port, 53000)
    }

    func testDeduplicatesRepeatedFileDescriptors() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p1075
            cControlCenter
            u501
            f9
            PTCP
            n*:7000
            f10
            PTCP
            n*:7000
            """,
        )

        XCTAssertEqual(
            ports,
            [
                PortEntry(
                    networkProtocol: .tcp,
                    address: "*",
                    port: 7000,
                    pid: 1075,
                    command: "ControlCenter",
                    user: "501",
                ),
            ],
        )
    }

    func testKeepsSameCommandPortsFromDifferentProcesses() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p101
            cnode
            u501
            f9
            PTCP
            n*:3000
            p202
            cnode
            u501
            f10
            PTCP
            n*:3001
            """,
        )

        XCTAssertEqual(ports.map(\.id), [
            "TCP|*|3000|101|node",
            "TCP|*|3001|202|node",
        ])
    }

    func testSortsByPortProtocolCommandAndPid() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p4
            czed
            u501
            f1
            PTCP
            n127.0.0.1:9000
            p3
            calpha
            u501
            f1
            PUDP
            n*:8000
            p2
            cbeta
            u501
            f1
            PTCP
            n*:8000
            p1
            calpha
            u501
            f1
            PTCP
            n*:8000
            """,
        )

        XCTAssertEqual(ports.map(\.pid), [1, 2, 3, 4])
    }

    func testParsesIPv6AddressUsingLastColonAsPortSeparator() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p42
            cserver
            u501
            f3
            PTCP
            n[::1]:9090
            """,
        )

        XCTAssertEqual(ports.first?.address, "[::1]")
        XCTAssertEqual(ports.first?.port, 9090)
    }

    func testParsesWildcardIPv4AndIPv6Addresses() {
        let ports = PortScannerService.parseLsofFieldOutput(
            """
            p10
            cserver
            u501
            f3
            PTCP
            n0.0.0.0:3000
            p11
            cserver
            u501
            f4
            PTCP
            n[::]:3001
            """,
        )

        XCTAssertEqual(ports.map(\.address), ["0.0.0.0", "[::]"])
        XCTAssertEqual(ports.map(\.port), [3000, 3001])
    }

    private static let parseableLsofOutput = """
    p24106
    cnode
    u501
    f31
    PTCP
    n*:8081
    """
}

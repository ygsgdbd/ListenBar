@testable import ListenBar
import XCTest

final class PortScannerParserTests: XCTestCase {
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
}

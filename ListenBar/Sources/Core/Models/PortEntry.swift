import Foundation

enum NetworkProtocol: String, CaseIterable, Equatable, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
}

struct PortEntry: Equatable, Hashable, Identifiable, Sendable {
    let networkProtocol: NetworkProtocol
    let address: String
    let port: Int
    let pid: Int
    let command: String
    let user: String?

    var id: String {
        [
            networkProtocol.rawValue,
            address,
            String(port),
            String(pid),
            command
        ].joined(separator: "|")
    }
}

struct PortProcessMetadata: Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
    let path: String?
}

enum PortProcessIcon: Equatable, Sendable {
    case application(path: String?)
    case process
}

struct PortProcessGroup: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let subtitle: String
    let icon: PortProcessIcon
    let ports: [PortEntry]
}

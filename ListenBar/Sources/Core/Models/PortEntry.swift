import Foundation

enum NetworkProtocol: String, CaseIterable, Equatable, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
}

enum PortAddressExposure: Equatable, Sendable {
    case localOnly
    case allInterfaces
    case specificInterface

    var label: String {
        switch self {
        case .localOnly:
            return "Local only"
        case .allInterfaces:
            return "All interfaces"
        case .specificInterface:
            return "Specific interface"
        }
    }
}

enum PortKillMode: Equatable, Sendable {
    case quit
    case force

    var title: String {
        switch self {
        case .quit:
            return "Quit Process (SIGTERM)"
        case .force:
            return "Force Kill (SIGKILL)"
        }
    }

    var signalName: String {
        switch self {
        case .quit:
            return "SIGTERM"
        case .force:
            return "SIGKILL"
        }
    }
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

    var addressExposure: PortAddressExposure {
        let normalizedAddress = address
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        if address == "*" || normalizedAddress == "0.0.0.0" || normalizedAddress == "::" {
            return .allInterfaces
        }

        if normalizedAddress == "localhost"
            || normalizedAddress == "::1"
            || normalizedAddress.hasPrefix("127.") {
            return .localOnly
        }

        return .specificInterface
    }

    var localhostURL: URL? {
        guard networkProtocol == .tcp, addressExposure != .specificInterface else {
            return nil
        }
        return URL(string: "http://localhost:\(port)")
    }

    var lsofCommand: String {
        switch networkProtocol {
        case .tcp:
            return "/usr/sbin/lsof -nP -iTCP:\(port) -sTCP:LISTEN"
        case .udp:
            return "/usr/sbin/lsof -nP -iUDP:\(port)"
        }
    }
}

enum PortProcessMetadataKind: Equatable, Sendable {
    case application(bundleIdentifier: String)
    case executable
}

struct PortProcessMetadata: Equatable, Sendable {
    let kind: PortProcessMetadataKind
    let name: String
    let path: String?
    let processDetailName: String?

    init(
        bundleIdentifier: String,
        name: String,
        path: String?,
        processDetailName: String? = nil
    ) {
        self.kind = .application(bundleIdentifier: bundleIdentifier)
        self.name = name
        self.path = path
        self.processDetailName = processDetailName
    }

    private init(
        kind: PortProcessMetadataKind,
        name: String,
        path: String?,
        processDetailName: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.path = path
        self.processDetailName = processDetailName
    }

    static func executable(name: String, path: String) -> Self {
        Self(kind: .executable, name: name, path: path)
    }
}

enum PortProcessIcon: Equatable, Sendable {
    case application(path: String?)
    case executable(path: String)
    case process
}

struct PortProcessGroup: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let subtitle: String
    let icon: PortProcessIcon
    let ports: [PortEntry]
    let portProcessDetails: [String: String]

    init(
        id: String,
        displayName: String,
        subtitle: String,
        icon: PortProcessIcon,
        ports: [PortEntry],
        portProcessDetails: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.icon = icon
        self.ports = ports
        self.portProcessDetails = portProcessDetails
    }
}

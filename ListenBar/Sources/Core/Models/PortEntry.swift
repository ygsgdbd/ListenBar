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
            return String(localized: "仅本机", bundle: .main, comment: "端口只绑定到 localhost 或 loopback。")
        case .allInterfaces:
            return String(localized: "所有网络接口", bundle: .main, comment: "端口绑定到所有网络接口。")
        case .specificInterface:
            return String(localized: "指定网络接口", bundle: .main, comment: "端口绑定到指定的非 loopback 接口。")
        }
    }
}

enum PortKillMode: Equatable, Sendable {
    case quit
    case force

    var isDestructive: Bool {
        self == .force
    }

    var title: String {
        switch self {
        case .quit:
            return String(localized: "终止进程 (SIGTERM)", bundle: .main, comment: "使用 SIGTERM 终止进程。")
        case .force:
            return String(localized: "强制终止 (SIGKILL)", bundle: .main, comment: "使用 SIGKILL 强制终止进程。")
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

    func matchesEndpoint(of other: PortEntry) -> Bool {
        networkProtocol == other.networkProtocol
            && address == other.address
            && port == other.port
            && pid == other.pid
            && command == other.command
    }
}

enum PortProcessMetadataKind: Equatable, Sendable {
    case application(bundleIdentifier: String)
    case executable
}

enum PortProcessClassification: Equatable, Sendable {
    case user
    case systemOrOtherUser

    var sectionTitle: String {
        switch self {
        case .user:
            return String(localized: "用户进程", bundle: .main, comment: "当前用户进程列表分区标题。")
        case .systemOrOtherUser:
            return String(localized: "系统/其他用户进程", bundle: .main, comment: "系统或其他用户进程列表分区标题。")
        }
    }
}

enum PortProcessSource: Equatable, Hashable, Sendable {
    case application
    case homebrew
    case macPorts
    case nix
    case visualStudioCode
    case terminal
    case launchd
    case system
    case executable
    case unknown

    var label: String {
        switch self {
        case .application:
            return String(localized: "App", bundle: .main, comment: "进程来源推断：普通 App。")
        case .homebrew:
            return String(localized: "Homebrew", bundle: .main, comment: "进程来源推断：Homebrew。")
        case .macPorts:
            return String(localized: "MacPorts", bundle: .main, comment: "进程来源推断：MacPorts。")
        case .nix:
            return String(localized: "Nix", bundle: .main, comment: "进程来源推断：Nix。")
        case .visualStudioCode:
            return String(localized: "VS Code", bundle: .main, comment: "进程来源推断：VS Code。")
        case .terminal:
            return String(localized: "Terminal", bundle: .main, comment: "进程来源推断：终端。")
        case .launchd:
            return String(localized: "launchd", bundle: .main, comment: "进程来源推断：launchd。")
        case .system:
            return String(localized: "系统", bundle: .main, comment: "进程来源推断：系统。")
        case .executable:
            return String(localized: "可执行文件", bundle: .main, comment: "进程来源推断：普通可执行文件。")
        case .unknown:
            return String(localized: "未知来源", bundle: .main, comment: "无法推断进程来源。")
        }
    }
}

struct PortProcessMetadata: Equatable, Sendable {
    let kind: PortProcessMetadataKind
    let name: String
    let path: String?
    let processDetailName: String?
    let executablePath: String?
    let commandLine: String?
    let commandLineSummary: String?
    let redactedCommandLine: String?
    let redactedCommandLineSummary: String?
    let residentMemoryBytes: UInt64?
    let sources: [PortProcessSource]
    let classification: PortProcessClassification

    init(
        bundleIdentifier: String,
        name: String,
        path: String?,
        processDetailName: String? = nil,
        executablePath: String? = nil,
        commandLine: String? = nil,
        commandLineSummary: String? = nil,
        redactedCommandLine: String? = nil,
        redactedCommandLineSummary: String? = nil,
        residentMemoryBytes: UInt64? = nil,
        sources: [PortProcessSource] = [.application],
        classification: PortProcessClassification = .user
    ) {
        self.kind = .application(bundleIdentifier: bundleIdentifier)
        self.name = name
        self.path = path
        self.processDetailName = processDetailName
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.commandLineSummary = commandLineSummary
        self.redactedCommandLine = redactedCommandLine
        self.redactedCommandLineSummary = redactedCommandLineSummary
        self.residentMemoryBytes = residentMemoryBytes
        self.sources = sources
        self.classification = classification
    }

    private init(
        kind: PortProcessMetadataKind,
        name: String,
        path: String?,
        processDetailName: String? = nil,
        executablePath: String? = nil,
        commandLine: String? = nil,
        commandLineSummary: String? = nil,
        redactedCommandLine: String? = nil,
        redactedCommandLineSummary: String? = nil,
        residentMemoryBytes: UInt64? = nil,
        sources: [PortProcessSource] = [.unknown],
        classification: PortProcessClassification = .user
    ) {
        self.kind = kind
        self.name = name
        self.path = path
        self.processDetailName = processDetailName
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.commandLineSummary = commandLineSummary
        self.redactedCommandLine = redactedCommandLine
        self.redactedCommandLineSummary = redactedCommandLineSummary
        self.residentMemoryBytes = residentMemoryBytes
        self.sources = sources
        self.classification = classification
    }

    static func executable(
        name: String,
        path: String?,
        commandLine: String? = nil,
        commandLineSummary: String? = nil,
        redactedCommandLine: String? = nil,
        redactedCommandLineSummary: String? = nil,
        residentMemoryBytes: UInt64? = nil,
        sources: [PortProcessSource] = [.executable],
        classification: PortProcessClassification = .user
    ) -> Self {
        Self(
            kind: .executable,
            name: name,
            path: path,
            executablePath: path,
            commandLine: commandLine,
            commandLineSummary: commandLineSummary,
            redactedCommandLine: redactedCommandLine,
            redactedCommandLineSummary: redactedCommandLineSummary,
            residentMemoryBytes: residentMemoryBytes,
            sources: sources,
            classification: classification
        )
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
    let classification: PortProcessClassification
    let ports: [PortEntry]
    let portProcessDetails: [String: String]

    init(
        id: String,
        displayName: String,
        subtitle: String,
        icon: PortProcessIcon,
        classification: PortProcessClassification = .user,
        ports: [PortEntry],
        portProcessDetails: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.icon = icon
        self.classification = classification
        self.ports = ports
        self.portProcessDetails = portProcessDetails
    }
}

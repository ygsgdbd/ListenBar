import Foundation

enum PortScannerError: LocalizedError, Equatable {
    case lsofFailed(status: Int32, message: String)
    case lsofOutputUnreadable

    var errorDescription: String? {
        switch self {
        case let .lsofFailed(status, message):
            if message.isEmpty {
                return "lsof exited with status \(status)."
            }
            return message
        case .lsofOutputUnreadable:
            return "Unable to read lsof output."
        }
    }
}

enum PortScannerService {
    static let lsofPath = "/usr/sbin/lsof"
    static let lsofArguments = [
        "-nP",
        "-w",
        "+c",
        "0",
        "-iTCP",
        "-sTCP:LISTEN",
        "-iUDP",
        "-F",
        "pcunP"
    ]

    static func scanListeningPorts() async throws -> [PortEntry] {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lsofPath)
            process.arguments = lsofArguments

            let standardOutput = Pipe()
            let standardError = Pipe()
            process.standardOutput = standardOutput
            process.standardError = standardError

            try process.run()
            process.waitUntilExit()

            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

            guard let output = String(data: outputData, encoding: .utf8) else {
                throw PortScannerError.lsofOutputUnreadable
            }

            let ports = parseLsofFieldOutput(output)
            if ports.isEmpty, process.terminationStatus != 0 {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw PortScannerError.lsofFailed(
                    status: process.terminationStatus,
                    message: message
                )
            }

            return ports
        }
        .value
    }

    static func parseLsofFieldOutput(_ output: String) -> [PortEntry] {
        var process = ProcessRecord()
        var file = FileRecord()
        var entries: [PortEntry] = []

        func flushFile() {
            guard let entry = makeEntry(process: process, file: file) else {
                return
            }
            entries.append(entry)
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                flushFile()
                process = ProcessRecord(pid: Int(value), command: nil, user: nil)
                file = FileRecord()
            case "c":
                process.command = value
            case "u":
                process.user = value
            case "f":
                flushFile()
                file = FileRecord()
            case "P":
                file.networkProtocol = NetworkProtocol(rawValue: value)
            case "n":
                file.name = value
            default:
                continue
            }
        }
        flushFile()

        return Array(Set(entries)).sorted(by: portEntrySort)
    }

    private static func makeEntry(process: ProcessRecord, file: FileRecord) -> PortEntry? {
        guard
            let pid = process.pid,
            let command = process.command,
            let networkProtocol = file.networkProtocol,
            let name = file.name,
            let endpoint = parseEndpoint(name)
        else {
            return nil
        }

        return PortEntry(
            networkProtocol: networkProtocol,
            address: endpoint.address,
            port: endpoint.port,
            pid: pid,
            command: command,
            user: process.user
        )
    }

    private static func parseEndpoint(_ value: String) -> (address: String, port: Int)? {
        guard let separatorIndex = value.lastIndex(of: ":") else {
            return nil
        }

        let rawAddress = String(value[..<separatorIndex])
        let rawPort = String(value[value.index(after: separatorIndex)...])

        guard !rawPort.isEmpty, rawPort != "*", let port = Int(rawPort) else {
            return nil
        }

        let address = rawAddress.isEmpty ? "*" : rawAddress
        return (address, port)
    }

    private static func portEntrySort(_ lhs: PortEntry, _ rhs: PortEntry) -> Bool {
        if lhs.port != rhs.port {
            return lhs.port < rhs.port
        }
        if lhs.networkProtocol != rhs.networkProtocol {
            return lhs.networkProtocol.rawValue < rhs.networkProtocol.rawValue
        }

        let commandComparison = lhs.command.localizedStandardCompare(rhs.command)
        if commandComparison != .orderedSame {
            return commandComparison == .orderedAscending
        }

        if lhs.pid != rhs.pid {
            return lhs.pid < rhs.pid
        }

        return lhs.address.localizedStandardCompare(rhs.address) == .orderedAscending
    }
}

private struct ProcessRecord {
    var pid: Int?
    var command: String?
    var user: String?
}

private struct FileRecord {
    var networkProtocol: NetworkProtocol?
    var name: String?
}

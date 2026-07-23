import Darwin
import Dispatch
import Foundation

enum PortScannerError: LocalizedError, Equatable {
    case lsofFailed(status: Int32, message: String)
    case lsofOutputUnreadable

    var errorDescription: String? {
        switch self {
        case let .lsofFailed(status, message):
            if message.isEmpty {
                return String(
                    format: String(localized: "lsof 退出状态码：%d。", bundle: .main, comment: "lsof 非零退出且没有 stderr 时的兜底错误。"),
                    locale: Locale.current,
                    status,
                )
            }
            return message
        case .lsofOutputUnreadable:
            return String(localized: "无法读取 lsof 输出。", bundle: .main, comment: "无法解码 lsof 输出时显示的错误。")
        }
    }
}

struct PortScannerProcessResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

enum PortScannerService {
    private static let processIOQueue = DispatchQueue(
        label: "top.ygsgdbd.ListenBar.PortScannerService.IO",
        qos: .userInitiated,
        attributes: .concurrent,
    )

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
        "pcunP",
    ]

    static func scanListeningPorts() async throws -> [PortEntry] {
        let result = try await executeProcess(
            executableURL: URL(fileURLWithPath: lsofPath),
            arguments: lsofArguments,
        )
        return try interpretLsofResult(result)
    }

    static func executeProcess(
        executableURL: URL,
        arguments: [String],
    ) async throws -> PortScannerProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let outputDescriptor = try duplicateDescriptor(
            standardOutput.fileHandleForReading.fileDescriptor,
        )
        let errorDescriptor: Int32
        do {
            errorDescriptor = try duplicateDescriptor(
                standardError.fileHandleForReading.fileDescriptor,
            )
        } catch {
            Darwin.close(outputDescriptor)
            throw error
        }

        async let outputData = readData(from: outputDescriptor)
        async let errorData = readData(from: errorDescriptor)

        do {
            let terminationStatus = try await runAndWaitForTermination(process)
            let (standardOutputData, standardErrorData) = try await (outputData, errorData)
            return PortScannerProcessResult(
                terminationStatus: terminationStatus,
                standardOutput: standardOutputData,
                standardError: standardErrorData,
            )
        } catch {
            try? standardOutput.fileHandleForWriting.close()
            try? standardError.fileHandleForWriting.close()
            _ = try? await (outputData, errorData)
            throw error
        }
    }

    static func interpretLsofResult(_ result: PortScannerProcessResult) throws -> [PortEntry] {
        guard result.terminationStatus == 0 else {
            let message = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PortScannerError.lsofFailed(
                status: result.terminationStatus,
                message: message,
            )
        }

        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw PortScannerError.lsofOutputUnreadable
        }

        return parseLsofFieldOutput(output)
    }

    private static func duplicateDescriptor(_ descriptor: Int32) throws -> Int32 {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return duplicate
    }

    private static func readData(from descriptor: Int32) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let state = DispatchIOReadState(continuation: continuation)
            let channel = DispatchIO(
                type: .stream,
                fileDescriptor: descriptor,
                queue: processIOQueue,
            ) { _ in
                Darwin.close(descriptor)
            }
            channel.setLimit(lowWater: 64 * 1024)
            channel.read(offset: 0, length: Int.max, queue: processIOQueue) { done, chunk, error in
                if done {
                    channel.close()
                }
                state.receive(chunk: chunk, done: done, error: error)
            }
        }
    }

    private static func runAndWaitForTermination(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                continuation.resume(returning: terminatedProcess.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
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
            user: process.user,
        )
    }

    private static func parseEndpoint(_ value: String) -> (address: String, port: Int)? {
        let localEndpoint = value
            .split(separator: "->", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? value

        guard let separatorIndex = localEndpoint.lastIndex(of: ":") else {
            return nil
        }

        let rawAddress = String(localEndpoint[..<separatorIndex])
        let rawPort = String(localEndpoint[localEndpoint.index(after: separatorIndex)...])

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

private final class DispatchIOReadState: @unchecked Sendable {
    private let continuation: CheckedContinuation<Data, Error>
    private var data = Data()

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    // DispatchIO guarantees that handlers for one read operation are not reentrant.
    func receive(chunk: DispatchData?, done: Bool, error: Int32) {
        if let chunk {
            chunk.enumerateBytes { buffer, _, _ in
                data.append(contentsOf: buffer)
            }
        }

        guard done else { return }
        if error == 0 {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO))
        }
    }
}

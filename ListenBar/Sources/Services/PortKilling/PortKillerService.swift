import Darwin
import Foundation

enum PortKillerError: LocalizedError, Equatable {
    case invalidPID(Int)
    case signalFailed(pid: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .invalidPID(pid):
            return "无效的 PID：\(pid)"
        case let .signalFailed(pid, message):
            return "无法终止 PID \(pid)：\(message)"
        }
    }
}

enum PortKillerService {
    static func terminateProcess(pid: Int, mode: PortKillMode) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard pid > 0 else {
                throw PortKillerError.invalidPID(pid)
            }

            let result = Darwin.kill(pid_t(pid), mode.signal)
            guard result == 0 else {
                let message = String(cString: strerror(errno))
                throw PortKillerError.signalFailed(pid: pid, message: message)
            }
        }
        .value
    }
}

private extension PortKillMode {
    var signal: Int32 {
        switch self {
        case .quit:
            return SIGTERM
        case .force:
            return SIGKILL
        }
    }
}

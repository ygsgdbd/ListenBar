import Darwin
import Foundation

enum PortKillerError: LocalizedError, Equatable {
    case invalidPID(Int)
    case signalFailed(pid: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .invalidPID(pid):
            return String(
                format: String(localized: "无效的 PID：%lld", bundle: .main, comment: "进程 ID 无效时显示的错误。"),
                locale: Locale.current,
                Int64(pid),
            )
        case let .signalFailed(pid, message):
            return String(
                format: String(localized: "无法终止 PID %lld：%@", bundle: .main, comment: "向进程发送信号失败时显示的错误。"),
                locale: Locale.current,
                Int64(pid),
                message,
            )
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

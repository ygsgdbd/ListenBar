import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @Dependency(\.date.now) var now
    @Dependency(\.portKiller) var portKiller
    @Dependency(\.portProcessMetadata) var portProcessMetadata
    @Dependency(\.portScanner) var portScanner

    @ObservableState
    struct State: Equatable {
        @Presents var confirmationDialog: ConfirmationDialogState<ConfirmationDialog>?
        var errorMessage: String?
        var isLoading = false
        var lastUpdated: Date?
        var metadataByPID: [Int: PortProcessMetadata] = [:]
        var postRefreshErrorMessage: String?
        var ports: [PortEntry] = []
        var processGroups: [PortProcessGroup] = []

        var title: String {
            String(
                format: String(localized: "监听进程 %lld · 端口 %lld", bundle: .main, comment: "菜单标题，显示监听进程和端口数量。"),
                locale: Locale.current,
                Int64(processGroups.count),
                Int64(ports.count)
            )
        }
    }

    enum ViewAction: Equatable, Sendable {
        case copyLsofCommandTapped(PortEntry)
        case copyProcessPathTapped(pid: Int)
        case copyCommandLineTapped(pid: Int)
        case copyPIDTapped(PortEntry)
        case copyURLTapped(PortEntry)
        case killGroupTapped(PortProcessGroup, PortKillMode)
        case killPortTapped(PortEntry, PortKillMode)
        case openLocalhostTapped(PortEntry)
        case revealProcessPathTapped(pid: Int)
        case quitTapped
    }

    @CasePathable
    enum ConfirmationDialog: Equatable, Sendable {
        case confirmKill(PortKillRequest)
        case confirmKillGroup(PortGroupKillRequest)
    }

    enum ResponseAction: Equatable, Sendable {
        case portGroupKillFinished(PortGroupKillResult)
        case portKillFinished(Result<PortKillRequest, PortKillerFailure>)
        case portsLoaded(Result<PortScanSnapshot, PortScannerFailure>)
    }

    enum Action: Equatable, Sendable {
        case confirmationDialog(PresentationAction<ConfirmationDialog>)
        case task
        case view(ViewAction)
        case response(ResponseAction)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                state.errorMessage = nil
                state.postRefreshErrorMessage = nil
                return loadPortsEffect()

            case let .view(.copyLsofCommandTapped(port)):
                return copyTextEffect(port.lsofCommand)

            case let .view(.copyProcessPathTapped(pid)):
                guard let path = Self.processPath(forPID: pid, metadataByPID: state.metadataByPID) else { return .none }
                return copyTextEffect(path)

            case let .view(.copyCommandLineTapped(pid)):
                guard let commandLine = Self.commandLine(forPID: pid, metadataByPID: state.metadataByPID) else { return .none }
                return copyTextEffect(commandLine)

            case let .view(.copyPIDTapped(port)):
                return copyTextEffect(String(port.pid))

            case let .view(.copyURLTapped(port)):
                guard let url = port.localhostURL else { return .none }
                return copyTextEffect(url.absoluteString)

            case let .view(.killGroupTapped(group, mode)):
                let request = PortGroupKillRequest(group: group, mode: mode)
                state.confirmationDialog = request.confirmationDialog(warnings: groupKillWarnings(for: request))
                return .none

            case let .view(.killPortTapped(port, mode)):
                let request = PortKillRequest(
                    port: port,
                    mode: mode,
                    processName: state.metadataByPID[port.pid]?.name
                )
                let warnings = killWarnings(for: request, state: state)
                guard warnings.isEmpty else {
                    state.confirmationDialog = request.confirmationDialog(warnings: warnings)
                    return .none
                }
                state.isLoading = true
                state.errorMessage = nil
                return terminatePortEffect(request)

            case let .view(.openLocalhostTapped(port)):
                guard let url = port.localhostURL else { return .none }
                return openURLEffect(url)

            case let .view(.revealProcessPathTapped(pid)):
                guard let path = Self.processPath(forPID: pid, metadataByPID: state.metadataByPID) else { return .none }
                return revealPathEffect(path)

            case .view(.quitTapped):
                return .run { _ in
                    await MainActor.run {
                        NSApplication.shared.terminate(nil)
                    }
                }

            case let .confirmationDialog(.presented(.confirmKill(request))):
                state.confirmationDialog = nil
                state.isLoading = true
                state.errorMessage = nil
                return terminatePortEffect(request)

            case let .confirmationDialog(.presented(.confirmKillGroup(request))):
                state.confirmationDialog = nil
                state.isLoading = true
                state.errorMessage = nil
                state.postRefreshErrorMessage = nil
                return terminateGroupEffect(request)

            case .confirmationDialog:
                return .none

            case let .response(.portsLoaded(.success(snapshot))):
                state.isLoading = false
                state.errorMessage = state.postRefreshErrorMessage
                state.postRefreshErrorMessage = nil
                state.lastUpdated = now
                state.metadataByPID = snapshot.metadataByPID
                state.ports = snapshot.ports
                state.processGroups = snapshot.processGroups
                return .none

            case let .response(.portsLoaded(.failure(failure))):
                state.isLoading = false
                state.errorMessage = failure.message
                state.postRefreshErrorMessage = nil
                return .none

            case let .response(.portGroupKillFinished(result)):
                state.postRefreshErrorMessage = result.failureMessage
                return loadPortsEffect()

            case .response(.portKillFinished(.success)):
                return loadPortsEffect()

            case let .response(.portKillFinished(.failure(failure))):
                state.isLoading = false
                state.errorMessage = failure.message
                return .none
            }
        }
        .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
    }

    private func loadPortsEffect() -> Effect<Action> {
        .run { send in
            do {
                let ports = try await portScanner.scan()
                let metadata = await portProcessMetadata.resolve(Set(ports.map(\.pid)))
                let snapshot = PortScanSnapshot(
                    ports: ports,
                    metadataByPID: metadata,
                    processGroups: PortProcessGroupingService.groups(
                        for: ports,
                        metadataByPID: metadata
                    )
                )
                await send(.response(.portsLoaded(.success(snapshot))))
            } catch {
                await send(.response(.portsLoaded(.failure(.init(error)))))
            }
        }
    }

    private func terminatePortEffect(_ request: PortKillRequest) -> Effect<Action> {
        .run { send in
            do {
                try await portKiller.terminate(request.port.pid, request.mode)
                await send(.response(.portKillFinished(.success(request))))
            } catch {
                await send(.response(.portKillFinished(.failure(.init(error)))))
            }
        }
    }

    private func terminateGroupEffect(_ request: PortGroupKillRequest) -> Effect<Action> {
        .run { send in
            var failures: [PortKillPIDFailure] = []
            for pid in request.pids {
                do {
                    try await portKiller.terminate(pid, request.mode)
                } catch {
                    failures.append(
                        PortKillPIDFailure(
                            pid: pid,
                            message: PortKillerFailure(error).message
                        )
                    )
                }
            }
            await send(
                .response(
                    .portGroupKillFinished(
                        PortGroupKillResult(request: request, failures: failures)
                    )
                )
            )
        }
    }

    private func copyTextEffect(_ text: String) -> Effect<Action> {
        .run { _ in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                _ = NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    private func revealPathEffect(_ path: String) -> Effect<Action> {
        .run { _ in
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private func openURLEffect(_ url: URL) -> Effect<Action> {
        .run { _ in
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    private func groupKillWarnings(for request: PortGroupKillRequest) -> [PortKillWarning] {
        var warnings: [PortKillWarning] = []
        if request.mode == .force {
            warnings.append(.forceKill)
        }
        if request.classification == .systemOrOtherUser {
            warnings.append(.systemProcess)
        }
        if request.pids.count > 1 {
            warnings.append(.multipleProcesses(request.pids.count))
        }
        return warnings
    }

    private func killWarnings(
        for request: PortKillRequest,
        state: State
    ) -> [PortKillWarning] {
        var warnings: [PortKillWarning] = []
        if request.mode == .force {
            warnings.append(.forceKill)
        }

        guard let metadata = state.metadataByPID[request.port.pid] else {
            return warnings
        }

        if metadata.classification == .systemOrOtherUser || isSystemProcess(metadata) {
            warnings.append(.systemProcess)
        }
        if isAppMainProcess(metadata) {
            warnings.append(.appMainProcess)
        }
        return warnings
    }

    private func isAppMainProcess(_ metadata: PortProcessMetadata) -> Bool {
        guard case .application = metadata.kind else {
            return false
        }
        return metadata.processDetailName == nil
    }

    static func processPath(
        forPID pid: Int,
        metadataByPID: [Int: PortProcessMetadata]
    ) -> String? {
        guard let metadata = metadataByPID[pid] else {
            return nil
        }
        return metadata.executablePath ?? metadata.path
    }

    static func commandLine(
        forPID pid: Int,
        metadataByPID: [Int: PortProcessMetadata]
    ) -> String? {
        metadataByPID[pid]?.commandLine
    }

    private func isSystemProcess(_ metadata: PortProcessMetadata) -> Bool {
        let paths = [metadata.path, metadata.executablePath].compactMap { $0 }
        return paths.contains { path in
            [
                "/System/",
                "/usr/sbin/",
                "/usr/libexec/",
                "/bin/",
                "/sbin/"
            ].contains { path.hasPrefix($0) }
        }
    }
}

struct PortScanSnapshot: Equatable, Sendable {
    let ports: [PortEntry]
    let metadataByPID: [Int: PortProcessMetadata]
    let processGroups: [PortProcessGroup]
}

struct PortKillRequest: Equatable, Sendable {
    let port: PortEntry
    let mode: PortKillMode
    let processName: String

    init(
        port: PortEntry,
        mode: PortKillMode,
        processName: String? = nil
    ) {
        self.port = port
        self.mode = mode
        self.processName = processName ?? port.command
    }

    func confirmationDialog(
        warnings: [PortKillWarning]
    ) -> ConfirmationDialogState<AppFeature.ConfirmationDialog> {
        ConfirmationDialogState {
            TextState(mode.title)
        } actions: {
            ButtonState(role: .cancel) {
                TextState(String(localized: "取消", bundle: .main, comment: "取消按钮标题。"))
            }
            ButtonState(role: .destructive, action: .confirmKill(self)) {
                TextState(mode.title)
            }
        } message: {
            TextState(confirmationMessage(warnings: warnings))
        }
    }

    private func confirmationMessage(warnings: [PortKillWarning]) -> String {
        let endpoint = "\(port.networkProtocol.rawValue) \(port.address):\(port.port)"
        let warningText = warnings.map(\.message).joined(separator: " ")
        return String(
            format: String(localized: "%@ 将发送到 %@ (PID %lld)，目标为 %@。%@", bundle: .main, comment: "发送进程终止信号前的确认说明。"),
            locale: Locale.current,
            mode.signalName,
            processName,
            Int64(port.pid),
            endpoint,
            warningText
        )
    }
}

struct PortGroupKillRequest: Equatable, Sendable {
    let groupID: String
    let processName: String
    let ports: [PortEntry]
    let pids: [Int]
    let mode: PortKillMode
    let classification: PortProcessClassification

    init(group: PortProcessGroup, mode: PortKillMode) {
        self.groupID = group.id
        self.processName = group.displayName
        self.ports = group.ports
        self.pids = Array(Set(group.ports.map(\.pid))).sorted()
        self.mode = mode
        self.classification = group.classification
    }

    func confirmationDialog(
        warnings: [PortKillWarning]
    ) -> ConfirmationDialogState<AppFeature.ConfirmationDialog> {
        ConfirmationDialogState {
            TextState(mode.groupTitle)
        } actions: {
            ButtonState(role: .cancel) {
                TextState(String(localized: "取消", bundle: .main, comment: "取消按钮标题。"))
            }
            ButtonState(role: .destructive, action: .confirmKillGroup(self)) {
                TextState(mode.groupTitle)
            }
        } message: {
            TextState(confirmationMessage(warnings: warnings))
        }
    }

    private func confirmationMessage(warnings: [PortKillWarning]) -> String {
        let portsText = Set(ports.map(\.port))
            .sorted()
            .map(String.init)
            .joined(separator: ", ")
        let warningText = warnings.map(\.message).joined(separator: " ")
        return String(
            format: String(localized: "%@ 将发送到 %@ 的 %lld 个监听进程，端口为 %@。%@", bundle: .main, comment: "批量发送进程终止信号前的确认说明。"),
            locale: Locale.current,
            mode.signalName,
            processName,
            Int64(pids.count),
            portsText,
            warningText
        )
    }
}

struct PortKillPIDFailure: Equatable, Sendable {
    let pid: Int
    let message: String
}

struct PortGroupKillResult: Equatable, Sendable {
    let request: PortGroupKillRequest
    let failures: [PortKillPIDFailure]

    var failureMessage: String? {
        guard !failures.isEmpty else {
            return nil
        }

        let details = failures
            .map { "PID \($0.pid): \($0.message)" }
            .joined(separator: "; ")
        return String(
            format: String(localized: "部分进程未能终止：%@", bundle: .main, comment: "批量终止进程时部分 PID 失败的错误。"),
            locale: Locale.current,
            details
        )
    }
}

enum PortKillWarning: Equatable, Sendable {
    case forceKill
    case systemProcess
    case appMainProcess
    case multipleProcesses(Int)

    var message: String {
        switch self {
        case .forceKill:
            return String(localized: "强制终止无法被进程优雅处理。", bundle: .main, comment: "发送 SIGKILL 前显示的警告。")
        case .systemProcess:
            return String(localized: "这看起来是系统进程。", bundle: .main, comment: "终止系统进程前显示的警告。")
        case .appMainProcess:
            return String(localized: "这看起来是主应用进程。", bundle: .main, comment: "终止应用主进程前显示的警告。")
        case let .multipleProcesses(count):
            return String(
                format: String(localized: "这会影响 %lld 个进程。", bundle: .main, comment: "批量终止多个进程前显示的警告。"),
                locale: Locale.current,
                Int64(count)
            )
        }
    }
}

private extension PortKillMode {
    var groupTitle: String {
        switch self {
        case .quit:
            return String(localized: "终止全部监听进程 (SIGTERM)", bundle: .main, comment: "批量使用 SIGTERM 终止进程。")
        case .force:
            return String(localized: "强制终止全部监听进程 (SIGKILL)", bundle: .main, comment: "批量使用 SIGKILL 终止进程。")
        }
    }
}

struct PortScannerFailure: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }

    init(message: String) {
        self.message = message
    }

    init(_ error: Error) {
        if let failure = error as? PortScannerFailure {
            self = failure
        } else if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            self.message = errorDescription
        } else {
            self.message = error.localizedDescription
        }
    }
}

struct PortKillerFailure: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }

    init(message: String) {
        self.message = message
    }

    init(_ error: Error) {
        if let failure = error as? PortKillerFailure {
            self = failure
        } else if let localizedError = error as? LocalizedError,
                  let errorDescription = localizedError.errorDescription {
            self.message = errorDescription
        } else {
            self.message = error.localizedDescription
        }
    }
}

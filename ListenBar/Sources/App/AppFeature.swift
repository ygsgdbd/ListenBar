import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.portKillConfirmation) var portKillConfirmation
    @Dependency(\.portKillNotification) var portKillNotification
    @Dependency(\.portKiller) var portKiller
    @Dependency(\.portProcessMetadata) var portProcessMetadata
    @Dependency(\.portScanner) var portScanner

    @ObservableState
    struct State: Equatable {
        var autoRefreshInterval: AutoRefreshInterval = .off
        var errorMessage: String?
        var isLoading = false
        var lastUpdated: Date?
        var metadataByPID: [Int: PortProcessMetadata] = [:]
        var postRefreshErrorMessage: String?
        var ports: [PortEntry] = []
        var processGroups: [PortProcessGroup] = []
        var refreshPending = false

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
        case autoRefreshIntervalTapped(AutoRefreshInterval)
        case copyFullInformationTapped
        case copyGroupPortsTapped(PortProcessGroup)
        case copyLsofCommandTapped(PortEntry)
        case copyProcessInformationTapped(PortProcessGroup)
        case copyProcessPathTapped(pid: Int)
        case copyCommandLineTapped(pid: Int)
        case copyRedactedCommandLineTapped(pid: Int)
        case copyPIDTapped(pid: Int)
        case copyURLTapped(PortEntry)
        case killGroupTapped(PortProcessGroup, PortKillMode)
        case killPortTapped(PortEntry, PortKillMode)
        case openLocalhostTapped(PortEntry)
        case revealProcessPathTapped(pid: Int)
        case quitTapped
    }

    enum ResponseAction: Equatable, Sendable {
        case portGroupKillFinished(PortGroupKillResult)
        case portKillFinished(PortKillResult)
        case portsLoaded(Result<PortScanSnapshot, PortScannerFailure>)
    }

    enum Action: Equatable, Sendable {
        case autoRefreshTick
        case menuPresented
        case portGroupKillConfirmationResponse(PortGroupKillRequest, confirmed: Bool)
        case portKillConfirmationResponse(PortKillRequest, confirmed: Bool)
        case task
        case view(ViewAction)
        case response(ResponseAction)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .autoRefreshTick:
                guard !state.isLoading else { return .none }
                return startRefresh(&state)

            case .menuPresented:
                guard !state.isLoading else {
                    state.refreshPending = true
                    return .none
                }
                return startRefresh(&state)

            case .task:
                return startRefresh(&state)

            case let .view(.autoRefreshIntervalTapped(interval)):
                state.autoRefreshInterval = interval
                guard interval != .off else {
                    return .cancel(id: CancelID.autoRefresh)
                }
                let timer = autoRefreshEffect(interval)
                guard !state.isLoading else {
                    state.refreshPending = true
                    return timer
                }
                return .merge(startRefresh(&state), timer)

            case .view(.copyFullInformationTapped):
                return copyTextEffect(
                    PortListFormatter.text(
                        groups: state.processGroups,
                        metadataByPID: state.metadataByPID
                    )
                )

            case let .view(.copyGroupPortsTapped(group)):
                return copyTextEffect(PortListFormatter.portsText(group: group))

            case let .view(.copyLsofCommandTapped(port)):
                return copyTextEffect(port.lsofCommand)

            case let .view(.copyProcessInformationTapped(group)):
                return copyTextEffect(
                    PortListFormatter.text(
                        group: group,
                        metadataByPID: state.metadataByPID
                    )
                )

            case let .view(.copyProcessPathTapped(pid)):
                guard let path = Self.processPath(forPID: pid, metadataByPID: state.metadataByPID) else { return .none }
                return copyTextEffect(path)

            case let .view(.copyCommandLineTapped(pid)):
                guard let commandLine = Self.commandLine(forPID: pid, metadataByPID: state.metadataByPID) else { return .none }
                return copyTextEffect(commandLine)

            case let .view(.copyRedactedCommandLineTapped(pid)):
                guard let commandLine = Self.redactedCommandLine(forPID: pid, metadataByPID: state.metadataByPID) else { return .none }
                return copyTextEffect(commandLine)

            case let .view(.copyPIDTapped(pid)):
                return copyTextEffect(String(pid))

            case let .view(.copyURLTapped(port)):
                guard let url = port.localhostURL else { return .none }
                return copyTextEffect(url.absoluteString)

            case let .view(.killGroupTapped(group, mode)):
                let request = PortGroupKillRequest(
                    group: group,
                    mode: mode,
                    metadataByPID: state.metadataByPID
                )
                return confirmGroupKillEffect(
                    request,
                    warnings: groupKillWarnings(for: request)
                )

            case let .view(.killPortTapped(port, mode)):
                let request = PortKillRequest(
                    port: port,
                    mode: mode,
                    processName: state.metadataByPID[port.pid]?.name,
                    expectedExecutablePath: Self.processPath(
                        forPID: port.pid,
                        metadataByPID: state.metadataByPID
                    )
                )
                let warnings = killWarnings(for: request, state: state)
                guard warnings.isEmpty else {
                    return confirmPortKillEffect(request, warnings: warnings)
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

            case let .portKillConfirmationResponse(request, confirmed):
                guard confirmed else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                state.postRefreshErrorMessage = nil
                return terminatePortEffect(request)

            case let .portGroupKillConfirmationResponse(request, confirmed):
                guard confirmed else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                state.postRefreshErrorMessage = nil
                return terminateGroupEffect(request)

            case let .response(.portsLoaded(.success(snapshot))):
                let postRefreshErrorMessage = state.postRefreshErrorMessage
                apply(snapshot, to: &state)
                state.errorMessage = postRefreshErrorMessage
                return startPendingRefreshIfNeeded(&state)

            case let .response(.portsLoaded(.failure(failure))):
                state.isLoading = false
                state.errorMessage = failure.message
                state.postRefreshErrorMessage = nil
                return startPendingRefreshIfNeeded(&state)

            case let .response(.portGroupKillFinished(result)):
                let notificationEffect = sendNotificationEffect(result.notification)
                if let snapshot = result.refreshedSnapshot {
                    apply(snapshot, to: &state)
                    state.errorMessage = result.failureMessage
                    return .merge(
                        notificationEffect,
                        startPendingRefreshIfNeeded(&state)
                    )
                }
                state.postRefreshErrorMessage = result.failureMessage
                return .merge(notificationEffect, loadPortsEffect())

            case let .response(.portKillFinished(result)):
                let notificationEffect = sendNotificationEffect(result.notification)
                if let snapshot = result.refreshedSnapshot {
                    apply(snapshot, to: &state)
                    state.errorMessage = result.failure?.message
                    return .merge(
                        notificationEffect,
                        startPendingRefreshIfNeeded(&state)
                    )
                }
                if let failure = result.failure {
                    state.isLoading = false
                    state.errorMessage = failure.message
                    return .merge(
                        notificationEffect,
                        startPendingRefreshIfNeeded(&state)
                    )
                }
                return .merge(notificationEffect, loadPortsEffect())
            }
        }
    }

    private enum CancelID: Hashable {
        case autoRefresh
    }

    private func loadPortsEffect() -> Effect<Action> {
        .run { send in
            do {
                let snapshot = try await scanSnapshot()
                await send(.response(.portsLoaded(.success(snapshot))))
            } catch {
                await send(.response(.portsLoaded(.failure(.init(error)))))
            }
        }
    }

    private func startRefresh(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.errorMessage = nil
        state.postRefreshErrorMessage = nil
        return loadPortsEffect()
    }

    private func startPendingRefreshIfNeeded(_ state: inout State) -> Effect<Action> {
        guard state.refreshPending else {
            return .none
        }
        state.refreshPending = false
        return startRefresh(&state)
    }

    private func autoRefreshEffect(_ interval: AutoRefreshInterval) -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                try await clock.sleep(for: .seconds(interval.seconds))
                await send(.autoRefreshTick)
            }
        }
        .cancellable(id: CancelID.autoRefresh, cancelInFlight: true)
    }

    private func confirmPortKillEffect(
        _ request: PortKillRequest,
        warnings: [PortKillWarning]
    ) -> Effect<Action> {
        let confirmation = request.confirmation(warnings: warnings)
        return .run { send in
            let confirmed = await portKillConfirmation.confirm(confirmation)
            await send(.portKillConfirmationResponse(request, confirmed: confirmed))
        }
    }

    private func confirmGroupKillEffect(
        _ request: PortGroupKillRequest,
        warnings: [PortKillWarning]
    ) -> Effect<Action> {
        let confirmation = request.confirmation(warnings: warnings)
        return .run { send in
            let confirmed = await portKillConfirmation.confirm(confirmation)
            await send(.portGroupKillConfirmationResponse(request, confirmed: confirmed))
        }
    }

    private func scanSnapshot() async throws -> PortScanSnapshot {
        let ports = try await portScanner.scan()
        let metadata = await portProcessMetadata.resolve(ports)
        return PortScanSnapshot(
            ports: ports,
            metadataByPID: metadata,
            processGroups: PortProcessGroupingService.groups(
                for: ports,
                metadataByPID: metadata
            )
        )
    }

    private func terminatePortEffect(_ request: PortKillRequest) -> Effect<Action> {
        .run { send in
            do {
                let snapshot = try await scanSnapshot()
                guard Self.preflightMatches(request, snapshot: snapshot) else {
                    await send(
                        .response(
                            .portKillFinished(
                                .aborted(
                                    request: request,
                                    refreshedSnapshot: snapshot,
                                    failure: .staleTarget
                                )
                            )
                        )
                    )
                    return
                }
                try await portKiller.terminate(request.port.pid, request.mode)
                await send(.response(.portKillFinished(.success(request: request))))
            } catch {
                await send(.response(.portKillFinished(.failure(request: request, failure: .init(error)))))
            }
        }
    }

    private func terminateGroupEffect(_ request: PortGroupKillRequest) -> Effect<Action> {
        .run { send in
            let snapshot: PortScanSnapshot
            do {
                snapshot = try await scanSnapshot()
            } catch {
                await send(
                    .response(
                        .portGroupKillFinished(
                            PortGroupKillResult(
                                request: request,
                                failures: [.init(pid: 0, message: PortScannerFailure(error).message)],
                                refreshedSnapshot: nil
                            )
                        )
                    )
                )
                return
            }

            guard Self.preflightMatches(request, snapshot: snapshot) else {
                await send(
                    .response(
                        .portGroupKillFinished(
                            PortGroupKillResult(
                                request: request,
                                failures: [.init(pid: 0, message: PortKillerFailure.staleTarget.message)],
                                refreshedSnapshot: snapshot
                            )
                        )
                    )
                )
                return
            }

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

    private func sendNotificationEffect(_ notification: PortKillNotification) -> Effect<Action> {
        .run { _ in
            await portKillNotification.send(notification)
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

    static func redactedCommandLine(
        forPID pid: Int,
        metadataByPID: [Int: PortProcessMetadata]
    ) -> String? {
        metadataByPID[pid]?.redactedCommandLine
    }

    static func preflightMatches(
        _ request: PortKillRequest,
        snapshot: PortScanSnapshot
    ) -> Bool {
        guard snapshot.ports.contains(where: { $0.matchesEndpoint(of: request.port) }) else {
            return false
        }
        guard let expectedExecutablePath = request.expectedExecutablePath else {
            return true
        }
        return processPath(forPID: request.port.pid, metadataByPID: snapshot.metadataByPID) == expectedExecutablePath
    }

    static func preflightMatches(
        _ request: PortGroupKillRequest,
        snapshot: PortScanSnapshot
    ) -> Bool {
        guard let group = snapshot.processGroups.first(where: { $0.id == request.groupID }) else {
            return false
        }
        guard Set(group.ports.map(\.id)) == Set(request.ports.map(\.id)) else {
            return false
        }
        for port in request.ports {
            if let expectedExecutablePath = request.expectedExecutablePathsByPID[port.pid],
               processPath(forPID: port.pid, metadataByPID: snapshot.metadataByPID) != expectedExecutablePath {
                return false
            }
        }
        return true
    }

    private func apply(_ snapshot: PortScanSnapshot, to state: inout State) {
        state.isLoading = false
        state.postRefreshErrorMessage = nil
        state.lastUpdated = now
        state.metadataByPID = snapshot.metadataByPID
        state.ports = snapshot.ports
        state.processGroups = snapshot.processGroups
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

enum AutoRefreshInterval: CaseIterable, Equatable, Identifiable, Sendable {
    case off
    case fiveSeconds
    case tenSeconds

    var id: Self { self }

    var seconds: Int {
        switch self {
        case .off:
            return 0
        case .fiveSeconds:
            return 5
        case .tenSeconds:
            return 10
        }
    }

    var title: String {
        switch self {
        case .off:
            return String(localized: "关闭", bundle: .main, comment: "自动刷新关闭。")
        case .fiveSeconds:
            return String(localized: "每 5 秒", bundle: .main, comment: "每 5 秒自动刷新。")
        case .tenSeconds:
            return String(localized: "每 10 秒", bundle: .main, comment: "每 10 秒自动刷新。")
        }
    }
}

struct PortKillRequest: Equatable, Sendable {
    let port: PortEntry
    let mode: PortKillMode
    let processName: String
    let expectedExecutablePath: String?

    init(
        port: PortEntry,
        mode: PortKillMode,
        processName: String? = nil,
        expectedExecutablePath: String? = nil
    ) {
        self.port = port
        self.mode = mode
        self.processName = processName ?? port.command
        self.expectedExecutablePath = expectedExecutablePath
    }

    func confirmation(warnings: [PortKillWarning]) -> PortKillConfirmation {
        PortKillConfirmation(
            title: mode.title,
            message: confirmationMessage(warnings: warnings),
            confirmButtonTitle: mode.title,
            isDestructive: mode.isDestructive
        )
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
    let expectedExecutablePathsByPID: [Int: String]

    init(
        group: PortProcessGroup,
        mode: PortKillMode,
        metadataByPID: [Int: PortProcessMetadata] = [:]
    ) {
        self.groupID = group.id
        self.processName = group.displayName
        self.ports = group.ports
        self.pids = Array(Set(group.ports.map(\.pid))).sorted()
        self.mode = mode
        self.classification = group.classification
        self.expectedExecutablePathsByPID = Dictionary(
            uniqueKeysWithValues: pids.compactMap { pid in
                guard let path = AppFeature.processPath(forPID: pid, metadataByPID: metadataByPID) else {
                    return nil
                }
                return (pid, path)
            }
        )
    }

    func confirmation(warnings: [PortKillWarning]) -> PortKillConfirmation {
        PortKillConfirmation(
            title: mode.groupTitle,
            message: confirmationMessage(warnings: warnings),
            confirmButtonTitle: mode.groupTitle,
            isDestructive: mode.isDestructive
        )
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

struct PortKillResult: Equatable, Sendable {
    let request: PortKillRequest
    let refreshedSnapshot: PortScanSnapshot?
    let failure: PortKillerFailure?

    static func success(request: PortKillRequest) -> Self {
        Self(request: request, refreshedSnapshot: nil, failure: nil)
    }

    static func failure(request: PortKillRequest, failure: PortKillerFailure) -> Self {
        Self(request: request, refreshedSnapshot: nil, failure: failure)
    }

    static func aborted(
        request: PortKillRequest,
        refreshedSnapshot: PortScanSnapshot,
        failure: PortKillerFailure
    ) -> Self {
        Self(request: request, refreshedSnapshot: refreshedSnapshot, failure: failure)
    }

    var notification: PortKillNotification {
        let target = String(
            format: String(localized: "%@ (PID %lld) · %@ %@:%lld", bundle: .main, comment: "单个进程终止结果通知的目标信息。"),
            locale: Locale.current,
            request.processName,
            Int64(request.port.pid),
            request.port.networkProtocol.rawValue,
            request.port.address,
            Int64(request.port.port)
        )

        if let failure {
            return PortKillNotification(
                title: String(
                    format: String(localized: "发送 %@ 失败", bundle: .main, comment: "进程终止信号发送失败通知标题。"),
                    locale: Locale.current,
                    request.mode.signalName
                ),
                body: "\(target) · \(failure.message)"
            )
        }

        return PortKillNotification(
            title: String(
                format: String(localized: "已发送 %@", bundle: .main, comment: "进程终止信号发送成功通知标题。"),
                locale: Locale.current,
                request.mode.signalName
            ),
            body: target
        )
    }
}

struct PortGroupKillResult: Equatable, Sendable {
    let request: PortGroupKillRequest
    let failures: [PortKillPIDFailure]
    var refreshedSnapshot: PortScanSnapshot?

    var failureMessage: String? {
        guard !failures.isEmpty else {
            return nil
        }
        if failures.count == 1, let failure = failures.first, failure.pid == 0 {
            return failure.message
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

    var notification: PortKillNotification {
        let portsText = Set(request.ports.map(\.port))
            .sorted()
            .map(String.init)
            .joined(separator: " ")
        let target = String(
            format: String(localized: "%@ · %lld 个进程 · 端口 %@", bundle: .main, comment: "批量进程终止结果通知的目标信息。"),
            locale: Locale.current,
            request.processName,
            Int64(request.pids.count),
            portsText
        )

        guard let failureMessage else {
            return PortKillNotification(
                title: String(
                    format: String(localized: "已发送 %@", bundle: .main, comment: "进程终止信号发送成功通知标题。"),
                    locale: Locale.current,
                    request.mode.signalName
                ),
                body: target
            )
        }

        let failedPIDCount = failures.filter { $0.pid > 0 }.count
        let isPartialFailure = failedPIDCount > 0 && failedPIDCount < request.pids.count
        let titleFormat = isPartialFailure
            ? String(localized: "部分进程发送 %@ 失败", bundle: .main, comment: "部分进程终止信号发送失败通知标题。")
            : String(localized: "发送 %@ 失败", bundle: .main, comment: "进程终止信号发送失败通知标题。")
        let body: String
        if isPartialFailure {
            body = String(
                format: String(localized: "%@ · 成功 %lld/%lld · %@", bundle: .main, comment: "批量进程终止部分失败通知正文。"),
                locale: Locale.current,
                target,
                Int64(request.pids.count - failedPIDCount),
                Int64(request.pids.count),
                failureMessage
            )
        } else {
            body = "\(target) · \(failureMessage)"
        }

        return PortKillNotification(
            title: String(
                format: titleFormat,
                locale: Locale.current,
                request.mode.signalName
            ),
            body: body
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

    static var staleTarget: Self {
        Self(
            message: String(
                localized: "端口占用已变化，请重新确认。",
                bundle: .main,
                comment: "终止进程前重新扫描发现端口占用已变化。"
            )
        )
    }

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

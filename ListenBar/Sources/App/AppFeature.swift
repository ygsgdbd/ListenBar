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
        var ports: [PortEntry] = []
        var processGroups: [PortProcessGroup] = []

        var title: String {
            "监听进程 \(processGroups.count) · 端口 \(ports.count)"
        }
    }

    enum ViewAction: Equatable, Sendable {
        case copyLsofCommandTapped(PortEntry)
        case copyPIDTapped(PortEntry)
        case copyURLTapped(PortEntry)
        case killPortTapped(PortEntry, PortKillMode)
        case openLocalhostTapped(PortEntry)
        case quitTapped
    }

    @CasePathable
    enum ConfirmationDialog: Equatable, Sendable {
        case confirmKill(PortKillRequest)
    }

    enum ResponseAction: Equatable, Sendable {
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
                return loadPortsEffect()

            case let .view(.copyLsofCommandTapped(port)):
                return copyTextEffect(port.lsofCommand)

            case let .view(.copyPIDTapped(port)):
                return copyTextEffect(String(port.pid))

            case let .view(.copyURLTapped(port)):
                guard let url = port.localhostURL else { return .none }
                return copyTextEffect(url.absoluteString)

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

            case .confirmationDialog:
                return .none

            case let .response(.portsLoaded(.success(snapshot))):
                state.isLoading = false
                state.errorMessage = nil
                state.lastUpdated = now
                state.metadataByPID = snapshot.metadataByPID
                state.ports = snapshot.ports
                state.processGroups = snapshot.processGroups
                return .none

            case let .response(.portsLoaded(.failure(failure))):
                state.isLoading = false
                state.errorMessage = failure.message
                return .none

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

    private func copyTextEffect(_ text: String) -> Effect<Action> {
        .run { _ in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                _ = NSPasteboard.general.setString(text, forType: .string)
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

        if isSystemProcess(metadata) {
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

    private func isSystemProcess(_ metadata: PortProcessMetadata) -> Bool {
        guard let path = metadata.path else {
            return false
        }
        return [
            "/System/",
            "/usr/sbin/",
            "/usr/libexec/",
            "/bin/",
            "/sbin/"
        ].contains { path.hasPrefix($0) }
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
                TextState("Cancel")
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
        return "\(mode.signalName) will be sent to \(processName) (PID \(port.pid)) for \(endpoint). \(warningText)"
    }
}

enum PortKillWarning: Equatable, Sendable {
    case forceKill
    case systemProcess
    case appMainProcess

    var message: String {
        switch self {
        case .forceKill:
            return "Force kill cannot be handled gracefully."
        case .systemProcess:
            return "This looks like a system process."
        case .appMainProcess:
            return "This looks like the main app process."
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

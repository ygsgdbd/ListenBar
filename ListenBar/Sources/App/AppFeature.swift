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
        var errorMessage: String?
        var isLoading = false
        var lastUpdated: Date?
        var ports: [PortEntry] = []
        var processGroups: [PortProcessGroup] = []

        var title: String {
            "监听进程 \(processGroups.count) · 端口 \(ports.count)"
        }
    }

    enum ViewAction: Equatable, Sendable {
        case killPortTapped(PortEntry)
        case refreshTapped
        case quitTapped
    }

    enum ResponseAction: Equatable, Sendable {
        case portKillFinished(Result<PortEntry, PortKillerFailure>)
        case portsLoaded(Result<PortScanSnapshot, PortScannerFailure>)
    }

    enum Action: Equatable, Sendable {
        case task
        case view(ViewAction)
        case response(ResponseAction)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .view(.refreshTapped):
                state.isLoading = true
                state.errorMessage = nil
                return loadPortsEffect()

            case let .view(.killPortTapped(port)):
                state.isLoading = true
                state.errorMessage = nil
                return terminatePortEffect(port)

            case .view(.quitTapped):
                return .run { _ in
                    await MainActor.run {
                        NSApplication.shared.terminate(nil)
                    }
                }

            case let .response(.portsLoaded(.success(snapshot))):
                state.isLoading = false
                state.errorMessage = nil
                state.lastUpdated = now
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
    }

    private func loadPortsEffect() -> Effect<Action> {
        .run { send in
            do {
                let ports = try await portScanner.scan()
                let metadata = await portProcessMetadata.resolve(Set(ports.map(\.pid)))
                let snapshot = PortScanSnapshot(
                    ports: ports,
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

    private func terminatePortEffect(_ port: PortEntry) -> Effect<Action> {
        .run { send in
            do {
                try await portKiller.terminate(port.pid)
                await send(.response(.portKillFinished(.success(port))))
            } catch {
                await send(.response(.portKillFinished(.failure(.init(error)))))
            }
        }
    }
}

struct PortScanSnapshot: Equatable, Sendable {
    let ports: [PortEntry]
    let processGroups: [PortProcessGroup]
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

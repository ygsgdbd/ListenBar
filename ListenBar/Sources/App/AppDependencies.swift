import ComposableArchitecture
import Foundation

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isToggleOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }
}

struct PortScannerClient {
    var scan: @Sendable () async throws -> [PortEntry]
}

struct PortProcessMetadataClient {
    var resolve: @Sendable ([PortEntry]) async -> [Int: PortProcessMetadata]
}

struct PortKillerClient {
    var terminate: @Sendable (Int, PortKillMode) async throws -> Void
}

struct ApplicationQuitClient {
    var request: @Sendable (ApplicationQuitRequest) async -> ApplicationQuitAttempt
}

struct LaunchAtLoginClient {
    var status: @Sendable () async -> LaunchAtLoginStatus
    var setEnabled: @Sendable (Bool) async -> LaunchAtLoginStatus
}

struct PortKillConfirmationClient {
    var confirm: @Sendable (PortKillConfirmation) async -> Bool
}

struct PortKillNotificationClient {
    var send: @Sendable (PortKillNotification) async -> Void
}

extension PortScannerClient: DependencyKey {
    static let liveValue = Self(
        scan: {
            try await PortScannerService.scanListeningPorts()
        }
    )

    static let testValue = Self(
        scan: { [] }
    )
}

extension PortProcessMetadataClient: DependencyKey {
    static let liveValue = Self(
        resolve: { ports in
            await PortProcessMetadataService.resolveMetadata(for: ports)
        }
    )

    static let testValue = Self(
        resolve: { _ in [:] }
    )
}

extension PortKillerClient: DependencyKey {
    static let liveValue = Self(
        terminate: { pid, mode in
            try await PortKillerService.terminateProcess(pid: pid, mode: mode)
        }
    )

    static let testValue = Self(
        terminate: { _, _ in }
    )
}

extension ApplicationQuitClient: DependencyKey {
    static let liveValue = Self(
        request: { request in
            await ApplicationQuitService.request(request)
        }
    )

    static let testValue = Self(
        request: { _ in
            ApplicationQuitAttempt(
                matchedInstanceCount: 0,
                acceptedInstanceCount: 0
            )
        }
    )
}

extension LaunchAtLoginClient: DependencyKey {
    static let liveValue = Self(
        status: { LaunchAtLoginService.status },
        setEnabled: { enabled in
            LaunchAtLoginService.setLaunchAtLogin(enabled)
        }
    )

    static let testValue = Self(
        status: { .disabled },
        setEnabled: { $0 ? .enabled : .disabled }
    )
}

extension PortKillConfirmationClient: DependencyKey {
    static let liveValue = Self(
        confirm: { confirmation in
            await PortKillInteractionService.confirm(confirmation)
        }
    )

    static let testValue = Self(
        confirm: { _ in false }
    )
}

extension PortKillNotificationClient: DependencyKey {
    static let liveValue = Self(
        send: { notification in
            await PortKillInteractionService.send(notification)
        }
    )

    static let testValue = Self(
        send: { _ in }
    )
}

extension DependencyValues {
    var applicationQuitter: ApplicationQuitClient {
        get { self[ApplicationQuitClient.self] }
        set { self[ApplicationQuitClient.self] = newValue }
    }

    var launchAtLoginClient: LaunchAtLoginClient {
        get { self[LaunchAtLoginClient.self] }
        set { self[LaunchAtLoginClient.self] = newValue }
    }

    var portScanner: PortScannerClient {
        get { self[PortScannerClient.self] }
        set { self[PortScannerClient.self] = newValue }
    }

    var portProcessMetadata: PortProcessMetadataClient {
        get { self[PortProcessMetadataClient.self] }
        set { self[PortProcessMetadataClient.self] = newValue }
    }

    var portKiller: PortKillerClient {
        get { self[PortKillerClient.self] }
        set { self[PortKillerClient.self] = newValue }
    }

    var portKillConfirmation: PortKillConfirmationClient {
        get { self[PortKillConfirmationClient.self] }
        set { self[PortKillConfirmationClient.self] = newValue }
    }

    var portKillNotification: PortKillNotificationClient {
        get { self[PortKillNotificationClient.self] }
        set { self[PortKillNotificationClient.self] = newValue }
    }
}

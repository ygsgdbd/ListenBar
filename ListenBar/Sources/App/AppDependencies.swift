import ComposableArchitecture
import Foundation

struct PortScannerClient {
    var scan: @Sendable () async throws -> [PortEntry]
}

struct PortProcessMetadataClient {
    var resolve: @Sendable (Set<Int>) async -> [Int: PortProcessMetadata]
}

struct PortKillerClient {
    var terminate: @Sendable (Int, PortKillMode) async throws -> Void
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
        resolve: { pids in
            await PortProcessMetadataService.resolveMetadata(for: pids)
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

extension DependencyValues {
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
}

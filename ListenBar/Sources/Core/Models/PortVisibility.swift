import Foundation

struct PortScanSnapshot: Equatable, Sendable {
    let ports: [PortEntry]
    let metadataByPID: [Int: PortProcessMetadata]
    let processGroups: [PortProcessGroup]
}

struct PortVisibility: Equatable, Sendable {
    private let snapshot: PortScanSnapshot
    private(set) var visibleSnapshot: PortScanSnapshot

    var ignoredProcessGroupCount: Int {
        snapshot.processGroups.count - visibleSnapshot.processGroups.count
    }

    init(
        snapshot: PortScanSnapshot = .init(ports: [], metadataByPID: [:], processGroups: []),
        ignoredProcesses: [IgnoredProcessItem] = [],
    ) {
        self.snapshot = snapshot
        self.visibleSnapshot = snapshot
        apply(ignoredProcesses: ignoredProcesses)
    }

    mutating func apply(ignoredProcesses: [IgnoredProcessItem]) {
        guard !ignoredProcesses.isEmpty else {
            visibleSnapshot = snapshot
            return
        }

        let visibleGroups = snapshot.processGroups.filter { group in
            !ignoredProcesses.contains { item in
                item.matches(group: group, metadataByPID: snapshot.metadataByPID)
            }
        }
        let visiblePortIDs = Set(visibleGroups.flatMap(\.ports).map(\.id))
        let visiblePorts = snapshot.ports.filter { visiblePortIDs.contains($0.id) }
        let visiblePIDs = Set(visiblePorts.map(\.pid))

        visibleSnapshot = PortScanSnapshot(
            ports: visiblePorts,
            metadataByPID: snapshot.metadataByPID.filter { visiblePIDs.contains($0.key) },
            processGroups: visibleGroups,
        )
    }
}

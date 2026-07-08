import Foundation

enum PortProcessGroupingService {
    static func groups(
        for ports: [PortEntry],
        metadataByPID: [Int: PortProcessMetadata]
    ) -> [PortProcessGroup] {
        var accumulators: [String: GroupAccumulator] = [:]

        for port in ports {
            let metadata = metadataByPID[port.pid]
            let identity = identity(for: port, metadata: metadata)
            var accumulator = accumulators[identity.id] ?? GroupAccumulator(identity: identity)
            accumulator.ports.append(port)
            if let processDetailName = metadata?.processDetailName {
                accumulator.portProcessDetails[port.id] = processDetailName
            }
            accumulators[identity.id] = accumulator
        }

        return accumulators.values
            .map(\.group)
            .sorted(by: groupSort)
    }

    private static func identity(
        for port: PortEntry,
        metadata: PortProcessMetadata?
    ) -> GroupIdentity {
        if let metadata {
            switch metadata.kind {
            case let .application(bundleIdentifier):
                return GroupIdentity(
                    id: "app:\(bundleIdentifier)",
                    displayName: metadata.name,
                    icon: .application(path: metadata.path)
                )

            case .executable:
                return GroupIdentity(
                    id: "process:\(port.pid):\(port.command)",
                    displayName: "\(port.command) (PID \(port.pid))",
                    icon: metadata.path.map(PortProcessIcon.executable(path:)) ?? .process
                )
            }
        }

        return GroupIdentity(
            id: "process:\(port.pid):\(port.command)",
            displayName: "\(port.command) (PID \(port.pid))",
            icon: .process
        )
    }

    fileprivate static func portSort(_ lhs: PortEntry, _ rhs: PortEntry) -> Bool {
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

    private static func groupSort(_ lhs: PortProcessGroup, _ rhs: PortProcessGroup) -> Bool {
        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}

private struct GroupIdentity {
    let id: String
    let displayName: String
    let icon: PortProcessIcon
}

private struct GroupAccumulator {
    let identity: GroupIdentity
    var ports: [PortEntry] = []
    var portProcessDetails: [String: String] = [:]

    var group: PortProcessGroup {
        let sortedPorts = ports.sorted(by: PortProcessGroupingService.portSort)
        let portSummary = Set(sortedPorts.map(\.port))
            .sorted()
            .map(String.init)
            .joined(separator: ", ")
        let detailNames = Set(portProcessDetails.values)
            .sorted()
        let subtitle: String

        if detailNames.count == 1, let detailName = detailNames.first {
            subtitle = "\(detailName) · \(portSummary)"
        } else if detailNames.count > 1 {
            subtitle = "\(detailNames.count) 个子进程 · \(portSummary)"
        } else {
            subtitle = portSummary
        }

        return PortProcessGroup(
            id: identity.id,
            displayName: identity.displayName,
            subtitle: subtitle,
            icon: identity.icon,
            ports: sortedPorts,
            portProcessDetails: portProcessDetails
        )
    }
}

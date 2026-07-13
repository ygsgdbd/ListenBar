import Foundation

enum PortProcessGroupingService {
    static func groups(
        for ports: [PortEntry],
        metadataByPID: [Int: PortProcessMetadata],
    ) -> [PortProcessGroup] {
        var accumulators: [String: GroupAccumulator] = [:]

        for port in ports {
            let metadata = metadataByPID[port.pid]
            let classification = classification(for: port, metadata: metadata)
            let identity = identity(
                for: port,
                metadata: metadata,
                classification: classification,
            )
            var accumulator = accumulators[identity.id] ?? GroupAccumulator(identity: identity)
            accumulator.ports.append(port)
            accumulator.include(classification)
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
        metadata: PortProcessMetadata?,
        classification: PortProcessClassification,
    ) -> GroupIdentity {
        if let metadata {
            switch metadata.kind {
            case let .application(bundleIdentifier):
                return GroupIdentity(
                    id: "app:\(bundleIdentifier)",
                    displayName: metadata.name,
                    icon: .application(path: metadata.path),
                    classification: classification,
                )

            case .executable:
                return GroupIdentity(
                    id: "process:\(port.pid):\(port.command)",
                    displayName: "\(port.command) (PID \(port.pid))",
                    icon: metadata.path.map(PortProcessIcon.executable(path:)) ?? .process,
                    classification: classification,
                )
            }
        }

        return GroupIdentity(
            id: "process:\(port.pid):\(port.command)",
            displayName: "\(port.command) (PID \(port.pid))",
            icon: .process,
            classification: classification,
        )
    }

    private static func classification(
        for port: PortEntry,
        metadata: PortProcessMetadata?,
    ) -> PortProcessClassification {
        if let metadata {
            return metadata.classification
        }

        guard let user = port.user?.lowercased() else {
            return .user
        }
        if user == "0" || user == "root" {
            return .systemOrOtherUser
        }
        return .user
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
    let classification: PortProcessClassification
}

private struct GroupAccumulator {
    let identity: GroupIdentity
    var classification: PortProcessClassification
    var ports: [PortEntry] = []
    var portProcessDetails: [String: String] = [:]

    init(identity: GroupIdentity) {
        self.identity = identity
        self.classification = identity.classification
    }

    mutating func include(_ classification: PortProcessClassification) {
        if classification == .systemOrOtherUser {
            self.classification = .systemOrOtherUser
        }
    }

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
            subtitle = String(
                format: String(localized: "%lld 个子进程 · %@", bundle: .main, comment: "多个 helper 进程及其端口的分组副标题。"),
                locale: Locale.current,
                Int64(detailNames.count),
                portSummary,
            )
        } else {
            subtitle = portSummary
        }

        return PortProcessGroup(
            id: identity.id,
            displayName: identity.displayName,
            subtitle: subtitle,
            icon: identity.icon,
            classification: classification,
            ports: sortedPorts,
            portProcessDetails: portProcessDetails,
        )
    }
}

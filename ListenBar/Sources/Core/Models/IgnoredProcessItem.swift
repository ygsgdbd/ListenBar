import Foundation

struct IgnoredProcessItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case application
        case executable
    }

    let kind: Kind
    let identifier: String
    let displayName: String

    var id: String {
        "\(kind.rawValue):\(identifier)"
    }

    var hasStableIdentity: Bool {
        switch kind {
        case .application:
            return !identifier.isEmpty
                && identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        case .executable:
            return Self.stableExecutablePath(identifier) != nil
        }
    }

    private init(
        kind: Kind,
        identifier: String,
        displayName: String,
    ) {
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
    }

    static func application(
        bundleIdentifier: String,
        displayName: String,
    ) -> Self {
        Self(
            kind: .application,
            identifier: bundleIdentifier,
            displayName: displayName,
        )
    }

    static func executable(
        path: String,
        displayName: String,
    ) -> Self {
        Self(
            kind: .executable,
            identifier: path,
            displayName: displayName,
        )
    }

    init?(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata],
    ) {
        if let bundleIdentifier = group.applicationBundleIdentifier {
            self = .application(
                bundleIdentifier: bundleIdentifier,
                displayName: group.displayName,
            )
            return
        }

        let executablePaths = Set(
            group.ports.compactMap { port in
                Self.stableExecutablePath(metadataByPID[port.pid]?.executablePath)
            },
        )
        guard executablePaths.count == 1, let path = executablePaths.first else {
            return nil
        }
        let displayName = group.ports.lazy.compactMap { port -> String? in
            guard
                let metadata = metadataByPID[port.pid],
                Self.stableExecutablePath(metadata.executablePath) == path
            else {
                return nil
            }
            return metadata.name
        }
        .first ?? URL(fileURLWithPath: path).lastPathComponent
        self = .executable(path: path, displayName: displayName)
    }

    func matches(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata],
    ) -> Bool {
        switch kind {
        case .application:
            return group.applicationBundleIdentifier == identifier

        case .executable:
            guard group.applicationBundleIdentifier == nil, hasStableIdentity else {
                return false
            }
            return group.ports.contains { port in
                Self.stableExecutablePath(metadataByPID[port.pid]?.executablePath) == identifier
            }
        }
    }

    private static func stableExecutablePath(_ value: String?) -> String? {
        guard
            let value,
            value == value.trimmingCharacters(in: .whitespacesAndNewlines),
            value.hasPrefix("/"),
            value.count > 1
        else {
            return nil
        }
        return value
    }
}

extension PortScanSnapshot {
    func filtering(ignoredProcesses: [IgnoredProcessItem]) -> Self {
        guard !ignoredProcesses.isEmpty else { return self }

        let visibleGroups = processGroups.filter { group in
            !ignoredProcesses.contains { item in
                item.matches(group: group, metadataByPID: metadataByPID)
            }
        }
        let visiblePortIDs = Set(visibleGroups.flatMap(\.ports).map(\.id))
        let visiblePorts = ports.filter { visiblePortIDs.contains($0.id) }
        let visiblePIDs = Set(visiblePorts.map(\.pid))

        return Self(
            ports: visiblePorts,
            metadataByPID: metadataByPID.filter { visiblePIDs.contains($0.key) },
            processGroups: visibleGroups,
        )
    }
}

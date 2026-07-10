import Foundation

enum PortListFormatter {
    static func text(
        groups: [PortProcessGroup],
        metadataByPID: [Int: PortProcessMetadata]
    ) -> String {
        groups.map { group in
            groupText(group: group, metadataByPID: metadataByPID)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func groupText(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata]
    ) -> String {
        let processCount = Set(group.ports.map(\.pid)).count
        let header = [
            "group",
            shellToken(group.displayName),
            "processes=\(processCount)",
            "ports=\(group.ports.count)",
            "source=\(groupSource(group: group, metadataByPID: metadataByPID))"
        ].joined(separator: " ")

        let rows = group.ports.map { port in
            portText(port: port, metadata: metadataByPID[port.pid])
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private static func portText(
        port: PortEntry,
        metadata: PortProcessMetadata?
    ) -> String {
        var fields = [
            port.networkProtocol.rawValue,
            port.address,
            String(port.port),
            "pid=\(port.pid)",
            "command=\(shellToken(port.command))"
        ]

        if let sources = metadata?.sources, !sources.isEmpty {
            fields.append("source=\(shellToken(sourceLabels(sources)))")
        }
        if let url = port.localhostURL?.absoluteString {
            fields.append("url=\(url)")
        }
        if let path = metadata?.executablePath ?? metadata?.path {
            fields.append("path=\(shellToken(path))")
        }
        return fields.joined(separator: " ")
    }

    private static func groupSource(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata]
    ) -> String {
        var sources: [PortProcessSource] = []
        for port in group.ports {
            for source in metadataByPID[port.pid]?.sources ?? [] where !sources.contains(source) {
                sources.append(source)
            }
        }
        guard !sources.isEmpty else {
            return shellToken(PortProcessSource.unknown.label)
        }
        return shellToken(sourceLabels(sources))
    }

    private static func sourceLabels(_ sources: [PortProcessSource]) -> String {
        sources.map(\.label).joined(separator: " • ")
    }

    private static func shellToken(_ value: String) -> String {
        guard !value.isEmpty else {
            return "''"
        }

        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "/._-:=@%+,"))
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

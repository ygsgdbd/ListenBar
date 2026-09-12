import Foundation

struct PortProcessInfoItems: Equatable {
    let items: [PortProcessInfoItem]
    let applicationPath: String?

    var singleItem: PortProcessInfoItem? {
        items.count == 1 ? items.first : nil
    }

    init(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata],
    ) {
        let applicationPath = Self.applicationPath(for: group, metadataByPID: metadataByPID)
        var seenPIDs: Set<Int> = []
        var items: [PortProcessInfoItem] = []

        for port in group.ports where !seenPIDs.contains(port.pid) {
            let metadata = metadataByPID[port.pid]
            let details = PortProcessDetails(metadata: metadata)

            seenPIDs.insert(port.pid)
            items.append(
                PortProcessInfoItem(
                    pid: port.pid,
                    title: Self.title(
                        for: port,
                        metadata: metadata,
                        group: group,
                    ),
                    details: details,
                    applicationPath: applicationPath,
                ),
            )
        }

        self.items = items
        self.applicationPath = applicationPath
    }

    private static func applicationPath(
        for group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata],
    ) -> String? {
        guard let groupBundleIdentifier = group.applicationBundleIdentifier else {
            return nil
        }

        let paths = Set(
            group.ports.compactMap { port -> String? in
                guard
                    let metadata = metadataByPID[port.pid],
                    case let .application(bundleIdentifier) = metadata.kind,
                    bundleIdentifier == groupBundleIdentifier
                else {
                    return nil
                }
                return metadata.path
            },
        )
        guard paths.count == 1 else {
            return nil
        }
        return paths.first
    }

    private static func title(
        for port: PortEntry,
        metadata: PortProcessMetadata?,
        group: PortProcessGroup,
    ) -> String {
        if let detailName = group.portProcessDetails[port.id] ?? metadata?.processDetailName,
           !detailName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return "\(detailName) · PID \(port.pid)"
        }

        return "PID \(port.pid)"
    }
}

struct PortProcessInfoItem: Equatable, Identifiable {
    let pid: Int
    let title: String
    let details: PortProcessDetails
    let applicationPath: String?

    var executablePathToReveal: String? {
        guard let path = details.executablePath, path != applicationPath else { return nil }
        return path
    }

    var copyPIDTitle: String {
        String(
            format: String(localized: "复制 PID (%@)", bundle: .main, comment: "复制 PID 菜单项，括号内显示实际进程 ID。"),
            locale: Locale.current,
            String(pid),
        )
    }

    var id: Int {
        pid
    }
}

struct PortProcessDetails: Equatable {
    private let metadata: PortProcessMetadata?

    init(metadata: PortProcessMetadata?) {
        self.metadata = metadata
    }

    var path: String? {
        metadata?.executablePath ?? metadata?.path
    }

    var executablePath: String? {
        metadata?.executablePath
    }

    var commandLine: String? {
        metadata?.commandLine
    }

    var redactedCommandLine: String? {
        metadata?.redactedCommandLine
    }

    var commandLineSummary: String? {
        metadata?.commandLineSummary
    }

    var redactedCommandLineSummary: String? {
        metadata?.redactedCommandLineSummary
    }

    var hasDetails: Bool {
        metadata != nil
    }

    var source: String {
        guard let metadata else { return "" }
        return String(
            format: String(localized: "来源：%@", bundle: .main, comment: "进程来源推断标签。"),
            locale: Locale.current,
            metadata.sources.map(\.label).joined(separator: " • "),
        )
    }

    var memory: String? {
        guard let metadata else { return nil }
        let memoryValue = metadata.residentMemoryBytes
            .map { PortMemoryFormatter.string(bytes: $0) }
            ?? String(localized: "不可用", bundle: .main, comment: "无法读取进程常驻内存。")
        return String(
            format: String(localized: "常驻内存：%@", bundle: .main, comment: "进程常驻内存。"),
            locale: Locale.current,
            memoryValue,
        )
    }
}

enum PortMemoryFormatter {
    static func string(bytes: UInt64, locale: Locale = .current) -> String {
        let kilobyte = 1_024.0
        let megabyte = kilobyte * 1_024.0
        let gigabyte = megabyte * 1_024.0
        let value = Double(bytes)

        if value >= gigabyte {
            return String(format: "%.1f GB", locale: locale, value / gigabyte)
        }
        if value >= megabyte {
            return String(format: "%.1f MB", locale: locale, value / megabyte)
        }
        if value >= kilobyte {
            return String(format: "%.1f KB", locale: locale, value / kilobyte)
        }
        return "\(bytes) B"
    }
}

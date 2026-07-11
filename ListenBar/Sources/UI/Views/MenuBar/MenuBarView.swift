import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: StoreOf<AppFeature>
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Group {
            Section {
                if let lastUpdated = store.lastUpdated {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(updatedAtText(lastUpdated, now: context.date))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text(store.title)
            }

            Divider()

            if let errorMessage = store.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                }
            }

            if store.processGroups.isEmpty {
                Section {
                    Text(emptyStateText)
                }
            } else {
                let userGroups = store.processGroups.filter { $0.classification == .user }
                let systemGroups = store.processGroups.filter { $0.classification == .systemOrOtherUser }

                if !userGroups.isEmpty {
                    processGroupsSection(
                        title: PortProcessSectionLabels.title(
                            classification: .user,
                            groups: userGroups
                        ),
                        groups: userGroups
                    )
                }
                if !systemGroups.isEmpty {
                    processGroupsSection(
                        title: PortProcessSectionLabels.title(
                            classification: .systemOrOtherUser,
                            groups: systemGroups
                        ),
                        groups: systemGroups
                    )
                }
            }

            Divider()

            Button {
                store.send(.view(.copyFullInformationTapped))
            } label: {
                Label("复制完整信息", systemImage: "list.clipboard")
            }
            .disabled(store.processGroups.isEmpty)

            Menu {
                ForEach(AutoRefreshInterval.allCases) { interval in
                    Button {
                        store.send(.view(.autoRefreshIntervalTapped(interval)))
                    } label: {
                        if store.autoRefreshInterval == interval {
                            Label(interval.title, systemImage: "checkmark")
                        } else {
                            Text(interval.title)
                        }
                    }
                }
            } label: {
                Label(
                    String(
                        format: String(localized: "自动刷新：%@", bundle: .main, comment: "自动刷新菜单标题。"),
                        locale: Locale.current,
                        store.autoRefreshInterval.title
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
            }

            Button {
                updaterController.checkForUpdates(nil)
            } label: {
                Label("检查更新...", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                store.send(.view(.quitTapped))
            } label: {
                Label("退出 ListenBar", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .task {
            await Task.yield()
            store.send(.menuPresented)
        }
    }

    private func processGroupsSection(
        title: String,
        groups: [PortProcessGroup]
    ) -> some View {
        Section(title) {
            ForEach(groups) { group in
                PortProcessGroupMenu(
                    group: group,
                    metadataByPID: store.metadataByPID,
                    isLoading: store.isLoading,
                    onOpenLocalhost: { port in
                        store.send(.view(.openLocalhostTapped(port)))
                    },
                    onCopyURL: { port in
                        store.send(.view(.copyURLTapped(port)))
                    },
                    onCopyPID: { pid in
                        store.send(.view(.copyPIDTapped(pid: pid)))
                    },
                    onCopyGroupPorts: { group in
                        store.send(.view(.copyGroupPortsTapped(group)))
                    },
                    onCopyProcessInformation: { group in
                        store.send(.view(.copyProcessInformationTapped(group)))
                    },
                    onCopyProcessPath: { pid in
                        store.send(.view(.copyProcessPathTapped(pid: pid)))
                    },
                    onCopyCommandLine: { pid in
                        store.send(.view(.copyCommandLineTapped(pid: pid)))
                    },
                    onCopyRedactedCommandLine: { pid in
                        store.send(.view(.copyRedactedCommandLineTapped(pid: pid)))
                    },
                    onCopyLsofCommand: { port in
                        store.send(.view(.copyLsofCommandTapped(port)))
                    },
                    onRevealProcessPath: { pid in
                        store.send(.view(.revealProcessPathTapped(pid: pid)))
                    },
                    onKillPort: { port, mode in
                        store.send(.view(.killPortTapped(port, mode)))
                    },
                    onKillGroup: { group, mode in
                        store.send(.view(.killGroupTapped(group, mode)))
                    },
                    onQuitApplication: { group, mode in
                        store.send(.view(.quitApplicationTapped(group, mode)))
                    }
                )
            }
        }
    }

    private var emptyStateText: String {
        if store.isLoading {
            return String(localized: "正在扫描...", bundle: .main, comment: "扫描端口时的空状态。")
        }
        return String(localized: "未发现监听端口", bundle: .main, comment: "没有发现监听端口时的空状态。")
    }

    private func updatedAtText(_ lastUpdated: Date, now: Date) -> String {
        String(
            format: String(localized: "更新于 %@", bundle: .main, comment: "最近一次端口扫描的更新时间。"),
            locale: Locale.current,
            PortLastUpdatedFormatter.relativeString(from: lastUpdated, to: now)
        )
    }
}

enum PortLastUpdatedFormatter {
    static func relativeString(from lastUpdated: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(lastUpdated)))
        guard seconds > 0 else {
            return String(localized: "刚刚", bundle: .main, comment: "相对更新时间：刚刚。")
        }

        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        let remainingSeconds = seconds % 60

        if days > 0 {
            return String(
                format: String(localized: "%lld 天 %lld 小时 %lld 分 %lld 秒前", bundle: .main, comment: "相对更新时间：天、小时、分钟、秒。"),
                locale: Locale.current,
                Int64(days),
                Int64(hours),
                Int64(minutes),
                Int64(remainingSeconds)
            )
        }
        if hours > 0 {
            return String(
                format: String(localized: "%lld 小时 %lld 分 %lld 秒前", bundle: .main, comment: "相对更新时间：小时、分钟、秒。"),
                locale: Locale.current,
                Int64(hours),
                Int64(minutes),
                Int64(remainingSeconds)
            )
        }
        if minutes > 0 {
            return String(
                format: String(localized: "%lld 分 %lld 秒前", bundle: .main, comment: "相对更新时间：分钟、秒。"),
                locale: Locale.current,
                Int64(minutes),
                Int64(remainingSeconds)
            )
        }
        return String(
            format: String(localized: "%lld 秒前", bundle: .main, comment: "相对更新时间：秒。"),
            locale: Locale.current,
            Int64(remainingSeconds)
        )
    }
}

private struct PortProcessGroupMenu: View {
    let group: PortProcessGroup
    let metadataByPID: [Int: PortProcessMetadata]
    let isLoading: Bool
    let onOpenLocalhost: (PortEntry) -> Void
    let onCopyURL: (PortEntry) -> Void
    let onCopyPID: (Int) -> Void
    let onCopyGroupPorts: (PortProcessGroup) -> Void
    let onCopyProcessInformation: (PortProcessGroup) -> Void
    let onCopyProcessPath: (Int) -> Void
    let onCopyCommandLine: (Int) -> Void
    let onCopyRedactedCommandLine: (Int) -> Void
    let onCopyLsofCommand: (PortEntry) -> Void
    let onRevealProcessPath: (Int) -> Void
    let onKillPort: (PortEntry, PortKillMode) -> Void
    let onKillGroup: (PortProcessGroup, PortKillMode) -> Void
    let onQuitApplication: (PortProcessGroup, ApplicationQuitMode) -> Void

    var body: some View {
        let showsPIDInPortMenus = PortMenuLabels.showsPID(for: group.ports)
        let processInfoItems = PortProcessInfoItems(
            group: group,
            metadataByPID: metadataByPID
        )

        Menu {
            ForEach(group.ports) { port in
                PortMenu(
                    port: port,
                    showsPID: showsPIDInPortMenus,
                    processName: group.portProcessDetails[port.id],
                    isLoading: isLoading,
                    onOpenLocalhost: onOpenLocalhost,
                    onCopyURL: onCopyURL,
                    onCopyLsofCommand: onCopyLsofCommand,
                    onKillPort: onKillPort
                )
            }

            Divider()

            Button {
                onCopyGroupPorts(group)
            } label: {
                Label("复制全部端口", systemImage: "list.clipboard")
            }

            Button {
                onCopyProcessInformation(group)
            } label: {
                Label("复制进程信息", systemImage: "doc.text")
            }

            if group.id.hasPrefix("app:") {
                Divider()

                Button {
                    onQuitApplication(group, .normal)
                } label: {
                    Label(
                        String(
                            format: String(localized: "退出 %@", bundle: .main, comment: "正常退出应用菜单项。"),
                            locale: Locale.current,
                            group.displayName
                        ),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                }
                .disabled(isLoading)

                Button(role: .destructive) {
                    onQuitApplication(group, .force)
                } label: {
                    Label(
                        String(
                            format: String(localized: "强制退出 %@…", bundle: .main, comment: "强制退出应用菜单项。"),
                            locale: Locale.current,
                            group.displayName
                        ),
                        systemImage: "exclamationmark.octagon"
                    )
                }
                .disabled(isLoading)

                Divider()

                Button(role: PortKillMode.quit.isDestructive ? .destructive : nil) {
                    onKillGroup(group, .quit)
                } label: {
                    Label(PortKillMode.quit.groupMenuTitle, systemImage: "xmark.circle")
                }
                .disabled(isLoading)

                Button(role: PortKillMode.force.isDestructive ? .destructive : nil) {
                    onKillGroup(group, .force)
                } label: {
                    Label(PortKillMode.force.groupMenuTitle, systemImage: "exclamationmark.octagon")
                }
                .disabled(isLoading)
            }

            if let processInfoItem = processInfoItems.singleItem {
                Divider()

                PortProcessInfoMenuContent(
                    item: processInfoItem,
                    isLoading: isLoading,
                    onCopyPID: onCopyPID,
                    onCopyProcessPath: onCopyProcessPath,
                    onCopyCommandLine: onCopyCommandLine,
                    onCopyRedactedCommandLine: onCopyRedactedCommandLine,
                    onRevealProcessPath: onRevealProcessPath
                )
            } else if !processInfoItems.items.isEmpty {
                Divider()

                Menu {
                    ForEach(processInfoItems.items) { item in
                        Menu {
                            PortProcessInfoMenuContent(
                                item: item,
                                isLoading: isLoading,
                                onCopyPID: onCopyPID,
                                onCopyProcessPath: onCopyProcessPath,
                                onCopyCommandLine: onCopyCommandLine,
                                onCopyRedactedCommandLine: onCopyRedactedCommandLine,
                                onRevealProcessPath: onRevealProcessPath
                            )
                        } label: {
                            Text(verbatim: item.title)
                                .monospacedDigit()
                        }
                    }
                } label: {
                    Label("进程详情", systemImage: "info.circle")
                }
            }
        } label: {
            PortProcessIconView(icon: group.icon)
            Text(group.displayName)
            Text(group.subtitle)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct PortMenu: View {
    let port: PortEntry
    let showsPID: Bool
    let processName: String?
    let isLoading: Bool
    let onOpenLocalhost: (PortEntry) -> Void
    let onCopyURL: (PortEntry) -> Void
    let onCopyLsofCommand: (PortEntry) -> Void
    let onKillPort: (PortEntry, PortKillMode) -> Void

    var body: some View {
        let labels = PortMenuLabels(
            port: port,
            showsPID: showsPID,
            processName: processName
        )

        Menu {
            if labels.localhostURLString != nil {
                Button {
                    onOpenLocalhost(port)
                } label: {
                    Label("打开 localhost", systemImage: "safari")
                }
                .disabled(isLoading)

                Button {
                    onCopyURL(port)
                } label: {
                    Label("复制 URL", systemImage: "link")
                }
            }

            Button {
                onCopyLsofCommand(port)
            } label: {
                Label("复制 lsof 命令", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: PortKillMode.quit.isDestructive ? .destructive : nil) {
                onKillPort(port, .quit)
            } label: {
                Label(PortKillMode.quit.menuTitle, systemImage: "xmark.circle")
            }
            .disabled(isLoading)

            Button(role: PortKillMode.force.isDestructive ? .destructive : nil) {
                onKillPort(port, .force)
            } label: {
                Label(PortKillMode.force.menuTitle, systemImage: "exclamationmark.octagon")
            }
            .disabled(isLoading)
        } label: {
            Text(verbatim: labels.title)
                .font(.system(.body, design: .monospaced))
            Text(verbatim: labels.subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PortProcessInfoMenuContent: View {
    let item: PortProcessInfoItem
    let isLoading: Bool
    let onCopyPID: (Int) -> Void
    let onCopyProcessPath: (Int) -> Void
    let onCopyCommandLine: (Int) -> Void
    let onCopyRedactedCommandLine: (Int) -> Void
    let onRevealProcessPath: (Int) -> Void

    var body: some View {
        Button {
            onCopyPID(item.pid)
        } label: {
            Label(item.copyPIDTitle, systemImage: "number")
                .monospacedDigit()
        }

        if item.labels.hasDetails {
            Section(item.labels.source) {
                if let memory = item.labels.memory {
                    Label(memory, systemImage: "memorychip")
                        .monospacedDigit()
                }

                if let path = item.labels.path {
                    Button {
                        onRevealProcessPath(item.pid)
                    } label: {
                        Label {
                            Text("在 Finder 中显示")
                            Text(verbatim: path)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .disabled(isLoading)

                    Button {
                        onCopyProcessPath(item.pid)
                    } label: {
                        Label {
                            Text("复制路径")
                            Text(verbatim: path)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }

                if let redactedCommandLineSummary = item.labels.redactedCommandLineSummary {
                    Button {
                        onCopyRedactedCommandLine(item.pid)
                    } label: {
                        Label {
                            Text("复制脱敏启动命令")
                            Text(verbatim: redactedCommandLineSummary)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "lock.doc")
                        }
                    }
                }

                if item.labels.commandLineSummary != nil {
                    Button {
                        onCopyCommandLine(item.pid)
                    } label: {
                        Label("复制启动命令", systemImage: "terminal")
                    }
                }
            }
        }
    }
}

struct PortProcessInfoItems: Equatable {
    let items: [PortProcessInfoItem]

    var singleItem: PortProcessInfoItem? {
        items.count == 1 ? items.first : nil
    }

    init(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata]
    ) {
        var seenPIDs: Set<Int> = []
        var items: [PortProcessInfoItem] = []

        for port in group.ports where !seenPIDs.contains(port.pid) {
            let metadata = metadataByPID[port.pid]
            let labels = PortProcessInfoLabels(metadata: metadata)

            seenPIDs.insert(port.pid)
            items.append(
                PortProcessInfoItem(
                    pid: port.pid,
                    title: Self.title(
                        for: port,
                        metadata: metadata,
                        group: group
                    ),
                    labels: labels
                )
            )
        }

        self.items = items
    }

    private static func title(
        for port: PortEntry,
        metadata: PortProcessMetadata?,
        group: PortProcessGroup
    ) -> String {
        if let detailName = group.portProcessDetails[port.id] ?? metadata?.processDetailName,
           !detailName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(detailName) · PID \(port.pid)"
        }

        return "PID \(port.pid)"
    }
}

struct PortProcessInfoItem: Equatable, Identifiable {
    let pid: Int
    let title: String
    let labels: PortProcessInfoLabels

    var copyPIDTitle: String {
        String(
            format: String(localized: "复制 PID (%@)", bundle: .main, comment: "复制 PID 菜单项，括号内显示实际进程 ID。"),
            locale: Locale.current,
            String(pid)
        )
    }

    var id: Int {
        pid
    }
}

struct PortProcessInfoLabels: Equatable {
    let source: String
    let memory: String?
    let path: String?
    let commandLineSummary: String?
    let redactedCommandLineSummary: String?

    var hasDetails: Bool {
        memory != nil || path != nil || commandLineSummary != nil || redactedCommandLineSummary != nil
    }

    init(metadata: PortProcessMetadata?) {
        guard let metadata else {
            self.source = ""
            self.memory = nil
            self.path = nil
            self.commandLineSummary = nil
            self.redactedCommandLineSummary = nil
            return
        }

        self.source = String(
            format: String(localized: "来源：%@", bundle: .main, comment: "进程来源推断标签。"),
            locale: Locale.current,
            metadata.sources.map(\.label).joined(separator: " • ")
        )
        let memoryValue = metadata.residentMemoryBytes
            .map { PortMemoryFormatter.string(bytes: $0) }
            ?? String(localized: "不可用", bundle: .main, comment: "无法读取进程常驻内存。")
        self.memory = String(
            format: String(localized: "常驻内存：%@", bundle: .main, comment: "进程常驻内存。"),
            locale: Locale.current,
            memoryValue
        )
        self.path = metadata.executablePath ?? metadata.path
        self.commandLineSummary = metadata.commandLineSummary
        self.redactedCommandLineSummary = metadata.redactedCommandLineSummary
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

struct PortProcessSectionLabels: Equatable {
    static func title(
        classification: PortProcessClassification,
        groups: [PortProcessGroup]
    ) -> String {
        let processCount = Set(groups.flatMap { group in
            group.ports.map(\.pid)
        }).count
        let portCount = groups.reduce(0) { $0 + $1.ports.count }
        return String(
            format: String(localized: "%@（%lld 进程 · %lld 端口）", bundle: .main, comment: "进程分区标题，包含进程数和端口数。"),
            locale: Locale.current,
            classification.sectionTitle,
            Int64(processCount),
            Int64(portCount)
        )
    }
}

struct PortMenuLabels: Equatable {
    let title: String
    let subtitle: String
    let localhostURLString: String?
    let lsofCommand: String

    static func showsPID(for ports: [PortEntry]) -> Bool {
        Set(ports.map(\.pid)).count > 1
    }

    init(
        port: PortEntry,
        showsPID: Bool,
        processName: String? = nil
    ) {
        self.title = "\(port.address):\(port.port)"
        self.localhostURLString = port.localhostURL?.absoluteString
        self.lsofCommand = port.lsofCommand

        var subtitle = "\(port.networkProtocol.rawValue) · \(port.addressExposure.label)"
        if showsPID {
            subtitle += " · PID \(port.pid)"
        }
        if let processName = processName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !processName.isEmpty {
            subtitle += " · \(processName)"
        }
        self.subtitle = subtitle
    }
}

private struct PortProcessIconView: View {
    let icon: PortProcessIcon

    var body: some View {
        switch icon {
        case let .application(path):
            if let path, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            } else {
                Image(systemName: "app.dashed")
            }
        case let .executable(path):
            if FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            } else {
                Image(systemName: "terminal")
            }
        case .process:
            Image(systemName: "terminal")
        }
    }
}

#Preview {
    MenuBarView(
        store: Store(
            initialState: AppFeature.State(
                lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
                ports: [
                    PortEntry(
                        networkProtocol: .tcp,
                        address: "127.0.0.1",
                        port: 8080,
                        pid: 123,
                        command: "node",
                        user: "501"
                    )
                ],
                processGroups: [
                    PortProcessGroup(
                        id: "process:123:node",
                        displayName: "node (PID 123)",
                        subtitle: "8080",
                        icon: .process,
                        ports: [
                            PortEntry(
                                networkProtocol: .tcp,
                                address: "127.0.0.1",
                                port: 8080,
                                pid: 123,
                                command: "node",
                                user: "501"
                            )
                        ]
                    )
                ]
            )
        ) {
            AppFeature()
        },
        updaterController: SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    )
}

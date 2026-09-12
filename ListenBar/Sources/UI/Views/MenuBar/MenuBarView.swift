import AppKit
import ComposableArchitecture
import Sparkle
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: StoreOf<AppFeature>
    @ObservedObject var updateMonitor: SparkleUpdateMonitor
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Group {
            Section {
                if let lastUpdated = store.lastUpdated {
                    Text("更新于 \(lastUpdated, style: .relative)")
                        .font(.caption)
                        .monospacedDigit()
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
                            groups: userGroups,
                        ),
                        groups: userGroups,
                    )
                }
                if !systemGroups.isEmpty {
                    processGroupsSection(
                        title: PortProcessSectionLabels.title(
                            classification: .systemOrOtherUser,
                            groups: systemGroups,
                        ),
                        groups: systemGroups,
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

            if !store.ignoredProcessesForMenu.isEmpty {
                Menu {
                    Section {
                        ForEach(store.ignoredProcessesForMenu) { item in
                            Button {
                                store.send(.view(.restoreIgnoredProcessTapped(item)))
                            } label: {
                                Label(item.displayName, systemImage: "eye")
                            }
                        }
                    } header: {
                        Text(IgnoredProcessMenuLabels.restoreHint)
                    }

                    Divider()

                    Button {
                        store.send(.view(.restoreAllIgnoredProcessesTapped))
                    } label: {
                        Label("恢复全部", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Label(
                        IgnoredProcessMenuLabels.menuTitle(
                            count: store.ignoredProcessesForMenu.count,
                        ),
                        systemImage: "eye.slash",
                    )
                }
            }

            Divider()

            Menu {
                ForEach(AutoRefreshMode.presets) { mode in
                    Button {
                        store.send(.view(.autoRefreshModeTapped(mode)))
                    } label: {
                        if store.autoRefreshMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                Label(
                    String(
                        format: String(localized: "自动刷新：%@", bundle: .main, comment: "自动刷新菜单标题。"),
                        locale: Locale.current,
                        store.autoRefreshMode.title,
                    ),
                    systemImage: "clock.arrow.circlepath",
                )
            }

            Toggle(
                "登录时打开",
                isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.send(.view(.setLaunchAtLogin($0))) },
                ),
            )
            .toggleStyle(.checkbox)

            if store.launchAtLoginRequiresApproval {
                Text("请前往“系统设置”>“通用”>“登录项”允许 ListenBar。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    LaunchAtLoginService.openSystemSettingsLoginItems()
                } label: {
                    Label("打开登录项设置", systemImage: "gear")
                }
            }

            Divider()

            AppInfoView(
                updateMonitor: updateMonitor,
                updaterController: updaterController,
            )

            Divider()

            Button {
                store.send(.view(.quitTapped))
            } label: {
                Label("退出 ListenBar", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
    }

    private func processGroupsSection(
        title: String,
        groups: [PortProcessGroup],
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
                    onIgnoreGroup: { group in
                        store.send(.view(.ignoreGroupTapped(group)))
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
                    onRevealApplicationPath: { group in
                        store.send(.view(.revealApplicationPathTapped(group)))
                    },
                    onKillPort: { port, mode in
                        store.send(.view(.killPortTapped(port, mode)))
                    },
                    onKillGroup: { group, mode in
                        store.send(.view(.killGroupTapped(group, mode)))
                    },
                    onQuitApplication: { group, mode in
                        store.send(.view(.quitApplicationTapped(group, mode)))
                    },
                )
            }
        }
    }

    private var emptyStateText: String {
        if store.isLoading {
            return String(localized: "正在扫描…", bundle: .main, comment: "扫描端口时的空状态。")
        }
        return IgnoredProcessMenuLabels.emptyState(
            hasIgnoredMatches: store.ignoredProcessGroupCount > 0,
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
    let onIgnoreGroup: (PortProcessGroup) -> Void
    let onCopyProcessPath: (Int) -> Void
    let onCopyCommandLine: (Int) -> Void
    let onCopyRedactedCommandLine: (Int) -> Void
    let onCopyLsofCommand: (PortEntry) -> Void
    let onRevealProcessPath: (Int) -> Void
    let onRevealApplicationPath: (PortProcessGroup) -> Void
    let onKillPort: (PortEntry, PortKillMode) -> Void
    let onKillGroup: (PortProcessGroup, PortKillMode) -> Void
    let onQuitApplication: (PortProcessGroup, ApplicationQuitMode) -> Void

    var body: some View {
        let labels = PortProcessGroupMenuLabels(group: group)
        let showsPIDInPortMenus = PortMenuLabels.showsPID(for: group.ports)
        let processInfoItems = PortProcessInfoItems(
            group: group,
            metadataByPID: metadataByPID,
        )
        let canIgnore = IgnoredProcessItem(
            group: group,
            metadataByPID: metadataByPID,
        ) != nil
        let onlineSearchQuery = PortProcessSearch.query(
            group: group,
            metadataByPID: metadataByPID,
        )

        Menu {
            Section(labels.portSectionTitle) {
                ForEach(group.ports) { port in
                    PortMenu(
                        port: port,
                        showsPID: showsPIDInPortMenus,
                        processName: group.portProcessDetails[port.id],
                        isLoading: isLoading,
                        onOpenLocalhost: onOpenLocalhost,
                        onCopyURL: onCopyURL,
                        onCopyLsofCommand: onCopyLsofCommand,
                        onKillPort: onKillPort,
                    )
                }
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

            if let onlineSearchQuery {
                Menu {
                    ForEach(PortProcessSearchProvider.allCases) { provider in
                        if let url = provider.url(query: onlineSearchQuery) {
                            Link(destination: url) {
                                Text(verbatim: provider.displayName)
                            }
                        }
                    }
                } label: {
                    Label("搜索进程信息", systemImage: "magnifyingglass")
                }
            }

            if canIgnore || group.applicationBundleIdentifier != nil {
                Divider()
            }

            if canIgnore {
                Button {
                    onIgnoreGroup(group)
                } label: {
                    Label(
                        IgnoredProcessMenuLabels.ignoreTitle(
                            isApplication: group.applicationBundleIdentifier != nil,
                        ),
                        systemImage: "eye.slash",
                    )
                }
            }

            if group.applicationBundleIdentifier != nil {
                Button {
                    onQuitApplication(group, .normal)
                } label: {
                    Label(
                        String(
                            format: String(localized: "退出 %@", bundle: .main, comment: "正常退出应用菜单项。"),
                            locale: Locale.current,
                            group.displayName,
                        ),
                        systemImage: "rectangle.portrait.and.arrow.right",
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
                            group.displayName,
                        ),
                        systemImage: "exclamationmark.octagon",
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
                    onRevealProcessPath: onRevealProcessPath,
                    onRevealApplicationPath: {
                        onRevealApplicationPath(group)
                    },
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
                                onRevealProcessPath: onRevealProcessPath,
                                onRevealApplicationPath: {
                                    onRevealApplicationPath(group)
                                },
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
            Text(labels.title)
            Text(labels.subtitle)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

enum PortProcessSearchProvider: CaseIterable, Hashable, Identifiable {
    case google
    case bing
    case baidu

    var id: Self { self }

    var displayName: String {
        switch self {
        case .google:
            "Google"
        case .bing:
            "Bing"
        case .baidu:
            "百度"
        }
    }

    func url(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"

        switch self {
        case .google:
            components.host = "www.google.com"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .bing:
            components.host = "www.bing.com"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .baidu:
            components.host = "www.baidu.com"
            components.path = "/s"
            components.queryItems = [URLQueryItem(name: "wd", value: query)]
        }

        return components.url
    }
}

enum PortProcessSearch {
    static func query(
        group: PortProcessGroup,
        metadataByPID: [Int: PortProcessMetadata],
    ) -> String? {
        let processIdentity: String

        if let bundleIdentifier = normalized(group.applicationBundleIdentifier) {
            let displayName = normalized(group.displayName)
            if let displayName,
               displayName.caseInsensitiveCompare(bundleIdentifier) != .orderedSame
            {
                processIdentity = "\(displayName) \(bundleIdentifier)"
            } else {
                processIdentity = bundleIdentifier
            }
        } else {
            guard let firstPort = group.ports.first,
                  let processName = normalized(metadataByPID[firstPort.pid]?.name)
                  ?? normalized(firstPort.command)
            else {
                return nil
            }
            processIdentity = processName
        }

        return "\(processIdentity) macOS process"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let normalized = value?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " "),
            !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }
}

enum IgnoredProcessMenuLabels {
    static var restoreHint: String {
        String(localized: "点击项目以恢复显示", bundle: .main, comment: "已忽略项目子菜单的恢复操作说明。")
    }

    static func ignoreTitle(isApplication: Bool) -> String {
        if isApplication {
            return String(localized: "忽略此 App", bundle: .main, comment: "忽略应用菜单项。")
        }
        return String(localized: "忽略此进程", bundle: .main, comment: "忽略进程菜单项。")
    }

    static func menuTitle(count: Int) -> String {
        String(
            format: String(localized: "已忽略项目（%lld）", bundle: .main, comment: "已忽略项目子菜单标题。"),
            locale: Locale.current,
            Int64(count),
        )
    }

    static func emptyState(hasIgnoredMatches: Bool) -> String {
        if hasIgnoredMatches {
            return String(localized: "所有监听项目均已忽略", bundle: .main, comment: "扫描结果全部被忽略时的空状态。")
        }
        return String(localized: "未发现监听端口", bundle: .main, comment: "没有发现监听端口时的空状态。")
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
            processName: processName,
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
    let onRevealApplicationPath: () -> Void

    var body: some View {
        Button {
            onCopyPID(item.pid)
        } label: {
            Label(item.copyPIDTitle, systemImage: "number")
                .monospacedDigit()
        }

        if item.details.hasDetails {
            Section(item.details.source) {
                if let memory = item.details.memory {
                    Label(memory, systemImage: "memorychip")
                        .monospacedDigit()
                }

                if let applicationPath = item.applicationPath {
                    Button {
                        onRevealApplicationPath()
                    } label: {
                        Label {
                            Text("在 Finder 中显示 App")
                            Text(verbatim: applicationPath)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .disabled(isLoading)
                }

                if let executablePath = item.executablePathToReveal {
                    Button {
                        onRevealProcessPath(item.pid)
                    } label: {
                        Label {
                            Text("在 Finder 中显示可执行文件")
                            Text(verbatim: executablePath)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .disabled(isLoading)
                }

                if let path = item.details.path {
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

                if let redactedCommandLineSummary = item.details.redactedCommandLineSummary {
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

                if item.details.commandLineSummary != nil {
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

struct PortProcessSectionLabels: Equatable {
    static func title(
        classification: PortProcessClassification,
        groups: [PortProcessGroup],
    ) -> String {
        let processCount = Set(groups.flatMap { group in
            group.ports.map(\.pid)
        }).count
        let portCount = groups.reduce(0) { $0 + $1.ports.count }
        return String(
            format: String(localized: "%@（%@ · %@）", bundle: .main, comment: "进程分区标题，包含进程数和端口数。"),
            locale: Locale.current,
            classification.sectionTitle,
            MenuCountLabels.processes(processCount),
            MenuCountLabels.ports(portCount),
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
        processName: String? = nil,
    ) {
        self.title = "\(port.address):\(port.port)"
        self.localhostURLString = port.localhostURL?.absoluteString
        self.lsofCommand = port.lsofCommand

        var subtitle = "\(port.networkProtocol.rawValue) · \(port.addressExposure.label)"
        if showsPID {
            subtitle += " · PID \(port.pid)"
        }
        if let processName = processName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !processName.isEmpty
        {
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
                        user: "501",
                    ),
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
                                user: "501",
                            ),
                        ],
                    ),
                ],
            ),
        ) {
            AppFeature()
        },
        updateMonitor: SparkleUpdateMonitor(),
        updaterController: SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        ),
    )
}

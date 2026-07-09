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
                Section("进程") {
                    ForEach(store.processGroups) { group in
                        PortProcessGroupMenu(
                            group: group,
                            isLoading: store.isLoading,
                            onOpenLocalhost: { port in
                                store.send(.view(.openLocalhostTapped(port)))
                            },
                            onCopyURL: { port in
                                store.send(.view(.copyURLTapped(port)))
                            },
                            onCopyPID: { port in
                                store.send(.view(.copyPIDTapped(port)))
                            },
                            onCopyLsofCommand: { port in
                                store.send(.view(.copyLsofCommandTapped(port)))
                            },
                            onKillPort: { port, mode in
                                store.send(.view(.killPortTapped(port, mode)))
                            }
                        )
                    }
                }
            }

            Divider()

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
        .confirmationDialog($store.scope(\.confirmationDialog, action: \.confirmationDialog))
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
    let isLoading: Bool
    let onOpenLocalhost: (PortEntry) -> Void
    let onCopyURL: (PortEntry) -> Void
    let onCopyPID: (PortEntry) -> Void
    let onCopyLsofCommand: (PortEntry) -> Void
    let onKillPort: (PortEntry, PortKillMode) -> Void

    var body: some View {
        let showsPIDInPortMenus = PortMenuLabels.showsPID(for: group.ports)

        Menu {
            ForEach(group.ports) { port in
                PortMenu(
                    port: port,
                    showsPID: showsPIDInPortMenus,
                    processName: group.portProcessDetails[port.id] == nil ? nil : port.command,
                    isLoading: isLoading,
                    onOpenLocalhost: onOpenLocalhost,
                    onCopyURL: onCopyURL,
                    onCopyPID: onCopyPID,
                    onCopyLsofCommand: onCopyLsofCommand,
                    onKillPort: onKillPort
                )
            }
        } label: {
            PortProcessIconView(icon: group.icon)
            Text(group.displayName)
            Text(group.subtitle)
                .foregroundStyle(.secondary)
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
    let onCopyPID: (PortEntry) -> Void
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
                onCopyPID(port)
            } label: {
                Label("复制 PID", systemImage: "number")
            }

            Button {
                onCopyLsofCommand(port)
            } label: {
                Label("复制 lsof 命令", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onKillPort(port, .quit)
            } label: {
                Label(PortKillMode.quit.title, systemImage: "xmark.circle")
            }
            .disabled(isLoading)

            Button(role: .destructive) {
                onKillPort(port, .force)
            } label: {
                Label(PortKillMode.force.title, systemImage: "exclamationmark.octagon")
            }
            .disabled(isLoading)
        } label: {
            Text(verbatim: labels.title)
            Text(verbatim: labels.subtitle)
                .foregroundStyle(.secondary)
        }
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
        self.title = String(port.port)
        self.localhostURLString = port.localhostURL?.absoluteString
        self.lsofCommand = port.lsofCommand

        var subtitle = "\(port.networkProtocol.rawValue) \(port.address):\(port.port) · \(port.addressExposure.label)"
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

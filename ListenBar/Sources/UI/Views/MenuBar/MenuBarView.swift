import AppKit
import ComposableArchitecture
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        Group {
            Section {
                Button {
                    store.send(.view(.refreshTapped))
                } label: {
                    Label(store.isLoading ? "刷新中..." : "刷新端口", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .keyboardShortcut("r", modifiers: .command)

                if let lastUpdated = store.lastUpdated {
                    Text("更新于 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
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
                    Text(store.isLoading ? "正在扫描..." : "未发现监听端口")
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
                store.send(.view(.quitTapped))
            } label: {
                Label("退出 ListenBar", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .confirmationDialog($store.scope(\.confirmationDialog, action: \.confirmationDialog))
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
                    Label("Open localhost", systemImage: "safari")
                }
                .disabled(isLoading)

                Button {
                    onCopyURL(port)
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
            }

            Button {
                onCopyPID(port)
            } label: {
                Label("Copy PID", systemImage: "number")
            }

            Button {
                onCopyLsofCommand(port)
            } label: {
                Label("Copy lsof command", systemImage: "doc.on.doc")
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
        }
    )
}

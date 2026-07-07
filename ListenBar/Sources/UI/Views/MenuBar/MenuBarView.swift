import AppKit
import ComposableArchitecture
import SwiftUI

struct MenuBarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Section {
            Button {
                store.send(.view(.refreshTapped))
            } label: {
                Label(store.isLoading ? "刷新中..." : "刷新端口", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)

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
                        isLoading: store.isLoading
                    ) { port in
                        store.send(.view(.killPortTapped(port)))
                    }
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
}

private struct PortProcessGroupMenu: View {
    let group: PortProcessGroup
    let isLoading: Bool
    let onKillPort: (PortEntry) -> Void

    var body: some View {
        Menu {
            ForEach(group.ports) { port in
                PortMenu(
                    port: port,
                    isLoading: isLoading,
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
    let isLoading: Bool
    let onKillPort: (PortEntry) -> Void

    var body: some View {
        Menu {
            Button(role: .destructive) {
                onKillPort(port)
            } label: {
                Label("终止占用进程", systemImage: "xmark.circle")
            }
            .disabled(isLoading)
        } label: {
            Text("\(port.networkProtocol.rawValue) \(port.address):\(port.port)")
            Text("PID \(port.pid)")
                .foregroundStyle(.secondary)
        }
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

import AppKit
import ComposableArchitecture
import IssueReporting
import Sparkle
import SwiftUI

@main
struct ListenBarApp: App {
    let menuTrackingObservers: [NSObjectProtocol]
    let store: StoreOf<AppFeature>
    let updaterController: SPUStandardUpdaterController

    init() {
        PortKillInteractionService.configureNotifications()
        let store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
        self.store = store
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.menuTrackingObservers = [
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { notification in
                MainActor.assumeIsolated {
                    guard MenuBarView.isRootMenuTrackingNotification(notification) else { return }
                    store.send(.menuPresented)
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main
            ) { notification in
                MainActor.assumeIsolated {
                    guard MenuBarView.isRootMenuTrackingNotification(notification) else { return }
                    store.send(.menuDismissed)
                }
            }
        ]
        if !isTesting {
            store.send(.task)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, updaterController: updaterController)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("ListenBar")
        }
        .menuBarExtraStyle(.menu)
    }
}

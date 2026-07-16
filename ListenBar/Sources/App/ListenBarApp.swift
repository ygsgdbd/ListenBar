import AppKit
import ComposableArchitecture
import IssueReporting
import Sharing
import Sparkle
import SwiftUI

@main
struct ListenBarApp: App {
    let menuTrackingObservers: [NSObjectProtocol]
    let readmeBackdropWindow: NSWindow?
    let readmeColorScheme: ColorScheme?
    let store: StoreOf<AppFeature>
    let updateMonitor: SparkleUpdateMonitor
    let updaterController: SPUStandardUpdaterController

    init() {
        PortKillInteractionService.configureNotifications()
        #if DEBUG
            let readmeConfiguration = ReadmeScreenshotConfiguration(
                arguments: ProcessInfo.processInfo.arguments,
            )
            if readmeConfiguration != nil {
                prepareDependencies {
                    $0.defaultFileStorage = .inMemory
                }
            }
            readmeConfiguration?.applyAppearance()
            let readmeMenuAppearance = readmeConfiguration?.appAppearance
            self.readmeBackdropWindow = readmeConfiguration?.makeBackdropWindow()
            self.readmeColorScheme = readmeConfiguration?.colorScheme
            let initialState = readmeConfiguration?.initialState(now: Date()) ?? AppFeature.State()
            let startsLiveServices = readmeConfiguration == nil
        #else
            let readmeMenuAppearance: NSAppearance? = nil
            self.readmeBackdropWindow = nil
            self.readmeColorScheme = nil
            let initialState = AppFeature.State()
            let startsLiveServices = true
        #endif
        let store = Store(initialState: initialState) {
            AppFeature()
        }
        let updateMonitor = SparkleUpdateMonitor()
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: startsLiveServices,
            updaterDelegate: updateMonitor,
            userDriverDelegate: nil,
        )
        self.store = store
        self.updateMonitor = updateMonitor
        self.updaterController = updaterController
        self.menuTrackingObservers = [
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main,
            ) { notification in
                MainActor.assumeIsolated {
                    if let menu = notification.object as? NSMenu,
                       let readmeMenuAppearance
                    {
                        menu.appearance = readmeMenuAppearance
                        for item in menu.items {
                            item.submenu?.appearance = readmeMenuAppearance
                        }
                    }
                    guard MenuBarView.isRootMenuTrackingNotification(notification) else { return }
                    store.send(.menuPresented)
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main,
            ) { notification in
                MainActor.assumeIsolated {
                    guard MenuBarView.isRootMenuTrackingNotification(notification) else { return }
                    store.send(.menuDismissed)
                }
            },
        ]
        if !isTesting && startsLiveServices {
            updateMonitor.startSilentCheck(using: updaterController.updater)
            store.send(.task)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: store,
                updateMonitor: updateMonitor,
                updaterController: updaterController,
            )
            .preferredColorScheme(readmeColorScheme)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("ListenBar")
        }
        .menuBarExtraStyle(.menu)
    }
}

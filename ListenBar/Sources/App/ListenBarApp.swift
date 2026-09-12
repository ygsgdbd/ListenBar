import AppKit
import ComposableArchitecture
import IssueReporting
import Sharing
import Sparkle
import SwiftUI

@main
struct ListenBarApp: App {
    let menuTrackingCoordinator: MenuTrackingCoordinator
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
        let startsUpdater = startsLiveServices && !isTesting
        let updateMonitor = SparkleUpdateMonitor()
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: updateMonitor,
            userDriverDelegate: updateMonitor,
        )
        self.store = store
        self.updateMonitor = updateMonitor
        self.updaterController = updaterController
        self.menuTrackingCoordinator = MenuTrackingCoordinator(
            store: store,
            updateMonitor: updateMonitor,
            readmeMenuAppearance: readmeMenuAppearance,
        )
        if startsUpdater {
            updateMonitor.startSilentCheck(using: updaterController.updater)
        }
        if !isTesting && startsLiveServices {
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

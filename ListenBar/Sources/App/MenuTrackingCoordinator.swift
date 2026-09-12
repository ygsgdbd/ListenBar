import AppKit
import ComposableArchitecture

final class MenuTrackingCoordinator {
    private let notificationCenter: NotificationCenter
    private let observers: [NSObjectProtocol]

    @MainActor
    init(
        store: StoreOf<AppFeature>,
        updateMonitor: SparkleUpdateMonitor,
        readmeMenuAppearance: NSAppearance? = nil,
        notificationCenter: NotificationCenter = .default,
    ) {
        self.notificationCenter = notificationCenter
        self.observers = [
            notificationCenter.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main,
            ) { notification in
                MainActor.assumeIsolated {
                    guard let menu = notification.object as? NSMenu else { return }
                    if let readmeMenuAppearance {
                        menu.appearance = readmeMenuAppearance
                        for item in menu.items {
                            item.submenu?.appearance = readmeMenuAppearance
                        }
                    }
                    guard Self.isRootMenu(menu) else { return }
                    updateMonitor.menuTrackingDidBegin()
                    store.send(.menuPresented)
                }
            },
            notificationCenter.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main,
            ) { notification in
                MainActor.assumeIsolated {
                    guard let menu = notification.object as? NSMenu,
                          Self.isRootMenu(menu)
                    else { return }
                    updateMonitor.menuTrackingDidEnd()
                    store.send(.menuDismissed)
                }
            },
        ]
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    @MainActor
    private static func isRootMenu(_ menu: NSMenu) -> Bool {
        menu.supermenu == nil && menu !== NSApp.mainMenu
    }
}

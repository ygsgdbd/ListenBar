import AppKit
import Foundation
import UserNotifications

struct PortKillConfirmation: Equatable, Sendable {
    let title: String
    let message: String
    let confirmButtonTitle: String
    let isDestructive: Bool
}

struct PortKillNotification: Equatable, Sendable {
    let title: String
    let body: String
}

enum PortKillInteractionService {
    @MainActor
    private static let notificationDelegate = PortKillNotificationDelegate()

    @MainActor
    static func configureNotifications() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    @MainActor
    static func confirm(_ confirmation: PortKillConfirmation) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.addButton(withTitle: confirmation.confirmButtonTitle)
        alert.buttons.first?.hasDestructiveAction = confirmation.isDestructive
        alert.addButton(
            withTitle: String(localized: "取消", bundle: .main, comment: "取消按钮标题。")
        )

        return alert.runModal() == .alertFirstButtonReturn
    }

    static func send(_ notification: PortKillNotification) async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body

            try await center.add(
                UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
            )
        } catch {
            // Notifications are best-effort and must not change the kill result.
        }
    }
}

private final class PortKillNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

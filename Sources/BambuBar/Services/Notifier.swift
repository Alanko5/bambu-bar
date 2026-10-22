import Foundation
import UserNotifications

/// Posts print notifications (finished, failed, paused, errors).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter? {
        // Notification Center needs a real app bundle; developer runs from a bare binary skip it.
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, id: String) {
        guard let center else { return }
        center.getNotificationSettings { settings in
            let send = {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.threadIdentifier = "printer"
                // Same id replaces the previous one of its kind instead of piling up.
                center.add(UNNotificationRequest(identifier: "bambubar.\(id)", content: content, trigger: nil))
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional: send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in if granted { send() } }
            default: break
            }
        }
    }

    // Show banners even while the app's own window is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { MainWindow.show(.overview) }
        completionHandler()
    }
}

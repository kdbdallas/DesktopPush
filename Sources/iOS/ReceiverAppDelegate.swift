import Foundation
import UIKit
import SwiftUI
@preconcurrency import UserNotifications
import DesktopPushSharediOS

@main
final class ReceiverAppDelegate: UIResponder, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        clearApplicationBadge(application)
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.refreshNotificationStatus(error: error)
            }
        }
        refreshNotificationStatus()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ReceiverSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apns-device-token")
        UserDefaults.standard.removeObject(forKey: "apns-registration-error")
        NotificationCenter.default.post(name: .receiverTokenDidChange, object: nil)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "apns-registration-error")
        NotificationCenter.default.post(name: .receiverTokenDidChange, object: nil)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        clearApplicationBadge(application)
        application.registerForRemoteNotifications()
        refreshNotificationStatus()
        Task { [weak self] in
            let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
            for notification in notifications where notification.request.content.userInfo["desktoppush-id"] != nil {
                self?.appendToHistory(notification.request.content)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        appendToHistory(notification.request.content)
        clearApplicationBadge(UIApplication.shared)
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        appendToHistory(response.notification.request.content)
        clearApplicationBadge(UIApplication.shared)
    }

    private func appendToHistory(_ content: UNNotificationContent) {
        let identifier = (content.userInfo["desktoppush-id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let attachmentKind = (content.userInfo["desktoppush-attachment-kind"] as? String).flatMap(AttachmentKind.init(rawValue:))
        let record = ReceivedNotification(
            id: identifier,
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            attachmentKind: attachmentKind,
            attachmentFileName: content.attachments.first?.url.lastPathComponent,
            badge: content.badge?.intValue,
            categoryIdentifier: content.categoryIdentifier,
            threadIdentifier: content.threadIdentifier,
            soundRequested: content.sound != nil,
            userInfo: displayableUserInfo(content.userInfo)
        )
        NotificationHistory.append(record)
        NotificationCenter.default.post(name: .receiverHistoryDidChange, object: nil)
    }

    private func displayableUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo.reduce(into: [:]) { result, entry in
            guard let key = entry.key as? String, key != "aps" else { return }
            result[key] = entry.value as? String ?? String(describing: entry.value)
        }
    }

    private func clearApplicationBadge(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    private func refreshNotificationStatus(error: Error? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let message: String?
            if let error {
                message = error.localizedDescription
            } else {
                switch settings.authorizationStatus {
                case .denied:
                    message = "Notifications are disabled. Enable them in Settings to receive pushes."
                case .notDetermined:
                    message = "Allow notifications when prompted to receive pushes."
                case .authorized, .provisional, .ephemeral:
                    message = nil
                @unknown default:
                    message = "Notification permission status is unavailable."
                }
            }
            DispatchQueue.main.async {
                if let message {
                    UserDefaults.standard.set(message, forKey: "apns-registration-error")
                } else {
                    UserDefaults.standard.removeObject(forKey: "apns-registration-error")
                }
                NotificationCenter.default.post(name: .receiverTokenDidChange, object: nil)
            }
        }
    }
}

final class ReceiverSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: NotificationHistoryView())
        window.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        self.window = window
    }
}

extension Notification.Name {
    static let receiverHistoryDidChange = Notification.Name("receiverHistoryDidChange")
    static let receiverTokenDidChange = Notification.Name("receiverTokenDidChange")
}

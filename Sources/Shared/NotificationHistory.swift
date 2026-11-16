import Foundation

public enum NotificationHistory {
    public static let appGroup = "group.com.port21.desktoppush"
    private static let key = "received-notification-history"

    private static var defaults: UserDefaults {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil,
              let sharedDefaults = UserDefaults(suiteName: appGroup) else {
            return .standard
        }
        return sharedDefaults
    }

    public static func load() -> [ReceivedNotification] {
        defaults.synchronize()
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder.desktopPush.decode([ReceivedNotification].self, from: data) else { return [] }
        return Array(history.sorted { $0.receivedAt > $1.receivedAt }.prefix(10))
    }

    public static func append(_ notification: ReceivedNotification) {
        var history = load()
        history.removeAll { $0.id == notification.id }
        history.insert(notification, at: 0)
        history.sort { $0.receivedAt > $1.receivedAt }
        let data = try? JSONEncoder.desktopPush.encode(Array(history.prefix(10)))
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    public static func clear() {
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }
}

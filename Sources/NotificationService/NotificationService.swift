@preconcurrency import UserNotifications
import DesktopPushSharediOS

final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content
        attachRemoteMediaIfPresent(to: content, original: request.content, contentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttemptContent {
            record(bestAttemptContent)
            contentHandler?(bestAttemptContent)
        }
    }

    private func attachRemoteMediaIfPresent(to content: UNMutableNotificationContent, original: UNNotificationContent, contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let string = original.userInfo["desktoppush-attachment-url"] as? String,
              let remoteURL = URL(string: string),
              remoteURL.scheme == "https" else {
            record(content)
            contentHandler(content)
            self.contentHandler = nil
            return
        }
        let contentBox = UncheckedBox(content)
        let handlerBox = UncheckedBox(contentHandler)
        URLSession.shared.downloadTask(with: remoteURL) { [weak self, contentBox, handlerBox] temporaryURL, response, _ in
            defer { self?.finish(content: contentBox, handler: handlerBox) }
            guard let temporaryURL else { return }
            do {
                let extensionHint = response?.suggestedFilename?.split(separator: ".").last.map(String.init) ?? remoteURL.pathExtension
                let fileURL = FileManager.default.temporaryDirectory.appending(path: "desktoppush-\(UUID().uuidString).\(extensionHint.isEmpty ? "attachment" : extensionHint)")
                try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
                contentBox.value.attachments = [try UNNotificationAttachment(identifier: "desktoppush-media", url: fileURL)]
            } catch { }
        }.resume()
    }

    private func finish(content: UncheckedBox<UNMutableNotificationContent>, handler: UncheckedBox<(UNNotificationContent) -> Void>) {
        record(content.value)
        handler.value(content.value)
        contentHandler = nil
    }

    private func record(_ content: UNNotificationContent) {
        let identifier = (content.userInfo["desktoppush-id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let kind = (content.userInfo["desktoppush-attachment-kind"] as? String).flatMap(AttachmentKind.init(rawValue:))
        NotificationHistory.append(
            ReceivedNotification(
                id: identifier,
                title: content.title,
                subtitle: content.subtitle,
                body: content.body,
                attachmentKind: kind,
                attachmentFileName: content.attachments.first?.url.lastPathComponent,
                badge: content.badge?.intValue,
                categoryIdentifier: content.categoryIdentifier,
                threadIdentifier: content.threadIdentifier,
                soundRequested: content.sound != nil,
                userInfo: displayableUserInfo(content.userInfo)
            )
        )
    }

    private func displayableUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo.reduce(into: [:]) { result, entry in
            guard let key = entry.key as? String, key != "aps" else { return }
            result[key] = entry.value as? String ?? String(describing: entry.value)
        }
    }
}

private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

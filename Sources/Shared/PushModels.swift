import Foundation

public enum APNSEnvironment: String, Codable, CaseIterable, Sendable, Identifiable {
    case sandbox
    case production

    public var id: String { rawValue }
    public var host: String {
        switch self {
        case .sandbox: "api.sandbox.push.apple.com"
        case .production: "api.push.apple.com"
        }
    }
}

public enum AttachmentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case image, gif, audio, video

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .image: "photo"
        case .gif: "sparkles.rectangle.stack"
        case .audio: "waveform"
        case .video: "video"
        }
    }
}

public struct PushAttachment: Codable, Equatable, Sendable {
    public var kind: AttachmentKind
    public var remoteURL: URL

    public init(kind: AttachmentKind, remoteURL: URL) {
        self.kind = kind
        self.remoteURL = remoteURL
    }
}

public struct PushPayload: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var body: String
    public var badge: Int?
    public var sound: String?
    public var attachment: PushAttachment?
    public var category: String?
    public var threadIdentifier: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String = "",
        body: String = "",
        badge: Int? = nil,
        sound: String? = "default",
        attachment: PushAttachment? = nil,
        category: String? = nil,
        threadIdentifier: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
        self.sound = sound
        self.attachment = attachment
        self.category = category
        self.threadIdentifier = threadIdentifier
        self.createdAt = createdAt
    }

    public var requestBody: Data? {
        var alert: [String: Any] = ["title": title, "body": body]
        if !subtitle.isEmpty { alert["subtitle"] = subtitle }
        var aps: [String: Any] = ["alert": alert, "mutable-content": 1]
        if let badge { aps["badge"] = badge }
        if let sound, !sound.isEmpty { aps["sound"] = sound }
        if let category, !category.isEmpty { aps["category"] = category }
        if let threadIdentifier, !threadIdentifier.isEmpty { aps["thread-id"] = threadIdentifier }

        var envelope: [String: Any] = ["aps": aps, "desktoppush-id": id.uuidString]
        if let attachment {
            envelope["desktoppush-attachment-url"] = attachment.remoteURL.absoluteString
            envelope["desktoppush-attachment-kind"] = attachment.kind.rawValue
        }
        return try? JSONSerialization.data(withJSONObject: envelope)
    }
}

public struct DeviceRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var token: String
    public var environment: APNSEnvironment
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, token: String, environment: APNSEnvironment = .sandbox, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.token = token.normalizedDeviceToken
        self.environment = environment
        self.createdAt = createdAt
    }
}

public struct CertificateProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var topic: String
    public var environment: APNSEnvironment
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, topic: String, environment: APNSEnvironment, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.topic = topic
        self.environment = environment
        self.createdAt = createdAt
    }
}

public struct ScheduledPush: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var payload: PushPayload
    public var deviceIDs: [UUID]
    public var certificateID: UUID
    public var fireDate: Date
    public var deliveredAt: Date?
    public var lastError: String?

    public init(id: UUID = UUID(), payload: PushPayload, deviceIDs: [UUID], certificateID: UUID, fireDate: Date, deliveredAt: Date? = nil, lastError: String? = nil) {
        self.id = id
        self.payload = payload
        self.deviceIDs = deviceIDs
        self.certificateID = certificateID
        self.fireDate = fireDate
        self.deliveredAt = deliveredAt
        self.lastError = lastError
    }
}

public struct DeliveryResult: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable, Equatable { case delivered, failed }
    public var id: UUID
    public var deviceID: UUID
    public var date: Date
    public var status: Status
    public var detail: String

    public init(id: UUID = UUID(), deviceID: UUID, date: Date = .now, status: Status, detail: String) {
        self.id = id
        self.deviceID = deviceID
        self.date = date
        self.status = status
        self.detail = detail
    }
}

public struct ReceivedNotification: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var body: String
    public var receivedAt: Date
    public var attachmentKind: AttachmentKind?
    public var attachmentFileName: String?
    public var badge: Int?
    public var categoryIdentifier: String
    public var threadIdentifier: String
    public var soundRequested: Bool
    public var userInfo: [String: String]

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        body: String,
        receivedAt: Date = .now,
        attachmentKind: AttachmentKind? = nil,
        attachmentFileName: String? = nil,
        badge: Int? = nil,
        categoryIdentifier: String = "",
        threadIdentifier: String = "",
        soundRequested: Bool = false,
        userInfo: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.receivedAt = receivedAt
        self.attachmentKind = attachmentKind
        self.attachmentFileName = attachmentFileName
        self.badge = badge
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
        self.soundRequested = soundRequested
        self.userInfo = userInfo
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, body, receivedAt, attachmentKind, attachmentFileName
        case badge, categoryIdentifier, threadIdentifier, soundRequested, userInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt) ?? .now
        attachmentKind = try container.decodeIfPresent(AttachmentKind.self, forKey: .attachmentKind)
        attachmentFileName = try container.decodeIfPresent(String.self, forKey: .attachmentFileName)
        badge = try container.decodeIfPresent(Int.self, forKey: .badge)
        categoryIdentifier = try container.decodeIfPresent(String.self, forKey: .categoryIdentifier) ?? ""
        threadIdentifier = try container.decodeIfPresent(String.self, forKey: .threadIdentifier) ?? ""
        soundRequested = try container.decodeIfPresent(Bool.self, forKey: .soundRequested) ?? false
        userInfo = try container.decodeIfPresent([String: String].self, forKey: .userInfo) ?? [:]
    }
}

public extension String {
    var normalizedDeviceToken: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("<", with: "")
            .replacing(">", with: "")
            .replacing(" ", with: "")
    }
}

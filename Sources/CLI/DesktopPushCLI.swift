import Foundation
import DesktopPushSharedMac

@main
struct DesktopPushCLI {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else { throw CLIError.usage }
            let options = Options(arguments: Array(arguments.dropFirst()))
            switch command {
            case "send": try await send(options)
            case "notification-center": try await forwardNotificationCenter(options)
            case "help", "--help", "-h": print(help)
            default: throw CLIError.usage
            }
        } catch {
            fputs("desktoppush: \(error.localizedDescription)\n", stderr)
            fputs("Run `desktoppush help` for usage.\n", stderr)
            exit(1)
        }
    }

    private static func send(_ options: Options) async throws {
        let configuration = try SendConfiguration(options: options)
        try await send(configuration.payload, using: configuration)
    }

    private static func forwardNotificationCenter(_ options: Options) async throws {
        let configuration = try SendConfiguration(options: options)
        let limit = Int(options.value(for: "limit") ?? "1") ?? 1
        let afterCursor = try cursor(named: "after-cursor", in: options)
        let throughCursor = try cursor(named: "through-cursor", in: options)
        let entries = try NotificationCenterReader.entries(
            limit: max(1, min(limit, 20)),
            afterCursor: afterCursor,
            throughCursor: throughCursor
        )
        // In range mode an empty result just means every record in the range was
        // unreadable or already removed; treat it as handled so the caller advances.
        guard !entries.isEmpty || afterCursor != nil else { throw CLIError.noNotificationEntries }
        for entry in entries {
            var payload = configuration.payload
            payload.title = entry.title
            payload.subtitle = entry.subtitle
            payload.body = entry.body
            try await send(payload, using: configuration)
            print("Forwarded record \(entry.cursor): \(entry.title)")
        }
    }

    private static func cursor(named name: String, in options: Options) throws -> NotificationCursor? {
        guard let value = options.value(for: name) else { return nil }
        guard let cursor = NotificationCursor(value) else { throw CLIError.invalidCursor(name) }
        return cursor
    }

    private static func send(_ payload: PushPayload, using configuration: SendConfiguration) async throws {
        for device in configuration.devices {
            try await APNSClient.send(
                payload: payload,
                to: device,
                topic: configuration.topic,
                certificateData: configuration.certificateData,
                certificatePassword: configuration.password
            )
            print("Accepted by APNs for \(device.name).")
        }
    }

    private static let help = """
    DesktopPush command-line sender

    Send a push:
      desktoppush send --certificate Push.p12 --password secret --topic com.example.Receiver \\
        --token APNS_DEVICE_TOKEN --title "Build complete" --body "All tests passed"

    Broadcast a push to every device saved in DesktopPush for Mac:
      desktoppush send --certificate Push.p12 --password secret --topic com.example.Receiver \\
        --broadcast --title "Build complete" --body "All tests passed"

    Forward the most recent macOS Notification Center entry:
      desktoppush notification-center --certificate Push.p12 --password secret --topic com.example.Receiver \\
        --token APNS_DEVICE_TOKEN --limit 1

    Forward an exact range of delivered Notification Center records (used by the background forwarder):
      desktoppush notification-center --certificate Push.p12 --password secret --topic com.example.Receiver \\
        --broadcast --after-cursor 816470470946069:10077 --through-cursor 816475844463850:10082 --limit 20

    Options: --subtitle TEXT --badge NUMBER --sound default|none|FILENAME
             --attachment HTTPS_URL --attachment-kind image|gif|audio|video
             --environment sandbox|production --name DEVICE_NAME
             --broadcast (use saved devices; do not combine with --token)
             --after-cursor CURSOR --through-cursor CURSOR

    A cursor is DELIVERED_MICROSECONDS:RECORD_ID. Record IDs alone are not usable
    as a position because macOS reuses them after the newest record is removed.

    The notification-center command reads the local usernoted database. macOS may
    require Full Disk Access for your terminal; its internal database schema can change.
    """
}

private struct SendConfiguration {
    let certificateData: Data
    let password: String
    let topic: String
    let devices: [DeviceRecord]
    let payload: PushPayload

    init(options: Options) throws {
        guard let certificatePath = options.value(for: "certificate"),
              let password = options.value(for: "password"),
              let topic = options.value(for: "topic") else { throw CLIError.missingRequiredOption }
        let isBroadcast = options.contains("broadcast")
        let token = options.value(for: "token")
        guard !(isBroadcast && token != nil) else { throw CLIError.conflictingRecipients }
        let environment = APNSEnvironment(rawValue: options.value(for: "environment") ?? "sandbox") ?? .sandbox
        let soundValue = options.value(for: "sound")
        let sound = soundValue == "none" ? nil : (soundValue ?? "default")
        let attachment = try options.value(for: "attachment").map { string -> PushAttachment in
            guard let url = URL(string: string), url.scheme == "https" else { throw CLIError.invalidAttachmentURL }
            let kind = AttachmentKind(rawValue: options.value(for: "attachment-kind") ?? "image") ?? .image
            return PushAttachment(kind: kind, remoteURL: url)
        }
        var isDirectory: ObjCBool = false
        guard !certificatePath.isEmpty,
              FileManager.default.fileExists(atPath: certificatePath, isDirectory: &isDirectory),
              !isDirectory.boolValue else { throw CLIError.certificateNotFound(certificatePath) }
        guard !password.isEmpty else { throw CLIError.emptyPassword }
        certificateData = try Data(contentsOf: URL(fileURLWithPath: certificatePath))
        self.password = password
        self.topic = topic
        if isBroadcast {
            let savedDevices = LocalStore.load([DeviceRecord].self, from: "devices.json", fallback: [])
            guard !savedDevices.isEmpty else { throw CLIError.noSavedDevices }
            devices = savedDevices
        } else {
            guard let token else { throw CLIError.missingRequiredOption }
            devices = [DeviceRecord(name: options.value(for: "name") ?? "Command line device", token: token, environment: environment)]
        }
        payload = PushPayload(
            title: options.value(for: "title") ?? "",
            subtitle: options.value(for: "subtitle") ?? "",
            body: options.value(for: "body") ?? "",
            badge: options.value(for: "badge").flatMap(Int.init),
            sound: sound,
            attachment: attachment
        )
    }
}

private struct Options {
    private let values: [String: String]
    private let flags: Set<String>

    init(arguments: [String]) {
        var result: [String: String] = [:]
        var detectedFlags: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--"), index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                result[String(argument.dropFirst(2))] = arguments[index + 1]
                index += 2
            } else {
                if argument.hasPrefix("--") { detectedFlags.insert(String(argument.dropFirst(2))) }
                index += 1
            }
        }
        values = result
        flags = detectedFlags
    }

    func value(for key: String) -> String? { values[key] }
    func contains(_ flag: String) -> Bool { flags.contains(flag) }
}

/// A position in delivery order: when the record was delivered (in microseconds since
/// 2001-01-01), with the record ID as a tie-breaker. Unlike `rec_id` alone, this only
/// moves forward, because usernoted reuses `rec_id` values after the newest row is deleted.
private struct NotificationCursor: CustomStringConvertible {
    var deliveredMicroseconds: Int64
    var recordID: Int64

    init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let delivered = Int64(parts[0]), delivered >= 0,
              let recordID = Int64(parts[1]), recordID >= 0 else { return nil }
        deliveredMicroseconds = delivered
        self.recordID = recordID
    }

    var description: String { "\(deliveredMicroseconds):\(recordID)" }

    /// Keep in sync with `Scripts/forward-notification-center.zsh`.
    static let deliveredMicrosecondsSQL = "CAST(ROUND(delivered_date * 1000000) AS INTEGER)"
    var sqlRowValue: String { "(\(deliveredMicroseconds), \(recordID))" }
}

private struct NotificationEntry {
    var cursor: String
    var title: String
    var subtitle: String
    var body: String
}

private enum NotificationCenterReader {
    static func entries(limit: Int, afterCursor: NotificationCursor?, throughCursor: NotificationCursor?) throws -> [NotificationEntry] {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/group.com.apple.usernoted/db2/db")
        guard FileManager.default.fileExists(atPath: database.path) else { throw CLIError.notificationDatabaseUnavailable }
        let output = try runSQLite(
            database: database,
            limit: limit,
            afterCursor: afterCursor,
            throughCursor: throughCursor
        )
        // sqlite3 -json prints nothing at all when no rows match.
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = output.data(using: .utf8),
              let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let cursor = record["cursor"] as? String,
                  let hex = record["plist_hex"] as? String,
                  let plistData = plistData(fromHex: hex),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) else {
                return nil
            }
            return entry(from: plist, cursor: cursor)
        }
    }

    private static func runSQLite(
        database: URL,
        limit: Int,
        afterCursor: NotificationCursor?,
        throughCursor: NotificationCursor?
    ) throws -> String {
        let position = "(\(NotificationCursor.deliveredMicrosecondsSQL), rec_id)"
        var conditions = ["delivered_date IS NOT NULL"]
        if let afterCursor { conditions.append("\(position) > \(afterCursor.sqlRowValue)") }
        if let throughCursor { conditions.append("\(position) <= \(throughCursor.sqlRowValue)") }
        let predicate = conditions.joined(separator: " AND ")
        let ordering = afterCursor == nil ? "DESC" : "ASC"
        let query = """
            SELECT \(NotificationCursor.deliveredMicrosecondsSQL) || ':' || rec_id AS cursor, hex(data) AS plist_hex \
            FROM record WHERE \(predicate) \
            ORDER BY \(NotificationCursor.deliveredMicrosecondsSQL) \(ordering), rec_id \(ordering) LIMIT \(limit);
            """
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain stdout before waiting: a batch of large records can exceed the pipe
        // buffer, and sqlite3 would block forever writing to a pipe nobody reads.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError.notificationDatabaseUnavailable }
        return String(decoding: output, as: UTF8.self)
    }

    private static func entry(from record: [String: Any], cursor: String) -> NotificationEntry? {
        let flattened = flatten(record)
        let title = flattened["titl"] ?? flattened["title"] ?? flattened["header"] ?? "macOS notification"
        let subtitle = flattened["subt"] ?? flattened["subtitle"] ?? ""
        let body = flattened["body"] ?? flattened["message"] ?? flattened["text"] ?? ""
        return body.isEmpty && title == "macOS notification" ? nil : NotificationEntry(cursor: cursor, title: title, subtitle: subtitle, body: body)
    }

    private static func entry(from plist: Any, cursor: String) -> NotificationEntry? {
        guard let record = plist as? [String: Any] else { return nil }
        return entry(from: record, cursor: cursor)
    }

    private static func flatten(_ value: Any) -> [String: String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, item in
                if let text = item.value as? String { result[item.key.lowercased()] = text }
                for (key, text) in flatten(item.value) where result[key] == nil { result[key] = text }
            }
        }
        if let array = value as? [Any] { return array.reduce(into: [:]) { $0.merge(flatten($1)) { current, _ in current } } }
        return [:]
    }

    private static func plistData(fromHex hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return Data(bytes)
    }
}

private enum CLIError: LocalizedError {
    case usage, missingRequiredOption, conflictingRecipients, noSavedDevices, invalidAttachmentURL, invalidCursor(String), certificateNotFound(String), emptyPassword, notificationDatabaseUnavailable, noNotificationEntries
    var errorDescription: String? {
        switch self {
        case .usage: "Unknown or missing command."
        case .missingRequiredOption: "--certificate, --password, and --topic are required, along with --token or --broadcast."
        case .conflictingRecipients: "Use either --token or --broadcast, not both."
        case .noSavedDevices: "No saved devices were found. Add a device in DesktopPush for Mac first."
        case .invalidAttachmentURL: "Attachment URLs must use HTTPS."
        case .certificateNotFound(let path) where path.isEmpty:
            "--certificate is empty. If you used a shell variable such as \"$PUSH_P12\", make sure it is exported or set before this command runs."
        case .certificateNotFound(let path): "Certificate file not found: \(path)"
        case .emptyPassword:
            "--password is empty. If you used a shell variable such as \"$P12_PASSWORD\", make sure it is exported or set before this command runs."
        case .invalidCursor(let name): "--\(name) must be DELIVERED_MICROSECONDS:RECORD_ID (two non-negative integers)."
        case .notificationDatabaseUnavailable: "Notification Center history could not be read. Grant your terminal Full Disk Access and try again."
        case .noNotificationEntries: "No readable Notification Center entries were found."
        }
    }
}

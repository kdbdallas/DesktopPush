import SwiftUI
import DesktopPushSharediOS

struct NotificationHistoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var history: [ReceivedNotification] = NotificationHistory.load()
    @State private var deviceToken = UserDefaults.standard.string(forKey: "apns-device-token") ?? ""
    @State private var registrationError = UserDefaults.standard.string(forKey: "apns-registration-error")

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ReceiverSetupSection(token: deviceToken, registrationError: registrationError)
                    NotificationHistorySection(history: history)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("DesktopPush")
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                if !history.isEmpty {
                    Button("Clear", role: .destructive) { NotificationHistory.clear(); reload() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .receiverHistoryDidChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .receiverTokenDidChange)) { _ in
            deviceToken = UserDefaults.standard.string(forKey: "apns-device-token") ?? ""
            registrationError = UserDefaults.standard.string(forKey: "apns-registration-error")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
        .onAppear(perform: reload)
    }

    private func reload() { history = NotificationHistory.load() }
}

struct ReceiverSetupSection: View {
    let token: String
    let registrationError: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This iPhone")
                .font(.title2.weight(.semibold))
            if token.isEmpty {
                Label(registrationError ?? "Requesting an APNs device token…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(registrationError == nil ? Color.secondary : Color.red)
            } else {
                Text(token).font(.caption.monospaced()).textSelection(.enabled)
                Button { UIPasteboard.general.string = token; didCopy = true } label: {
                    Label(didCopy ? "Copied" : "Copy Device Token", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Paste this token into the Devices section of DesktopPush for Mac. Development certificates use Sandbox; distribution certificates use Production.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct NotificationHistorySection: View {
    let history: [ReceivedNotification]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent notifications")
                .font(.title2.weight(.semibold))
            Text("Showing the latest 10 notifications. Tap one for details.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if history.isEmpty {
                EmptyNotificationHistory()
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(history) { notification in
                        NavigationLink {
                            NotificationDetailView(notification: notification)
                        } label: {
                            NotificationHistoryRow(notification: notification)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.vertical, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyNotificationHistory: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing received yet")
                .font(.headline)
            Text("Send a push from DesktopPush on your Mac after copying this phone’s device token.")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
    }
}

struct NotificationHistoryRow: View {
    let notification: ReceivedNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(notification.title.isEmpty ? "Notification" : notification.title).font(.headline)
                Spacer()
                Text(notification.receivedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            if !notification.subtitle.isEmpty { Text(notification.subtitle).font(.subheadline) }
            if !notification.body.isEmpty { Text(notification.body).foregroundStyle(.secondary) }
            if let kind = notification.attachmentKind { Label(kind.rawValue.capitalized, systemImage: kind.symbol).font(.caption).foregroundStyle(.tint) }
        }
        .padding(.vertical, 3)
    }
}

struct NotificationDetailView: View {
    let notification: ReceivedNotification

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NotificationDetailHeader(
                    title: notification.title,
                    subtitle: notification.subtitle,
                    receivedAt: notification.receivedAt
                )
                NotificationDetailMessage(message: notification.body)
                NotificationDetailDelivery(notification: notification)
                NotificationDetailAttachment(
                    kind: notification.attachmentKind,
                    filename: notification.attachmentFileName
                )
                NotificationDetailPayload(userInfo: notification.userInfo)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationDetailHeader: View {
    let title: String
    let subtitle: String
    let receivedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.isEmpty ? "Notification" : title)
                .font(.title.weight(.bold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Label {
                Text(receivedAt, format: .dateTime.weekday().month().day().year().hour().minute().second())
            } icon: {
                Image(systemName: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct NotificationDetailMessage: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)
            Text(message.isEmpty ? "No body text" : message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NotificationDetailDelivery: View {
    let notification: ReceivedNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delivery details")
                .font(.headline)
            if let badge = notification.badge {
                NotificationDetailValue(label: "Badge", value: String(badge))
            }
            NotificationDetailValue(label: "Sound", value: notification.soundRequested ? "Requested" : "None")
            if !notification.categoryIdentifier.isEmpty {
                NotificationDetailValue(label: "Category", value: notification.categoryIdentifier)
            }
            if !notification.threadIdentifier.isEmpty {
                NotificationDetailValue(label: "Thread", value: notification.threadIdentifier)
            }
        }
    }
}

struct NotificationDetailAttachment: View {
    let kind: AttachmentKind?
    let filename: String?

    var body: some View {
        if let kind {
            VStack(alignment: .leading, spacing: 8) {
                Text("Attachment")
                    .font(.headline)
                Label(kind.rawValue.capitalized, systemImage: kind.symbol)
                if let filename, !filename.isEmpty {
                    NotificationDetailValue(label: "File", value: filename)
                }
            }
        }
    }
}

struct NotificationDetailPayload: View {
    let userInfo: [String: String]

    var body: some View {
        if !userInfo.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom payload")
                    .font(.headline)
                ForEach(userInfo.keys.sorted(), id: \.self) { key in
                    NotificationDetailValue(label: key, value: userInfo[key] ?? "")
                }
            }
        }
    }
}

struct NotificationDetailValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

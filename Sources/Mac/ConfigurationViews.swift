import SwiftUI
import UniformTypeIdentifiers
import DesktopPushSharedMac

struct DevicesView: View {
    @ObservedObject var model: SenderModel
    @State private var name = ""
    @State private var token = ""
    @State private var environment: APNSEnvironment = .sandbox
    @State private var selectedDeviceIDs: Set<UUID> = []

    var body: some View {
        List(selection: $selectedDeviceIDs) {
            Section("Registered devices") {
                ForEach(model.devices) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                        Text(device.token).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(device.environment == .sandbox ? "Sandbox (development token)" : "Production (distribution token)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(device.id)
                }
                .onDelete(perform: model.removeDevices)
            }
            Section("Add device") {
                TextField("Device name", text: $name)
                TextField("APNs device token", text: $token, axis: .vertical).font(.body.monospaced()).lineLimit(2...4)
                Picker("Environment", selection: $environment) {
                    ForEach(APNSEnvironment.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Add Device") {
                    model.addDevice(name: name, token: token, environment: environment)
                    if model.errorMessage == nil { name = ""; token = "" }
                }
            }
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelectedDevices) {
                    Label("Remove Device", systemImage: "trash")
                }
                .disabled(selectedDeviceIDs.isEmpty)
                .help("Remove the selected device token")
            }
        }
    }

    private func deleteSelectedDevices() {
        let offsets = IndexSet(model.devices.indices.filter { selectedDeviceIDs.contains(model.devices[$0].id) })
        model.removeDevices(at: offsets)
        selectedDeviceIDs.removeAll()
    }
}

struct CertificatesView: View {
    @ObservedObject var model: SenderModel
    @State private var showingImporter = false
    @State private var name = ""
    @State private var topic = "com.port21.desktoppush.iOS"
    @State private var password = ""
    @State private var environment: APNSEnvironment = .sandbox
    @State private var selectedCertificateIDs: Set<UUID> = []

    var body: some View {
        List(selection: $selectedCertificateIDs) {
            Section("Push certificates") {
                if model.certificates.isEmpty {
                    ContentUnavailableView("No certificate", systemImage: "checkmark.seal", description: Text("Import the .p12 APNs certificate used for your iOS app."))
                }
                ForEach(model.certificates) { certificate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(certificate.name)
                        Text("\(certificate.topic) · \(certificate.environment.rawValue)").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(certificate.id)
                }
                .onDelete(perform: model.removeCertificates)
            }
            Section("Import .p12") {
                TextField("Certificate name", text: $name)
                TextField("APNs topic (iOS bundle identifier)", text: $topic)
                SecureField("Certificate password", text: $password)
                Picker("Environment", selection: $environment) { ForEach(APNSEnvironment.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Button("Choose .p12 File…") { showingImporter = true }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("The .p12 and password are stored in your login Keychain, not in the project or a plain-text settings file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Certificates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelectedCertificates) {
                    Label("Remove Certificate", systemImage: "trash")
                }
                .disabled(selectedCertificateIDs.isEmpty)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data]) { result in
            guard case let .success(url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            model.importCertificate(from: url, name: name, topic: topic, environment: environment, password: password)
            if model.errorMessage == nil { name = ""; password = "" }
        }
    }

    private func deleteSelectedCertificates() {
        let offsets = IndexSet(model.certificates.indices.filter { selectedCertificateIDs.contains(model.certificates[$0].id) })
        model.removeCertificates(at: offsets)
        selectedCertificateIDs.removeAll()
    }
}

struct ScheduledPushesView: View {
    @ObservedObject var model: SenderModel

    var body: some View {
        List {
            if model.schedules.isEmpty {
                ContentUnavailableView(
                    "No scheduled pushes",
                    systemImage: "calendar.badge.clock",
                    description: Text("Choose a date and time in the composer, then select Schedule Push.")
                )
            }
            ForEach(model.schedules) { schedule in
                ScheduledPushRow(
                    schedule: schedule,
                    deviceNames: model.devices
                        .filter { schedule.deviceIDs.contains($0.id) }
                        .map(\.name),
                    certificateName: model.certificates.first(where: { $0.id == schedule.certificateID })?.name
                )
            }
            .onDelete(perform: model.deleteSchedules)
        }
        .navigationTitle("Scheduled Pushes")
    }
}

struct ScheduledPushRow: View {
    let schedule: ScheduledPush
    let deviceNames: [String]
    let certificateName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScheduledPushHeader(title: schedule.payload.title, fireDate: schedule.fireDate, deliveredAt: schedule.deliveredAt)
            ScheduledPushContent(payload: schedule.payload)
            ScheduledPushRecipients(deviceNames: deviceNames, certificateName: certificateName)
            if let error = schedule.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 5)
    }
}

struct ScheduledPushHeader: View {
    let title: String
    let fireDate: Date
    let deliveredAt: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.isEmpty ? "Untitled push" : title)
                .font(.headline)
            Spacer()
            if let deliveredAt {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("Sent \(deliveredAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Label("Scheduled", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        Text(fireDate, format: .dateTime.weekday().month().day().year().hour().minute())
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

struct ScheduledPushContent: View {
    let payload: PushPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !payload.subtitle.isEmpty {
                Text(payload.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !payload.body.isEmpty {
                Text(payload.body)
                    .lineLimit(3)
            }
            HStack(spacing: 10) {
                if let badge = payload.badge {
                    Label("Badge \(badge)", systemImage: "app.badge")
                }
                if let sound = payload.sound, !sound.isEmpty {
                    Label(sound == "default" ? "Default sound" : sound, systemImage: "speaker.wave.2")
                }
                if let attachment = payload.attachment {
                    Label(attachment.kind.rawValue.capitalized, systemImage: attachment.kind.symbol)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct ScheduledPushRecipients: View {
    let deviceNames: [String]
    let certificateName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(deviceNames.isEmpty ? "No saved recipients" : deviceNames.formatted(), systemImage: "iphone")
            if let certificateName {
                Label(certificateName, systemImage: "checkmark.seal")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct CommandLineView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ContentUnavailableView("Scriptable delivery", systemImage: "terminal", description: Text("The desktoppush executable sends the same APNs payloads as the Mac app using a certificate and device token supplied by your script."))
                CommandExample(title: "Send a text push", command: "desktoppush send --certificate Push.p12 --password secret --topic com.example.Receiver --token APNS_TOKEN --title \"Build complete\" --body \"All tests passed\"")
                CommandExample(title: "Include an attachment", command: "desktoppush send --certificate Push.p12 --password secret --topic com.example.Receiver --token APNS_TOKEN --attachment https://example.com/image.gif --attachment-kind gif")
                CommandExample(title: "Read recent Notification Center entries", command: "desktoppush notification-center --certificate Push.p12 --password secret --topic com.example.Receiver --token APNS_TOKEN")
                Text("Notification Center history is protected by macOS. The final command performs a best-effort read and tells you when Full Disk Access is required; use the JSON import option when macOS blocks access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 700, alignment: .leading)
        }
        .navigationTitle("Command Line")
    }
}

struct CommandExample: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(command).font(.body.monospaced()).textSelection(.enabled)
                .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

import SwiftUI
import DesktopPushSharedMac

struct MacRootView: View {
    @ObservedObject var model: SenderModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("SEND") {
                    Label("Compose", systemImage: "paperplane")
                        .tag(SenderModel.Section.composer)
                    Label("Scheduled", systemImage: "calendar")
                        .tag(SenderModel.Section.scheduled)
                }
                Section("SETUP") {
                    Label("Devices", systemImage: "iphone")
                        .tag(SenderModel.Section.devices)
                    Label("Certificates", systemImage: "checkmark.seal")
                        .tag(SenderModel.Section.certificates)
                    Label("Command Line", systemImage: "terminal")
                        .tag(SenderModel.Section.commandLine)
                }
            }
            .navigationTitle("DesktopPush")
            .frame(minWidth: 190)
        } detail: {
            switch model.selection ?? .composer {
            case .composer: ComposerView(model: model)
            case .devices: DevicesView(model: model)
            case .certificates: CertificatesView(model: model)
            case .scheduled: ScheduledPushesView(model: model)
            case .commandLine: CommandLineView()
            }
        }
        .alert("DesktopPush", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Delivery", isPresented: Binding(get: { model.confirmationMessage != nil }, set: { if !$0 { model.confirmationMessage = nil } })) {
            Button("OK", role: .cancel) { model.confirmationMessage = nil }
        } message: { Text(model.confirmationMessage ?? "") }
    }
}

struct ComposerView: View {
    @ObservedObject var model: SenderModel

    var body: some View {
        Form {
            NotificationContentSection(model: model)
            DeliverySection(model: model)
            SchedulingSection(model: model)
            RecentDeliverySection(deliveries: model.deliveries, devices: model.devices)
        }
        .formStyle(.grouped)
        .navigationTitle("New Push")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.sendNow() } } label: {
                    Label(model.isSending ? "Sending" : "Send Now", systemImage: "paperplane.fill")
                }
                .disabled(!model.canSend)
            }
        }
    }
}

struct NotificationContentSection: View {
    @ObservedObject var model: SenderModel

    var body: some View {
        Section("Notification content") {
            TextField("Title", text: $model.payload.title)
            TextField("Subtitle", text: $model.payload.subtitle)
            TextField("Body", text: $model.payload.body, axis: .vertical)
                .lineLimit(3...6)
            Picker("Sound", selection: $model.soundOption) {
                Text("None").tag(NotificationSoundOption.none)
                Text("Default").tag(NotificationSoundOption.systemDefault)
                Text("Custom sound…").tag(NotificationSoundOption.custom)
            }
            .onChange(of: model.soundOption) { _, _ in model.updateSound() }
            if model.soundOption == .custom {
                TextField("Custom sound filename", text: $model.customSoundFilename)
                    .onChange(of: model.customSoundFilename) { _, _ in model.updateSound() }
                Text("Include the exact filename and extension, such as custom.aiff. The sound file must be bundled with the iOS app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Stepper(value: Binding(get: { model.payload.badge ?? 0 }, set: { model.payload.badge = $0 == 0 ? nil : $0 }), in: 0...999) {
                Text(model.payload.badge == nil ? "Badge: unchanged" : "Badge: \(model.payload.badge ?? 0)")
            }
            Picker("Attachment", selection: $model.attachmentKind) {
                ForEach(AttachmentKind.allCases) { kind in Label(kind.rawValue.capitalized, systemImage: kind.symbol).tag(kind) }
            }
            TextField("HTTPS attachment URL", text: $model.attachmentURLText)
                .onChange(of: model.attachmentURLText) { _, _ in model.updateAttachment() }
                .onChange(of: model.attachmentKind) { _, _ in model.updateAttachment() }
            Text("Images, GIFs, audio, and video are downloaded by the iOS notification-service extension.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DeliverySection: View {
    @ObservedObject var model: SenderModel

    var body: some View {
        Section("Send to") {
            Picker("Certificate", selection: $model.selectedCertificateID) {
                Text("Choose a certificate").tag(UUID?.none)
                ForEach(model.certificates) { certificate in
                    Text("\(certificate.name) · \(certificate.environment.rawValue)").tag(UUID?.some(certificate.id))
                }
            }
            if model.devices.isEmpty {
                ContentUnavailableView("No devices", systemImage: "iphone.slash", description: Text("Add an iOS device token in Devices."))
            } else {
                Toggle("Broadcast to all saved devices", isOn: $model.sendToAllDevices)
                    .onChange(of: model.sendToAllDevices) { _, enabled in model.setBroadcast(enabled) }
                Text("All device switches start on. Turn off a device to send only to the remaining selected devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.devices) { device in
                    Toggle(isOn: Binding(get: { model.sendToAllDevices || model.selectedDeviceIDs.contains(device.id) }, set: { selected in
                        model.setDeviceSelected(selected, id: device.id)
                    })) {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.environment.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct SchedulingSection: View {
    @ObservedObject var model: SenderModel

    var body: some View {
        Section("Schedule") {
            DatePicker("Send at", selection: $model.scheduledDate, in: Date.now...)
            Button("Schedule Push") { model.scheduleCurrentPush() }
                .disabled(!model.canSend)
            Text("Scheduled pushes are sent while DesktopPush is running. Use the CLI with launchd or cron for unattended delivery.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct RecentDeliverySection: View {
    let deliveries: [DeliveryResult]
    let devices: [DeviceRecord]

    var body: some View {
        Section("Recent delivery") {
            if deliveries.isEmpty { Text("No delivery attempts yet.").foregroundStyle(.secondary) }
            ForEach(deliveries.prefix(8)) { result in
                HStack {
                    Image(systemName: result.status == .delivered ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.status == .delivered ? .green : .red)
                    VStack(alignment: .leading) {
                        Text(devices.first(where: { $0.id == result.deviceID })?.name ?? "Removed device")
                        Text(result.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(result.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

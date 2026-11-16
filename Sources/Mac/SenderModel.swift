import Foundation
import Combine
import SwiftUI
import UserNotifications
import DesktopPushSharedMac

enum NotificationSoundOption: String, CaseIterable, Identifiable {
    case none
    case systemDefault
    case custom

    var id: String { rawValue }
}

@MainActor
final class SenderModel: ObservableObject {
    enum Section: Hashable { case composer, devices, certificates, scheduled, commandLine }

    @Published var selection: Section? = .composer
    @Published var payload = PushPayload()
    @Published var soundOption: NotificationSoundOption = .systemDefault
    @Published var customSoundFilename = "custom.aiff"
    @Published var attachmentURLText = ""
    @Published var attachmentKind: AttachmentKind = .image
    @Published var devices: [DeviceRecord] = LocalStore.load([DeviceRecord].self, from: "devices.json", fallback: [])
    @Published var certificates: [CertificateProfile] = LocalStore.load([CertificateProfile].self, from: "certificates.json", fallback: [])
    @Published var schedules: [ScheduledPush] = LocalStore.load([ScheduledPush].self, from: "schedules.json", fallback: [])
    @Published var deliveries: [DeliveryResult] = LocalStore.load([DeliveryResult].self, from: "deliveries.json", fallback: [])
    @Published var selectedDeviceIDs: Set<UUID> = []
    @Published var sendToAllDevices = true
    @Published var selectedCertificateID: UUID?
    @Published var scheduledDate = Date.now.addingTimeInterval(300)
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?
    private var timer: Timer?

    init() {
        selectedDeviceIDs = Set(devices.map(\.id))
    }

    private var allDeviceIDs: Set<UUID> { Set(devices.map(\.id)) }
    private var recipientDeviceIDs: Set<UUID> { sendToAllDevices ? allDeviceIDs : selectedDeviceIDs.intersection(allDeviceIDs) }

    var canSend: Bool { !recipientDeviceIDs.isEmpty && selectedCertificateID != nil && !isSending }
    var selectedCertificate: CertificateProfile? { certificates.first { $0.id == selectedCertificateID } }

    func start() async {
        if selectedCertificateID == nil { selectedCertificateID = certificates.first?.id }
        await requestNotificationPermission()
        serviceDueSchedules()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.serviceDueSchedules() }
        }
    }

    func updateAttachment() {
        let trimmed = attachmentURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.attachment = URL(string: trimmed).flatMap { PushAttachment(kind: attachmentKind, remoteURL: $0) }
    }

    func updateSound() {
        switch soundOption {
        case .none:
            payload.sound = nil
        case .systemDefault:
            payload.sound = "default"
        case .custom:
            let filename = customSoundFilename.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.sound = filename.isEmpty ? nil : filename
        }
    }

    func addDevice(name: String, token: String, environment: APNSEnvironment) {
        let normalized = token.normalizedDeviceToken
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, normalized.count == 64 else {
            errorMessage = "Enter a name and a 64-character APNs device token."
            return
        }
        let device = DeviceRecord(name: name, token: normalized, environment: environment)
        devices.append(device)
        selectedDeviceIDs.insert(device.id)
        persist()
    }

    func removeDevices(at offsets: IndexSet) {
        let ids = offsets.map { devices[$0].id }
        devices.remove(atOffsets: offsets)
        selectedDeviceIDs.subtract(ids)
        if devices.isEmpty || selectedDeviceIDs == allDeviceIDs { sendToAllDevices = true }
        persist()
    }

    func setBroadcast(_ enabled: Bool) {
        sendToAllDevices = enabled
        if enabled { selectedDeviceIDs = allDeviceIDs }
    }

    func setDeviceSelected(_ selected: Bool, id: UUID) {
        if selected {
            selectedDeviceIDs.insert(id)
        } else {
            selectedDeviceIDs.remove(id)
        }
        sendToAllDevices = !devices.isEmpty && selectedDeviceIDs == allDeviceIDs
    }

    func importCertificate(from url: URL, name: String, topic: String, environment: APNSEnvironment, password: String) {
        guard !name.isEmpty, !topic.isEmpty else {
            errorMessage = "Give the certificate a name and enter the app’s bundle identifier as the topic."
            return
        }
        do {
            let profile = CertificateProfile(name: name, topic: topic, environment: environment)
            let certificateData = try Data(contentsOf: url)
            try CertificateVault.store(data: certificateData, password: password, for: profile.id)
            certificates.append(profile)
            selectedCertificateID = profile.id
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeCertificates(at offsets: IndexSet) {
        let removed = offsets.map { certificates[$0] }
        for certificate in removed { try? CertificateVault.remove(certificate.id) }
        certificates.remove(atOffsets: offsets)
        if !certificates.contains(where: { $0.id == selectedCertificateID }) { selectedCertificateID = certificates.first?.id }
        persist()
    }

    func sendNow() async {
        guard let certificate = selectedCertificate else { return }
        isSending = true
        defer { isSending = false }
        let targets = devices.filter { recipientDeviceIDs.contains($0.id) }
        let currentPayload = payload
        let topic = certificate.topic
        do {
            let material = try CertificateVault.load(certificate.id)
            let results = await withTaskGroup(of: DeliveryResult.self) { group in
                for device in targets {
                    let deviceID = device.id
                    group.addTask {
                        do {
                            try await APNSClient.send(payload: currentPayload, to: device, topic: topic, certificateData: material.data, certificatePassword: material.password)
                            return DeliveryResult(deviceID: deviceID, status: .delivered, detail: "Accepted by APNs")
                        } catch {
                            return DeliveryResult(deviceID: deviceID, status: .failed, detail: error.localizedDescription)
                        }
                    }
                }
                var results: [DeliveryResult] = []
                while let result = await group.next() { results.append(result) }
                return results
            }
            deliveries.insert(contentsOf: results, at: 0)
            persist()
            let successCount = results.filter { $0.status == .delivered }.count
            if successCount == results.count, !results.isEmpty {
                resetComposer()
            }
            confirmationMessage = "APNs accepted \(successCount) of \(results.count) delivery request\(results.count == 1 ? "" : "s")."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleCurrentPush() {
        guard let certificate = selectedCertificate, !recipientDeviceIDs.isEmpty else { return }
        let fireDate = scheduledDate
        schedules.append(ScheduledPush(payload: payload, deviceIDs: Array(recipientDeviceIDs), certificateID: certificate.id, fireDate: fireDate))
        schedules.sort { $0.payload.createdAt > $1.payload.createdAt }
        persist()
        resetComposer()
        selection = .scheduled
        confirmationMessage = "Push scheduled for \(fireDate.formatted(date: .abbreviated, time: .shortened)). Keep DesktopPush running to deliver it."
    }

    func deleteSchedules(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
        persist()
    }

    private func serviceDueSchedules() {
        let dueIDs = schedules.filter { $0.deliveredAt == nil && $0.fireDate <= .now }.map(\.id)
        for id in dueIDs { Task { await deliverSchedule(id) } }
    }

    private func deliverSchedule(_ id: UUID) async {
        guard let index = schedules.firstIndex(where: { $0.id == id }), let certificate = certificates.first(where: { $0.id == schedules[index].certificateID }) else { return }
        let schedule = schedules[index]
        do {
            let material = try CertificateVault.load(certificate.id)
            for device in devices where schedule.deviceIDs.contains(device.id) {
                do {
                    try await APNSClient.send(payload: schedule.payload, to: device, topic: certificate.topic, certificateData: material.data, certificatePassword: material.password)
                    deliveries.insert(DeliveryResult(deviceID: device.id, status: .delivered, detail: "Scheduled push accepted by APNs"), at: 0)
                } catch {
                    schedules[index].lastError = error.localizedDescription
                    deliveries.insert(DeliveryResult(deviceID: device.id, status: .failed, detail: error.localizedDescription), at: 0)
                }
            }
            schedules[index].deliveredAt = .now
        } catch { schedules[index].lastError = error.localizedDescription }
        persist()
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])
    }

    private func persist() {
        try? LocalStore.save(devices, to: "devices.json")
        try? LocalStore.save(certificates, to: "certificates.json")
        try? LocalStore.save(schedules, to: "schedules.json")
        try? LocalStore.save(Array(deliveries.prefix(100)), to: "deliveries.json")
    }

    private func resetComposer() {
        payload = PushPayload()
        soundOption = .systemDefault
        customSoundFilename = "custom.aiff"
        attachmentURLText = ""
        attachmentKind = .image
        selectedDeviceIDs = allDeviceIDs
        sendToAllDevices = true
        scheduledDate = .now.addingTimeInterval(300)
    }
}

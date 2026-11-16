import Foundation
import Security

public enum APNSError: LocalizedError, Sendable {
    case cannotReadCertificate(status: OSStatus)
    case invalidCertificatePassword
    case invalidResponse
    case rejected(status: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotReadCertificate(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Security error \(status)"
            return "The .p12 could not provide a usable certificate identity: \(detail). Export the Apple Push Services certificate again, including its private key."
        case .invalidCertificatePassword: return "The certificate password was rejected."
        case .invalidResponse: return "APNs returned an invalid response."
        case let .rejected(status, reason): return "APNs rejected the request (\(status)): \(reason)"
        }
    }
}

public enum APNSClient {
    public static func send(
        payload: PushPayload,
        to device: DeviceRecord,
        topic: String,
        certificateData: Data,
        certificatePassword: String
    ) async throws {
        let importedIdentity = try importIdentity(certificateData, password: certificatePassword)
        let delegate = CertificateSessionDelegate(importedIdentity: importedIdentity)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        guard let body = payload.requestBody else { throw APNSError.invalidResponse }
        let url = URL(string: "https://\(device.environment.host)/3/device/\(device.token)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APNSError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String ?? "Unknown error"
            throw APNSError.rejected(status: http.statusCode, reason: reason)
        }
    }

    private static func importIdentity(_ data: Data, password: String) throws -> ImportedIdentity {
        var imported: CFArray?
        #if os(macOS)
        let temporaryKeychain = try TemporaryIdentityKeychain()
        let options = [
            kSecImportExportPassphrase as String: password,
            kSecImportExportKeychain as String: temporaryKeychain.keychain
        ] as CFDictionary
        #else
        let temporaryKeychain: TemporaryIdentityKeychain? = nil
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        #endif
        let result = SecPKCS12Import(data as CFData, options, &imported)
        guard result == errSecSuccess else {
            throw result == errSecAuthFailed ? APNSError.invalidCertificatePassword : APNSError.cannotReadCertificate(status: result)
        }
        guard let item = (imported as? [[String: Any]])?.first,
              let value = item[kSecImportItemIdentity as String] else {
            throw APNSError.cannotReadCertificate(status: errSecItemNotFound)
        }
        return ImportedIdentity(identity: value as! SecIdentity, temporaryKeychain: temporaryKeychain)
    }
}

private final class CertificateSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let importedIdentity: ImportedIdentity

    init(importedIdentity: ImportedIdentity) { self.importedIdentity = importedIdentity }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            completionHandler(.useCredential, URLCredential(identity: importedIdentity.identity, certificates: nil, persistence: .forSession))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

private final class ImportedIdentity: @unchecked Sendable {
    let identity: SecIdentity
    private let temporaryKeychain: TemporaryIdentityKeychain?

    init(identity: SecIdentity, temporaryKeychain: TemporaryIdentityKeychain?) {
        self.identity = identity
        self.temporaryKeychain = temporaryKeychain
    }
}

#if os(macOS)
private final class TemporaryIdentityKeychain: @unchecked Sendable {
    let keychain: SecKeychain

    init() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "DesktopPush", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let location = directory.appending(path: "apns-\(UUID().uuidString).keychain-db")
        let password = Data(UUID().uuidString.utf8)
        var createdKeychain: SecKeychain?
        let result = location.path.withCString { path in
            password.withUnsafeBytes { bytes in
                SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &createdKeychain)
            }
        }
        guard result == errSecSuccess, let createdKeychain else { throw APNSError.cannotReadCertificate(status: result) }
        keychain = createdKeychain
    }

    deinit { SecKeychainDelete(keychain) }
}
#else
private typealias TemporaryIdentityKeychain = Never
#endif

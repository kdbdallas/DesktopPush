import Foundation
import Security

enum CertificateVault {
    struct Material { let data: Data; let password: String }
    private static let service = "com.dallas.desktoppush.certificate"

    static func store(data: Data, password: String, for id: UUID) throws {
        try remove(id)
        try add(data, account: "\(id.uuidString).p12")
        try add(Data(password.utf8), account: "\(id.uuidString).password")
    }

    static func load(_ id: UUID) throws -> Material {
        Material(data: try read(account: "\(id.uuidString).p12"), password: String(decoding: try read(account: "\(id.uuidString).password"), as: UTF8.self))
    }

    static func remove(_ id: UUID) throws {
        for suffix in ["p12", "password"] {
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "\(id.uuidString).\(suffix)"] as CFDictionary)
        }
    }

    private static func add(_ data: Data, account: String) throws {
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked] as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private static func read(account: String) throws -> Data {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)." }
}

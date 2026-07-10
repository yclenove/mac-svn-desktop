import Foundation
import Security

public protocol AIAPIKeyStoring: Sendable {
    func saveAPIKey(_ apiKey: String, for providerID: UUID) async throws -> String
    func apiKey(ref: String) async throws -> String?
    func deleteAPIKey(ref: String) async throws
}

public enum AIKeychainError: Error, Equatable, Sendable {
    case invalidReference(String)
    case unhandledStatus(Int32)
    case invalidPasswordData
}

public protocol KeychainAccessing: Sendable {
    func saveGenericPassword(service: String, account: String, password: String) async throws
    func genericPassword(service: String, account: String) async throws -> String?
    func deleteGenericPassword(service: String, account: String) async throws
}

public struct SystemKeychainAccessor: KeychainAccessing, Sendable {
    public init() {}

    public func saveGenericPassword(service: String, account: String, password: String) async throws {
        let passwordData = Data(password.utf8)
        let addQuery = baseQuery(service: service, account: account)
            .merging([
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]) { _, new in new }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(service: service, account: account) as CFDictionary,
                [kSecValueData as String: passwordData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw AIKeychainError.unhandledStatus(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw AIKeychainError.unhandledStatus(status)
        }
    }

    public func genericPassword(service: String, account: String) async throws -> String? {
        let query = baseQuery(service: service, account: account)
            .merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]) { _, new in new }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw AIKeychainError.unhandledStatus(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw AIKeychainError.invalidPasswordData
        }
        return password
    }

    public func deleteGenericPassword(service: String, account: String) async throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIKeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public actor AIKeychainStore: AIAPIKeyStoring {
    private static let refPrefix = ProductBranding.keychainRefPrefix
    private let service = ProductBranding.keychainService
    private let keychain: any KeychainAccessing

    public init(keychain: any KeychainAccessing = SystemKeychainAccessor()) {
        self.keychain = keychain
    }

    public func saveAPIKey(_ apiKey: String, for providerID: UUID) async throws -> String {
        let account = providerID.uuidString.lowercased()
        try await keychain.saveGenericPassword(service: service, account: account, password: apiKey)
        return Self.refPrefix + account
    }

    public func apiKey(ref: String) async throws -> String? {
        let account = try account(from: ref)
        return try await keychain.genericPassword(service: service, account: account)
    }

    public func deleteAPIKey(ref: String) async throws {
        let account = try account(from: ref)
        try await keychain.deleteGenericPassword(service: service, account: account)
    }

    private func account(from ref: String) throws -> String {
        guard ref.hasPrefix(Self.refPrefix) else {
            throw AIKeychainError.invalidReference(ref)
        }

        let account = String(ref.dropFirst(Self.refPrefix.count))
        guard UUID(uuidString: account) != nil else {
            throw AIKeychainError.invalidReference(ref)
        }
        return account.lowercased()
    }
}

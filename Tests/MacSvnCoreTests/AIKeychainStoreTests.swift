import Foundation
import XCTest
@testable import MacSvnCore

final class AIKeychainStoreTests: XCTestCase {
    func testSaveReadAndDeleteAPIKeyUsesStableReferenceWithoutLeakingSecret() async throws {
        let providerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let keychain = FakeKeychainAccessor()
        let store = AIKeychainStore(keychain: keychain)

        let ref = try await store.saveAPIKey("sk-secret-value", for: providerID)
        let loaded = try await store.apiKey(ref: ref)
        try await store.deleteAPIKey(ref: ref)
        let deleted = try await store.apiKey(ref: ref)

        XCTAssertEqual(ref, "svnstudio.ai-provider.10000000-0000-0000-0000-000000000001")
        XCTAssertFalse(ref.contains("sk-secret-value"))
        XCTAssertEqual(loaded, "sk-secret-value")
        XCTAssertNil(deleted)
        let savedAccounts = await keychain.savedAccounts
        let deletedAccounts = await keychain.deletedAccounts
        XCTAssertEqual(savedAccounts, ["10000000-0000-0000-0000-000000000001"])
        XCTAssertEqual(deletedAccounts, ["10000000-0000-0000-0000-000000000001"])
    }

    func testRejectsInvalidKeyReference() async {
        let store = AIKeychainStore(keychain: FakeKeychainAccessor())

        do {
            _ = try await store.apiKey(ref: "plain-secret")
            XCTFail("Expected invalid ref")
        } catch let error as AIKeychainError {
            XCTAssertEqual(error, .invalidReference("plain-secret"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor FakeKeychainAccessor: KeychainAccessing {
    private var storage: [String: String] = [:]
    private(set) var savedAccounts: [String] = []
    private(set) var deletedAccounts: [String] = []

    func saveGenericPassword(service: String, account: String, password: String) async throws {
        storage["\(service):\(account)"] = password
        savedAccounts.append(account)
    }

    func genericPassword(service: String, account: String) async throws -> String? {
        storage["\(service):\(account)"]
    }

    func deleteGenericPassword(service: String, account: String) async throws {
        storage.removeValue(forKey: "\(service):\(account)")
        deletedAccounts.append(account)
    }
}

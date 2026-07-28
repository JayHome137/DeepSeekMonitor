import Foundation
import XCTest
@testable import DeepSeekMonitor

final class APIKeyStoreTests: XCTestCase {
    func testExistingKeychainValueWinsAndRemovesLegacyValue() {
        withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage(storedAPIKey: "keychain-key")
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            let result = store.loadAndMigrate()

            XCTAssertEqual(result.apiKey, "keychain-key")
            XCTAssertNil(result.migrationWarning)
            XCTAssertNil(defaults.string(forKey: APIKeyStore.legacyDefaultsKey))
        }
    }

    func testLegacyValueMigratesOnlyAfterKeychainReadback() {
        withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage()
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            let result = store.loadAndMigrate()

            XCTAssertEqual(result.apiKey, "legacy-key")
            XCTAssertEqual(secureStorage.storedAPIKey, "legacy-key")
            XCTAssertNil(result.migrationWarning)
            XCTAssertNil(defaults.string(forKey: APIKeyStore.legacyDefaultsKey))
        }
    }

    func testMigrationWriteFailureKeepsLegacyValueAvailable() {
        withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage()
            secureStorage.writeError = MockStorageError.failure
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            let result = store.loadAndMigrate()

            XCTAssertEqual(result.apiKey, "legacy-key")
            XCTAssertNotNil(result.migrationWarning)
            XCTAssertEqual(defaults.string(forKey: APIKeyStore.legacyDefaultsKey), "legacy-key")
        }
    }

    func testMigrationReadFailureKeepsLegacyValueAvailable() {
        withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage()
            secureStorage.readError = MockStorageError.failure
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            let result = store.loadAndMigrate()

            XCTAssertEqual(result.apiKey, "legacy-key")
            XCTAssertNotNil(result.migrationWarning)
            XCTAssertEqual(defaults.string(forKey: APIKeyStore.legacyDefaultsKey), "legacy-key")
        }
    }

    func testSaveVerificationFailureDoesNotRemoveLegacyValue() throws {
        try withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage()
            secureStorage.persistWrites = false
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            XCTAssertThrowsError(try store.save("replacement-key"))
            XCTAssertEqual(defaults.string(forKey: APIKeyStore.legacyDefaultsKey), "legacy-key")
        }
    }

    func testDeleteFailureKeepsLegacyValue() throws {
        try withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage(storedAPIKey: "keychain-key")
            secureStorage.deleteError = MockStorageError.failure
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            XCTAssertThrowsError(try store.delete())
            XCTAssertEqual(secureStorage.storedAPIKey, "keychain-key")
            XCTAssertEqual(defaults.string(forKey: APIKeyStore.legacyDefaultsKey), "legacy-key")
        }
    }

    func testDeleteSuccessClearsKeychainAndLegacyValues() throws {
        try withDefaults { defaults in
            defaults.set("legacy-key", forKey: APIKeyStore.legacyDefaultsKey)
            let secureStorage = MockAPIKeySecureStorage(storedAPIKey: "keychain-key")
            let store = APIKeyStore(secureStorage: secureStorage, defaults: defaults)

            try store.delete()

            XCTAssertNil(secureStorage.storedAPIKey)
            XCTAssertNil(defaults.string(forKey: APIKeyStore.legacyDefaultsKey))
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "APIKeyStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}

private enum MockStorageError: Error {
    case failure
}

private final class MockAPIKeySecureStorage: APIKeySecureStorage {
    var storedAPIKey: String?
    var readError: Error?
    var writeError: Error?
    var deleteError: Error?
    var persistWrites = true

    init(storedAPIKey: String? = nil) {
        self.storedAPIKey = storedAPIKey
    }

    func read() throws -> String? {
        if let readError {
            throw readError
        }
        return storedAPIKey
    }

    func write(_ apiKey: String) throws {
        if let writeError {
            throw writeError
        }
        if persistWrites {
            storedAPIKey = apiKey
        }
    }

    func delete() throws {
        if let deleteError {
            throw deleteError
        }
        storedAPIKey = nil
    }
}

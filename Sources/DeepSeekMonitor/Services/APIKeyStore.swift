import Foundation
import Security

enum APIKeyStorageOperation: String {
    case read = "读取"
    case write = "写入"
    case delete = "删除"
}

enum APIKeyStorageError: LocalizedError {
    case emptyAPIKey
    case invalidStoredData
    case verificationFailed
    case keychain(APIKeyStorageOperation, OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "API Key 不能为空"
        case .invalidStoredData:
            return "macOS 钥匙串中的 API Key 数据无效"
        case .verificationFailed:
            return "API Key 写入 macOS 钥匙串后校验失败"
        case .keychain(let operation, let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "macOS 钥匙串\(operation.rawValue)失败（\(status)：\(detail)）"
        }
    }
}

protocol APIKeySecureStorage {
    func read() throws -> String?
    func write(_ apiKey: String) throws
    func delete() throws
}

struct KeychainAPIKeySecureStorage: APIKeySecureStorage {
    private let service = "com.deepseek.monitor"
    private let account = "deepseek-api-key"

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStorageError.keychain(.read, status)
        }
        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8),
              apiKey.isEmpty == false else {
            throw APIKeyStorageError.invalidStoredData
        }
        return apiKey
    }

    func write(_ apiKey: String) throws {
        guard apiKey.isEmpty == false else {
            throw APIKeyStorageError.emptyAPIKey
        }

        let valueData = Data(apiKey.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData: valueData] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStorageError.keychain(.write, updateStatus)
        }

        var insertQuery = baseQuery
        insertQuery[kSecValueData] = valueData
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw APIKeyStorageError.keychain(.write, insertStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStorageError.keychain(.delete, status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}

struct APIKeyLoadResult {
    let apiKey: String?
    let migrationWarning: String?
}

final class APIKeyStore {
    static let legacyDefaultsKey = "deepseek_api_key"

    private let secureStorage: APIKeySecureStorage
    private let defaults: UserDefaults

    init(
        secureStorage: APIKeySecureStorage = KeychainAPIKeySecureStorage(),
        defaults: UserDefaults = .standard
    ) {
        self.secureStorage = secureStorage
        self.defaults = defaults
    }

    func loadAndMigrate() -> APIKeyLoadResult {
        let legacyAPIKey = defaults.string(forKey: Self.legacyDefaultsKey).flatMap {
            $0.isEmpty ? nil : $0
        }

        do {
            if let storedAPIKey = try secureStorage.read() {
                defaults.removeObject(forKey: Self.legacyDefaultsKey)
                return APIKeyLoadResult(apiKey: storedAPIKey, migrationWarning: nil)
            }

            guard let legacyAPIKey else {
                return APIKeyLoadResult(apiKey: nil, migrationWarning: nil)
            }

            do {
                try save(legacyAPIKey)
                return APIKeyLoadResult(apiKey: legacyAPIKey, migrationWarning: nil)
            } catch {
                return APIKeyLoadResult(apiKey: legacyAPIKey, migrationWarning: error.localizedDescription)
            }
        } catch {
            return APIKeyLoadResult(apiKey: legacyAPIKey, migrationWarning: error.localizedDescription)
        }
    }

    func save(_ apiKey: String) throws {
        guard apiKey.isEmpty == false else {
            throw APIKeyStorageError.emptyAPIKey
        }

        try secureStorage.write(apiKey)
        guard try secureStorage.read() == apiKey else {
            throw APIKeyStorageError.verificationFailed
        }
        defaults.removeObject(forKey: Self.legacyDefaultsKey)
    }

    func delete() throws {
        try secureStorage.delete()
        defaults.removeObject(forKey: Self.legacyDefaultsKey)
    }
}

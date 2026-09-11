import Foundation
import Security

/// Keychain 读写。
///
/// 沙盒应用访问自身条目不需要额外 entitlement。API Key 只存这里，不写进配置文件、
/// 不进 UserDefaults、不落进日志。
struct KeychainStore: Sendable {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    /// 钥匙串读取的细分结果。
    enum KeychainReadOutcome: Equatable {
        case found(String)
        case missing
        /// 条目存在，但当前签名无权读取（用户拒绝了授权，或授权记录已失效）。
        case denied(OSStatus)
        case failed(OSStatus)
    }

    private let service: String

    init(service: String = "com.nipher.OhNews") {
        self.service = service
    }

    func save(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(updateStatus)
    }

    func read(account: String) -> String? {
        guard case .found(let value) = readOutcome(account: account) else { return nil }
        return value
    }

    /// 读取结果。
    ///
    /// 把「条目不存在」与「无权读取」分开：应用重新签名（例如 `DEVELOPMENT_TEAM`
    /// 为空时的 ad-hoc 构建）会让已有条目的授权失效，这时把「读不到」当成
    /// 「没存过」会让用户反复重存密钥而找不到真正的原因。
    func readOutcome(account: String) -> KeychainReadOutcome {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                return .missing
            }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return .denied(status)
        default:
            return .failed(status)
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

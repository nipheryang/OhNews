// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

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

    /// 读取结果缓存：**一次启动最多读一次钥匙串**。
    ///
    /// 为什么必须有它：读到密钥要经过系统授权，而应用重新签名（`DEVELOPMENT_TEAM`
    /// 为空时的 ad-hoc 构建、每次重建都会变）会让已有条目的授权失效，于是每次读取
    /// 都弹一次密码框。偏偏解读与摘要服务是**每篇文章**都要一次密钥——两者相乘就是
    /// 用户说的"切一篇文章弹一次"，根本没法用。
    ///
    /// 缓存的是**结果**，把"被拒绝"也一起缓存：用户点过一次拒绝之后，本次启动
    /// 就不再打扰他，而不是每换一篇文章再问一遍。
    private final class ReadCache: @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [String: KeychainReadOutcome] = [:]

        func outcome(for account: String) -> KeychainReadOutcome? {
            lock.lock(); defer { lock.unlock() }
            return outcomes[account]
        }

        func store(_ outcome: KeychainReadOutcome, for account: String) {
            lock.lock(); defer { lock.unlock() }
            outcomes[account] = outcome
        }

        func clear() {
            lock.lock(); defer { lock.unlock() }
            outcomes.removeAll()
        }
    }

    private static let cache = ReadCache()

    func save(_ value: String, account: String) throws {
        // 存了新密钥，之前缓存的「读不到／被拒绝」必须作废，否则用户存完仍然用不上。
        Self.cache.clear()

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
        if let cached = Self.cache.outcome(for: account) {
            #if DEBUG
            NSLog("%@", "[钥匙串] 命中缓存（不再询问系统）account=\(account)")
            #endif
            return cached
        }

        let outcome = readFromSystem(account: account)
        // 只有"没存过"不缓存：它不弹框、代价为零，而用户可能随后就去存一个。
        // 其余（读到／被拒绝／失败）一律缓存，避免反复打扰。
        if case .missing = outcome {} else {
            Self.cache.store(outcome, for: account)
        }
        #if DEBUG
        NSLog("%@", "[钥匙串] 读取系统 account=\(account) 结果=\(outcome)")
        #endif
        return outcome
    }

    private func readFromSystem(account: String) -> KeychainReadOutcome {
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
        Self.cache.clear()

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

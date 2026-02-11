import Foundation
import Security
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "Keychain")

/// Lightweight wrapper around macOS Keychain Services for storing credentials.
struct KeychainHelper {
    static let serviceName = "tech.pushtoprod.TokenFuel"

    /// Save data to the Keychain under the given account name.
    /// Overwrites any existing item with the same service + account.
    static func save(data: Data, account: String) throws {
        // Delete any existing item first (SecItemAdd fails on duplicates)
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            log.error("Keychain save failed (\(account)): \(message)")
            throw KeychainError.saveFailed(status)
        }

        log.info("Saved credential to Keychain: \(account)")
    }

    /// Load data from the Keychain for the given account name.
    /// Returns nil if no item is found.
    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                log.warning("Keychain load failed (\(account)): status \(status)")
            }
            return nil
        }

        return data
    }

    /// Delete an item from the Keychain for the given account name.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            log.info("Deleted credential from Keychain: \(account)")
            return true
        } else if status == errSecItemNotFound {
            return false
        } else {
            log.warning("Keychain delete failed (\(account)): status \(status)")
            return false
        }
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
                return "Keychain save failed: \(message) (OSStatus \(status))"
            }
        }
    }
}

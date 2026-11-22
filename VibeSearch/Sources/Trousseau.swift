import Foundation
import Security

/// Clé d'API rangée dans le trousseau d'iOS (chiffrée, jamais dans les réglages ni dans les sauvegardes en clair).
enum Trousseau {
    private static let service = "fr.vibe.search.ia"

    static func lire(_ compte: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: compte, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var res: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &res) == errSecSuccess, let d = res as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func ecrire(_ compte: String, _ valeur: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: compte]
        SecItemDelete(base as CFDictionary)
        guard let v = valeur?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
        var ajout = base
        ajout[kSecValueData as String] = Data(v.utf8)
        ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(ajout as CFDictionary, nil)
    }
}

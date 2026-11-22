import Foundation
import SafariServices

/// Extension Safari « VibeSearch » : tout le travail est fait par le script (contenu.js).
/// Ce gestionnaire répond seulement aux messages éventuels de l'extension.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let reponse = NSExtensionItem()
        reponse.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [reponse], completionHandler: nil)
    }
}

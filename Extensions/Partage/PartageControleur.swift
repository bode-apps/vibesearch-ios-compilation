import UIKit
import UniformTypeIdentifiers

/// Extension « Partager › VibeSearch » : ouvre le lien partagé (ou lance une recherche sur le texte)
/// dans VibeSearch, depuis n'importe quelle appli (Safari, Messages, Mail, Notes…).
final class PartageControleur: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await traiter() }
    }

    private func traiter() async {
        let elements = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let fournisseurs = elements.flatMap { $0.attachments ?? [] }
        var cible: String?
        // 1. Une adresse web
        for f in fournisseurs where f.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let u = try? await f.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, ["http", "https"].contains(u.scheme ?? "") {
                cible = u.absoluteString
                break
            }
        }
        // 2. Sinon du texte (qui peut contenir une adresse)
        if cible == nil {
            for f in fournisseurs where f.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let t = try? await f.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    let detecteur = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                    let lien = detecteur?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t))?.url
                    cible = lien?.absoluteString ?? t.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        if let cible, !cible.isEmpty,
           let encode = cible.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))),
           let url = URL(string: "vibesearch:" + encode) {
            ouvrir(url)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Une extension n'a pas le droit d'appeler UIApplication.open : on remonte la chaîne des
    /// répondeurs jusqu'à l'application et on appelle la méthode par le runtime Objective-C.
    private func ouvrir(_ url: URL) {
        let selecteur = NSSelectorFromString("openURL:options:completionHandler:")
        typealias Ouvrir = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        var r: UIResponder? = self
        while let actuel = r {
            if actuel is UIApplication, actuel.responds(to: selecteur), let imp = actuel.method(for: selecteur) {
                let f = unsafeBitCast(imp, to: Ouvrir.self)
                f(actuel, selecteur, url as NSURL, NSDictionary(), nil)
                return
            }
            r = actuel.next
        }
    }
}

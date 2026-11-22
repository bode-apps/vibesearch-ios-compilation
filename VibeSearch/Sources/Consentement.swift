import Foundation
import JavaScriptCore
import WebKit

/// Refus automatique des bannières cookies (moteur autoconsent de DuckDuckGo, MPL-2.0).
/// Le script de page vit dans un monde isolé ; ce « fond » natif lui fournit les règles utiles
/// pour l'adresse de chaque cadre (filtrées dans un JSContext chargé une seule fois) et exécute
/// ses tests dans le monde de la page quand il le demande.
@MainActor
final class Consentement {
    static let partage = Consentement()

    private var cache: [String: String] = [:]
    private var ordreCache: [String] = []

    private static let configuration: [String: Any] = [
        "enabled": true, "autoAction": "optOut", "disabledCmps": [String](), "enablePrehide": true,
        "enableCosmeticRules": true, "enableGeneratedRules": true, "detectRetries": 20, "isMainWorld": false,
        "prehideTimeout": 2000, "enableHeuristicDetection": true, "enablePopupMutationObserver": true,
        "visualTest": false, "performanceLoggingEnabled": false, "heuristicMode": "reject",
        "logs": ["lifecycle": false, "rulesteps": false, "detectionsteps": false, "evals": false, "errors": false, "messages": false, "waits": false]
    ]

    /// Traite un message du script de page ; la valeur renvoyée devient la réponse de sa promesse.
    func recevoir(type: String, corps: [String: Any], message: WKScriptMessage, onglet: Onglet?) async -> Any? {
        switch type {
        case "init":
            let url = corps["url"] as? String ?? ""
            let principal = corps["mainFrame"] as? Bool ?? true
            guard Reglages.partage.refuserCookies, let filtrees = await regles(url: url, principal: principal) else {
                return Self.json(["type": "initResp", "config": ["enabled": false], "rules": ["autoconsent": [String]()]])
            }
            // Les règles arrivent déjà en JSON : on les insère telles quelles (pas de double décodage)
            let debut = String(Self.json(["type": "initResp", "config": Self.configuration]).dropLast())
            return debut + ",\"rules\":{\"autoconsent\":[],\"compact\":" + filtrees + "}}"
        case "eval":
            // Test d'une règle dans le monde de la page (là où vivent les objets des CMP)
            guard let code = corps["code"] as? String, let id = corps["id"] as? String, let vue = message.webView else { return nil }
            let cadre = message.frameInfo
            let ok: Bool = await withCheckedContinuation { suite in
                vue.evaluateJavaScript(code, in: cadre, in: .page) { resultat in
                    if case let .success(valeur) = resultat {
                        suite.resume(returning: (valeur as? Bool) ?? ((valeur as? NSNumber)?.boolValue ?? false))
                    } else {
                        suite.resume(returning: false)
                    }
                }
            }
            return ["type": "evalResp", "id": id, "result": ok] as [String: Any]
        case "optOutResult":
            if corps["result"] as? Bool == true { onglet?.cookiesRefuses += 1 }
            return nil
        default:
            return nil
        }
    }
    /// Règles compactes filtrées pour une adresse (JSON). Le calcul se fait sur une file dédiée
    /// (jamais sur le fil de l'interface) ; résultat gardé par site (les règles dépendent surtout du site).
    private func regles(url: String, principal: Bool) async -> String? {
        var cle = (principal ? "M|" : "F|")
        if let u = URL(string: url) { cle += (u.host() ?? "") + "/" + (u.pathComponents.dropFirst().first ?? "") }
        if let r = cache[cle] { return r }
        let r = await MoteurRegles.partage.filtrer(url: url, principal: principal)
        guard let r else { return nil }
        cache[cle] = r
        ordreCache.append(cle)
        if ordreCache.count > 40 { cache[ordreCache.removeFirst()] = nil }
        return r
    }

    /// Prépare le moteur dès le lancement (hors du fil principal).
    func prechauffer() { Task.detached(priority: .utility) { _ = await MoteurRegles.partage.filtrer(url: "https://example.com/", principal: true) } }
    private static func json(_ objet: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: objet), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}

/// JSContext d'autoconsent, isolé dans son propre acteur (file dédiée, jamais le fil de l'interface).
actor MoteurRegles {
    static let partage = MoteurRegles()
    private var contexte: JSContext?

    func filtrer(url: String, principal: Bool) -> String? {
        if contexte == nil {
            let nouveau: JSContext? = JSContext()
            guard let src = Bundle.main.url(forResource: "consentement-regles", withExtension: "js"),
                  let code = try? String(contentsOf: src, encoding: .utf8),
                  let ctx = nouveau else { return nil }
            _ = ctx.evaluateScript(code)
            contexte = ctx
        }
        let fonction: JSValue? = contexte?.objectForKeyedSubscript("vibeRegles")
        let resultat: JSValue? = fonction?.call(withArguments: [url, principal])
        let texte: String? = resultat?.toString()
        guard let r = texte, r.hasPrefix("{") else { return nil }
        return r
    }
}
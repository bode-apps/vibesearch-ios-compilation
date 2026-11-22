import Foundation

/// Client minimal de l'API Claude (Messages, en flux SSE) — Swift n'a pas de SDK officiel,
/// on parle donc HTTP directement (POST /v1/messages).
/// Les blocs de contenu de chaque réponse (texte, réflexion, repli) sont gardés TELS QUELS et
/// renvoyés au tour suivant : c'est ce que l'API attend d'une conversation.
struct Claude {
    let cle: String
    let modele: ModeleIA

    enum Evenement {
        case texte(String)
        /// `complet` = le message est arrivé jusqu'au bout (message_stop) ; `modele` = modèle qui a répondu (repli éventuel).
        case fin(blocs: [[String: Any]], entree: Int, sortie: Int, lectureCache: Int, ecritureCache: Int, arret: String?, modele: String, complet: Bool)
    }

    /// Arrêt demandé par l'utilisateur : la lecture s'interrompt proprement et le coût déjà
    /// consommé est quand même remonté (contrairement à l'annulation de la tâche).
    final class Arret: @unchecked Sendable {
        private let verrou = NSLock()
        private var _demande = false
        var demande: Bool {
            get { verrou.lock(); defer { verrou.unlock() }; return _demande }
            set { verrou.lock(); _demande = newValue; verrou.unlock() }
        }
    }

    struct Erreur: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Envoie la conversation et renvoie les morceaux de texte au fil de l'eau.
    /// `outils` : outils serveur facultatifs (ex. recherche web) ; `effort` : low / medium / high.
    func envoyer(systeme: String, messages: [[String: Any]], arret: Arret = Arret(), outils: [[String: Any]]? = nil, effort: String = "medium") -> AsyncThrowingStream<Evenement, Error> {
        AsyncThrowingStream { suite in
            let tache = Task {
                do {
                    try await diffuser(systeme: systeme, messages: messages, arretDemande: arret, outils: outils, effort: effort, suite: suite)
                    suite.finish()
                } catch {
                    suite.finish(throwing: error)
                }
            }
            suite.onTermination = { _ in tache.cancel() }
        }
    }

    private func diffuser(systeme: String, messages: [[String: Any]], arretDemande: Arret, outils: [[String: Any]]?, effort: String, suite: AsyncThrowingStream<Evenement, Error>.Continuation) async throws {
        var corps: [String: Any] = [
            "model": modele.rawValue,
            "max_tokens": 32000,
            "stream": true,
            "system": systeme,
            "messages": messages,
            // Mise en cache automatique du préfixe : les questions suivantes sur la même page coûtent bien moins cher
            "cache_control": ["type": "ephemeral"],
            "output_config": ["effort": effort]
        ]
        if let outils { corps["tools"] = outils }
        var requete = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 300)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "content-type")
        requete.setValue(cle, forHTTPHeaderField: "x-api-key")
        requete.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if modele.replisServeur {
            // Si le modèle décline une demande, l'API la relance d'elle-même sur un modèle de repli
            corps["fallbacks"] = "default"
            requete.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)

        let (octets, reponse) = try await URLSession.shared.bytes(for: requete)
        let statut = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        guard statut == 200 else {
            var texte = ""
            for try await ligne in octets.lines { texte += ligne }
            let message = ((try? JSONSerialization.jsonObject(with: Data(texte.utf8))) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw Erreur(message: Self.erreurLisible(statut: statut, detail: message))
        }

        var blocs: [Int: [String: Any]] = [:]
        var entree = 0, sortie = 0, lecture = 0, ecriture = 0
        var arret: String?
        var servi = modele.rawValue
        var complet = false
        // Coût toujours remonté, même si la lecture est interrompue (bouton Stop) : le plafond reste juste
        defer {
            let ordonnes = blocs.keys.sorted().compactMap { blocs[$0] }
            if !complet {
                // Réponse interrompue : jetons de sortie estimés d'après le texte reçu (~3 caractères par jeton)
                let caracteres = ordonnes.reduce(0) { $0 + (($1["text"] as? String)?.count ?? 0) + (($1["thinking"] as? String)?.count ?? 0) }
                sortie = max(sortie, caracteres / 3)
            }
            suite.yield(.fin(blocs: ordonnes, entree: entree, sortie: sortie, lectureCache: lecture, ecritureCache: ecriture, arret: arret, modele: servi, complet: complet))
        }
        for try await ligne in octets.lines {
            if Task.isCancelled || arretDemande.demande { break }
            guard ligne.hasPrefix("data:") else { continue }
            let json = ligne.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let ev = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any], let type = ev["type"] as? String else { continue }
            switch type {
            case "message_start":
                if let m = (ev["message"] as? [String: Any])?["model"] as? String { servi = m }
                let u = (ev["message"] as? [String: Any])?["usage"] as? [String: Any]
                entree = u?["input_tokens"] as? Int ?? 0
                lecture = u?["cache_read_input_tokens"] as? Int ?? 0
                ecriture = u?["cache_creation_input_tokens"] as? Int ?? 0
            case "content_block_start":
                if let i = ev["index"] as? Int, let b = ev["content_block"] as? [String: Any] { blocs[i] = b }
            case "content_block_delta":
                guard let i = ev["index"] as? Int, let d = ev["delta"] as? [String: Any], var b = blocs[i] else { continue }
                switch d["type"] as? String {
                case "text_delta":
                    let t = d["text"] as? String ?? ""
                    b["text"] = (b["text"] as? String ?? "") + t
                    suite.yield(.texte(t))
                case "thinking_delta":
                    b["thinking"] = (b["thinking"] as? String ?? "") + (d["thinking"] as? String ?? "")
                case "signature_delta":
                    b["signature"] = d["signature"] as? String ?? ""
                default:
                    break
                }
                blocs[i] = b
            case "message_delta":
                if let d = ev["delta"] as? [String: Any], let s = d["stop_reason"] as? String { arret = s }
                if let u = ev["usage"] as? [String: Any] {
                    sortie = u["output_tokens"] as? Int ?? sortie
                    if let e = u["input_tokens"] as? Int { entree = e }
                }
            case "message_stop":
                complet = true
            case "error":
                let m = (ev["error"] as? [String: Any])?["message"] as? String ?? "erreur inconnue"
                throw Erreur(message: "Claude a interrompu la réponse : \(m)")
            default:
                break
            }
        }
    }

    /// Coût en dollars d'un échange (lecture de cache facturée 10 %, écriture 125 %), au prix du
    /// modèle qui a réellement répondu (un repli peut en changer).
    func cout(entree: Int, sortie: Int, lectureCache: Int, ecritureCache: Int, modeleServi: String? = nil) -> Double {
        let p = Self.prix(modeleServi ?? modele.rawValue) ?? modele.prix
        let e = Double(entree) + Double(lectureCache) * 0.1 + Double(ecritureCache) * 1.25
        return (e * p.entree + Double(sortie) * p.sortie) / 1_000_000
    }

    /// Prix connus ($ par million de jetons) ; modèle inconnu → prix du modèle choisi.
    private static func prix(_ id: String) -> (entree: Double, sortie: Double)? {
        if let m = ModeleIA(rawValue: id) { return m.prix }
        if id.hasPrefix("claude-opus-5") || id.hasPrefix("claude-opus-4") { return (5, 25) }
        if id.hasPrefix("claude-sonnet") { return (2, 10) }
        if id.hasPrefix("claude-haiku") { return (1, 5) }
        return nil
    }

    private static func erreurLisible(statut: Int, detail: String?) -> String {
        switch statut {
        case 401: "Clé d'API refusée. Vérifiez-la dans Réglages › Intelligence artificielle."
        case 429: "Trop de demandes pour le moment, réessayez dans un instant."
        case 529, 503: "Claude est surchargé, réessayez dans un instant."
        case 400: "Demande refusée par l'API : \(detail ?? "requête invalide")."
        default: "Erreur \(statut)\(detail.map { " : \($0)" } ?? "")."
        }
    }
}

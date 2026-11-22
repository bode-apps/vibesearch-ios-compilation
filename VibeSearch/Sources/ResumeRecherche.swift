import Foundation
import Observation

/// Réponse IA automatique sur les pages de résultats (Google, Bing, DuckDuckGo…), comme sur PC :
/// dès que la page est chargée, Claude lit les résultats et affiche une réponse courte avec ses sources
/// au-dessus de la barre. Jamais en mode Fantôme. Une réponse par recherche (gardée en mémoire).
@MainActor
@Observable
final class ResumeRecherche {
    static let partage = ResumeRecherche()

    struct Reponse {
        var requete = ""
        var texte = ""
        var enCours = true
        var erreur: String?
    }

    /// Réponses par adresse de page de résultats.
    private(set) var reponses: [String: Reponse] = [:]
    /// Pages où l'utilisateur a fermé la bulle.
    private(set) var masquees: Set<String> = []
    @ObservationIgnored private var taches: [String: Task<Void, Never>] = [:]

    func reponse(pour url: URL?) -> Reponse? {
        guard let k = url?.absoluteString, !masquees.contains(k) else { return nil }
        return reponses[k]
    }

    func masqueePour(_ url: URL?) -> Bool { url.map { masquees.contains($0.absoluteString) } ?? false }

    func masquer(_ url: URL?) {
        guard let k = url?.absoluteString else { return }
        masquees.insert(k)
        taches[k]?.cancel()
    }

    private struct Resultats: Decodable {
        struct R: Decodable { let titre: String; let url: String; let extrait: String }
        let requete: String
        let resultats: [R]
    }

    /// Appelé quand une page de résultats a fini de charger.
    func lancer(pour onglet: Onglet) {
        let r = Reglages.partage
        guard r.resumeAuto, !onglet.fantome, !r.plafondAtteint, onglet.estPageRecherche,
              let url = onglet.url, let cle = Trousseau.lire("anthropic"), !cle.isEmpty else { return }
        let k = url.absoluteString
        guard reponses[k] == nil, !masquees.contains(k) else { return }
        if reponses.count > 30 { reponses.removeAll() }
        reponses[k] = Reponse()
        taches[k] = Task { [weak self] in
            guard let self else { return }
            // Les résultats Google arrivent parfois un peu après la fin du chargement
            var lu: Resultats?
            for _ in 0 ..< 3 {
                if let json = await onglet.executer(FabriqueWeb.sourceRecherche),
                   let r = try? JSONDecoder().decode(Resultats.self, from: Data(json.utf8)), r.resultats.count >= 2 {
                    lu = r
                    break
                }
                try? await Task.sleep(for: .milliseconds(900))
            }
            guard let lu else {
                self.reponses[k]?.enCours = false
                self.reponses[k]?.erreur = "Résultats illisibles sur cette page."
                return
            }
            self.reponses[k]?.requete = lu.requete
            var contexte = "<recherche requete=\"\(lu.requete)\">\n"
            for (i, x) in lu.resultats.enumerated() { contexte += "[\(i + 1)] \(x.titre)\n\(x.url)\n\(x.extrait)\n\n" }
            contexte += "</recherche>"
            let systeme = """
            Tu es l'assistant de recherche du navigateur VibeSearch sur iPhone. À partir des résultats fournis, \
            réponds directement à la recherche en français, en 2 à 4 phrases courtes. Cite tes sources juste après \
            l'information sous la forme de liens Markdown [1](adresse), [2](adresse). Pas de titres, pas de listes \
            longues. Si les résultats ne permettent pas de répondre, dis-le en une phrase.
            """
            let client = Claude(cle: cle, modele: r.modeleIA)
            do {
                for try await ev in client.envoyer(systeme: systeme, messages: [["role": "user", "content": contexte]], effort: "low") {
                    if Task.isCancelled { break }
                    switch ev {
                    case let .texte(t):
                        self.reponses[k]?.texte += t
                    case let .fin(_, entree, sortie, lecture, ecriture, motif, servi, _):
                        r.ajouterDepense(client.cout(entree: entree, sortie: sortie, lectureCache: lecture, ecritureCache: ecriture, modeleServi: servi))
                        if motif == "refusal" { self.reponses[k]?.erreur = "Claude a préféré ne pas répondre." }
                    }
                }
            } catch {
                self.reponses[k]?.erreur = error.localizedDescription
            }
            self.reponses[k]?.enCours = false
        }
    }
}

import Foundation
import os
import WebKit

let journal = Logger(subsystem: "fr.vibe.search", category: "bloqueur")

/// Bloqueur de pubs et de traqueurs : listes EasyList / Liste FR / EasyPrivacy converties en règles
/// WebKit au moment de la compilation de l'appli (outils/listes.mjs).
/// WebKit les compile en automate natif UNE fois par version, puis les garde sur le disque :
/// au lancement suivant, le chargement est instantané et le filtrage ne coûte aucun JavaScript.
@MainActor
final class Bloqueur {
    static let partage = Bloqueur()

    struct Liste: Decodable { let id: String; let groupe: String; let nom: String; let regles: Int }
    private struct Manifeste: Decodable { let version: String; let listes: [Liste] }

    private(set) var listes: [Liste] = []
    /// Listes compilées prêtes à l'emploi, par identifiant.
    private(set) var compilees: [String: WKContentRuleList] = [:]
    private(set) var pret = false
    private var version = ""
    private var enAttente: [() -> Void] = []

    var nombreRegles: Int { listes.filter { compilees[$0.id] != nil }.reduce(0) { $0 + $1.regles } }

    func preparer() {
        guard version.isEmpty,
              let url = Bundle.main.url(forResource: "listes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Manifeste.self, from: data)
        else { pret = true; return }
        version = m.version
        listes = m.listes
        let peutEtre: WKContentRuleListStore? = WKContentRuleListStore.default()
        guard let store = peutEtre else { pret = true; return }
        let groupe = DispatchGroup()
        let recherches = DispatchGroup()
        let debut = Date()
        for liste in m.listes {
            let ident = "\(liste.id)@\(m.version)"
            groupe.enter()
            recherches.enter()
            store.lookUpContentRuleList(forIdentifier: ident) { [weak self] trouvee, _ in
                recherches.leave()
                if let trouvee {
                    self?.compilees[liste.id] = trouvee
                    groupe.leave()
                    return
                }
                // Première ouverture de cette version : compilation (quelques secondes, en arrière-plan côté WebKit)
                guard let fichier = Bundle.main.url(forResource: "regles-\(liste.id)", withExtension: "json"),
                      let json = try? String(contentsOf: fichier, encoding: .utf8)
                else { groupe.leave(); return }
                store.compileContentRuleList(forIdentifier: ident, encodedContentRuleList: json) { compilee, erreur in
                    if let compilee { self?.compilees[liste.id] = compilee }
                    if let erreur { journal.error("bloqueur \(liste.nom, privacy: .public) : \(erreur.localizedDescription, privacy: .public)") }
                    groupe.leave()
                }
            }
        }
        // Les pages n'attendent que la recherche des listes déjà compilées (une fraction de seconde) :
        // une première compilation (après installation ou mise à jour) se fait sans bloquer la navigation.
        recherches.notify(queue: .main) { [weak self] in self?.libererAttente() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.libererAttente() }
        groupe.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.pret = true
            journal.notice("bloqueur prêt : \(self.nombreRegles) règles en \(String(format: "%.1f", Date().timeIntervalSince(debut)), privacy: .public) s")
            self.nettoyerAnciennesVersions(store: store)
            self.reappliquer()
            self.libererAttente()
        }
    }

    private var attenteLiberee = false
    private func libererAttente() {
        guard !attenteLiberee else { return }
        attenteLiberee = true
        for onglet in Navigateur.partage.tousLesOnglets { onglet.reappliquerBlocage() }
        let a = enAttente
        enAttente = []
        a.forEach { $0() }
    }

    /// Supprime du disque les listes compilées d'anciennes versions de l'appli.
    private func nettoyerAnciennesVersions(store: WKContentRuleListStore) {
        store.getAvailableContentRuleListIdentifiers { ids in
            for id in ids ?? [] where !id.hasSuffix("@\(self.version)") {
                store.removeContentRuleList(forIdentifier: id) { _ in }
            }
        }
    }

    /// Listes actives selon les réglages.
    func listesActives() -> [WKContentRuleList] {
        let r = Reglages.partage
        return listes.compactMap { l in
            if l.groupe == "pubs" && !r.bloquerPubs { return nil }
            if l.groupe == "traqueurs" && !r.bloquerTraqueurs { return nil }
            return compilees[l.id]
        }
    }

    /// Pose (ou retire) les listes sur un contrôleur de page selon le site visité.
    func appliquer(sur ucc: WKUserContentController, hote: String?) {
        ucc.removeAllContentRuleLists()
        guard !Reglages.partage.estAutorise(hote: hote) else { return }
        for l in listesActives() { ucc.add(l) }
    }

    /// Réglages changés : chaque onglet ouvert reprend les bonnes listes.
    func reappliquer() {
        guard pret || attenteLiberee else { return }
        for onglet in Navigateur.partage.tousLesOnglets { onglet.reappliquerBlocage() }
    }

    /// Exécute une action dès que les listes sont prêtes (premier chargement de page).
    func quandPret(_ action: @escaping () -> Void) {
        if pret || attenteLiberee { action() } else { enAttente.append(action) }
    }
}

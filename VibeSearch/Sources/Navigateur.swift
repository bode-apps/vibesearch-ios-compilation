import Foundation
import Observation
import UIKit

/// État global du navigateur : onglets normaux, onglets Fantôme, groupes, onglet actif, mémoire.
@MainActor
@Observable
final class Navigateur {
    static let partage = Navigateur()

    private(set) var onglets: [Onglet] = []
    private(set) var ongletsFantome: [Onglet] = []
    private(set) var actif: Onglet?
    var modeFantome = false
    var grilleVisible = false
    /// Saisie dans la barre d'adresse en cours.
    var saisieActive = false { didSet { if saisieActive { barreReduite = false } } }
    /// Barre du bas réduite (défilement vers le bas).
    private(set) var barreReduite = false
    /// Groupe affiché dans la grille (nil = tous les onglets).
    var groupeAffiche: String?
    /// Traduction demandée pour cet onglet (exécutée par la vue de traduction).
    var traductionDemandee: Onglet?
    /// Panneau à ouvrir (raccourcis, liens vibesearch://, essais).
    var panneauDemande: Feuille?
    @ObservationIgnored private var fermes: [(url: URL, fantome: Bool, groupe: String?)] = []
    @ObservationIgnored private var debutFantome: Date?

    var tousLesOnglets: [Onglet] { onglets + ongletsFantome }
    var ongletsAffiches: [Onglet] { modeFantome ? ongletsFantome : onglets }
    var peutRouvrir: Bool { fermes.contains { !$0.fantome || !ongletsFantome.isEmpty } }
    /// Groupes existants (dans l'ordre d'apparition).
    var groupes: [String] {
        var vus: [String] = []
        for o in onglets { if let g = o.groupe, !vus.contains(g) { vus.append(g) } }
        return vus
    }

    private init() {
        // Le bloqueur commence à charger ses listes AVANT la restauration des onglets
        Bloqueur.partage.preparer()
        // Extensions (Bitwarden) : le contrôleur doit exister avant la création des premières pages
        Extensions.demarrer()
        restaurerSession()
        if onglets.isEmpty { actif = nouvelOnglet(fantome: false, activer: true) }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.libererMemoire(garder: 1) }
        }
    }

    // MARK: - Onglets

    @discardableResult
    func nouvelOnglet(url: URL? = nil, fantome: Bool, activer: Bool, apres: Onglet? = nil) -> Onglet {
        let o = Onglet(fantome: fantome)
        if fantome {
            if ongletsFantome.isEmpty { debutFantome = .now }
            inserer(o, dans: &ongletsFantome, apres: apres)
        } else {
            // Nouvel onglet créé depuis la grille d'un groupe : il rejoint ce groupe
            o.groupe = apres?.groupe ?? (grilleVisible ? groupeAffiche : nil)
            inserer(o, dans: &onglets, apres: apres)
        }
        Extensions.ongletOuvert(o)
        if activer { self.activer(o) }
        if let url { o.charger(url) }
        return o
    }

    private func inserer(_ o: Onglet, dans liste: inout [Onglet], apres: Onglet?) {
        if let apres, let i = liste.firstIndex(where: { $0 === apres }) { liste.insert(o, at: i + 1) } else { liste.append(o) }
    }

    func activer(_ o: Onglet) {
        let ancien = actif
        if actif !== o { actif?.capturer() }
        // Entrée dans le mode Fantôme : Face ID si le réglage le demande
        if o.fantome && actif?.fantome != true { Verrou.partage.entreeFantome() }
        actif = o
        modeFantome = o.fantome
        o.dernierAcces = .now
        barreReduite = false
        if o.url != nil { o.vueActive() }
        if ancien !== o { Extensions.ongletActive(o, avant: ancien) }
        libererMemoire(garder: Reglages.partage.ongletsVivants)
    }

    func fermer(_ o: Onglet) {
        if let u = o.url {
            fermes.append((u, o.fantome, o.groupe))
            if fermes.count > 25 { fermes.removeFirst() }
        }
        o.endormir()
        var liste = o.fantome ? ongletsFantome : onglets
        guard let i = liste.firstIndex(where: { $0 === o }) else { return }
        liste.remove(at: i)
        if o.fantome { ongletsFantome = liste } else { onglets = liste }
        Extensions.ongletFerme(o)
        if o.fantome && ongletsFantome.isEmpty { finirFantome() }
        if actif === o {
            if let suivant = liste[safe: min(i, liste.count - 1)] {
                activer(suivant)
            } else if o.fantome, let dernier = onglets.max(by: { $0.dernierAcces < $1.dernierAcces }) {
                activer(dernier)
            } else {
                nouvelOnglet(fantome: o.fantome, activer: true)
            }
        }
        enregistrerSessionPlusTard()
    }

    func fermerTout(fantome: Bool, groupe: String? = nil) {
        let cibles = (fantome ? ongletsFantome : onglets).filter { groupe == nil || $0.groupe == groupe }
        for o in cibles { o.endormir() }
        if fantome {
            ongletsFantome = []
            finirFantome()
        } else {
            onglets.removeAll { o in cibles.contains { $0 === o } }
            for o in cibles { Extensions.ongletFerme(o) }
        }
        if let a = actif, !cibles.contains(where: { $0 === a }) { return }
        if let o = onglets.max(by: { $0.dernierAcces < $1.dernierAcces }), fantome || !onglets.isEmpty { activer(o) } else { nouvelOnglet(fantome: false, activer: true) }
        enregistrerSessionPlusTard()
    }

    func rouvrirDernier() {
        guard let i = fermes.lastIndex(where: { !$0.fantome || !ongletsFantome.isEmpty }) else { return }
        let f = fermes.remove(at: i)
        let o = nouvelOnglet(url: f.url, fantome: f.fantome, activer: true)
        o.groupe = f.groupe
    }

    // MARK: - Groupes

    func ranger(_ o: Onglet, dans groupe: String?) {
        o.groupe = groupe?.trimmingCharacters(in: .whitespaces).isEmpty == false ? groupe : nil
        enregistrerSessionPlusTard()
    }

    func renommerGroupe(_ ancien: String, en nouveau: String) {
        let n = nouveau.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        for o in onglets where o.groupe == ancien { o.groupe = n }
        if groupeAffiche == ancien { groupeAffiche = n }
        enregistrerSessionPlusTard()
    }

    func dissoudreGroupe(_ g: String) {
        for o in onglets where o.groupe == g { o.groupe = nil }
        if groupeAffiche == g { groupeAffiche = nil }
        enregistrerSessionPlusTard()
    }

    // MARK: - Ouverture d'adresses

    /// Texte tapé dans la barre : adresse si ça en a l'air, sinon recherche.
    func ouvrir(texte: String) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let url = Adresse.interpreter(t) else { return }
        ouvrir(url: url, nouvelOnglet: false)
    }

    @discardableResult
    func ouvrir(url: URL, nouvelOnglet nouveau: Bool, arrierePlan: Bool = false, fantome: Bool? = nil) -> Onglet {
        let f = fantome ?? modeFantome
        if !nouveau, let a = actif, a.fantome == f {
            a.charger(url)
            return a
        }
        let o = nouvelOnglet(fantome: f, activer: !arrierePlan, apres: actif?.fantome == f ? actif : nil)
        if arrierePlan {
            o.url = url // chargé au premier affichage : n'occupe pas de mémoire tout de suite
        } else {
            o.charger(url)
        }
        return o
    }

    func basculerFantome() {
        if modeFantome {
            if let o = onglets.max(by: { $0.dernierAcces < $1.dernierAcces }) { activer(o) } else { nouvelOnglet(fantome: false, activer: true) }
        } else if let o = ongletsFantome.max(by: { $0.dernierAcces < $1.dernierAcces }) {
            activer(o)
        } else {
            nouvelOnglet(fantome: true, activer: true)
        }
    }

    /// Fantôme : autodestruction 24 h après l'ouverture (comme sur PC).
    func verifierFantome() {
        if let d = debutFantome, Date.now.timeIntervalSince(d) > 24 * 3600, !ongletsFantome.isEmpty { fermerTout(fantome: true) }
    }

    /// Fin de session Fantôme : stockage détruit, nouvelle empreinte, téléchargements effacés,
    /// et plus aucune page Fantôme dans « Rouvrir l'onglet fermé ».
    private func finirFantome() {
        debutFantome = nil
        fermes.removeAll { $0.fantome }
        FabriqueWeb.detruireFantome()
        Telechargements.partage.effacerFantome()
    }

    /// Fermeture automatique des onglets oubliés (réglage), au retour dans l'appli.
    func fermerOnglesOublies() {
        let jours = Reglages.partage.fermetureAuto.rawValue
        guard jours > 0 else { return }
        let limite = Date.now.addingTimeInterval(-Double(jours) * 86400)
        let vieux = onglets.filter { $0 !== actif && $0.dernierAcces < limite }
        guard !vieux.isEmpty else { return }
        for o in vieux { o.endormir() }
        onglets.removeAll { o in vieux.contains { $0 === o } }
        enregistrerSessionPlusTard()
    }

    // MARK: - Barre

    func reduireBarre(_ r: Bool) {
        guard r != barreReduite, !saisieActive else { return }
        barreReduite = r
    }

    // MARK: - Mémoire

    /// Garde vivants l'onglet actif et les plus récents ; les autres s'endorment.
    func libererMemoire(garder: Int) {
        let vivants = tousLesOnglets.filter { $0.vue != nil && $0 !== actif }.sorted { $0.dernierAcces > $1.dernierAcces }
        for o in vivants.dropFirst(max(0, garder - 1)) where !o.enChargement || garder <= 1 {
            o.endormir()
        }
    }

    // MARK: - Session (onglets normaux seulement : le Fantôme ne laisse aucune trace)

    private struct OngletSauve: Codable {
        let id: UUID
        let url: URL?
        let titre: String
        let etat: Data?
        var groupe: String?
        var acces: Date?
    }
    private struct Session: Codable { let onglets: [OngletSauve]; let actif: UUID? }

    private static var fichierSession: URL {
        let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier.appendingPathComponent("session.json")
    }

    @ObservationIgnored private var enregistrementPrevu = false
    func enregistrerSessionPlusTard() {
        guard !enregistrementPrevu else { return }
        enregistrementPrevu = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.enregistrementPrevu = false
            self?.enregistrerSession()
        }
    }

    func enregistrerSession() {
        guard Reglages.partage.restaurerSession else {
            try? FileManager.default.removeItem(at: Self.fichierSession)
            return
        }
        let s = Session(
            onglets: onglets.filter { $0.url != nil }.map {
                OngletSauve(id: $0.id, url: $0.url, titre: $0.titre, etat: $0.etatPourSession, groupe: $0.groupe, acces: $0.dernierAcces)
            },
            actif: actif?.fantome == false ? actif?.id : nil)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: Self.fichierSession, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func restaurerSession() {
        guard Reglages.partage.restaurerSession,
              let data = try? Data(contentsOf: Self.fichierSession),
              let s = try? JSONDecoder().decode(Session.self, from: data) else { return }
        onglets = s.onglets.map {
            let o = Onglet(id: $0.id, fantome: false, url: $0.url, titre: $0.titre, etat: $0.etat, groupe: $0.groupe)
            if let a = $0.acces { o.dernierAcces = a }
            return o
        }
        // Onglet actif choisi SANS créer sa vue web : au lancement, la fenêtre de l'appli n'existe pas encore,
        // et une vue web créée hors fenêtre fait planter la gestion des touchers d'iOS au premier toucher.
        // Elle sera créée par l'écran (WebConteneur) une fois la fenêtre en place.
        if let o = onglets.first(where: { $0.id == s.actif }) ?? onglets.last {
            actif = o
            modeFantome = false
            o.dernierAcces = .now
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

import Foundation
import Observation

/// Moteurs de recherche (mêmes adresses que la version PC : filtre parental désactivé partout).
enum Moteur: String, CaseIterable, Identifiable, Codable {
    case googleEpure = "google-clean", google, duckduckgo, brave, startpage, bing
    var id: String { rawValue }
    var nom: String {
        switch self {
        case .googleEpure: "Google (épuré)"
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .brave: "Brave Search"
        case .startpage: "Startpage"
        case .bing: "Bing"
        }
    }
    /// %s = requête encodée. udm=14 = onglet « Web » de Google : sans aperçu IA, beaucoup moins d'encarts.
    var modele: String {
        switch self {
        case .googleEpure: "https://www.google.com/search?udm=14&safe=off&q=%s"
        // Google normal : aperçu IA, images, encarts… comme dans Safari
        case .google: "https://www.google.com/search?q=%s"
        case .duckduckgo: "https://duckduckgo.com/?kp=-2&q=%s"
        case .brave: "https://search.brave.com/search?safesearch=off&q=%s"
        case .startpage: "https://www.startpage.com/do/search?qadf=none&q=%s"
        case .bing: "https://www.bing.com/search?adlt=off&q=%s"
        }
    }
    func adresse(pour requete: String) -> URL? {
        let q = requete.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? requete
        return URL(string: modele.replacingOccurrences(of: "%s", with: q))
    }
}

/// Modèles Claude proposés (prix en dollars par million de jetons : entrée / sortie).
enum ModeleIA: String, CaseIterable, Identifiable, Codable {
    case opus = "claude-opus-5-5", sonnet = "claude-sonnet-5-5", haiku = "claude-haiku-5-5"
    var id: String { rawValue }
    var nom: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }
    var detail: String {
        switch self {
        case .opus: "Le plus fin · 4 $ / 20 $ le million de jetons"
        case .sonnet: "Équilibré · 2 $ / 10 $"
        case .haiku: "Le plus rapide et économique · 0,10 $ / 0,50 $"
        }
    }
    var prix: (entree: Double, sortie: Double) {
        switch self {
        case .opus: (4, 20)
        case .sonnet: (2, 10)
        case .haiku: (0.10, 0.50)
        }
    }
    /// Repli côté serveur si le modèle décline (non disponible pour Haiku).
    var replisServeur: Bool { self != .haiku }
}

/// Fermeture automatique des onglets oubliés.
enum FermetureAuto: Int, CaseIterable, Identifiable, Codable {
    case jamais = 0, jour = 1, semaine = 7, mois = 30
    var id: Int { rawValue }
    var nom: String {
        switch self {
        case .jamais: "Jamais"
        case .jour: "Après un jour"
        case .semaine: "Après une semaine"
        case .mois: "Après un mois"
        }
    }
}

/// Réglages propres à un site (mémorisés par nom de domaine).
struct ReglageSite: Codable, Equatable {
    var zoom: Double = 1
    var ordinateur = false
    /// nil = suit le réglage général du mode sombre.
    var sombre: Bool?
    var estVide: Bool { zoom == 1 && !ordinateur && sombre == nil }
}

/// Réglages de l'appli, enregistrés dans UserDefaults à chaque changement.
@MainActor
@Observable
final class Reglages {
    static let partage = Reglages()
    @ObservationIgnored private let d = UserDefaults.standard

    var moteur: Moteur { didSet { d.set(moteur.rawValue, forKey: "moteur") } }
    var bloquerPubs: Bool { didSet { d.set(bloquerPubs, forKey: "bloquerPubs"); Bloqueur.partage.reappliquer() } }
    var bloquerTraqueurs: Bool { didSet { d.set(bloquerTraqueurs, forKey: "bloquerTraqueurs"); Bloqueur.partage.reappliquer() } }
    var refuserCookies: Bool { didSet { d.set(refuserCookies, forKey: "refuserCookies"); Bloqueur.partage.reappliquer() } }
    var bouclierEmpreinte: Bool { didSet { d.set(bouclierEmpreinte, forKey: "bouclierEmpreinte"); Bloqueur.partage.reappliquer() } }
    var sauterSponsors: Bool { didSet { d.set(sauterSponsors, forKey: "sauterSponsors"); Bloqueur.partage.reappliquer() } }
    var sauterIntros: Bool { didSet { d.set(sauterIntros, forKey: "sauterIntros") } }
    var pubsYouTube: Bool { didSet { d.set(pubsYouTube, forKey: "pubsYouTube"); Bloqueur.partage.reappliquer() } }
    /// Sites où le blocage est coupé (« ce site marche mal »).
    var sitesAutorises: [String] { didSet { d.set(sitesAutorises, forKey: "sitesAutorises"); Bloqueur.partage.reappliquer() } }
    var restaurerSession: Bool { didSet { d.set(restaurerSession, forKey: "restaurerSession") } }
    var modeleIA: ModeleIA { didSet { d.set(modeleIA.rawValue, forKey: "modeleIA") } }
    /// Plafond mensuel de dépense IA en dollars (0 = pas de plafond).
    var plafondIA: Double { didSet { d.set(plafondIA, forKey: "plafondIA") } }
    /// Dépense IA du mois en cours (« AAAA-MM » → dollars).
    var depenseIA: [String: Double] { didSet { d.set(depenseIA, forKey: "depenseIA") } }
    /// Nombre d'onglets gardés « vivants » en mémoire ; les autres dorment (rechargés au retour).
    var ongletsVivants: Int { didSet { d.set(ongletsVivants, forKey: "ongletsVivants") } }
    /// Retire les paramètres de pistage des adresses (utm_…, fbclid, gclid…).
    var nettoyerLiens: Bool { didSet { d.set(nettoyerLiens, forKey: "nettoyerLiens") } }
    /// Essaie toujours HTTPS d'abord ; HTTP seulement si le site ne sait pas faire autrement.
    var httpsPartout: Bool { didSet { d.set(httpsPartout, forKey: "httpsPartout") } }
    /// Face ID pour ouvrir le mode Fantôme / l'appli.
    var verrouFantome: Bool { didSet { d.set(verrouFantome, forKey: "verrouFantome") } }
    var verrouAppli: Bool { didSet { d.set(verrouAppli, forKey: "verrouAppli") } }
    /// Thème sombre imposé aux sites clairs.
    var sombreSites: Bool { didSet { d.set(sombreSites, forKey: "sombreSites"); Bloqueur.partage.reappliquer() } }
    /// YouTube continue à jouer en arrière-plan et écran verrouillé.
    var youtubeArrierePlan: Bool { didSet { d.set(youtubeArrierePlan, forKey: "youtubeArrierePlan"); Bloqueur.partage.reappliquer() } }
    var fermetureAuto: FermetureAuto { didSet { d.set(fermetureAuto.rawValue, forKey: "fermetureAuto") } }
    /// Bouton « Réponse IA » sur les pages de résultats des moteurs de recherche.
    var bulleRecherche: Bool { didSet { d.set(bulleRecherche, forKey: "bulleRecherche") } }
    /// Réponse IA automatique au-dessus des résultats de recherche (sinon : bouton « Demander »).
    var resumeAuto: Bool { didSet { d.set(resumeAuto, forKey: "resumeAuto") } }
    /// Bitwarden intégré au navigateur (extension, iOS 18.4+).
    var extensionBitwarden: Bool {
        didSet {
            d.set(extensionBitwarden, forKey: "extensionBitwarden")
            if extensionBitwarden { Extensions.demarrer() } else { Extensions.arreter() }
        }
    }
    /// Barre qui se réduit quand on fait défiler la page vers le bas.
    var barreReductible: Bool { didSet { d.set(barreReductible, forKey: "barreReductible") } }
    /// Réglages par site (zoom, version ordinateur, sombre).
    var parSite: [String: ReglageSite] {
        didSet { if let data = try? JSONEncoder().encode(parSite) { d.set(data, forKey: "parSite") } }
    }

    private init() {
        d.register(defaults: [
            "moteur": Moteur.googleEpure.rawValue, "bloquerPubs": true, "bloquerTraqueurs": true, "refuserCookies": true,
            "bouclierEmpreinte": true, "sauterSponsors": true, "sauterIntros": true, "pubsYouTube": true, "restaurerSession": true,
            "modeleIA": ModeleIA.opus.rawValue, "plafondIA": 5.0, "ongletsVivants": 4,
            "nettoyerLiens": true, "httpsPartout": true, "verrouFantome": false, "verrouAppli": false, "sombreSites": false,
            "youtubeArrierePlan": true, "fermetureAuto": FermetureAuto.semaine.rawValue, "bulleRecherche": true, "resumeAuto": true, "barreReductible": true, "extensionBitwarden": true
        ])
        moteur = Moteur(rawValue: d.string(forKey: "moteur") ?? "") ?? .googleEpure
        bloquerPubs = d.bool(forKey: "bloquerPubs")
        bloquerTraqueurs = d.bool(forKey: "bloquerTraqueurs")
        refuserCookies = d.bool(forKey: "refuserCookies")
        bouclierEmpreinte = d.bool(forKey: "bouclierEmpreinte")
        sauterSponsors = d.bool(forKey: "sauterSponsors")
        sauterIntros = d.bool(forKey: "sauterIntros")
        pubsYouTube = d.bool(forKey: "pubsYouTube")
        sitesAutorises = d.stringArray(forKey: "sitesAutorises") ?? []
        restaurerSession = d.bool(forKey: "restaurerSession")
        modeleIA = ModeleIA(rawValue: d.string(forKey: "modeleIA") ?? "") ?? .opus
        plafondIA = d.double(forKey: "plafondIA")
        depenseIA = (d.dictionary(forKey: "depenseIA") as? [String: Double]) ?? [:]
        ongletsVivants = max(2, d.integer(forKey: "ongletsVivants"))
        nettoyerLiens = d.bool(forKey: "nettoyerLiens")
        httpsPartout = d.bool(forKey: "httpsPartout")
        verrouFantome = d.bool(forKey: "verrouFantome")
        verrouAppli = d.bool(forKey: "verrouAppli")
        sombreSites = d.bool(forKey: "sombreSites")
        youtubeArrierePlan = d.bool(forKey: "youtubeArrierePlan")
        fermetureAuto = FermetureAuto(rawValue: d.integer(forKey: "fermetureAuto")) ?? .semaine
        bulleRecherche = d.bool(forKey: "bulleRecherche")
        resumeAuto = d.bool(forKey: "resumeAuto")
        extensionBitwarden = d.bool(forKey: "extensionBitwarden")
        barreReductible = d.bool(forKey: "barreReductible")
        parSite = (d.data(forKey: "parSite")).flatMap { try? JSONDecoder().decode([String: ReglageSite].self, from: $0) } ?? [:]
    }

    /// Clé de site : domaine sans « www. » ni « m. ».
    static func cleSite(_ hote: String?) -> String? {
        guard var h = hote?.lowercased(), !h.isEmpty else { return nil }
        for p in ["www.", "m."] where h.hasPrefix(p) { h.removeFirst(p.count) }
        return h
    }
    func site(_ hote: String?) -> ReglageSite { Self.cleSite(hote).flatMap { parSite[$0] } ?? ReglageSite() }
    func modifierSite(_ hote: String?, _ change: (inout ReglageSite) -> Void) {
        guard let cle = Self.cleSite(hote) else { return }
        var s = parSite[cle] ?? ReglageSite()
        change(&s)
        parSite[cle] = s.estVide ? nil : s
    }
    func sombre(pour hote: String?) -> Bool { site(hote).sombre ?? sombreSites }

    static var moisCourant: String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
    var depenseDuMois: Double { depenseIA[Self.moisCourant] ?? 0 }
    func ajouterDepense(_ dollars: Double) { depenseIA[Self.moisCourant, default: 0] += dollars }
    var plafondAtteint: Bool { plafondIA > 0 && depenseDuMois >= plafondIA }

    /// Le blocage est-il coupé pour cet hôte (ou un domaine parent) ?
    func estAutorise(hote: String?) -> Bool {
        guard var h = hote?.lowercased(), !sitesAutorises.isEmpty else { return false }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return sitesAutorises.contains { h == $0 || h.hasSuffix("." + $0) }
    }
    func basculerAutorisation(hote: String) {
        var h = hote.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        if let i = sitesAutorises.firstIndex(of: h) { sitesAutorises.remove(at: i) } else { sitesAutorises.append(h) }
    }
}

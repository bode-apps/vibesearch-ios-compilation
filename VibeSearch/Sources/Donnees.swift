import Foundation
import Observation

/// Petit stockage JSON dans « Application Support », écrit en différé (jamais à chaque frappe).
@MainActor
struct FichierJSON<T: Codable> {
    let nom: String
    private var url: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(nom)
    }
    func lire() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func ecrire(_ valeur: T) {
        guard let data = try? JSONEncoder().encode(valeur) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func effacer() { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Historique

struct Visite: Codable, Identifiable, Hashable {
    var id: String { url }
    let url: String
    var titre: String
    var date: Date
    var nombre: Int
}

@MainActor
@Observable
final class Historique {
    static let partage = Historique()
    private(set) var visites: [Visite] = [] // la plus récente en premier
    @ObservationIgnored private let fichier = FichierJSON<[Visite]>(nom: "historique.json")
    @ObservationIgnored private var sale = false
    @ObservationIgnored private var prevu = false

    private init() { visites = fichier.lire() ?? [] }

    func visiter(url: URL, titre: String) {
        guard let s = url.scheme, s.hasPrefix("http") else { return }
        let cle = url.absoluteString
        var v = Visite(url: cle, titre: titre, date: .now, nombre: 1)
        if let i = visites.firstIndex(where: { $0.url == cle }) {
            v.nombre = visites[i].nombre + 1
            if titre.isEmpty { v.titre = visites[i].titre }
            visites.remove(at: i)
        }
        visites.insert(v, at: 0)
        if visites.count > 4000 { visites.removeLast(visites.count - 4000) }
        planifier()
    }

    func retirer(_ v: Visite) { visites.removeAll { $0.url == v.url }; planifier() }
    func retirerJour(_ jour: Date) {
        let cal = Calendar.current
        visites.removeAll { cal.isDate($0.date, inSameDayAs: jour) }
        planifier()
    }
    func toutEffacer(depuis: Date? = nil) {
        if let depuis { visites.removeAll { $0.date >= depuis } } else { visites = [] }
        planifier()
    }

    /// Sites les plus visités, calculés une fois puis gardés jusqu'à la prochaine visite.
    @ObservationIgnored private var cacheFrequents: [(hote: String, url: URL, titre: String)]?

    /// Sites les plus visités (pour la page d'accueil et les suggestions).
    func sitesFrequents(_ n: Int) -> [(hote: String, url: URL, titre: String)] {
        if let c = cacheFrequents { return Array(c.prefix(n)) }
        let tous = calculerFrequents()
        cacheFrequents = tous
        return Array(tous.prefix(n))
    }

    private func calculerFrequents() -> [(hote: String, url: URL, titre: String)] {
        var compte: [String: (Int, URL, String)] = [:]
        for v in visites.prefix(1500) {
            guard let u = URL(string: v.url), var h = u.host() else { continue }
            if h.hasPrefix("www.") { h.removeFirst(4) }
            let actuel = compte[h]
            compte[h] = ((actuel?.0 ?? 0) + v.nombre, actuel?.1 ?? URL(string: "https://\(u.host() ?? h)/")!, actuel?.2 ?? v.titre)
        }
        return compte.sorted { $0.value.0 > $1.value.0 }.prefix(80).map { ($0.key, $0.value.1, $0.value.2) }
    }

    private func planifier() {
        sale = true
        cacheFrequents = nil
        guard !prevu else { return }
        prevu = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.prevu = false
            self?.enregistrer()
        }
    }

    func enregistrer() {
        guard sale else { return }
        sale = false
        fichier.ecrire(visites)
    }
}

// MARK: - Favoris

struct Favori: Codable, Identifiable, Hashable {
    var id = UUID()
    var titre: String
    var url: String
}

@MainActor
@Observable
final class Favoris {
    static let partage = Favoris()
    var liste: [Favori] = [] { didSet { fichier.ecrire(liste) } }
    @ObservationIgnored private let fichier = FichierJSON<[Favori]>(nom: "favoris.json")

    private init() {
        liste = fichier.lire() ?? [
            Favori(titre: "YouTube", url: "https://m.youtube.com/"),
            Favori(titre: "Wikipédia", url: "https://fr.wikipedia.org/"),
            Favori(titre: "Le Monde", url: "https://www.lemonde.fr/"),
            Favori(titre: "Reddit", url: "https://www.reddit.com/")
        ]
    }

    func contient(_ url: URL?) -> Bool { guard let u = url?.absoluteString else { return false }; return liste.contains { $0.url == u } }
    func ajouter(url: URL, titre: String) {
        guard !contient(url) else { return }
        liste.append(Favori(titre: titre.isEmpty ? (url.host() ?? url.absoluteString) : titre, url: url.absoluteString))
    }
    func basculer(url: URL, titre: String) {
        if contient(url) { liste.removeAll { $0.url == url.absoluteString } } else { ajouter(url: url, titre: titre) }
    }
    func enregistrer() { fichier.ecrire(liste) }
}

// MARK: - Suggestions de la barre d'adresse

@MainActor
enum Suggestions {
    /// Sites connus proposés dès les premières lettres (« you » → youtube.com), comme sur PC.
    private static let connus = [
        "youtube.com", "google.com", "wikipedia.org", "reddit.com", "x.com", "instagram.com", "facebook.com", "twitch.tv",
        "amazon.fr", "leboncoin.fr", "lemonde.fr", "github.com", "netflix.com", "chatgpt.com", "claude.ai", "gmail.com",
        "tiktok.com", "linkedin.com", "spotify.com", "discord.com", "allocine.fr", "marmiton.org", "francetvinfo.fr", "ouest-france.fr",
        "bfmtv.com", "lequipe.fr", "doctolib.fr", "impots.gouv.fr", "ameli.fr", "sncf-connect.com", "vinted.fr", "cdiscount.com"
    ]

    struct Ligne: Identifiable, Hashable {
        var id: String { url.absoluteString }
        let titre: String
        let detail: String
        let url: URL
        let icone: String
    }

    static func pour(_ texte: String) -> [Ligne] {
        let t = texte.lowercased().trimmingCharacters(in: .whitespaces)
        guard t.count >= 1 else { return [] }
        var lignes: [Ligne] = []
        var vus = Set<String>()
        func ajouter(_ l: Ligne) {
            guard !vus.contains(l.url.absoluteString), lignes.count < 8 else { return }
            vus.insert(l.url.absoluteString)
            lignes.append(l)
        }
        // 1. Sites : favoris, historique, puis sites connus dont le nom commence par la saisie
        if !t.contains(" ") {
            for f in Favoris.partage.liste {
                guard let u = URL(string: f.url), let h = u.host()?.replacingOccurrences(of: "www.", with: ""), h.hasPrefix(t) || f.titre.lowercased().hasPrefix(t) else { continue }
                ajouter(Ligne(titre: f.titre, detail: h, url: u, icone: "star.fill"))
            }
            for s in Historique.partage.sitesFrequents(60) where s.hote.hasPrefix(t) || s.hote.hasPrefix("m." + t) {
                ajouter(Ligne(titre: s.hote, detail: s.titre, url: s.url, icone: "clock.arrow.circlepath"))
            }
            for c in connus where c.hasPrefix(t) {
                ajouter(Ligne(titre: c, detail: "Site", url: URL(string: "https://\(c)/")!, icone: "globe"))
            }
        }
        // 2. Pages de l'historique dont le titre ou l'adresse contient la saisie
        if t.count >= 2 {
            for v in Historique.partage.visites.prefix(2000) where v.titre.lowercased().contains(t) || v.url.lowercased().contains(t) {
                guard let u = URL(string: v.url) else { continue }
                ajouter(Ligne(titre: v.titre.isEmpty ? v.url : v.titre, detail: Adresse.courte(u), url: u, icone: "clock"))
                if lignes.count >= 6 { break }
            }
        }
        return lignes
    }
}

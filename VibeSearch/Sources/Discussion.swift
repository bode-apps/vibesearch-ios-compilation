import BackgroundTasks
import CryptoKit
import Foundation
import Network
import Observation
import UIKit
import UserNotifications

// Discussion chiffrée de bout en bout, compatible avec VibeSearch PC (même format, même relais).
// Secret partagé de 32 octets → HKDF-SHA256 (sel « vibesearch-chat-v1 ») → clé AES-256-GCM + noms de boîtes.
// Le relais (SurvieTikTok) ne voit que des octets chiffrés ; tout y est effacé à la lecture ou au bout de 24 h.

/// Un correspondant (une invitation = un contact ; l'iPhone a ses propres invitations).
struct ContactChat: Codable, Identifiable, Hashable {
    var id: String
    var nom: String
    var secret: Data
    /// « a » = a créé l'invitation, « b » = l'a rejointe.
    var role: String
    var creeLe: Date
    var luJusqua: Date
    /// Le correspondant a déjà écrit (invitation utilisée).
    var rejoint: Bool
}

/// Un message reçu ou envoyé (gardé 24 h au plus, comme sur PC).
struct MessageChat: Codable, Identifiable, Hashable {
    var id: String
    var contact: String
    var deMoi: Bool
    var de: String
    var date: Date
    var genre: String // text, link, tab, image
    var texte: String?
    var url: String?
    var titre: String?
    var image: Data?
}

enum CryptoChat {
    private static let sel = Data("vibesearch-chat-v1".utf8)

    static func deriver(_ secret: Data, _ info: String, _ octets: Int) -> Data {
        let k = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: sel, info: Data(info.utf8), outputByteCount: octets)
        return k.withUnsafeBytes { Data($0) }
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func boites(_ c: ContactChat) -> (lire: String, ecrire: String) {
        let versA = hex(deriver(c.secret, "box-to-a", 32))
        let versB = hex(deriver(c.secret, "box-to-b", 32))
        return c.role == "a" ? (versA, versB) : (versB, versA)
    }

    /// Code de vérification à comparer à voix haute avec le correspondant (« 1234 5678 9012 »).
    static func codeVerification(_ secret: Data) -> String {
        let d = deriver(secret, "verify", 8)
        let n = d.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } % 1_000_000_000_000
        let s = String(format: "%012llu", n)
        let c = Array(s)
        return "\(String(c[0 ..< 4])) \(String(c[4 ..< 8])) \(String(c[8 ..< 12]))"
    }

    static func idContact(_ secret: Data) -> String {
        "c" + String(hex(Data(SHA256.hash(data: Data("vibesearch-contact".utf8) + secret))).prefix(15))
    }

    static func invitation(_ secret: Data) -> String { "VS1-" + base64url(secret) }

    static func lireInvitation(_ texte: String) -> Data? {
        let t = texte.components(separatedBy: .whitespacesAndNewlines).joined()
        guard t.hasPrefix("VS1-") else { return nil }
        let corps = String(t.dropFirst(4))
        guard corps.count == 43, corps.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
              let d = deBase64url(corps), d.count == 32 else { return nil }
        return d
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func deBase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }

    static func chiffrer(_ clair: Data, secret: Data, boite: String) throws -> Data {
        let cle = SymmetricKey(data: deriver(secret, "aes-256-gcm", 32))
        let boite = try AES.GCM.seal(clair, using: cle, nonce: AES.GCM.Nonce(), authenticating: Data(boite.utf8))
        guard let c = boite.combined else { throw CocoaError(.coderInvalidValue) }
        return c
    }

    static func dechiffrer(_ donnees: Data, secret: Data, boite: String) -> Data? {
        guard donnees.count >= 29, let s = try? AES.GCM.SealedBox(combined: donnees) else { return nil }
        let cle = SymmetricKey(data: deriver(secret, "aes-256-gcm", 32))
        return try? AES.GCM.open(s, using: cle, authenticating: Data(boite.utf8))
    }
}

/// Client HTTP minimal vers le relais (HTTP sans TLS sur une adresse IP, que URLSession refuse
/// sous iOS) : connexion TCP directe. Le contenu est déjà chiffré de bout en bout.
enum RelaisChat {
    static let hote = "__HOTE_RELAIS__"
    static let chemin = "/vibesearch/relay.php"

    struct Erreur: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func requete(_ methode: String, boite: String, corps: Data? = nil, type: String? = nil) async throws -> (statut: Int, corps: Data) {
        var entete = "\(methode) \(chemin)?box=\(boite) HTTP/1.0\r\nHost: \(hote)\r\nUser-Agent: VibeSearch-iOS\r\nConnection: close\r\n"
        if let type { entete += "Content-Type: \(type)\r\n" }
        if let corps { entete += "Content-Length: \(corps.count)\r\n" }
        entete += "\r\n"
        var envoi = Data(entete.utf8)
        if let corps { envoi += corps }
        let brut = try await echanger(envoi)
        guard let fin = brut.range(of: Data("\r\n\r\n".utf8)) else { throw Erreur(message: "Réponse illisible du relais") }
        let tete = String(decoding: brut[..<fin.lowerBound], as: UTF8.self)
        let statut = Int(tete.split(separator: " ").dropFirst().first ?? "") ?? 0
        var corpsRecu = Data(brut[fin.upperBound...])
        if tete.lowercased().contains("transfer-encoding: chunked") { corpsRecu = dechunker(corpsRecu) }
        return (statut, corpsRecu)
    }

    private static func echanger(_ envoi: Data) async throws -> Data {
        let c = NWConnection(host: NWEndpoint.Host(hote), port: 80, using: .tcp)
        let file = DispatchQueue(label: "fr.vibe.search.relais")
        return try await withCheckedThrowingContinuation { suite in
            var recu = Data()
            var fini = false
            let terminer: (Result<Data, Error>) -> Void = { r in
                guard !fini else { return }
                fini = true
                c.cancel()
                suite.resume(with: r)
            }
            file.asyncAfter(deadline: .now() + 20) { terminer(.failure(Erreur(message: "Le relais ne répond pas"))) }
            func lire() {
                c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { donnees, _, complet, erreur in
                    if let donnees { recu += donnees }
                    if let erreur { terminer(recu.isEmpty ? .failure(erreur) : .success(recu)); return }
                    if complet { terminer(.success(recu)) } else { lire() }
                }
            }
            c.stateUpdateHandler = { etat in
                switch etat {
                case .ready:
                    c.send(content: envoi, completion: .contentProcessed { e in
                        if let e { terminer(.failure(e)) } else { lire() }
                    })
                case let .failed(e):
                    terminer(.failure(e))
                case .waiting:
                    terminer(.failure(Erreur(message: "Pas de connexion au relais")))
                default:
                    break
                }
            }
            c.start(queue: file)
        }
    }

    private static func dechunker(_ d: Data) -> Data {
        var sortie = Data()
        var i = d.startIndex
        while i < d.endIndex {
            guard let fl = d[i...].range(of: Data("\r\n".utf8)),
                  let taille = Int(String(decoding: d[i ..< fl.lowerBound], as: UTF8.self).split(separator: ";")[0].trimmingCharacters(in: .whitespaces), radix: 16),
                  taille > 0 else { break }
            let debut = fl.upperBound
            let fin = min(d.endIndex, debut + taille)
            sortie += d[debut ..< fin]
            i = min(d.endIndex, fin + 2)
        }
        return sortie
    }
}

/// État de la discussion : contacts (trousseau), messages (24 h), relève périodique.
@MainActor
@Observable
final class Discussion {
    static let partage = Discussion()
    static let tacheReleve = "fr.vibe.search.releve"

    private(set) var contacts: [ContactChat] = []
    private(set) var messages: [MessageChat] = []
    /// Nom affiché chez les correspondants.
    var monNom: String { didSet { UserDefaults.standard.set(monNom, forKey: "chatNom") } }
    /// Panneau ouvert sur ce contact : relève rapide, rien n'est « non lu ».
    var contactOuvert: String?
    var erreur: String?
    /// Dernier onglet reçu (bulle « Ouvrir »).
    var ongletRecu: MessageChat?
    @ObservationIgnored private var minuteur: Timer?
    @ObservationIgnored private var echecs = 0
    @ObservationIgnored private var enReleve = false
    @ObservationIgnored private let fichier = FichierJSON<[MessageChat]>(nom: "discussion.json")

    private init() {
        monNom = UserDefaults.standard.string(forKey: "chatNom") ?? "Bode"
        if let json = Trousseau.lire("chat-contacts"), let c = try? JSONDecoder().decode([ContactChat].self, from: Data(json.utf8)) { contacts = c }
        messages = fichier.lire() ?? []
        purger()
    }

    func nonLus(_ c: ContactChat) -> Int { messages.filter { $0.contact == c.id && !$0.deMoi && $0.date > c.luJusqua }.count }
    var totalNonLus: Int { contacts.reduce(0) { $0 + nonLus($1) } }
    func fil(_ c: ContactChat) -> [MessageChat] { messages.filter { $0.contact == c.id }.sorted { $0.date < $1.date } }

    private func enregistrerContacts() {
        if let d = try? JSONEncoder().encode(contacts) { Trousseau.ecrire("chat-contacts", String(decoding: d, as: UTF8.self)) }
    }

    private func enregistrerMessages() { fichier.ecrire(messages) }

    // MARK: Appairage

    /// Crée une invitation (on sera « a ») et renvoie le code à transmettre.
    func inviter(nom: String) -> String {
        var octets = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &octets)
        let secret = Data(octets)
        contacts.append(ContactChat(id: CryptoChat.idContact(secret), nom: nom.isEmpty ? "Contact" : nom, secret: secret, role: "a", creeLe: .now, luJusqua: .now, rejoint: false))
        enregistrerContacts()
        demarrer()
        demanderNotifications()
        return CryptoChat.invitation(secret)
    }

    /// Rejoint une invitation reçue (on sera « b »). Renvoie un message d'erreur, ou nil si c'est bon.
    func rejoindre(code: String, nom: String) -> String? {
        guard let secret = CryptoChat.lireInvitation(code) else { return "Code invalide : il commence par « VS1- » et fait 47 caractères." }
        let id = CryptoChat.idContact(secret)
        if contacts.contains(where: { $0.id == id }) { return "Cette invitation est déjà sur cet iPhone : collez-la sur l'AUTRE appareil." }
        contacts.append(ContactChat(id: id, nom: nom.isEmpty ? "Contact" : nom, secret: secret, role: "b", creeLe: .now, luJusqua: .now, rejoint: true))
        enregistrerContacts()
        demarrer()
        demanderNotifications()
        // Petit bonjour : prévient l'autre appareil que l'invitation est utilisée
        envoyer(texte: "👋 \(monNom) a rejoint la discussion depuis son iPhone.", a: id)
        return nil
    }

    func renommer(_ id: String, _ nom: String) {
        guard let i = contacts.firstIndex(where: { $0.id == id }), !nom.isEmpty else { return }
        contacts[i].nom = nom
        enregistrerContacts()
    }

    func supprimer(_ id: String) {
        contacts.removeAll { $0.id == id }
        messages.removeAll { $0.contact == id }
        enregistrerContacts()
        enregistrerMessages()
    }

    func marquerLu(_ id: String) {
        guard let i = contacts.firstIndex(where: { $0.id == id }) else { return }
        contacts[i].luJusqua = .now
        enregistrerContacts()
        UNUserNotificationCenter.current().setBadgeCount(totalNonLus) { _ in }
    }

    // MARK: Envoi

    func envoyer(texte: String, a id: String) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // Un texte qui n'est qu'une adresse devient un lien (comme sur PC)
        if !t.contains(" "), let u = URL(string: t), ["http", "https"].contains(u.scheme ?? "") {
            envoyerMessage(genre: "link", a: id, url: t)
        } else {
            envoyerMessage(genre: "text", a: id, texte: String(t.prefix(8000)))
        }
    }

    func envoyerOnglet(_ url: URL, titre: String, a id: String) {
        envoyerMessage(genre: "tab", a: id, url: url.absoluteString, titre: String(titre.prefix(500)))
    }

    func envoyerImage(_ image: UIImage, legende: String?, a id: String) {
        // Même compression que sur PC : on réduit jusqu'à passer sous la limite
        for (cote, qualite) in [(1600.0, 0.85), (1280, 0.78), (1024, 0.7), (800, 0.62)] {
            let echelle = min(1, cote / max(image.size.width, image.size.height))
            let taille = CGSize(width: image.size.width * echelle, height: image.size.height * echelle)
            let reduite = UIGraphicsImageRenderer(size: taille).image { _ in image.draw(in: CGRect(origin: .zero, size: taille)) }
            if let jpeg = reduite.jpegData(compressionQuality: qualite), jpeg.count * 4 / 3 < 4_400_000 {
                envoyerMessage(genre: "image", a: id, texte: legende, image: jpeg)
                return
            }
        }
        erreur = "Image trop lourde."
    }

    private func envoyerMessage(genre: String, a id: String, texte: String? = nil, url: String? = nil, titre: String? = nil, image: Data? = nil) {
        guard let c = contacts.first(where: { $0.id == id }) else { return }
        var octets = [UInt8](repeating: 0, count: 9)
        _ = SecRandomCopyBytes(kSecRandomDefault, 9, &octets)
        let idMessage = CryptoChat.base64url(Data(octets))
        let maintenant = Date()
        var fil: [String: Any] = ["v": 1, "id": idMessage, "from": String(monNom.prefix(40)), "at": Int(maintenant.timeIntervalSince1970 * 1000), "kind": genre]
        if let texte, !texte.isEmpty { fil["text"] = texte }
        if let url { fil["url"] = url }
        if let titre, !titre.isEmpty { fil["title"] = titre }
        if let image { fil["image"] = "data:image/jpeg;base64," + image.base64EncodedString() }
        let local = MessageChat(id: idMessage, contact: id, deMoi: true, de: monNom, date: maintenant, genre: genre, texte: texte, url: url, titre: titre, image: image)
        messages.append(local)
        enregistrerMessages()
        Task {
            do {
                let clair = try JSONSerialization.data(withJSONObject: fil)
                let boite = CryptoChat.boites(c).ecrire
                let chiffre = try CryptoChat.chiffrer(clair, secret: c.secret, boite: boite)
                let r = try await RelaisChat.requete("POST", boite: boite, corps: chiffre, type: "application/octet-stream")
                switch r.statut {
                case 200 ..< 300: erreur = nil
                case 413: erreur = "Message trop lourd pour le relais."
                case 429: erreur = "La boîte de \(c.nom) est pleine (il doit relever ses messages)."
                default: erreur = "Envoi refusé par le relais (\(r.statut))."
                }
            } catch {
                self.erreur = "Envoi impossible : \(error.localizedDescription)"
            }
        }
    }

    // MARK: Relève

    /// Relève périodique tant que l'appli est ouverte (3 s si une discussion est affichée, 20 s sinon).
    func demarrer() {
        guard !contacts.isEmpty else { return }
        minuteur?.invalidate()
        let delai = contactOuvert != nil ? 3.0 : min(120, 20 * pow(2, Double(min(echecs, 4))))
        minuteur = Timer.scheduledTimer(withTimeInterval: delai, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.relever()
                self.demarrer()
            }
        }
        if messages.isEmpty || echecs == 0 {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.relever()
            }
        }
    }

    func arreter() {
        minuteur?.invalidate()
        minuteur = nil
    }

    private struct Recu: Decodable { let id: String; let data: String }

    /// Relève toutes les boîtes. Renvoie les nouveaux messages reçus.
    @discardableResult
    func relever() async -> [MessageChat] {
        guard !enReleve else { return [] }
        enReleve = true
        defer { enReleve = false }
        purger()
        var nouveaux: [MessageChat] = []
        var ok = true
        for c in contacts {
            let boite = CryptoChat.boites(c).lire
            guard let r = try? await RelaisChat.requete("GET", boite: boite), r.statut == 200 else { ok = false; continue }
            guard let liste = try? JSONDecoder().decode([Recu].self, from: r.corps), !liste.isEmpty else { continue }
            for brut in liste {
                guard let donnees = Data(base64Encoded: brut.data),
                      let clair = CryptoChat.dechiffrer(donnees, secret: c.secret, boite: boite),
                      let m = decoder(clair, contact: c.id) else { continue }
                if messages.contains(where: { $0.id == m.id && $0.contact == c.id }) { continue }
                messages.append(m)
                nouveaux.append(m)
            }
            // Tout ce qui a été relevé est effacé du relais (même illisible), comme sur PC
            if let corps = try? JSONEncoder().encode(liste.map(\.id)) {
                _ = try? await RelaisChat.requete("DELETE", boite: boite, corps: corps, type: "application/json")
            }
            if let i = contacts.firstIndex(where: { $0.id == c.id }), !contacts[i].rejoint, nouveaux.contains(where: { $0.contact == c.id }) {
                contacts[i].rejoint = true
                enregistrerContacts()
            }
        }
        echecs = ok ? 0 : echecs + 1
        if !nouveaux.isEmpty {
            enregistrerMessages()
            for m in nouveaux where m.genre == "tab" {
                // Onglet envoyé : ouvert en arrière-plan (comme sur PC) et signalé par une bulle
                if let u = URL(string: m.url ?? "") { Navigateur.partage.ouvrir(url: u, nouvelOnglet: true, arrierePlan: true, fantome: false) }
                ongletRecu = m
            }
            if let ouvert = contactOuvert { marquerLu(ouvert) }
            UNUserNotificationCenter.current().setBadgeCount(totalNonLus) { _ in }
        }
        return nouveaux
    }

    private func decoder(_ clair: Data, contact: String) -> MessageChat? {
        guard let j = try? JSONSerialization.jsonObject(with: clair) as? [String: Any],
              j["v"] as? Int == 1, let id = j["id"] as? String, (6 ... 64).contains(id.count),
              let genre = j["kind"] as? String, ["text", "link", "tab", "image"].contains(genre),
              let at = j["at"] as? Double else { return nil }
        let date = Date(timeIntervalSince1970: at / 1000)
        // Pas plus vieux que 24 h, pas plus de 10 min dans le futur
        guard date > Date.now.addingTimeInterval(-86400), date < Date.now.addingTimeInterval(600) else { return nil }
        let texte = (j["text"] as? String).map { String($0.prefix(8000)) }
        let url = (j["url"] as? String).flatMap { $0.hasPrefix("http://") || $0.hasPrefix("https://") ? String($0.prefix(4000)) : nil }
        var image: Data?
        if let i = j["image"] as? String, i.count <= 4_500_000, let virgule = i.firstIndex(of: ","), i.hasPrefix("data:image/") {
            image = Data(base64Encoded: String(i[i.index(after: virgule)...]))
        }
        switch genre {
        case "text": guard texte?.isEmpty == false else { return nil }
        case "link", "tab": guard url != nil else { return nil }
        default: guard image != nil else { return nil }
        }
        return MessageChat(id: id, contact: contact, deMoi: false, de: String((j["from"] as? String ?? "?").prefix(40)), date: date,
                           genre: genre, texte: texte, url: url, titre: (j["title"] as? String).map { String($0.prefix(500)) }, image: image)
    }

    /// Plus rien au-delà de 24 h (comme sur PC).
    private func purger() {
        let avant = messages.count
        messages.removeAll { $0.date < Date.now.addingTimeInterval(-86400) }
        if messages.count != avant { enregistrerMessages() }
    }

    // MARK: Arrière-plan et notifications

    private func demanderNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Relève occasionnelle quand l'appli est fermée (iOS décide du moment, au mieux toutes les 15 min).
    static func programmerReleve() {
        let r = BGAppRefreshTaskRequest(identifier: tacheReleve)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// Exécutée par iOS en arrière-plan : relève, puis notification locale pour chaque message.
    func releverEnArrierePlan() async {
        let nouveaux = await relever()
        for m in nouveaux.prefix(5) {
            let n = UNMutableNotificationContent()
            n.title = m.de
            n.body = m.genre == "image" ? "📷 Photo" : (m.genre == "tab" ? "🔗 \(m.titre ?? m.url ?? "Onglet")" : (m.texte ?? m.url ?? ""))
            n.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: m.id, content: n, trigger: nil))
        }
    }
}

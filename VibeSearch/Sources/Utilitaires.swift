import Foundation
import UIKit

/// Interprétation du texte tapé dans la barre d'adresse.
enum Adresse {
    @MainActor
    static func interpreter(_ texte: String) -> URL? {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        // Adresse complète
        if let u = URL(string: t), let s = u.scheme?.lowercased(), ["http", "https", "about", "data", "file"].contains(s) { return u }
        // « exemple.fr », « exemple.fr/page », « localhost:3000 », « 192.168.1.1 »
        if !t.contains(" "), let u = URL(string: "https://" + t), let h = u.host(), estHote(h) {
            if h == "localhost" || h.allSatisfy({ $0.isNumber || $0 == "." }) { return URL(string: "http://" + t) }
            return u
        }
        return Reglages.partage.moteur.adresse(pour: t)
    }

    private static func estHote(_ h: String) -> Bool {
        if h == "localhost" || estIPv4(h) { return true }
        let parties = h.split(separator: ".")
        guard parties.count >= 2, let tld = parties.last, tld.count >= 2 else { return false }
        return tld.allSatisfy { $0.isLetter } || h.allSatisfy { $0.isNumber || $0 == "." }
    }

    static func estIPv4(_ h: String) -> Bool {
        let p = h.split(separator: ".", omittingEmptySubsequences: false)
        return p.count == 4 && p.allSatisfy { Int($0).map { (0 ... 255).contains($0) } ?? false }
    }

    /// Adresse locale ou IP : pas de passage forcé en HTTPS.
    static func estLocale(_ h: String) -> Bool {
        h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".localhost") || estIPv4(h) || h.contains(":") || !h.contains(".")
    }

    /// Paramètres de pistage retirés des adresses (liens partagés, publicités, réseaux sociaux).
    private static let pisteurs: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id", "igshid", "igsh",
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "wickedid", "rb_clickid",
        "s_cid", "ef_id", "_openstat", "spm", "scm", "ncid", "sr_share", "ref_src", "ref_url", "at_medium", "at_campaign"
    ]

    /// Adresse sans paramètres de pistage (nil si rien à retirer).
    static func nettoyee(_ url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = c.queryItems, !items.isEmpty else { return nil }
        let hote = url.host()?.lowercased() ?? ""
        let gardes = items.filter { item in
            let n = item.name.lowercased()
            if n.hasPrefix("utm_") || n.hasPrefix("pk_") && n != "pk" || pisteurs.contains(n) { return false }
            // « si » = identifiant de partage YouTube / Spotify (relie le partage à votre compte)
            if n == "si", hote.hasSuffix("youtube.com") || hote == "youtu.be" || hote.hasSuffix("spotify.com") { return false }
            return true
        }
        guard gardes.count != items.count else { return nil }
        c.queryItems = gardes.isEmpty ? nil : gardes
        return c.url
    }

    /// Adresse à copier / partager : nettoyée si le réglage est actif.
    @MainActor
    static func aPartager(_ url: URL) -> URL {
        Reglages.partage.nettoyerLiens ? (nettoyee(url) ?? url) : url
    }

    /// Adresse lisible pour la barre (sans « https:// » ni « www. »).
    static func courte(_ url: URL?) -> String {
        guard let url else { return "" }
        var h = url.host() ?? url.absoluteString
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }
}

/// Présentation de vues UIKit au-dessus de l'interface SwiftUI (partage, boîtes de dialogue).
@MainActor
enum Presentateur {
    static var sommet: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.keyWindow?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

@MainActor
enum Partage {
    static func presenter(_ elements: [Any]) {
        guard let vc = Presentateur.sommet else { return }
        let a = UIActivityViewController(activityItems: elements, applicationActivities: nil)
        a.popoverPresentationController?.sourceView = vc.view
        a.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 80, width: 1, height: 1)
        vc.present(a, animated: true)
    }
}

/// alert() / confirm() / prompt() des pages, affichés avec le nom du site.
@MainActor
enum Dialogue {
    static func alerte(_ message: String, hote: String) async {
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            let a = UIAlertController(title: hote, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in suite.resume() })
            presenter(a) { suite.resume() }
        }
    }

    static func confirmer(_ message: String, hote: String) async -> Bool {
        await withCheckedContinuation { suite in
            let a = UIAlertController(title: hote, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in suite.resume(returning: false) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in suite.resume(returning: true) })
            presenter(a) { suite.resume(returning: false) }
        }
    }

    static func saisir(_ message: String, defaut: String?, hote: String) async -> String? {
        await withCheckedContinuation { suite in
            let a = UIAlertController(title: hote, message: message, preferredStyle: .alert)
            a.addTextField { $0.text = defaut }
            a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in suite.resume(returning: nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { [weak a] _ in suite.resume(returning: a?.textFields?.first?.text ?? "") })
            presenter(a) { suite.resume(returning: nil) }
        }
    }

    /// Anti-boucle : au-delà de 3 boîtes en 10 s, les suivantes sont refusées d'office.
    private static var recentes: [Date] = []

    /// Présente l'alerte ; si c'est impossible (rien à l'écran, feuille en train de se fermer,
    /// avalanche d'alertes), `sinon` débloque immédiatement la page.
    private static func presenter(_ a: UIAlertController, sinon: () -> Void) {
        recentes = recentes.filter { Date.now.timeIntervalSince($0) < 10 } + [.now]
        guard recentes.count <= 3, let vc = Presentateur.sommet, !vc.isBeingDismissed, !vc.isBeingPresented,
              vc.presentedViewController == nil else { sinon(); return }
        vc.present(a, animated: true)
    }
}

extension Date {
    /// « il y a 5 min », « hier »…
    var relatif: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: .now)
    }
}

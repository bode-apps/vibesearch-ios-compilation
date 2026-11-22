import Foundation
import WebKit

/// Fabrique des configurations WebKit des onglets : stockage (normal ou Fantôme), scripts de page,
/// canaux de messages. Les scripts sont lus une seule fois puis partagés par tous les onglets.
@MainActor
enum FabriqueWeb {
    /// Monde JavaScript isolé de VibeSearch : la page ne voit ni nos variables ni nos canaux.
    static let mondeVibe = WKContentWorld.world(name: "vibe")
    /// Nom secret des évènements du bouclier (page → monde isolé), tiré à chaque lancement.
    static let evenement = "v" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(14).lowercased()
    /// Graines du bouclier : une pour la navigation normale, une autre pour la session Fantôme
    /// (un site ne peut pas relier les deux identités par leur empreinte).
    private static let graineNormale = UInt32.random(in: 1 ... UInt32.max)
    private static var graineFantome = UInt32.random(in: 1 ... UInt32.max)

    /// Stockage du mode Fantôme : uniquement en mémoire, détruit avec les onglets Fantôme.
    private static var magasinFantome: WKWebsiteDataStore?
    static func stockageFantome() -> WKWebsiteDataStore {
        if let m = magasinFantome { return m }
        let m = WKWebsiteDataStore.nonPersistent()
        magasinFantome = m
        return m
    }
    /// Fin de la session Fantôme : plus aucune trace (cookies, cache, stockage local), nouvelle empreinte.
    static func detruireFantome() {
        magasinFantome = nil
        graineFantome = UInt32.random(in: 1 ... UInt32.max)
        scriptBouclierFantome = nil
    }

    static func ressource(_ nom: String, _ ext: String = "js") -> String {
        guard let url = Bundle.main.url(forResource: nom, withExtension: ext),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    private static let sourceBouclier = ressource("bouclier").replacingOccurrences(of: "__EVENEMENT__", with: evenement)
    private static func bouclier(graine: UInt32) -> WKUserScript {
        WKUserScript(source: sourceBouclier.replacingOccurrences(of: "__GRAINE__", with: String(graine)),
                     injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }
    private static let scriptBouclierNormal = bouclier(graine: graineNormale)
    private static var scriptBouclierFantome: WKUserScript?
    private static let scriptRelaisBouclier = WKUserScript(
        source: ressource("relais-bouclier").replacingOccurrences(of: "__EVENEMENT__", with: evenement),
        injectionTime: .atDocumentStart, forMainFrameOnly: false, in: mondeVibe)
    private static let scriptConsentement = WKUserScript(
        source: ressource("consentement-page"), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: mondeVibe)
    private static let scriptYoutube = WKUserScript(
        source: ressource("youtube"), injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: mondeVibe)
    private static let scriptYoutubeSansPubs = WKUserScript(
        source: "window.__vibeSansPubs = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true, in: mondeVibe)
    private static func scriptYoutubePage(arrierePlan: Bool) -> WKUserScript {
        WKUserScript(source: ressource("youtube-page").replacingOccurrences(of: "__ARRIERE_PLAN__", with: arrierePlan ? "true" : "false")
                        .replacingOccurrences(of: "__EVENEMENT__", with: evenement),
                     injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
    }
    private static let scriptYoutubePageAvec = scriptYoutubePage(arrierePlan: true)
    private static let scriptYoutubePageSans = scriptYoutubePage(arrierePlan: false)
    private static let scriptSombre = WKUserScript(
        source: ressource("sombre"), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: mondeVibe)
    /// Extraction du texte de la page pour l'IA, du mode lecture et de la traduction.
    static let sourceLecture = ressource("lecture")
    static let sourceLecteur = ressource("lecteur")
    static let sourceRecherche = ressource("recherche")
    static let sourceTraduction = ressource("traduction")

    /// Installe les scripts selon les réglages et le site (comme les listes de blocage, un changement
    /// s'applique au chargement suivant de la page).
    static func installerScripts(_ ucc: WKUserContentController, hote: String?, fantome: Bool) {
        let r = Reglages.partage
        ucc.removeAllUserScripts()
        let protege = !r.estAutorise(hote: hote)
        if r.bouclierEmpreinte && protege {
            if fantome {
                let s = scriptBouclierFantome ?? bouclier(graine: graineFantome)
                scriptBouclierFantome = s
                ucc.addUserScript(s)
            } else {
                ucc.addUserScript(scriptBouclierNormal)
            }
            ucc.addUserScript(scriptRelaisBouclier)
        }
        if r.refuserCookies && protege { ucc.addUserScript(scriptConsentement) }
        let youtube = hote.map { $0 == "youtube.com" || $0.hasSuffix(".youtube.com") } ?? true
        if youtube {
            if r.pubsYouTube || r.sauterSponsors {
                if r.pubsYouTube { ucc.addUserScript(scriptYoutubeSansPubs) }
                ucc.addUserScript(scriptYoutube)
            }
            ucc.addUserScript(r.youtubeArrierePlan ? scriptYoutubePageAvec : scriptYoutubePageSans)
        }
        if r.sombre(pour: hote) { ucc.addUserScript(scriptSombre) }
    }

    /// Contrôleur de contenu propre à un onglet (scripts, canaux, listes de blocage).
    static func controleur(pour onglet: Onglet, hote: String?) -> WKUserContentController {
        let ucc = WKUserContentController()
        brancherCanaux(ucc, onglet: onglet)
        installerScripts(ucc, hote: hote, fantome: onglet.fantome)
        Bloqueur.partage.appliquer(sur: ucc, hote: hote)
        return ucc
    }

    static func configuration(pour onglet: Onglet) -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = onglet.fantome ? stockageFantome() : .default()
        c.allowsInlineMediaPlayback = true
        c.allowsPictureInPictureMediaPlayback = true
        c.allowsAirPlayForMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = .audio
        c.dataDetectorTypes = [.phoneNumber, .link]
        c.defaultWebpagePreferences.preferredContentMode = .mobile
        c.preferences.isFraudulentWebsiteWarningEnabled = true
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        c.applicationNameForUserAgent = agentUtilisateur
        c.userContentController = controleur(pour: onglet, hote: onglet.url?.host())
        Extensions.poser(sur: c, fantome: onglet.fantome)
        return c
    }

    /// Fin de l'identité navigateur : celle de Safari pour la VRAIE version d'iOS de l'appareil
    /// (une version figée trahirait VibeSearch et peut gêner certains sites).
    static let agentUtilisateur: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = v.minorVersion == 0 ? "\(v.majorVersion).0" : "\(v.majorVersion).\(v.minorVersion)"
        return "Version/\(version) Mobile/15E148 Safari/604.1"
    }()

    /// Canaux page → appli, tous dans le monde isolé (invisibles pour les sites).
    /// Les relais gardent une référence FAIBLE vers l'onglet.
    static func brancherCanaux(_ ucc: WKUserContentController, onglet: Onglet) {
        ucc.removeAllScriptMessageHandlers()
        ucc.add(RelaisSimple(onglet: onglet), contentWorld: mondeVibe, name: "vibeBouclier")
        let reponse = RelaisReponse(onglet: onglet)
        ucc.addScriptMessageHandler(reponse, contentWorld: mondeVibe, name: "vibeConsent")
        ucc.addScriptMessageHandler(reponse, contentWorld: mondeVibe, name: "vibeYoutube")
    }
}

/// Messages sans réponse (bouclier : tentative d'empreinte repérée).
@MainActor
final class RelaisSimple: NSObject, WKScriptMessageHandler {
    weak var onglet: Onglet?
    init(onglet: Onglet) { self.onglet = onglet }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let genre = message.body as? String, genre.count < 20 else { return }
        onglet?.signalerEmpreinte(genre)
    }
}

/// Messages avec réponse (la page attend le résultat de sa promesse).
@MainActor
final class RelaisReponse: NSObject, WKScriptMessageHandlerWithReply {
    weak var onglet: Onglet?
    init(onglet: Onglet) { self.onglet = onglet }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let corps = message.body as? [String: Any], let type = corps["type"] as? String else { return (nil, nil) }
        switch message.name {
        case "vibeConsent":
            return (await Consentement.partage.recevoir(type: type, corps: corps, message: message, onglet: onglet), nil)
        case "vibeYoutube":
            guard type == "segments", let id = corps["id"] as? String else { return (nil, nil) }
            let segs = await SponsorBlock.partage.segments(video: id)
            return (segs.map { ["debut": $0.debut, "fin": $0.fin, "categorie": $0.categorie, "uuid": $0.uuid] as [String: Any] }, nil)
        default:
            return (nil, nil)
        }
    }
}

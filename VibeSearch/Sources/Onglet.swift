import Observation
import UIKit
import WebKit

/// Un onglet. Sa vue WebKit n'existe que lorsqu'il est « vivant » : un onglet endormi ne garde
/// que son adresse, son historique (interactionState) et un aperçu, pour économiser la mémoire.
@MainActor
@Observable
final class Onglet: NSObject, Identifiable {
    let id: UUID
    let fantome: Bool

    var titre = ""
    var url: URL?
    var progression = 0.0
    var enChargement = false
    var peutReculer = false
    var peutAvancer = false
    var securise = true
    var apercu: UIImage?
    var dernierAcces = Date()
    /// Groupe d'onglets (nil = aucun).
    var groupe: String?
    /// Tentatives d'empreinte repérées sur la page en cours (canvas, webgl, audio, position).
    var empreintes: Set<String> = []
    var cookiesRefuses = 0
    /// Page traduite (bouton « Original » dans le menu).
    var traduite = false
    /// Page d'accueil VibeSearch (aucune page web chargée).
    var estAccueil: Bool { url == nil && vue == nil }

    @ObservationIgnored private(set) var vue: WKWebView?
    @ObservationIgnored var etatSauve: Data?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// Site pour lequel listes et scripts ont été posés (clé de site + autorisation + sombre).
    @ObservationIgnored private var cleAppliquee: String?
    /// HTTPS tenté d'office sur cet hôte (repli en HTTP s'il échoue).
    @ObservationIgnored private var tentativeHTTPS: String?
    @ObservationIgnored private var dernierDefilement: CGFloat = 0
    /// Hôtes qui ne savent pas faire HTTPS (pour la session seulement).
    private static var httpPermis: Set<String> = []

    var hote: String? { url?.host() }
    var titreAffiche: String {
        if !titre.isEmpty { return titre }
        if let h = hote { return h }
        return estAccueil ? "Nouvel onglet" : "Chargement…"
    }
    /// Version ordinateur du site (mémorisée par site).
    var versionOrdinateur: Bool { Reglages.partage.site(hote).ordinateur }

    /// Page de résultats d'un moteur de recherche connu (pour la réponse IA).
    var estPageRecherche: Bool {
        guard let u = url, let h = u.host()?.lowercased(),
              let q = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" || $0.name == "query" })?.value,
              !q.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let p = u.path
        return (h.contains("google.") && p == "/search") || h == "duckduckgo.com" || h == "html.duckduckgo.com"
            || (h == "search.brave.com" && p == "/search") || (h.hasSuffix("bing.com") && p == "/search")
            || (h.hasSuffix("startpage.com") && p.contains("search"))
    }
    var estVideoYoutube: Bool {
        guard let u = url, let h = u.host(), h == "youtube.com" || h.hasSuffix(".youtube.com") else { return false }
        return u.path == "/watch" || u.path.hasPrefix("/shorts/")
    }

    init(id: UUID = UUID(), fantome: Bool, url: URL? = nil, titre: String = "", etat: Data? = nil, groupe: String? = nil) {
        self.id = id
        self.fantome = fantome
        self.url = url
        self.titre = titre
        self.etatSauve = etat
        self.groupe = groupe
        super.init()
    }

    // MARK: - Cycle de vie de la vue

    /// Vue WebKit de l'onglet, créée (ou réveillée) si besoin.
    /// `reprendre` : recharge la page (ou restaure l'historique) à la création. `charger` passe `false`.
    @discardableResult
    func vueActive(configuration: WKWebViewConfiguration? = nil, reprendre: Bool = true) -> WKWebView {
        if let v = vue { return v }
        let hoteInitial = url?.host()
        if let configuration {
            // Fenêtre ouverte par une page : WebKit impose sa configuration (même stockage que l'ouvreur),
            // mais elle partagerait le contrôleur de contenu de l'ouvreur → on lui en donne un à elle.
            configuration.userContentController = FabriqueWeb.controleur(pour: self, hote: hoteInitial)
        }
        let v = WKWebView(frame: .zero, configuration: configuration ?? FabriqueWeb.configuration(pour: self))
        v.navigationDelegate = self
        v.uiDelegate = self
        v.allowsBackForwardNavigationGestures = true
        v.allowsLinkPreview = true
        v.isFindInteractionEnabled = true
        v.isOpaque = false
        v.isInspectable = false
        v.backgroundColor = UIColor(Theme.fond0)
        v.scrollView.backgroundColor = UIColor(Theme.fond0)
        v.scrollView.contentInsetAdjustmentBehavior = .automatic
        v.scrollView.keyboardDismissMode = .interactive
        let rafraichir = UIRefreshControl()
        rafraichir.tintColor = UIColor(Theme.accent)
        rafraichir.addAction(UIAction { [weak self, weak rafraichir] _ in
            self?.vue?.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { rafraichir?.endRefreshing() }
        }, for: .valueChanged)
        v.scrollView.refreshControl = rafraichir
        observer(v)
        vue = v
        cleAppliquee = nil
        if configuration == nil {
            // Les listes et scripts sont déjà posés pour ce site par FabriqueWeb.configuration
            cleAppliquee = cle(pour: hoteInitial)
        }
        if configuration == nil && reprendre {
            if let etat = etatSauve {
                etatSauve = nil
                // Restauration seulement quand le bloqueur est prêt : pas une page sans protection
                Bloqueur.partage.quandPret { [weak self, weak v] in
                    guard let self, let v else { return }
                    self.appliquerSite(hote: self.url?.host())
                    v.interactionState = etat
                }
            } else if let url {
                charger(url)
            }
        }
        return v
    }

    private func observer(_ v: WKWebView) {
        observations = [
            v.observe(\.title, options: [.new]) { [weak self] v, _ in MainActor.assumeIsolated {
                guard let self else { return }
                self.titre = v.title ?? ""
                Extensions.changement(self, titre: true)
            } },
            v.observe(\.url, options: [.new]) { [weak self] v, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let u = v.url, u.host() != self.url?.host() {
                        self.empreintes = []
                        self.cookiesRefuses = 0
                    }
                    if let u = v.url { self.url = u }
                    Extensions.changement(self, adresse: true)
                }
            },
            v.observe(\.estimatedProgress, options: [.new]) { [weak self] v, _ in MainActor.assumeIsolated { self?.progression = v.estimatedProgress } },
            v.observe(\.isLoading, options: [.new]) { [weak self] v, _ in MainActor.assumeIsolated {
                guard let self else { return }
                self.enChargement = v.isLoading
                Extensions.changement(self, chargement: true)
            } },
            v.observe(\.canGoBack, options: [.new]) { [weak self] v, _ in MainActor.assumeIsolated { self?.peutReculer = v.canGoBack } },
            v.observe(\.canGoForward, options: [.new]) { [weak self] v, _ in MainActor.assumeIsolated { self?.peutAvancer = v.canGoForward } },
            v.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] v, _ in MainActor.assumeIsolated { self?.securise = v.hasOnlySecureContent } },
            // Défilement : la barre se réduit en descendant, revient en remontant ou en haut de page
            v.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                MainActor.assumeIsolated { self?.defilement(sv) }
            }
        ]
    }

    private func defilement(_ sv: UIScrollView) {
        guard Reglages.partage.barreReductible, Navigateur.partage.actif === self else { return }
        let y = sv.contentOffset.y + sv.adjustedContentInset.top
        let delta = y - dernierDefilement
        if y <= 10 {
            Navigateur.partage.reduireBarre(false)
        } else if sv.isTracking || sv.isDecelerating {
            if delta > 14 && y > 80 { Navigateur.partage.reduireBarre(true) } else if delta < -24 { Navigateur.partage.reduireBarre(false) }
        }
        if abs(delta) > 14 || y <= 10 { dernierDefilement = y }
    }

    /// Endort l'onglet : garde l'historique et un aperçu, libère le processus web.
    func endormir() {
        guard let v = vue else { return }
        etatSauve = v.interactionState as? Data
        if let u = v.url { url = u }
        observations = []
        v.stopLoading()
        v.navigationDelegate = nil
        v.uiDelegate = nil
        v.configuration.userContentController.removeAllScriptMessageHandlers()
        v.removeFromSuperview()
        vue = nil
        cleAppliquee = nil
        enChargement = false
        traduite = false
    }

    /// État à enregistrer pour la session (onglet vivant ou endormi).
    var etatPourSession: Data? { (vue?.interactionState as? Data) ?? etatSauve }

    // MARK: - Navigation

    func charger(_ url: URL) {
        self.url = url
        let v = vueActive(reprendre: false)
        Bloqueur.partage.quandPret { [weak self, weak v] in
            guard let self, let v else { return }
            self.appliquerSite(hote: url.host())
            v.load(URLRequest(url: url))
        }
    }

    func recharger() {
        if let v = vue { v.reload() } else if let url { charger(url) }
    }

    func reculer() { vue?.goBack() }
    func avancer() { vue?.goForward() }
    func arreter() { vue?.stopLoading() }

    /// Prend un petit aperçu pour la grille des onglets (seulement l'onglet affiché).
    func capturer() {
        guard let v = vue, v.window != nil, v.bounds.width > 0 else { return }
        let c = WKSnapshotConfiguration()
        c.snapshotWidth = NSNumber(value: 360)
        c.afterScreenUpdates = false
        v.takeSnapshot(with: c) { [weak self] image, _ in
            MainActor.assumeIsolated { if let image { self?.apercu = image } }
        }
    }

    func signalerEmpreinte(_ genre: String) { empreintes.insert(genre) }

    /// Exécute un script dans le monde isolé de VibeSearch et renvoie son résultat texte.
    func executer(_ source: String) async -> String? {
        guard let v = vue else { return nil }
        return await withCheckedContinuation { suite in
            v.evaluateJavaScript(source, in: nil, in: FabriqueWeb.mondeVibe) { res in
                if case let .success(val) = res { suite.resume(returning: val as? String) } else { suite.resume(returning: nil) }
            }
        }
    }

    /// Appelle une fonction asynchrone dans le monde de la PAGE (sous-titres YouTube, image dans l'image).
    func executerDansPage(_ corps: String) async -> String? {
        guard let v = vue else { return nil }
        return await withCheckedContinuation { suite in
            v.callAsyncJavaScript(corps, arguments: [:], in: nil, in: .page) { res in
                if case let .success(val) = res { suite.resume(returning: val as? String) } else { suite.resume(returning: nil) }
            }
        }
    }

    // MARK: - Réglages par site

    private func cle(pour hote: String?) -> String {
        let r = Reglages.partage
        return "\(Reglages.cleSite(hote) ?? "")|\(r.estAutorise(hote: hote))|\(r.sombre(pour: hote))"
    }

    /// Pose les listes de blocage et les scripts selon le site (protection coupée si l'utilisateur
    /// l'a autorisé, mode sombre par site…). Ne fait rien si c'est déjà le cas.
    private func appliquerSite(hote: String?) {
        guard let v = vue else { return }
        let c = cle(pour: hote)
        guard c != cleAppliquee else { return }
        cleAppliquee = c
        let ucc = v.configuration.userContentController
        Bloqueur.partage.appliquer(sur: ucc, hote: hote)
        FabriqueWeb.installerScripts(ucc, hote: hote, fantome: fantome)
    }

    /// Réglages changés : listes et scripts reposés (effet au prochain chargement de la page).
    func reappliquerBlocage() {
        cleAppliquee = nil
        appliquerSite(hote: hote)
    }

    func basculerVersionOrdinateur() {
        Reglages.partage.modifierSite(hote) { $0.ordinateur.toggle() }
        recharger()
    }

    func zoomer(_ pas: Double?) {
        let actuel = Reglages.partage.site(hote).zoom
        let nouveau = pas.map { min(3, max(0.5, ((actuel + $0) * 100).rounded() / 100)) } ?? 1
        Reglages.partage.modifierSite(hote) { $0.zoom = nouveau }
        vue?.pageZoom = nouveau
    }

    func basculerSombre() {
        let actuel = Reglages.partage.sombre(pour: hote)
        Reglages.partage.modifierSite(hote) { s in
            s.sombre = !actuel == Reglages.partage.sombreSites ? nil : !actuel
        }
        reappliquerBlocage()
        recharger()
    }
}

// MARK: - WKNavigationDelegate
// Variantes « async » des méthodes de WebKit : pas de piège de signature de bloc (@MainActor/@Sendable).

extension Onglet: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = action.request.url else { return (.allow, preferences) }
        let schema = url.scheme?.lowercased() ?? ""
        // Liens vers d'autres applis (téléphone, mail, App Store, Plans…) : seulement sur un VRAI toucher,
        // jamais sur une redirection publicitaire
        if !["http", "https", "about", "blob", "data", "file"].contains(schema) {
            if action.navigationType == .linkActivated { _ = await UIApplication.shared.open(url) }
            return (.cancel, preferences)
        }
        if action.shouldPerformDownload { return (.download, preferences) }
        guard action.targetFrame?.isMainFrame == true else { return (.allow, preferences) }

        let r = Reglages.partage
        let hote = url.host()?.lowercased() ?? ""
        // Adresse améliorée : sans pisteurs, en HTTPS
        var cible = url
        if r.nettoyerLiens, action.request.httpMethod ?? "GET" == "GET", let propre = Adresse.nettoyee(cible) { cible = propre }
        if r.httpsPartout, schema == "http", !Adresse.estLocale(hote), !Self.httpPermis.contains(hote) {
            if tentativeHTTPS == hote {
                // Le site renvoie lui-même vers HTTP : il ne sait pas faire autrement
                Self.httpPermis.insert(hote)
            } else if var c = URLComponents(url: cible, resolvingAgainstBaseURL: false) {
                c.scheme = "https"
                if c.port == 80 { c.port = nil }
                if let u = c.url { cible = u }
                tentativeHTTPS = hote
            }
        }
        if cible != url {
            webView.load(URLRequest(url: cible))
            return (.cancel, preferences)
        }
        appliquerSite(hote: hote)
        preferences.preferredContentMode = r.site(hote).ordinateur ? .desktop : .mobile
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor reponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        // Téléchargement seulement pour la page principale : une iframe (pub…) ne peut pas en imposer un
        guard reponse.isForMainFrame else { return reponse.canShowMIMEType ? .allow : .cancel }
        let http = reponse.response as? HTTPURLResponse
        let piece = (http?.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().hasPrefix("attachment")
        return (piece || !reponse.canShowMIMEType) ? .download : .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        Telechargements.partage.suivre(download, fantome: fantome)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Telechargements.partage.suivre(download, fantome: fantome)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let h = webView.url?.host()?.lowercased(), h == tentativeHTTPS { tentativeHTTPS = nil }
        let zoom = Reglages.partage.site(webView.url?.host()).zoom
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        traduite = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if estPageRecherche { ResumeRecherche.partage.lancer(pour: self) }
        guard !fantome, let u = webView.url else { return }
        Historique.partage.visiter(url: u, titre: webView.title ?? "")
        Navigateur.partage.enregistrerSessionPlusTard()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        let echouee = e.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        // HTTPS tenté d'office mais refusé par le site : repli en HTTP (une seule fois par site et par session)
        if let h = tentativeHTTPS, let u = echouee, u.scheme == "https", u.host()?.lowercased() == h,
           e.domain == NSURLErrorDomain, e.code != NSURLErrorCancelled, var c = URLComponents(url: u, resolvingAgainstBaseURL: false) {
            Self.httpPermis.insert(h)
            tentativeHTTPS = nil
            c.scheme = "http"
            if let http = c.url { webView.load(URLRequest(url: http)) }
            return
        }
        // Annulation volontaire, téléchargement ou blocage par nos listes : pas de page d'erreur
        guard e.code != NSURLErrorCancelled, e.code != 102, e.code != 104 else { return }
        let texte = e.localizedDescription.replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <meta name=viewport content="width=device-width,initial-scale=1"><body style="background:#05040e;color:#eeebff;font:17px -apple-system;display:grid;place-items:center;height:90vh;text-align:center;margin:0">
        <div><div style="font-size:54px">🛰️</div><h2 style="margin:.4em 0">Page inaccessible</h2><p style="color:#aaa5d6;padding:0 24px">\(texte)</p></div>
        """
        webView.loadHTMLString(html, baseURL: echouee)
    }

    /// Processus web tué par iOS (mémoire) : l'onglet affiché est rechargé, les autres s'endorment
    /// (ils se rechargeront quand on y reviendra, sans reprendre de mémoire maintenant).
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if Navigateur.partage.actif === self { webView.reload() } else { endormir() }
    }
}

// MARK: - WKUIDelegate

extension Onglet: WKUIDelegate {
    /// target=_blank / window.open (déclenché par l'utilisateur) : nouvel onglet.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let nouvel = Navigateur.partage.nouvelOnglet(fantome: fantome, activer: true, apres: self)
        nouvel.url = action.request.url
        nouvel.groupe = groupe
        return nouvel.vueActive(configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        Navigateur.partage.fermer(self)
    }

    func webView(_ webView: WKWebView, contextMenuConfigurationFor info: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let lien = info.linkURL else { return nil }
        let fantome = self.fantome
        let nav = Navigateur.partage
        let propre = Adresse.aPartager(lien)
        var actions: [UIMenuElement] = [
            UIAction(title: "Ouvrir dans un nouvel onglet", image: UIImage(systemName: "plus.square.on.square")) { _ in
                MainActor.assumeIsolated { _ = nav.ouvrir(url: lien, nouvelOnglet: true, arrierePlan: true, fantome: fantome) }
            },
            UIAction(title: "Ouvrir en Fantôme", image: UIImage(systemName: "theatermasks")) { _ in
                MainActor.assumeIsolated { _ = nav.ouvrir(url: lien, nouvelOnglet: true, arrierePlan: false, fantome: true) }
            },
            UIAction(title: "Copier le lien", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = propre },
            UIAction(title: "Partager", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                MainActor.assumeIsolated { Partage.presenter([propre]) }
            },
            UIAction(title: "Télécharger le lien", image: UIImage(systemName: "arrow.down.circle")) { [weak webView] _ in
                MainActor.assumeIsolated {
                    webView?.startDownload(using: URLRequest(url: lien)) { d in
                        MainActor.assumeIsolated { Telechargements.partage.suivre(d, fantome: fantome) }
                    }
                }
            }
        ]
        let contacts = Discussion.partage.contacts
        if !contacts.isEmpty {
            actions.append(UIMenu(title: "Envoyer à…", image: UIImage(systemName: "paperplane"), children: contacts.map { c in
                UIAction(title: c.nom, image: UIImage(systemName: "person.crop.circle")) { _ in
                    MainActor.assumeIsolated { Discussion.partage.envoyerOnglet(propre, titre: info.linkURL?.host() ?? "", a: c.id) }
                }
            }))
        }
        if !fantome {
            actions.append(UIAction(title: "Ajouter aux favoris", image: UIImage(systemName: "star")) { _ in
                MainActor.assumeIsolated { Favoris.partage.ajouter(url: propre, titre: lien.host() ?? lien.absoluteString) }
            })
        }
        let menu = UIMenu(title: propre.absoluteString, children: actions)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }

    // Boîtes de dialogue JavaScript (alert / confirm / prompt)
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await Dialogue.alerte(message, hote: frame.securityOrigin.host)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Dialogue.confirmer(message, hote: frame.securityOrigin.host)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        await Dialogue.saisir(prompt, defaut: defaultText, hote: frame.securityOrigin.host)
    }

    /// Caméra / micro : demandé à l'utilisateur par iOS (jamais accordé en silence).
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        .prompt
    }
}

import Observation
import UIKit
import WebKit

/// Extensions web dans VibeSearch (moteur WebKit d'iOS 18.4 et plus, le même que Safari).
/// Bitwarden y est livré : compilé sur GitHub depuis son code officiel (version Safari), il tourne
/// DANS le navigateur comme sur ordinateur : remplissage, clés d'accès (passkeys), générateur.
/// Jamais dans les onglets Fantôme. Point d'entrée commun, sans souci de version d'iOS.
@MainActor
enum Extensions {
    static var bitwardenLivre: Bool { MoteurExtensionsSupport.dossierBitwarden != nil }

    static var disponible: Bool {
        if #available(iOS 18.4, *) { return MoteurExtensions.partage.pret }
        return false
    }

    static var etat: String {
        if #available(iOS 18.4, *) { return MoteurExtensions.partage.etat }
        return "Demande iOS 18.4 ou plus récent."
    }

    /// Dernières erreurs signalées par l'extension ou par WebKit (diagnostic).
    static var journal: [String] {
        if #available(iOS 18.4, *) { return MoteurExtensions.partage.journal }
        return []
    }

    static func demarrer() {
        if #available(iOS 18.4, *) { MoteurExtensions.partage.demarrer() }
    }

    static func arreter() {
        if #available(iOS 18.4, *) { MoteurExtensions.partage.arreter() }
    }

    /// Contrôleur à poser sur la configuration d'un onglet normal.
    static func poser(sur c: WKWebViewConfiguration, fantome: Bool) {
        guard !fantome else { return }
        if #available(iOS 18.4, *), let ctl = MoteurExtensions.partage.controleur { c.webExtensionController = ctl }
    }

    /// Ouvre Bitwarden (sa fenêtre habituelle) pour l'onglet actif.
    static func ouvrirBitwarden() {
        if #available(iOS 18.4, *) { MoteurExtensions.partage.ouvrir() }
    }

    static func ongletOuvert(_ o: Onglet) {
        guard !o.fantome else { return }
        if #available(iOS 18.4, *) { MoteurExtensions.partage.ouvert(o) }
    }

    static func ongletFerme(_ o: Onglet) {
        guard !o.fantome else { return }
        if #available(iOS 18.4, *) { MoteurExtensions.partage.ferme(o) }
    }

    static func ongletActive(_ o: Onglet, avant: Onglet?) {
        guard !o.fantome else { return }
        if #available(iOS 18.4, *) { MoteurExtensions.partage.active(o, avant: avant) }
    }

    static func changement(_ o: Onglet, titre: Bool = false, adresse: Bool = false, chargement: Bool = false) {
        guard !o.fantome else { return }
        if #available(iOS 18.4, *) {
            var p: WKWebExtension.TabChangedProperties = []
            if titre { p.insert(.title) }
            if adresse { p.insert(.URL) }
            if chargement { p.insert(.loading) }
            MoteurExtensions.partage.change(o, p)
        }
    }
}

enum MoteurExtensionsSupport {
    /// Dossier de l'extension dans l'appli (absent si la compilation de Bitwarden a échoué).
    static var dossierBitwarden: URL? {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("ExtensionsWeb/bitwarden", isDirectory: true),
              FileManager.default.fileExists(atPath: base.appendingPathComponent("manifest.json").path) else { return nil }
        return base
    }
}

@available(iOS 18.4, *)
@MainActor
@Observable
final class MoteurExtensions: NSObject, WKWebExtensionControllerDelegate {
    static let partage = MoteurExtensions()

    private(set) var etat = "Arrêtée"
    private(set) var pret = false
    private(set) var journal: [String] = []
    @ObservationIgnored private(set) var controleur: WKWebExtensionController?
    @ObservationIgnored private var contexte: WKWebExtensionContext?
    let fenetre = FenetreExtensions()
    @ObservationIgnored private var enCours = false

    /// Identité FIXE : le coffre Bitwarden (session, réglages) reste d'un lancement à l'autre.
    private static let adresseBase = URL(string: "webkit-extension://3f9c2a71-8d4e-4b6a-9e2f-7c1d5b8a0e64")!

    func demarrer() {
        guard Reglages.partage.extensionBitwarden, !enCours, contexte == nil else { return }
        guard let dossier = MoteurExtensionsSupport.dossierBitwarden else {
            etat = "Bitwarden n'est pas inclus dans cette version."
            return
        }
        enCours = true
        etat = "Chargement…"
        if controleur == nil {
            let cfg = WKWebExtensionController.Configuration.default()
            let vue = WKWebViewConfiguration()
            // « Safari » dans l'identité : Bitwarden choisit alors son mode Safari (presse-papiers, etc.)
            vue.applicationNameForUserAgent = FabriqueWeb.agentUtilisateur
            cfg.webViewConfiguration = vue
            let ctl = WKWebExtensionController(configuration: cfg)
            ctl.delegate = self
            controleur = ctl
        }
        Task { @MainActor in
            defer { self.enCours = false }
            do {
                let ext = try await WKWebExtension(resourceBaseURL: dossier)
                let ctx = WKWebExtensionContext(for: ext)
                ctx.uniqueIdentifier = "fr.vibe.search.bitwarden"
                ctx.baseURL = Self.adresseBase
                ctx.inspectionName = "Bitwarden"
                for p in ext.requestedPermissions.union(ext.optionalPermissions) {
                    ctx.setPermissionStatus(.grantedExplicitly, for: p)
                }
                for m in ext.allRequestedMatchPatterns.union(ext.optionalPermissionMatchPatterns) {
                    ctx.setPermissionStatus(.grantedExplicitly, for: m)
                }
                guard let ctl = self.controleur else { return }
                for e in ext.errors { self.noter("WebKit (manifeste) : \(e.localizedDescription)") }
                NotificationCenter.default.addObserver(forName: WKWebExtensionContext.errorsDidUpdateNotification, object: ctx, queue: .main) { [weak self] n in
                    MainActor.assumeIsolated {
                        guard let c = n.object as? WKWebExtensionContext else { return }
                        for e in c.errors { self?.noter("WebKit : \(e.localizedDescription)") }
                    }
                }
                try ctl.load(ctx)
                self.noter("Chargée : \(ext.displayName ?? "?") \(ext.version ?? "")")
                ctx.loadBackgroundContent { [weak self] e in
                    MainActor.assumeIsolated { self?.noter(e.map { "Arrière-plan : échec \($0.localizedDescription)" } ?? "Arrière-plan : démarré") }
                }
                self.contexte = ctx
                self.pret = true
                let avert = (ext.errors + ctx.errors).map(\.localizedDescription)
                self.etat = avert.isEmpty ? "Prête · version \(ext.version ?? "?")"
                    : "Prête · version \(ext.version ?? "?") · " + avert.prefix(3).joined(separator: " · ")
                // L'extension découvre la fenêtre et les onglets déjà ouverts
                ctl.didOpenWindow(self.fenetre)
                for o in Navigateur.partage.onglets { ctl.didOpenTab(o) }
                ctl.didFocusWindow(self.fenetre)
                if let a = Navigateur.partage.actif, !a.fantome { ctl.didActivateTab(a, previousActiveTab: nil) }
            } catch {
                self.etat = "Erreur : \(error.localizedDescription)"
                self.noter("Échec du chargement : \(error.localizedDescription)")
            }
        }
    }

    func noter(_ ligne: String) {
        let l = "\(Date().formatted(date: .omitted, time: .standard)) \(ligne)"
        NSLog("[VibeExtension] %@", l)
        journal.append(l)
        if journal.count > 150 { journal.removeFirst(journal.count - 150) }
    }

    func arreter() {
        if let ctl = controleur, let ctx = contexte { try? ctl.unload(ctx) }
        contexte = nil
        pret = false
        etat = "Arrêtée"
    }

    func ouvrir() {
        guard let ctx = contexte else { noter("Ouverture impossible : extension pas chargée"); return }
        noter("Ouverture de la fenêtre Bitwarden")
        let a = Navigateur.partage.actif
        ctx.performAction(for: a?.fantome == false ? a : nil)
    }

    // MARK: Onglets → extension

    func ouvert(_ o: Onglet) {
        guard pret, let ctl = controleur else { return }
        ctl.didOpenTab(o)
    }

    func ferme(_ o: Onglet) {
        guard pret, let ctl = controleur else { return }
        ctl.didCloseTab(o, windowIsClosing: false)
    }

    func active(_ o: Onglet, avant: Onglet?) {
        guard pret, let ctl = controleur else { return }
        ctl.didActivateTab(o, previousActiveTab: avant?.fantome == false ? avant : nil)
    }

    func change(_ o: Onglet, _ p: WKWebExtension.TabChangedProperties) {
        guard pret, let ctl = controleur, !p.isEmpty else { return }
        ctl.didChangeTabProperties(p, for: o)
    }

    // MARK: Délégué

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [fenetre]
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        fenetre
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        fermerFenetreBitwarden()
        let nav = Navigateur.partage
        if let u = configuration.url {
            return nav.ouvrir(url: u, nouvelOnglet: true, arrierePlan: !configuration.shouldBeActive, fantome: false)
        }
        return nav.nouvelOnglet(fantome: false, activer: configuration.shouldBeActive)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration, for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        // Une seule fenêtre sur iPhone : les pages demandées s'ouvrent en onglets
        fermerFenetreBitwarden()
        for u in configuration.tabURLs { _ = Navigateur.partage.ouvrir(url: u, nouvelOnglet: true, fantome: false) }
        return fenetre
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        if let u = extensionContext.optionsPageURL { _ = Navigateur.partage.ouvrir(url: u, nouvelOnglet: true, fantome: false) }
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        (permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        (urls, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        (matchPatterns, nil)
    }

    @ObservationIgnored private weak var fenetreBitwarden: UIViewController?

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext) async throws {
        guard let vc = action.popupViewController, let haut = Presentateur.sommet else { noter("Fenêtre : rien à présenter"); return }
        if vc.parent != nil || vc.presentingViewController != nil { return }
        // La fenêtre de WebKit dans NOTRE conteneur plein écran : WebKit ne peut plus la réduire
        // à mi-hauteur, et sa fermeture (bouton ✓, fin du remplissage) ferme le conteneur.
        let conteneur = ConteneurFenetreExtension(contenu: vc, action: action)
        fenetreBitwarden = conteneur
        haut.present(conteneur, animated: true)
    }

    private func fermerFenetreBitwarden() {
        fenetreBitwarden?.dismiss(animated: true)
    }

    /// Messages « vers l'appli » de la version Safari de Bitwarden (ce que fait son appli Mac).
    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {
        guard let m = message as? [String: Any], let commande = m["command"] as? String else { return nil }
        let maintenant = Int64(Date().timeIntervalSince1970 * 1000)
        func reponse(_ valeur: Any) -> [String: Any] {
            var r: [String: Any] = ["command": commande, "response": valeur, "timestamp": maintenant]
            if let id = m["messageId"] { r["messageId"] = id }
            return ["message": r]
        }
        if commande != "vibeJournal" && commande != "sleep" { noter("→ appli : \(commande)") }
        switch commande {
        case "vibeJournal":
            noter("[\(m["lieu"] as? String ?? "?")] \(m["message"] as? String ?? "")")
            return nil
        case "readFromClipboard":
            return UIPasteboard.general.string ?? ""
        case "copyToClipboard":
            if let t = m["data"] as? String {
                // Mot de passe copié : effacé du presse-papiers au bout de 2 minutes, et pas sur les autres appareils
                UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: t]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
            }
            return nil
        case "showPopover":
            ouvrir()
            return nil
        case "downloadFile":
            enregistrer(m["data"] as? String)
            return nil
        case "sleep":
            return nil
        case "biometricUnlockAvailable":
            return reponse("not available")
        case "getBiometricsStatus", "getBiometricsStatusForUser":
            return reponse(5) // PlatformUnsupported : déverrouillage par code PIN ou mot de passe maître
        case "authenticateWithBiometrics", "unlockWithBiometricsForUser":
            return reponse(false)
        case "biometricUnlock":
            return reponse("not supported")
        default:
            return nil
        }
    }

    /// Export du coffre, pièce jointe… : fichier enregistré puis proposé au partage (Fichiers, AirDrop…).
    private func enregistrer(_ json: String?) {
        guard let json, let d = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let blob = d["blobData"] as? String else { return }
        let type = (d["blobOptions"] as? [String: Any])?["type"] as? String
        guard let donnees = type == "text/plain" ? Data(blob.utf8) : Data(base64Encoded: blob) else { return }
        let nom = ((d["fileName"] as? String) ?? "bitwarden").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nom)
        do {
            try donnees.write(to: url, options: [.atomic, .completeFileProtection])
            Partage.presenter([url])
        } catch {}
    }
}

/// L'unique fenêtre du navigateur, vue par les extensions (onglets normaux seulement).
@available(iOS 18.4, *)
@MainActor
final class FenetreExtensions: NSObject, WKWebExtensionWindow {
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        Navigateur.partage.onglets
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let a = Navigateur.partage.actif, !a.fantome else { return nil }
        return a
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .fullscreen }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        Presentateur.sommet?.view.window?.screen.bounds ?? .zero
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        Presentateur.sommet?.view.window?.frame ?? .zero
    }

    func focus(for context: WKWebExtensionContext) async throws {}
}

/// Un onglet, vu par les extensions.
@available(iOS 18.4, *)
extension Onglet: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        fantome ? nil : MoteurExtensions.partage.fenetre
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        Navigateur.partage.onglets.firstIndex { $0 === self } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { vue }
    func title(for context: WKWebExtensionContext) -> String? { titre }
    func url(for context: WKWebExtensionContext) -> URL? { self.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !enChargement }
    func isSelected(for context: WKWebExtensionContext) -> Bool { Navigateur.partage.actif === self }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { charger(url) }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws { recharger() }
    func goBack(for context: WKWebExtensionContext) async throws { reculer() }
    func goForward(for context: WKWebExtensionContext) async throws { avancer() }
    func activate(for context: WKWebExtensionContext) async throws { Navigateur.partage.activer(self) }
    func close(for context: WKWebExtensionContext) async throws { Navigateur.partage.fermer(self) }
}

/// Plein écran qui accueille la fenêtre d'une extension (une feuille restait coincée à
/// mi-hauteur : iOS suit la taille annoncée par la page de l'extension). Barre du haut avec ✕.
@available(iOS 18.4, *)
@MainActor
final class ConteneurFenetreExtension: UIViewController {
    private let contenu: UIViewController
    private weak var action: WKWebExtension.Action?
    private static let fond = UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1)

    init(contenu: UIViewController, action: WKWebExtension.Action) {
        self.contenu = contenu
        self.action = action
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.fond

        let barre = UIView()
        barre.backgroundColor = Self.fond
        barre.translatesAutoresizingMaskIntoConstraints = false
        let titre = UILabel()
        titre.text = action?.webExtensionContext?.webExtension.displayShortName ?? "Extension"
        titre.font = .systemFont(ofSize: 17, weight: .semibold)
        titre.textColor = .white
        titre.translatesAutoresizingMaskIntoConstraints = false
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular))
        c.baseForegroundColor = UIColor.white.withAlphaComponent(0.75)
        let fermer = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.fermer() })
        fermer.accessibilityLabel = "Fermer"
        fermer.translatesAutoresizingMaskIntoConstraints = false
        barre.addSubview(titre)
        barre.addSubview(fermer)
        view.addSubview(barre)

        addChild(contenu)
        contenu.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contenu.view)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            barre.topAnchor.constraint(equalTo: g.topAnchor),
            barre.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barre.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barre.heightAnchor.constraint(equalToConstant: 52),
            titre.centerYAnchor.constraint(equalTo: barre.centerYAnchor),
            titre.leadingAnchor.constraint(equalTo: barre.leadingAnchor, constant: 18),
            fermer.centerYAnchor.constraint(equalTo: barre.centerYAnchor),
            fermer.trailingAnchor.constraint(equalTo: barre.trailingAnchor, constant: -8),
            fermer.widthAnchor.constraint(equalToConstant: 52),
            fermer.heightAnchor.constraint(equalToConstant: 52),
            contenu.view.topAnchor.constraint(equalTo: barre.bottomAnchor),
            contenu.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contenu.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contenu.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contenu.didMove(toParent: self)
    }

    /// La page de l'extension annonce sa taille : ignorée (plein écran).
    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {}

    private func fermer() {
        action?.closePopup()
        if presentingViewController != nil { dismiss(animated: true) }
    }
}

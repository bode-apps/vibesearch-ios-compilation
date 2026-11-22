import LocalAuthentication
import SwiftUI
import Translation
import WebKit

// MARK: - Mode lecture

/// Article épuré : texte seul, grand, sans pubs ni menus. Affiché dans une vue WebKit sans JavaScript
/// et sans stockage (rien n'est gardé).
struct LecteurVue: View {
    let onglet: Onglet
    @Environment(\.dismiss) private var fermer
    @AppStorage("lecteurTaille") private var taille = 19.0
    @AppStorage("lecteurSerif") private var serif = true
    @State private var article: Article?
    @State private var echec = false

    struct Article: Decodable { let titre: String; let site: String; let adresse: String; let html: String }

    var body: some View {
        NavigationStack {
            Group {
                if let a = article {
                    PageLecteur(html: Self.page(a, taille: taille, serif: serif), base: URL(string: a.adresse))
                        .ignoresSafeArea(edges: .bottom)
                } else if echec {
                    ContentUnavailableView("Mode lecture indisponible", systemImage: "doc.text", description: Text("Cette page n'a pas d'article à extraire."))
                } else {
                    ProgressView()
                }
            }
            .background(Color(hex: 0x15131F).ignoresSafeArea())
            .navigationTitle(article?.site ?? "Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { taille = max(14, taille - 1) } label: { Image(systemName: "textformat.size.smaller") }
                    Button { taille = min(30, taille + 1) } label: { Image(systemName: "textformat.size.larger") }
                    Button { serif.toggle() } label: { Image(systemName: serif ? "textformat" : "character.book.closed") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } }
            }
        }
        .task {
            guard article == nil else { return }
            if let json = await onglet.executer(FabriqueWeb.sourceLecteur),
               let a = try? JSONDecoder().decode(Article.self, from: Data(json.utf8)), a.html.count > 200 {
                article = a
            } else {
                echec = true
            }
        }
    }

    static func page(_ a: Article, taille: Double, serif: Bool) -> String {
        let police = serif ? "'New York', ui-serif, Georgia, serif" : "-apple-system, system-ui, sans-serif"
        let titre = a.titre.replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
        <style>
        :root { color-scheme: dark; }
        body { margin: 0; padding: 22px 20px 60px; background: #15131f; color: #e9e6f5; font: \(Int(taille))px/1.62 \(police); }
        h1 { font: 700 \(Int(taille * 1.45))px/1.2 -apple-system, system-ui; margin: 0 0 6px; color: #fff; }
        .site { color: #8f8ab8; font: 14px -apple-system; margin-bottom: 26px; }
        h2, h3, h4 { font-family: -apple-system, system-ui; line-height: 1.3; color: #fff; margin: 1.4em 0 .5em; }
        p, li { margin: 0 0 1em; } a { color: #8fb8ff; text-decoration: none; }
        img { max-width: 100%; height: auto; border-radius: 12px; display: block; margin: 1em auto; }
        blockquote { margin: 1em 0; padding: .2em 1em; border-left: 3px solid #7c6cff; color: #c9c4e6; }
        pre, code { font: 14px ui-monospace, monospace; background: #1f1c2e; border-radius: 6px; padding: 2px 5px; white-space: pre-wrap; }
        figcaption { color: #8f8ab8; font: 14px -apple-system; text-align: center; }
        table { border-collapse: collapse; font-size: .85em; } td, th { border: 1px solid #333; padding: 4px 6px; }
        </style>
        <h1>\(titre)</h1><div class=site>\(a.site)</div>\(a.html)
        """
    }
}

/// Vue WebKit du lecteur : JavaScript coupé, stockage éphémère, liens ouverts dans un nouvel onglet.
struct PageLecteur: UIViewRepresentable {
    let html: String
    let base: URL?

    func makeCoordinator() -> Coordinateur { Coordinateur() }

    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.defaultWebpagePreferences.allowsContentJavaScript = false
        if let pubs = Bloqueur.partage.listesActives().first { c.userContentController.add(pubs) }
        let v = WKWebView(frame: .zero, configuration: c)
        v.isOpaque = false
        v.backgroundColor = UIColor(Color(hex: 0x15131F))
        v.navigationDelegate = context.coordinator
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        guard context.coordinator.dernier != html else { return }
        context.coordinator.dernier = html
        v.loadHTMLString(html, baseURL: base)
    }

    final class Coordinateur: NSObject, WKNavigationDelegate {
        var dernier = ""
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            if action.navigationType == .linkActivated, let u = action.request.url {
                await MainActor.run { _ = Navigateur.partage.ouvrir(url: u, nouvelOnglet: true, arrierePlan: true) }
                return (.cancel, preferences)
            }
            return (.allow, preferences)
        }
    }
}

// MARK: - Traduction sur l'appareil (iOS 18 : gratuite, privée, rien ne quitte l'iPhone)

/// Vue invisible qui porte la session de traduction d'iOS et traduit l'onglet demandé.
struct TraducteurInvisible: View {
    @Environment(Navigateur.self) private var nav

    var body: some View {
        if #available(iOS 18.0, *) {
            Traducteur18(onglet: nav.traductionDemandee)
        } else {
            Color.clear.frame(width: 0, height: 0)
                .onChange(of: nav.traductionDemandee?.id) { _, id in
                    if id != nil {
                        nav.traductionDemandee = nil
                        Task { await Dialogue.alerte("La traduction de page demande iOS 18 ou plus récent.", hote: "VibeSearch") }
                    }
                }
        }
    }
}

@available(iOS 18.0, *)
private struct Traducteur18: View {
    let onglet: Onglet?
    @Environment(Navigateur.self) private var nav
    @State private var configuration: TranslationSession.Configuration?

    private struct Morceau: Decodable { let i: Int; let t: String }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: onglet?.id) { _, id in
                guard id != nil else { return }
                let cible = Locale.Language(identifier: Locale.preferredLanguages.first ?? "fr")
                if configuration == nil {
                    configuration = TranslationSession.Configuration(source: nil, target: cible)
                } else {
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { session in
                guard let o = onglet else { return }
                defer { Task { @MainActor in nav.traductionDemandee = nil } }
                _ = await o.executer(FabriqueWeb.sourceTraduction + ";''")
                // Par paquets : la page s'affiche traduite au fur et à mesure
                for _ in 0 ..< 12 {
                    guard let json = await o.executer("vibeTraduction.collecter(150)"),
                          let lot = try? JSONDecoder().decode([Morceau].self, from: Data(json.utf8)), !lot.isEmpty else { break }
                    let requetes = lot.map { TranslationSession.Request(sourceText: $0.t, clientIdentifier: String($0.i)) }
                    guard let reponses = try? await session.translations(from: requetes) else { break }
                    var table: [String: String] = [:]
                    for r in reponses { if let id = r.clientIdentifier { table[id] = r.targetText } }
                    guard let data = try? JSONSerialization.data(withJSONObject: table),
                          let arg = String(data: data, encoding: .utf8) else { break }
                    _ = await o.executer("vibeTraduction.appliquer(\(arg)) ? 'ok' : ''")
                    await MainActor.run { o.traduite = true }
                }
            }
    }
}

// MARK: - Verrou Face ID

@MainActor
@Observable
final class Verrou {
    static let partage = Verrou()
    /// Appli (ou mode Fantôme) verrouillée : contenu masqué tant que Face ID n'a pas validé.
    var verrouille = false
    @ObservationIgnored private var enCours = false

    /// À appeler au retour dans l'appli et en entrant dans le mode Fantôme.
    func verifier(fantome: Bool) {
        let r = Reglages.partage
        if r.verrouAppli || (fantome && r.verrouFantome) { verrouille = true }
    }

    /// Passage en mode Fantôme : Face ID si « Verrouiller le Fantôme » est actif.
    func entreeFantome() {
        guard Reglages.partage.verrouFantome else { return }
        verrouille = true
        deverrouiller()
    }

    func deverrouiller() {
        guard !enCours else { return }
        enCours = true
        let contexte = LAContext()
        contexte.localizedFallbackTitle = "Code"
        var erreur: NSError?
        guard contexte.canEvaluatePolicy(.deviceOwnerAuthentication, error: &erreur) else {
            // Pas de code ni de Face ID sur l'appareil : le verrou ne peut pas s'appliquer
            verrouille = false
            enCours = false
            return
        }
        contexte.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Déverrouiller VibeSearch") { ok, _ in
            Task { @MainActor in
                if ok { self.verrouille = false }
                self.enCours = false
            }
        }
    }
}

/// Écran posé par-dessus tout quand l'appli est verrouillée, ou quand elle passe en arrière-plan
/// en mode Fantôme (le sélecteur d'applis ne montre pas la page).
struct Rideau: View {
    let verrouille: Bool
    var deverrouiller: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: verrouille ? "lock.fill" : "theatermasks.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.degrade)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 14)
                Text("VibeSearch").font(.title.bold())
                if verrouille {
                    Button("Déverrouiller", action: deverrouiller)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

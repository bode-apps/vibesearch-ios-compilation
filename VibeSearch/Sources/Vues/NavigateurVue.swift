import SwiftUI
import WebKit

/// Feuilles ouvertes depuis la barre du bas, le menu, les raccourcis.
enum Feuille: String, Identifiable {
    case menu, reglages, historique, favoris, telechargements, bouclier, discussion, lecteur, aide
    var id: String { rawValue }
}

/// Écran principal : la page (ou l'accueil) en plein écran, la barre « verre » en bas.
struct NavigateurVue: View {
    @Environment(Navigateur.self) private var nav
    @State private var feuille: Feuille?
    @State private var questionIA: QuestionIA?
    /// Clavier ouvert pour un champ de la PAGE : la barre se retire pour laisser la place.
    @State private var clavierPage = false
    @State private var discussion = Discussion.partage
    @State private var resumes = ResumeRecherche.partage

    var body: some View {
        ZStack {
            Theme.fond0.ignoresSafeArea()
            if let o = nav.actif {
                if o.estAccueil {
                    PageAccueil(feuille: $feuille)
                        .transition(.opacity)
                } else {
                    WebConteneur(onglet: o)
                        .ignoresSafeArea(.keyboard)
                        .id(o.id)
                }
            }
            if nav.saisieActive {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { nav.saisieActive = false }
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !clavierPage || nav.saisieActive {
                VStack(spacing: 8) {
                    if !nav.saisieActive && !nav.barreReduite { bullesFlottantes }
                    BarreBas(feuille: $feuille, questionIA: $questionIA)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background { TraducteurInvisible() }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: nav.saisieActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: nav.barreReduite)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            if !nav.saisieActive { withAnimation(.easeOut(duration: 0.2)) { clavierPage = true } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { clavierPage = false }
        }
        .onChange(of: nav.panneauDemande) { _, f in
            guard let f else { return }
            nav.panneauDemande = nil
            feuille = f
        }
        .overlay(alignment: .top) { BulleTelechargement() }
        .fullScreenCover(isPresented: Binding(get: { nav.grilleVisible }, set: { nav.grilleVisible = $0 })) {
            GrilleOnglets(questionIA: $questionIA)
        }
        .sheet(item: $feuille) { f in
            Group {
                switch f {
                case .menu: MenuVue(feuille: $feuille, questionIA: $questionIA)
                case .reglages: ReglagesVue(feuille: $feuille)
                case .historique: HistoriqueVue()
                case .favoris: FavorisVue()
                case .telechargements: TelechargementsVue()
                case .bouclier: BouclierVue()
                case .discussion: DiscussionVue()
                case .aide: AideParDefautVue()
                case .lecteur:
                    if let o = nav.actif { LecteurVue(onglet: o) }
                }
            }
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(Theme.rayonGrand)
        }
        .sheet(item: $questionIA) { q in
            IAVue(demande: q)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(Theme.rayonGrand)
        }
    }

    /// Bulles au-dessus de la barre : réponse IA sur une page de résultats, onglet reçu.
    @ViewBuilder
    private var bullesFlottantes: some View {
        if let m = discussion.ongletRecu {
            bulle(icone: "rectangle.portrait.and.arrow.forward", texte: "\(m.de) : \(m.titre ?? Adresse.courte(URL(string: m.url ?? "")))", action: "Ouvrir") {
                discussion.ongletRecu = nil
                if let o = nav.ongletsAffiches.last(where: { $0.url?.absoluteString == m.url }) ?? nav.onglets.last(where: { $0.url?.absoluteString == m.url }) {
                    nav.activer(o)
                } else if let u = URL(string: m.url ?? "") {
                    nav.ouvrir(url: u, nouvelOnglet: true, fantome: false)
                }
            } fermer: { discussion.ongletRecu = nil }
        } else if let o = nav.actif, Reglages.partage.bulleRecherche, o.estPageRecherche {
            if let r = resumes.reponse(pour: o.url) {
                carteReponse(r, onglet: o)
            } else if !o.enChargement && ResumeRecherche.partage.reponse(pour: o.url) == nil && !resumes.masqueePour(o.url) {
                bulle(icone: "sparkles", texte: "Réponse de Claude à cette recherche", action: "Demander") {
                    questionIA = QuestionIA(onglet: o, action: .recherche)
                } fermer: { resumes.masquer(o.url) }
            }
        }
    }

    /// Réponse automatique de Claude au-dessus des résultats de recherche.
    private func carteReponse(_ r: ResumeRecherche.Reponse, onglet o: Onglet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.degrade)
                Text("Réponse de Claude").font(.subheadline.weight(.semibold))
                if r.enCours { ProgressView().controlSize(.small).tint(Theme.accent) }
                Spacer()
                Button("Continuer") { questionIA = QuestionIA(onglet: o, action: .recherche) }
                    .font(.subheadline.weight(.bold))
                    .disabled(r.enCours)
                Button { resumes.masquer(o.url) } label: {
                    Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Theme.texteFaible)
                }
            }
            ScrollView {
                Group {
                    if let e = r.erreur, r.texte.isEmpty {
                        Text(e).foregroundStyle(Theme.danger)
                    } else if r.texte.isEmpty {
                        Text("Claude lit les résultats…").foregroundStyle(Theme.texteDoux)
                    } else {
                        Text((try? AttributedString(markdown: r.texte, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(r.texte))
                            .foregroundStyle(Theme.texte)
                            .tint(Theme.accent3)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 170)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .carteVerre(rayon: 18)
        .lueur()
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Liens des sources : ouverts dans l'onglet
        .environment(\.openURL, OpenURLAction { url in
            if ["http", "https"].contains(url.scheme ?? "") { o.charger(url) }
            return .handled
        })
    }

    private func bulle(icone: String, texte: String, action: String, faire: @escaping () -> Void, fermer: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icone).foregroundStyle(Theme.degrade)
            Text(texte).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            Button(action, action: faire).font(.subheadline.weight(.bold))
            Button(action: fermer) { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Theme.texteFaible) }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .carteVerre(rayon: 999)
        .lueur()
        .padding(.horizontal, 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Héberge la vue WebKit de l'onglet actif (une seule à l'écran : les autres ne dessinent rien).
struct WebConteneur: UIViewRepresentable {
    let onglet: Onglet

    func makeUIView(context: Context) -> UIView {
        let boite = UIView()
        boite.backgroundColor = UIColor(Theme.fond0)
        placer(dans: boite)
        return boite
    }

    func updateUIView(_ boite: UIView, context: Context) { placer(dans: boite) }

    private func placer(dans boite: UIView) {
        let v = onglet.vueActive()
        guard v.superview !== boite else { return }
        boite.subviews.forEach { $0.removeFromSuperview() }
        v.removeFromSuperview()
        v.frame = boite.bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        boite.addSubview(v)
    }
}

/// Petite bulle quand un téléchargement se termine.
struct BulleTelechargement: View {
    @State private var dl = Telechargements.partage
    @State private var visible: Telechargements.Element?
    @State private var minuteur: Task<Void, Never>?

    var body: some View {
        Group {
            if let e = visible {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.ok)
                    Text(e.nom).lineLimit(1).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    if let f = e.fichier {
                        Button("Ouvrir") { Partage.presenter([f]); visible = nil }
                            .font(.subheadline.weight(.bold))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .carteVerre(rayon: 999)
                .lueur(couleur: Theme.ok)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visible?.id)
        .onChange(of: dl.dernierFini?.id) { _, _ in
            visible = dl.dernierFini
            // Chaque nouvelle bulle relance son propre délai (l'ancien est annulé)
            minuteur?.cancel()
            minuteur = Task {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { visible = nil }
            }
        }
    }
}

/// Option B : les façons gratuites d'ouvrir les liens dans VibeSearch (Apple réserve le
/// « navigateur par défaut » aux applis d'un compte développeur payant).
struct AideParDefautVue: View {
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Apple ne laisse choisir comme navigateur par défaut que les applis publiées avec un compte développeur payant. Voici comment ouvrir quand même vos liens dans VibeSearch, gratuitement.")
                        .font(.callout).foregroundStyle(Theme.texteDoux)
                }
                etape("safari", "Extension Safari : tout ouvrir dans VibeSearch",
                      "Réglages › Apps › Safari › Extensions › « VibeSearch » › activer, puis « Autoriser » sur « Tous les sites web ». Dès qu'une page s'ouvre dans Safari (lien de Mail, Messages, une autre appli…), elle bascule dans VibeSearch. Le bouton puzzle de Safari permet de la couper ou de ne rediriger que les liens touchés.")
                etape("square.and.arrow.up", "Menu Partager",
                      "Dans n'importe quelle appli : Partager › VibeSearch. (Si l'icône n'apparaît pas : faites défiler les applis › Plus › activez VibeSearch.)")
                etape("hand.tap", "Appui long sur un lien",
                      "Dans Messages, Mail ou Notes : appui long sur le lien › Partager › VibeSearch.")
                etape("square.grid.2x2", "Widget et Centre de contrôle",
                      "Ajoutez le widget « Recherche VibeSearch » sur l'écran d'accueil ou de verrouillage, et le bouton VibeSearch dans le Centre de contrôle (iOS 18).")
                etape("mic", "Siri, Spotlight, bouton Action",
                      "« Rechercher avec VibeSearch », « Onglet Fantôme dans VibeSearch ». Sur iPhone 15 Pro et plus : Réglages › Bouton Action › Raccourci › VibeSearch.")
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Ouvrir les liens ici")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
    }

    private func etape(_ icone: String, _ titre: String, _ texte: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(titre, systemImage: icone).font(.headline)
            Text(texte).font(.callout).foregroundStyle(Theme.texteDoux)
        }
        .padding(.vertical, 4)
    }
}

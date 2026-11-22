import SwiftUI
import WebKit

/// Demande d'IA : sur une page, plusieurs onglets, des résultats de recherche ou une vidéo YouTube.
struct QuestionIA: Identifiable {
    enum Action { case resumer, pointsCles, simplifier, recherche, video }
    let id = UUID()
    let onglets: [Onglet]
    let action: Action?

    init(onglet: Onglet, action: Action?) {
        self.onglets = [onglet]
        self.action = action
    }

    init(onglets: [Onglet]) {
        self.onglets = onglets
        self.action = nil
    }

    var fantome: Bool { onglets.contains { $0.fantome } }
}

/// Discussion avec Claude à propos de ce qui est ouvert.
struct IAVue: View {
    let demande: QuestionIA
    @Environment(\.dismiss) private var fermer
    @State private var r = Reglages.partage

    private struct Bulle: Identifiable { let id = UUID(); let deMoi: Bool; var texte: String }

    @State private var bulles: [Bulle] = []
    /// Conversation telle qu'envoyée à l'API (blocs de réponse conservés à l'identique).
    @State private var messages: [[String: Any]] = []
    @State private var saisie = ""
    @State private var enCours = false
    @State private var erreur: String?
    /// Contexte préparé (texte des pages, résultats ou transcription), envoyé au premier tour.
    @State private var contexte: String?
    @State private var resumeContexte = ""
    @State private var cle = Trousseau.lire("anthropic") ?? ""
    @State private var arret: Claude.Arret?
    @State private var fantomeAccepte = false
    @FocusState private var focus: Bool

    private var modeVideo: Bool { demande.action == .video }
    private var modeRecherche: Bool { demande.action == .recherche }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cle.isEmpty {
                    demandeCle
                } else {
                    conversation
                    champ
                }
            }
            .navigationTitle("Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(r.modeleIA.nom).font(.caption).foregroundStyle(Theme.texteFaible)
                }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { arret?.demande = true; fermer() } }
            }
        }
        .task { await preparer() }
        .onDisappear { arret?.demande = true }
        // Liens de la réponse : minutage de vidéo → la vidéo y saute ; autre lien → nouvel onglet
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "vibe-temps", let s = Double(url.absoluteString.dropFirst("vibe-temps:".count)), let o = demande.onglets.first {
                Task { _ = await o.executerDansPage("const v = document.querySelector('video'); if (v) { v.currentTime = \(s); v.play() } return 'ok'") }
                fermer()
            } else if ["http", "https"].contains(url.scheme ?? "") {
                Navigateur.partage.ouvrir(url: url, nouvelOnglet: true, fantome: demande.fantome)
                fermer()
            }
            return .handled
        })
    }

    // MARK: Vues

    private var demandeCle: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill").font(.largeTitle).foregroundStyle(Theme.degrade)
            Text("Ajoutez votre clé d'API Claude").font(.headline)
            Text("Elle se crée sur console.anthropic.com et reste dans le trousseau chiffré de cet iPhone.")
                .font(.subheadline).foregroundStyle(Theme.texteDoux).multilineTextAlignment(.center)
            SecureField("sk-ant-…", text: $cle)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).carteVerre(rayon: 12)
            Button("Enregistrer") { Trousseau.ecrire("anthropic", cle); cle = Trousseau.lire("anthropic") ?? "" }
                .buttonStyle(.borderedProminent)
                .disabled(cle.isEmpty)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
    }

    private var conversation: some View {
        ScrollViewReader { defile in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if demande.fantome && !fantomeAccepte {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Mode Fantôme", systemImage: "theatermasks.fill").font(.headline).foregroundStyle(Theme.fantome)
                            Text("Le contenu de la page sera envoyé à Anthropic (Claude) pour répondre. VibeSearch n'en garde rien, mais il quitte l'iPhone.")
                                .font(.callout).foregroundStyle(Theme.texteDoux)
                            Button("Continuer quand même") { fantomeAccepte = true; lancerActionAuto() }
                                .buttonStyle(.bordered).tint(Theme.fantome)
                        }
                        .padding(14).carteVerre()
                    }
                    if contexte != nil {
                        Label(resumeContexte, systemImage: modeVideo ? "play.rectangle" : (modeRecherche ? "magnifyingglass" : "doc.text"))
                            .font(.caption).foregroundStyle(Theme.texteFaible).lineLimit(2)
                    } else if erreur == nil {
                        ProgressView(modeVideo ? "Lecture des sous-titres…" : "Lecture de la page…").frame(maxWidth: .infinity)
                    }
                    if bulles.isEmpty && contexte != nil && !enCours && (!demande.fantome || fantomeAccepte) {
                        raccourcis
                    }
                    ForEach(bulles) { b in
                        Text(Self.markdown(b.texte))
                            .textSelection(.enabled)
                            .font(.body)
                            .foregroundStyle(Theme.texte)
                            .tint(Theme.accent3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: b.deMoi ? .trailing : .leading)
                            .background(b.deMoi ? AnyShapeStyle(Theme.accent.opacity(0.22)) : AnyShapeStyle(Theme.fond2.opacity(0.7)),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(b.deMoi ? .leading : .trailing, 36)
                    }
                    if enCours && bulles.last?.deMoi != false {
                        ProgressView().tint(Theme.accent)
                    }
                    if let erreur {
                        Label(erreur, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Theme.danger)
                    }
                    if r.plafondAtteint {
                        Label("Plafond mensuel atteint (\(String(format: "%.0f $", r.plafondIA))). Modifiable dans Réglages.", systemImage: "gauge.with.dots.needle.100percent")
                            .font(.callout).foregroundStyle(Theme.danger)
                    }
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(16)
            }
            .onChange(of: bulles.last?.texte) { _, _ in defile.scrollTo("fin", anchor: .bottom) }
        }
    }

    private var raccourcis: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if modeVideo {
                    puce("Résumer la vidéo", "play.rectangle") { poser(Self.consigne(.video)) }
                    puce("Points clés", "list.bullet") { poser("Donne les moments clés de la vidéo, chacun avec son minutage cliquable.") }
                } else if modeRecherche {
                    puce("Réponse", "sparkles") { poser(Self.consigne(.recherche)) }
                } else {
                    puce(demande.onglets.count > 1 ? "Comparer" : "Résumer", "text.alignleft") {
                        poser(demande.onglets.count > 1 ? "Compare ces pages : points communs, différences, ce qu'il faut retenir." : Self.consigne(.resumer))
                    }
                    puce("Points clés", "list.bullet") { poser(Self.consigne(.pointsCles)) }
                    puce("Expliquer", "lightbulb") { poser(Self.consigne(.simplifier)) }
                }
            }
        }
    }

    private func puce(_ titre: String, _ icone: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(titre, systemImage: icone).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.fond2, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
        }
        .buttonStyle(BoutonRebond())
    }

    private var champ: some View {
        HStack(spacing: 10) {
            TextField(modeVideo ? "Poser une question sur la vidéo…" : "Poser une question…", text: $saisie, axis: .vertical)
                .lineLimit(1 ... 4)
                .focused($focus)
                .submitLabel(.send)
                .onSubmit { envoyerSaisie() }
            Button {
                if enCours { arret?.demande = true } else { envoyerSaisie() }
            } label: {
                Image(systemName: enCours ? "stop.fill" : "arrow.up")
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.degrade, in: Circle())
            }
            .disabled(!enCours && (saisie.trimmingCharacters(in: .whitespaces).isEmpty || contexte == nil || (demande.fantome && !fantomeAccepte)))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Préparation du contexte

    private func preparer() async {
        guard contexte == nil else { return }
        if modeVideo {
            await preparerVideo()
        } else if modeRecherche {
            await preparerRecherche()
        } else {
            await preparerPages()
        }
        if !demande.fantome { lancerActionAuto() }
    }

    private func lancerActionAuto() {
        guard bulles.isEmpty, contexte != nil, let a = demande.action else { return }
        poser(Self.consigne(a))
    }

    private struct Page: Decodable { let titre: String; let adresse: String; let texte: String }

    private func preparerPages() async {
        let limite = 120_000 / max(1, demande.onglets.count)
        var parties: [String] = []
        var titres: [String] = []
        for o in demande.onglets {
            // Onglet endormi : réveillé le temps de lire son texte
            if o.vue == nil, o.url != nil {
                o.vueActive()
                for _ in 0 ..< 40 where o.enChargement || o.progression < 0.5 { try? await Task.sleep(for: .milliseconds(300)) }
            }
            guard let json = await o.executer(FabriqueWeb.sourceLecture),
                  let p = try? JSONDecoder().decode(Page.self, from: Data(json.utf8)) else { continue }
            titres.append(p.titre.isEmpty ? Adresse.courte(URL(string: p.adresse)) : p.titre)
            parties.append("<page titre=\"\(p.titre)\" adresse=\"\(p.adresse)\">\n\(p.texte.prefix(limite))\n</page>")
        }
        guard !parties.isEmpty else {
            erreur = "Impossible de lire le texte de cette page."
            return
        }
        contexte = parties.joined(separator: "\n\n")
        resumeContexte = titres.joined(separator: " · ")
    }

    private struct Resultats: Decodable {
        struct R: Decodable { let titre: String; let url: String; let extrait: String }
        let requete: String
        let resultats: [R]
    }

    private func preparerRecherche() async {
        guard let o = demande.onglets.first, let json = await o.executer(FabriqueWeb.sourceRecherche),
              let r = try? JSONDecoder().decode(Resultats.self, from: Data(json.utf8)), !r.resultats.isEmpty else {
            // Mise en page inconnue : on se rabat sur le texte de la page
            await preparerPages()
            return
        }
        var t = "<recherche requete=\"\(r.requete)\">\n"
        for (i, x) in r.resultats.enumerated() { t += "[\(i + 1)] \(x.titre)\n\(x.url)\n\(x.extrait)\n\n" }
        contexte = t + "</recherche>"
        resumeContexte = "« \(r.requete) » · \(r.resultats.count) résultats"
    }

    private struct Transcription: Decodable {
        struct S: Decodable { let t: Int; let x: String }
        let titre: String
        let segments: [S]
    }

    private func preparerVideo() async {
        guard let o = demande.onglets.first,
              let json = await o.executerDansPage("const f = window['\(FabriqueWeb.evenement)st']; return f ? await f() : ''"),
              let tr = try? JSONDecoder().decode(Transcription.self, from: Data(json.utf8)) else {
            erreur = "Impossible de lire la vidéo."
            return
        }
        guard !tr.segments.isEmpty else {
            erreur = "Pas de sous-titres trouvés. Activez les sous-titres (CC) de la vidéo quelques secondes, puis réessayez."
            return
        }
        var lignes: [String] = []
        var total = 0
        for s in tr.segments {
            let l = "[\(Self.minutage(s.t))] \(s.x)"
            total += l.count
            if total > 150_000 { break }
            lignes.append(l)
        }
        contexte = "<video titre=\"\(tr.titre)\">\n" + lignes.joined(separator: "\n") + "\n</video>"
        resumeContexte = tr.titre
    }

    private static func minutage(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func consigne(_ a: QuestionIA.Action) -> String {
        switch a {
        case .resumer: "Résume cette page en quelques paragraphes courts."
        case .pointsCles: "Donne les points clés sous forme de liste."
        case .simplifier: "Explique simplement de quoi il s'agit, comme à quelqu'un qui découvre le sujet."
        case .recherche: "Réponds à ma recherche à partir de ces résultats, en citant tes sources."
        case .video: "Résume cette vidéo : l'idée principale, puis les moments importants avec leur minutage cliquable."
        }
    }

    private var systeme: String {
        var s = """
        Tu es l'assistant du navigateur VibeSearch sur iPhone. Tu réponds en français, de façon claire et concise \
        (l'écran est petit), en t'appuyant sur le contenu fourni. Si la réponse n'y est pas, dis-le. \
        Utilise le Markdown simple (gras, listes, liens) sans tableaux ni titres.
        """
        if modeRecherche {
            s += " Cite les sources sous la forme de liens Markdown [1](adresse), [2](adresse)… juste après l'information."
        }
        if modeVideo {
            s += " Chaque minutage cité doit être un lien Markdown de la forme [12:34](vibe-temps:754), où le nombre est la position en secondes."
        }
        return s
    }

    // MARK: Envoi

    private func envoyerSaisie() {
        let q = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        saisie = ""
        poser(q)
    }

    private func poser(_ question: String) {
        guard let contexte, !enCours, !r.plafondAtteint else { return }
        guard !demande.fantome || fantomeAccepte else { return }
        erreur = nil
        bulles.append(Bulle(deMoi: true, texte: question))
        var contenu: [[String: Any]] = []
        if messages.isEmpty {
            // Premier tour : le contexte en tête (préfixe stable → mis en cache pour les questions suivantes)
            contenu.append(["type": "text", "text": contexte])
        }
        contenu.append(["type": "text", "text": question])
        messages.append(["role": "user", "content": contenu])
        enCours = true
        let client = Claude(cle: cle, modele: r.modeleIA)
        let jeton = Claude.Arret()
        arret = jeton
        let historique = messages
        let sys = systeme
        Task { @MainActor in
            bulles.append(Bulle(deMoi: false, texte: ""))
            let index = bulles.count - 1
            var recu = ""
            var termine = false
            do {
                for try await ev in client.envoyer(systeme: sys, messages: historique, arret: jeton) {
                    switch ev {
                    case let .texte(t):
                        recu += t
                        if bulles.indices.contains(index) { bulles[index].texte = recu }
                    case let .fin(blocs, entree, sortie, lecture, ecriture, motif, servi, complet):
                        r.ajouterDepense(client.cout(entree: entree, sortie: sortie, lectureCache: lecture, ecritureCache: ecriture, modeleServi: servi))
                        // Seule une réponse complète et non vide entre dans la conversation (sinon l'API refuserait la suite)
                        if complet && motif != "refusal" && !blocs.isEmpty {
                            messages.append(["role": "assistant", "content": blocs])
                            termine = true
                        }
                        if motif == "refusal" { erreur = "Claude a décliné cette demande." }
                        if motif == "max_tokens" { erreur = "Réponse coupée (trop longue)." }
                        if !complet && jeton.demande && bulles.indices.contains(index) { bulles[index].texte = recu + " …" }
                    }
                }
            } catch {
                if !jeton.demande { self.erreur = error.localizedDescription }
            }
            if !termine {
                // Question restée sans réponse complète : retirée pour garder une conversation valide
                if messages.last?["role"] as? String == "user" { messages.removeLast() }
                if bulles.indices.contains(index), bulles[index].texte.isEmpty { bulles.remove(at: index) }
            }
            // Ne libère le bouton que si c'est bien CETTE requête qui se termine
            if arret === jeton {
                enCours = false
                arret = nil
            }
        }
    }

    private static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

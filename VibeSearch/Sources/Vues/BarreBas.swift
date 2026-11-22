import SwiftUI

/// Barre du bas façon verre dépoli : adresse (avec LED de chargement), boutons de navigation.
/// En bas de l'écran pour être à portée de pouce ; glisser l'adresse à gauche/droite change d'onglet.
struct BarreBas: View {
    @Environment(Navigateur.self) private var nav
    @Binding var feuille: Feuille?
    @Binding var questionIA: QuestionIA?
    @State private var texte = ""
    @FocusState private var focus: Bool
    @State private var decalage: CGFloat = 0

    private var onglet: Onglet? { nav.actif }
    private var fantome: Bool { onglet?.fantome ?? false }

    var body: some View {
        if nav.barreReduite && !nav.saisieActive {
            barreCompacte
        } else {
            barreComplete
        }
    }

    /// Barre réduite pendant la lecture : juste le site, un toucher la rouvre.
    private var barreCompacte: some View {
        Button { nav.reduireBarre(false) } label: {
            HStack(spacing: 5) {
                if fantome { Image(systemName: "theatermasks.fill").foregroundStyle(Theme.fantome) }
                Text(Adresse.courte(onglet?.url)).lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.texteDoux)
            .frame(maxWidth: .infinity)
            .padding(.top, 6).padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
        }
        .overlay(alignment: .top) { LEDChargement(onglet: onglet).offset(y: -2) }
    }

    private var barreComplete: some View {
        VStack(spacing: 10) {
            if nav.saisieActive {
                ListeSuggestions(texte: texte) { url in
                    nav.saisieActive = false
                    nav.ouvrir(url: url, nouvelOnglet: false)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            pilule
            if !nav.saisieActive { boutons }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, nav.saisieActive ? 8 : 0)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Theme.trait).frame(height: 0.5) }
                .ignoresSafeArea()
        }
        .onChange(of: nav.saisieActive) { _, actif in
            if actif { preparerSaisie() } else { focus = false }
        }
        .onAppear { if nav.saisieActive { preparerSaisie() } }
        .onChange(of: focus) { _, f in if !f && nav.saisieActive { nav.saisieActive = false } }
    }

    private func preparerSaisie() {
        texte = onglet?.url?.absoluteString ?? ""
        focus = true
        // Tout sélectionner : taper remplace l'adresse, comme dans Safari
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    // MARK: Pilule d'adresse

    private var pilule: some View {
        HStack(spacing: 8) {
            if nav.saisieActive {
                Image(systemName: fantome ? "theatermasks.fill" : "magnifyingglass")
                    .foregroundStyle(fantome ? Theme.fantome : Theme.texteDoux)
                TextField("Rechercher ou saisir une adresse", text: $texte)
                    .focused($focus)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        nav.saisieActive = false
                        nav.ouvrir(texte: texte)
                    }
                if !texte.isEmpty {
                    Button { texte = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.texteFaible) }
                }
                Button("Annuler") { nav.saisieActive = false }
                    .font(.subheadline.weight(.semibold))
            } else {
                Button { feuille = .bouclier } label: { BadgeBouclier(onglet: onglet) }
                    .buttonStyle(BoutonRebond())
                Button { nav.saisieActive = true } label: {
                    HStack(spacing: 5) {
                        if fantome { Image(systemName: "theatermasks.fill").font(.caption).foregroundStyle(Theme.fantome) }
                        if let o = onglet, o.url != nil, !o.securise {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.danger)
                        }
                        Text(onglet?.estAccueil == false ? Adresse.courte(onglet?.url) : "Rechercher ou saisir une adresse")
                            .lineLimit(1)
                            .foregroundStyle(onglet?.estAccueil == false ? Theme.texte : Theme.texteFaible)
                    }
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let o = onglet, !o.estAccueil {
                    Button { o.enChargement ? o.arreter() : o.recharger() } label: {
                        Image(systemName: o.enChargement ? "xmark" : "arrow.clockwise")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.texteDoux)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(BoutonRebond())
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Theme.fond2.opacity(0.75), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(fantome ? Theme.fantome.opacity(0.55) : (nav.saisieActive ? Theme.accent.opacity(0.6) : Theme.trait), lineWidth: 1)
        }
        .overlay(alignment: .bottom) { LEDChargement(onglet: onglet) }
        .lueur(nav.saisieActive || fantome, couleur: fantome ? Theme.fantome : Theme.accent)
        .offset(x: decalage)
        .gesture(glisserOnglets, including: nav.saisieActive ? .subviews : .all)
    }

    /// Glisser l'adresse : onglet précédent / suivant.
    private var glisserOnglets: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { g in
                if abs(g.translation.width) > abs(g.translation.height) { decalage = g.translation.width * 0.35 }
            }
            .onEnded { g in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { decalage = 0 }
                let liste = nav.ongletsAffiches
                guard abs(g.translation.width) > 70, let a = onglet, let i = liste.firstIndex(where: { $0 === a }) else { return }
                let j = g.translation.width < 0 ? i + 1 : i - 1
                if let cible = liste[safe: j] {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    nav.activer(cible)
                } else if g.translation.width < 0 {
                    nav.nouvelOnglet(fantome: fantome, activer: true, apres: a)
                }
            }
    }

    // MARK: Boutons

    private var boutons: some View {
        HStack(spacing: 0) {
            bouton("chevron.backward", actif: onglet?.peutReculer == true) { onglet?.reculer() }
            bouton("chevron.forward", actif: onglet?.peutAvancer == true) { onglet?.avancer() }
            Button {
                guard let o = onglet, !o.estAccueil else { return }
                // L'IA s'adapte à la page : vidéo YouTube → résumé de la vidéo, résultats → réponse sourcée
                questionIA = QuestionIA(onglet: o, action: o.estVideoYoutube ? .video : (o.estPageRecherche ? .recherche : nil))
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.degrade)
                    .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(BoutonRebond())
            .opacity(onglet?.estAccueil == false ? 1 : 0.35)
            Button { onglet?.capturer(); nav.grilleVisible = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(fantome ? Theme.fantome : Theme.texte, lineWidth: 1.8)
                        .frame(width: 24, height: 24)
                    Text("\(min(nav.ongletsAffiches.count, 99))").font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(fantome ? Theme.fantome : Theme.texte)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(BoutonRebond())
            .contextMenu {
                Button { nav.nouvelOnglet(fantome: false, activer: true) } label: { Label("Nouvel onglet", systemImage: "plus.square") }
                Button { nav.nouvelOnglet(fantome: true, activer: true) } label: { Label("Nouvel onglet Fantôme", systemImage: "theatermasks") }
                if let o = onglet {
                    Button(role: .destructive) { nav.fermer(o) } label: { Label("Fermer cet onglet", systemImage: "xmark") }
                }
            }
            bouton("ellipsis", actif: true) { feuille = .menu }
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
    }

    private func bouton(_ icone: String, actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icone)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(actif ? Theme.texte : Theme.texteFaible.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(BoutonRebond())
        .disabled(!actif)
    }
}

/// Bouclier avec pastille : traces bloquées sur la page (empreinte + bannières refusées).
struct BadgeBouclier: View {
    let onglet: Onglet?
    var body: some View {
        let autorise = Reglages.partage.estAutorise(hote: onglet?.hote)
        let n = (onglet?.empreintes.count ?? 0) + (onglet?.cookiesRefuses ?? 0)
        Image(systemName: autorise ? "shield.slash" : "shield.lefthalf.filled")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(autorise ? AnyShapeStyle(Theme.texteFaible) : AnyShapeStyle(Theme.degrade))
            .frame(width: 30, height: 30)
            .overlay(alignment: .topTrailing) {
                if n > 0 && !autorise {
                    Text("\(n)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                        .offset(x: 6, y: -3)
                }
            }
    }
}

/// LED de chargement qui court sous l'adresse.
struct LEDChargement: View {
    let onglet: Onglet?
    var body: some View {
        GeometryReader { g in
            if let o = onglet, o.enChargement, o.progression < 1 {
                Capsule()
                    .fill(Theme.degradeLED)
                    .frame(width: max(24, g.size.width * o.progression), height: 2.5)
                    .shadow(color: Theme.accent, radius: 5)
                    .animation(.easeOut(duration: 0.25), value: o.progression)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
    }
}

/// Propositions pendant la saisie : recherche, sites (« you » → youtube.com), historique, favoris.
struct ListeSuggestions: View {
    let texte: String
    let ouvrir: (URL) -> Void

    var body: some View {
        let lignes = Suggestions.pour(texte)
        let recherche = texte.trimmingCharacters(in: .whitespaces)
        VStack(spacing: 0) {
            if !recherche.isEmpty, let url = Reglages.partage.moteur.adresse(pour: recherche) {
                ligne(icone: "magnifyingglass", titre: recherche, detail: "Rechercher avec \(Reglages.partage.moteur.nom)") { ouvrir(url) }
            }
            ForEach(lignes) { l in
                Divider().overlay(Theme.trait)
                ligne(icone: l.icone, titre: l.titre, detail: l.detail) { ouvrir(l.url) }
            }
        }
        .carteVerre()
        .opacity(recherche.isEmpty && lignes.isEmpty ? 0 : 1)
    }

    private func ligne(icone: String, titre: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icone).frame(width: 22).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titre).lineLimit(1).foregroundStyle(Theme.texte)
                    Text(detail).font(.caption).lineLimit(1).foregroundStyle(Theme.texteFaible)
                }
                Spacer()
                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(Theme.texteFaible)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Vue d'ensemble des onglets : aperçus, recherche, groupes, bascule Onglets / Fantôme,
/// sélection de plusieurs onglets pour une question à Claude.
struct GrilleOnglets: View {
    @Environment(Navigateur.self) private var nav
    @Environment(\.dismiss) private var fermer
    @Binding var questionIA: QuestionIA?
    @State private var recherche = ""
    @State private var selection: Set<UUID>?
    @State private var nouveauGroupe: Onglet?
    @State private var nomGroupe = ""
    @State private var groupeARenommer: String?

    private let colonnes = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var visibles: [Onglet] {
        var l = nav.ongletsAffiches
        if !nav.modeFantome, let g = nav.groupeAffiche { l = l.filter { $0.groupe == g } }
        let q = recherche.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            l = l.filter { $0.titreAffiche.localizedCaseInsensitiveContains(q) || ($0.url?.absoluteString.localizedCaseInsensitiveContains(q) ?? false) }
        }
        return l
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { defile in
                ScrollView {
                    if !nav.modeFantome && !nav.groupes.isEmpty { pucesGroupes }
                    LazyVGrid(columns: colonnes, spacing: 16) {
                        ForEach(visibles) { o in carte(o).id(o.id) }
                    }
                    .padding(14)
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: visibles.map(\.id))
                }
                .onAppear { if let a = nav.actif { defile.scrollTo(a.id, anchor: .center) } }
            }
            .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Rechercher dans les onglets")
            .background(Theme.fond0.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: Binding(get: { nav.modeFantome }, set: { f in if f != nav.modeFantome { nav.basculerFantome() } })) {
                        Text("Onglets · \(nav.onglets.count)").tag(false)
                        Text("Fantôme · \(nav.ongletsFantome.count)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if let sel = selection {
                        Button("Annuler") { selection = nil }
                        Spacer()
                        Button {
                            let choisis = nav.ongletsAffiches.filter { sel.contains($0.id) && $0.url != nil }
                            selection = nil
                            fermer()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { questionIA = QuestionIA(onglets: choisis) }
                        } label: {
                            Label("Demander à Claude (\(sel.count))", systemImage: "sparkles").fontWeight(.bold)
                        }
                        .disabled(sel.count < 2)
                    } else {
                        Menu {
                            Button { selection = [] } label: { Label("Question à Claude sur plusieurs onglets", systemImage: "sparkles") }
                            Button(role: .destructive) { nav.fermerTout(fantome: nav.modeFantome, groupe: nav.modeFantome ? nil : nav.groupeAffiche) } label: {
                                Label("Fermer les \(visibles.count) onglets", systemImage: "xmark.square")
                            }
                            if nav.peutRouvrir {
                                Button { nav.rouvrirDernier(); fermer() } label: { Label("Rouvrir le dernier onglet fermé", systemImage: "arrow.uturn.backward") }
                            }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 52, height: 44).contentShape(Rectangle()) }
                        Spacer()
                        Button {
                            nav.nouvelOnglet(fantome: nav.modeFantome, activer: true)
                            fermer()
                        } label: {
                            Image(systemName: "plus").font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 40)
                                .background(nav.modeFantome ? AnyShapeStyle(Theme.fantome) : AnyShapeStyle(Theme.degrade), in: Capsule())
                                .lueur()
                        }
                        Spacer()
                        Button("OK") { fermer() }.fontWeight(.bold)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .bottomBar, .navigationBar)
            .toolbarBackground(.visible, for: .bottomBar, .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Nouveau groupe", isPresented: Binding(get: { nouveauGroupe != nil }, set: { if !$0 { nouveauGroupe = nil } })) {
                TextField("Nom du groupe", text: $nomGroupe)
                Button("Créer") {
                    if let o = nouveauGroupe { nav.ranger(o, dans: nomGroupe); nav.groupeAffiche = o.groupe }
                    nomGroupe = ""
                }
                Button("Annuler", role: .cancel) { nomGroupe = "" }
            }
            .alert("Renommer le groupe", isPresented: Binding(get: { groupeARenommer != nil }, set: { if !$0 { groupeARenommer = nil } })) {
                TextField("Nom du groupe", text: $nomGroupe)
                Button("Renommer") { if let g = groupeARenommer { nav.renommerGroupe(g, en: nomGroupe) }; nomGroupe = "" }
                Button("Annuler", role: .cancel) { nomGroupe = "" }
            }
        }
    }

    /// Puces des groupes : « Tous », puis chaque groupe (appui long : renommer, dissoudre).
    private var pucesGroupes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                puce("Tous", actif: nav.groupeAffiche == nil) { nav.groupeAffiche = nil }
                ForEach(nav.groupes, id: \.self) { g in
                    puce(g, actif: nav.groupeAffiche == g) { nav.groupeAffiche = g }
                        .contextMenu {
                            Button { nomGroupe = g; groupeARenommer = g } label: { Label("Renommer", systemImage: "pencil") }
                            Button(role: .destructive) { nav.dissoudreGroupe(g) } label: { Label("Dissoudre le groupe", systemImage: "folder.badge.minus") }
                        }
                }
            }
            .padding(.horizontal, 14).padding(.top, 10)
        }
    }

    private func puce(_ titre: String, actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(actif ? AnyShapeStyle(Theme.accent.opacity(0.35)) : AnyShapeStyle(Theme.fond2), in: Capsule())
                .overlay(Capsule().strokeBorder(actif ? Theme.accent : Theme.trait))
                .foregroundStyle(Theme.texte)
        }
        .buttonStyle(BoutonRebond())
    }

    private func carte(_ o: Onglet) -> some View {
        let actif = nav.actif === o
        let choisi = selection?.contains(o.id) ?? false
        // La carte n'est PAS un bouton : un bouton dans un bouton (la croix) laisse le grand gagner,
        // et toucher la croix ouvrait l'onglet au lieu de le fermer.
        return VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(o.estAccueil ? "✦" : Monogramme.lettre(titre: o.titre, url: o.url))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Monogramme.couleur(o.hote ?? "").gradient, in: RoundedRectangle(cornerRadius: 5))
                    Text(o.titreAffiche).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.texte)
                    Spacer(minLength: 2)
                    if selection != nil {
                        Image(systemName: choisi ? "checkmark.circle.fill" : "circle").foregroundStyle(choisi ? Theme.accent : Theme.texteFaible)
                    } else {
                        Button { withAnimation { nav.fermer(o) } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.texteDoux)
                                .frame(width: 24, height: 24)
                                .background(Theme.fond3, in: Circle())
                                .frame(width: 40, height: 36) // zone de toucher confortable
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                ZStack(alignment: .bottomLeading) {
                    Theme.fond1
                    if let img = o.apercu {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: o.estAccueil ? "sparkle.magnifyingglass" : "globe")
                                .font(.title).foregroundStyle(Theme.degrade)
                            Text(o.estAccueil ? "Accueil" : Adresse.courte(o.url)).font(.caption2).foregroundStyle(Theme.texteFaible)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let g = o.groupe, nav.groupeAffiche == nil, !o.fantome {
                        Label(g, systemImage: "folder.fill").font(.caption2.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                }
                .frame(height: 210)
                .clipped()
            }
            .background(Theme.fond2)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rayon, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.rayon, style: .continuous)
                    .strokeBorder(choisi || actif ? (o.fantome ? Theme.fantome : Theme.accent) : Theme.trait, lineWidth: choisi || actif ? 2 : 1)
            }
            .lueur(actif || choisi, couleur: o.fantome ? Theme.fantome : Theme.accent)
            .contentShape(RoundedRectangle(cornerRadius: Theme.rayon, style: .continuous))
            .onTapGesture {
                if var s = selection {
                    if s.contains(o.id) { s.remove(o.id) } else { s.insert(o.id) }
                    selection = s
                } else {
                    nav.activer(o)
                    fermer()
                }
            }
        .contextMenu {
            if let u = o.url {
                Button { UIPasteboard.general.url = Adresse.aPartager(u) } label: { Label("Copier le lien", systemImage: "doc.on.doc") }
                Button { Partage.presenter([Adresse.aPartager(u)]) } label: { Label("Partager", systemImage: "square.and.arrow.up") }
            }
            if !o.fantome {
                Menu {
                    Button { nomGroupe = ""; nouveauGroupe = o } label: { Label("Nouveau groupe…", systemImage: "folder.badge.plus") }
                    ForEach(nav.groupes.filter { $0 != o.groupe }, id: \.self) { g in
                        Button { nav.ranger(o, dans: g) } label: { Label(g, systemImage: "folder") }
                    }
                    if o.groupe != nil {
                        Button { nav.ranger(o, dans: nil) } label: { Label("Retirer du groupe", systemImage: "folder.badge.minus") }
                    }
                } label: { Label("Ranger dans un groupe", systemImage: "folder") }
            }
            Button(role: .destructive) { nav.fermer(o) } label: { Label("Fermer", systemImage: "xmark") }
        }
    }
}

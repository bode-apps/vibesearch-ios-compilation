import SwiftUI
import WebKit

/// Menu « … » : actions sur la page et accès aux panneaux.
struct MenuVue: View {
    @Environment(Navigateur.self) private var nav
    @Environment(\.dismiss) private var fermer
    @Binding var feuille: Feuille?
    @Binding var questionIA: QuestionIA?
    @State private var favoris = Favoris.partage
    @State private var discussion = Discussion.partage
    @State private var reglages = Reglages.partage

    private let colonnes = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        let o = nav.actif
        let page = o.flatMap { $0.estAccueil ? nil : $0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let p = page { entete(p) }

                LazyVGrid(columns: colonnes, spacing: 14) {
                    action("plus.square", "Nouvel onglet") { nav.nouvelOnglet(fantome: false, activer: true) }
                    action("theatermasks", "Fantôme", couleur: Theme.fantome) { nav.nouvelOnglet(fantome: true, activer: true) }
                    if let p = page {
                        if !p.fantome {
                            let estFavori = favoris.contient(p.url)
                            action(estFavori ? "star.fill" : "star", estFavori ? "Retirer" : "Favori", couleur: Color(hex: 0xFBBF24)) {
                                if let u = p.url { favoris.basculer(url: Adresse.aPartager(u), titre: p.titre) }
                            }
                        }
                        action("square.and.arrow.up", "Partager") {
                            if let u = p.url { apres { Partage.presenter([Adresse.aPartager(u)]) } }
                        }
                        action("text.magnifyingglass", "Chercher") {
                            apres { p.vue?.findInteraction?.presentFindNavigator(showingReplace: false) }
                        }
                        action("doc.plaintext", "Lecture") { ouvrir(.lecteur) }
                        action(p.traduite ? "arrow.uturn.backward" : "character.bubble", p.traduite ? "Original" : "Traduire") {
                            if p.traduite {
                                Task { _ = await p.executer("vibeTraduction.restaurer() ? 'ok' : ''"); p.traduite = false }
                            } else {
                                nav.traductionDemandee = p
                            }
                        }
                        action("sparkles", p.estVideoYoutube ? "Résumé vidéo" : "Résumer", couleur: Theme.accent2) {
                            let a: QuestionIA.Action = p.estVideoYoutube ? .video : (p.estPageRecherche ? .recherche : .resumer)
                            apres { questionIA = QuestionIA(onglet: p, action: a) }
                        }
                        if p.estVideoYoutube {
                            action("pip.enter", "Mini-lecteur") {
                                Task { _ = await p.executerDansPage("const v = document.querySelector('video'); if (v && v.webkitSetPresentationMode) { v.removeAttribute('disablepictureinpicture'); v.play(); v.webkitSetPresentationMode('picture-in-picture') } return 'ok'") }
                            }
                        }
                        action(p.versionOrdinateur ? "iphone" : "desktopcomputer", p.versionOrdinateur ? "Mobile" : "Ordinateur") {
                            p.basculerVersionOrdinateur()
                        }
                        action(reglages.sombre(pour: p.hote) ? "sun.max" : "moon", reglages.sombre(pour: p.hote) ? "Clair" : "Sombre") {
                            p.basculerSombre()
                        }
                        action("doc.on.doc", "Copier") { if let u = p.url { UIPasteboard.general.url = Adresse.aPartager(u) } }
                    }
                    action("bubble.left.and.bubble.right", "Discussion", pastille: discussion.totalNonLus) { ouvrir(.discussion) }
                    action("book", "Favoris") { ouvrir(.favoris) }
                    action("clock.arrow.circlepath", "Historique") { ouvrir(.historique) }
                    action("arrow.down.circle", "Fichiers", pastille: Telechargements.partage.enCours) { ouvrir(.telechargements) }
                    if nav.peutRouvrir {
                        action("arrow.uturn.backward", "Rouvrir") { nav.rouvrirDernier() }
                    }
                    if Extensions.disponible {
                        action("key.fill", "Bitwarden", couleur: Color(hex: 0x175DDC)) { apres { Extensions.ouvrirBitwarden() } }
                    }
                    action("gearshape", "Réglages") { ouvrir(.reglages) }
                }

                if let p = page {
                    zoom(p)
                    if !discussion.contacts.isEmpty, let u = p.url {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ENVOYER CET ONGLET À").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.texteFaible)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(discussion.contacts) { c in
                                        Button {
                                            discussion.envoyerOnglet(Adresse.aPartager(u), titre: p.titre, a: c.id)
                                            fermer()
                                        } label: {
                                            Label(c.nom, systemImage: "paperplane.fill").font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(Theme.fond2, in: Capsule())
                                        }
                                        .buttonStyle(BoutonRebond())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func entete(_ p: Onglet) -> some View {
        HStack(spacing: 12) {
            Text(Monogramme.lettre(titre: p.titre, url: p.url))
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Monogramme.couleur(p.hote ?? "").gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.titreAffiche).font(.headline).lineLimit(1)
                Text(p.url?.absoluteString ?? "").font(.caption).foregroundStyle(Theme.texteFaible).lineLimit(1)
            }
        }
    }

    /// Zoom du texte, mémorisé par site.
    private func zoom(_ p: Onglet) -> some View {
        HStack {
            Label("Taille du texte", systemImage: "textformat.size").foregroundStyle(Theme.texteDoux)
            Spacer()
            Button { p.zoomer(-0.1) } label: { Image(systemName: "minus").frame(width: 34, height: 30) }
            Button { p.zoomer(nil) } label: {
                Text("\(Int((reglages.site(p.hote).zoom * 100).rounded())) %").font(.subheadline.monospacedDigit()).frame(minWidth: 54)
            }
            Button { p.zoomer(0.1) } label: { Image(systemName: "plus").frame(width: 34, height: 30) }
        }
        .buttonStyle(.bordered)
        .padding(12)
        .carteVerre()
    }

    /// Action après la fermeture du menu (partage, recherche dans la page : elles ont besoin de l'écran).
    private func apres(_ faire: @escaping () -> Void) {
        fermer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: faire)
    }

    /// Remplace le menu par un autre panneau (sheet(item:) gère l'enchaînement).
    private func ouvrir(_ f: Feuille) { feuille = f }

    private static let gardentOuvert: Set<String> = ["Favoris", "Historique", "Fichiers", "Réglages", "Discussion", "Lecture"]

    private func action(_ icone: String, _ titre: String, couleur: Color = Theme.accent, pastille: Int = 0, faire: @escaping () -> Void) -> some View {
        Button {
            faire()
            if !Self.gardentOuvert.contains(titre) && !["Partager", "Chercher", "Résumer", "Résumé vidéo", "Bitwarden"].contains(titre) { fermer() }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icone)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(couleur)
                    .frame(width: 56, height: 56)
                    .background(Theme.fond2.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.trait))
                    .overlay(alignment: .topTrailing) {
                        if pastille > 0 {
                            Text("\(pastille)").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(5).background(Theme.accent, in: Circle()).offset(x: 6, y: -6)
                        }
                    }
                Text(titre).font(.caption).foregroundStyle(Theme.texteDoux).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(BoutonRebond())
    }
}
/// Bouclier : ce qui est bloqué sur la page en cours, et l'interrupteur « ce site ».
struct BouclierVue: View {
    @Environment(Navigateur.self) private var nav
    @State private var reglages = Reglages.partage

    var body: some View {
        let o = nav.actif
        let hote = o?.hote
        NavigationStack {
            List {
                if let o, let hote {
                    Section {
                        Toggle(isOn: Binding(get: { !reglages.estAutorise(hote: hote) }, set: { _ in
                            reglages.basculerAutorisation(hote: hote)
                            o.reappliquerBlocage()
                            o.recharger()
                        })) {
                            Label("Protection sur \(Adresse.courte(o.url))", systemImage: "shield.lefthalf.filled")
                        }
                    } footer: {
                        Text("Si un site fonctionne mal, coupez la protection uniquement pour lui.")
                    }
                    Section("Sur cette page") {
                        ligne("Bannières cookies refusées", "\(o.cookiesRefuses)", "hand.raised.fill")
                        ligne("Empreinte brouillée", o.empreintes.isEmpty ? "aucune tentative" : o.empreintes.sorted().map(Self.nom).joined(separator: ", "), "touchid")
                        ligne("Position", o.empreintes.contains("position") ? "demandée · refusée" : "toujours refusée", "location.slash.fill")
                    }
                }
                Section("Partout") {
                    Toggle(isOn: $reglages.bloquerPubs) { Label("Bloquer les pubs", systemImage: "rectangle.slash") }
                    Toggle(isOn: $reglages.bloquerTraqueurs) { Label("Bloquer les traqueurs", systemImage: "eye.slash") }
                    Toggle(isOn: $reglages.refuserCookies) { Label("Refuser les cookies", systemImage: "hand.raised") }
                    Toggle(isOn: $reglages.bouclierEmpreinte) { Label("Brouiller l'empreinte", systemImage: "touchid") }
                    Toggle(isOn: $reglages.nettoyerLiens) { Label("Nettoyer les liens (utm, fbclid…)", systemImage: "link.badge.plus") }
                    Toggle(isOn: $reglages.httpsPartout) { Label("HTTPS partout", systemImage: "lock") }
                }
                Section {
                    ligne("Règles de blocage actives", Bloqueur.partage.nombreRegles.formatted(), "list.bullet.rectangle")
                } footer: {
                    Text("Listes EasyList, Liste FR et EasyPrivacy, compilées par WebKit : le filtrage ne ralentit pas les pages. Elles sont mises à jour à chaque nouvelle version de l'appli.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Bouclier")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    static func nom(_ k: String) -> String {
        ["canvas": "Canvas", "webgl": "WebGL", "audio": "Audio", "position": "position"][k] ?? k
    }

    private func ligne(_ titre: String, _ valeur: String, _ icone: String) -> some View {
        HStack {
            Label(titre, systemImage: icone)
            Spacer()
            Text(valeur).foregroundStyle(Theme.texteDoux).multilineTextAlignment(.trailing)
        }
    }
}

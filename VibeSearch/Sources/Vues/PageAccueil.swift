import SwiftUI

/// Page « Nouvel onglet » : logo lumineux, favoris, sites fréquents, état du bouclier.
struct PageAccueil: View {
    @Environment(Navigateur.self) private var nav
    @Binding var feuille: Feuille?
    @State private var favoris = Favoris.partage
    @State private var pulse = false

    private let colonnes = [GridItem(.adaptive(minimum: 72), spacing: 14)]

    var body: some View {
        let fantome = nav.actif?.fantome ?? false
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(fantome ? Theme.fantome.opacity(0.25) : Theme.accent.opacity(0.22))
                            .frame(width: 150, height: 150).blur(radius: 40)
                            .scaleEffect(pulse ? 1.12 : 0.92)
                        Image(systemName: fantome ? "theatermasks.fill" : "sparkle.magnifyingglass")
                            .font(.system(size: 58, weight: .semibold))
                            .foregroundStyle(fantome ? AnyShapeStyle(Theme.fantome) : AnyShapeStyle(Theme.degrade))
                            .shadow(color: Theme.accent.opacity(0.7), radius: 16)
                    }
                    .frame(height: 120)
                    Text(fantome ? "Mode Fantôme" : "VibeSearch")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.texte)
                    Text(fantome ? "Rien n'est gardé : historique, cookies et cache disparaissent à la fermeture (ou au bout de 24 h)."
                        : "Navigation rapide, sans pubs ni traqueurs.")
                        .font(.subheadline).foregroundStyle(Theme.texteDoux)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .padding(.top, 40)

                Button { nav.saisieActive = true } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Rechercher avec \(Reglages.partage.moteur.nom)")
                        Spacer()
                    }
                    .foregroundStyle(Theme.texteFaible)
                    .padding(.horizontal, 16).frame(height: 50)
                    .carteVerre()
                    .lueur(couleur: fantome ? Theme.fantome : Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                if !favoris.liste.isEmpty {
                    section("Favoris") {
                        LazyVGrid(columns: colonnes, spacing: 16) {
                            ForEach(favoris.liste) { f in
                                if let u = URL(string: f.url) { tuile(titre: f.titre, url: u) }
                            }
                        }
                    }
                }

                if !fantome {
                    let frequents = Historique.partage.sitesFrequents(8)
                    if !frequents.isEmpty {
                        section("Souvent visités") {
                            LazyVGrid(columns: colonnes, spacing: 16) {
                                ForEach(frequents, id: \.hote) { s in tuile(titre: s.hote, url: s.url) }
                            }
                        }
                    }
                }

                Button { feuille = .bouclier } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled").font(.title2).foregroundStyle(Theme.degrade)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bouclier actif").font(.headline).foregroundStyle(Theme.texte)
                            Text(resumeBouclier).font(.caption).foregroundStyle(Theme.texteDoux)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.texteFaible)
                    }
                    .padding(16)
                    .carteVerre()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background {
            RadialGradient(colors: [(fantome ? Theme.fantome : Theme.accent).opacity(0.16), .clear], center: .top, startRadius: 10, endRadius: 520)
                .ignoresSafeArea()
        }
        .onAppear { withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { pulse = true } }
    }

    private var resumeBouclier: String {
        let r = Reglages.partage
        var parties: [String] = []
        let n = Bloqueur.partage.nombreRegles
        if r.bloquerPubs || r.bloquerTraqueurs { parties.append(n > 0 ? "\(n.formatted()) règles de blocage" : "listes en préparation…") }
        if r.refuserCookies { parties.append("cookies refusés") }
        if r.bouclierEmpreinte { parties.append("empreinte brouillée") }
        return parties.joined(separator: " · ")
    }

    private func section<C: View>(_ titre: String, @ViewBuilder contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.texteFaible)
            contenu()
        }
        .padding(.horizontal, 20)
    }

    private func tuile(titre: String, url: URL) -> some View {
        Button { nav.ouvrir(url: url, nouvelOnglet: false) } label: {
            VStack(spacing: 7) {
                Text(Monogramme.lettre(titre: titre, url: url))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Monogramme.couleur(url.host() ?? titre).gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: Monogramme.couleur(url.host() ?? titre).opacity(0.45), radius: 8)
                Text(titre).font(.caption).lineLimit(1).foregroundStyle(Theme.texteDoux)
            }
        }
        .buttonStyle(BoutonRebond())
        .contextMenu {
            Button { nav.ouvrir(url: url, nouvelOnglet: true, arrierePlan: true) } label: { Label("Ouvrir dans un nouvel onglet", systemImage: "plus.square.on.square") }
            Button { nav.ouvrir(url: url, nouvelOnglet: true, fantome: true) } label: { Label("Ouvrir en Fantôme", systemImage: "theatermasks") }
            if Favoris.partage.contient(url) {
                Button(role: .destructive) { Favoris.partage.basculer(url: url, titre: titre) } label: { Label("Retirer des favoris", systemImage: "star.slash") }
            }
        }
    }
}

/// Couleur stable par site pour les monogrammes (pas d'icônes téléchargées : rien ne fuite).
enum Monogramme {
    private static let couleurs: [Color] = [Theme.accent, Theme.accent2, Theme.accent3, Color(hex: 0xF472B6), Color(hex: 0x34D399), Color(hex: 0xFBBF24), Color(hex: 0xFB7185), Color(hex: 0x22D3EE)]
    /// Initiale à afficher : celle du titre s'il y en a un, sinon du site (sans « www. » ni « m. »).
    static func lettre(titre: String?, url: URL?) -> String {
        var h = Adresse.courte(url)
        if h.hasPrefix("m.") { h.removeFirst(2) }
        let source = (titre?.isEmpty == false) ? titre! : h
        return String(source.prefix(1)).uppercased()
    }

    static func couleur(_ cle: String) -> Color {
        var h: UInt32 = 2166136261
        for b in cle.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return couleurs[Int(h % UInt32(couleurs.count))]
    }
}

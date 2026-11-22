import UniformTypeIdentifiers
import SwiftUI
import WebKit

/// Réglages.
struct ReglagesVue: View {
    @Binding var feuille: Feuille?
    @State private var r = Reglages.partage
    @State private var cle = Trousseau.lire("anthropic") ?? ""
    @State private var confirmation: String?
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { feuille = .aide } label: {
                        Label("Ouvrir les liens dans VibeSearch", systemImage: "arrow.up.forward.app")
                    }
                } footer: {
                    Text("Extension Safari, menu Partager, widget, Siri : les solutions gratuites à la place du « navigateur par défaut ».")
                }
                Section("Recherche") {
                    Picker("Moteur", selection: $r.moteur) {
                        ForEach(Moteur.allCases) { Text($0.nom).tag($0) }
                    }
                    Toggle("Réponse de Claude sur les résultats", isOn: $r.bulleRecherche)
                    Toggle("…automatique dès la recherche", isOn: $r.resumeAuto).disabled(!r.bulleRecherche)
                }
                if Extensions.bitwardenLivre {
                    Section {
                        Toggle(isOn: $r.extensionBitwarden) { Label("Bitwarden", systemImage: "key.fill") }
                        if r.extensionBitwarden {
                            Text(Extensions.etat).font(.caption).foregroundStyle(Theme.texteFaible)
                            if !Extensions.journal.isEmpty {
                                DisclosureGroup("Journal (\(Extensions.journal.count))") {
                                    Text(Extensions.journal.suffix(40).joined(separator: "\n"))
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.texteDoux)
                                        .textSelection(.enabled)
                                    Button("Copier le journal") { UIPasteboard.general.string = Extensions.journal.joined(separator: "\n") }
                                }
                            }
                        }
                    } header: { Text("Extensions") } footer: {
                        Text("Le vrai Bitwarden, intégré au navigateur (comme sur ordinateur) : remplissage des identifiants, clés d'accès, générateur de mots de passe. Ouvrez-le avec ⋯ › Bitwarden et connectez-vous une fois. Jamais actif dans le mode Fantôme.")
                    }
                }
                Section {
                    Toggle("Bloquer les pubs", isOn: $r.bloquerPubs)
                    Toggle("Bloquer les traqueurs", isOn: $r.bloquerTraqueurs)
                    Toggle("Refuser les bannières cookies", isOn: $r.refuserCookies)
                    Toggle("Brouiller l'empreinte du navigateur", isOn: $r.bouclierEmpreinte)
                    Toggle("Nettoyer les liens (utm, fbclid, gclid…)", isOn: $r.nettoyerLiens)
                    Toggle("HTTPS partout", isOn: $r.httpsPartout)
                } header: { Text("Vie privée") } footer: { Text("La position n'est jamais donnée aux sites, sans même vous le demander. HTTPS partout repasse en HTTP seulement si un site ne sait pas faire autrement.") }
                Section {
                    Toggle("Face ID pour le mode Fantôme", isOn: $r.verrouFantome)
                    Toggle("Face ID pour ouvrir VibeSearch", isOn: $r.verrouAppli)
                } header: { Text("Verrou") } footer: { Text("En mode Fantôme, le sélecteur d'applis n'affiche jamais la page.") }
                Section("YouTube") {
                    Toggle("Passer les pubs vidéo", isOn: $r.pubsYouTube)
                    Toggle("Sauter les sponsors", isOn: $r.sauterSponsors)
                    Toggle("Sauter les intros", isOn: $r.sauterIntros)
                    Toggle("Lecture en arrière-plan et écran verrouillé", isOn: $r.youtubeArrierePlan)
                }
                Section {
                    Toggle("Thème sombre imposé aux sites clairs", isOn: $r.sombreSites)
                    Toggle("Barre réduite pendant la lecture", isOn: $r.barreReductible)
                } header: { Text("Affichage") } footer: { Text("Le mode sombre, la taille du texte et la version ordinateur se règlent aussi site par site depuis le menu « … ».") }
                Section {
                    Toggle("Rouvrir les onglets au lancement", isOn: $r.restaurerSession)
                    Picker("Fermer les onglets oubliés", selection: $r.fermetureAuto) {
                        ForEach(FermetureAuto.allCases) { Text($0.nom).tag($0) }
                    }
                    Stepper("Onglets gardés en mémoire : \(r.ongletsVivants)", value: $r.ongletsVivants, in: 2 ... 10)
                } header: { Text("Onglets") } footer: { Text("Au-delà, les onglets s'endorment et se rechargent quand vous y revenez : moins de mémoire, plus d'autonomie.") }
                Section("Discussion chiffrée") {
                    Button { feuille = .discussion } label: { Label("Correspondants et invitations", systemImage: "bubble.left.and.bubble.right") }
                }
                Section {
                    SecureField("Clé d'API Claude (sk-ant-…)", text: $cle)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Trousseau.ecrire("anthropic", cle) }
                        .onChange(of: cle) { _, v in Trousseau.ecrire("anthropic", v) }
                    Picker("Modèle", selection: $r.modeleIA) {
                        ForEach(ModeleIA.allCases) { m in
                            VStack(alignment: .leading) { Text(m.nom); Text(m.detail).font(.caption).foregroundStyle(.secondary) }.tag(m)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Stepper("Plafond mensuel : \(r.plafondIA == 0 ? "aucun" : String(format: "%.0f $", r.plafondIA))", value: $r.plafondIA, in: 0 ... 200, step: 5)
                    HStack { Text("Dépensé ce mois-ci"); Spacer(); Text(String(format: "%.3f $", r.depenseDuMois)).foregroundStyle(.secondary) }
                    Button {
                        UIPasteboard.general.setItems([[UTType.plainText.identifier: cle]], options: [.expirationDate: Date.now.addingTimeInterval(120), .localOnly: true])
                    } label: { Label("Copier la clé pour le clavier IA", systemImage: "keyboard") }
                    .disabled(cle.isEmpty)
                } header: { Text("Intelligence artificielle") } footer: { Text("La clé est rangée dans le trousseau chiffré de l'iPhone. Elle se crée sur console.anthropic.com. La copie pour le clavier s'efface d'elle-même au bout de 2 minutes.") }
                Section {
                    Label("« Dis Siri, demande à VibeSearch »", systemImage: "waveform")
                    Label("Clavier : Réglages › Général › Clavier › Claviers › Ajouter › VibeSearch IA, puis « Autoriser l'accès complet ». Copie la clé ci-dessus, puis 🔑 sur le clavier.", systemImage: "keyboard")
                        .font(.callout)
                } header: { Text("Claude partout") } footer: { Text("Siri écoute ta question, Claude répond (avec recherche web pour l'actualité, la météo…) et Siri lit la réponse. Astuce : crée dans Raccourcis un raccourci nommé « Claude » avec l'action « Demander à Claude » pour dire simplement « Dis Siri, Claude ». Il se met aussi sur le bouton Action.") }
                Section("Données") {
                    Button("Effacer l'historique") { confirmation = "historique" }
                    Button("Effacer cookies et données des sites") { confirmation = "sites" }
                    Button("Vider le cache") { confirmation = "cache" }
                }
                if !r.parSite.isEmpty {
                    Section("Réglages par site") {
                        ForEach(r.parSite.keys.sorted(), id: \.self) { site in
                            let s = r.parSite[site] ?? ReglageSite()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site)
                                Text([s.zoom != 1 ? "texte \(Int(s.zoom * 100)) %" : nil, s.ordinateur ? "version ordinateur" : nil,
                                      s.sombre.map { $0 ? "sombre" : "clair" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { i in
                            let cles = r.parSite.keys.sorted()
                            for x in i { r.parSite[cles[x]] = nil }
                        }
                    }
                }
                if !r.sitesAutorises.isEmpty {
                    Section("Protection coupée sur") {
                        ForEach(r.sitesAutorises, id: \.self) { Text($0) }
                            .onDelete { r.sitesAutorises.remove(atOffsets: $0) }
                    }
                }
                Section("À propos") {
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?").foregroundStyle(.secondary) }
                    HStack { Text("Règles de blocage"); Spacer(); Text(Bloqueur.partage.nombreRegles.formatted()).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
            .confirmationDialog("Confirmer ?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { effacer(confirmation ?? "") }
            } message: {
                Text("Cette action est définitive.")
            }
        }
    }

    private func effacer(_ quoi: String) {
        let magasin = WKWebsiteDataStore.default()
        switch quoi {
        case "historique":
            Historique.partage.toutEffacer()
            Historique.partage.enregistrer()
        case "sites":
            magasin.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        case "cache":
            magasin.removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {}
        default:
            break
        }
    }
}

/// Historique groupé par jour, avec recherche.
struct HistoriqueVue: View {
    @Environment(Navigateur.self) private var nav
    @Environment(\.dismiss) private var fermer
    @State private var h = Historique.partage
    @State private var recherche = ""

    var body: some View {
        NavigationStack {
            let filtrees = recherche.isEmpty ? Array(h.visites.prefix(800))
                : h.visites.filter { $0.titre.localizedCaseInsensitiveContains(recherche) || $0.url.localizedCaseInsensitiveContains(recherche) }
            let jours = Dictionary(grouping: filtrees) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
            List {
                ForEach(jours, id: \.key) { jour, visites in
                    Section {
                        ForEach(visites) { v in
                            Button {
                                if let u = URL(string: v.url) { nav.ouvrir(url: u, nouvelOnglet: false) }
                                fermer()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.titre.isEmpty ? v.url : v.titre).lineLimit(1).foregroundStyle(Theme.texte)
                                    Text(Adresse.courte(URL(string: v.url)) + " · " + v.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption).foregroundStyle(Theme.texteFaible)
                                }
                            }
                            .swipeActions { Button("Retirer", role: .destructive) { h.retirer(v) } }
                        }
                    } header: {
                        HStack {
                            Text(jour.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            Spacer()
                            Button("Effacer ce jour") { h.retirerJour(jour) }.font(.caption)
                        }
                    }
                }
            }
            .overlay { if filtrees.isEmpty { ContentUnavailableView("Aucune page", systemImage: "clock") } }
            .searchable(text: $recherche, prompt: "Rechercher dans l'historique")
            .scrollContentBackground(.hidden)
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
    }
}

/// Favoris : ouvrir, réordonner, supprimer, ajouter la page en cours.
struct FavorisVue: View {
    @Environment(Navigateur.self) private var nav
    @Environment(\.dismiss) private var fermer
    @State private var f = Favoris.partage

    var body: some View {
        NavigationStack {
            List {
                if let o = nav.actif, let u = o.url, !o.fantome, !f.contient(u) {
                    Button { f.ajouter(url: u, titre: o.titre) } label: { Label("Ajouter « \(o.titreAffiche) »", systemImage: "star.badge.plus") }
                }
                ForEach(f.liste) { fav in
                    Button {
                        if let u = URL(string: fav.url) { nav.ouvrir(url: u, nouvelOnglet: false) }
                        fermer()
                    } label: {
                        HStack(spacing: 12) {
                            Text(Monogramme.lettre(titre: fav.titre, url: URL(string: fav.url)))
                                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Monogramme.couleur(URL(string: fav.url)?.host() ?? "").gradient, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fav.titre).lineLimit(1).foregroundStyle(Theme.texte)
                                Text(Adresse.courte(URL(string: fav.url))).font(.caption).foregroundStyle(Theme.texteFaible)
                            }
                        }
                    }
                }
                .onDelete { f.liste.remove(atOffsets: $0) }
                .onMove { f.liste.move(fromOffsets: $0, toOffset: $1) }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Favoris")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } }
            }
        }
    }
}

/// Téléchargements en cours et terminés.
struct TelechargementsVue: View {
    @Environment(\.dismiss) private var fermer
    @State private var t = Telechargements.partage

    var body: some View {
        NavigationStack {
            List {
                ForEach(t.elements) { e in
                    Button {
                        if let f = e.fichier, e.fini { Partage.presenter([f]) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: e.erreur != nil ? "exclamationmark.triangle.fill" : (e.fini ? "doc.fill" : "arrow.down.circle"))
                                .font(.title3)
                                .foregroundStyle(e.erreur != nil ? Theme.danger : (e.fini ? Theme.ok : Theme.accent))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.nom).lineLimit(1).foregroundStyle(Theme.texte)
                                if let err = e.erreur {
                                    Text(err).font(.caption).foregroundStyle(Theme.danger)
                                } else if !e.fini {
                                    ProgressView(value: e.progression).tint(Theme.accent)
                                } else {
                                    Text(e.debut.relatif).font(.caption).foregroundStyle(Theme.texteFaible)
                                }
                            }
                        }
                    }
                    .swipeActions { Button("Supprimer", role: .destructive) { t.retirer(e) } }
                }
            }
            .overlay {
                if t.elements.isEmpty {
                    ContentUnavailableView("Aucun téléchargement", systemImage: "arrow.down.circle",
                                           description: Text("Les fichiers arrivent dans Fichiers › Sur mon iPhone › VibeSearch › Téléchargements."))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Téléchargements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Vider") { t.viderListe() }.disabled(t.elements.isEmpty) }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } }
            }
        }
    }
}

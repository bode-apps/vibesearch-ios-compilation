import PhotosUI
import SwiftUI

/// Liste des correspondants de la discussion chiffrée (un ami, son propre PC…).
struct DiscussionVue: View {
    @Environment(\.dismiss) private var fermer
    @State private var d = Discussion.partage
    @State private var invitation: String?
    @State private var nomInvite = ""
    @State private var codeRejoindre = ""
    @State private var nomRejoindre = ""
    @State private var erreurRejoindre: String?
    @State private var mode: Mode?

    private enum Mode: String, Identifiable { case inviter, rejoindre; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            List {
                if d.contacts.isEmpty {
                    Section {
                        Text("Discutez de façon chiffrée avec VibeSearch PC (Gabin, ou votre propre ordinateur pour y envoyer des onglets). Rien ne reste sur le serveur : tout est effacé à la lecture, et au bout de 24 h.")
                            .font(.callout).foregroundStyle(Theme.texteDoux)
                    }
                }
                Section {
                    ForEach(d.contacts) { c in
                        NavigationLink(value: c.id) {
                            HStack(spacing: 12) {
                                Text(String(c.nom.prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Monogramme.couleur(c.id).gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.nom).foregroundStyle(Theme.texte)
                                    Text(c.rejoint ? (d.fil(c).last.map(Self.apercu) ?? "Aucun message") : "Invitation en attente…")
                                        .font(.caption).foregroundStyle(Theme.texteFaible).lineLimit(1)
                                }
                                Spacer()
                                let n = d.nonLus(c)
                                if n > 0 {
                                    Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.accent, in: Capsule())
                                }
                            }
                        }
                    }
                    .onDelete { i in for x in i { d.supprimer(d.contacts[x].id) } }
                }
                Section {
                    Button { mode = .inviter } label: { Label("Inviter quelqu'un (ou mon PC)", systemImage: "person.badge.plus") }
                    Button { mode = .rejoindre } label: { Label("Rejoindre avec un code", systemImage: "key.horizontal") }
                    HStack {
                        Text("Mon nom")
                        TextField("Nom affiché", text: $d.monNom).multilineTextAlignment(.trailing).foregroundStyle(Theme.texteDoux)
                    }
                } footer: {
                    Text("Chiffrement AES-256-GCM de bout en bout, compatible avec la discussion de VibeSearch PC. Les codes de vérification permettent de s'assurer que personne ne s'est intercalé.")
                }
                if let e = d.erreur {
                    Section { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in ConversationVue(idContact: id) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
            .sheet(item: $mode) { m in
                NavigationStack {
                    Form {
                        if m == .inviter {
                            if let code = invitation {
                                Section {
                                    Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                    Button { UIPasteboard.general.string = code } label: { Label("Copier le code", systemImage: "doc.on.doc") }
                                    ShareLink(item: code) { Label("Envoyer le code", systemImage: "square.and.arrow.up") }
                                } footer: {
                                    Text("Sur l'autre appareil : VibeSearch › Discussion › Rejoindre, puis collez ce code. Envoyez-le par un moyen sûr (en main propre, message chiffré).")
                                }
                            } else {
                                Section {
                                    TextField("Nom du correspondant (ex. Alex, Mon PC)", text: $nomInvite)
                                    Button("Créer l'invitation") { invitation = d.inviter(nom: nomInvite) }
                                        .disabled(nomInvite.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        } else {
                            Section {
                                TextField("Code VS1-…", text: $codeRejoindre, axis: .vertical)
                                    .font(.system(.callout, design: .monospaced))
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                Button { codeRejoindre = UIPasteboard.general.string ?? "" } label: { Label("Coller", systemImage: "doc.on.clipboard") }
                                TextField("Nom du correspondant", text: $nomRejoindre)
                                Button("Rejoindre") {
                                    erreurRejoindre = d.rejoindre(code: codeRejoindre, nom: nomRejoindre)
                                    if erreurRejoindre == nil { mode = nil }
                                }
                                .disabled(codeRejoindre.isEmpty || nomRejoindre.trimmingCharacters(in: .whitespaces).isEmpty)
                            } footer: {
                                if let e = erreurRejoindre { Text(e).foregroundStyle(Theme.danger) }
                            }
                        }
                    }
                    .navigationTitle(m == .inviter ? "Inviter" : "Rejoindre")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { mode = nil; invitation = nil; nomInvite = "" } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { d.demarrer() }
    }

    static func apercu(_ m: MessageChat) -> String {
        let qui = m.deMoi ? "Vous : " : ""
        switch m.genre {
        case "image": return qui + "📷 Photo"
        case "tab": return qui + "🔗 " + (m.titre ?? m.url ?? "Onglet")
        case "link": return qui + (m.url ?? "")
        default: return qui + (m.texte ?? "")
        }
    }
}

/// Fil d'une conversation.
struct ConversationVue: View {
    let idContact: String
    @Environment(Navigateur.self) private var nav
    @State private var d = Discussion.partage
    @State private var saisie = ""
    @State private var photo: PhotosPickerItem?
    @State private var details = false

    private var contact: ContactChat? { d.contacts.first { $0.id == idContact } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { defile in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let c = contact, !c.rejoint {
                            Label("En attente : \(c.nom) n'a pas encore utilisé l'invitation.", systemImage: "hourglass")
                                .font(.callout).foregroundStyle(Theme.texteDoux).padding(.top, 20)
                        }
                        ForEach(contact.map { d.fil($0) } ?? []) { m in bulle(m).id(m.id) }
                    }
                    .padding(14)
                }
                .onChange(of: contact.map { d.fil($0).count } ?? 0) { _, _ in
                    if let dernier = contact.flatMap({ d.fil($0).last }) { withAnimation { defile.scrollTo(dernier.id, anchor: .bottom) } }
                }
                .onAppear { if let dernier = contact.flatMap({ d.fil($0).last }) { defile.scrollTo(dernier.id, anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").font(.title3).foregroundStyle(Theme.accent)
                }
                if let o = nav.actif, let u = o.url, !o.fantome {
                    Button { d.envoyerOnglet(Adresse.aPartager(u), titre: o.titre, a: idContact) } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.forward").font(.title3).foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Envoyer l'onglet en cours")
                }
                TextField("Message", text: $saisie, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.fond2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button {
                    d.envoyer(texte: saisie, a: idContact)
                    saisie = ""
                } label: {
                    Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Theme.degrade, in: Circle())
                }
                .disabled(saisie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(contact?.nom ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { details = true } label: { Image(systemName: "checkmark.shield") }
            }
        }
        .alert("Code de vérification", isPresented: $details) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(contact.map { "\(CryptoChat.codeVerification($0.secret))\n\nLe même code doit s'afficher chez \($0.nom). Sinon, quelqu'un s'est intercalé : supprimez ce contact." } ?? "")
        }
        .onAppear {
            d.contactOuvert = idContact
            d.marquerLu(idContact)
            d.demarrer()
        }
        .onDisappear {
            d.contactOuvert = nil
            d.marquerLu(idContact)
            d.demarrer()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    d.envoyerImage(img, legende: nil, a: idContact)
                }
                photo = nil
            }
        }
    }

    @ViewBuilder
    private func bulle(_ m: MessageChat) -> some View {
        VStack(alignment: m.deMoi ? .trailing : .leading, spacing: 4) {
            Group {
                switch m.genre {
                case "image":
                    if let data = m.image, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contextMenu { Button { Partage.presenter([img]) } label: { Label("Partager", systemImage: "square.and.arrow.up") } }
                    }
                    if let t = m.texte { Text(t) }
                case "link", "tab":
                    Button {
                        if let u = URL(string: m.url ?? "") { nav.ouvrir(url: u, nouvelOnglet: true, fantome: false) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(m.genre == "tab" ? "Onglet" : "Lien", systemImage: m.genre == "tab" ? "rectangle.on.rectangle" : "link")
                                .font(.caption.bold()).foregroundStyle(Theme.accent3)
                            Text(m.titre ?? m.texte ?? Adresse.courte(URL(string: m.url ?? ""))).foregroundStyle(Theme.texte).multilineTextAlignment(.leading)
                            Text(m.url ?? "").font(.caption).foregroundStyle(Theme.texteFaible).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                default:
                    Text(m.texte ?? "").textSelection(.enabled)
                }
            }
            .padding(10)
            .background(m.deMoi ? AnyShapeStyle(Theme.accent.opacity(0.28)) : AnyShapeStyle(Theme.fond2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(m.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(Theme.texteFaible)
        }
        .frame(maxWidth: .infinity, alignment: m.deMoi ? .trailing : .leading)
        .padding(m.deMoi ? .leading : .trailing, 40)
    }
}

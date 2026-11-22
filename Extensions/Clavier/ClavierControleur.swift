import Security
import SwiftUI
import UIKit

// Clavier « VibeSearch IA » : après avoir écrit avec le clavier habituel, on passe sur ce clavier
// (touche 🌐) et un bouton suffit pour corriger, reformuler, raccourcir, traduire… le texte du champ
// (ou la sélection), grâce à Claude. « Annuler » remet le texte d'origine.

// MARK: - Contrôleur du clavier

final class ClavierControleur: UIInputViewController {
    private let etat = EtatClavier()

    override func viewDidLoad() {
        super.viewDidLoad()
        etat.controleur = self
        let hote = UIHostingController(rootView: VueClavier(etat: etat))
        hote.view.backgroundColor = .clear
        hote.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hote)
        view.addSubview(hote.view)
        NSLayoutConstraint.activate([
            hote.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hote.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hote.view.topAnchor.constraint(equalTo: view.topAnchor),
            hote.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hote.view.heightAnchor.constraint(equalToConstant: 276)
        ])
        hote.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        etat.accesComplet = hasFullAccess
        etat.afficherGlobe = needsInputModeSwitchKey
        etat.rafraichirApercu()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        etat.rafraichirApercu()
    }

    /// Texte visé : la sélection, sinon tout le texte accessible autour du curseur.
    func texteCible() -> (texte: String, selection: Bool) {
        let p = textDocumentProxy
        if let s = p.selectedText, !s.isEmpty { return (s, true) }
        return ((p.documentContextBeforeInput ?? "") + (p.documentContextAfterInput ?? ""), false)
    }

    /// Remplace le texte visé par `nouveau`.
    func remplacer(ancien: String, selection: Bool, par nouveau: String) {
        let p = textDocumentProxy
        if selection {
            p.insertText(nouveau) // remplace la sélection
            return
        }
        // Curseur en fin de texte, puis effacement caractère par caractère et insertion
        let apres = p.documentContextAfterInput ?? ""
        if !apres.isEmpty { p.adjustTextPosition(byCharacterOffset: apres.count) }
        for _ in 0 ..< ancien.count { p.deleteBackward() }
        p.insertText(nouveau)
    }

    func effacer() { textDocumentProxy.deleteBackward() }
    func inserer(_ t: String) { textDocumentProxy.insertText(t) }
}

// MARK: - État et appels à Claude

@MainActor
final class EtatClavier: ObservableObject {
    weak var controleur: ClavierControleur?
    @Published var accesComplet = true
    @Published var afficherGlobe = true
    @Published var enCours: Action?
    @Published var message: String?
    @Published var apercu = ""
    @Published var modele: String = UserDefaults.standard.string(forKey: "modele") ?? "claude-opus-5-5" {
        didSet { UserDefaults.standard.set(modele, forKey: "modele") }
    }
    /// Pour « Annuler » : texte d'origine et texte inséré.
    private var dernier: (avant: String, apres: String)?

    var peutAnnuler: Bool { dernier != nil }
    var aUneCle: Bool { CleClavier.lire() != nil }

    static let modeles = [("claude-opus-5-5", "Opus"), ("claude-sonnet-5-5", "Sonnet"), ("claude-haiku-5-5", "Haiku")]
    var nomModele: String { Self.modeles.first { $0.0 == modele }?.1 ?? "Opus" }

    func changerModele() {
        let i = Self.modeles.firstIndex { $0.0 == modele } ?? 0
        modele = Self.modeles[(i + 1) % Self.modeles.count].0
    }

    func rafraichirApercu() {
        guard let c = controleur else { return }
        let t = c.texteCible()
        apercu = t.texte.isEmpty ? "" : (t.selection ? "Sélection : " : "") + String(t.texte.suffix(90))
    }

    func collerCle() {
        guard accesComplet else { message = "Active d'abord « Autoriser l'accès complet »."; return }
        guard let t = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), t.hasPrefix("sk-ant-") else {
            message = "Copie d'abord ta clé dans VibeSearch (Réglages › Intelligence artificielle › Copier la clé pour le clavier)."
            return
        }
        CleClavier.ecrire(t)
        message = "Clé enregistrée ✓"
        objectWillChange.send()
    }

    func annuler() {
        guard let d = dernier, let c = controleur else { return }
        c.remplacer(ancien: d.apres, selection: false, par: d.avant)
        dernier = nil
        message = nil
        rafraichirApercu()
    }

    func lancer(_ action: Action) {
        guard enCours == nil, let c = controleur else { return }
        guard accesComplet else {
            message = "Réglages › Général › Clavier › Claviers › VibeSearch IA › Autoriser l'accès complet (nécessaire pour joindre Claude)."
            return
        }
        guard let cle = CleClavier.lire() else { message = "Touche 🔑 pour ajouter ta clé Claude."; return }
        let cible = c.texteCible()
        let texte = cible.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { message = "Écris (ou sélectionne) d'abord un texte, puis reviens sur ce clavier."; return }
        enCours = action
        message = nil
        Task {
            do {
                let resultat = try await Self.demander(action: action, texte: texte, cle: cle, modele: modele)
                c.remplacer(ancien: cible.texte, selection: cible.selection, par: resultat)
                dernier = (cible.texte, resultat)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                message = error.localizedDescription
            }
            enCours = nil
            rafraichirApercu()
        }
    }

    struct Erreur: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Appel direct à l'API Claude (Messages). Réponse courte : pas besoin de flux.
    static func demander(action: Action, texte: String, cle: String, modele: String) async throws -> String {
        var corps: [String: Any] = [
            "model": modele,
            "max_tokens": 8000,
            "system": """
            Tu es l'assistant d'écriture intégré au clavier de l'iPhone. Applique la consigne au texte fourni et \
            renvoie UNIQUEMENT le texte final, prêt à être inséré : sans guillemets, sans titre, sans explication. \
            Garde la langue du texte (sauf pour une traduction) et la mise en forme simple (retours à la ligne).
            """,
            "messages": [["role": "user", "content": "Consigne : \(action.consigne)\n\nTexte :\n\(texte)"]],
            "output_config": ["effort": "low"]
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(cle, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if modele != "claude-haiku-5-5" {
            corps["fallbacks"] = "default"
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: corps)
        let (data, rep) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (rep as? HTTPURLResponse)?.statusCode == 200, let json else {
            let m = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "erreur inconnue"
            if (rep as? HTTPURLResponse)?.statusCode == 401 { throw Erreur(message: "Clé refusée : recopie-la depuis VibeSearch (🔑).") }
            throw Erreur(message: "Claude : \(m)")
        }
        if json["stop_reason"] as? String == "refusal" { throw Erreur(message: "Claude a préféré ne pas traiter ce texte.") }
        let blocs = json["content"] as? [[String: Any]] ?? []
        let sortie = blocs.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sortie.isEmpty else { throw Erreur(message: "Réponse vide, réessaie.") }
        return sortie
    }
}

enum Action: String, CaseIterable, Identifiable {
    case corriger, reformuler, court, poli, familier, traduire, ecrire, emoji
    var id: String { rawValue }
    var titre: String {
        switch self {
        case .corriger: "Corriger"
        case .reformuler: "Reformuler"
        case .court: "Plus court"
        case .poli: "Plus poli"
        case .familier: "Détendu"
        case .traduire: "Traduire"
        case .ecrire: "Écrire"
        case .emoji: "Émojis"
        }
    }
    var icone: String {
        switch self {
        case .corriger: "checkmark.circle"
        case .reformuler: "arrow.triangle.2.circlepath"
        case .court: "scissors"
        case .poli: "briefcase"
        case .familier: "face.smiling"
        case .traduire: "globe"
        case .ecrire: "sparkles"
        case .emoji: "heart"
        }
    }
    var consigne: String {
        switch self {
        case .corriger: "Corrige l'orthographe, la grammaire, les accords et la ponctuation, sans changer le style ni le sens."
        case .reformuler: "Reformule pour que ce soit plus clair et plus naturel, en gardant le même ton et le même sens."
        case .court: "Raccourcis au maximum en gardant l'essentiel du message."
        case .poli: "Rends ce texte poli et professionnel (vouvoiement si c'est adapté)."
        case .familier: "Rends ce texte détendu et chaleureux, comme un message entre amis (tutoiement)."
        case .traduire: "Traduis en anglais si le texte est en français, sinon traduis en français."
        case .ecrire: "Le texte est une demande : rédige ce qui est demandé (message, mail, réponse…), prêt à envoyer."
        case .emoji: "Ajoute quelques émojis bien choisis au texte, sans changer les mots."
        }
    }
}

/// Clé Claude du clavier : son propre trousseau (le clavier ne partage pas les données de l'appli).
enum CleClavier {
    private static let service = "fr.vibe.search.clavier"
    static func lire() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "anthropic", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var res: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &res) == errSecSuccess, let d = res as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func ecrire(_ v: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "anthropic"]
        SecItemDelete(base as CFDictionary)
        var a = base
        a[kSecValueData as String] = Data(v.utf8)
        a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }
}

// MARK: - Interface

private let violet = Color(red: 124 / 255, green: 108 / 255, blue: 1)
private let degrade = LinearGradient(colors: [Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255), violet, Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

struct VueClavier: View {
    @ObservedObject var etat: EtatClavier
    private let colonnes = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            // Ligne d'état : aperçu du texte visé ou message
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(degrade)
                Text(etat.message ?? (etat.apercu.isEmpty ? "Écris ton texte, puis choisis une action" : "« \(etat.apercu) »"))
                    .font(.caption).lineLimit(2)
                    .foregroundStyle(etat.message == nil ? Color.secondary : Color.primary)
                Spacer(minLength: 0)
                Button(etat.nomModele) { etat.changerModele() }
                    .font(.caption.weight(.semibold)).foregroundStyle(violet)
            }
            .padding(.horizontal, 10).frame(height: 36)

            LazyVGrid(columns: colonnes, spacing: 8) {
                ForEach(Action.allCases) { a in
                    Button { etat.lancer(a) } label: {
                        VStack(spacing: 4) {
                            if etat.enCours == a { ProgressView().frame(height: 18) } else { Image(systemName: a.icone).font(.system(size: 17, weight: .semibold)) }
                            Text(a.titre).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .foregroundStyle(a == .ecrire ? .white : .primary)
                        .background(a == .ecrire ? AnyShapeStyle(degrade) : AnyShapeStyle(Color(.secondarySystemBackground)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .disabled(etat.enCours != nil)
                }
            }
            .padding(.horizontal, 6)

            // Rangée du bas : clavier suivant, clé, annuler, espace, effacer, retour
            HStack(spacing: 6) {
                if etat.afficherGlobe {
                    Button { etat.controleur?.advanceToNextInputMode() } label: { touche("globe") }
                }
                Button { etat.collerCle() } label: { touche(etat.aUneCle ? "key.fill" : "key") }
                Button { etat.annuler() } label: { touche("arrow.uturn.backward") }.disabled(!etat.peutAnnuler)
                Button { etat.controleur?.inserer(" ") } label: {
                    Text("espace").font(.subheadline).frame(maxWidth: .infinity).frame(height: 42)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Button { etat.controleur?.effacer() } label: { touche("delete.left") }
                Button { etat.controleur?.inserer("\n") } label: { touche("return") }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 8)
    }

    private func touche(_ icone: String) -> some View {
        Image(systemName: icone).font(.system(size: 16, weight: .medium))
            .frame(width: 42, height: 42)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

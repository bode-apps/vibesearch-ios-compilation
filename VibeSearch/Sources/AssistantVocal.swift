import AppIntents
import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Claude comme assistant vocal : « Dis Siri, demande à VibeSearch » → Siri écoute la question,
/// Claude répond (avec recherche web pour l'actualité, la météo, les horaires…), Siri lit la réponse.
/// Les questions qui se suivent à moins de 10 minutes forment une conversation.
@MainActor
enum AssistantVocal {
    private static let cleHistorique = "assistantHistorique"
    private static let cleDate = "assistantDate"

    struct Erreur: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `ecran` : capture de l'écran (JPEG) quand la question porte sur ce qui est affiché.
    static func repondre(_ question: String, ecran: Data? = nil) async throws -> String {
        guard let cle = Trousseau.lire("anthropic"), !cle.isEmpty else {
            throw Erreur(message: "Ajoute d'abord ta clé Claude dans VibeSearch, Réglages, Intelligence artificielle.")
        }
        let r = Reglages.partage
        guard !r.plafondAtteint else { throw Erreur(message: "Le plafond mensuel de dépense de Claude est atteint.") }

        // Conversation en cours (moins de 10 minutes, et pas trop longue)
        let d = UserDefaults.standard
        var messages: [[String: Any]] = []
        if ecran == nil, let date = d.object(forKey: cleDate) as? Date, Date.now.timeIntervalSince(date) < 600,
           d.string(forKey: "assistantModele") == Reglages.partage.modeleIA.rawValue,
           let data = d.data(forKey: cleHistorique),
           let anciens = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], anciens.count < 12 {
            messages = anciens
        }
        var contenu: [[String: Any]] = []
        if let ecran {
            contenu.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": ecran.base64EncodedString()]])
        }
        // L'heure va dans la question (elle change), jamais dans les instructions : le raisonnement de Claude
        // est lié aux instructions, qui doivent rester identiques pendant toute la conversation.
        let maintenant = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(Locale(identifier: "fr_FR")))
        contenu.append(["type": "text", "text": "(Nous sommes le \(maintenant).)\n\(question)"])
        messages.append(["role": "user", "content": contenu])

        let systeme = """
        Tu es Claude, l'assistant vocal sur l'iPhone de Bode. Ta réponse sera LUE À VOIX HAUTE par Siri : \
        réponds en français, en une à trois phrases courtes et naturelles, sans Markdown, sans listes, sans émojis, \
        sans adresses web ni références entre crochets. Pour tout ce qui dépend de l'actualité (météo, actualités, \
        horaires, prix, résultats sportifs…), utilise la recherche web. Bode est en France ; la date et l'heure sont au début de chaque question.
        """ + (ecran == nil ? "" : """
         L'image jointe est une capture de ce qui est affiché à l'écran en ce moment (l'appli que Bode utilise). \
        Si on te demande de rédiger quelque chose (réponse à un message, commentaire, mail), donne UNIQUEMENT le texte \
        à envoyer, sans introduction : il sera copié dans le presse-papiers pour être collé.
        """)
        let outils: [[String: Any]] = [[
            "type": "web_search_20260209", "name": "web_search", "max_uses": 3,
            "user_location": ["type": "approximate", "country": "FR", "timezone": "Europe/Paris"]
        ]]
        let client = Claude(cle: cle, modele: r.modeleIA)
        var texte = ""
        // « pause_turn » : la recherche web n'est pas finie, on relance (au plus 3 fois)
        for _ in 0 ..< 3 {
            var motif: String?
            var complet = false
            for try await ev in client.envoyer(systeme: systeme, messages: messages, outils: outils, effort: "low") {
                switch ev {
                case let .texte(t):
                    texte += t
                case let .fin(blocs, entree, sortie, lecture, ecriture, arret, servi, fini):
                    r.ajouterDepense(client.cout(entree: entree, sortie: sortie, lectureCache: lecture, ecritureCache: ecriture, modeleServi: servi))
                    motif = arret
                    complet = fini
                    if fini && !blocs.isEmpty && arret != "refusal" { messages.append(["role": "assistant", "content": blocs]) }
                }
            }
            if motif == "refusal" { throw Erreur(message: "Claude a préféré ne pas répondre à cette question.") }
            if motif != "pause_turn" || !complet { break }
        }
        let reponse = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reponse.isEmpty else { throw Erreur(message: "Claude n'a pas répondu, réessaie.") }
        // Conversation gardée pour la question suivante (pas les captures d'écran, trop lourdes)
        if ecran == nil, let data = try? JSONSerialization.data(withJSONObject: messages) {
            d.set(data, forKey: cleHistorique)
            d.set(Date.now, forKey: cleDate)
            d.set(Reglages.partage.modeleIA.rawValue, forKey: "assistantModele")
        }
        return reponse
    }
}

struct DemanderAClaude: AppIntent {
    static let title: LocalizedStringResource = "Demander à Claude"
    static let description = IntentDescription("Pose une question à Claude à la voix ; Siri lit la réponse.")

    @Parameter(title: "Question", requestValueDialog: IntentDialog("Que veux-tu demander à Claude ?"))
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let reponse = try await AssistantVocal.repondre(question)
        return .result(value: reponse, dialog: "\(reponse)")
    }
}

/// Claude sur ce qui est à l'écran, depuis n'importe quelle appli : un raccourci (toucher deux fois le dos
/// de l'iPhone, bouton Action…) prend une capture, dicte la question et lance cette action.
/// La réponse est lue à voix haute et copiée dans le presse-papiers (pour la coller dans l'appli).
struct ClaudeSurLEcran: AppIntent {
    static let title: LocalizedStringResource = "Claude sur l'écran"
    static let description = IntentDescription("Pose une question à Claude sur ce qui est affiché. La réponse est lue à voix haute et copiée.")

    @Parameter(title: "Question")
    var question: String

    @Parameter(title: "Capture d'écran")
    var capture: IntentFile?

    @Parameter(title: "Lire la réponse à voix haute", default: true)
    var lire: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let image = capture.flatMap { UIImage(data: $0.data) }.flatMap(Self.reduire)
        let reponse = try await AssistantVocal.repondre(question, ecran: image)
        UIPasteboard.general.string = reponse
        if lire { await Voix.lire(reponse) }
        return .result(value: reponse, dialog: "\(reponse)")
    }

    /// Capture réduite (1568 px au plus, JPEG) : plus rapide et moins chère à envoyer.
    private static func reduire(_ img: UIImage) -> Data? {
        let cote = max(img.size.width * img.scale, img.size.height * img.scale)
        let echelle = min(1, 1568 / max(cote, 1))
        let taille = CGSize(width: img.size.width * img.scale * echelle, height: img.size.height * img.scale * echelle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: taille, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: taille)) }
            .jpegData(compressionQuality: 0.8)
    }
}

/// Synthèse vocale française ; attend la fin de la lecture (l'appli reste éveillée jusque-là).
@MainActor
final class Voix: NSObject, AVSpeechSynthesizerDelegate {
    private static let partage = Voix()
    private let synthe = AVSpeechSynthesizer()
    private var fin: CheckedContinuation<Void, Never>?

    static func lire(_ texte: String) async {
        let v = partage
        v.synthe.delegate = v
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let enonce = AVSpeechUtterance(string: texte)
        enonce.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        enonce.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        await withCheckedContinuation { suite in
            v.fin = suite
            v.synthe.speak(enonce)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.fin?.resume(); self.fin = nil }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.fin?.resume(); self.fin = nil }
    }
}
import AppIntents
import Foundation

// Raccourcis : Siri, Spotlight, bouton Action, appli Raccourcis (et « Partager › Raccourci »).

struct OuvrirDansVibeSearch: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir dans VibeSearch"
    static let description = IntentDescription("Ouvre une adresse (ou lance une recherche) dans un nouvel onglet VibeSearch.")
    static let openAppWhenRun = true

    @Parameter(title: "Adresse ou recherche")
    var texte: String

    @MainActor
    func perform() async throws -> some IntentResult {
        if let u = Adresse.interpreter(texte) { Navigateur.partage.ouvrir(url: u, nouvelOnglet: true, fantome: false) }
        return .result()
    }
}

struct RechercherDansVibeSearch: AppIntent {
    static let title: LocalizedStringResource = "Rechercher avec VibeSearch"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let nav = Navigateur.partage
        if nav.actif?.estAccueil != true { nav.nouvelOnglet(fantome: false, activer: true) }
        nav.saisieActive = true
        return .result()
    }
}

struct OngletFantome: AppIntent {
    static let title: LocalizedStringResource = "Nouvel onglet Fantôme"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigateur.partage.nouvelOnglet(fantome: true, activer: true)
        return .result()
    }
}

struct OuvrirDiscussion: AppIntent {
    static let title: LocalizedStringResource = "Discussion VibeSearch"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigateur.partage.panneauDemande = .discussion
        return .result()
    }
}

struct RaccourcisVibeSearch: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DemanderAClaude(), phrases: ["Demande à \(.applicationName)", "Pose une question à \(.applicationName)", "\(.applicationName) j'ai une question"],
                    shortTitle: "Demander à Claude", systemImageName: "sparkles")
        AppShortcut(intent: RechercherDansVibeSearch(), phrases: ["Rechercher avec \(.applicationName)", "Chercher sur \(.applicationName)"],
                    shortTitle: "Rechercher", systemImageName: "magnifyingglass")
        AppShortcut(intent: OngletFantome(), phrases: ["Onglet Fantôme dans \(.applicationName)", "Navigation privée \(.applicationName)"],
                    shortTitle: "Onglet Fantôme", systemImageName: "theatermasks")
        AppShortcut(intent: OuvrirDiscussion(), phrases: ["Discussion \(.applicationName)", "Messages \(.applicationName)"],
                    shortTitle: "Discussion", systemImageName: "bubble.left.and.bubble.right")
    }
}

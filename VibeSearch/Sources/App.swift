import AVFoundation
import BackgroundTasks
import SwiftUI

/// Point d'entrée de VibeSearch pour iPhone.
@main
struct VibeSearchApp: App {
    @State private var navigateur = Navigateur.partage
    @State private var verrou = Verrou.partage
    @Environment(\.scenePhase) private var phase
    @State private var etaitEnArrierePlan = true

    init() {
        Bloqueur.partage.preparer()
        Consentement.partage.prechauffer()
        Apparence.appliquer()
        // Son des vidéos en arrière-plan et écran verrouillé (YouTube, podcasts…)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        // Relève de la discussion chiffrée quand l'appli est fermée
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Discussion.tacheReleve, using: nil) { tache in
            Task { @MainActor in
                Discussion.programmerReleve()
                await Discussion.partage.releverEnArrierePlan()
                tache.setTaskCompleted(success: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigateurVue()
                .environment(navigateur)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .overlay {
                    // Verrou Face ID, et rideau dans le sélecteur d'applis en mode Fantôme
                    if verrou.verrouille || (phase != .active && (navigateur.modeFantome || Reglages.partage.verrouAppli)) {
                        Rideau(verrouille: verrou.verrouille) { verrou.deverrouiller() }
                            .transition(.opacity)
                    }
                }
                .onOpenURL { ouvrir($0) }
                .task { Essai.depuisArguments(navigateur) }
        }
        .onChange(of: phase) { _, nouvelle in
            switch nouvelle {
            case .background:
                etaitEnArrierePlan = true
                navigateur.enregistrerSession()
                Historique.partage.enregistrer()
                Favoris.partage.enregistrer()
                Discussion.partage.arreter()
                if !Discussion.partage.contacts.isEmpty { Discussion.programmerReleve() }
            case .active:
                if etaitEnArrierePlan {
                    etaitEnArrierePlan = false
                    verrou.verifier(fantome: navigateur.modeFantome)
                    if verrou.verrouille { verrou.deverrouiller() }
                    navigateur.verifierFantome()
                    navigateur.fermerOnglesOublies()
                }
                Discussion.partage.demarrer()
            default:
                break
            }
        }
    }

    /// Liens « vibesearch:… » : extension de partage, extension Safari, widget, raccourcis.
    ///  vibesearch:https://exemple.fr · vibesearch://exemple.fr · vibesearch://recherche ·
    ///  vibesearch://fantome · vibesearch://discussion
    private func ouvrir(_ url: URL) {
        var s = url.absoluteString
        for prefixe in ["vibesearch://", "vibesearch:"] where s.hasPrefix(prefixe) {
            s.removeFirst(prefixe.count)
            break
        }
        switch s.lowercased() {
        case "recherche", "recherche/":
            if navigateur.actif?.estAccueil != true { navigateur.nouvelOnglet(fantome: false, activer: true) }
            navigateur.saisieActive = true
        case "fantome", "fantome/":
            navigateur.nouvelOnglet(fantome: true, activer: true)
        case "discussion", "discussion/":
            navigateur.panneauDemande = .discussion
        default:
            if let u = Adresse.interpreter(s.removingPercentEncoding ?? s) { navigateur.ouvrir(url: u, nouvelOnglet: true, fantome: false) }
        }
    }
}

/// Essais automatiques dans le simulateur (workflow « essai ») :
/// `-ouvrir <adresse>` ouvre une page dans un nouvel onglet, `-grille` affiche les onglets,
/// `-panneau <nom>` ouvre un panneau (menu, reglages, discussion…).
@MainActor
enum Essai {
    static func depuisArguments(_ nav: Navigateur) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-ouvrir"), i + 1 < args.count, let u = Adresse.interpreter(args[i + 1]) {
            nav.ouvrir(url: u, nouvelOnglet: true)
        }
        if args.contains("-grille") { nav.grilleVisible = true }
        if args.contains("-bitwarden") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { Extensions.ouvrirBitwarden() }
        }
        if let i = args.firstIndex(of: "-panneau"), i + 1 < args.count, let f = Feuille(rawValue: args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { nav.panneauDemande = f }
        }
    }
}

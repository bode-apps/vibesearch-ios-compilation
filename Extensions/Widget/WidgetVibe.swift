import AppIntents
import SwiftUI
import WidgetKit

// Widgets VibeSearch : barre de recherche (écran d'accueil), raccourci (écran verrouillé),
// et bouton du Centre de contrôle (iOS 18). Tous ouvrent l'appli par un lien vibesearch://.

private let violet = Color(red: 124 / 255, green: 108 / 255, blue: 1)
private let degrade = LinearGradient(colors: [Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255), violet, Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

struct EntreeVibe: TimelineEntry { let date: Date }

struct FournisseurVibe: TimelineProvider {
    func placeholder(in context: Context) -> EntreeVibe { EntreeVibe(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (EntreeVibe) -> Void) { completion(EntreeVibe(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeVibe>) -> Void) {
        completion(Timeline(entries: [EntreeVibe(date: .now)], policy: .never))
    }
}

struct VueWidget: View {
    @Environment(\.widgetFamily) private var famille
    var entree: EntreeVibe

    var body: some View {
        switch famille {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "sparkle.magnifyingglass").font(.title2.weight(.semibold))
            }
            .widgetURL(URL(string: "vibesearch://recherche"))
        case .accessoryRectangular:
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                Text("Rechercher").font(.headline)
            }
            .widgetURL(URL(string: "vibesearch://recherche"))
        case .systemMedium:
            VStack(spacing: 12) {
                Link(destination: URL(string: "vibesearch://recherche")!) { barre }
                HStack(spacing: 12) {
                    bouton("theatermasks.fill", "Fantôme", "vibesearch://fantome")
                    bouton("bubble.left.and.bubble.right.fill", "Discussion", "vibesearch://discussion")
                }
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(degrade)
                Spacer()
                Text("VibeSearch").font(.headline).foregroundStyle(.white)
                Text("Rechercher").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "vibesearch://recherche"))
        }
    }

    private var barre: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            Text("Rechercher ou saisir une adresse").lineLimit(1)
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 14).frame(height: 44)
        .background(.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(violet.opacity(0.6)))
    }

    private func bouton(_ icone: String, _ titre: String, _ lien: String) -> some View {
        Link(destination: URL(string: lien)!) {
            Label(titre, systemImage: icone).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct WidgetRecherche: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RechercheVibeSearch", provider: FournisseurVibe()) { e in
            VueWidget(entree: e)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 10 / 255, green: 9 / 255, blue: 32 / 255), Color(red: 25 / 255, green: 22 / 255, blue: 67 / 255)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Recherche VibeSearch")
        .description("Rechercher, ouvrir un onglet Fantôme ou la discussion.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// Bouton du Centre de contrôle / écran verrouillé / bouton Action (iOS 18).
@available(iOS 18.0, *)
struct ControleRecherche: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "fr.vibe.search.controle") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "vibesearch://recherche")!)) {
                Label("VibeSearch", systemImage: "sparkle.magnifyingglass")
            }
        }
        .displayName("Recherche VibeSearch")
        .description("Ouvre VibeSearch prêt à rechercher.")
    }
}

@main
struct PaquetWidgets: WidgetBundle {
    var body: some Widget {
        WidgetRecherche()
        if #available(iOS 18.0, *) {
            ControleRecherche()
        }
    }
}

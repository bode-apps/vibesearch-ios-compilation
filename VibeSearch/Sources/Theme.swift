import SwiftUI
import UIKit

/// Design « Neon Glass » repris de la version PC : bleu-violet sombre, LED, arrondis façon Apple TV.
enum Theme {
    static let fond0 = Color(hex: 0x05040E)
    static let fond1 = Color(hex: 0x0A0920)
    static let fond2 = Color(hex: 0x110F2E)
    static let fond3 = Color(hex: 0x191643)
    static let verre = Color(red: 24 / 255, green: 21 / 255, blue: 62 / 255).opacity(0.62)
    static let trait = Color(red: 170 / 255, green: 160 / 255, blue: 1).opacity(0.12)
    static let traitFort = Color(red: 170 / 255, green: 160 / 255, blue: 1).opacity(0.22)

    static let texte = Color(hex: 0xEEEBFF)
    static let texteDoux = Color(hex: 0xAAA5D6)
    static let texteFaible = Color(hex: 0x6F6AA3)

    static let accent = Color(hex: 0x7C6CFF)
    static let accent2 = Color(hex: 0xA855F7)
    static let accent3 = Color(hex: 0x38BDF8)
    static let danger = Color(hex: 0xFB7185)
    static let ok = Color(hex: 0x34D399)
    static let fantome = Color(hex: 0xC084FC)

    static let degrade = LinearGradient(colors: [accent3, accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let degradeLED = LinearGradient(colors: [accent3, accent, accent2, accent3], startPoint: .leading, endPoint: .trailing)

    static let rayon: CGFloat = 16
    static let rayonGrand: CGFloat = 22
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Lueur LED autour d'un élément (bouton actif, barre en cours de chargement…).
struct LueurLED: ViewModifier {
    var actif = true
    var couleur = Theme.accent
    func body(content: Content) -> some View {
        content
            .shadow(color: actif ? couleur.opacity(0.45) : .clear, radius: 9)
            .shadow(color: actif ? Theme.accent2.opacity(0.18) : .clear, radius: 22)
    }
}

extension View {
    func lueur(_ actif: Bool = true, couleur: Color = Theme.accent) -> some View { modifier(LueurLED(actif: actif, couleur: couleur)) }

    /// Carte en verre dépoli.
    func carteVerre(rayon: CGFloat = Theme.rayon) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: rayon, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: rayon, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
    }
}

/// Bouton rond façon tvOS (léger rebond à l'appui).
struct BoutonRebond: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum Apparence {
    /// Couleurs UIKit (listes, barres de navigation des feuilles) accordées au thème.
    static func appliquer() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.texte)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.texte)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}

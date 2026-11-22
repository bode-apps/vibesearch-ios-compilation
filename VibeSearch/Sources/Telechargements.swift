import Foundation
import Observation
import WebKit

/// Téléchargements : enregistrés dans « Fichiers › Sur mon iPhone › VibeSearch › Téléchargements ».
@MainActor
@Observable
final class Telechargements: NSObject {
    static let partage = Telechargements()

    struct Element: Identifiable {
        let id = UUID()
        var nom: String
        var progression = 0.0
        var fini = false
        var erreur: String?
        var fichier: URL?
        let debut = Date()
        /// Téléchargé en mode Fantôme : fichier temporaire, effacé à la fin de la session Fantôme.
        var fantome = false
    }

    private(set) var elements: [Element] = []
    var enCours: Int { elements.filter { !$0.fini && $0.erreur == nil }.count }
    @ObservationIgnored private var suivis: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var observations: [UUID: NSKeyValueObservation] = [:]
    /// Le dernier téléchargement terminé, pour la bulle « Ouvrir ».
    var dernierFini: Element?

    static var dossier: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Téléchargements", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Dossier temporaire des téléchargements Fantôme (hors de « Fichiers », vidé à la fin de la session).
    static var dossierFantome: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("Fantome", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func effacerFantome() {
        try? FileManager.default.removeItem(at: Self.dossierFantome)
        elements.removeAll { $0.fantome }
        if dernierFini?.fantome == true { dernierFini = nil }
    }

    func suivre(_ d: WKDownload, fantome: Bool = false) {
        var e = Element(nom: d.originalRequest?.url?.lastPathComponent ?? "fichier")
        e.fantome = fantome
        elements.insert(e, at: 0)
        suivis[ObjectIdentifier(d)] = e.id
        d.delegate = self
        observations[e.id] = d.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
            let f = p.fractionCompleted
            Task { @MainActor in self?.modifier(e.id) { $0.progression = f } }
        }
    }

    private func modifier(_ id: UUID, _ change: (inout Element) -> Void) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        change(&elements[i])
    }

    func retirer(_ e: Element) {
        if let f = e.fichier { try? FileManager.default.removeItem(at: f) }
        elements.removeAll { $0.id == e.id }
    }

    func viderListe() { elements.removeAll { $0.fini || $0.erreur != nil } }

    /// Nom libre dans le dossier (« photo.jpg » → « photo 2.jpg »).
    private func destinationLibre(_ nom: String, fantome: Bool) -> URL {
        let dossier = fantome ? Self.dossierFantome : Self.dossier
        let propre = nom.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let base = (propre as NSString).deletingPathExtension
        let ext = (propre as NSString).pathExtension
        var url = dossier.appendingPathComponent(propre.isEmpty ? "fichier" : propre)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dossier.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}

extension Telechargements: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let id0 = suivis[ObjectIdentifier(download)]
        let fantome = elements.first { $0.id == id0 }?.fantome ?? false
        let dest = destinationLibre(suggestedFilename, fantome: fantome)
        if let id = id0 {
            modifier(id) {
                $0.nom = dest.lastPathComponent
                $0.fichier = dest
            }
        }
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = suivis.removeValue(forKey: ObjectIdentifier(download)) else { return }
        observations[id] = nil
        modifier(id) {
            $0.fini = true
            $0.progression = 1
        }
        dernierFini = elements.first { $0.id == id }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = suivis.removeValue(forKey: ObjectIdentifier(download)) else { return }
        observations[id] = nil
        modifier(id) { $0.erreur = error.localizedDescription }
    }
}

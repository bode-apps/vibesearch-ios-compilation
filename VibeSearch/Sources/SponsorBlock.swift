import CryptoKit
import Foundation

/// Base communautaire SponsorBlock : passages « sponsor » et « intro » des vidéos YouTube.
/// Confidentialité : seuls les 4 premiers caractères de l'empreinte SHA-256 de l'identifiant
/// sont envoyés ; le serveur répond pour des centaines de vidéos et on garde la bonne.
@MainActor
final class SponsorBlock {
    static let partage = SponsorBlock()

    struct Segment { let debut: Double; let fin: Double; let categorie: String; let uuid: String }
    private var cache: [String: [Segment]] = [:]
    /// Session sans cache ni cookies sur le disque (rien ne garde la trace des vidéos regardées).
    private let session = URLSession(configuration: .ephemeral)

    func segments(video id: String) async -> [Segment] {
        let r = Reglages.partage
        var categories: [String] = []
        if r.sauterSponsors { categories.append("sponsor") }
        if r.sauterIntros { categories.append("intro") }
        guard !categories.isEmpty, id.count == 11 else { return [] }
        let tous: [Segment]
        if let c = cache[id] {
            tous = c
        } else {
            tous = await telecharger(id)
            if !Navigateur.partage.modeFantome { cache[id] = tous }
            if cache.count > 200 { cache.removeAll() }
        }
        return tous.filter { categories.contains($0.categorie) }
    }

    private func telecharger(_ id: String) async -> [Segment] {
        let empreinte = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        var c = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments/\(empreinte.prefix(4))")!
        c.queryItems = [
            URLQueryItem(name: "categories", value: "[\"sponsor\",\"intro\"]"),
            URLQueryItem(name: "actionTypes", value: "[\"skip\"]")
        ]
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("VibeSearch-iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, rep) = try? await session.data(for: req),
              (rep as? HTTPURLResponse)?.statusCode == 200,
              let videos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let video = videos.first { $0["videoID"] as? String == id }
        let segs = video?["segments"] as? [[String: Any]] ?? []
        return segs.compactMap { s in
            guard let bornes = s["segment"] as? [Double], bornes.count == 2, bornes[1] > bornes[0] + 1,
                  let cat = s["category"] as? String else { return nil }
            return Segment(debut: bornes[0], fin: bornes[1], categorie: cat, uuid: s["UUID"] as? String ?? UUID().uuidString)
        }
    }
}

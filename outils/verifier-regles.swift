// Vérifie les listes de blocage avec le VRAI compilateur WebKit (sur le Mac de GitHub, avant
// la compilation de l'appli). Une règle refusée par WebKit ferait échouer toute sa liste sur
// l'iPhone : on isole les fautives par dichotomie, on les retire et on réécrit le fichier.
// Usage : swift outils/verifier-regles.swift VibeSearch/Ressources/Generees
import Foundation
import WebKit

let dossier = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "VibeSearch/Ressources/Generees")
let peutEtre: WKContentRuleListStore? = WKContentRuleListStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("verif-\(UUID().uuidString)"))
guard let magasin = peutEtre else { fatalError("magasin WebKit indisponible") }
var retirees = 0

/// Compilation synchrone : on fait tourner la boucle principale jusqu'à la réponse de WebKit.
func compile(_ regles: [Any]) -> Error? {
    guard let data = try? JSONSerialization.data(withJSONObject: regles), let json = String(data: data, encoding: .utf8) else { return nil }
    var fini = false
    var erreur: Error?
    magasin.compileContentRuleList(forIdentifier: "essai", encodedContentRuleList: json) { _, err in
        erreur = err
        fini = true
    }
    let limite = Date().addingTimeInterval(300)
    while !fini {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if Date() > limite { print("ERREUR : WebKit ne répond pas"); exit(2) }
    }
    return erreur
}

/// Renvoie le sous-ensemble valide (ordre conservé).
func valides(_ regles: [Any]) -> [Any] {
    if regles.isEmpty { return [] }
    guard let err = compile(regles) else { return regles }
    if regles.count == 1 {
        retirees += 1
        if retirees > 400 { print("ERREUR : trop de règles refusées, le convertisseur produit un format que WebKit ne comprend pas"); exit(1) }
        if retirees <= 30, let d = try? JSONSerialization.data(withJSONObject: regles[0]) {
            print("  règle refusée : \(String(data: d, encoding: .utf8) ?? "?") — \(err.localizedDescription)")
        }
        return []
    }
    let milieu = regles.count / 2
    return valides(Array(regles[..<milieu])) + valides(Array(regles[milieu...]))
}
let fichiers = try FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("regles-") && $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
var comptes: [String: Int] = [:]
for f in fichiers {
    let debut = Date()
    guard let regles = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? [Any] else { fatalError("JSON illisible : \(f.lastPathComponent)") }
    let avant = retirees
    let ok = valides(regles)
    if ok.count != regles.count {
        try JSONSerialization.data(withJSONObject: ok).write(to: f)
    }
    let id = String(f.deletingPathExtension().lastPathComponent.dropFirst("regles-".count))
    comptes[id] = ok.count
    print("\(f.lastPathComponent) : \(ok.count) règles valides, \(retirees - avant) retirées, \(String(format: "%.1f", Date().timeIntervalSince(debut))) s")
    if ok.count < regles.count / 2 { print("ERREUR : plus de la moitié des règles refusées"); exit(1) }
}

// Comptes à jour dans le manifeste
let manifeste = dossier.appendingPathComponent("listes.json")
if var m = try JSONSerialization.jsonObject(with: Data(contentsOf: manifeste)) as? [String: Any], var listes = m["listes"] as? [[String: Any]] {
    for i in listes.indices { if let id = listes[i]["id"] as? String, let n = comptes[id] { listes[i]["regles"] = n } }
    m["listes"] = listes
    try JSONSerialization.data(withJSONObject: m, options: .prettyPrinted).write(to: manifeste)
}
print("Vérification terminée : \(retirees) règle(s) retirée(s) au total")

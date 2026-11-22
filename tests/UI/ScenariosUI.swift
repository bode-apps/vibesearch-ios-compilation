import XCTest

/// Scénarios reproduits dans le simulateur (signalements de l'utilisateur).
final class ScenariosUI: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Recherche Google → fermeture de l'appli → réouverture → toucher dans la page = plantage signalé.
    func testToucherApresReouverture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ouvrir", "https://www.google.com/search?udm=14&q=tour+eiffel"]
        app.launch()
        sleep(15) // chargement + enregistrement de la session (3 s après la fin du chargement)
        // Témoin : toucher pendant le premier lancement
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "Plantage dès le premier lancement")
        app.terminate()

        app.launchArguments = []
        app.launch()
        sleep(12)
        for (x, y) in [(0.5, 0.35), (0.5, 0.5), (0.3, 0.25), (0.6, 0.6)] {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            sleep(3)
            XCTAssertEqual(app.state, .runningForeground, "L'appli s'est fermée après un toucher en (\(x), \(y))")
            if app.state != .runningForeground { return }
            // Revenir sur la page de résultats si le toucher a ouvert un lien
            if app.buttons["chevron.backward"].exists && app.buttons["chevron.backward"].isEnabled { app.buttons["chevron.backward"].tap(); sleep(2) }
        }
        // Même chose en passant simplement l'appli en arrière-plan
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        sleep(4)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "L'appli s'est fermée après retour d'arrière-plan")
    }
}
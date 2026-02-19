import XCTest

final class ShadowClientmacOSUITests: XCTestCase {
    private let shortTimeout: TimeInterval = 12
    private let sessionTimeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeSurfaceRendersCoreCards() throws {
        let app = XCUIApplication()
        app.launch()
        ensureHomeSurface(app)

        XCTAssertNotNil(
            waitForAnyElement(
                [
                    app.otherElements["shadow.home.hosts.card"],
                    app.staticTexts["Remote Desktop Hosts"],
                ],
                timeout: shortTimeout
            ),
            "Host card should be visible on launch."
        )
        XCTAssertNotNil(
            waitForAnyElement(
                [
                    app.otherElements["shadow.home.applist.section"],
                    app.staticTexts["Host App Library"],
                ],
                timeout: shortTimeout
            ),
            "Host app library section should be visible on launch."
        )
        XCTAssertNotNil(
            waitForAnyElement(
                [
                    app.otherElements["shadow.home.connection-status"],
                    app.staticTexts["Client Connection"],
                ],
                timeout: shortTimeout
            ),
            "Connection status card should be visible on launch."
        )
    }

    func testConnectThenLaunchTransitionsToRemoteSessionWhenHostAndAppExist() throws {
        let app = XCUIApplication()
        app.launch()
        ensureHomeSurface(app)

        XCTAssertNotNil(
            waitForAnyElement(
                [
                    app.otherElements["shadow.home.hosts.card"],
                    app.staticTexts["Remote Desktop Hosts"],
                ],
                timeout: shortTimeout
            ),
            "Host card must be visible before interaction."
        )

        guard let connectButton = waitForAnyElement(
            [
                app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".connect")).firstMatch,
                app.buttons["Connect"],
            ],
            timeout: shortTimeout,
            requireEnabled: true
        ) else {
            throw XCTSkip("No enabled host connect button is currently available.")
        }
        connectButton.tap()

        guard let launchButton = waitForAnyElement(
            [
                app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "shadow.home.applist.launch.")
                ).firstMatch,
                app.buttons["Launch"],
            ],
            timeout: shortTimeout,
            requireEnabled: true
        ) else {
            throw XCTSkip("No enabled remote app launch button is currently available.")
        }
        launchButton.tap()

        XCTAssertNotNil(
            waitForAnyElement(
                [
                    app.buttons["shadow.home.session.end"],
                    app.buttons["End Session"],
                ],
                timeout: sessionTimeout
            ),
            "Session overlay should expose End Session after connect/launch flow."
        )
        XCTAssertNotNil(
            waitForAnyElement(
                [
                    app.otherElements["shadow.root.remote-session"],
                    app.staticTexts["Remote Session"],
                ],
                timeout: sessionTimeout
            ),
            "Remote session root should become visible after launch."
        )
    }

    private func waitForAnyElement(
        _ candidates: [XCUIElement],
        timeout: TimeInterval,
        requireEnabled: Bool = false
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for element in candidates where element.exists {
                if !requireEnabled || element.isEnabled {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        for element in candidates where element.waitForExistence(timeout: 0.1) {
            if !requireEnabled || element.isEnabled {
                return element
            }
        }
        return nil
    }

    private func ensureHomeSurface(_ app: XCUIApplication) {
        if let endSession = waitForAnyElement(
            [
                app.buttons["shadow.home.session.end"],
                app.buttons["End Session"],
            ],
            timeout: 3,
            requireEnabled: true
        ) {
            endSession.tap()
            _ = waitForAnyElement(
                [
                    app.otherElements["shadow.home.hosts.card"],
                    app.staticTexts["Remote Desktop Hosts"],
                ],
                timeout: shortTimeout
            )
        }
    }
}

import XCTest

/// Real Example app + public SDK + synthetic parent-owned HTTP fixture.
/// Snapshot tests do not open a camera; the standard flow uses DEBUG generated frames.
/// Run on a regular iPhone simulator and an iPhone SE simulator for compact-width evidence.
@MainActor
final class HostedUiScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func button(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[label].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 20), "Missing button: \(label)\n\(app.debugDescription)")
        let ready = NSPredicate(format: "hittable == true AND enabled == true")
        expectation(for: ready, evaluatedWith: element)
        waitForExpectations(timeout: 20)
        return element
    }

    private func capture(_ scene: String, scheme: String, datePicker: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IdentifiedExampleBaseURL", "http://127.0.0.1:8341",
            "-IdentifiedExampleToken", "ui-\(scene)",
            "-IdentifiedExampleAutostart", "YES",
            "-IdentifiedExampleAppearance", scheme,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        if scene == "entry" || scene == "consent" {
            let begin = button("Begin verification", in: app)
            if scene == "consent" { begin.tap() }
        } else if scene != "status" {
            button("Continue verification", in: app).tap()
            // Enabled Continue proves the checklist's case/session fetch completed.
            let next = button("Continue", in: app)
            if scene != "checklist" { next.tap() }
        }
        let titles = [
            "entry": "Verify your identity", "consent": "Consent & privacy",
            "checklist": "Verify your identity", "name": "Your name", "id": "Your ID details",
            "documents": "Front of ID", "selfie": "Liveness check",
            "address": "Proof of address", "review": "Review & submit", "status": "Manual review required"
        ]
        XCTAssertTrue(app.staticTexts[titles[scene]!].firstMatch.waitForExistence(timeout: 20),
                      "Scene \(scene) not rendered\n\(app.debugDescription)")
        if scene == "review" { _ = button("Submit for review", in: app) }
        if scene == "status" { _ = button("Done", in: app) }
        if datePicker {
            let trigger = app.buttons["Date of birth"].firstMatch
            if trigger.waitForExistence(timeout: 3) {
                button("Date of birth", in: app).tap()
            } else {
                // Compatibility with the original compact inline native control.
                let inline = app.datePickers.firstMatch
                XCTAssertTrue(inline.waitForExistence(timeout: 10))
                inline.tap()
            }
            let opened = app.datePickers.firstMatch
            XCTAssertTrue(opened.waitForExistence(timeout: 10), "Native DOB picker did not open\n\(app.debugDescription)")
            let populated = NSPredicate { _, _ in
                opened.exists && opened.isHittable && !opened.frame.isEmpty && opened.descendants(matching: .any).count > 0
            }
            expectation(for: populated, evaluatedWith: opened)
            waitForExpectations(timeout: 10)
        }
        // XCUITest waits for app quiescence; capture the entire native display, including chrome.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(scheme)-\(scene)\(datePicker ? "-datepicker" : "").png"
        attachment.lifetime = .keepAlways
        add(attachment)
        if scene == "documents" || scene == "selfie" {
            _ = scrollToButton("Open camera", in: app)
        }
    }
    private func scrollToButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[label].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 20), "Missing button: \(label)")
        // Consent is long; bound scrolling rather than waiting on an offscreen checkbox.
        for _ in 0..<16 {
            if element.isHittable { return element }
            app.swipeUp()
        }
        XCTFail("Could not scroll to \(label)\n\(app.debugDescription)")
        return element
    }

    private func enterName(_ value: String, label: String, in app: XCUIApplication) {
        let field = app.textFields[label].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "Missing field: \(label)")
        field.tap()
        field.typeText(value)
    }

    private func attachFlowImage(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "flow-standard-\(name).png"
        image.lifetime = .keepAlways
        add(image)
    }

    private func attachScanningIfVisible(in app: XCUIApplication, name: String) {
        let scanning = app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["Scanning your selfie", "Matching your face to your ID", "Scanning your documents", "Running your checks"]
        )).firstMatch
        if scanning.exists && scanning.isHittable { attachFlowImage(name) }
    }

    private func captureGeneratedCard(_ side: String, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts[side].firstMatch.waitForExistence(timeout: 20))
        button("Open camera", in: app).tap()
        let preview = app.buttons["Use this photo"].firstMatch
        // Give autocapture the first opportunity. If it wins while waiting for the shutter,
        // accept the preview too; never wait for a shutter that has already disappeared.
        if !preview.waitForExistence(timeout: 4) {
            let ready = app.buttons.matching(NSPredicate(
                format: "(label == %@ OR label == %@) AND enabled == true",
                "Use this photo", "Capture \(side)"
            )).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 15), "No capture or preview\n\(app.debugDescription)")
            if !preview.exists {
                let shutter = app.buttons["Capture \(side)"].firstMatch
                if shutter.exists && shutter.isHittable && shutter.isEnabled { shutter.tap() }
            }
        }
        let usePhoto = button("Use this photo", in: app)
        attachFlowImage(side == "Front of ID" ? "card-front-preview" : "card-back-preview")
        usePhoto.tap()
    }

    /// Exercises UI navigation, metadata, generated capture, HTTP uploads, submit and host callback.
    /// This validates the SDK/fixture contract, not a real identity or biometric provider.
    func test_fullStandardFlow() async throws {
        let token = "ui-flow-standard-\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchArguments = [
            "-IdentifiedExampleBaseURL", "http://127.0.0.1:8341",
            "-IdentifiedExampleToken", token, "-IdentifiedExampleAutostart", "YES",
            "-IdentifiedExampleAppearance", "light", "-IdentifiedFixtureCamera", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        button("Begin verification", in: app).tap()
        scrollToButton("I agree", in: app).tap()
        button("Agree & continue", in: app).tap()
        button("Continue", in: app).tap() // checklist
        XCTAssertTrue(app.staticTexts["Your name"].firstMatch.waitForExistence(timeout: 20))
        enterName("Ama", label: "First name", in: app)
        enterName("Mensah", label: "Last name", in: app)
        button("Continue", in: app).tap()
        XCTAssertTrue(app.staticTexts["Your ID details"].firstMatch.waitForExistence(timeout: 20))
        button("Continue", in: app).tap() // valid synthetic DOB and Ghana PIN are prefilled
        captureGeneratedCard("Front of ID", in: app)
        captureGeneratedCard("Back of ID", in: app)
        XCTAssertTrue(app.staticTexts["Liveness check"].firstMatch.waitForExistence(timeout: 20))
        button("Open camera", in: app).tap()
        // Generated frames contain no face: the production detector reaches its timed fallback.
        // Waiting for its button observes the actual fallback, rather than assuming a fixed delay.
        button("Start liveness check", in: app).tap()
        let useSelfie = button("Use this photo", in: app) // wait includes the six-second capture
        attachFlowImage("selfie-preview")
        useSelfie.tap()
        attachScanningIfVisible(in: app, name: "selfie-scanning")
        XCTAssertTrue(app.staticTexts["Review & submit"].firstMatch.waitForExistence(timeout: 20))
        let submit = button("Submit for review", in: app)
        attachFlowImage("review-accepted-captures")
        submit.tap()
        attachScanningIfVisible(in: app, name: "submit-scanning")
        XCTAssertTrue(app.staticTexts["Manual review required"].firstMatch.waitForExistence(timeout: 30))
        attachFlowImage("status")
        button("Done", in: app).tap()
        let callback = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "completed(caseId:", "manual_review"
        )).firstMatch
        XCTAssertTrue(callback.waitForExistence(timeout: 20), "Missing completed host callback\n\(app.debugDescription)")

        var request = URLRequest(url: URL(string: "http://127.0.0.1:8341/__fixture__/\(token)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "Fixture inspection must succeed")
        let record = try JSONDecoder().decode(StandardFlowRecord.self, from: data)
        XCTAssertEqual(record.uploads, ["license_front", "license_back", "selfie:left", "selfie:right", "selfie:center"])
        XCTAssertTrue(record.submitted)
        XCTAssertEqual(record.metadata.firstName, "Ama")
        XCTAssertEqual(record.metadata.lastName, "Mensah")
    }

    private struct StandardFlowRecord: Decodable {
        let uploads: [String]
        let submitted: Bool
        let metadata: Metadata

        struct Metadata: Decodable {
            let firstName: String
            let lastName: String
            enum CodingKeys: String, CodingKey {
                case firstName = "first_name", lastName = "last_name"
            }
        }
    }

    func test_light_id_datepicker() { capture("id", scheme: "light", datePicker: true) }
    func test_dark_id_datepicker() { capture("id", scheme: "dark", datePicker: true) }
    func test_light_entry() { capture("entry", scheme: "light") }
    func test_light_consent() { capture("consent", scheme: "light") }
    func test_light_checklist() { capture("checklist", scheme: "light") }
    func test_light_name() { capture("name", scheme: "light") }
    func test_light_id() { capture("id", scheme: "light") }
    func test_light_documents() { capture("documents", scheme: "light") }
    func test_light_selfie() { capture("selfie", scheme: "light") }
    func test_light_address() { capture("address", scheme: "light") }
    func test_light_review() { capture("review", scheme: "light") }
    func test_light_status() { capture("status", scheme: "light") }
    func test_dark_entry() { capture("entry", scheme: "dark") }
    func test_dark_consent() { capture("consent", scheme: "dark") }
    func test_dark_checklist() { capture("checklist", scheme: "dark") }
    func test_dark_name() { capture("name", scheme: "dark") }
    func test_dark_id() { capture("id", scheme: "dark") }
    func test_dark_documents() { capture("documents", scheme: "dark") }
    func test_dark_selfie() { capture("selfie", scheme: "dark") }
    func test_dark_address() { capture("address", scheme: "dark") }
    func test_dark_review() { capture("review", scheme: "dark") }
    func test_dark_status() { capture("status", scheme: "dark") }
}

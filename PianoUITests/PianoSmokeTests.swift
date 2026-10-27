import XCTest
import UIKit

/// User-facing flows run through visible controls with isolated simulator data.
final class PianoSmokeTests: XCTestCase {
    private var currentApp: XCUIApplication?

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if DEBUG && targetEnvironment(simulator)
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        #else
        throw XCTSkip("UI smoke tests require a Debug simulator build with isolated test data")
        #endif
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "PianoFlow UI failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if let currentApp {
                let hierarchy = XCTAttachment(string: currentApp.debugDescription)
                hierarchy.name = "PianoFlow accessibility tree"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
        }
        if let currentApp, currentApp.state != .notRunning {
            currentApp.terminate()
        }
        currentApp = nil
        try super.tearDownWithError()
    }

    func testRecordSaveRelaunchAndReplay() {
        let runID = UUID().uuidString
        let app = launchApp(runID: runID)

        tapToolbarControl("piano.record", menuTitle: "Record", in: app)
        let c4 = app.buttons["piano.key.60"]
        XCTAssertTrue(c4.waitForExistence(timeout: 5), "Middle C must be available on the keyboard")
        XCTAssertTrue(c4.isHittable)
        c4.press(forDuration: 1.2)
        let d4 = app.buttons["piano.key.62"]
        XCTAssertTrue(d4.waitForExistence(timeout: 5))
        d4.tap()
        tapToolbarControl("piano.record", menuTitle: "Stop recording", in: app)

        // Reuse the isolated test run's storage to verify the take reached disk.
        app.terminate()
        let reopened = launchApp(runID: runID)
        tapToolbarControl("piano.library", menuTitle: "Saved performances", in: reopened)
        let noteCount = reopened.staticTexts["2 notes"]
        scrollUntilHittable(noteCount, targetID: "recorded note count",
                            scrollID: "performance.library.scroll", in: reopened)
        XCTAssertTrue(noteCount.exists, "The recorded take should survive relaunch")

        let play = reopened.buttons["performance.play"].firstMatch
        tapWhenVisible(play, targetID: "performance.play",
                       scrollID: "performance.library.scroll", in: reopened)
        XCTAssertTrue(reopened.staticTexts["Playing"].waitForExistence(timeout: 3),
                      "Library replay should enter the playing state")
    }

    func testGuidedPracticeAdvancesOnRealKeyTouch() {
        let app = launchApp()
        startCMajorScale(in: app)

        let progress = app.descendants(matching: .any)
            .matching(identifier: "practice.progress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForProgress("0 of 15", in: progress))

        let c4 = app.buttons["piano.key.60"]
        XCTAssertTrue(c4.waitForExistence(timeout: 5))
        XCTAssertTrue(c4.isHittable, "The first target key should remain tappable beside the score")
        XCTAssertGreaterThanOrEqual(c4.frame.height, 44,
                                    "The keyboard needs a usable touch height beside the score")
        c4.tap()
        XCTAssertTrue(waitForProgress("1 of 15", in: progress),
                      "A real keyboard tap should advance the wait-mode exercise")
    }

    func testStopAllSoundFinishesAnActiveTake() {
        let app = launchApp()
        tapToolbarControl("piano.record", menuTitle: "Record", in: app)
        let c4 = app.buttons["piano.key.60"]
        XCTAssertTrue(c4.waitForExistence(timeout: 5))
        c4.tap()
        tapToolbarControl("piano.sustain", menuTitle: "Turn sustain on", in: app)

        tapToolbarControl("piano.stopAllSound", menuTitle: "Stop all sound", in: app)
        XCTAssertEqual(app.buttons["piano.record"].label, "Record")
        XCTAssertEqual(app.buttons["piano.moreControls"].value as? String, "No active effects")
        XCTAssertEqual(c4.value as? String, "Released")

        // Recovery must leave the same key playable and recording usable again.
        tapToolbarControl("piano.record", menuTitle: "Record", in: app)
        c4.tap()
        tapToolbarControl("piano.record", menuTitle: "Stop recording", in: app)
        tapToolbarControl("piano.library", menuTitle: "Saved performances", in: app)
        let count = app.descendants(matching: .any)
            .matching(identifier: "performance.count").firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "2 saved performances")
    }

    func testLandscapeRotationRetainsPracticeState() throws {
        let app = launchApp()
        try skipDuoInnerDisplayRotation(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(waitForWindowShape(window, portrait: false),
                      "The app should start in landscape on a rotating display")
        startCMajorScale(in: app)
        let progress = app.descendants(matching: .any)
            .matching(identifier: "practice.progress").firstMatch

        let c4 = app.buttons["piano.key.60"]
        XCTAssertTrue(c4.waitForExistence(timeout: 5))
        c4.tap()
        XCTAssertTrue(waitForProgress("1 of 15", in: progress))

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(waitForWindowShape(window, portrait: false),
                      "The app should remain in landscape after rotating right")
        XCTAssertTrue(waitForProgress("1 of 15", in: progress),
                      "Rotating right should preserve the current exercise")
        let d4 = app.buttons["piano.key.62"]
        XCTAssertTrue(d4.waitForExistence(timeout: 5))
        XCTAssertTrue(d4.isHittable)
        d4.tap()
        XCTAssertTrue(waitForProgress("2 of 15", in: progress))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForWindowShape(window, portrait: false),
                      "The app should remain in landscape after rotating left")
        XCTAssertTrue(waitForProgress("2 of 15", in: progress),
                      "Rotating left should preserve the advanced exercise")
        XCTAssertTrue(app.buttons["practice.exit"].isHittable)
    }

    func testPortraitResizeRetainsPracticeOnAdaptiveDisplays() throws {
        let app = launchApp()
        try skipDuoInnerDisplayRotation(in: app)
        startCMajorScale(in: app)
        let progress = app.descendants(matching: .any)
            .matching(identifier: "practice.progress").firstMatch
        let c4 = app.buttons["piano.key.60"]
        XCTAssertTrue(c4.waitForExistence(timeout: 5))
        c4.tap()
        XCTAssertTrue(waitForProgress("1 of 15", in: progress))

        let window = app.windows.firstMatch
        let initialFrame = window.frame
        XCUIDevice.shared.orientation = .portrait
        let becamePortrait = waitForWindowShape(window, portrait: true)
        if !becamePortrait {
            // An adaptive display should respond to a portrait request here.
            let hasAdaptiveDisplay = min(initialFrame.width, initialFrame.height) >= 600
            if UIDevice.current.userInterfaceIdiom == .pad || hasAdaptiveDisplay {
                XCTFail("The adaptive display did not resize into portrait")
                return
            }
            throw XCTSkip("This iPhone keeps the app in its supported landscape orientation")
        }

        XCTAssertTrue(waitForProgress("1 of 15", in: progress))
        let d4 = app.buttons["piano.key.62"]
        XCTAssertTrue(d4.waitForExistence(timeout: 5))
        XCTAssertTrue(d4.isHittable, "The target key should remain reachable after portrait resize")
        XCTAssertGreaterThanOrEqual(d4.frame.height, 44)
        d4.tap()
        XCTAssertTrue(waitForProgress("2 of 15", in: progress))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForWindowShape(window, portrait: false))
        XCTAssertTrue(waitForProgress("2 of 15", in: progress))
    }

    func testLargestTextToolbarAndSettingsRemainUsable() {
        let app = launchApp(largeText: true)
        let record = app.buttons["piano.record"]
        let more = app.buttons["piano.moreControls"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(record.isHittable, "Record must remain reachable at the largest text size")
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.isHittable, "More controls must remain reachable at the largest text size")

        tapToolbarControl("piano.settings", menuTitle: "Settings", in: app)
        XCTAssertTrue(app.staticTexts["PIANO SETTINGS"].waitForExistence(timeout: 5))
        let labels = app.switches["settings.keyLabels"]
        scrollUntilHittable(labels, targetID: "settings.keyLabels",
                            scrollID: "settings.scroll", in: app)
        let originalValue = labels.value as? String ?? ""
        // On iPad the accessible Toggle frame includes its wide text label;
        // the actual switch track is at the trailing edge of that frame.
        labels.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let changedValue = expectation(for: NSPredicate(format: "value != %@", originalValue),
                                       evaluatedWith: labels)
        XCTAssertEqual(XCTWaiter.wait(for: [changedValue], timeout: 5), .completed)
        app.buttons["Done"].tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.isHittable)
    }

    func testSettingsPrivacyAndSupportRemainAvailableAtLargestText() {
        executionTimeAllowance = 240
        let app = launchApp(largeText: true)
        tapToolbarControl("piano.settings", menuTitle: "Settings", in: app)
        let scroll = app.scrollViews["settings.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))

        // This section is below the keyboard and MIDI preferences. At AX5,
        // move through that long screen before fine-scrolling to each row.
        // Use the gutter so the gesture cannot adjust a volume slider.
        for _ in 0..<8 {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.85))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)
                ), withVelocity: .fast, thenHoldForDuration: 0.2)
        }

        for identifier in ["settings.privacyPolicy", "settings.contactSupport"] {
            let control = app.descendants(matching: .any)
                .matching(identifier: identifier).firstMatch
            scrollUntilHittable(control, targetID: identifier,
                                scrollID: "settings.scroll", in: app)
            XCTAssertTrue(control.isHittable, "Privacy and support must remain reachable for free users")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
            XCTAssertGreaterThanOrEqual(control.frame.minX, viewport.minX - 2)
            XCTAssertLessThanOrEqual(control.frame.maxX, viewport.maxX + 2)
        }

        let version = app.descendants(matching: .any)
            .matching(identifier: "settings.appVersion").firstMatch
        scrollUntilHittable(version, targetID: "settings.appVersion",
                            scrollID: "settings.scroll", in: app)
        XCTAssertTrue(version.label.contains("Version "), "Show the installed app version and build")
        XCTAssertTrue(version.label.contains("("), "Include the build number in support details")
        let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
        XCTAssertGreaterThanOrEqual(version.frame.minX, viewport.minX - 2)
        XCTAssertLessThanOrEqual(version.frame.maxX, viewport.maxX + 2)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Privacy and support at largest app text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["piano.record"].waitForExistence(timeout: 5))
    }

    func testPremiumRecordingControlsProtectPaidFeaturesAndKeepM4AFree() {
        let app = launchApp()
        tapToolbarControl("piano.record", menuTitle: "Record", in: app)
        let c4 = app.buttons["piano.key.60"]
        XCTAssertTrue(c4.waitForExistence(timeout: 5))
        c4.press(forDuration: 0.6)
        tapToolbarControl("piano.record", menuTitle: "Stop recording", in: app)
        tapToolbarControl("piano.library", menuTitle: "Saved performances", in: app)
        tapWhenVisible(app.buttons["performance.tools"].firstMatch,
                       targetID: "performance.tools", scrollID: "performance.library.scroll", in: app)

        tapWhenVisible(app.buttons["recording.premium.studio"],
                       targetID: "recording.premium.studio", scrollID: "recording.tools.scroll", in: app)
        XCTAssertTrue(app.staticTexts["premium.headline"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["premium.headline"].label, "Advanced recording studio")
        app.buttons["premium.done"].tap()

        tapWhenVisible(app.buttons["recording.premium.export"],
                       targetID: "recording.premium.export", scrollID: "recording.tools.scroll", in: app)
        XCTAssertTrue(app.staticTexts["premium.headline"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["premium.headline"].label, "Lossless WAV export")
        app.buttons["premium.done"].tap()

        XCTAssertFalse(app.buttons["recording.export.prepareWAV"].exists,
                       "Dismissing an upgrade must not select the paid export")
        tapWhenVisible(app.buttons["recording.export.prepareM4A"],
                       targetID: "recording.export.prepareM4A", scrollID: "recording.tools.scroll", in: app)
        XCTAssertTrue(app.buttons["recording.export.shareM4A"].waitForExistence(timeout: 15),
                      "A free user should be able to render and share Concert M4A audio")
    }

    func testPremiumPaywallSupportsLargestText() {
        let app = launchApp(largeText: true)
        tapToolbarControl("piano.settings", menuTitle: "Settings", in: app)
        tapWhenVisible(app.buttons["settings.premium"], targetID: "settings.premium",
                       scrollID: "settings.scroll", in: app)
        let scroll = app.scrollViews["premium.scroll"]
        let window = app.windows.firstMatch
        let headline = app.staticTexts["premium.headline"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(headline.label, "Your piano. Your studio.")

        // XCTest can capture a landscape simulator screenshot with portrait
        // orientation metadata while a sheet is settling. Check actual AX
        // geometry before taking the visual attachment.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard window.exists, scroll.exists, headline.exists else { return false }
            let viewport = scroll.frame.intersection(window.frame)
            let frame = headline.frame
            return !viewport.isNull && viewport.width > 0 &&
                frame.minX >= viewport.minX - 2 && frame.maxX <= viewport.maxX + 2 &&
                viewport.minY <= frame.midY && frame.midY <= viewport.maxY
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed,
                       "The AX5 paywall headline must settle inside the visible sheet")

        func assertFitsHorizontally(_ element: XCUIElement, name: String) {
            XCTAssertTrue(element.exists, "Missing Premium text: \(name)")
            guard element.exists else { return }
            let viewport = scroll.frame.intersection(window.frame)
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 2,
                                        "\(name) clips past the left edge")
            XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 2,
                                     "\(name) clips past the right edge")
        }

        assertFitsHorizontally(headline, name: "headline")
        assertFitsHorizontally(
            app.staticTexts["A one-time upgrade for uninterrupted playing and a more capable recording studio."],
            name: "paywall introduction"
        )
        XCTAssertTrue(app.buttons["premium.done"].isHittable,
                      "The largest-text paywall must remain dismissible")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Premium paywall at largest app text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let screenScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenScreenshot.name = "Premium paywall full screen at largest text size"
        screenScreenshot.lifetime = .keepAlways
        add(screenScreenshot)

        let sheetScreenshot = XCTAttachment(screenshot: scroll.screenshot())
        sheetScreenshot.name = "Premium paywall visible scroll area at largest text size"
        sheetScreenshot.lifetime = .keepAlways
        add(sheetScreenshot)

        let benefits = [
            ("Ad-free playing", "Play without banners or app-open ads."),
            ("Two expressive piano sounds", "Shape your tone with the mellow Warm Studio and spacious Bright Hall sounds."),
            ("Advanced recording studio", "Adjust playback speed, loop a passage, and save trimmed copies of your takes."),
            ("Lossless WAV export", "Share full-quality WAV audio, ready for your music workflow.")
        ]
        for (title, detail) in benefits {
            let titleElement = app.staticTexts[title]
            scrollUntilHittable(titleElement, targetID: title, scrollID: "premium.scroll", in: app)
            assertFitsHorizontally(titleElement, name: title)
            assertFitsHorizontally(app.staticTexts[detail], name: "\(title) detail")
        }

        let freeFeatures = app.staticTexts[
            "One purchase. No subscription. Play, practice, record, replay, share MIDI, and export compact M4A audio for free."
        ]
        scrollUntilHittable(freeFeatures, targetID: "Premium free features",
                           scrollID: "premium.scroll", in: app)
        assertFitsHorizontally(freeFeatures, name: "free features disclosure")
        XCTAssertTrue(app.buttons["premium.restore"].exists,
                      "Scrolling must reach the purchase and restore section")
        app.buttons["premium.done"].tap()
        XCTAssertTrue(app.scrollViews["settings.scroll"].waitForExistence(timeout: 5))
    }

    // These tests run in the Duo's current display state. Fold and unfold require
    // a separate manual Device Hub pass; XCUIDevice has no public fold-pose control.

    private func skipDuoInnerDisplayRotation(in app: XCUIApplication) throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let frame = app.windows.firstMatch.frame
        if min(frame.width, frame.height) >= 600 {
            throw XCTSkip("Duo inner display keeps posture-defined bounds; test resizing in Device Hub.")
        }
    }

    @discardableResult
    private func launchApp(runID: String = UUID().uuidString,
                           largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchEnvironment["PIANOFLOW_UI_TEST_RUN_ID"] = runID
        if let plannedTextSize = ProcessInfo.processInfo.environment["PIANOFLOW_UI_TEST_LARGE_TEXT"] {
            app.launchEnvironment["PIANOFLOW_UI_TEST_LARGE_TEXT"] = plannedTextSize
        }
        if largeText {
            app.launchEnvironment["PIANOFLOW_UI_TEST_LARGE_TEXT"] = "1"
        }
        currentApp = app
        app.launch()
        XCTAssertTrue(app.buttons["piano.record"].waitForExistence(timeout: 30),
                      "The piano toolbar should appear after launch")
        return app
    }

    private func tapToolbarControl(_ identifier: String, menuTitle: String,
                                   in app: XCUIApplication) {
        let direct = app.buttons[identifier]
        if direct.exists && direct.isHittable {
            direct.tap()
            return
        }
        let more = app.buttons["piano.moreControls"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", menuTitle)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing More menu action: \(menuTitle)")
        item.tap()
    }

    private func startCMajorScale(in app: XCUIApplication) {
        tapToolbarControl("piano.practice", menuTitle: "Guided practice", in: app)
        let exercise = app.buttons["practice.exercise.c-major-scale"]
        tapWhenVisible(exercise, targetID: "practice.exercise.c-major-scale",
                       scrollID: "practice.library.scroll", in: app)
        let start = app.buttons["practice.start"]
        tapWhenVisible(start, targetID: "practice.start",
                       scrollID: "practice.setup.scroll", in: app)
        XCTAssertTrue(app.buttons["practice.exit"].waitForExistence(timeout: 5),
                      "Starting practice should return to the keyboard")
    }

    private func tapWhenVisible(_ element: XCUIElement, targetID: String,
                                scrollID: String, in app: XCUIApplication) {
        scrollUntilHittable(element, targetID: targetID, scrollID: scrollID, in: app)
        element.tap()
    }

    private func scrollUntilHittable(_ element: XCUIElement, targetID: String,
                                     scrollID: String, in app: XCUIApplication) {
        // Lazy stacks do not create distant controls until their own sheet has
        // scrolled to them. A swipe on the app would hit the piano behind it.
        let scroll = app.scrollViews[scrollID]
        guard scroll.waitForExistence(timeout: 5) else {
            XCTFail("Missing scroll container: \(scrollID)")
            return
        }
        let maxAttempts = 20
        for attempt in 0...maxAttempts {
            if element.exists {
                let scrollFrame = scroll.frame
                let targetCenter = CGPoint(x: element.frame.midX, y: element.frame.midY)
                let visibleArea = scrollFrame.insetBy(dx: 2, dy: 8)
                let hittable = element.isHittable
                print("UI scroll \(targetID) #\(attempt): targetY=\(targetCenter.y) viewportY=\(scrollFrame.minY)...\(scrollFrame.maxY) hittable=\(hittable)")
                if hittable && visibleArea.contains(targetCenter) {
                    return
                }
                guard attempt < maxAttempts else { break }

                // A full swipe can jump past a large AX row in a short sheet.
                // Move toward the row by at most 40% of the visible height.
                let distance = targetCenter.y - scrollFrame.midY
                let travel = min(max(abs(distance), 24), scrollFrame.height * 0.4)
                let direction: CGFloat = distance >= 0 ? -1 : 1
                // On a wide landscape phone, central purchase buttons can
                // capture a drag. Start in the left content gutter instead.
                let dragX: CGFloat = scrollFrame.width > scrollFrame.height * 1.5 ? 0.1 : 0.5
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: dragX, dy: 0.5))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(
                    dx: dragX, dy: 0.5 + direction * travel / scrollFrame.height
                ))
                start.press(forDuration: 0.12, thenDragTo: end,
                            withVelocity: .slow, thenHoldForDuration: 0.2)
                continue
            }
            print("UI scroll \(targetID) #\(attempt): target unrealized; swiping up \(scrollID)")
            guard attempt < maxAttempts else { break }
            scroll.swipeUp()
        }
        XCTFail("Could not reach \(targetID) in \(scrollID) after scrolling")
    }

    private func waitForProgress(_ expected: String, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                                    expected, expected)
        let value = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [value], timeout: 5) == .completed
    }

    private func waitForWindowShape(_ window: XCUIElement, portrait: Bool) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard window.exists else { return false }
            let frame = window.frame
            return portrait ? frame.height > frame.width : frame.width > frame.height
        }
        let resized = expectation(for: predicate, evaluatedWith: window)
        return XCTWaiter.wait(for: [resized], timeout: 8) == .completed
    }
}

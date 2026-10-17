import XCTest

final class HouseXraySmoke:XCTestCase {
    @MainActor func testPersonalHouseWorkflow() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout:20))
        screenshot("01-house")
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.buttons["Layers"].waitForExistence(timeout:10))
        app.buttons["Finished"].tap();screenshot("02-finished")
        app.buttons["Ghost"].tap();app.buttons["Layers"].tap()
        XCTAssertTrue(app.switches["Show ceilings"].waitForExistence(timeout:5));app.switches["Show ceilings"].tap()
        app.buttons["Done"].tap();screenshot("03-ghost")
        app.tabBars.buttons["Evidence"].tap()
        XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout:5));screenshot("04-evidence")
        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.buttons["Start capture"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Start capture"].isEnabled,"Synthetic projects must not mix with field captures")
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.buttons["Drawings & design references"].waitForExistence(timeout:5))
        app.buttons["Drawings & design references"].tap()
        XCTAssertTrue(app.buttons["Import drawing or source file"].waitForExistence(timeout:5));screenshot("05-drawings")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Capture coverage"].tap()
        XCTAssertTrue(app.buttons["Analyze saved capture coverage"].waitForExistence(timeout:5));screenshot("06-coverage")
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["The sample house"].waitForExistence(timeout:10))
    }
    func screenshot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}

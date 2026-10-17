import XCTest

final class HouseXraySmoke: XCTestCase {
  @MainActor func testPersonalHouseWorkflow() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--demo"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 20))
    screenshot("01-house")
    app.tabBars.buttons["Explore"].tap()
    XCTAssertTrue(app.buttons["Layers"].waitForExistence(timeout: 10))
    app.buttons["Finished"].tap()
    screenshot("02-finished")
    app.buttons["Ghost"].tap()
    app.buttons["Layers"].tap()
    XCTAssertTrue(app.switches["Show ceilings"].waitForExistence(timeout: 5))
    app.switches["Show ceilings"].tap()
    app.buttons["Done"].tap()
    screenshot("03-ghost")
    app.tabBars.buttons["Evidence"].tap()
    XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout: 5))
    screenshot("04-evidence")
    app.tabBars.buttons["Capture"].tap()
    XCTAssertTrue(app.buttons["Start capture"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.buttons["Start capture"].isEnabled, "Synthetic projects must not mix with field captures")
    app.tabBars.buttons["Tools"].tap()
    XCTAssertTrue(app.buttons["Drawings & design references"].waitForExistence(timeout: 5))
    app.buttons["Drawings & design references"].tap()
    XCTAssertTrue(app.buttons["Import drawing or source file"].waitForExistence(timeout: 5))
    screenshot("05-drawings")
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["Capture coverage"].tap()
    XCTAssertTrue(app.buttons["Analyze saved capture coverage"].waitForExistence(timeout: 5))
    screenshot("06-coverage")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["The sample house"].waitForExistence(timeout: 10))
  }
  @MainActor func testPhotoPointWorkflow() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--photo-demo"];app.launch()
    XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:30));app.tabBars.buttons["Evidence"].tap()
    app.buttons["Locate a point from three photos"].tap()
    let segment=app.descendants(matching:.any)["point-segment-picker"].firstMatch
    XCTAssertTrue(segment.waitForExistence(timeout:10));segment.tap()
    app.descendants(matching:.any)["point-segment-choice"].firstMatch.tap()
    func reveal(_ element:XCUIElement) {
      for _ in 0..<12 {
        if element.exists && element.isHittable && element.frame.minY>90 && element.frame.maxY<app.frame.maxY-95{return}
        app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.80)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.27)))
      }
      XCTAssertTrue(element.isHittable)
    }
    for (index,photo) in [0,4,8].enumerated() {
      let picker=app.descendants(matching:.any)["point-photo-picker-\(index)"].firstMatch;reveal(picker);picker.tap()
      app.descendants(matching:.any)["point-photo-choice-\(photo)"].firstMatch.tap()
      let image=app.descendants(matching:.any)["point-image-\(index)"].firstMatch
      XCTAssertTrue(image.waitForExistence(timeout:5));reveal(image)
      let frame=image.frame,w=min(frame.width,frame.height*4/3),h=w*3/4
      let u=[0.6083333333,0.5,0.3916666667][index],v=0.6354166667
      let dx=((frame.width-w)/2+w*u)/frame.width,dy=((frame.height-h)/2+h*v)/frame.height
      image.coordinate(withNormalizedOffset:CGVector(dx:dx,dy:dy)).tap()
      if index==0{screenshot("07-photo-point")}
    }
    let save=app.buttons["Check and save point"];reveal(save);XCTAssertTrue(save.isEnabled);save.tap()
    let saved=app.staticTexts["Saved Photo-located point with three source photographs."]
    XCTAssertTrue(saved.waitForExistence(timeout:10));screenshot("08-photo-point-saved")
    app.tabBars.buttons["Explore"].tap();app.buttons["Wall"].tap()
    for point in [CGVector(dx:0.25,dy:0.29),CGVector(dx:0.65,dy:0.29),CGVector(dx:0.25,dy:0.42)] {app.coordinate(withNormalizedOffset:point).tap()}
    let define=app.buttons["Define wall or ceiling volume"]
    XCTAssertTrue(define.waitForExistence(timeout:5));define.tap()
    let boundarySave=app.buttons["Save reveal boundary"]
    XCTAssertTrue(boundarySave.waitForExistence(timeout:5));screenshot("09-boundary-definition");boundarySave.tap()
    XCTAssertTrue(app.buttons["Layers"].waitForExistence(timeout:5))
    app.terminate()
  }
  @MainActor func testLandscapeControlsAndRotation() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--demo"]
    XCUIDevice.shared.orientation = .landscapeLeft
    defer {XCUIDevice.shared.orientation = .portrait;app.terminate()}
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout:20))
    app.tabBars.buttons["Explore"].tap()
    let viewMode=app.buttons["View mode"],tool=app.buttons["Inspection tool"],layers=app.buttons["Layers"]
    for control in [viewMode,tool,layers] {
      XCTAssertTrue(control.waitForExistence(timeout:10));XCTAssertTrue(control.isHittable)
      XCTAssertTrue(app.frame.contains(control.frame),"Landscape control outside the screen: \(control.label)")
    }
    viewMode.tap();app.buttons["Finished"].tap()
    tool.tap();app.buttons["Measure"].tap()
    XCTAssertTrue(app.staticTexts["Tap two surface points"].waitForExistence(timeout:5))
    screenshot("10-landscape-measure")
    layers.tap()
    XCTAssertTrue(app.switches["Show ceilings"].waitForExistence(timeout:5));app.buttons["Done"].tap()
    XCUIDevice.shared.orientation = .portrait
    XCTAssertTrue(app.buttons["Trace route"].waitForExistence(timeout:10))
    XCTAssertTrue(app.buttons["Finished"].isSelected)
    screenshot("11-portrait-after-rotation")
  }
  @MainActor func testEvidenceSearchMatchesRoomAndSystemTogether() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
    defer {app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:20));app.tabBars.buttons["Evidence"].tap()
    app.swipeDown()
    let search=app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("kitchen speaker")
    let count=app.staticTexts["evidence-result-count"]
    let found=expectation(for:NSPredicate(format:"label == %@","0 photographs · 1 object"),evaluatedWith:count)
    wait(for:[found],timeout:10)
    XCTAssertTrue(app.staticTexts["Speaker prewire"].firstMatch.isHittable)
    XCTAssertFalse(app.staticTexts["Outlet circuit"].firstMatch.exists)
    screenshot("12-evidence-room-and-system-search")
  }
  @MainActor func testStepNavigationControlsInBothOrientations() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
    defer {XCUIDevice.shared.orientation = .portrait;app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout:20));app.tabBars.buttons["Explore"].tap()
    app.buttons["Layers"].tap()
    let toggle=app.switches["Step and snap-turn buttons"]
    XCTAssertTrue(toggle.waitForExistence(timeout:5));if toggle.value as? String != "1" {toggle.tap()}
    app.buttons["Done"].tap()
    let names=["Step left","Step forward","Step backward","Step right","Turn left 15 degrees","Look up 15 degrees","Look down 15 degrees","Turn right 15 degrees"]
    for orientation in [UIDeviceOrientation.portrait,.landscapeLeft] {
      XCUIDevice.shared.orientation=orientation
      for name in names {
        let button=app.buttons[name];XCTAssertTrue(button.waitForExistence(timeout:5));XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.width,44);XCTAssertGreaterThanOrEqual(button.frame.height,44)
        XCTAssertTrue(app.frame.contains(button.frame));button.tap()
      }
    }
    screenshot("13-landscape-step-navigation")
    app.buttons["Layers"].tap();app.switches["Orbit overview"].tap();app.buttons["Done"].tap()
    XCTAssertFalse(app.buttons["Step forward"].isEnabled)
    app.buttons["Layers"].tap();app.switches["Orbit overview"].tap();app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Step forward"].isEnabled)
    app.buttons["Layers"].tap();app.switches["Step and snap-turn buttons"].tap();app.buttons["Done"].tap()
  }
  func screenshot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
}


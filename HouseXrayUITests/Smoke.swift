import XCTest

final class HouseXraySmoke: XCTestCase {
  @MainActor func testClosureReviewKeepsMissingStageEvidenceExplicit() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
    defer{app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["House"].waitForExistence(timeout:20));app.tabBars.buttons["House"].tap()
    func reveal(_ element:XCUIElement) {
      for _ in 0..<16 {
        if element.exists && element.isHittable && element.frame.maxY<app.frame.maxY-40 {return}
        app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.7)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.45)))
      }
      XCTAssertTrue(element.exists && element.isHittable)
    }
    let open=app.buttons["Closure review and notes"];reveal(open);open.tap()
    let review=app.buttons["Review dated evidence"];XCTAssertTrue(review.waitForExistence(timeout:10));review.tap()
    let export=app.buttons["Export dated review inventory"];XCTAssertTrue(export.waitForExistence(timeout:20))
    let missing=app.staticTexts.matching(identifier:"No photographs assigned to this room and stage.").firstMatch;reveal(missing)
    XCTAssertTrue(missing.isHittable)
    XCTAssertFalse(app.staticTexts["Closure verified"].exists);screenshot("30-closure-review-missing-evidence")
  }

  @MainActor func testReviewedServiceTourPreviewAndTradeScope() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--service-tour-demo"];app.launch()
    defer{app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Tools"].waitForExistence(timeout:20));app.tabBars.buttons["Tools"].tap()
    func reveal(_ element:XCUIElement) {
      for _ in 0..<16 {
        if element.exists && element.isHittable && element.frame.maxY<app.frame.maxY-40 {return}
        app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.65)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.45)))
      }
      XCTAssertTrue(element.exists && element.isHittable)
    }
    let preset=app.descendants(matching:.any)["tour-preset"].firstMatch;reveal(preset);preset.tap()
    app.buttons["Service systems"].tap()
    let trade=app.descendants(matching:.any)["tour-trade"].firstMatch;reveal(trade);trade.tap();app.buttons["Plumbing"].tap()
    let preview=app.buttons["Preview shot list"];reveal(preview);preview.tap()
    let missing=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","no reviewed service routes")).firstMatch
    XCTAssertTrue(missing.waitForExistence(timeout:15));screenshot("28-service-tour-omission")
    app.navigationBars["Automatic shots"].buttons.firstMatch.tap()
    reveal(trade);trade.tap();app.buttons["Electrical"].tap();reveal(preview);preview.tap()
    let endpoint=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","start endpoint")).firstMatch
    XCTAssertTrue(endpoint.waitForExistence(timeout:15))
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","identity unconfirmed")).firstMatch.exists)
    screenshot("29-service-tour-endpoints")
  }
  @MainActor func testMeasuredEnvelopeSaveAndRelaunch() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--envelope-demo","--envelope-demo-reset"];app.launch()
    defer{app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:20));app.tabBars.buttons["Evidence"].tap()
    let source=app.staticTexts["Visible centerline"];XCTAssertTrue(source.waitForExistence(timeout:10));source.tap()
    let open=app.buttons["Record a service envelope"]
    for _ in 0..<20 {if open.exists && open.isHittable{break};app.swipeUp()}
    XCTAssertTrue(open.isHittable);open.tap()
    let width=app.textFields["envelope-width"];XCTAssertTrue(width.waitForExistence(timeout:10));width.tap();width.typeText("50")
    app.buttons["envelope-keyboard-done"].tap()
    let evidence=app.descendants(matching:.any).matching(identifier:"envelope-evidence").firstMatch
    for _ in 0..<8 {if evidence.exists && evidence.isHittable{break};app.swipeUp()}
    XCTAssertTrue(evidence.isHittable);evidence.tap();evidence.typeText("Synthetic 50 mm outer measurement");app.buttons["envelope-keyboard-done"].tap()
    let confirm=app.switches["envelope-confirm"]
    for _ in 0..<8 {if confirm.exists && confirm.isHittable{break};app.swipeUp()}
    XCTAssertTrue(confirm.isHittable);setSwitch(confirm,to:true)
    let save=app.buttons["envelope-save"]
    for _ in 0..<8 {if save.isHittable{break};app.swipeUp()}
    XCTAssertTrue(save.isEnabled);screenshot("26-measured-envelope");save.tap()
    XCTAssertTrue(app.navigationBars["Object details"].waitForExistence(timeout:10));app.navigationBars["Object details"].buttons["Cancel"].tap()
    app.terminate();app.launchArguments=["--envelope-demo"];app.launch()
    XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:20));app.tabBars.buttons["Evidence"].tap()
    let envelope=app.staticTexts["Visible centerline · measured envelope"];XCTAssertTrue(envelope.waitForExistence(timeout:10));envelope.tap()
    let size=app.staticTexts["service-envelope-size"]
    for _ in 0..<20 {if size.exists && size.isHittable{break};app.swipeUp()}
    XCTAssertTrue(size.isHittable);XCTAssertTrue(size.label.contains("50 mm"))
    let savedEvidence=app.descendants(matching:.any).matching(identifier:"service-envelope-evidence").firstMatch
    // A one-pixel sliver of the size row can be hittable while the following
    // evidence row is still outside the Form's realized accessibility cells.
    for _ in 0..<10 {
      if savedEvidence.exists && savedEvidence.isHittable && savedEvidence.frame.maxY<app.frame.maxY-40 {break}
      app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.65)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.45)))
    }
    XCTAssertTrue(savedEvidence.exists && savedEvidence.isHittable)
    XCTAssertLessThan(savedEvidence.frame.maxY,app.frame.maxY-40)
    XCTAssertEqual(savedEvidence.label,"Synthetic 50 mm outer measurement");screenshot("27-measured-envelope-relaunched")
  }
  @MainActor func testDrawingSuggestionReviewAndRelaunch() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--drawing-demo","--drawing-demo-reset"];app.launch()
    defer{app.terminate()}
    func openMarks() {
      XCTAssertTrue(app.tabBars.buttons["Tools"].waitForExistence(timeout:20));app.tabBars.buttons["Tools"].tap()
      app.buttons["Drawings & design references"].tap();app.staticTexts["Plan.pdf"].tap()
      let open=app.buttons["Labels and boundary suggestions"];XCTAssertTrue(open.waitForExistence(timeout:10));open.tap()
      XCTAssertTrue(app.buttons["drawing-find-suggestions"].waitForExistence(timeout:10))
    }
    openMarks()
    let detect=app.buttons["drawing-find-suggestions"]
    for _ in 0..<5 {if detect.isHittable{break};app.swipeUp()}
    XCTAssertTrue(detect.isHittable);detect.tap()
    let status=app.staticTexts["drawing-suggestion-status"];XCTAssertTrue(status.waitForExistence(timeout:40))
    let keep=app.buttons["Keep ROOM A"]
    for _ in 0..<8 {if keep.exists && keep.isHittable{break};app.swipeUp()}
    XCTAssertTrue(keep.isHittable);keep.tap()
    let review=app.buttons["drawing-review-ROOM A"]
    for _ in 0..<12 {if review.exists && review.isHittable{break};app.swipeUp()}
    XCTAssertTrue(review.isHittable);XCTAssertEqual(review.label,"Mark reviewed");review.tap()
    XCTAssertEqual(review.label,"Unreview");screenshot("24-drawing-suggestion-review")
    app.buttons["drawing-save-marks"].tap()
    XCTAssertTrue(app.navigationBars["Plan.pdf"].waitForExistence(timeout:10));app.navigationBars["Plan.pdf"].buttons["Save"].tap()
    app.terminate();app.launchArguments=["--drawing-demo"];app.launch();openMarks()
    for _ in 0..<12 {if review.exists && review.isHittable{break};app.swipeUp()}
    XCTAssertTrue(review.isHittable);XCTAssertEqual(review.label,"Unreview")
    XCTAssertTrue(app.staticTexts["drawing-mark-count"].label.contains("1 reviewed"));screenshot("25-drawing-review-relaunched")
  }
  @MainActor func testSavedIFCSourceWorkflow() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--ifc-demo"];app.launch()
    defer{app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Tools"].waitForExistence(timeout:20));app.tabBars.buttons["Tools"].tap()
    app.buttons["Drawings & design references"].tap();app.staticTexts["Source.ifc"].tap()
    let convert=app.buttons["Import this IFC design"];XCTAssertTrue(convert.waitForExistence(timeout:10));XCTAssertFalse(convert.isEnabled)
    app.descendants(matching:.any)["ifc-source-room"].firstMatch.tap();app.buttons["Source room"].tap()
    XCTAssertTrue(convert.isEnabled);convert.tap()
    let result=app.staticTexts["ifc-source-result"];XCTAssertTrue(result.waitForExistence(timeout:75))
    XCTAssertTrue(result.label.contains("separate source frame"));XCTAssertTrue(result.label.contains("House alignment remains unknown"))
    for _ in 0..<4 {if result.isHittable{break};app.swipeUp()}
    XCTAssertTrue(result.isHittable)
    let coordinates=app.staticTexts["ifc-source-coordinates"];XCTAssertTrue(coordinates.exists)
    let retained=coordinates.label;XCTAssertTrue(retained.contains("without a local offset"));screenshot("21-saved-ifc-source-frame")
    let properties=app.staticTexts["ifc-source-properties"];XCTAssertTrue(properties.exists);let retainedProperties=properties.label
    XCTAssertTrue(retainedProperties.contains("Converted 1 of 1"))
    let inspect=app.buttons["Inspect source properties"]
    for _ in 0..<4 {if inspect.isHittable{break};app.swipeDown()}
    XCTAssertTrue(inspect.isHittable);inspect.tap()
    let object=app.buttons["ifc-property-record-22"]
    for _ in 0..<6 {if object.exists && object.isHittable{break};app.swipeUp()}
    XCTAssertTrue(object.isHittable);object.tap()
    let values=app.staticTexts["ifc-property-record-values"];XCTAssertTrue(values.waitForExistence(timeout:10));XCTAssertTrue(values.label.contains("Analytic 1x2x3 metre block"));screenshot("23-ifc-source-object-properties")
    app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap()
    app.navigationBars["Source.ifc"].buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Source.ifc"].waitForExistence(timeout:10));app.staticTexts["Source.ifc"].tap()
    XCTAssertTrue(coordinates.waitForExistence(timeout:10));XCTAssertEqual(coordinates.label,retained)
    XCTAssertEqual(properties.label,retainedProperties)
    app.navigationBars["Source.ifc"].buttons["Save"].tap()
  }
  @MainActor func testPointCloudDeclarationWorkflow() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--point-cloud-demo"];app.launch()
    defer{app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Tools"].waitForExistence(timeout:20));app.tabBars.buttons["Tools"].tap()
    app.buttons["Drawings & design references"].tap();app.staticTexts["Source.ply"].tap()
    let reopen=app.buttons["Import this point cloud"];XCTAssertTrue(reopen.waitForExistence(timeout:10));reopen.tap()
    let add=app.buttons["Import declared geometry"];XCTAssertTrue(add.waitForExistence(timeout:10));XCTAssertFalse(add.isEnabled)
    app.descendants(matching:.any)["point-cloud-units"].firstMatch.tap();app.buttons["Millimetres"].tap();XCTAssertFalse(add.isEnabled)
    app.descendants(matching:.any)["point-cloud-upright"].firstMatch.tap();app.buttons["Y up"].tap();XCTAssertFalse(add.isEnabled)
    app.descendants(matching:.any)["point-cloud-room"].firstMatch.tap();app.buttons["Source room"].tap()
    XCTAssertTrue(add.isEnabled);screenshot("19-point-cloud-coordinate-declaration");add.tap()
    XCTAssertTrue(reopen.waitForExistence(timeout:10));app.navigationBars["Source.ply"].buttons["Save"].tap()
    app.tabBars.buttons["Evidence"].tap();app.swipeUp()
    XCTAssertTrue(app.staticTexts["Source"].firstMatch.waitForExistence(timeout:10));app.staticTexts["Source"].firstMatch.tap()
    let declaration=app.staticTexts["Imported coordinates: Millimetres, Y up. Owner-declared; placement is not independently calibrated."]
    for _ in 0..<16 {if declaration.exists && declaration.isHittable{break};app.swipeUp()}
    XCTAssertTrue(declaration.isHittable);screenshot("20-point-cloud-recorded-provenance")
  }
  @MainActor func testBatchClassificationWorkflow() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
    defer{app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:20));app.tabBars.buttons["Evidence"].tap()
    app.buttons["Classify objects"].tap()
    app.descendants(matching:.any)["batch-system"].firstMatch.tap()
    try XCTUnwrap(app.buttons.matching(identifier:"Low voltage").allElementsBoundByIndex.last(where:{$0.isHittable})).tap()
    app.descendants(matching:.any)["batch-class"].firstMatch.tap()
    try XCTUnwrap(app.buttons.matching(identifier:"Low voltage").allElementsBoundByIndex.last(where:{$0.isHittable})).tap()
    let filter=app.textFields["Filter objects"];filter.tap();filter.typeText("Speaker")
    let done=app.buttons["batch-filter-done"]
    XCTAssertTrue(done.waitForExistence(timeout:5));XCTAssertEqual(app.buttons.matching(identifier:"batch-filter-done").count,1)
    screenshot("batch-filter-before-done");done.tap()
    let keyboardDismissed=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.keyboards.firstMatch)
    wait(for:[keyboardDismissed],timeout:5)
    let toggles=app.switches.matching(NSPredicate(format:"identifier BEGINSWITH %@","batch-object-"))
    XCTAssertEqual(toggles.count,3)
    setSwitch(toggles.element(boundBy:0),to:true);setSwitch(toggles.element(boundBy:1),to:true)
    app.buttons["Apply to 2 objects"].tap()
    XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout:10))
    app.swipeDown();let search=app.searchFields.firstMatch
    search.tap();search.typeText("speaker")
    let found=expectation(for:NSPredicate(format:"label == %@","0 photographs · 3 objects"),evaluatedWith:app.staticTexts["evidence-result-count"])
    wait(for:[found],timeout:10)
    app.staticTexts["Speaker prewire"].firstMatch.tap()
    let service=app.descendants(matching:.any)["object-service-class"].firstMatch
    for _ in 0..<10 {if service.exists && service.isHittable{break};app.swipeUp()}
    XCTAssertTrue(service.exists);XCTAssertTrue(service.label.contains("Low voltage") || (service.value as? String)?.contains("Low voltage")==true);screenshot("18-batch-classification")
    app.navigationBars["Object details"].buttons["Cancel"].tap()
  }
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
      var earlier=false
      for attempt in 0..<16 {
        let top=max(90,app.navigationBars.firstMatch.frame.maxY+8),bottom=min(app.frame.maxY-95,app.tabBars.firstMatch.frame.minY-8)
        if element.exists {
          let frame=element.frame
          if element.isHittable && frame.minY>=top && frame.maxY<=bottom{return}
          if frame.height>0 {
            if frame.minY<top {earlier=true}
            else if frame.maxY>bottom {earlier=false}
          }
        }else if attempt==8 {earlier.toggle()}
        // Short bidirectional moves handle Form reflow after saving a point
        // or switching to a curve without scrolling a visible image away.
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:earlier ? 0.35:0.65))
        let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:earlier ? 0.55:0.45))
        start.press(forDuration:0.05,thenDragTo:end)
      }
      screenshot("photo-control-reveal-failure")
      XCTFail("Photo control did not become fully visible: \(element.identifier), frame \(element.frame)")
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
    XCTAssertTrue(saved.waitForExistence(timeout:10));reveal(saved);screenshot("08-photo-point-saved")
    let mode=app.buttons["photo-mode-action"]
    XCTAssertTrue(mode.waitForExistence(timeout:5));XCTAssertTrue(mode.isHittable);mode.tap()
    let curveEnabled=expectation(for:NSPredicate(format:"label == %@","Locate a point"),evaluatedWith:mode)
    wait(for:[curveEnabled],timeout:5)
    XCTAssertTrue(app.navigationBars["Photo curve"].exists)
    for offset in [-0.0677083333,0.0677083333] {
      let first=app.descendants(matching:.any)["point-image-0"].firstMatch
      reveal(first)
      for index in 0..<3 {
        let image=app.descendants(matching:.any)["point-image-\(index)"].firstMatch;reveal(image)
        let frame=image.frame,w=min(frame.width,frame.height*4/3),h=w*3/4
        let u=[0.6083333333,0.5,0.3916666667][index]+offset,v=0.6354166667
        image.coordinate(withNormalizedOffset:CGVector(dx:((frame.width-w)/2+w*u)/frame.width,dy:((frame.height-h)/2+h*v)/frame.height)).tap()
      }
      let add=app.buttons["Check and add curve point"];reveal(add);XCTAssertTrue(add.isEnabled);add.tap()
    }
    let visible=app.switches["Every joining interval is visible in the source photos"];reveal(visible);setSwitch(visible,to:true)
    let saveCurve=app.buttons["Save photo-traced curve"];reveal(saveCurve);XCTAssertTrue(saveCurve.isEnabled);saveCurve.tap()
    let savedCurve=app.staticTexts["Saved Photo-traced curve with 2 independently checked source tracks."]
    XCTAssertTrue(savedCurve.waitForExistence(timeout:10));reveal(savedCurve)
    screenshot("16-photo-curve-saved")
    mode.tap();XCTAssertTrue(app.navigationBars["Photo point"].waitForExistence(timeout:5))
    XCTAssertEqual(mode.label,"Trace a curve")
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
    app.staticTexts["Speaker prewire"].firstMatch.tap()
    func revealField(_ field:XCUIElement) {
      for _ in 0..<12 {
        let frame=field.exists ? field.frame:.zero
        if field.exists && field.isHittable && frame.minY>120 && frame.maxY<app.frame.maxY-100{return}
        let moveDown=field.exists && frame.maxY>0 && frame.minY<120
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:moveDown ? 0.32:0.65))
        let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:moveDown ? 0.65:0.32))
        start.press(forDuration:0.05,thenDragTo:end)
      }
      screenshot("service-field-reveal-failure")
      XCTAssertTrue(field.isHittable)
    }
    let label=app.textFields["service-observed-label"]
    revealField(label);label.tap();label.typeText("Label-UI-contract")
    let done=app.buttons["service-keyboard-done"];XCTAssertTrue(done.waitForExistence(timeout:5));screenshot("16-service-label-entry")
    XCTAssertEqual(app.buttons.matching(identifier:"service-keyboard-done").count,1);done.tap()
    let port=app.textFields["service-port"]
    revealField(port);port.tap();port.typeText("P-UI-24")
    XCTAssertTrue(done.waitForExistence(timeout:5));XCTAssertEqual(app.buttons.matching(identifier:"service-keyboard-done").count,1);done.tap();screenshot("22-service-fields-before-save")
    app.navigationBars["Object details"].buttons["Save"].tap()
    XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout:10))
    app.terminate();app.launch()
    XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:20));app.tabBars.buttons["Evidence"].tap()
    app.swipeDown();let freshSearch=app.searchFields.firstMatch
    XCTAssertTrue(freshSearch.waitForExistence(timeout:10));freshSearch.tap();freshSearch.typeText("kitchen Label-UI-contract P-UI-24")
    let restored=expectation(for:NSPredicate(format:"label == %@","0 photographs · 1 object"),evaluatedWith:app.staticTexts["evidence-result-count"])
    wait(for:[restored],timeout:10)
    app.staticTexts["Speaker prewire"].firstMatch.tap();revealField(label)
    XCTAssertEqual(label.value as? String,"Label-UI-contract");revealField(port)
    XCTAssertEqual(port.value as? String,"P-UI-24");screenshot("17-typed-service-details-restored")
  }
  @MainActor func testStepNavigationControlsInBothOrientations() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
    defer {XCUIDevice.shared.orientation = .portrait;app.terminate()}
    XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout:20));app.tabBars.buttons["Explore"].tap()
    app.buttons["Layers"].tap()
    setSwitch(app.switches["Step and snap-turn buttons"],to:true)
    app.buttons["Done"].tap()
    screenshot("13-portrait-step-navigation")
    let names=["Step left","Step forward","Step backward","Step right","Turn left 15 degrees","Look up 15 degrees","Look down 15 degrees","Turn right 15 degrees"]
    for orientation in [UIDeviceOrientation.portrait,.landscapeLeft] {
      XCUIDevice.shared.orientation=orientation
      for name in names {
        let button=app.buttons[name];XCTAssertTrue(button.waitForExistence(timeout:5));XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.width,44);XCTAssertGreaterThanOrEqual(button.frame.height,44)
        XCTAssertTrue(app.frame.contains(button.frame));button.tap()
      }
    }
    screenshot("14-landscape-step-navigation")
    app.buttons["Layers"].tap();setSwitch(app.switches["Orbit overview"],to:true);app.buttons["Done"].tap()
    XCTAssertFalse(app.buttons["Step forward"].isEnabled)
    app.buttons["Layers"].tap();setSwitch(app.switches["Orbit overview"],to:false);app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Step forward"].isEnabled)
    app.buttons["Layers"].tap();setSwitch(app.switches["Step and snap-turn buttons"],to:false);app.buttons["Done"].tap()
  }
  @MainActor func testSinglePhotoAnnotationSurvivesRelaunch() throws {
    continueAfterFailure=false
    let app=XCUIApplication();app.launchArguments=["--documentary-demo","--documentary-demo-reset"];app.launch()
    defer {app.terminate()}
    func openPhoto(){
      XCTAssertTrue(app.tabBars.buttons["Evidence"].waitForExistence(timeout:30));app.tabBars.buttons["Evidence"].tap()
      let photo=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Annotation source photograph")).firstMatch
      XCTAssertTrue(photo.waitForExistence(timeout:10));photo.tap()
      XCTAssertTrue(app.descendants(matching:.any)["documentary-annotation-image"].firstMatch.waitForExistence(timeout:10))
    }
    func reveal(_ element:XCUIElement){
      for _ in 0..<8 {
        if element.exists && element.isHittable && element.frame.maxY<app.frame.maxY-50{return}
        app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.82)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.30)))
      }
      XCTAssertTrue(element.isHittable)
    }
    openPhoto()
    let surface=app.descendants(matching:.any)["documentary-annotation-image"].firstMatch
    surface.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.45)).tap()
    let add=app.buttons["documentary-add-annotation"];reveal(add);XCTAssertTrue(add.isEnabled);add.tap()
    let count=app.staticTexts["documentary-annotation-count"]
    XCTAssertEqual(count.label,"1 2D annotation")
    let undo=app.buttons["Undo annotation edit"];reveal(undo);undo.tap();XCTAssertEqual(count.label,"0 2D annotations")
    app.swipeDown();app.swipeDown()
    surface.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.45)).tap();reveal(add);add.tap()
    app.buttons["documentary-save"].tap()
    app.terminate();app.launchArguments=["--documentary-demo"];app.launch();openPhoto()
    screenshot("15a-single-photo-restored-image")
    reveal(count);XCTAssertEqual(count.label,"1 2D annotation")
    screenshot("15-single-photo-annotation-restored")
  }
  @MainActor private func setSwitch(_ row:XCUIElement,to enabled:Bool) {
    XCTAssertTrue(row.waitForExistence(timeout:5))
    let expected=enabled ? "1":"0"
    if row.value as? String != expected {
      // SwiftUI exposes the labeled Form row and its UISwitch separately.
      // A center tap on the row can hit the label without changing the switch.
      let control=row.switches.firstMatch
      (control.exists ? control:row).tap()
    }
    let changed=expectation(for:NSPredicate(format:"value == %@",expected),evaluatedWith:row)
    wait(for:[changed],timeout:5)
  }
  func screenshot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
}


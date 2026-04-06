//
//  MathPDFUITestsLaunchTests.swift
//  MathPDFUITests
//
//  Created by Zihong Lin on 4/5/26.
//

import XCTest

final class MathPDFUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }
}

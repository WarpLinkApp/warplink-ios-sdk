#if canImport(SwiftUI)
import SwiftUI
import XCTest
@testable import WarpLink

/// The SwiftUI button keeps every call shape an app wrote against 1.3.0, and
/// the Tether shape has its own label. This file is the compile check.
@available(iOS 16.0, macOS 13.0, *)
final class TetherPasteButtonSourceTests: XCTestCase {

    func testTheTrailingClosureShapeFromBeforeTetherStillCompiles() {
        let button = WarpLinkPasteButton { _ in }

        XCTAssertNotNil(button)
    }

    func testTheLabelledShapeFromBeforeTetherStillCompiles() {
        let button = WarpLinkPasteButton(onResult: { (_: Result<WarpLinkDeepLink?, WarpLinkError>) in })

        XCTAssertNotNil(button)
    }

    func testTheTetherShapesCompile() {
        let tether = WarpLinkPasteButton(onTether: { _ in })
        let both = WarpLinkPasteButton(onResult: { _ in }, onTether: { _ in })

        XCTAssertNotNil(tether)
        XCTAssertNotNil(both)
    }
}
#endif

import ReactiveCharacterKit
import XCTest

final class CharacterAppearanceValidationTests: XCTestCase {
  func testRegionReportsNonFiniteValuesBeforeInvalidBounds() {
    XCTAssertThrowsError(
      try CharacterRegion(name: "eyes", x: .infinity, y: -1, width: 0, height: 0)
    ) { error in
      XCTAssertEqual(error as? CharacterAppearanceError,
                     .invalidRegion(name: "eyes", reason: "all values must be finite"))
      XCTAssertEqual(String(describing: error), "region eyes is invalid: all values must be finite")
    }
  }

  func testColorReportsTheFirstInvalidComponentWithoutSemanticRejection() {
    XCTAssertThrowsError(try CharacterColor(red: .nan, green: 2, blue: 0)) { error in
      guard case .nonFiniteColorComponent(let field, let value) = error as? CharacterAppearanceError else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(field, "red")
      XCTAssertTrue(value.isNaN)
      XCTAssertEqual(String(describing: error), "red must be finite; received \(Double.nan)")
    }
    XCTAssertThrowsError(try CharacterColor(red: 0, green: 2, blue: .infinity)) { error in
      XCTAssertEqual(error as? CharacterAppearanceError,
                     .colorComponentOutOfRange(field: "green", value: 2))
      XCTAssertEqual(String(describing: error), "green must be in 0...1; received 2.0")
    }
  }

  func testStyleRejectsInvalidLineWidthAsAppearanceConfiguration() {
    XCTAssertThrowsError(try CharacterStyle(lineWidth: 0)) { error in
      XCTAssertEqual(error as? CharacterAppearanceError, .invalidStyle(field: "lineWidth", value: 0))
      XCTAssertEqual(String(describing: error), "style.lineWidth is invalid: 0.0")
    }
  }
}

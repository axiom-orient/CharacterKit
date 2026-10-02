import ReactiveCharacterKit
import XCTest

final class CharacterPresentationValidationTests: XCTestCase {
  func testMotionProfileValidationRejectsInvalidValues() {
    XCTAssertThrowsError(try CharacterMotionProfile(expressiveness: 2)) { error in
      XCTAssertEqual(error as? CharacterPresentationError,
                     .invalidMotionProfile(field: "expressiveness", value: 2))
      XCTAssertEqual(String(describing: error), "motionProfile.expressiveness is invalid: 2.0")
    }
    XCTAssertThrowsError(try CharacterMotionProfile(trailStrength: -.leastNonzeroMagnitude)) { error in
      XCTAssertEqual(error as? CharacterPresentationError,
                     .invalidMotionProfile(field: "trailStrength", value: -.leastNonzeroMagnitude))
    }
    XCTAssertThrowsError(try CharacterMotionProfile(idleStrength: -.infinity)) { error in
      XCTAssertEqual(error as? CharacterPresentationError,
                     .invalidMotionProfile(field: "idleStrength", value: -.infinity))
    }
  }

  func testTransitionProfileCannotExceedOneSecondHandoff() {
    XCTAssertThrowsError(
      try CharacterTransitionProfile(
        minimumReturnDuration: 0.2,
        maximumReturnDuration: 0.92,
        neutralHoldDuration: 0.10,
        rebound: 0.02
      )
    ) { error in
      guard case .invalidTransitionProfile(let field, let value) = error as? CharacterPresentationError else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(field, "transitionTotalDuration")
      XCTAssertEqual(value, 1.02, accuracy: 1e-12)
    }
  }

  func testTransitionReportsInvalidNumbersBeforeDurationRelations() {
    XCTAssertThrowsError(
      try CharacterTransitionProfile(minimumReturnDuration: .nan, maximumReturnDuration: 0)
    ) { error in
      guard case .invalidTransitionProfile(let field, let value) = error as? CharacterPresentationError else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(field, "transition")
      XCTAssertTrue(value.isNaN)
      XCTAssertEqual(String(describing: error), "transitionProfile.transition is invalid: \(Double.nan)")
    }
  }
}

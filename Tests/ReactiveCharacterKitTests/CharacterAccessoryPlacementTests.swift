import XCTest

@testable import ReactiveCharacterKit

final class CharacterAccessoryPlacementTests: XCTestCase {
  func testRejectsNonFiniteAndOutOfBudgetValues() {
    for value in [Double.nan, .infinity, -.infinity, -3, 4] {
      XCTAssertThrowsError(try CharacterAccessoryPlacement(centerX: value, width: 1, height: 1))
      XCTAssertThrowsError(try CharacterAccessoryPlacement(centerY: value, width: 1, height: 1))
    }
    for value in [Double.nan, .infinity, 0, -1, 4.01] {
      XCTAssertThrowsError(try CharacterAccessoryPlacement(width: value, height: 1))
      XCTAssertThrowsError(try CharacterAccessoryPlacement(width: 1, height: value))
    }
    for value in [Double.nan, .infinity, -0.01, 1.01] {
      XCTAssertThrowsError(try CharacterAccessoryPlacement(width: 1, height: 1, opacity: value))
    }
    XCTAssertThrowsError(try CharacterAccessoryPlacement(width: 1, height: 1, angle: .infinity))
    XCTAssertThrowsError(try CharacterAccessoryPlacement(width: 1, height: 1, angle: 7))
  }

  func testValidationReportsFieldWithoutRepairingInput() {
    XCTAssertThrowsError(try CharacterAccessoryPlacement(width: 0, height: 1)) {
      XCTAssertEqual(
        $0 as? CharacterAccessoryPlacementError, .invalidValue(field: "width", value: 0))
    }
  }

  func testBuiltInImageEnvelopesPreserveOriginalGeometry() throws {
    let expected: [(CharacterAccessoryAsset, Double, Double, Double, Double)] = [
      (.hood, -0.04, -0.06, 1.08, 1.08),
      (.baseballCap, 0.00, -0.21, 1.00, 0.80),
      (.bunnyEars, 0.20, -0.20, 0.60, 0.58),
    ]
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    for (accessory, x, y, w, h) in expected {
      let direction = try CharacterArtDirection(name: "Accessory envelope", assets: .init(accessories: [accessory]))
      let scene = try CharacterSceneBuilder.scene(pose: pose, artDirection: direction, width: 200, height: 300)
      let face = scene.faceBounds.rect
      let actual = try XCTUnwrap(scene.nodes.first { $0.id == "art.accessory.0" }?.image).bounds.rect
      let wanted = CharacterRect(
        x: face.x + face.width * x, y: face.y + face.height * y,
        width: face.width * w, height: face.height * h)
      XCTAssertEqual(actual.x, wanted.x, accuracy: 1e-12)
      XCTAssertEqual(actual.y, wanted.y, accuracy: 1e-12)
      XCTAssertEqual(actual.width, wanted.width, accuracy: 1e-12)
      XCTAssertEqual(actual.height, wanted.height, accuracy: 1e-12)
    }
  }

  func testEveryAnchorFollowsItsLayoutNotASecondHardcodedFace() throws {
    let face = CharacterRect(x: 10, y: 20, width: 200, height: 300)
    let layout = CharacterLayout.strict
    let expected: [(CharacterAccessoryAnchor, CharacterRect)] = [
      (.face, face), (.eyes, CharacterGeometry.map(layout.eyes, into: face)),
      (.nose, CharacterGeometry.map(layout.nose, into: face)),
      (.mouth, CharacterGeometry.map(layout.mouth, into: face)),
      (.writing, CharacterGeometry.map(layout.writing, into: face)),
    ]
    for (anchor, rect) in expected {
      let placement = try CharacterAccessoryPlacement(anchor: anchor, width: 1, height: 1)
      let actual = CharacterAccessoryGeometry.envelope(for: placement, face: face, layout: layout)
      XCTAssertEqual(actual.x, rect.x, accuracy: 1e-12)
      XCTAssertEqual(actual.y, rect.y, accuracy: 1e-12)
      XCTAssertEqual(actual.width, rect.width, accuracy: 1e-12)
      XCTAssertEqual(actual.height, rect.height, accuracy: 1e-12)
    }
  }

  func testAspectFitPreservesSourceRatioAndCenter() throws {
    let envelope = CharacterRect(x: 10, y: 20, width: 200, height: 100)
    for image in [CharacterSize(width: 40, height: 10), CharacterSize(width: 10, height: 40)] {
      let rect = try XCTUnwrap(CharacterAccessoryGeometry.aspectFit(image: image, in: envelope))
      XCTAssertEqual(rect.width / rect.height, image.width / image.height, accuracy: 1e-12)
      XCTAssertEqual(rect.midX, envelope.midX)
      XCTAssertEqual(rect.midY, envelope.midY)
      XCTAssertLessThanOrEqual(rect.width, envelope.width)
      XCTAssertLessThanOrEqual(rect.height, envelope.height)
    }
    XCTAssertNil(
      CharacterAccessoryGeometry.aspectFit(image: .init(width: 0, height: 10), in: envelope))
  }

  func testPresetsAndLayerVocabularyAreDeterministic() {
    XCTAssertEqual(
      CharacterAccessoryLayer.allCases, [.behindSurface, .behindFeatures, .foreground])
    let face = CharacterRect(x: 0, y: 0, width: 100, height: 100)
    for preset: CharacterAccessoryPlacement in [.glasses, .crown, .bowTie, .badge] {
      let a = CharacterAccessoryGeometry.envelope(for: preset, face: face, layout: .default)
      let b = CharacterAccessoryGeometry.envelope(for: preset, face: face, layout: .default)
      XCTAssertEqual(a, b)
      XCTAssertGreaterThan(a.width, 0)
      XCTAssertGreaterThan(a.height, 0)
    }
  }
}

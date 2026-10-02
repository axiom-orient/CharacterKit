import XCTest

@testable import ReactiveCharacterKit

final class CharacterOrnamentPlacementTests: XCTestCase {
  private func assertOnPerimeter(
    _ accent: CharacterAccentPose,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let bounds = CharacterOrnamentPlacement.envelope(for: accent)
    let safe = CharacterOrnamentPlacement.faceFeatureSafeZone
    let intersectsSafe =
      bounds.minX < safe.maxX && safe.minX < bounds.maxX
      && bounds.minY < safe.maxY && safe.minY < bounds.maxY
    XCTAssertGreaterThanOrEqual(bounds.minX, 0, file: file, line: line)
    XCTAssertLessThanOrEqual(bounds.maxX, 1, file: file, line: line)
    XCTAssertGreaterThanOrEqual(bounds.minY, 0, file: file, line: line)
    XCTAssertLessThanOrEqual(bounds.maxY, 1, file: file, line: line)
    XCTAssertFalse(intersectsSafe, file: file, line: line)
  }

  func testNoAccessoryAndBehindPlaneHoodPreserveAuthoredCue() {
    let puff = CharacterAccentPose(
      kind: .puff, centerX: 0.14, centerY: 0.68,
      width: 0.14, height: 0.08, angle: 0, opacity: 0.3)
    XCTAssertEqual(CharacterOrnamentPlacement.adjusted(puff, avoiding: []), puff)
    XCTAssertEqual(
      CharacterOrnamentPlacement.adjusted(puff, avoiding: [.hood]), puff)
  }

  func testRimFitSpeakerRoutesCheekTearWithoutChangingItsMeaning() {
    let tear = CharacterAccentPose(
      kind: .tearDrop, centerX: 0.80, centerY: 0.51,
      width: 0.05, height: 0.10, angle: 0, opacity: 0.4)
    let adjusted = CharacterOrnamentPlacement.adjusted(
      tear, avoiding: [.arcadeHeadset])
    XCTAssertNotEqual(adjusted, tear)
    XCTAssertGreaterThanOrEqual(adjusted.centerX, tear.centerX)
    XCTAssertEqual(adjusted.kind, tear.kind)
    XCTAssertEqual(adjusted.opacity, tear.opacity)
    assertOnPerimeter(adjusted)
  }

  func testOuterSpeakerCollisionRoutesTearWithoutChangingItsSideOrMeaning() {
    let tear = CharacterAccentPose(
      kind: .tearDrop, centerX: 0.915, centerY: 0.51,
      width: 0.05, height: 0.10, angle: 0, opacity: 0.4)
    let adjusted = CharacterOrnamentPlacement.adjusted(
      tear, avoiding: [.arcadeHeadset])
    XCTAssertNotEqual(adjusted, tear)
    XCTAssertGreaterThanOrEqual(adjusted.centerX, tear.centerX)
    XCTAssertEqual(adjusted.kind, tear.kind)
    XCTAssertEqual(adjusted.opacity, tear.opacity)
    assertOnPerimeter(adjusted)
  }

  func testHeadsetRoutesLeftSweatToSafeLeftPerimeterLane() {
    let sweat = CharacterAccentPose(
      kind: .sweatDrop, centerX: 0.16, centerY: 0.33,
      width: 0.05, height: 0.10, angle: -0.20, opacity: 0.3)
    let adjusted = CharacterOrnamentPlacement.adjusted(
      sweat, avoiding: [.arcadeHeadset])
    XCTAssertNotEqual(adjusted, sweat)
    XCTAssertLessThanOrEqual(adjusted.centerX, CharacterOrnamentPlacement.faceFeatureSafeZone.minX)
    XCTAssertNotEqual(adjusted.centerY, sweat.centerY)
    assertOnPerimeter(adjusted)
  }

  func testPinMovesRightHeartButKeepsRightPerimeterLane() {
    let heart = CharacterAccentPose(
      kind: .heart, centerX: 0.88, centerY: 0.17,
      width: 0.13, height: 0.13, angle: 0.16, opacity: 0.6)
    let adjusted = CharacterOrnamentPlacement.adjusted(
      heart, avoiding: [.baseballCap])
    XCTAssertNotEqual(adjusted, heart)
    XCTAssertGreaterThanOrEqual(
      CharacterOrnamentPlacement.envelope(for: adjusted).minX,
      CharacterOrnamentPlacement.faceFeatureSafeZone.maxX)
    assertOnPerimeter(adjusted)
  }

  func testBlockedTopCueNeverJumpsToAnotherSemanticSide() {
    let ray = CharacterAccentPose(
      kind: .ray, centerX: 0.50, centerY: 0.05,
      width: 0.16, height: 0.03, angle: 0, opacity: 0.5)
    let adjusted = CharacterOrnamentPlacement.adjusted(
      ray, avoiding: [.arcadeHeadset])
    let bounds = CharacterOrnamentPlacement.envelope(for: adjusted)
    XCTAssertLessThanOrEqual(bounds.maxY, CharacterOrnamentPlacement.faceFeatureSafeZone.minY)
    assertOnPerimeter(adjusted)
  }

  func testDesignedBehindSurfaceAccessoryDoesNotMoveOrnament() throws {
    let accent = CharacterAccentPose(
      kind: .heart, centerX: 0.88, centerY: 0.17,
      width: 0.13, height: 0.13, angle: 0.16, opacity: 0.6)
    let placement = try CharacterAccessoryPlacement(
      anchor: .face, layer: .behindSurface, centerX: 0.86, centerY: 0.17,
      width: 0.30, height: 0.30)
    let accessory = CharacterDesignedAccessory(
      id: "background-badge", label: "Background badge", glyph: .badge,
      placement: placement, color: .accent)

    XCTAssertEqual(
      CharacterOrnamentPlacement.adjusted(
        accent, avoiding: [accessory], layout: .default),
      accent)
  }

  func testApplicationAssetWithBuiltInNameDoesNotBorrowPackageCollisionPolicy() throws {
    let accent = CharacterAccentPose(
      kind: .tearDrop, centerX: 0.80, centerY: 0.51,
      width: 0.05, height: 0.10, angle: 0, opacity: 0.4)
    let image = try CharacterImageAsset(name: CharacterImageAsset.arcadeHeadset.name)
    let custom = try CharacterAccessoryAsset(
      image: image, width: 0.10, height: 0.10, accessibilityLabel: "Host asset")

    XCTAssertEqual(CharacterOrnamentPlacement.adjusted(accent, avoiding: [custom]), accent)
  }

  func testPlacementIsDeterministic() {
    let accent = CharacterAccentPose(
      kind: .ring, centerX: 0.91, centerY: 0.66,
      width: 0.11, height: 0.15, angle: 0, opacity: 0.3)
    let a = CharacterOrnamentPlacement.adjusted(accent, avoiding: [.arcadeHeadset])
    let b = CharacterOrnamentPlacement.adjusted(accent, avoiding: [.arcadeHeadset])
    XCTAssertEqual(a, b)
  }
}

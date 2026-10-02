import XCTest

@testable import ReactiveCharacterKit

final class CharacterArtDirectionTests: XCTestCase {
  func testBuiltInAppearancesShareGeometryAndUsePaletteMatchedAssets() {
    let directions = [
      CharacterArtDirection.black,
      .white,
      .arcade,
    ]

    XCTAssertTrue(directions.allSatisfy { $0.layout == .standard })
    XCTAssertTrue(directions.allSatisfy { $0.projection == .softSphere })
    XCTAssertTrue(directions.allSatisfy { $0.motionProfile == .cartoon })
    XCTAssertTrue(directions.allSatisfy { $0.transitionProfile == .cartoon })
    XCTAssertEqual(directions.map(\.assets), [.black, .white, .arcade])
    XCTAssertEqual(
      directions.flatMap { $0.assets.accessories.map(\.image.name) },
      ["headset-black", "headset-white", "headset-arcade"])
    XCTAssertTrue(
      directions.allSatisfy { $0.contentInset == CharacterArtDirection.canonicalContentInset })
    XCTAssertTrue(directions.allSatisfy { $0.featureGlow == 0 && $0.ornamentGlow == 0 })

    XCTAssertNotEqual(
      CharacterArtDirection.black.style.partColors, CharacterArtDirection.white.style.partColors)
    XCTAssertNotEqual(
      CharacterArtDirection.black.style.partColors, CharacterArtDirection.arcade.style.partColors)
  }

  func testCustomArtDirectionNeedsNoPresetOrRegistry() throws {
    let image = try CharacterImageAsset(name: "my-face", source: .application)
    let assets = CharacterAssetPack(face: image)
    let style = try CharacterStyle(lineWidth: 0.012)
    let direction = try CharacterArtDirection(
      name: "Product Character",
      components: .face,
      layout: .strict,
      style: style,
      surface: .visible,
      projection: .flat,
      motionProfile: .soft,
      transitionProfile: .reducedMotion,
      assets: assets,
      featureGlow: 0.4,
      ornamentGlow: 0.2
    )

    XCTAssertEqual(direction.assets.face, image)
    XCTAssertEqual(direction.components, .face)
    XCTAssertEqual(direction.style, style)
  }

  func testArtDirectionRejectsInvalidNameAndGlow() {
    XCTAssertThrowsError(try CharacterArtDirection(name: ""))
    XCTAssertThrowsError(try CharacterArtDirection(name: "x", featureGlow: .infinity))
    XCTAssertThrowsError(try CharacterArtDirection(name: "x", ornamentGlow: 2))
  }

  func testChangingPresentationDoesNotChangeSemanticState() throws {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let custom = try CharacterArtDirection(name: "Minimal", assets: .empty)
    XCTAssertEqual(state.emotion, .joy)
    XCTAssertNotEqual(custom, .black)
    XCTAssertEqual(
      state,
      ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state)
  }

  func testCartoonProfilesStayPresentationOnlyAndWithinValidatedRange() throws {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let expressive = ReactiveCharacter.pose(state: state, elapsed: 0.12, motionProfile: .expressive)
    let cartoon = ReactiveCharacter.pose(state: state, elapsed: 0.12, motionProfile: .cartoon)

    XCTAssertNotEqual(cartoon, expressive)
    XCTAssertEqual(state.emotion, .joy)
    XCTAssertGreaterThan(CharacterMotionProfile.cartoon.expressiveness, 1)
    XCTAssertLessThanOrEqual(CharacterMotionProfile.cartoon.expressiveness, 1.5)
    XCTAssertLessThanOrEqual(
      CharacterTransitionProfile.cartoon.maximumReturnDuration
        + CharacterTransitionProfile.cartoon.neutralHoldDuration,
      CharacterTransitionProfile.maximumAllowedHandoffDuration)
  }

  func testReplacingFaceTreatmentPreservesEverythingElse() {
    let base = CharacterArtDirection.arcade
    let changed = base.replacingFaceTreatment(eyes: .horizontal, mouth: .filled)

    XCTAssertEqual(changed.name, base.name)
    XCTAssertEqual(changed.components, base.components)
    XCTAssertEqual(changed.layout, base.layout)
    XCTAssertEqual(changed.assets, base.assets)
    XCTAssertEqual(changed.motionProfile, base.motionProfile)
    XCTAssertEqual(changed.transitionProfile, base.transitionProfile)
    XCTAssertEqual(changed.style.eyeTreatment, .horizontal)
    XCTAssertEqual(changed.style.mouthTreatment, .filled)
    XCTAssertEqual(changed.style.partColors, base.style.partColors)
  }
}

import XCTest

@testable import ReactiveCharacterKit

final class CharacterPartColorTests: XCTestCase {
  private func color(_ red: Double, _ green: Double, _ blue: Double) throws -> CharacterColor {
    try CharacterColor(red: red, green: green, blue: blue)
  }

  private func solid(_ node: CharacterSceneNode?) throws -> CharacterColor {
    let node = try XCTUnwrap(node)
    guard case .solid(let color) = node.fill else {
      throw XCTSkip("node does not use a solid fill")
    }
    return color
  }

  private func featureColor(_ node: CharacterSceneNode?) throws -> CharacterColor {
    let node = try XCTUnwrap(node)
    if case .solid(let color) = node.fill { return color }
    if let stroke = node.stroke { return stroke }
    throw XCTSkip("node does not expose a fill or stroke color")
  }

  private func emotionState(_ emotion: CharacterEmotion) -> CharacterState {
    ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
  }

  func testArtDirectionUsesIndependentFeatureColors() throws {
    let colors = CharacterPartColors(
      surface: try color(0.11, 0.12, 0.13),
      eyes: try color(0.21, 0.22, 0.23),
      nose: try color(0.31, 0.32, 0.33),
      mouth: try color(0.41, 0.42, 0.43),
      mouthDetail: try color(0.51, 0.52, 0.53),
      tongue: try color(0.61, 0.62, 0.63),
      writing: try color(0.71, 0.72, 0.73),
      accent: try color(0.81, 0.82, 0.83)
    )
    let direction = try CharacterArtDirection(
      name: "Color contract",
      components: .all,
      layout: .standard,
      style: CharacterStyle(partColors: colors, lineWidth: 0.012),
      surface: .visible,
      projection: .softSphere,
      motionProfile: .cartoon
    )
    let pose = ReactiveCharacter.pose(
      state: emotionState(.joy), elapsed: 0, reduceMotion: true,
      projection: direction.projection, motionProfile: direction.motionProfile)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 320, height: 320,
      environment: .init(reduceTransparency: true))

    XCTAssertEqual(try solid(scene.nodes.first { $0.id == "art.face" }), colors.surface)
    XCTAssertEqual(try featureColor(scene.nodes.first { $0.id == "eye.left" }), colors.eyes)
    XCTAssertEqual(scene.nodes.first { $0.id == "nose" }?.stroke, colors.nose)
    XCTAssertEqual(scene.nodes.first { $0.id == "mouth" }?.stroke, colors.mouth)
    XCTAssertEqual(try solid(scene.nodes.first { $0.id == "mouth.teeth" }), colors.mouthDetail)
    XCTAssertEqual(try solid(scene.nodes.first { $0.id == "mouth.innerTongue" }), colors.tongue)
  }

  func testDesignRuntimeColorsOverridePartsWithoutChangingGeometry() throws {
    var profile = try CharacterDesign.load(.white).profile
    profile.components = CharacterDesignComponent.allCases
    profile.rendering.mode = .flat
    profile.accessories = [
      CharacterDesignAccessory(
        id: "test-halo", label: "Test halo", glyph: .halo,
        anchor: .face, layer: .foreground,
        centerX: 0.5, centerY: 0.08, width: 0.42, height: 0.18,
        color: .feature
      )
    ]
    let design = try profile.compile()
    let colors = CharacterPartColors(
      surface: try color(0.13, 0.19, 0.25),
      eyes: try color(0.17, 0.71, 0.92),
      nose: try color(0.92, 0.68, 0.18),
      mouth: try color(0.94, 0.31, 0.48),
      mouthDetail: try color(0.95, 0.94, 0.80),
      tongue: try color(0.96, 0.48, 0.66),
      writing: try color(0.50, 0.90, 0.74),
      accent: try color(0.72, 0.53, 0.97),
      accessory: try color(0.22, 0.91, 0.37),
      accessoryDetail: try color(0.94, 0.82, 0.19)
    )
    let pose = ReactiveCharacter.pose(
      state: emotionState(.joy), elapsed: 0, reduceMotion: true,
      projection: design.projection, motionProfile: design.motionProfile)
    let overlay = CharacterAccentPose(
      kind: .sparkle, centerX: 0.12, centerY: 0.22,
      width: 0.05, height: 0.05, angle: 0, opacity: 0.8)
    let base = try CharacterSceneBuilder.scene(
      pose: pose, design: design, width: 320, height: 320,
      environment: .init(reduceTransparency: true), overlayAccents: [overlay])
    let custom = try CharacterSceneBuilder.scene(
      pose: pose, design: design, width: 320, height: 320,
      environment: .init(reduceTransparency: true, partColors: colors), overlayAccents: [overlay])

    XCTAssertEqual(base.faceBounds, custom.faceBounds)
    XCTAssertEqual(base.nodes.map(\.path), custom.nodes.map(\.path))
    XCTAssertEqual(try solid(custom.nodes.first { $0.id == "surface.body" }), colors.surface)
    XCTAssertEqual(try solid(custom.nodes.first { $0.id == "eye.left" }), colors.eyes)
    XCTAssertEqual(custom.nodes.first { $0.id == "nose" }?.stroke, colors.nose)
    XCTAssertEqual(try featureColor(custom.nodes.first { $0.id == "mouth" }), colors.mouth)
    let detailColors = custom.nodes.filter {
      $0.id == "mouth.teeth" || $0.id == "mouth.innerTongue"
    }.compactMap {
      node -> CharacterColor? in
      guard case .solid(let color) = node.fill else { return nil }
      return color
    }
    XCTAssertTrue(detailColors.contains(colors.mouthDetail))
    XCTAssertTrue(detailColors.contains(colors.tongue))
    XCTAssertEqual(
      custom.nodes.first { $0.id == "accessory.test-halo.ring" }?.stroke, colors.accessory)
    XCTAssertEqual(try solid(custom.nodes.first { $0.id == "accent.0" }), colors.accent)
  }

  func testIncreasedContrastOwnsAccessibilityProjectionOverRuntimeColors() throws {
    var profile = try CharacterDesign.load(.white).profile
    profile.components = CharacterDesignComponent.allCases
    profile.rendering.mode = .flat
    let design = try profile.compile()
    let custom = CharacterPartColors(
      surface: try color(0.4, 0.4, 0.4),
      eyes: try color(0.45, 0.45, 0.45),
      mouth: try color(0.5, 0.5, 0.5)
    )
    let pose = ReactiveCharacter.pose(
      state: emotionState(.joy), elapsed: 0, reduceMotion: true,
      projection: design.projection, motionProfile: design.motionProfile)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, design: design, width: 320, height: 320,
      environment: .init(increasedContrast: true, partColors: custom))
    let surface = try solid(scene.nodes.first { $0.id == "surface.body" })
    let eye = try solid(scene.nodes.first { $0.id == "eye.left" })
    XCTAssertNotEqual(surface, custom.surface)
    XCTAssertNotEqual(eye, custom.eyes)
    XCTAssertEqual(surface.contrastRatio(with: eye), 21, accuracy: 0.001)
  }
}

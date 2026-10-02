import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class EyeColorTests: XCTestCase {
  func testCanonicalPartColorsChangePaintWithoutChangingGeometry() throws {
    let colors = CharacterPartColors(
      surface: try CharacterColor(red: 0.08, green: 0.10, blue: 0.14),
      eyes: try CharacterColor(red: 0.2, green: 0.9, blue: 1),
      mouth: try CharacterColor(red: 0.95, green: 0.42, blue: 0.62),
      mouthDetail: try CharacterColor(red: 1, green: 0.95, blue: 0.80),
      tongue: try CharacterColor(red: 0.98, green: 0.48, blue: 0.68),
      writing: try CharacterColor(red: 0.42, green: 0.88, blue: 0.72)
    )
    let task = try CharacterTaskID(validating: "part-colors")
    let started = ReactiveCharacter.act(
      state: .idle, event: .agentStarted(taskID: task)
    ).stateAfter
    let working = ReactiveCharacter.act(state: started, event: .agentProgress(taskID: task, progress: 0.4))
      .stateAfter
    let joyful = ReactiveCharacter.act(state: .idle, event: .emotionChanged(.joy)).stateAfter
    for state in [CharacterState.idle, joyful, working] {
      for reduced in [false, true] {
        let direction = try CharacterArtDirection(
          name: "Color contract", components: [.eyes, .mouth, .writing], projection: .flat)
        let pose = ReactiveCharacter.pose(
          state: state, elapsed: 0.8, reduceMotion: reduced,
          projection: direction.projection, motionProfile: direction.motionProfile)
        let original = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction, width: 400, height: 400,
          environment: .init(reduceTransparency: true))
        let updated = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction.replacingPartColors(colors), width: 400, height: 400,
          environment: .init(reduceTransparency: true))
        XCTAssertEqual(original.nodes.map(\.id), updated.nodes.map(\.id))
        XCTAssertEqual(original.nodes.map(\.path), updated.nodes.map(\.path))
        XCTAssertEqual(original.nodes.map(\.transform), updated.nodes.map(\.transform))
        XCTAssertEqual(
          updated.nodes.first { $0.id == "art.face" }?.fill,
          .solid(colors.surface))
        for node in updated.nodes where node.id.hasPrefix("eye") {
          if node.fill != nil { XCTAssertEqual(node.fill, .solid(colors.eyes)) }
          if node.stroke != nil { XCTAssertEqual(node.stroke, colors.eyes) }
        }
        if let mouth = updated.nodes.first(where: { $0.id == "mouth" }) {
          XCTAssertEqual(mouth.stroke, colors.mouth)
        }
        for node in updated.nodes where node.id.hasPrefix("writing") {
          if node.fill != nil { XCTAssertEqual(node.fill, .solid(colors.writing)) }
          if node.stroke != nil { XCTAssertEqual(node.stroke, colors.writing) }
        }
        _ = try CharacterSVGRenderer.render(updated)
      }
    }
  }

  func testProfileEyeRoundTripAndExistingDefaults() throws {
    for preset in CharacterDesignPreset.allCases {
      let original = try CharacterDesign.load(preset)
      if preset == .arcade {
        XCTAssertNotEqual(original.lightPalette.eye, original.lightPalette.feature)
      } else {
        XCTAssertEqual(original.lightPalette.eye, original.lightPalette.feature)
      }
      var profile = original.profile
      profile.rendering.mode = .flat
      profile.palettes.light.eye = "#33CCFF"
      profile.palettes.dark.eye = "#FFAA33"
      let design = try CharacterDesign.decode(JSONEncoder().encode(profile))
      XCTAssertEqual(design.profile, profile)
      XCTAssertNotEqual(design.lightPalette.eye, design.darkPalette.eye)
      let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0)
      for appearance in [CharacterDesignAppearance.light, .dark] {
        let scene = try CharacterSceneBuilder.scene(
          pose: pose, design: design, width: 240, height: 240,
          environment: .init(appearance: appearance))
        XCTAssertEqual(
          scene.nodes.first { $0.id == "eye.left" }?.fill,
          .solid(design.palette(for: appearance).eye))
      }
      XCTAssertEqual(
        design.lightPalette.increasedContrast().eye,
        original.lightPalette.increasedContrast().eye)
      profile.palettes.light.eye = "invalid"
      XCTAssertThrowsError(try profile.compile())
    }
  }
  func testDesignEyeColorAcrossRenderModesPreservesOtherFeatures() throws {
    let pose = ReactiveCharacter.pose(
      state: ReactiveCharacter.act(state: .idle, event: .emotionChanged(.joy)).stateAfter,
      elapsed: 0.6)
    for mode in CharacterRenderMode.allCases {
      var profile = try CharacterDesign.load(.black).profile
      profile.rendering.mode = mode
      let before = try CharacterSceneBuilder.scene(
        pose: pose, design: profile.compile(), width: 320, height: 320)
      profile.palettes.light.eye = "#33CCFF"
      let design = try profile.compile()
      let after = try CharacterSceneBuilder.scene(
        pose: pose, design: design, width: 320, height: 320)
      XCTAssertEqual(before.nodes.count, after.nodes.count)
      for (a, b) in zip(before.nodes, after.nodes) {
        if a.id.hasPrefix("eye"), !a.id.hasSuffix(".light") {
          XCTAssertEqual(a.path, b.path)
          XCTAssertEqual(a.transform, b.transform)
          if a.fill != nil { XCTAssertEqual(b.fill, .solid(design.lightPalette.eye)) }
          if a.stroke != nil { XCTAssertEqual(b.stroke, design.lightPalette.eye) }
        } else {
          XCTAssertEqual(a, b)
        }
      }
      let tokens = try XCTUnwrap(
        JSONSerialization.jsonObject(with: design.encodedTokens()) as? [String: Any])
      XCTAssertNotNil((tokens["color"] as? [String: Any])?["eye"])
    }
  }

  func testEyeJSONRejectsNullAndWrongType() throws {
    let design = try CharacterDesign.load(.black)
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(design.profile)) as? [String: Any])
    var palettes = try XCTUnwrap(root["palettes"] as? [String: Any])
    var light = try XCTUnwrap(palettes["light"] as? [String: Any])
    for invalid: Any in [NSNull(), 42] {
      light["eye"] = invalid
      palettes["light"] = light
      root["palettes"] = palettes
      XCTAssertThrowsError(try CharacterDesign.decode(JSONSerialization.data(withJSONObject: root)))
    }
  }

}

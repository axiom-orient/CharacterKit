import XCTest

@testable import ReactiveCharacterKit

final class CharacterSceneCompilerTests: XCTestCase {
  private func frame(ids: [String]) -> CharacterScene {
    CharacterScene(
      width: 100, height: 100, faceBounds: .init(.init(x: 0, y: 0, width: 100, height: 100)),
      surfaceTransform: .identity,
      nodes: ids.map {
        CharacterSceneNode(
          id: $0, layer: .surface, path: .ellipse(.init(x: 10, y: 10, width: 80, height: 80)),
          fill: .solid(.designWhite), stroke: nil, lineWidth: 0, opacity: 1,
          transform: .identity, clips: [])
      }, effectiveMode: .flat, isCompact: false)
  }

  func testSceneAndSVGRejectEmptyAndDuplicateNodeIdentity() throws {
    for ids in [[""], [" \n"], ["eye.left", "eye.left"]] {
      let scene = frame(ids: ids)
      XCTAssertThrowsError(try CharacterSceneValidation.validate(scene))
      XCTAssertThrowsError(try CharacterSVGRenderer.render(scene))
    }
    XCTAssertNoThrow(try CharacterSceneValidation.validate(frame(ids: ["left", "right"])))
  }

  func testPawUsesMinimalAnatomyWithoutEmittingFaceGeometry() throws {
    let direction = CharacterCatSupplementalAsset.pawPad.artDirection
    XCTAssertEqual(direction.anatomy, .minimal)
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: direction, width: 320, height: 320, includeBackground: false)
    XCTAssertFalse(scene.nodes.isEmpty)
    XCTAssertTrue(scene.nodes.allSatisfy { $0.image != nil })
  }

  func testBothDialectsUseTheSameViewportAndPoseGate() throws {
    let design = try CharacterDesign.load(.black)
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    for input in [CharacterAppearanceInput.design(design), .art(.catSimple2D)] {
      for size in [Double.nan, .infinity, 0, -1, 16_385] {
        XCTAssertThrowsError(try CharacterSceneCompiler.compile(
          pose: pose, input: input, width: size, height: 320, environment: .init(),
          includeBackground: false, overlays: []))
      }
      let scene = try CharacterSceneCompiler.compile(
        pose: pose, input: input, width: 320, height: 320, environment: .init(),
        includeBackground: false, overlays: [])
      XCTAssertEqual(scene.nodes.map(\.layer.rawValue), scene.nodes.map(\.layer.rawValue).sorted())
      XCTAssertEqual(Set(scene.nodes.map(\.id)).count, scene.nodes.count)
    }
  }

  func testArtDirectionKeepsItsOwnPaletteAndDesignKeepsContrastPrecedence() throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    let colors = CharacterStyle.white.partColors
    func art(_ environment: CharacterDesignEnvironment) throws -> CharacterScene {
      try CharacterSceneBuilder.scene(
        pose: pose, artDirection: .catSimple2D, width: 320, height: 320,
        environment: environment)
    }
    XCTAssertEqual(try art(.init()), try art(.init(partColors: colors)))
    let design = try CharacterDesign.load(.black)
    let first = try CharacterSceneBuilder.scene(
      pose: pose, design: design, width: 320, height: 320,
      environment: .init(increasedContrast: true))
    let second = try CharacterSceneBuilder.scene(
      pose: pose, design: design, width: 320, height: 320,
      environment: .init(increasedContrast: true, partColors: colors))
    XCTAssertEqual(first, second)
  }
}

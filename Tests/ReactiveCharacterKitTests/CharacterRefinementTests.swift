import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterRefinementTests: XCTestCase {
  private func scene(_ emotion: CharacterEmotion?, direction: CharacterArtDirection) throws
    -> CharacterScene
  {
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
    return try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: state, elapsed: 0.52, reduceMotion: true),
      artDirection: direction, width: 512, height: 560)
  }

  func testSimpleCatHasOneFlatFacePatchAndNoDefaultNoseOrOpticalIris() throws {
    let value = try scene(nil, direction: .catSimple2D)
    XCTAssertEqual(value.nodes.filter { $0.id == "cat.face.patch" }.count, 1)
    XCTAssertFalse(value.nodes.contains { $0.id == "nose" || $0.id == "cat.philtrum" })
    XCTAssertFalse(value.nodes.contains { $0.id.contains(".iris") || $0.id.contains("highlight") })
    XCTAssertFalse(value.nodes.contains { $0.image != nil })
  }

  func testPortraitAffectionConsumesHeartContourNotAnotherOval() throws {
    let value = try scene(.affection, direction: .portrait)
    let eye = try XCTUnwrap(value.nodes.first { $0.id == "eye.left" })
    let cubics = eye.path.commands.filter { if case .cubic = $0 { true } else { false } }
    XCTAssertEqual(cubics.count, 12, "Shared continuous contour must preserve heart topology")
  }

  func testPortraitSurpriseMouthOpensAboveAndBelowItsAnchor() throws {
    let value = try scene(.surprise, direction: .portrait)
    let mouth = try XCTUnwrap(value.nodes.first { $0.id == "mouth" })
    let ys = mouth.path.commands.flatMap { command -> [Double] in
      switch command {
      case .move(let p), .line(let p): [p.y]
      case .quad(let a, let b): [a.y, b.y]
      case .cubic(let a, let b, let c): [a.y, b.y, c.y]
      case .close: []
      }
    }
    XCTAssertLessThan(try XCTUnwrap(ys.min()), CharacterPortraitGeometry.mouthCenter.y - 5)
    XCTAssertGreaterThan(try XCTUnwrap(ys.max()), CharacterPortraitGeometry.mouthCenter.y + 5)
  }

  func testGirlAndBoyShareExpressionTopologyButOwnDifferentReferenceAnatomy() throws {
    for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
      let girl = try scene(emotion, direction: CharacterPortraitStyle.bobGirl.artDirection)
      let boy = try scene(emotion, direction: CharacterPortraitStyle.shortHairBoy.artDirection)
      for id in ["eye.left", "eye.right", "mouth"] {
        let girlPart = try XCTUnwrap(girl.nodes.first { $0.id == id })
        let boyPart = try XCTUnwrap(boy.nodes.first { $0.id == id })
        XCTAssertEqual(girlPart.path.commands.count, boyPart.path.commands.count)
      }
      XCTAssertNotEqual(girl.nodes.first { $0.id == "portrait.face" }?.path,
                        boy.nodes.first { $0.id == "portrait.face" }?.path)
      XCTAssertEqual(CharacterPortraitStyle.bobGirl.artDirection.style, .portrait)
    }
    XCTAssertTrue(CharacterPortraitStyle.bobGirl.artDirection.requiredImageAssets.isEmpty)
    XCTAssertTrue(CharacterPortraitStyle.shortHairBoy.artDirection.requiredImageAssets.isEmpty)
  }

  func testCompactBlinkHasStableTopologyAndNeverDisappears() throws {
    for contour: CharacterEyeContour in [.neutral, .init(crescent: 1), .init(heart: 1)] {
      var previous: [CharacterVectorPoint]?
      for step in 0...100 {
        let eye = CharacterEyePose(
          centerX: 0.3, centerY: 0.5, width: 0.19, height: 0.43,
          angle: 0, unblinkedWidth: 0.19, unblinkedHeight: 0.43, blink: Double(step) / 100)
        let path = CharacterCompactEyeGeometry.path(
          eye: eye, contour: contour, left: true, center: .init(x: 100, y: 100),
          width: 24, height: 36, treatment: .vertical, thickness: 4.5)
        let points = points(path)
        XCTAssertEqual(path.commands.count, 14)
        XCTAssertEqual(points.count, 37)
        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertGreaterThan(points.map(\.y).max()! - points.map(\.y).min()!, 4)
        if let previous {
          XCTAssertLessThan(
            zip(previous, points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max()!, 0.5)
        }
        previous = points
      }
    }
  }

  func testSimpleSadnessAndAngerUseAFrownNotARestSmile() throws {
    for emotion in [CharacterEmotion.sadness, .angerIrritation] {
      let result = try scene(emotion, direction: .catSimple2D)
      let lips = try XCTUnwrap(result.nodes.first { $0.id == "mouth.lip" })
      XCTAssertLessThan(points(lips.path).map(\.y).min()!, 401)
      XCTAssertGreaterThan(lips.opacity, 0.8)
    }
  }

  func testPawUsesOneImageAndExistingMotionWithoutFacialFeatures() throws {
    let direction = CharacterCatSupplementalAsset.pawPad.artDirection
    XCTAssertEqual(direction.requiredImageAssets, [.catPawPad])
    let receipt = ReactiveCharacter.act(
      state: .idle,
      event: .animationStarted(id: try .init(validating: "paw-test"), animation: .bounce))
    let frames = try [0.0, 0.12, 0.24, 0.4].map { time in
      try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(
          state: receipt.stateAfter, elapsed: time, motionProfile: .cartoon),
        artDirection: direction, width: 320, height: 320)
    }
    XCTAssertTrue(
      frames.allSatisfy { $0.nodes.count == 1 && $0.nodes[0].image?.asset == .catPawPad })
    XCTAssertNotEqual(frames[0], frames[2])
    let svg = try CharacterSVGRenderer.render(frames[2], title: "paw")
    XCTAssertTrue(svg.contains("data:image/png;base64,"))
    XCTAssertFalse(svg.contains("eye.left"))
    XCTAssertEqual(receipt.effects.count, 1)
  }

  func testPawReducedMotionIsStaticAndRejectsInvalidViewport() throws {
    let direction = CharacterCatSupplementalAsset.pawPad.artDirection
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(.joy)).stateAfter
    func frame(_ time: Double, width: Double = 320) throws -> CharacterScene {
      try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(state: state, elapsed: time, reduceMotion: true),
        artDirection: direction, width: width, height: 320)
    }
    XCTAssertEqual(try frame(0), try frame(100))
    XCTAssertThrowsError(try frame(0, width: .infinity))
    XCTAssertThrowsError(try frame(0, width: -1))
  }

  func testAllCompactEyeTreatmentsStaySeparatedAcrossGazesAndExpressions() throws {
    let directions: [CharacterArtDirection] = [.portrait, .catSimple2D]
    for direction in directions {
      for treatment in CharacterEyeTreatment.allCases {
        for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
          for x in [0.0, 0.5, 1.0] {
            for y in [0.0, 0.5, 1.0] {
              let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion))
                .stateAfter
              let focused = ReactiveCharacter.act(
                state: state,
                event: .attentionFocused(try .init(validatingX: x, y: y))
              ).stateAfter
              let scene = try CharacterSceneBuilder.scene(
                pose: ReactiveCharacter.pose(state: focused, elapsed: 0.52, reduceMotion: true),
                artDirection: direction.replacingFaceTreatment(eyes: treatment), width: 512,
                height: 560)
              let left = points(try XCTUnwrap(scene.nodes.first { $0.id == "eye.left" }).path)
              let right = points(try XCTUnwrap(scene.nodes.first { $0.id == "eye.right" }).path)
              // Independently bounded reference-face safe area, including enlarged heart eyes.
              XCTAssertLessThan(left.map(\.x).max()!, 246)
              XCTAssertGreaterThan(right.map(\.x).min()!, 266)
              XCTAssertGreaterThan(left.map(\.x).min()!, 123)
              XCTAssertLessThan(right.map(\.x).max()!, 389)
            }
          }
        }
      }
    }
  }

  private func points(_ path: CharacterVectorPath) -> [CharacterVectorPoint] {
    path.commands.flatMap { command -> [CharacterVectorPoint] in
      switch command {
      case .move(let p), .line(let p): [p]
      case .quad(let a, let b): [a, b]
      case .cubic(let a, let b, let c): [a, b, c]
      case .close: []
      }
    }
  }
}

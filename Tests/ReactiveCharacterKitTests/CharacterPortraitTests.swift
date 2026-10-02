import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterPortraitTests: XCTestCase {
  private func state(_ emotion: CharacterEmotion?) -> CharacterState {
    ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
  }

  private func scene(_ pose: CharacterPose, _ style: CharacterPortraitStyle = .standard) throws
    -> CharacterScene
  {
    try CharacterSceneBuilder.scene(
      pose: pose, artDirection: style.artDirection, width: 512, height: 560)
  }

  private func points(_ path: CharacterVectorPath) -> [CharacterVectorPoint] {
    path.commands.flatMap { command -> [CharacterVectorPoint] in
      switch command {
      case .move(let p), .line(let p): [p]
      case .quad(let c, let p): [c, p]
      case .cubic(let a, let b, let p): [a, b, p]
      case .close: []
      }
    }
  }

  func testCropUsesOneBoyArtworkOwnerAndNoRasterSubstitute() throws {
    let value = try scene(
      ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true), .shortHairBoy)
    XCTAssertEqual(value.nodes.first { $0.id == "portrait.hair.back" }?.path,
                   CharacterBoyArtwork.Front.hairBack)
    XCTAssertEqual(value.nodes.first { $0.id == "portrait.hair.fringe" }?.path,
                   CharacterBoyArtwork.Front.hairFringe)
    XCTAssertEqual(value.nodes.filter { $0.id.hasPrefix("portrait.hair.highlight.") }.count, 2)
    XCTAssertFalse(value.nodes.contains { $0.id.hasPrefix("portrait.hair.detail.") })
    XCTAssertFalse(value.nodes.contains { $0.image != nil })
  }

  func testPortraitAnatomyIsExplicitAndProcedural() throws {
    XCTAssertEqual(CharacterArtDirection.portrait.anatomy, .portrait(.standard))
    XCTAssertTrue(CharacterArtDirection.portrait.requiredImageAssets.isEmpty)
    XCTAssertFalse(CharacterArtDirection.portrait.components.contains(.nose))
    let value = try scene(ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true))
    XCTAssertFalse(value.nodes.contains { $0.image != nil || $0.id.hasPrefix("cat.") })
    XCTAssertFalse(try CharacterSVGRenderer.render(value).contains("<image"))
    XCTAssertEqual(value.nodes.filter { $0.id.hasPrefix("eyebrow.") }.count, 2)
  }

  func testAnatomyConfigurationHasOneAuthoritativeCase() {
    XCTAssertEqual(CharacterArtDirection.black.anatomy, .minimal)
    XCTAssertEqual(CharacterArtDirection.cat.anatomy, .cat(.animated))
    XCTAssertEqual(CharacterArtDirection.portrait.anatomy, .portrait(.standard))
  }

  func testConfigurationCopiesPreservePortraitChoices() throws {
    let style = CharacterPortraitStyle(
      hairstyle: .crop, eyewear: .loweredSunglasses, hairAccessory: .cross,
      hairColor: try CharacterColor(red: 0.15, green: 0.10, blue: 0.07))
    let original = style.artDirection
    let replacement = original.replacingMotionProfile(.expressive)
      .replacingFaceTreatment(eyes: .horizontal, mouth: .filled)
      .replacingPartColors(.init(surface: .featureDefault, eyes: .surfaceDefault))
    XCTAssertEqual(replacement.anatomy, .portrait(style))
    XCTAssertEqual(original.style.eyeTreatment, .vertical)
  }

  func testAllStylesAndExpressionsProduceFiniteScenesWithStablePartIdentity() throws {
    for hair in CharacterPortraitStyle.Hairstyle.allCases {
      for eyewear in CharacterPortraitStyle.Eyewear.allCases {
        for accessory in CharacterPortraitStyle.HairAccessory.allCases {
          let style = CharacterPortraitStyle(hairstyle: hair, eyewear: eyewear, hairAccessory: accessory)
          for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
            let pose = ReactiveCharacter.pose(
              state: state(emotion), elapsed: 0.52, reduceMotion: true, motionProfile: .cartoon)
            let value = try scene(pose, style)
            try CharacterSceneValidation.validate(value)
            let ids = value.nodes.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count)
            XCTAssertTrue(ids.contains("mouth"))
            XCTAssertTrue(ids.contains("portrait.hair.fringe"))
            XCTAssertEqual(ids.contains("portrait.hair.clip"), accessory == .bar || accessory == .cross)
            XCTAssertEqual(ids.contains("portrait.hair.flower.center"), accessory == .flower)
            XCTAssertEqual(ids.contains("portrait.hair.cap.crown"), accessory == .backwardCap)
            XCTAssertEqual(ids.contains("portrait.glasses.left"), eyewear != .none)
            XCTAssertEqual(value.nodes.filter { $0.id.hasPrefix("eyebrow.") }.count, 2)
            XCTAssertEqual(
              value.nodes.map(\.layer.rawValue), value.nodes.map(\.layer.rawValue).sorted())
          }
        }
      }
    }
  }

  func testBrowsShareExpressionOwnerAndAreNotBlinkOrVoiceChannels() throws {
    for emotion in CharacterEmotion.allCases {
      let expression = CharacterExpression.sample(
        emotion: emotion, elapsed: 0.52, reduceMotion: false, profile: .cartoon)
      let base = ReactiveCharacter.pose(
        state: state(emotion), elapsed: 0.52, motionProfile: .cartoon)
      XCTAssertEqual(base.brows, expression.brows)
      XCTAssertEqual(base.replacingSurface(.identity).brows, base.brows)
      for time in stride(from: 0.0, through: 6, by: 0.037) {
        let pose = ReactiveCharacter.pose(
          state: state(emotion), elapsed: time, motionProfile: .cartoon)
        XCTAssertEqual(pose.brows, base.brows)
      }
      let speaking = ReactiveCharacter.act(state: state(emotion), event: .voiceStarted).stateAfter
      let loud = ReactiveCharacter.act(state: speaking, event: .voiceLevelChanged(1)).stateAfter
      XCTAssertEqual(
        ReactiveCharacter.pose(state: loud, elapsed: 0.52, motionProfile: .cartoon).brows,
        base.brows)
    }
  }

  func testBrowsHaveDistinctDirectionsWithoutChangingMinimalOrCatOutput() throws {
    let angry = ReactiveCharacter.pose(
      state: state(.angerIrritation), elapsed: 0, reduceMotion: true)
    let sad = ReactiveCharacter.pose(state: state(.sadness), elapsed: 0, reduceMotion: true)
    XCTAssertGreaterThan(angry.brows.left.angle, 0)
    XCTAssertLessThan(angry.brows.right.angle, 0)
    XCTAssertLessThan(sad.brows.left.angle, 0)
    XCTAssertGreaterThan(sad.brows.right.angle, 0)
    for direction in [
      CharacterArtDirection.black, .white, .arcade, .cat, .catSimple2D, .catNorwegianForest,
    ] {
      let value = try CharacterSceneBuilder.scene(
        pose: angry, artDirection: direction, width: 160, height: 160)
      XCTAssertFalse(value.nodes.contains { $0.id.hasPrefix("eyebrow.") })
    }
  }

  func testReferenceEyesStaySeparatedAndBrowsStayAboveEyesForNineGazes() throws {
    for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
      for x in [0.0, 0.5, 1.0] {
        for y in [0.0, 0.5, 1.0] {
          let focused = ReactiveCharacter.act(
            state: state(emotion), event: .attentionFocused(try .init(validatingX: x, y: y))
          ).stateAfter
          let pose = ReactiveCharacter.pose(
            state: focused, elapsed: 0.52, reduceMotion: true, motionProfile: .cartoon)
          let value = try scene(pose)
          for left in [true, false] {
            let eye = try XCTUnwrap(
              value.nodes.first { $0.id == (left ? "eye.left" : "eye.right") })
            let brow = try XCTUnwrap(
              value.nodes.first { $0.id == (left ? "eyebrow.left" : "eyebrow.right") })
            let ep = points(eye.path)
            let bp = points(brow.path)
            // Renewal uses larger ovals and expressive hearts, not the previous 24-point eyes.
            // Keep a 20-point center gap even for rotated/horizontal expression silhouettes.
            XCTAssertLessThan(ep.map(\.x).max()! - ep.map(\.x).min()!, 88)
            XCTAssertTrue(ep.allSatisfy { left ? $0.x < 246 : $0.x > 266 })
            // Include the largest allowed brow rotation in the conservative separation bound.
            XCTAssertLessThan(bp.map(\.y).max()! + 12, ep.map(\.y).min()! - 4)
          }
        }
      }
    }
  }

  func testGazeMovesOnlyEyesNotBrowsOrRestMouth() throws {
    let base = state(nil)
    var referenceBrows: [String: CharacterSceneNode] = [:]
    var referenceMouth: CharacterSceneNode?

    for x in [0.0, 0.5, 1.0] {
      for y in [0.0, 0.5, 1.0] {
        let focused = ReactiveCharacter.act(
          state: base, event: .attentionFocused(try .init(validatingX: x, y: y))
        ).stateAfter
        let value = try scene(
          ReactiveCharacter.pose(
            state: focused, elapsed: 0.52, reduceMotion: true, motionProfile: .cartoon))
        for id in ["eyebrow.left", "eyebrow.right"] {
          let node = try XCTUnwrap(value.nodes.first { $0.id == id })
          if let existing = referenceBrows[id] {
            XCTAssertEqual(node, existing, "Gaze alone must not move portrait eyebrows")
          } else {
            referenceBrows[id] = node
          }
        }
        let mouth = try XCTUnwrap(value.nodes.first { $0.id == "mouth" })
        if let existing = referenceMouth {
          XCTAssertEqual(mouth, existing, "Gaze alone must not drag the portrait mouth")
        } else {
          referenceMouth = mouth
        }
      }
    }
  }

  func testNeutralPortraitUsesCompactClosedMouthWithContinuousTopology() throws {
    let value = try scene(
      ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, motionProfile: .cartoon))
    let mouth = try XCTUnwrap(value.nodes.first { $0.id == "mouth" })
    XCTAssertNil(mouth.fill)
    XCTAssertEqual(mouth.path.commands.count, 4)
    XCTAssertLessThan(points(mouth.path).map(\.x).max()! - points(mouth.path).map(\.x).min()!, 32)
    let open = try scene(
      ReactiveCharacter.pose(
        state: state(.surprise), elapsed: 0, reduceMotion: true, motionProfile: .cartoon))
    XCTAssertEqual(
      mouth.path.commands.count, open.nodes.first { $0.id == "mouth" }?.path.commands.count)
  }

  func testInterruptedBrowsHaveContinuousPositions() throws {
    var session = CharacterPresentationSession(state: state(.angerIrritation), at: 0)
    for (time, emotion) in [(0.6, CharacterEmotion.sadness), (0.64, .surprise), (0.70, .joy)] {
      let before = session.pose(at: time, motionProfile: .cartoon)
      session.update(
        state: state(emotion), at: time, motionProfile: .cartoon, transitionProfile: .cartoon)
      let after = session.pose(at: time, motionProfile: .cartoon)
      XCTAssertEqual(after.brows, before.brows)
      let next = session.pose(at: time + 0.0001, motionProfile: .cartoon)
      XCTAssertEqual(next.brows.left.angle, after.brows.left.angle, accuracy: 0.003)
      XCTAssertEqual(next.brows.left.lift, after.brows.left.lift, accuracy: 0.003)
      _ = try scene(next)
    }
  }

  func testReducedMotionIsStaticAndKeepsAllThirteenExpressions() throws {
    var signatures: [CharacterBrowPairPose] = []
    for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
      let first = ReactiveCharacter.pose(
        state: state(emotion), elapsed: 0, reduceMotion: true, motionProfile: .cartoon)
      let later = ReactiveCharacter.pose(
        state: state(emotion), elapsed: 100, reduceMotion: true, motionProfile: .cartoon)
      XCTAssertEqual(try scene(first), try scene(later))
      XCTAssertFalse(signatures.contains(first.brows))
      signatures.append(first.brows)
    }
    XCTAssertEqual(signatures.count, 13)
  }

  func testAccessoryAndFeatureComponentsAreHonored() throws {
    let style = CharacterPortraitStyle(eyewear: .sunglasses, hairAccessory: .cross)
    for components: CharacterComponents in [[], [.eyes], [.mouth], [.accessories], .default] {
      let direction = CharacterArtDirection.portrait(style, components: components)
      let value = try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
        artDirection: direction, width: 240, height: 240)
      XCTAssertEqual(value.nodes.contains { $0.id == "eyebrow.left" }, components.contains(.eyes))
      XCTAssertEqual(value.nodes.contains { $0.id == "mouth" }, components.contains(.mouth))
      XCTAssertEqual(
        value.nodes.contains { $0.id == "portrait.glasses.left" }, components.contains(.accessories)
      )
      XCTAssertEqual(
        value.nodes.contains { $0.id == "portrait.hair.clip" }, components.contains(.accessories))
    }
  }
}

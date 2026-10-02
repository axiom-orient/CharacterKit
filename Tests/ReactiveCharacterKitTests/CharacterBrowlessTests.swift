import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterBrowlessTests: XCTestCase {
  private func state(_ emotion: CharacterEmotion) -> CharacterState {
    ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
  }

  func testAccessorySelectionCannotResizeTheFace() throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    for size in [96.0, 160, 320] {
      let base = try CharacterArtDirection(name: "Unadorned")
      let original = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: base, width: size, height: size * 1.5)
      for accessory: CharacterAccessoryAsset in [.hood, .baseballCap, .bunnyEars, .arcadeHeadset] {
        let direction = try CharacterArtDirection(name: "Adorned", assets: .init(accessories: [accessory]))
        let adorned = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction, width: size, height: size * 1.5)
        XCTAssertEqual(adorned.faceBounds, original.faceBounds)
        for id in ["eye.left", "eye.right"] {
          XCTAssertEqual(adorned.nodes.first { $0.id == id }, original.nodes.first { $0.id == id })
        }
      }
    }
  }

  func testAllEmotionsUseOnePrimaryEyeNodeWithoutEyebrowNodes() throws {
    for emotion in CharacterEmotion.allCases {
      let pose = ReactiveCharacter.pose(
        state: state(emotion), elapsed: 0.52, reduceMotion: true, motionProfile: .cartoon)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: .black, width: 320, height: 320)
      XCTAssertFalse(scene.nodes.contains { $0.id.lowercased().contains("brow") })
      for eyeID in ["eye.left", "eye.right"] {
        let node = try XCTUnwrap(scene.nodes.first { $0.id == eyeID })
        XCTAssertEqual(node.path.commands.count, 14, "one move, twelve cubics, close")
        XCTAssertNotNil(
          node.fill, "\(emotion): all silhouettes stay filled, including smile ribbons")
        XCTAssertNil(node.stroke, "the ribbon itself owns uniform thickness")
      }
    }
  }
  func testContoursStayFiniteAndNormalizedForEveryEmotionProfileAndClock() throws {
    let strongest = try CharacterMotionProfile(
      expressiveness: 1.5, trailStrength: 1.5, accentStrength: 1.5, idleStrength: 1.5)
    for profile in [CharacterMotionProfile.expressive, .cartoon, strongest] {
      for emotion in CharacterEmotion.allCases {
        for reduced in [false, true] {
          for t in [0.0, 0.08, 0.22, 0.52, 3, 86400, 1e20] {
            let pose = ReactiveCharacter.pose(
              state: state(emotion), elapsed: t, reduceMotion: reduced, motionProfile: profile)
            for eye in [pose.eyeContours.left, pose.eyeContours.right] {
              for value in [eye.lidCompression, eye.innerPinch, eye.crescent] {
                XCTAssertTrue(value.isFinite && (0...1).contains(value), "\(emotion) \(t)")
              }
            }
          }
        }
      }
    }
  }

  func testPrimarySignaturesDoNotDependOnAccentOrSpeechGlyph() {
    func contour(_ emotion: CharacterEmotion) -> CharacterEyeContourPair {
      ReactiveCharacter.pose(
        state: state(emotion), elapsed: 0.52,
        reduceMotion: true, motionProfile: .cartoon
      ).eyeContours
    }
    XCTAssertEqual(contour(.joy).left.crescent, 1)
    XCTAssertEqual(contour(.joy).left, contour(.joy).right)
    XCTAssertEqual(contour(.affection).left.heart, 1)
    XCTAssertEqual(contour(.affection).left, contour(.affection).right)
    XCTAssertGreaterThan(contour(.angerIrritation).left.innerPinch, 0.9)
    XCTAssertNotEqual(contour(.disgustContempt).left, contour(.disgustContempt).right)
    XCTAssertNotEqual(contour(.gratitude), contour(.calmTrust))
    XCTAssertGreaterThan(contour(.gratitude).left.crescent, contour(.calmTrust).left.crescent)
    XCTAssertNotEqual(contour(.anxietyFear), contour(.surprise))
    XCTAssertNotEqual(contour(.calmTrust), contour(.angerIrritation))
    XCTAssertNotEqual(contour(.calmTrust), contour(.disgustContempt))
    for emotion in CharacterEmotion.allCases {
      let talking = ReactiveCharacter.reduce(state: state(emotion), event: .chatStarted).state
      let pose = ReactiveCharacter.pose(
        state: talking, elapsed: 2, reduceMotion: true,
        motionProfile: .cartoon)
      XCTAssertEqual(pose.eyeContours, contour(emotion))
      XCTAssertEqual(pose.replacingSurface(.init(angle: 0.4)).eyeContours, pose.eyeContours)
    }
  }

  func testReduceMotionAndAllAccessoryEmotionSizeCombinations() throws {
    let base = CharacterArtDirection.black
    for accessory in [
      CharacterAccessoryAsset?.none, .arcadeHeadset, .hood, .baseballCap, .bunnyEars,
    ] {
      let direction = try CharacterArtDirection(
        name: base.name, components: base.components, layout: base.layout, style: base.style,
        surface: base.surface, projection: base.projection, motionProfile: base.motionProfile,
        transitionProfile: base.transitionProfile,
        assets: .init(
          background: base.assets.background, face: base.assets.face,
          accessories: accessory.map { [$0] } ?? []),
        featureGlow: base.featureGlow, ornamentGlow: base.ornamentGlow,
        contentInset: base.contentInset)
      for emotion in CharacterEmotion.allCases {
        let a = ReactiveCharacter.pose(
          state: state(emotion), elapsed: 0,
          reduceMotion: true, motionProfile: .cartoon)
        let b = ReactiveCharacter.pose(
          state: state(emotion), elapsed: 100,
          reduceMotion: true, motionProfile: .cartoon)
        XCTAssertEqual(a, b)
        for size in [96.0, 160, 320] {
          let first = try CharacterSceneBuilder.scene(
            pose: a, artDirection: direction,
            width: size, height: size)
          let second = try CharacterSceneBuilder.scene(
            pose: b, artDirection: direction,
            width: size, height: size)
          XCTAssertEqual(first, second)
          XCTAssertFalse(first.nodes.contains { $0.id.lowercased().contains("brow") })
        }
      }
    }
  }

  func testContourHandoffAndInterruptionRemainContinuous() {
    var session = CharacterPresentationSession(state: state(.joy), at: 0)
    let source = session.pose(at: 1, motionProfile: .cartoon).eyeContours
    XCTAssertTrue(
      session.update(
        state: state(.angerIrritation), at: 1,
        motionProfile: .cartoon, transitionProfile: .cartoon))
    XCTAssertEqual(session.pose(at: 1, motionProfile: .cartoon).eyeContours, source)
    var previous = source
    for step in 1...900 {
      let current = session.pose(
        at: 1 + Double(step) / 1000,
        motionProfile: .cartoon
      ).eyeContours
      for pair in [(previous.left, current.left), (previous.right, current.right)] {
        XCTAssertLessThan(abs(pair.0.crescent - pair.1.crescent), 0.08)
        XCTAssertLessThan(abs(pair.0.innerPinch - pair.1.innerPinch), 0.08)
        XCTAssertLessThan(abs(pair.0.lidCompression - pair.1.lidCompression), 0.08)
      }
      previous = current
    }
    let before = session.pose(at: 1.3, motionProfile: .cartoon).eyeContours
    _ = session.update(
      state: state(.disgustContempt), at: 1.3,
      motionProfile: .cartoon, transitionProfile: .cartoon)
    XCTAssertEqual(session.pose(at: 1.3, motionProfile: .cartoon).eyeContours, before)
    let historic = session.pose(at: 1.31, motionProfile: .cartoon)
    _ = session.pose(at: 100, motionProfile: .cartoon)
    XCTAssertEqual(session.pose(at: 1.31, motionProfile: .cartoon), historic)
  }

  func testDeterministicVariationBoundsAndLargeClocks() {
    let bank = CharacterPresentationVariation.self
    var first: [Int] = []
    var second: [Int] = []
    for index in 0..<64 {
      let t = Double(index) * 10
      let a = bank.index(elapsed: t, interval: 10, count: 6, seed: bank.idleSeed)
      XCTAssertEqual(a, bank.index(elapsed: t, interval: 10, count: 6, seed: bank.idleSeed))
      first.append(a)
      second.append(bank.index(elapsed: t, interval: 10, count: 6, seed: bank.idleSeed + 1))
    }
    XCTAssertGreaterThan(Set(first).count, 1)
    XCTAssertNotEqual(first, second)
    for t in [1e20, Double.greatestFiniteMagnitude] {
      let value = bank.index(elapsed: t, interval: 0.36, count: 8, seed: bank.speechSeed)
      XCTAssertTrue((0..<8).contains(value))
      XCTAssertTrue(bank.speechOpenness(elapsed: t).isFinite)
    }
    for index in 1...32 {
      let boundary = Double(index) * bank.syllableDuration
      XCTAssertEqual(
        bank.speechOpenness(elapsed: boundary - 1e-7),
        bank.speechOpenness(elapsed: boundary + 1e-7), accuracy: 1e-5)
    }
    for emotion in CharacterEmotion.allCases {
      let s = ReactiveCharacter.reduce(state: state(emotion), event: .chatStarted).state
      let pose = ReactiveCharacter.pose(state: s, elapsed: 1e20, motionProfile: .cartoon)
      XCTAssertTrue(pose.eyes.left.centerX.isFinite)
      XCTAssertTrue(pose.mouth.openness.isFinite)
    }
  }

  func testReducedSamplingImmediatelySuppressesExistingBridgeWithoutMutation() {
    var session = CharacterPresentationSession(state: state(.joy), at: 0)
    _ = session.update(state: state(.angerIrritation), at: 1)
    let snapshot = session
    let expected = ReactiveCharacter.pose(
      state: state(.angerIrritation), elapsed: 0,
      reduceMotion: true)
    XCTAssertEqual(session.pose(at: 1.01, reduceMotion: true), expected)
    XCTAssertEqual(session.pose(at: 1.15, reduceMotion: true), expected)
    XCTAssertEqual(session, snapshot, "Sampling cannot reconcile or mutate the caller's session")
  }

  func testEntryOnlyReactionsStopHighFrequencySurfaceMotion() {
    for emotion: CharacterEmotion in [.anxietyFear, .angerIrritation, .disgustContempt, .surprise] {
      let entry = CharacterExpression.sample(
        emotion: emotion, elapsed: 0.16,
        reduceMotion: false, profile: .cartoon)
      XCTAssertNotEqual(entry.surface, .identity)
      for time in [0.8, 2.4, 7.3, 50.0] {
        let settled = CharacterExpression.sample(
          emotion: emotion, elapsed: time,
          reduceMotion: false, profile: .cartoon)
        XCTAssertEqual(settled.surface, .identity, "\(emotion) should not repeat entry recoil")
      }
    }
  }

}

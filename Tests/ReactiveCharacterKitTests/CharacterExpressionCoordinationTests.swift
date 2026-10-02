import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterExpressionCoordinationTests: XCTestCase {
  private func state(_ emotion: CharacterEmotion) -> CharacterState {
    ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
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

  private func mouthNode(_ pose: CharacterPose) -> CharacterSceneNode? {
    guard
      let scene = try? CharacterSceneBuilder.scene(
        pose: pose, artDirection: .black, width: 320, height: 320)
    else { return nil }
    return scene.nodes.first {
      $0.id == "mouth"
    }
  }

  func testSilentMouthArticulationHasSameExpressionAuthorityAsEyes() {
    for emotion in CharacterEmotion.allCases {
      for time in [0.0, 0.08, 0.16, 0.3, 0.52, 0.9, 1.2, 2.5, 5.0] {
        let expression = CharacterExpression.sample(
          emotion: emotion, elapsed: time, reduceMotion: false, profile: .cartoon)
        let pose = ReactiveCharacter.pose(
          state: state(emotion), elapsed: time, motionProfile: .cartoon)
        XCTAssertEqual(
          pose.mouth.openness, min(1, max(0, expression.mouthOpenness)),
          accuracy: 1e-12, "\(emotion) at \(time): atlas cycle must not close the face")
        XCTAssertTrue(pose.mouth.skew.isFinite)
        XCTAssertTrue(abs(pose.mouth.skew) <= 1)
        XCTAssertEqual(pose.eyeContours, expression.eyeContours)
      }
    }
  }

  func testSpeechArticulationPreservesExpressionAndRespectsItsOpenFloor() throws {
    for emotion in CharacterEmotion.allCases {
      var speaking = ReactiveCharacter.reduce(state: state(emotion), event: .voiceStarted).state
      let quiet = ReactiveCharacter.pose(state: speaking, elapsed: 0.52, motionProfile: .cartoon)
      speaking = ReactiveCharacter.reduce(state: speaking, event: .voiceLevelChanged(1)).state
      let loud = ReactiveCharacter.pose(state: speaking, elapsed: 0.52, motionProfile: .cartoon)
      XCTAssertEqual(quiet.eyeContours, loud.eyeContours)
      XCTAssertEqual(quiet.mouth.curvature, loud.mouth.curvature)
      XCTAssertTrue(quiet.mouth.skew.isFinite)
      XCTAssertTrue(loud.mouth.skew.isFinite)
      // A fully open surprise already exceeds the speech envelope; do not flatten it.
      XCTAssertEqual(loud.mouth.openness, max(quiet.mouth.openness, 0.88), accuracy: 1e-12)
      if quiet.mouth.openness < 0.88 {
        XCTAssertNotEqual(
          try XCTUnwrap(mouthNode(quiet)).path,
          try XCTUnwrap(mouthNode(loud)).path, "\(emotion)")
      } else {
        XCTAssertEqual(
          try XCTUnwrap(mouthNode(quiet)).path,
          try XCTUnwrap(mouthNode(loud)).path)
      }
    }
  }

  func testMouthFollowsEyeGazeWithoutDuplicatingGazeIntoArticulation() throws {
    let left = try CharacterPoint(validatingX: 0.05, y: 0.50)
    let right = try CharacterPoint(validatingX: 0.95, y: 0.50)

    func focused(_ emotion: CharacterEmotion, _ point: CharacterPoint) -> CharacterState {
      var result = state(emotion)
      result =
        ReactiveCharacter.reduce(
          state: result, event: .attentionFocused(point)
        ).state
      return result
    }

    for emotion in CharacterEmotion.allCases {
      let leftPose = ReactiveCharacter.pose(
        state: focused(emotion, left), elapsed: 0.52, reduceMotion: true)
      let rightPose = ReactiveCharacter.pose(
        state: focused(emotion, right), elapsed: 0.52, reduceMotion: true)
      XCTAssertGreaterThan(
        rightPose.face.mouth.offsetX, leftPose.face.mouth.offsetX, "\(emotion)")
      XCTAssertEqual(leftPose.mouth.width, rightPose.mouth.width, accuracy: 1e-12, "\(emotion)")
      XCTAssertEqual(leftPose.mouth.skew, rightPose.mouth.skew, accuracy: 1e-12, "\(emotion)")
    }

    let joyRight = ReactiveCharacter.pose(
      state: focused(.joy, right), elapsed: 0.52, reduceMotion: true)

    let flat = ReactiveCharacter.pose(
      state: focused(.joy, right), elapsed: 0.52, reduceMotion: true, projection: .flat)
    XCTAssertLessThanOrEqual(joyRight.face.mouth.scaleX, flat.face.mouth.scaleX)
    XCTAssertEqual(joyRight.mouth.width, flat.mouth.width, accuracy: 1e-12)
    XCTAssertGreaterThan(joyRight.eyes.left.width, 0)
    XCTAssertGreaterThan(joyRight.eyes.right.width, 0)
  }

  func testFullEntryBeginsWithNeutralEyesMouthAndSurface() {
    let epsilon = 0.000_001
    for emotion in CharacterEmotion.allCases {
      var session = CharacterPresentationSession(state: state(.joy))
      session.update(
        state: state(emotion), at: 1, motionProfile: .cartoon,
        transitionProfile: .cartoon)
      guard session.inspect(at: 1).remainingHandoffDuration > 0 else { continue }
      let entry = 1 + session.inspect(at: 1).remainingHandoffDuration
      let before = session.pose(at: entry - epsilon, motionProfile: .cartoon)
      let after = session.pose(at: entry + epsilon, motionProfile: .cartoon)
      XCTAssertEqual(before.eyes.left.width, after.eyes.left.width, accuracy: 1e-7, "\(emotion)")
      XCTAssertEqual(before.eyes.right.height, after.eyes.right.height, accuracy: 1e-7)
      XCTAssertEqual(before.eyes.left.centerX, after.eyes.left.centerX, accuracy: 1e-7)
      XCTAssertEqual(before.surface.scaleY, after.surface.scaleY, accuracy: 1e-7)
      XCTAssertEqual(before.surface.offsetY, after.surface.offsetY, accuracy: 1e-7)
      XCTAssertEqual(before.mouth.width, after.mouth.width, accuracy: 1e-7)
      let middle = session.pose(at: entry + 0.085, motionProfile: .cartoon)
      session.update(
        state: state(.surprise), at: entry + 0.085, motionProfile: .cartoon,
        transitionProfile: .cartoon)
      XCTAssertEqual(
        session.pose(at: entry + 0.085, motionProfile: .cartoon), middle,
        "Interrupted entry starts from the actually displayed whole face")
    }
  }

  func testMouthUsesOneContinuousTopologyAcrossEveryHandoff() throws {
    for emotion in CharacterEmotion.allCases {
      var session = CharacterPresentationSession(state: state(.joy))
      session.update(
        state: state(emotion), at: 1, motionProfile: .cartoon,
        transitionProfile: .cartoon)
      var previous: [CharacterVectorPoint]?
      for step in 0...800 {
        let pose = session.pose(at: 1 + Double(step) / 1000, motionProfile: .cartoon)
        guard let node = mouthNode(pose) else {
          // The revised contract keeps neutral silence visually empty. Start continuity checks
          // when the requested mouth is actually created during the handoff.
          previous = nil
          continue
        }
        XCTAssertEqual(node.path.commands.count, 14, "same move/twelve cubics/close")
        let current = points(node.path)
        XCTAssertEqual(current.count, 37)
        if let previous {
          for (a, b) in zip(previous, current) {
            XCTAssertLessThan(
              hypot(a.x - b.x, a.y - b.y), 1.25,
              "\(emotion) step \(step): no threshold-selected mouth jump")
          }
        }
        previous = current
      }
    }
  }

  func testNeutralAnchorsAreLevelAndMouthStaysHidden() throws {
    let pose = ReactiveCharacter.pose(
      state: .idle, elapsed: 0, reduceMotion: true,
      motionProfile: .cartoon)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: .black,
      width: 320, height: 320)
    func extent(_ id: String) throws -> (Double, Double, Double, Double) {
      let p = points(try XCTUnwrap(scene.nodes.first { $0.id == id }).path)
      return (
        try XCTUnwrap(p.map(\.x).min()), try XCTUnwrap(p.map(\.y).min()),
        try XCTUnwrap(p.map(\.x).max()), try XCTUnwrap(p.map(\.y).max())
      )
    }
    let l = try extent("eye.left")
    let r = try extent("eye.right")
    XCTAssertEqual(l.1, r.1, accuracy: 1e-8)
    XCTAssertEqual(l.3, r.3, accuracy: 1e-8)
    XCTAssertEqual(l.2 - l.0, r.2 - r.0, accuracy: 1e-8)
    XCTAssertFalse(scene.nodes.contains { $0.id.hasPrefix("mouth") })
  }
}

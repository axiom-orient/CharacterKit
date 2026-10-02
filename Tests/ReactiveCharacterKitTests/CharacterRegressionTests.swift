import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterRegressionTests: XCTestCase {
  private func state(_ events: [CharacterEvent]) -> CharacterState {
    events.reduce(ReactiveCharacter.initialState) {
      ReactiveCharacter.reduce(state: $0, event: $1).state
    }
  }

  func testExplicitAttentionSurvivesEmotionAndCommunicationOwnership() throws {
    let left = try CharacterPoint(validatingX: 0.05, y: 0.5)
    let right = try CharacterPoint(validatingX: 0.95, y: 0.5)
    for emotion in CharacterEmotion.allCases {
      for communication: CharacterEvent in [.chatStarted, .voiceStarted] {
        let events: [CharacterEvent] = [.emotionChanged(emotion), communication]
        let a = ReactiveCharacter.pose(
          state: state(events + [.attentionFocused(left)]), elapsed: 0.52)
        let b = ReactiveCharacter.pose(
          state: state(events + [.attentionFocused(right)]), elapsed: 0.52)
        XCTAssertGreaterThan(
          b.eyes.left.centerX - a.eyes.left.centerX, 0.25, "\(emotion), \(communication)")
      }
    }
  }

  func testExplicitAttentionSurvivesOneShotAndHistoricalTrails() throws {
    let id = try CharacterAnimationID(validating: "gaze-regression")
    let left = try CharacterPoint(validatingX: 0.05, y: 0.5)
    let right = try CharacterPoint(validatingX: 0.95, y: 0.5)
    let events: [CharacterEvent] = [
      .emotionChanged(.joy), .animationStarted(id: id, animation: .celebrate),
    ]
    let a = ReactiveCharacter.pose(state: state(events + [.attentionFocused(left)]), elapsed: 0.22)
    let b = ReactiveCharacter.pose(state: state(events + [.attentionFocused(right)]), elapsed: 0.22)
    XCTAssertGreaterThan(b.eyes.left.centerX - a.eyes.left.centerX, 0.25)
    let trailA = try XCTUnwrap(a.nearTrail)
    let trailB = try XCTUnwrap(b.nearTrail)
    XCTAssertGreaterThan(trailB.left.centerX - trailA.left.centerX, 0.25)
  }

  func testWritingFocusSurvivesOtherVisualOwners() throws {
    let left = try CharacterPoint(validatingX: 0.05, y: 0.8)
    let right = try CharacterPoint(validatingX: 0.95, y: 0.8)
    let tail: [CharacterEvent] = [.emotionChanged(.joy), .chatStarted]
    let a = ReactiveCharacter.pose(
      state: state([.userWritingBegan(focus: left)] + tail), elapsed: 0.52)
    let b = ReactiveCharacter.pose(
      state: state([.userWritingBegan(focus: right)] + tail), elapsed: 0.52)
    XCTAssertGreaterThan(b.eyes.left.centerX - a.eyes.left.centerX, 0.15)
  }

  func testMaximumMotionProfileNeverProducesNegativeEyeDimensions() throws {
    let profile = try CharacterMotionProfile(
      expressiveness: 1.5, trailStrength: 1.5, accentStrength: 1.5, idleStrength: 1.5)
    var failures: [String] = []
    for emotion in CharacterEmotion.allCases {
      let s = state([.emotionChanged(emotion)])
      for i in 0..<180 {
        let pose = ReactiveCharacter.pose(state: s, elapsed: Double(i) / 30, motionProfile: profile)
        if [
          pose.eyes.left.width, pose.eyes.left.height, pose.eyes.right.width,
          pose.eyes.right.height,
        ].contains(where: { !$0.isFinite || $0 <= 0 }) {
          failures.append("\(emotion) t=\(Double(i) / 30)")
        }
      }
    }
    XCTAssertTrue(failures.isEmpty, failures.prefix(6).joined(separator: "; "))
  }

  func testMaximumAccentStrengthIsAnOpacityNotUnboundedGain() throws {
    let profile = try CharacterMotionProfile(
      expressiveness: 1.5, trailStrength: 1.5, accentStrength: 1.5, idleStrength: 1.5)
    let id = try CharacterAnimationID(validating: "opacity-regression")
    var failures: [String] = []
    for animation in CharacterAnimation.allCases {
      let s = state([.animationStarted(id: id, animation: animation)])
      for i in 0..<100 {
        let pose = ReactiveCharacter.pose(
          state: s, elapsed: Double(i) * animation.duration / 100, motionProfile: profile)
        if pose.accents.contains(where: { !$0.opacity.isFinite || !(0...1).contains($0.opacity) }) {
          failures.append("\(animation) sample=\(i)")
        }
      }
    }
    XCTAssertTrue(failures.isEmpty, failures.prefix(6).joined(separator: "; "))
  }
}

extension CharacterRegressionTests {
  func testLargeFiniteWritingElapsedDoesNotConvertCycleToInt() throws {
    let task = try CharacterTaskID(validating: "long-time")
    let s = state([.agentStarted(taskID: task), .agentProgress(taskID: task, progress: 0.5)])
    for time in [86_400.0, 1e15, 1e20] {
      let pose = ReactiveCharacter.pose(state: s, elapsed: time)
      XCTAssertTrue(pose.eyes.left.centerX.isFinite)
      XCTAssertTrue(pose.eyes.right.height.isFinite)
      XCTAssertEqual(pose.writingProgress, 0.5)
    }
  }

  func testCompletedBridgeCanStillBeSampledHistorically() {
    var session = CharacterPresentationSession(state: ReactiveCharacter.initialState, at: 0)
    _ = session.update(state: state([.emotionChanged(.joy)]), at: 1)
    let during = session.pose(at: 1.02)
    _ = session.pose(at: 100)
    XCTAssertEqual(session.pose(at: 1.02), during)
    XCTAssertEqual(session.inspect(at: 100).remainingHandoffDuration, 0)
  }
}

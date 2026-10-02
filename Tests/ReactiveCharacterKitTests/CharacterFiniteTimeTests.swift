import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterFiniteTimeTests: XCTestCase {
  private let task = CharacterTaskID(UUID())
  private let extremeTimes = [Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude.nextDown, 1e308]

  private func state(_ events: [CharacterEvent]) -> CharacterState {
    events.reduce(.idle) { ReactiveCharacter.reduce(state: $0, event: $1).state }
  }

  func testEveryActivityProducesFinitePoseAndSceneAtExtremeFiniteTimes() throws {
    let failure = try CharacterFailure(operation: "finite-time", cause: "expected")
    let started = CharacterEvent.agentStarted(taskID: task)
    let states = [
      CharacterState.idle,
      state([.userWritingBegan(focus: .center)]),
      state([started]),
      state([started, .agentProgress(taskID: task, progress: 0.4)]),
      state([started, .agentCancellationRequested(taskID: task)]),
      state([started, .agentSucceeded(taskID: task)]),
      state([started, .agentFailed(taskID: task, failure: failure)]),
      state([started, .agentCancelled(taskID: task)]),
    ]
    for state in states {
      for time in extremeTimes {
        for reduced in [false, true] {
          try assertFiniteFrame(state: state, time: time, reduced: reduced, profile: .expressive)
        }
      }
    }
  }

  func testEveryEmotionPolicyProducesFinitePoseAndSceneAtExtremeFiniteTimes() throws {
    for emotion in CharacterEmotion.allCases {
      let state = state([.emotionChanged(emotion)])
      for mode in CharacterEmotionMotion.allCases {
        for time in extremeTimes {
          for reduced in [false, true] {
            try assertFiniteFrame(state: state, time: time, reduced: reduced, profile: .focusedEmotion(mode))
          }
        }
      }
    }
  }

  func testCommunicationAndExpiredAnimationsRemainFiniteAtExtremeTimes() throws {
    let communications: [CharacterEvent] = [.chatStarted, .listeningStarted, .voiceStarted]
    let animations = CharacterAnimation.allCases.map {
      CharacterEvent.animationStarted(id: CharacterAnimationID(UUID()), animation: $0)
    }
    for event in communications + animations {
      let state = state([.emotionChanged(.joy), event])
      for time in extremeTimes {
        try assertFiniteFrame(state: state, time: time, reduced: false, profile: .expressive)
      }
    }
  }

  func testNormalWritingAndThinkingKeepTheirExistingPeriodicArithmetic() {
    let thinking = state([.agentStarted(taskID: task)])
    let writing = state([.agentStarted(taskID: task), .agentProgress(taskID: task, progress: 0.4)])
    for time in [0.0, 0.18, 0.7, 1.4, 10, 60, 86_400, 1e20] {
      let pose = ReactiveCharacter.pose(state: writing, elapsed: time)
      let stroke = sin(time * 2 * Double.pi / 0.98)
      XCTAssertEqual(pose.writingPhase, 0.4)
      XCTAssertEqual(pose.writingMotionPhase, (time * 1.65).truncatingRemainder(dividingBy: 1))
      XCTAssertEqual(pose.surface.offsetX, stroke * 0.003)
      XCTAssertEqual(pose.surface.offsetY, -abs(stroke) * 0.004)
      XCTAssertEqual(pose.surface.angle, stroke * 0.006)
      let thought = ReactiveCharacter.pose(state: thinking, elapsed: time)
      let hover = sin(time * 2.15)
      XCTAssertEqual(thought.surface.offsetY, -0.008 + hover * 0.010)
      XCTAssertEqual(thought.surface.angle, sin(time * 1.07 + 0.8) * 0.018)
    }
  }

  private func assertFiniteFrame(
    state: CharacterState, time: Double, reduced: Bool, profile: CharacterMotionProfile,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let pose = ReactiveCharacter.pose(state: state, elapsed: time, reduceMotion: reduced, motionProfile: profile)
    let surface = pose.surface
    let values = [
      surface.offsetX, surface.offsetY, surface.scaleX, surface.scaleY, surface.angle,
      pose.writingPhase, pose.writingMotionPhase, pose.writingOpacity, pose.motionEnergy,
      pose.eyes.left.centerX, pose.eyes.left.centerY, pose.eyes.left.width, pose.eyes.left.height, pose.eyes.left.angle,
      pose.eyes.right.centerX, pose.eyes.right.centerY, pose.eyes.right.width, pose.eyes.right.height, pose.eyes.right.angle,
      pose.mouth.opacity, pose.mouth.curvature, pose.mouth.openness, pose.mouth.width, pose.mouth.skew,
    ]
    let context = "\(state.activity), \(state.emotion as Any), \(profile.emotionMotion), \(time), reduced=\(reduced)"
    XCTAssertTrue(values.allSatisfy(\.isFinite), context, file: file, line: line)
    let direction = try CharacterArtDirection(name: "Finite time", components: .all, motionProfile: profile)
    XCTAssertNoThrow(
      try CharacterSceneBuilder.scene(pose: pose, artDirection: direction, width: 240, height: 240),
      context, file: file, line: line)
  }
}

import XCTest
@testable import ReactiveCharacterKit

final class CharacterPresentationTests: XCTestCase {
  func testPoseSamplingIsDeterministicAndFinite() {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.interest)).state
    let a = ReactiveCharacter.pose(state: state, elapsed: 1.25)
    let b = ReactiveCharacter.pose(state: state, elapsed: 1.25)
    XCTAssertEqual(a, b)
    assertFinite(a)
  }

  func testReduceMotionProducesStableStatePose() {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let a = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
    let b = ReactiveCharacter.pose(state: state, elapsed: 100, reduceMotion: true)
    XCTAssertEqual(a, b)
  }

  func testListeningDoesNotOpenMouth() {
    var state = ReactiveCharacter.reduce(state: .idle, event: .listeningStarted).state
    state = ReactiveCharacter.reduce(state: state, event: .listeningLevelChanged(1)).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.5)
    XCTAssertLessThanOrEqual(pose.mouth.openness, 0.000_001)
  }

  func testVoiceLevelRetargetIsContinuous() {
    var state = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state
    var session = CharacterPresentationSession(state: state, at: 0)
    let before = session.pose(at: 0.4)

    state = ReactiveCharacter.reduce(state: state, event: .voiceLevelChanged(1)).state
    _ = session.update(state: state, at: 0.4)
    let atUpdate = session.pose(at: 0.4)
    XCTAssertEqual(atUpdate.mouth.openness, before.mouth.openness, accuracy: 0.000_001)
    let after = session.pose(at: 0.55)
    XCTAssertGreaterThanOrEqual(after.mouth.openness, atUpdate.mouth.openness)
  }

  func testInterruptedSemanticChangeStartsFromVisiblePose() {
    var state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    var session = CharacterPresentationSession(state: state, at: 0)
    let visible = session.pose(at: 0.6)

    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.sadness)).state
    XCTAssertTrue(session.update(state: state, at: 0.6))
    let handoffStart = session.pose(at: 0.6)
    XCTAssertEqual(handoffStart, visible)
  }

  func testFiniteExtremeSamplingDoesNotProduceNaN() {
    for time in [0.0, 1.0, 10_000.0, 1.0e20] {
      assertFinite(ReactiveCharacter.pose(state: .idle, elapsed: time))
    }
  }

  private func assertFinite(_ pose: CharacterPose, file: StaticString = #filePath, line: UInt = #line) {
    let values = [
      pose.eyes.left.centerX, pose.eyes.left.centerY, pose.eyes.left.width, pose.eyes.left.height,
      pose.eyes.right.centerX, pose.eyes.right.centerY, pose.eyes.right.width, pose.eyes.right.height,
      pose.noseOffsetX, pose.mouth.opacity, pose.mouth.curvature, pose.mouth.openness, pose.mouth.width,
      pose.surface.offsetX, pose.surface.offsetY, pose.surface.scaleX, pose.surface.scaleY,
      pose.surface.angle, pose.writingPhase, pose.writingMotionPhase, pose.writingOpacity,
      pose.motionEnergy,
    ]
    XCTAssertTrue(values.allSatisfy(\.isFinite), file: file, line: line)
  }
}

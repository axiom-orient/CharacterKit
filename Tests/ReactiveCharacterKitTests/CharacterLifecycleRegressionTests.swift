import XCTest
import ReactiveCharacterKit

final class CharacterLifecycleRegressionTests: XCTestCase {
  func testExpiredAnimationMatchesCompletedSceneBeforeHostCleanup() throws {
    let task = try CharacterTaskID(validating: "expiry-work")
    let joy = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let thinking = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: task)).state
    let speaking = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state

    for base in [CharacterState.idle, joy, thinking, speaking] {
      for animation in CharacterAnimation.allCases {
        let id = try CharacterAnimationID(validating: "expiry-\(animation.rawValue)")
        let active = ReactiveCharacter.reduce(
          state: base, event: .animationStarted(id: id, animation: animation)
        ).state
        let completed = ReactiveCharacter.reduce(state: active, event: .animationEnded(id: id)).state
        // Independent layers deliberately have different clocks. A late host timer must
        // not leave secondary character parts running on an already expired one-shot.
        let expiredPose = ReactiveCharacter.pose(
          state: active, elapsed: 2.7, expressionElapsed: 1.3, communicationElapsed: 4.1,
          animationElapsed: animation.duration + 0.2
        )
        let completedPose = ReactiveCharacter.pose(
          state: completed, elapsed: 2.7, expressionElapsed: 1.3, communicationElapsed: 4.1,
          animationElapsed: 0
        )
        let expired = try scene(expiredPose)
        let expected = try scene(completedPose)
        XCTAssertTrue(
          expired == expected,
          "Expired \(animation.rawValue) changed the \(base.visualChannel) scene before host cleanup"
        )
      }
    }
  }

  func testLateAnimationCleanupDoesNotMoveRenderedParts() throws {
    let id = try CharacterAnimationID(validating: "late-bounce")
    let joy = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    var presentation = CharacterPresentationSession(state: joy, at: 0)
    let active = ReactiveCharacter.reduce(
      state: joy, event: .animationStarted(id: id, animation: .bounce)
    ).state
    XCTAssertTrue(presentation.update(state: active, at: 2))
    let cleanupTime = 2 + presentation.inspect(at: 2).remainingHandoffDuration
      + CharacterAnimation.bounce.duration + 0.05
    let before = try scene(presentation.pose(at: cleanupTime))

    let completed = ReactiveCharacter.reduce(state: active, event: .animationEnded(id: id)).state
    XCTAssertFalse(presentation.update(state: completed, at: cleanupTime))
    XCTAssertEqual(presentation.inspect(at: cleanupTime).phase, .performing)
    let after = try scene(presentation.pose(at: cleanupTime))
    XCTAssertTrue(before == after, "Late cleanup changed an already completed visual performance")
  }

  func testAnimationRestoresLatestSurvivingSemanticOwner() throws {
    let id = try CharacterAnimationID(validating: "temporary-owner")
    var state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.calmTrust)).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    state = ReactiveCharacter.reduce(state: state, event: .userWritingBegan(focus: .center)).state
    state = ReactiveCharacter.reduce(state: state, event: .animationStarted(id: id, animation: .nod)).state
    state = ReactiveCharacter.reduce(state: state, event: .userWritingEnded).state
    XCTAssertEqual(state.visualChannel, .animation)

    state = ReactiveCharacter.reduce(state: state, event: .animationEnded(id: id)).state
    XCTAssertEqual(state.visualChannel, .communication)
    state = ReactiveCharacter.reduce(state: state, event: .communicationEnded).state
    XCTAssertEqual(state.visualChannel, .emotion)
    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(nil)).state
    XCTAssertEqual(state, .idle)
  }

  func testCompletionTimerCoversPresentationHandoffAndOneShot() throws {
    let initial = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    for animation in CharacterAnimation.allCases {
      let id = try CharacterAnimationID(validating: "timer-\(animation.rawValue)")
      let receipt = ReactiveCharacter.act(
        state: initial, event: .animationStarted(id: id, animation: animation)
      )
      var presentation = CharacterPresentationSession(state: initial, at: 0)
      XCTAssertTrue(presentation.update(state: receipt.stateAfter, at: 0.3))
      XCTAssertEqual(receipt.effects.count, 1)
      guard let effect = receipt.effects.first,
        case .scheduleAnimationEnd(let scheduledID, let delay) = effect
      else {
        return XCTFail("A one-shot must request its completion timer")
      }
      XCTAssertEqual(scheduledID, id)
      XCTAssertGreaterThanOrEqual(
        delay, presentation.inspect(at: 0.3).remainingHandoffDuration + animation.duration
      )
    }
  }

  private func scene(_ pose: CharacterPose) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(pose: pose, width: 240, height: 240)
  }
}

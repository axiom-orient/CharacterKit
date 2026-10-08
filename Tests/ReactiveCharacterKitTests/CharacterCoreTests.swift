import XCTest
@testable import ReactiveCharacterKit

final class CharacterCoreTests: XCTestCase {
  func testInitialStateIsSingleNeutralAuthority() {
    let state = ReactiveCharacter.initialState
    XCTAssertEqual(state, .idle)
    XCTAssertEqual(state.activity, .idle)
    XCTAssertEqual(state.attention, .automatic)
    XCTAssertNil(state.emotion)
    XCTAssertEqual(state.communication, .silent)
    XCTAssertNil(state.animation)
    XCTAssertEqual(state.visualChannel, .neutral)
  }

  func testAgentLifecycleIsExplicitAndRejectsRegressedProgress() throws {
    let task = try CharacterTaskID(validating: "task-1")
    let started = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: task))
    XCTAssertEqual(started.disposition, .accepted)
    XCTAssertEqual(started.state.activity, .agentThinking(taskID: task))

    let progressed = ReactiveCharacter.reduce(
      state: started.state,
      event: .agentProgress(taskID: task, progress: 0.6)
    )
    XCTAssertEqual(progressed.disposition, .accepted)
    XCTAssertEqual(
      progressed.state.activity,
      .agentWriting(taskID: task, progress: try CharacterProgress(validating: 0.6))
    )

    let regressed = ReactiveCharacter.reduce(
      state: progressed.state,
      event: .agentProgress(taskID: task, progress: 0.4)
    )
    XCTAssertEqual(
      regressed.disposition,
      .rejected(.progressRegressed(previous: 0.6, received: 0.4))
    )
    XCTAssertEqual(regressed.state, progressed.state)
  }

  func testStaleTaskCannotMutateCurrentTask() throws {
    let current = try CharacterTaskID(validating: "current")
    let stale = try CharacterTaskID(validating: "stale")
    let state = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: current)).state
    let result = ReactiveCharacter.reduce(
      state: state,
      event: .agentProgress(taskID: stale, progress: 0.5)
    )
    XCTAssertEqual(
      result.disposition,
      .ignored(.staleTask(expected: current, received: stale))
    )
    XCTAssertEqual(result.state, state)
  }

  func testEmotionCommunicationAndActivityRemainOrthogonal() throws {
    let task = try CharacterTaskID(validating: "orthogonal")
    var state = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: task)).state
    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.gratitude)).state
    state = ReactiveCharacter.reduce(state: state, event: .voiceStarted).state

    XCTAssertEqual(state.activity, .agentThinking(taskID: task))
    XCTAssertEqual(state.emotion, .gratitude)
    XCTAssertEqual(state.communication, .voice(level: .zero))
    XCTAssertEqual(state.visualChannel, .communication)
  }

  func testAnimationLifecycleUsesIdentityAndHostEffect() throws {
    let id = try CharacterAnimationID(validating: "blink-1")
    let started = ReactiveCharacter.reduce(
      state: .idle,
      event: .animationStarted(id: id, animation: .blink)
    )
    XCTAssertEqual(started.disposition, .accepted)
    XCTAssertEqual(started.state.animation, .init(id: id, animation: .blink))
    XCTAssertEqual(started.state.visualChannel, .animation)
    XCTAssertEqual(started.effects.count, 1)

    let ended = ReactiveCharacter.reduce(state: started.state, event: .animationEnded(id: id))
    XCTAssertEqual(ended.disposition, .accepted)
    XCTAssertNil(ended.state.animation)
    XCTAssertEqual(ended.state.visualChannel, .neutral)
  }

  func testValidatedInputsRejectInvalidNumbers() {
    XCTAssertThrowsError(try CharacterProgress(validating: -.leastNonzeroMagnitude))
    XCTAssertThrowsError(try CharacterProgress(validating: 1.000_001))
    XCTAssertThrowsError(try CharacterVoiceLevel(validating: .infinity))
    XCTAssertThrowsError(try CharacterPoint(validatingX: .nan, y: 0.5))
  }
}

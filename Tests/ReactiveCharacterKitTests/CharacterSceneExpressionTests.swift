import XCTest

@testable import ReactiveCharacterKit

final class CharacterSceneExpressionTests: XCTestCase {
  private func scene(
    _ state: CharacterState, at time: Double = 0, reduced: Bool = false
  ) throws -> CharacterScene {
    let direction = try CharacterArtDirection(
      name: "Expression lifecycle", components: [.eyes, .mouth, .writing], projection: .flat,
      motionProfile: .focusedEmotion())
    let pose = ReactiveCharacter.pose(
      state: state, elapsed: time, reduceMotion: reduced,
      projection: direction.projection, motionProfile: direction.motionProfile)
    return try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 400, height: 400)
  }

  func testListeningCannotManufactureSpeechOrMouthMotion() throws {
    let listening = ReactiveCharacter.act(state: .idle, event: .listeningStarted).stateAfter
    let loud = ReactiveCharacter.act(state: listening, event: .listeningLevelChanged(1)).stateAfter
    for state in [CharacterState.idle, listening, loud] {
      XCTAssertFalse(ReactiveCharacter.inspect(state: state).mouthRequested)
      for reduced in [false, true] {
        XCTAssertFalse(try scene(state, at: 0.8, reduced: reduced).nodes.contains { $0.id.hasPrefix("mouth") })
      }
    }
    let wrongDirection = ReactiveCharacter.act(state: loud, event: .voiceLevelChanged(0.8))
    XCTAssertEqual(wrongDirection.disposition, .ignored(.eventNotApplicable))
    XCTAssertEqual(wrongDirection.stateAfter, loud)
  }

  func testSpeechMouthDisappearsWhenCommunicationEnds() throws {
    for event in [CharacterEvent.chatStarted, .voiceStarted] {
      let speaking = ReactiveCharacter.act(state: .idle, event: event).stateAfter
      XCTAssertTrue(try scene(speaking, reduced: true).nodes.contains { $0.id == "mouth" })
      let silent = ReactiveCharacter.act(state: speaking, event: .communicationEnded).stateAfter
      XCTAssertFalse(try scene(silent, reduced: true).nodes.contains { $0.id.hasPrefix("mouth") })
    }
  }

  func testMouthDetailsRemainClippedInsideTheirParent() throws {
    let joyful = ReactiveCharacter.act(state: .idle, event: .emotionChanged(.joy)).stateAfter
    let frame = try scene(joyful, at: 0.3, reduced: true)
    let mouth = try XCTUnwrap(frame.nodes.first { $0.id == "mouth" })
    for id in ["mouth.teeth", "mouth.innerTongue"] {
      let detail = try XCTUnwrap(frame.nodes.first { $0.id == id })
      XCTAssertGreaterThan(detail.opacity, 0)
      XCTAssertEqual(detail.clips, [mouth.path])
      XCTAssertEqual(detail.transform, mouth.transform)
    }
  }

  func testWritingMovesWithStalledProgressAndStopsForTerminalStates() throws {
    let task = try CharacterTaskID(validating: "scene-writing")
    let thinking = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: task)).stateAfter
    let working = ReactiveCharacter.act(state: thinking, event: .agentProgress(taskID: task, progress: 0.4))
      .stateAfter
    XCTAssertTrue(ReactiveCharacter.inspect(state: working).mouthRequested)
    let first = try scene(working, at: 0.4)
    let later = try scene(working, at: 1.6)
    let writing = first.nodes.filter { $0.id.hasPrefix("writing") }
    XCTAssertFalse(writing.isEmpty)
    XCTAssertNotEqual(writing, later.nodes.filter { $0.id.hasPrefix("writing") })
    XCTAssertEqual(
      try scene(working, at: 0.4, reduced: true).nodes.filter { $0.id.hasPrefix("writing") },
      try scene(working, at: 1.6, reduced: true).nodes.filter { $0.id.hasPrefix("writing") })
    let failure = try CharacterFailure(operation: "test", cause: "expected")
    for event in [
      CharacterEvent.agentSucceeded(taskID: task), .agentFailed(taskID: task, failure: failure),
      .agentCancellationRequested(taskID: task), .reset,
    ] {
      let stopped = ReactiveCharacter.act(state: working, event: event).stateAfter
      XCTAssertFalse(try scene(stopped).nodes.contains { $0.id.hasPrefix("writing") })
    }
  }
}

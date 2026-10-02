import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterStateAuthorityTests: XCTestCase {
  private let task = CharacterTaskID(UUID())
  private let animation = CharacterAnimationID(UUID())

  func testVisualChannelIsDerivedFromAnimationAndSemanticRecency() {
    var state = CharacterState.idle
    assertSingleVisualAuthority(state)

    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.joy)).state
    assertSingleVisualAuthority(state)
    XCTAssertEqual(state.visualChannel, .emotion)

    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    assertSingleVisualAuthority(state)
    XCTAssertEqual(state.visualChannel, .communication)

    state = ReactiveCharacter.reduce(state: state, event: .agentStarted(taskID: task)).state
    assertSingleVisualAuthority(state)
    XCTAssertEqual(state.visualChannel, .activity)

    state =
      ReactiveCharacter.reduce(
        state: state, event: .animationStarted(id: animation, animation: .bounce)
      ).state
    assertSingleVisualAuthority(state)
    XCTAssertEqual(state.visualChannel, .animation)

    state = ReactiveCharacter.reduce(state: state, event: .animationEnded(id: animation)).state
    assertSingleVisualAuthority(state)
    XCTAssertEqual(state.visualChannel, .activity)

    state = ReactiveCharacter.reduce(state: state, event: .agentSucceeded(taskID: task)).state
    assertSingleVisualAuthority(state)
    XCTAssertEqual(state.visualChannel, .activity)
  }

  func testEndingOwnersFiltersRecencyWithoutExplicitFallbackMutation() {
    var state = ReactiveCharacter.reduce(
      state: .idle, event: .emotionChanged(.calmTrust)
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    XCTAssertEqual(state.semanticVisualRecency, [.communication, .emotion])

    state = ReactiveCharacter.reduce(state: state, event: .communicationEnded).state
    XCTAssertEqual(state.semanticVisualRecency, [.emotion])
    XCTAssertEqual(state.visualChannel, .emotion)

    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(nil)).state
    XCTAssertEqual(state.semanticVisualRecency, [])
    XCTAssertEqual(state.visualChannel, .neutral)
  }

  private func assertSingleVisualAuthority(
    _ state: CharacterState,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let expected: CharacterVisualChannel =
      state.animation != nil
      ? .animation
      : state.semanticVisualRecency.first?.publicChannel ?? .neutral
    XCTAssertEqual(state.visualChannel, expected, file: file, line: line)
    XCTAssertEqual(
      Set(state.semanticVisualRecency).count, state.semanticVisualRecency.count,
      "semantic visual recency must not contain duplicate owners", file: file, line: line
    )
  }
}

import XCTest
@testable import ReactiveCharacterKit

final class CharacterDetailExpiryTests: XCTestCase {
  func testExpiredAnimationUsesSurvivingOwnersClockBeforeCleanup() throws {
    let task = try CharacterTaskID(validating: "detail-expiry-work")
    let joy = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let thinking = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: task)).state
    let speaking = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state

    for base in [CharacterState.idle, joy, thinking, speaking] {
      for animation in CharacterAnimation.allCases {
        let id = try CharacterAnimationID(validating: "detail-expiry-\(animation.rawValue)")
        let active = ReactiveCharacter.reduce(
          state: base, event: .animationStarted(id: id, animation: animation)).state
        let completed = ReactiveCharacter.reduce(state: active, event: .animationEnded(id: id)).state
        for direction in [CharacterArtDirection.semiDocumentCat, .cat] {
          let expired = ReactiveCharacter.pose(
            state: active, elapsed: 2.7, artDirection: direction,
            expressionElapsed: 1.3, communicationElapsed: 4.1,
            animationElapsed: animation.duration + 0.2)
          let expected = ReactiveCharacter.pose(
            state: completed, elapsed: 2.7, artDirection: direction,
            expressionElapsed: 1.3, communicationElapsed: 4.1, animationElapsed: 0)
          XCTAssertEqual(expired.detailMotion, expected.detailMotion,
            "\(direction.name), \(base.visualChannel), \(animation.rawValue)")
        }
      }
    }
  }
}

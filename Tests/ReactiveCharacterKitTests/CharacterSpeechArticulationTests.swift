import Foundation
import Testing
@testable import ReactiveCharacterKit

struct CharacterSpeechArticulationTests {
  @Test func speechGeometryPreservesEmotionGazeActionAndSilenceWinsOverOpenExpression() throws {
    var state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    state = ReactiveCharacter.reduce(state: state, event: .voiceStarted).state
    state = ReactiveCharacter.reduce(state: state,
      event: .attentionFocused(try CharacterPoint(validatingX: 1, y: 0.2))).state
    state = ReactiveCharacter.reduce(state: state,
      event: .animationStarted(id: CharacterAnimationID(UUID()), animation: .nod)).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.4)
    let closed = pose.applyingSpeechArticulation(.closed)
    #expect(closed.mouth.openness == 0)
    #expect(closed.mouth.curvature == pose.mouth.curvature)
    #expect(closed.eyes == pose.eyes)
    #expect(closed.surface == pose.surface)
    #expect(closed.detailMotion == pose.detailMotion)
    #expect(closed.writingOpacity == pose.writingOpacity)
    #expect(pose.applyingSpeechArticulation(.wide, weight: 0) == pose)
    #expect(state.emotion == .surprise)
    #expect(state.animation?.animation == .nod)
    #expect(throws: CharacterError.self) { try CharacterSpeechArticulation(openness: .nan, width: 0.5) }
    #expect(throws: CharacterError.self) { try CharacterSpeechArticulation(openness: 0.5, width: 1.1) }
  }

  @Test func retargetIsContinuousAndReducedMotionUsesExplicitTarget() {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0)
    var speech = CharacterSpeechPresentation()
    #expect(speech.apply(to: pose, at: 1, reduceMotion: false) == pose)
    speech.update(.open, at: 1)
    #expect(speech.apply(to: pose, at: 1, reduceMotion: false) == pose)
    let midpoint = speech.apply(to: pose, at: 1.0225, reduceMotion: false)
    speech.update(.rounded, at: 1.0225)
    #expect(speech.apply(to: pose, at: 1.0225, reduceMotion: false) == midpoint)
    #expect(speech.apply(to: pose, at: 1.0225, reduceMotion: true).mouth.width == CharacterSpeechArticulation.rounded.width)
    speech.update(nil, at: 2)
    #expect(speech.apply(to: pose, at: 3, reduceMotion: false) == pose)
  }
}

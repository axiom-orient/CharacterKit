import CharacterChat
import Foundation
import ReactiveCharacterKit
import Testing

struct CharacterChatTests {
  @Test(arguments: [
    ("정말 행복해요!", CharacterEmotion.joy), ("사랑해요", .affection), ("정말 고마워요", .gratitude),
    ("어떻게 하는지 궁금해요?", .interest), ("깜짝 놀랐어요!", .surprise), ("천천히 해요, 믿어요", .calmTrust),
    ("슬퍼서 눈물이 나요", .sadness), ("무서워서 걱정돼요", .anxietyFear), ("정말 화가 나요!", .angerIrritation),
    ("이건 싫어요", .disgustContempt), ("미안해요", .shameGuilt), ("피곤해서 쉬고 싶어요", .fatigueBurden)
  ])
  func localRulesCoverTwelveDemonstratedExpressions(example: (String, CharacterEmotion)) throws {
    let cue = try #require(CharacterChatPlan(text: example.0).cues.first)
    #expect(cue.emotion == example.1)
    #expect(cue.animation != nil)
  }

  @Test func explicitSelectionWinsAndNeutralDoesNotInventSentiment() throws {
    let text = "사랑해요. 하지만 화가 나요!"
    let explicit = try CharacterChatPlan(text: text, emotion: .emotion(.calmTrust))
    #expect(explicit.cues.count == 2)
    #expect(explicit.cues.allSatisfy { $0.emotion == .calmTrust })
    #expect(try CharacterChatPlan(text: text, emotion: .neutral).cues.allSatisfy { $0.emotion == nil })
    #expect(try CharacterChatPlan(text: "문서를 열었습니다.").cues.first?.emotion == nil)
    #expect(try CharacterChatPlan(text: "행복하지 않아요").cues.first?.emotion == .sadness)
    #expect(try CharacterChatPlan(text: "걱정하지 마세요").cues.first?.emotion == .calmTrust)
    #expect(throws: CharacterChatError.emptyText) { try CharacterChatPlan(text: " \n") }
    #expect(throws: CharacterChatError.self) { try CharacterChatPlan(text: String(repeating: "아", count: 513)) }
  }

  @Test func unicodeCueRangesRoundTripAndFollowSpokenOffsets() throws {
    let text = "👨‍👩‍👧‍👦 정말 고마워요!\n 이젠 행복해요."
    let plan = try CharacterChatPlan(text: text)
    #expect(plan.cues.count == 2)
    for (index, cue) in plan.cues.enumerated() {
      let range = try #require(Range(cue.utf16Range, in: text))
      #expect(String(text[range]) == cue.text)
      #expect(plan.cueIndex(atUTF16Offset: cue.utf16Range.location) == index)
    }
    #expect(plan.cueIndex(atUTF16Offset: text.utf16.count) == nil)
    #expect(plan.cueIndex(atUTF16Offset: -1) == nil)
  }

  @Test func audioClockSelectsDifferentVowelsAndClosesOnMeasuredSilence() throws {
    let words = (0..<3).map { CharacterSpeechWord(time: Double($0) * 0.2, utf16Range: NSRange(location: $0, length: 1)) }
    let track = try CharacterSpeechTrack(text: "아이오", duration: 0.6,
      energy: Array(repeating: 1, count: 30), words: words)
    let a = track.frame(at: 0.1), i = track.frame(at: 0.3), o = track.frame(at: 0.5)
    #expect(a.articulation == .open)
    #expect(i.articulation == .wide)
    #expect(o.articulation == .rounded)
    #expect(i.articulation.width > o.articulation.width)
    #expect(track.frame(at: .infinity) == .silence)
    #expect(track.frame(at: -1) == .silence)
    #expect(track.frame(at: 0.6) == .silence)
    let silent = try CharacterSpeechTrack(text: "아이오", duration: 0.6,
      energy: Array(repeating: 0, count: 30), words: words)
    #expect(silent.frame(at: 0.3).articulation == .closed)
    #expect(silent.frame(at: 0.3).utf16Range?.location == 1)
    let spokenEmoji = try CharacterSpeechTrack(text: "😊", duration: 0.2,
      energy: Array(repeating: 0.8, count: 10),
      words: [.init(time: 0, utf16Range: NSRange(location: 0, length: 2))])
    #expect(spokenEmoji.frame(at: 0.1).articulation.openness > 0.5)
    #expect(throws: CharacterChatError.invalidSpeechTrack) {
      try CharacterSpeechTrack(text: "😊", duration: 0.2, energy: Array(repeating: 1, count: 10),
        words: [.init(time: 0, utf16Range: NSRange(location: 1, length: 1))])
    }
    #expect(throws: CharacterChatError.invalidSpeechTrack) {
      try CharacterSpeechTrack(text: "아", duration: 1, energy: [.nan], words: [])
    }
  }

  @Test func textPreviewIsDeterministicAndContainsNoAudioAssumption() throws {
    let a = try CharacterSpeechTrack.textPreview("아 이 오. ❤️"), b = try CharacterSpeechTrack.textPreview("아 이 오. ❤️")
    #expect(a.duration == b.duration)
    for t in stride(from: 0.0, through: a.duration, by: 0.03) { #expect(a.frame(at: t) == b.frame(at: t)) }
    #expect(try CharacterSpeechTrack.textPreview("❤️").frame(at: 0.1).articulation == .closed)
  }
}

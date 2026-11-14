import Foundation
import ReactiveCharacterKit

public enum CharacterChatError: Error, Sendable, Equatable, LocalizedError {
  case emptyText
  case textTooLong(maximum: Int)
  case invalidSpeechTrack
  public var errorDescription: String? {
    switch self {
    case .emptyText: "Enter a message to perform."
    case .textTooLong(let maximum): "Messages may contain at most \(maximum) characters."
    case .invalidSpeechTrack: "Speech timing, text ranges or energy samples are invalid."
    }
  }
}

/// Interpretation is an optional host adapter. The rendering SDK never reads chat text.
public enum CharacterChatEmotion: Sendable, Equatable {
  case automatic
  case neutral
  case emotion(CharacterEmotion)
}

/// A bounded, local message-to-expression plan. Automatic rules are deliberately
/// conservative; a host/model's explicit selection always takes precedence.
public struct CharacterChatPlan: Sendable, Equatable {
  public static let maximumCharacters = 512
  public struct Cue: Sendable, Equatable {
    public let text: String
    public let utf16Range: NSRange
    public let emotion: CharacterEmotion?
    public let animation: CharacterAnimation?
  }
  public let text: String
  public let selection: CharacterChatEmotion
  public let cues: [Cue]

  public init(text: String, emotion selection: CharacterChatEmotion = .automatic) throws {
    guard text.count <= Self.maximumCharacters else {
      throw CharacterChatError.textTooLong(maximum: Self.maximumCharacters)
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CharacterChatError.emptyText }
    self.text = text; self.selection = selection
    var result: [Cue] = []
    func append(_ range: Range<String.Index>) {
      let indices = text[range].indices.filter { !text[$0].isWhitespace }
      guard let first = indices.first, let last = indices.last else { return }
      let trimmed = first..<text.index(after: last)
      let part = String(text[trimmed])
      let emotion: CharacterEmotion?
      switch selection {
      case .automatic: emotion = Self.infer(part)
      case .neutral: emotion = nil
      case .emotion(let value): emotion = value
      }
      result.append(Cue(text: part, utf16Range: NSRange(trimmed, in: text),
        emotion: emotion, animation: Self.gesture(for: emotion)))
    }
    var start = text.startIndex
    for index in text.indices {
      let next = text.index(after: index)
      if ".!?。！？\n".contains(text[index]) {
        append(start..<next); start = next
      }
    }
    if start < text.endIndex { append(start..<text.endIndex) }
    cues = result
  }

  public func cueIndex(atUTF16Offset offset: Int) -> Int? {
    guard offset >= 0, offset < text.utf16.count else { return nil }
    return cues.lastIndex { $0.utf16Range.location <= offset } ?? cues.indices.first
  }

  private static func infer(_ text: String) -> CharacterEmotion? {
    let s = text.lowercased().filter { !$0.isWhitespace }
    // Negation is checked before positive vocabulary. Unknown/ambiguous text stays neutral.
    let rules: [(CharacterEmotion, [String])] = [
      (.sadness, ["행복하지않", "기쁘지않", "즐겁지않", "안행복", "안기뻐", "not happy", "unhappy"]),
      (.calmTrust, ["걱정하지마", "걱정안해", "무섭지않", "화나지않", "화안났", "화안나", "dontworry", "don'tworry", "notangry", "notsad", "nottired", "슬프지않", "싫지않", "피곤하지않", "안피곤"]),
      (.shameGuilt, ["미안", "죄송", "부끄", "창피", "후회", "sorry", "ashamed"]),
      (.angerIrritation, ["화가", "화나", "화났", "짜증", "분노", "억울", "angry", "furious", "😡", "😠"]),
      (.anxietyFear, ["걱정", "불안", "무서", "두려", "긴장", "겁나", "afraid", "scared", "worried", "😨"]),
      (.sadness, ["슬퍼", "슬프", "속상", "우울", "눈물", "ㅠㅠ", "ㅜㅜ", "sad", "cry", "😢", "😭"]),
      (.fatigueBurden, ["피곤", "지쳐", "힘들", "졸려", "지친", "쉬고싶", "tired", "sleepy", "exhausted", "😴"]),
      (.disgustContempt, ["싫어", "불쾌", "역겨", "징그러", "별로", "disgust", "gross", "🤢"]),
      (.gratitude, ["고마", "감사", "덕분", "thank", "grateful", "🙏"]),
      (.affection, ["사랑", "좋아해", "보고싶", "애정", "love", "missyou", "❤️", "🥰"]),
      (.surprise, ["깜짝", "놀랐", "놀라", "세상에", "대박", "surpris", "wow", "😲", "😮"]),
      (.calmTrust, ["괜찮", "안심", "믿어", "천천히", "편안", "안정", "trust", "relax", "calm"]),
      (.joy, ["신나", "행복", "기뻐", "기쁘", "즐거", "성공", "ㅋㅋ", "ㅎㅎ", "happy", "great", "yay", "😊", "😄"]),
      (.interest, ["궁금", "어떻게", "알려", "관심", "왜", "curious", "how", "why", "?"])
    ]
    return rules.first { _, terms in terms.contains { s.contains($0.filter { !$0.isWhitespace }) } }?.0
  }

  private static func gesture(for emotion: CharacterEmotion?) -> CharacterAnimation? {
    switch emotion {
    case .joy: .celebrate
    case .affection: .bounce
    case .gratitude, .calmTrust: .nod
    case .interest, .shameGuilt: .peek
    case .surprise, .anxietyFear: .recoil
    case .angerIrritation, .disgustContempt: .shake
    case .sadness, .fatigueBurden: .sigh
    case nil: nil
    }
  }
}

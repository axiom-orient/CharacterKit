import Foundation
import ReactiveCharacterKit

public struct CharacterSpeechWord: Sendable, Equatable {
  public let time: Double
  public let utf16Range: NSRange
  public init(time: Double, utf16Range: NSRange) { self.time = time; self.utf16Range = utf16Range }
}

/// A common audio/text-preview timeline. Audio clients supply measured normalized
/// energy and word timestamps. Vowel shapes are spelling estimates, not certified phonemes.
public struct CharacterSpeechTrack: Sendable {
  public static let energyInterval = 0.02
  public static let maximumDuration = 120.0
  public struct Frame: Sendable, Equatable {
    public let articulation: CharacterSpeechArticulation
    public let level: Double
    public let utf16Range: NSRange?
    public static let silence = Self(articulation: .closed, level: 0, utf16Range: nil)
  }
  private struct Unit: Sendable {
    let time: Double
    let end: Double
    let range: NSRange
    let character: Character
  }
  public let text: String
  public let duration: Double
  private let energy: [Double]
  private let units: [Unit]

  public init(text: String, duration: Double, energy: [Double], words: [CharacterSpeechWord]) throws {
    _ = try CharacterChatPlan(text: text, emotion: .neutral)
    guard duration.isFinite, duration > 0, duration <= Self.maximumDuration,
      !energy.isEmpty, energy.count <= 6001,
      energy.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      Double(energy.count) * Self.energyInterval >= duration - Self.energyInterval else {
      throw CharacterChatError.invalidSpeechTrack
    }
    var previous = -1.0
    var result: [Unit] = []
    for (index, word) in words.enumerated() {
      let r = word.utf16Range
      guard word.time.isFinite, word.time >= previous, word.time >= 0, word.time < duration,
        r.location >= 0, r.location <= text.utf16.count, r.length > 0,
        r.length <= text.utf16.count - r.location,
        let range = Range(r, in: text), NSRange(range, in: text) == r,
        text.indices.contains(range.lowerBound),
        range.upperBound == text.endIndex || text.indices.contains(range.upperBound) else { throw CharacterChatError.invalidSpeechTrack }
      previous = word.time
      let end = index + 1 < words.count ? words[index + 1].time : duration
      let indices = Array(text[range].indices)
      for (i, position) in indices.enumerated() {
        let after = text.index(after: position)
        result.append(Unit(time: word.time + (end - word.time) * Double(i) / Double(indices.count),
          end: word.time + (end - word.time) * Double(i + 1) / Double(indices.count),
          range: NSRange(position..<after, in: text), character: text[position]))
      }
    }
    self.text = text; self.duration = duration; self.energy = energy; units = result
  }

  public func frame(at time: Double) -> Frame {
    guard time.isFinite, time >= 0, time < duration else { return .silence }
    let index = min(energy.count - 1, Int(time / Self.energyInterval))
    let level = energy[index]
    guard let unit = units.last(where: { $0.time <= time && time < $0.end }) else {
      return .silence
    }
    guard level > 0.035 else { return Frame(articulation: .closed, level: 0, utf16Range: unit.range) }
    let phase = (time - unit.time) / max(0.001, unit.end - unit.time)
    let shape = Self.shape(for: unit.character, phase: phase)
    // All parameters are validated normalized values; scaling cannot fail here.
    return Frame(articulation: try! shape.scaled(by: level), level: level, utf16Range: unit.range)
  }

  /// Explicit silent preview. Its estimated timing is never used as an audio clock.
  public static func textPreview(_ text: String) throws -> Self {
    _ = try CharacterChatPlan(text: text, emotion: .neutral)
    var words: [CharacterSpeechWord] = []
    var spans: [(Double, Double, Bool)] = []
    var time = 0.0
    for index in text.indices {
      let ch = text[index]
      let voiced = ch.isLetter || ch.isNumber
      let length = voiced ? 0.16 : 0.22
      words.append(.init(time: time, utf16Range: NSRange(index..<text.index(after: index), in: text)))
      spans.append((time, time + length, voiced)); time += length
    }
    var energy: [Double] = []
    for t in stride(from: 0.0, to: time + energyInterval, by: energyInterval) {
      if let span = spans.first(where: { $0.0 <= t && t < $0.1 }), span.2 {
        let phase = (t - span.0) / (span.1 - span.0)
        energy.append(max(0, sin(.pi * phase)) * 0.9)
      } else { energy.append(0) }
    }
    return try Self(text: text, duration: time, energy: energy, words: words)
  }

  private static func shape(for character: Character, phase: Double) -> CharacterSpeechArticulation {
    let normalized = String(character).precomposedStringWithCanonicalMapping
    if let scalar = normalized.unicodeScalars.first, normalized.unicodeScalars.count == 1,
      (0xAC00...0xD7A3).contains(scalar.value) {
      let syllable = Int(scalar.value - 0xAC00)
      let lead = syllable / 588, vowel = syllable / 28 % 21, tail = syllable % 28
      if ([6, 7, 8, 17].contains(lead) && phase < 0.15)
        || ([16, 17, 18].contains(tail) && phase > 0.78) { return .closed }
      if [9, 14].contains(vowel) { return phase < 0.4 ? .rounded : .open }
      if [10, 11, 15, 16].contains(vowel) { return phase < 0.4 ? .rounded : .wide }
      if [8, 12, 13, 17].contains(vowel) { return .rounded }
      if [1, 3, 5, 7, 18, 19, 20].contains(vowel) { return .wide }
      return .open
    }
    switch normalized.lowercased() {
    case "a", "ㅏ", "ㅑ", "ㅓ", "ㅕ": return .open
    case "e", "i", "y", "ㅣ", "ㅔ", "ㅐ", "ㅡ": return .wide
    case "o", "u", "w", "ㅗ", "ㅜ", "ㅛ", "ㅠ": return .rounded
    case "m", "b", "p", "ㅁ", "ㅂ", "ㅍ": return .closed
    // An audio provider can pronounce emoji/symbol names. Positive measured
    // energy must still animate them; text-preview punctuation has zero energy.
    default: return character.isLetter || character.isNumber ? .consonant : .open
    }
  }
}

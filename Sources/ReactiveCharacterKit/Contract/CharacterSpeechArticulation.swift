import Foundation

/// Host-supplied mouth geometry from speech/viseme timing. This is presentation input,
/// not sentiment, an audio recorder or another semantic state owner.
public struct CharacterSpeechArticulation: Sendable, Equatable {
  public let openness: Double
  public let width: Double

  public init(openness: Double, width: Double) throws {
    for (field, value) in [("speech.openness", openness), ("speech.width", width)] {
      guard value.isFinite else { throw CharacterError.nonFiniteValue(field: field, value: value) }
      guard (0...1).contains(value) else { throw CharacterError.outOfRange(field: field, value: value) }
    }
    self.openness = openness
    self.width = width
  }

  init(uncheckedOpenness: Double, width: Double) {
    openness = uncheckedOpenness; self.width = width
  }

  public static let closed = Self(uncheckedOpenness: 0, width: 0.55)
  public static let open = Self(uncheckedOpenness: 0.88, width: 0.76)
  public static let wide = Self(uncheckedOpenness: 0.38, width: 0.96)
  public static let rounded = Self(uncheckedOpenness: 0.72, width: 0.32)
  public static let consonant = Self(uncheckedOpenness: 0.22, width: 0.58)

  /// Scale by measured/estimated speech energy. Silence closes the mouth even when
  /// the emotion's authored mouth is open. Invalid energy is rejected at the boundary.
  public func scaled(by energy: Double) throws -> Self {
    guard energy.isFinite else { throw CharacterError.nonFiniteValue(field: "speech.energy", value: energy) }
    guard (0...1).contains(energy) else { throw CharacterError.outOfRange(field: "speech.energy", value: energy) }
    return Self(uncheckedOpenness: openness * energy, width: width)
  }
}

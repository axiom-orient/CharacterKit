/// Reference-derived hand-drawn mouth vocabulary. These are presentation
/// glyphs; hosts still select semantic emotions and communication via state.
enum CharacterMouthGlyph: String, CaseIterable, Sendable, Equatable, Hashable {
  case slantedOpen
  case baseFlat
  case toothyOpen
  case tongueDrop
  case zigzag
  case clenchedWave
  case speechWave
  case puckerO
  case halfMoonTeeth
  case uneasyOpen
  case downturnedArc
  case asymmetricSmirk
  case openGrill
  case smallYawn
  case wideToothyGrin
  case caretFrown
}

enum CharacterMouthInterior: String, Sendable, Equatable {
  case none
  case teeth
  case tongue
  case teethAndTongue
}

struct MouthVector: Sendable, Equatable {
  let x: Double
  let y: Double
}

struct MouthCubicSegment: Sendable, Equatable {
  let start: MouthVector
  let control1: MouthVector
  let control2: MouthVector
  let end: MouthVector

  func mapped(_ transform: (MouthVector) -> MouthVector) -> Self {
    Self(
      start: transform(start), control1: transform(control1),
      control2: transform(control2), end: transform(end))
  }
}

enum MouthDetailKind: String, Sendable, Equatable {
  case negativeOpening
  case teeth
  case tongue
  case innerLine
}

struct MouthDetailPath: Sendable, Equatable {
  let kind: MouthDetailKind
  let segments: [MouthCubicSegment]
  let closed: Bool
}

struct MouthGlyphDefinition: Sendable, Equatable {
  let glyph: CharacterMouthGlyph
  let interior: CharacterMouthInterior
  let segments: [MouthCubicSegment]
  let details: [MouthDetailPath]
}

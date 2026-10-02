/// Procedural cat geometry. Authored reference cats use `CharacterAnatomy.reference`.
public enum CharacterProceduralCatTheme: String, CaseIterable, Sendable, Equatable {
  case animated
  case simple2D = "simple-2d"
}

/// The complete anatomy selection for one visual configuration.
/// Each case consumes the shared pose; it never owns semantic state or host effects.
public enum CharacterAnatomy: Sendable, Equatable {
  case minimal
  case cat(CharacterProceduralCatTheme)
  case reference(CharacterReferenceAppearance)
  case portrait(CharacterPortraitStyle)
}

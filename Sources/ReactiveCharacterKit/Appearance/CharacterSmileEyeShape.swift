/// Rendering of an existing smile in flat portrait/simple-cat anatomy.
/// This is not an emotion, an animation or a second pose owner.
public enum CharacterSmileEyeShape: String, CaseIterable, Sendable, Hashable {
  case arc
  case chevron
}

extension CharacterEyeContour {
  func presentingSmile(as shape: CharacterSmileEyeShape) -> Self {
    guard shape == .chevron else { return self }
    return Self(
      lidCompression: lidCompression, innerPinch: innerPinch,
      crescent: 0, ellipse: ellipse, chevron: max(chevron, crescent),
      widthScale: widthScale, heightScale: heightScale, circular: circular, heart: heart)
  }
}
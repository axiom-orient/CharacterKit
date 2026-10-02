import Foundation

public enum CharacterDesignPreset: String, Codable, CaseIterable, Sendable, Equatable {
  case black, white, arcade
}

public enum CharacterRenderMode: String, Codable, CaseIterable, Sendable, Equatable {
  case sculpted, flat, outline
}

public enum CharacterSurfaceLighting: String, Codable, CaseIterable, Sendable, Equatable {
  case radial, linear
}

public enum CharacterSilhouette: String, Codable, CaseIterable, Sendable, Equatable {
  case orb, roundedRectangle, capsule
}

public enum CharacterEyeStyle: String, Codable, CaseIterable, Sendable, Equatable {
  case capsule, ellipse, roundedRectangle
}

public enum CharacterMouthStyle: String, Codable, CaseIterable, Sendable, Equatable {
  case filled, outline
}

public enum CharacterDesignFit: String, Codable, CaseIterable, Sendable, Equatable {
  case contain, cover, stretch
}

public enum CharacterDesignProjection: String, Codable, CaseIterable, Sendable, Equatable {
  case flat, softSphere
}

public enum CharacterDesignComponent: String, Codable, CaseIterable, Sendable, Equatable {
  case eyes, nose, mouth, writing, ornaments, accessories
}

public enum CharacterDesignAccessoryGlyph: String, Codable, CaseIterable, Sendable, Equatable {
  case roundGlasses, visor, crown, bowTie, badge, headphones, halo
}

public enum CharacterDesignColorRole: String, Codable, CaseIterable, Sendable, Equatable {
  case surface, feature, detail, accent, outline
}

public enum CharacterDesignAppearance: String, Codable, CaseIterable, Sendable, Equatable {
  case light, dark
}

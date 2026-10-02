import Foundation

extension CharacterDesign {
  /// Resolved DTCG 2025.10 color/number token export. This is not a DTCG
  /// import/alias/resolver implementation; layout/rig data stays in the profile.
  public func encodedTokens(appearance: CharacterDesignAppearance = .light) throws -> Data {
    let p = palette(for: appearance)
    var colors: [String: Any] = [:]
    for (name, c) in [
      ("stage", p.stage), ("surface", p.surface), ("surfaceShade", p.surfaceShade),
      ("eye", p.eye), ("feature", p.feature), ("detail", p.detail), ("accent", p.accent),
      ("outline", p.outline),
    ] {
      colors[name] = [
        "$type": "color",
        "$value": [
          "colorSpace": "srgb",
          "components": [c.red, c.green, c.blue], "alpha": c.alpha,
        ],
      ]
    }
    var geometry: [String: Any] = [:]
    for (name, value) in [
      ("stroke", profile.rendering.lineWidth),
      ("cornerRadius", profile.rendering.cornerRadius), ("eyeScaleX", profile.rendering.eyeScaleX),
      ("eyeScaleY", profile.rendering.eyeScaleY), ("eyeSpacing", profile.rendering.eyeSpacing),
    ] {
      geometry[name] = [
        "$type": "number", "$value": value,
        "$description": "Normalized character geometry; not CSS px or native pt.",
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: [
        "$description":
          "\(profile.name) / \(appearance.rawValue) — resolved export from characterkit.design/1",
        "color": colors, "geometry": geometry,
      ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }
}

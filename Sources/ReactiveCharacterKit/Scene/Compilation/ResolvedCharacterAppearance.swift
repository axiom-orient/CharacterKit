import Foundation

/// The public APIs are different dialects, not interchangeable configuration schemas.
enum CharacterAppearanceInput {
  case design(CharacterDesign)
  case art(CharacterArtDirection)
}

/// Values only: resolution must never load an image, inspect a bundle or consult a clock.
struct ResolvedCharacterAppearance {
  enum Payload {
    case design(Design)
    case art(CharacterArtDirection)
  }

  struct Design {
    let source: CharacterDesign
    let palette: CharacterDesignPalette
    let partColors: CharacterPartColors
    let usesRuntimePartColors: Bool
    let surfaceShade: CharacterColor
    let strokeWidth: Double
  }

  let bounds: CharacterRect
  let mode: CharacterRenderMode
  let compact: Bool
  let simplified: Bool
  let payload: Payload

  static func resolve(
    _ input: CharacterAppearanceInput, width: Double, height: Double,
    environment: CharacterDesignEnvironment
  ) -> Self {
    let simplified = environment.increasedContrast || environment.reduceTransparency
    switch input {
    case .design(let design):
      let artboard = design.profile.layout.artboard(width: width, height: height)
      let face = CharacterGeometry.map(design.faceRegion, into: artboard)
      let palette = environment.increasedContrast
        ? design.palette(for: environment.appearance).increasedContrast()
        : design.palette(for: environment.appearance)
      let partColors = environment.increasedContrast
        ? palette.partColors : (environment.partColors ?? palette.partColors)
      return Self(
        bounds: face,
        mode: simplified ? .flat : design.profile.rendering.mode,
        compact: min(face.width, face.height) < design.profile.rendering.compactBelow,
        simplified: simplified,
        payload: .design(.init(
          source: design, palette: palette, partColors: partColors,
          usesRuntimePartColors: environment.partColors != nil && !environment.increasedContrast,
          surfaceShade: environment.increasedContrast || environment.partColors == nil
            ? palette.surfaceShade : partColors.surface.characterShade,
          strokeWidth: max(
            design.profile.rendering.minimumStrokeWidth,
            min(face.width, face.height) * design.profile.rendering.lineWidth)
            * (environment.increasedContrast ? 1.25 : 1))))
    case .art(let direction):
      let outer: CharacterRect
      if case .reference = direction.anatomy {
        outer = .init(x: 0, y: 0, width: width, height: height)
      } else {
        outer = CharacterGeometry.coordinateSpace(
          in: .init(width: width, height: height), surface: direction.surface)
      }
      let inset = min(outer.width, outer.height) * direction.contentInset
      let board = CharacterRect(
        x: outer.x + inset, y: outer.y + inset,
        width: outer.width - 2 * inset, height: outer.height - 2 * inset)
      // ArtDirection owns its colors. Environment partColors/appearance do not override them.
      return Self(
        bounds: board, mode: simplified ? .flat : .sculpted,
        compact: min(board.width, board.height) < CharacterRenderLimits.artCompactBelow,
        simplified: simplified, payload: .art(direction))
    }
  }
}

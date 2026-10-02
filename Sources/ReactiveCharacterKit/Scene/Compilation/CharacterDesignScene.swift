import Foundation

struct CharacterSceneDrawing {
  var nodes: [CharacterSceneNode] = []
  let design: CharacterDesign
  let palette: CharacterDesignPalette
  let partColors: CharacterPartColors
  let usesRuntimePartColors: Bool
  let surfaceShade: CharacterColor
  let face: CharacterRect
  let transform: CharacterSceneTransform
  let mode: CharacterRenderMode
  let compact: Bool
  let simplified: Bool
  let strokeWidth: Double

  mutating func add(
    _ id: String, _ path: CharacterVectorPath,
    layer: CharacterSceneLayer = .features, fill: CharacterScenePaint? = nil,
    stroke: CharacterColor? = nil, width: Double? = nil, opacity: Double = 1,
    transform: CharacterSceneTransform? = nil, clips: [CharacterVectorPath] = []
  ) {
    guard opacity > 0, !path.commands.isEmpty else { return }
    nodes.append(
      .init(
        id: id, layer: layer, path: path, fill: fill, stroke: stroke,
        lineWidth: width ?? strokeWidth, opacity: min(1, max(0, opacity)),
        transform: transform ?? self.transform, clips: clips))
  }

  func region(_ r: CharacterRegion) -> CharacterRect { CharacterGeometry.map(r, into: face) }

  func localPath(_ path: CharacterVectorPath, in rect: CharacterRect) -> CharacterVectorPath {
    path.mapped { .init(x: rect.x + $0.x * rect.width, y: rect.y + $0.y * rect.height) }
  }
}

extension CharacterSceneDrawing {
  static func emit(
    pose: CharacterPose, resolved: ResolvedCharacterAppearance.Design,
    appearance: ResolvedCharacterAppearance, transform: CharacterSceneTransform,
    width: Double, height: Double, includeBackground: Bool, overlays: [CharacterAccentPose]
  ) -> [CharacterSceneNode] {
    let design = resolved.source
    let palette = resolved.palette
    let compact = appearance.compact
    var drawing = CharacterSceneDrawing(
      design: design, palette: palette, partColors: resolved.partColors,
      usesRuntimePartColors: resolved.usesRuntimePartColors,
      surfaceShade: resolved.surfaceShade, face: appearance.bounds,
      transform: transform, mode: appearance.mode, compact: compact,
      simplified: appearance.simplified, strokeWidth: resolved.strokeWidth)
    if includeBackground {
      drawing.add(
        "stage", .rectangle(.init(x: 0, y: 0, width: width, height: height)),
        layer: .background, fill: .solid(palette.stage), transform: .identity)
    }
    drawing.drawSurface(pose: pose)
    if design.components.contains(.ornaments), !compact {
      for (index, accent) in (pose.accents + overlays).enumerated() {
        drawing.drawAccent(accent, id: "accent.\(index)")
      }
    }
    drawing.drawFace(pose: pose)
    if design.components.contains(.accessories) {
      for accessory in design.accessories { drawing.drawAccessory(accessory) }
    }
    return drawing.nodes
  }
}
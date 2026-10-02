import Foundation

enum CharacterOrnamentGeometry {
  static func placement(
    for accent: CharacterAccentPose, in face: CharacterRect
  ) -> (center: CharacterVectorPoint, bounds: CharacterRect) {
    let width = accent.width * face.width
    let height = accent.height * face.height
    let x = face.x + accent.centerX * face.width
    let y = face.y + accent.centerY * face.height
    return (
      .init(x: x, y: y),
      .init(x: x - width / 2, y: y - height / 2, width: width, height: height))
  }

  static func shape(_ kind: CharacterAccentKind) -> (path: CharacterVectorPath, filled: Bool) {
    var p = CharacterVectorPath()
    var filled = true
    switch kind {
    case .heart:
      p.move(0.50, 0.93)
      p.cubic(-0.22, 0.45, 0.08, -0.16, 0.50, 0.22)
      p.cubic(0.92, -0.16, 1.22, 0.45, 0.50, 0.93)
      p.close()
    case .sparkle:
      p.move(0.50, 0.02)
      p.quad(0.55, 0.43, 0.98, 0.50)
      p.quad(0.55, 0.57, 0.50, 0.98)
      p.quad(0.45, 0.57, 0.02, 0.50)
      p.quad(0.45, 0.43, 0.50, 0.02)
      p.close()
    case .ring:
      p = .ellipse(.init(x: 0.05, y: 0.05, width: 0.90, height: 0.90))
      filled = false
    case .ray:
      p.move(0.10, 0.50)
      p.line(0.90, 0.50)
      filled = false
    case .sweatDrop, .tearDrop:
      p.move(0.50, 0.02)
      p.cubic(0.37, 0.27, 0.08, 0.56, 0.20, 0.79)
      p.cubic(0.34, 1.05, 0.66, 1.05, 0.80, 0.79)
      p.cubic(0.92, 0.56, 0.63, 0.27, 0.50, 0.02)
      p.close()
    case .puff:
      p.move(0.08, 0.63)
      p.cubic(-0.03, 0.30, 0.23, 0.18, 0.34, 0.31)
      p.cubic(0.35, 0.01, 0.64, 0.03, 0.69, 0.30)
      p.cubic(1.00, 0.18, 1.10, 0.64, 0.87, 0.77)
      p.cubic(0.70, 0.92, 0.54, 0.69, 0.40, 0.84)
      p.line(0.10, 0.94)
      p.line(0.21, 0.76)
      p.quad(0.10, 0.78, 0.08, 0.63)
      p.close()
    }
    return (p, filled)
  }
}

extension CharacterSceneDrawing {
  mutating func drawAccent(_ accent: CharacterAccentPose, id: String) {
    let accent = CharacterOrnamentPlacement.adjusted(
      accent, avoiding: design.accessories, layout: design.layout)
    guard accent.opacity > 0, accent.width > 0, accent.height > 0 else { return }
    let placement = CharacterOrnamentGeometry.placement(for: accent, in: face)
    let envelope = placement.bounds
    let t = transform.concatenating(
      .around(x: placement.center.x, y: placement.center.y, angle: accent.angle))
    let (p, filled) = CharacterOrnamentGeometry.shape(accent.kind)
    add(
      id, localPath(p, in: envelope), layer: .behindFeatures,
      fill: filled && mode != .outline ? .solid(partColors.accent) : nil,
      stroke: !filled || mode == .outline ? partColors.accent : nil,
      width: min(strokeWidth * 0.78, min(envelope.width, envelope.height) * 0.16), opacity: accent.opacity, transform: t)
  }
}

extension CharacterArtDrawing {
  mutating func accent(_ accent: CharacterAccentPose, id: String) {
    let accent = CharacterOrnamentPlacement.adjusted(
      accent, avoiding: direction.assets.accessories, layout: direction.layout)
    guard accent.opacity > 0, accent.width > 0, accent.height > 0 else { return }
    let (shape, filled) = CharacterOrnamentGeometry.shape(accent.kind)
    let color = direction.style.partColors.accent
    let placement = CharacterOrnamentGeometry.placement(for: accent, in: board)
    let r = placement.bounds
    let t = transform.concatenating(
      .around(x: placement.center.x, y: placement.center.y, angle: accent.angle))
    let path = local(shape, in: r)
    let lineWidth = min(stroke * 0.78, min(r.width, r.height) * 0.16)
    glow(
      id + ".glow", bounds: r, color: color,
      amount: direction.ornamentGlow * accent.opacity, transform: t)
    let layer: CharacterSceneLayer = .foreground
    add(
      id, path, layer: layer,
      fill: filled ? .solid(color) : nil,
      stroke: color,
      width: filled ? max(0.6, lineWidth * 0.14) : lineWidth,
      opacity: accent.opacity, transform: t)

    if filled {
      add(
        id + ".edge", path, layer: layer,
        stroke: .designWhite, width: max(0.5, lineWidth * 0.16),
        opacity: min(0.52, accent.opacity * 0.62), transform: t)
      if let highlight = accentHighlightPath(for: accent.kind, in: r) {
        add(
          id + ".highlight", highlight, layer: layer,
          stroke: .designWhite, width: max(0.6, lineWidth * 0.18),
          opacity: min(0.80, accent.opacity * 0.88), transform: t)
      }
    }
  }

  func accentHighlightPath(for kind: CharacterAccentKind, in rect: CharacterRect)
    -> CharacterVectorPath?
  {
    var p = CharacterVectorPath()
    switch kind {
    case .heart:
      p.move(rect.x + rect.width * 0.34, rect.y + rect.height * 0.28)
      p.quad(
        rect.x + rect.width * 0.25, rect.y + rect.height * 0.16,
        rect.x + rect.width * 0.40, rect.y + rect.height * 0.11)
      return p
    case .sweatDrop, .tearDrop:
      p.move(rect.x + rect.width * 0.36, rect.y + rect.height * 0.28)
      p.quad(
        rect.x + rect.width * 0.24, rect.y + rect.height * 0.40,
        rect.x + rect.width * 0.30, rect.y + rect.height * 0.58)
      return p
    case .sparkle, .ring, .ray, .puff:
      return nil
    }
  }
}

import Foundation

/// Pure presentation-only collision policy for temporary ornaments.
///
/// `CharacterAccentPose` remains renderer-independent. A renderer may move an accent only when
/// a known visual attachment would otherwise cover it. Semantic state, timing and the face
/// coordinate system remain untouched.
enum CharacterOrnamentPlacement {
  /// Central feature area that temporary comic/emotion marks must not enter.
  /// This is intentionally narrower than the whole spherical surface: tears and sweat may sit on
  /// the cheek/rim, while eyes/mouth remain visually unobstructed.
  static let faceFeatureSafeZone = CharacterRect(x: 0.25, y: 0.25, width: 0.50, height: 0.47)

  private static let frame = CharacterRect(x: 0, y: 0, width: 1, height: 1)
  private static let pathAllowance = 0.02
  private static let collisionClearance = 0.012

  private enum PerimeterLane { case left, right, top, bottom }

  /// Candidate order preserves the authored side of the character. A tear on the right may move
  /// downward around an ear cup, but it never jumps across the face to the left simply because
  /// that location happened to be free.
  private static func candidateOffsets(for lane: PerimeterLane) -> [(Double, Double)] {
    let side: Double
    switch lane {
    case .left: side = -1
    case .right: side = 1
    case .top, .bottom: side = 0
    }
    if side != 0 {
      return [
        (0, 0),
        (side * 0.08, 0), (0, -0.08), (0, 0.08),
        (side * 0.08, -0.08), (side * 0.08, 0.08),
        (side * 0.10, -0.12), (side * 0.10, 0.12),
        (side * 0.14, 0), (0, -0.14), (0, 0.14),
        (side * 0.08, -0.18), (side * 0.08, 0.18),
        (side * 0.14, -0.22), (side * 0.14, 0.22),
        (0, -0.22), (0, 0.22),
        (side * 0.08, -0.30), (side * 0.08, 0.30),
        (0, -0.30), (0, 0.30),
        (side * 0.14, -0.34), (side * 0.14, 0.34),
        (0, -0.40), (0, 0.40), (0, -0.46), (0, 0.46),
      ]
    }
    let vertical: Double = lane == .top ? -1 : 1
    return [
      (0, 0),
      (0, vertical * 0.08), (-0.08, 0), (0.08, 0),
      (-0.08, vertical * 0.08), (0.08, vertical * 0.08),
      (0, vertical * 0.14), (-0.14, 0), (0.14, 0),
      (-0.18, vertical * 0.08), (0.18, vertical * 0.08),
      (-0.22, 0), (0.22, 0),
      (0, vertical * 0.22), (-0.30, 0), (0.30, 0),
    ]
  }

  static func adjusted(
    _ accent: CharacterAccentPose,
    avoiding assets: [CharacterAccessoryAsset],
    layout: CharacterLayout = .standard
  ) -> CharacterAccentPose {
    let obstacles = assets.flatMap { Self.obstacles(for: $0, layout: layout) }
    return adjusted(accent, avoiding: obstacles)
  }

  static func adjusted(
    _ accent: CharacterAccentPose,
    avoiding designedAccessories: [CharacterDesignedAccessory],
    layout: CharacterLayout
  ) -> CharacterAccentPose {
    let unitFace = CharacterRect(x: 0, y: 0, width: 1, height: 1)
    let obstacles = designedAccessories.compactMap { item -> CharacterRect? in
      guard item.placement.opacity > 0, item.placement.layer != .behindSurface else { return nil }
      return CharacterAccessoryGeometry.envelope(
        for: item.placement, face: unitFace, layout: layout)
    }
    return adjusted(accent, avoiding: obstacles)
  }

  private static func adjusted(
    _ accent: CharacterAccentPose,
    avoiding obstacles: [CharacterRect]
  ) -> CharacterAccentPose {
    guard accent.opacity > 0, accent.width > 0, accent.height > 0, !obstacles.isEmpty else {
      return accent
    }
    let originalVisualBounds = envelope(for: accent)
    let originalCollisionBounds = envelope(for: accent, extra: collisionClearance)
    guard intersectsAny(originalCollisionBounds, obstacles: obstacles) else { return accent }
    let lane = perimeterLane(for: originalVisualBounds)

    for (dx, dy) in candidateOffsets(for: lane).dropFirst() {
      let candidate = CharacterAccentPose(
        kind: accent.kind,
        centerX: accent.centerX + dx,
        centerY: accent.centerY + dy,
        width: accent.width,
        height: accent.height,
        angle: accent.angle,
        opacity: accent.opacity
      )
      let visualBounds = envelope(for: candidate)
      let collisionBounds = envelope(for: candidate, extra: collisionClearance)
      guard contains(frame, visualBounds) else { continue }
      guard !intersects(visualBounds, faceFeatureSafeZone) else { continue }
      guard preserves(lane: lane, bounds: visualBounds) else { continue }
      guard !intersectsAny(collisionBounds, obstacles: obstacles) else { continue }
      return candidate
    }

    // If every safe perimeter candidate still collides, preserve the authored pose instead of
    // silently dropping a caller-supplied ornament.
    return accent
  }

  static func envelope(for accent: CharacterAccentPose, extra: Double = 0) -> CharacterRect {
    let cosine = abs(cos(accent.angle))
    let sine = abs(sin(accent.angle))
    let halfWidth = (cosine * accent.width + sine * accent.height) / 2 + pathAllowance + extra
    let halfHeight = (sine * accent.width + cosine * accent.height) / 2 + pathAllowance + extra
    return CharacterRect(
      x: accent.centerX - halfWidth,
      y: accent.centerY - halfHeight,
      width: halfWidth * 2,
      height: halfHeight * 2
    )
  }

  private static func perimeterLane(for bounds: CharacterRect) -> PerimeterLane {
    let safe = faceFeatureSafeZone
    if bounds.maxX <= safe.minX { return .left }
    if bounds.minX >= safe.maxX { return .right }
    if bounds.maxY <= safe.minY { return .top }
    return .bottom
  }

  private static func preserves(lane: PerimeterLane, bounds: CharacterRect) -> Bool {
    switch lane {
    case .left: return bounds.maxX <= faceFeatureSafeZone.minX
    case .right: return bounds.minX >= faceFeatureSafeZone.maxX
    case .top: return bounds.maxY <= faceFeatureSafeZone.minY
    case .bottom: return bounds.minY >= faceFeatureSafeZone.maxY
    }
  }

  private static func contains(_ outer: CharacterRect, _ inner: CharacterRect) -> Bool {
    inner.minX >= outer.minX && inner.maxX <= outer.maxX
      && inner.minY >= outer.minY && inner.maxY <= outer.maxY
  }

  private static func intersectsAny(_ rect: CharacterRect, obstacles: [CharacterRect]) -> Bool {
    obstacles.contains { intersects(rect, $0) }
  }

  private static func intersects(_ lhs: CharacterRect, _ rhs: CharacterRect) -> Bool {
    lhs.minX < rhs.maxX && rhs.minX < lhs.maxX
      && lhs.minY < rhs.maxY && rhs.minY < lhs.maxY
  }

  /// Hard-occlusion envelopes only. Primary eyes/mouth draw above `.behindFeatures`, but
  /// transient foreground marks still route around catalogued physical props such as headset
  /// cups/mic. Broad decorative behind-feature artwork such as halo/hood keeps no obstacle.
  private static func obstacles(
    for accessory: CharacterAccessoryAsset, layout: CharacterLayout
  ) -> [CharacterRect] {
    guard accessory.opacity > 0,
      let spec = CharacterBuiltInAccessoryCatalog.spec(for: accessory.image)
    else { return [] }
    let face = CharacterRect(x: 0, y: 0, width: 1, height: 1)
    let anchor: CharacterRect
    switch accessory.anchor {
    case .face: anchor = face
    case .eyes: anchor = CharacterGeometry.map(layout.eyes, into: face)
    case .nose: anchor = CharacterGeometry.map(layout.nose, into: face)
    case .mouth: anchor = CharacterGeometry.map(layout.mouth, into: face)
    case .writing: anchor = CharacterGeometry.map(layout.writing, into: face)
    }
    let width = anchor.width * accessory.width
    let height = anchor.height * accessory.height
    let x = anchor.x + anchor.width * accessory.centerX
    let y = anchor.y + anchor.height * accessory.centerY
    let reference = spec.referenceRect
    let cosine = cos(accessory.angle - spec.angle)
    let sine = sin(accessory.angle - spec.angle)
    // Catalog bounds describe the default attachment. Map them into the ACTUAL anchor,
    // scale, position and rotation, exactly as the image placement does.
    return spec.hardOcclusion.map { obstacle in
      let cx = ((obstacle.midX - reference.minX) / reference.width - 0.5) * width
      let cy = ((obstacle.midY - reference.minY) / reference.height - 0.5) * height
      let w = obstacle.width / reference.width * width
      let h = obstacle.height / reference.height * height
      let halfW = (abs(cosine) * w + abs(sine) * h) / 2
      let halfH = (abs(sine) * w + abs(cosine) * h) / 2
      return CharacterRect(
        x: x + cosine * cx - sine * cy - halfW,
        y: y + sine * cx + cosine * cy - halfH,
        width: halfW * 2, height: halfH * 2)
    }
  }

}

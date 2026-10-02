import Foundation

/// The only owner of validation, surface transform, ordering and Scene publication.
/// Geometry emitters never construct or publish a Scene.
enum CharacterSceneCompiler {
  static func compile(
    pose: CharacterPose, input: CharacterAppearanceInput, width: Double, height: Double,
    environment: CharacterDesignEnvironment, includeBackground: Bool,
    overlays: [CharacterAccentPose]
  ) throws -> CharacterScene {
    guard width.isFinite, height.isFinite, CharacterRenderLimits.viewport.contains(width),
      CharacterRenderLimits.viewport.contains(height)
    else { throw CharacterDesignError.invalidViewport(width: width, height: height) }
    if case .art(let direction) = input,
      !direction.components.subtracting(.all).isEmpty {
      throw CharacterDesignError.invalid(path: "components", reason: "unknown component bits")
    }
    try validate(pose: pose, overlays: overlays)
    let appearance = ResolvedCharacterAppearance.resolve(
      input, width: width, height: height, environment: environment)
    let bounds = appearance.bounds
    let surface = pose.surface
    let transform = CharacterSceneTransform.around(
      x: bounds.midX, y: bounds.midY, angle: surface.angle,
      scaleX: surface.scaleX, scaleY: surface.scaleY,
      offsetX: surface.offsetX * bounds.width, offsetY: surface.offsetY * bounds.height)
    let nodes: [CharacterSceneNode]
    switch appearance.payload {
    case .design(let design):
      nodes = CharacterSceneDrawing.emit(
        pose: pose, resolved: design, appearance: appearance, transform: transform,
        width: width, height: height, includeBackground: includeBackground, overlays: overlays)
    case .art(let direction):
      nodes = CharacterArtDrawing.emit(
        pose: pose, direction: direction, appearance: appearance,
        transform: transform, width: width, height: height,
        includeBackground: includeBackground, overlays: overlays)
    }
    var layers: [Int: [CharacterSceneNode]] = [:]
    for node in nodes { layers[node.layer.rawValue, default: []].append(node) }
    let ordered = CharacterSceneLayer.allCases.flatMap { layers[$0.rawValue] ?? [] }
    return try CharacterSceneValidation.validated(CharacterScene(
      width: width, height: height, faceBounds: .init(bounds), surfaceTransform: transform,
      nodes: ordered, effectiveMode: appearance.mode, isCompact: appearance.compact))
  }

  static func validate(pose: CharacterPose, overlays: [CharacterAccentPose]) throws {
    guard overlays.count <= CharacterRenderLimits.maximumOverlayAccents else {
      throw CharacterDesignError.invalidPose(
        "overlayAccents exceeds \(CharacterRenderLimits.maximumOverlayAccents)")
    }
    let surface = pose.surface
    guard
      [
        surface.offsetX, surface.offsetY, surface.scaleX, surface.scaleY, surface.angle,
        pose.motionEnergy, pose.noseOffsetX, pose.writingMotionPhase, pose.writingOpacity,
        pose.mouth.opacity, pose.mouth.intrinsicAspect,
      ].allSatisfy(\.isFinite),
      surface.scaleX > 0, surface.scaleY > 0, pose.mouth.intrinsicAspect > 0
    else { throw CharacterDesignError.invalidPose("surface/mouth/writing") }
    for pair in [pose.eyes, pose.nearTrail, pose.farTrail].compactMap({ $0 }) {
      for eye in [pair.left, pair.right] {
        guard [eye.centerX, eye.centerY, eye.width, eye.height, eye.angle].allSatisfy(\.isFinite),
          eye.width > 0, eye.height > 0
        else { throw CharacterDesignError.invalidPose("eye") }
      }
    }
    for accent in pose.accents + overlays {
      guard
        [accent.centerX, accent.centerY, accent.width, accent.height, accent.angle, accent.opacity]
          .allSatisfy(\.isFinite), accent.width >= 0, accent.height >= 0,
        (-4...5).contains(accent.centerX), (-4...5).contains(accent.centerY),
        accent.width <= 4, accent.height <= 4, (0...1).contains(accent.opacity)
      else { throw CharacterDesignError.invalidPose("accent") }
    }
    if pose.mouth.visible {
      guard let bounds = pose.mouth.vectorBounds, bounds.width > 0, bounds.height > 0 else {
        throw CharacterDesignError.invalidPose("degenerate mouth contour")
      }
    }
    for segment in pose.mouth.contour + pose.mouth.details.flatMap(\.segments) {
      for point in [segment.start, segment.control1, segment.control2, segment.end] {
        guard point.x.isFinite, point.y.isFinite else {
          throw CharacterDesignError.invalidPose("mouth contour")
        }
      }
    }
  }
}

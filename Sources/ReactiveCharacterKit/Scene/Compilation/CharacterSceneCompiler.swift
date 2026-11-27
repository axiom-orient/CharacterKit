import Foundation

/// The only owner of validation, surface transform, ordering and Scene publication.
/// Geometry emitters never construct or publish a Scene.
enum CharacterSceneCompiler {
  private static let motionViewportInset = 0.004

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
    var transform: CharacterSceneTransform
    if case .fullBodyCat(_, let motion) = appearance.payload {
      // Ground the shared surface motion at the artwork's registered contact line.
      // A registered gesture eases out the shared body transform while the face remains live.
      let weight = motion.sharedSurfaceWeight ?? (motion.usesGestureTransform ? 0 : 1)
      transform = weight == 0 ? .identity : CharacterSceneTransform.around(
        x: bounds.midX,
        y: bounds.y + bounds.height * (CharacterFullBodyCatArtwork.groundY / CharacterFullBodyCatArtwork.size),
        angle: surface.angle * 0.42 * weight,
        scaleX: 1 + (surface.scaleX - 1) * 0.65 * weight, scaleY: 1 + (surface.scaleY - 1) * 0.65 * weight,
        offsetX: surface.offsetX * bounds.width * 0.54 * weight,
        offsetY: surface.offsetY * bounds.height * 0.62 * weight)
    } else {
      transform = CharacterSceneTransform.around(
        x: bounds.midX, y: bounds.midY, angle: surface.angle,
        scaleX: surface.scaleX, scaleY: surface.scaleY,
        offsetX: surface.offsetX * bounds.width, offsetY: surface.offsetY * bounds.height)
    }
    let nodes: [CharacterSceneNode]
    let faceBounds: CharacterRect
    switch appearance.payload {
    case .design(let design):
      faceBounds = bounds
      nodes = CharacterSceneDrawing.emit(
        pose: pose, resolved: design, appearance: appearance, transform: transform,
        width: width, height: height, includeBackground: includeBackground, overlays: overlays)
    case .art(let direction):
      faceBounds = bounds
      switch direction.anatomy {
      case .minimal:
        transform = fitMinimalArtTransform(transform, board: bounds, width: width, height: height)
      case .reference(let reference) where transform != .identity:
        // Keep the registered art on stage during motion without changing its neutral size.
        let artwork = CharacterReferenceDrawing.artworkPlacement(for: reference.rig, in: bounds).bounds
        transform = fitArtTransform(
          transform, envelopeCenter: (artwork.midX, artwork.midY),
          envelopeSize: (artwork.width, artwork.height), width: width, height: height,
          margin: min(width, height) * motionViewportInset)
      default:
        break
      }
      nodes = CharacterArtDrawing.emit(
        pose: pose, direction: direction, appearance: appearance,
        transform: transform, width: width, height: height,
        includeBackground: includeBackground, overlays: overlays)
    case .fullBodyCat(let preset, let motion):
      switch preset.style {
      case .felt:
        faceBounds = CharacterFullBodyCatDrawing.faceBounds(for: motion, in: bounds)
        nodes = CharacterFullBodyCatDrawing.nodes(
          pose: pose, appearance: preset, motion: motion, board: bounds, transform: transform)
      case .crayon:
        faceBounds = CharacterCrayonCatDrawing.faceBounds(for: motion, in: bounds)
        nodes = CharacterCrayonCatDrawing.nodes(
          pose: pose, motion: motion, board: bounds, transform: transform, tone: environment.appearance)
      }
    }
    var layers: [Int: [CharacterSceneNode]] = [:]
    for node in nodes { layers[node.layer.rawValue, default: []].append(node) }
    let ordered = CharacterSceneLayer.allCases.flatMap { layers[$0.rawValue] ?? [] }
    return try CharacterSceneValidation.validated(CharacterScene(
      width: width, height: height, faceBounds: .init(faceBounds), surfaceTransform: transform,
      nodes: ordered, effectiveMode: appearance.mode, isCompact: appearance.compact))
  }

  /// Use the same motion envelope for a minimal face and its removable accessories.
  private static func fitMinimalArtTransform(
    _ transform: CharacterSceneTransform, board: CharacterRect, width: Double, height: Double
  ) -> CharacterSceneTransform {
    let envelope = CharacterBuiltInAccessoryCatalog.headset.referenceRect
    let envelopeWidth = envelope.width * board.width
    let envelopeHeight = envelope.height * board.height
    // Layouts without the neutral gutter own their viewport framing.
    let margin = min(width, height) * motionViewportInset
    guard envelopeWidth <= width - 2 * margin, envelopeHeight <= height - 2 * margin else {
      return transform
    }

    return fitArtTransform(
      transform, envelopeCenter: (board.x + envelope.midX * board.width, board.y + envelope.midY * board.height),
      envelopeSize: (envelopeWidth, envelopeHeight),
      width: width, height: height, margin: margin)
  }

  private static func fitArtTransform(
    _ t: CharacterSceneTransform, envelopeCenter: (x: Double, y: Double),
    envelopeSize: (width: Double, height: Double), width: Double, height: Double,
    margin: Double
  ) -> CharacterSceneTransform {
    let centerX = width / 2
    let centerY = height / 2
    let reachX = abs(t.a * envelopeCenter.x + t.c * envelopeCenter.y + t.tx - centerX)
      + (abs(t.a) * envelopeSize.width + abs(t.c) * envelopeSize.height) / 2
    let reachY = abs(t.b * envelopeCenter.x + t.d * envelopeCenter.y + t.ty - centerY)
      + (abs(t.b) * envelopeSize.width + abs(t.d) * envelopeSize.height) / 2
    let scale = min(1, (centerX - margin) / reachX, (centerY - margin) / reachY)
    guard scale < 1 else { return t }
    let fit = CharacterSceneTransform.around(x: centerX, y: centerY, scaleX: scale, scaleY: scale)
    return fit.concatenating(t)
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
        pose.mouth.opacity, pose.mouth.openness, pose.mouth.width,
        pose.mouth.curvature, pose.mouth.skew, pose.mouth.waveBlendWeight,
      ].allSatisfy(\.isFinite),
      surface.scaleX > 0, surface.scaleY > 0, pose.mouth.width >= 0
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
  }
}

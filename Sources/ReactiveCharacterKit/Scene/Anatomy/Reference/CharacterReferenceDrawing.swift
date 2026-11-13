import Foundation

/// Adapts the shared final pose to source-space part transforms. It does not interpret events,
/// read files, keep a timer, or derive emotion a second time. Both backends consume these nodes.
struct CharacterReferenceDrawing {
  private static let rest = ReactiveCharacter.pose(
    state: .idle, elapsed: 0, reduceMotion: true, projection: .flat, motionProfile: .cartoon)

  static func nodes(
    pose: CharacterPose, direction: CharacterArtDirection,
    appearance: CharacterReferenceAppearance, board: CharacterRect,
    transform: CharacterSceneTransform, includeBackground: Bool
  ) -> [CharacterSceneNode] {
    let rig = appearance.rig
    let scale = min(board.width / rig.width, board.height / rig.height)
    let placement = CharacterSceneTransform(
      a: scale, b: 0, c: 0, d: scale,
      tx: board.midX - rig.width * scale / 2, ty: board.midY - rig.height * scale / 2)
    let whole = CharacterRect(x: 0, y: 0, width: rig.width, height: rig.height)
    let base = transform.concatenating(placement)
    var result: [CharacterSceneNode] = []

    func image(
      _ id: String, asset: CharacterImageAsset, layer: CharacterSceneLayer,
      local: CharacterSceneTransform = .identity, opacity: Double = 1,
      clips: [CharacterVectorPath] = [], background: Bool = false
    ) {
      guard opacity > 0 else { return }
      result.append(.init(
        id: id, layer: layer, path: .init(), fill: nil, stroke: nil, lineWidth: 0,
        opacity: opacity,
        transform: (background ? placement : base).concatenating(local), clips: clips,
        image: .init(asset: asset, bounds: .init(whole), contentMode: .fit)))
    }

    if includeBackground, direction.assets.background == nil {
      image(
        "reference.background", asset: .init(
          uncheckedName: "reference-\(rig.id.rawValue)-backdrop", source: .package),
        layer: .background, background: true)
    }
    for part in rig.layers {
      guard let asset = appearance.asset(for: part) else { continue }
      let id = "reference.\(part.part.rawValue)"
      switch part.part {
      case .body:
        guard direction.surface == .visible else { continue }
        image(id, asset: asset, layer: .surface)
      case .headsetShell, .headsetMetal, .headsetCushions, .headsetLight:
        guard direction.components.contains(.accessories) else { continue }
        image(id, asset: asset, layer: .behindFeatures)
      case .eyeLeft, .eyeRight:
        guard direction.components.contains(.eyes) else { continue }
        let eye = part.part.isLeft ? pose.eyes.left : pose.eyes.right
        let neutral = part.part.isLeft ? rest.eyes.left : rest.eyes.right
        let contour = part.part.isLeft ? pose.eyeContours.left : pose.eyeContours.right
        let gazeX = bounded(pose.face.gazeX / CharacterReferenceMotionPolicy.maximumGazeX)
        let gazeY = bounded(pose.face.gazeY / CharacterReferenceMotionPolicy.maximumGazeY)
        let blinkScale = max(CharacterReferenceMotionPolicy.minimumEyeScale, 1 - eye.blink)
        let shapeScale = min(CharacterReferenceMotionPolicy.maximumEyeScale,
          max(0.35, eye.unblinkedHeight / max(0.001, neutral.unblinkedHeight)))
        let scaleY = blinkScale * shapeScale
        let scaleX = min(1.15, max(0.8, eye.unblinkedWidth / max(0.001, neutral.unblinkedWidth)))
        let travel = CharacterReferenceMotionPolicy.eyeTravelFraction
        let local = CharacterSceneTransform.around(
          x: part.pivotX, y: part.pivotY, angle: eye.angle - neutral.angle,
          scaleX: scaleX, scaleY: scaleY,
          offsetX: gazeX * part.frame.width * travel,
          offsetY: gazeY * part.frame.height * travel)
        let hasSpecialShape = contour.heart > 0.01 || contour.crescent > 0.01
          || contour.chevron > 0.01 || contour.innerPinch > 0.01
        let procedural = direction.style.eyeTreatment != .vertical || hasSpecialShape
        if procedural {
          let frame = eyeFrame(part.frame, treatment: direction.style.eyeTreatment)
          result.append(.init(
            id: id + ".shape", layer: .features,
            path: CharacterEyeGeometry.path(contour, in: frame, left: part.part.isLeft),
            fill: .solid(direction.style.partColors.eyes), stroke: nil, lineWidth: 0,
            opacity: 1, transform: base.concatenating(local), clips: []))
        } else {
          image(id, asset: asset, layer: .features, local: local)
        }
      case .mouth:
        guard direction.components.contains(.mouth) else { continue }
        if !pose.mouth.visible || pose.mouth.opacity <= 0 {
          image(id, asset: asset, layer: .features)
        } else {
          // Reference mouth blends out as shared articulation blends in. No emotion switch here.
          image(id, asset: asset, layer: .features, opacity: 1 - pose.mouth.opacity)
          let region = CharacterRect(
            x: part.frame.midX - part.frame.width * 0.7,
            y: part.frame.midY - part.frame.height * 0.7,
            width: part.frame.width * 1.4, height: part.frame.height * 1.6)
          let paths = CharacterMouthGeometry.paths(for: pose.mouth, in: whole, region: region)
          let colors = direction.style.partColors
          let fill: CharacterScenePaint? = direction.style.mouthTreatment == .outline
            ? nil : .solid(paths.fill(light: colors.mouth, dark: colors.surface))
          result.append(.init(
            id: id + ".articulated", layer: .features, path: paths.outer,
            fill: fill, stroke: colors.mouth, lineWidth: max(0.7, part.frame.width * 0.045),
            opacity: pose.mouth.opacity, transform: base, clips: []))
          // The shared numeric rig already includes articulation opacity in its details.
          result.append(.init(
            id: id + ".teeth", layer: .features, path: paths.teeth,
            fill: .solid(colors.mouthDetail), stroke: nil, lineWidth: 0,
            opacity: paths.detailOpacity, transform: base,
            clips: [paths.outer]))
          result.append(.init(
            id: id + ".tongue", layer: .features, path: paths.tongue,
            fill: .solid(colors.tongue), stroke: nil, lineWidth: 0,
            opacity: paths.tongueOpacity, transform: base,
            clips: [paths.outer]))
        }
      }
    }
    return result
  }

  private static func bounded(_ value: Double) -> Double { min(1, max(-1, value)) }

  private static func eyeFrame(
    _ frame: CharacterRect, treatment: CharacterEyeTreatment
  ) -> CharacterRect {
    let width: Double
    let height: Double
    switch treatment {
    case .vertical:
      width = frame.width * 0.84
      height = frame.height * 0.88
    case .horizontal:
      width = min(frame.width * 1.1, frame.height * 0.8)
      height = frame.width * 0.48
    case .round:
      width = min(frame.width, frame.height) * 0.88
      height = width
    }
    return .init(x: frame.midX - width / 2, y: frame.midY - height / 2,
      width: width, height: height)
  }
}

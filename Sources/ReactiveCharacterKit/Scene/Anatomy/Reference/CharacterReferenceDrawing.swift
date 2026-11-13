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
      case .body, .mane, .earLeft, .earRight:
        guard direction.surface == .visible else { continue }
        var local = CharacterSceneTransform.identity
        let stage: CharacterSceneLayer = part.part == .body ? .surface : .behindSurface
        if part.part == .earLeft || part.part == .earRight {
          let left = part.part.isLeft
          let contour = left ? pose.eyeContours.left : pose.eyeContours.right
          let sign = left ? -1.0 : 1.0
          let desired = sign * (contour.lidCompression * 0.08 + contour.innerPinch * 0.10
            - contour.circular * 0.05) + pose.face.gazeX * 0.12
          let limit = CharacterReferenceMotionPolicy.maximumEarAngle
          local = .around(x: part.pivotX, y: part.pivotY, angle: min(limit, max(-limit, desired)))
          // A fixed, source-authored root covers the seam while only the pinna rotates.
          image(
            id + ".root", asset: asset, layer: stage,
            clips: [.rectangle(.init(
              x: 0, y: part.pivotY - CharacterReferenceMotionPolicy.earRootOverlap,
              width: whole.width, height: whole.height - part.pivotY
                + CharacterReferenceMotionPolicy.earRootOverlap))])
        }
        image(id, asset: asset, layer: stage, local: local)
      case .headsetShell, .headsetMetal, .headsetCushions, .headsetLight:
        guard direction.components.contains(.accessories) else { continue }
        image(id, asset: asset, layer: .behindFeatures)
      case .eyeLeft, .eyeRight, .irisLeft, .irisRight:
        guard direction.components.contains(.eyes) else { continue }
        let eye = part.part.isLeft ? pose.eyes.left : pose.eyes.right
        let neutral = part.part.isLeft ? rest.eyes.left : rest.eyes.right
        let contour = part.part.isLeft ? pose.eyeContours.left : pose.eyeContours.right
        if appearance.isCat {
          result += catEyeNodes(part: part, asset: asset, pose: pose,
            treatment: direction.style.eyeTreatment, whole: whole, base: base)
          continue
        }
        let gazeX = bounded(pose.face.gazeX / CharacterReferenceMotionPolicy.maximumGazeX)
        let gazeY = bounded(pose.face.gazeY / CharacterReferenceMotionPolicy.maximumGazeY)
        let blinkScale = max(CharacterReferenceMotionPolicy.minimumEyeScale, 1 - eye.blink)
        let shapeScale = min(CharacterReferenceMotionPolicy.maximumEyeScale,
          max(0.35, eye.unblinkedHeight / max(0.001, neutral.unblinkedHeight)))
        let scaleY = blinkScale * shapeScale
        let scaleX = min(1.15, max(0.8, eye.unblinkedWidth / max(0.001, neutral.unblinkedWidth)))
        // Cat sockets/irises were handled above; this path owns only the round mascot eyes.
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
      case .nose:
        guard direction.components.contains(.nose) else { continue }
        image(id, asset: asset, layer: .features)
      case .mouth:
        guard direction.components.contains(.mouth) else { continue }
        if appearance.isCat, pose.mouth.visible, pose.mouth.opacity > 0 {
          image(id, asset: asset, layer: .features, opacity: 1 - pose.mouth.opacity)
          result += catMouthNodes(frame: part.frame, mouth: pose.mouth, transform: base,
            colors: direction.style.partColors)
          continue
        }
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

  private static func catEyeNodes(
    part: CharacterReferenceRig.Layer, asset: CharacterImageAsset,
    pose: CharacterPose, treatment: CharacterEyeTreatment,
    whole: CharacterRect, base: CharacterSceneTransform
  ) -> [CharacterSceneNode] {
    let frame = part.frame
    // The source body has painted-over eye sockets, not usable eyelid artwork.
    // Keep the authored socket intact in every expression; clipping it to a cartoon
    // aperture reveals those unfinished pixels. Gaze moves only the iris inside it.
    var bounds = whole
    var local = CharacterSceneTransform.identity
    if part.part.isIris {
      bounds = .init(
        x: bounded(pose.face.gazeX / CharacterReferenceMotionPolicy.maximumGazeX)
          * frame.width * CharacterReferenceMotionPolicy.catIrisTravelFraction,
        y: bounded(pose.face.gazeY / CharacterReferenceMotionPolicy.maximumGazeY)
          * frame.height * CharacterReferenceMotionPolicy.catIrisTravelFraction,
        width: whole.width, height: whole.height)
      let shape: (Double, Double) = switch treatment {
      case .vertical: (1, 1)
      case .round: (1, 0.90)
      case .horizontal: (1.04, 0.80)
      }
      local = .around(x: frame.midX, y: frame.midY, scaleX: shape.0, scaleY: shape.1)
    }
    return [.init(id: "reference.\(part.part.rawValue)", layer: .features,
      path: .init(), fill: nil, stroke: nil, lineWidth: 0, opacity: 1,
      transform: base.concatenating(local), clips: [.rectangle(frame)],
      image: .init(asset: asset, bounds: .init(bounds), contentMode: .fit))]
  }

  private static func catMouthNodes(
    frame: CharacterRect, mouth: CharacterMouthPose, transform: CharacterSceneTransform,
    colors: CharacterPartColors
  ) -> [CharacterSceneNode] {
    let x = frame.midX + mouth.skew * frame.width * 0.08
    let y = frame.y + frame.height * 0.14
    let width = frame.width * min(0.33, max(0.20, mouth.width * 0.40))
    // Scene coordinates grow downward: positive expression curvature lifts the
    // corners, while negative curvature lowers them for a frown.
    let bend = -mouth.curvature * frame.height * 0.15
    let controlY = y + frame.height * (0.18 - max(0, -mouth.curvature) * 0.30)
    var outline = CharacterVectorPath()
    outline.move(x, frame.y - frame.height * 0.05)
    outline.line(x, y)
    outline.move(x - width, y + bend)
    outline.quad(x - width * 0.45, controlY, x, y)
    outline.quad(x + width * 0.45, controlY,
      x + width, y + bend)
    var nodes: [CharacterSceneNode] = []
    if mouth.openness > 0.06 {
      let halfOpening = width * 0.38
      let depth = frame.height * min(0.32, mouth.openness * 0.55)
      var opening = CharacterVectorPath()
      opening.move(x - halfOpening, y)
      opening.quad(x, y + depth * 0.20, x + halfOpening, y)
      opening.quad(x + halfOpening * 0.75, y + depth, x, y + depth)
      opening.quad(x - halfOpening * 0.75, y + depth, x - halfOpening, y)
      opening.close()
      nodes.append(.init(id: "reference.mouth.open", layer: .features,
        path: opening, fill: .solid(colors.mouth), stroke: nil, lineWidth: 0,
        opacity: mouth.opacity, transform: transform, clips: []))
    }
    nodes.append(CharacterSceneNode(id: "reference.mouth.articulated", layer: .features,
      path: outline, fill: nil, stroke: colors.mouth, lineWidth: max(0.55, frame.width * 0.013),
      opacity: mouth.opacity, transform: transform, clips: []))
    return nodes
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

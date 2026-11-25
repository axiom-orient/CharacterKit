/// The registered source artwork and its live features share a 256-point stage.
struct CharacterFullBodyCatDrawing {
  let pose: CharacterPose
  let bodyTransform: CharacterSceneTransform
  let faceTransform: CharacterSceneTransform
  let pixelScale: Double
  let featureOpacity: Double
  var nodes: [CharacterSceneNode] = []

  static func nodes(
    pose: CharacterPose, appearance _: CharacterFullBodyCatAppearance,
    motion: CharacterFullBodyCatMotion, board: CharacterRect, transform: CharacterSceneTransform
  ) -> [CharacterSceneNode] {
    let artwork = CharacterFullBodyCatArtwork.resolve(motion.pose)
    let inBetween = motion.transition?.frameAsset
    let legRig = motion.hasLegMotion && (!motion.hasFeltFootfall || motion.walkStrength > 0) ? artwork.walk : nil
    let face = registeredFace(for: motion, artwork: artwork)
    let registration = registration(in: board)
    let composed = CharacterFullBodyCatStage.place(motion, on: transform.concatenating(registration))
    let bodyImage = motion.mirrorsPuff ? composed.concatenating(.around(
      x: CharacterFullBodyCatArtwork.centerX, y: 0, scaleX: -1)) : composed
    let head =
      face.map { face in
        composed.concatenating(
          .around(
            x: face.bounds.midX, y: face.bounds.midY,
            angle: min(0.035, max(-0.035, motion.headAngle))))
      } ?? composed
    var drawing = Self(
      pose: pose, bodyTransform: bodyImage, faceTransform: head, pixelScale: registration.a,
      featureOpacity: inBetween == nil ? 1 : (motion.transition?.faceOpacity ?? 1))
    if let inBetween {
      drawing.image("body", inBetween, layer: .surface, transform: composed)
      if let face {
        drawing.drawFeatures(face, usesApplique: registration.a >= 0.75, turn: motion.transition?.faceTurn)
      }
    } else {
      drawing.draw(artwork, rig: legRig, face: face, motion: motion)
    }
    return drawing.nodes
  }

  static func faceBounds(for motion: CharacterFullBodyCatMotion, in board: CharacterRect) -> CharacterRect {
    let face = registeredFace(for: motion, artwork: CharacterFullBodyCatArtwork.resolve(motion.pose))
    guard let bounds = face?.bounds else { return board }
    let transform = registration(in: board)
    return .init(
      x: bounds.x * transform.a + transform.tx,
      y: bounds.y * transform.d + transform.ty, width: bounds.width * transform.a,
      height: bounds.height * transform.d)
  }

  private static func registeredFace(
    for motion: CharacterFullBodyCatMotion, artwork: CharacterFullBodyCatArtwork
  ) -> CharacterFullBodyCatArtwork.Face? {
    if let face = motion.transition?.face { return face }
    return motion.mirrorsPuff ? artwork.face?.mirrored : artwork.face
  }

  private static func registration(in board: CharacterRect) -> CharacterSceneTransform {
    let scale = min(board.width, board.height) / CharacterFullBodyCatArtwork.size
    return CharacterSceneTransform(
      a: scale, b: 0, c: 0, d: scale,
      tx: board.midX - CharacterFullBodyCatArtwork.centerX * scale,
      ty: board.midY - CharacterFullBodyCatArtwork.centerX * scale)
  }

  private mutating func draw(
    _ artwork: CharacterFullBodyCatArtwork, rig: CharacterFullBodyCatArtwork.Walk?,
    face: CharacterFullBodyCatArtwork.Face?, motion: CharacterFullBodyCatMotion
  ) {
    #if os(iOS) || os(macOS)
      if let rig, let feltWalk = CharacterFeltWalkSurface(motion: motion, rig: rig) {
        image("body", artwork.body, layer: .surface, transform: bodyTransform, feltWalk: feltWalk)
        if let face { drawFeatures(face, usesApplique: pixelScale >= 0.75) }
        return
      }
    #endif
    if let tail = artwork.tail {
      image(
        "tail", tail.asset, layer: .behindSurface,
        transform: bodyTransform.concatenating(
          .around(
            x: tail.pivot.x, y: tail.pivot.y, angle: motion.tailAngle)), clip: tail.clip)
    }
    if let rig {
      let direction: Double = motion.pose == .right ? 1 : -1
      for leg in rig.legs {
        let stride = motion.step(for: leg.id).transform(
          hip: leg.art.pivot, foot: leg.foot, direction: direction)
        image(
          leg.name, leg.art.asset, layer: .behindSurface,
          transform: bodyTransform.concatenating(stride), clip: leg.art.clip)
      }
    }
    image("body", rig?.torso ?? artwork.body, layer: .surface,
      transform: bodyTransform, clip: rig?.torsoClip)
    if let face { drawFeatures(face, usesApplique: pixelScale >= 0.75) }
    if let paw = artwork.paw {
      image(
        "paw.wave", paw.asset, layer: .foreground,
        transform: bodyTransform.concatenating(
          .around(
            x: paw.pivot.x, y: paw.pivot.y, angle: motion.pawAngle)))
    }
  }

  private mutating func image(
    _ id: String, _ asset: CharacterImageAsset, layer: CharacterSceneLayer,
    transform: CharacterSceneTransform, clip: CharacterVectorPath? = nil,
    feltWalk: CharacterFeltWalkSurface? = nil
  ) {
    nodes.append(
      .init(
        id: "full-body-cat.\(id)", layer: layer, path: .init(), fill: nil, stroke: nil,
        lineWidth: 0, opacity: 1, transform: transform, clips: clip.map { [$0] } ?? [],
        image: .init(
          asset: asset, bounds: .init(CharacterFullBodyCatArtwork.canvas), contentMode: .fit,
          feltWalk: feltWalk)))
  }

  mutating func feature(
    _ id: String, _ path: CharacterVectorPath, fill: CharacterScenePaint? = nil,
    stroke: CharacterColor? = nil, lineWidth: Double = 0,
    local: CharacterSceneTransform = .identity
  ) {
    nodes.append(
      .init(
        id: "full-body-cat.\(id)", layer: .features, path: path, fill: fill, stroke: stroke,
        lineWidth: lineWidth, opacity: featureOpacity, transform: faceTransform.concatenating(local), clips: []))
  }
}

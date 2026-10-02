import Foundation

/// Consumes the same resolved pose as the round face and cat. No clock, I/O or semantic switches.
struct CharacterPortraitDrawing {
  let pose: CharacterPose
  let direction: CharacterArtDirection
  let style: CharacterPortraitStyle
  let transform: CharacterSceneTransform
  let simplified: Bool
  var nodes: [CharacterSceneNode] = []

  typealias G = CharacterPortraitGeometry
  var featureLayout: CharacterPortraitFeatureLayout { .resolve(style) }

  static func nodes(
    pose: CharacterPose, direction: CharacterArtDirection, style: CharacterPortraitStyle,
    board: CharacterRect, transform: CharacterSceneTransform, simplified: Bool
  ) -> [CharacterSceneNode] {
    let source = CharacterPortraitFeatureLayout.sourceBounds(for: style)
    let scale = min(board.width / source.width, board.height / source.height)
    let local = CharacterSceneTransform(
      a: scale, b: 0, c: 0, d: scale,
      tx: board.midX - source.midX * scale, ty: board.midY - source.midY * scale)
    var drawing = Self(
      pose: pose, direction: direction, style: style,
      transform: transform.concatenating(local), simplified: simplified)
    drawing.draw()
    return drawing.nodes
  }

  var gazeX: Double { G.clamp(pose.face.gazeX / 0.23, -1, 1) }
  var gazeY: Double { G.clamp(pose.face.gazeY / 0.24, -1, 1) }
  var ink: CharacterColor { direction.style.partColors.outline }

  mutating func draw() {
    if direction.surface == .visible { drawHead() }
    if direction.components.contains(.eyes) {
      drawEye(left: true)
      drawEye(left: false)
      drawBrow(left: true)
      drawBrow(left: false)
    }
    if direction.components.contains(.mouth) { drawMouth() }
    if direction.components.contains(.nose) {
      var nose = CharacterVectorPath()
      let center = featureLayout.nose
      let unit = featureLayout.expressionScale
      nose.move(center.x + 2 * unit, center.y)
      nose.quad(center.x + 4 * unit, center.y + 5 * unit, center.x - unit, center.y + 6 * unit)
      add("nose", nose, stroke: direction.style.partColors.nose, width: 2.5 * unit, clips: faceFeatureClips)
    }
    if direction.components.contains(.accessories) {
      drawEyewear()
      if direction.surface == .visible { drawHairAccessory() }
    }
  }

  private mutating func drawHead() {
    switch style.head {
    case .boy(let viewpoint): drawBoyHead(viewpoint)
    case .classic(let hairstyle): drawClassicHead(hairstyle)
    }
  }

  private mutating func drawClassicHead(_ hairstyle: CharacterPortraitStyle.ClassicHairstyle) {
    let skin = direction.style.partColors.surface
    add(
      "portrait.hair.back", G.backHair(hairstyle), layer: .behindSurface,
      fill: .solid(style.hairColor))
    // Ears belong to the shared face, not to either hair preset.
    for left in [true, false] {
      add(
        left ? "portrait.ear.left" : "portrait.ear.right",
        .ellipse(.init(x: left ? 78 : 404, y: 335, width: 30, height: 48)),
        layer: .behindSurface, fill: .solid(skin), stroke: ink, width: G.faceLineWidth)
    }
    var shoulder = CharacterVectorPath()
    shoulder.move(199, 425)
    shoulder.cubic(156, 439, 130, 481, 117, 536)
    shoulder.line(395, 536)
    shoulder.cubic(382, 481, 356, 439, 313, 425)
    shoulder.close()
    add(
      "portrait.shoulders", shoulder, layer: .behindSurface,
      fill: .solid(direction.style.partColors.accent), stroke: ink, width: G.faceLineWidth)
    var neck = CharacterVectorPath()
    neck.move(219, 411)
    neck.line(293, 411)
    neck.line(296, 447)
    neck.quad(256, 478, 216, 447)
    neck.close()
    add(
      "portrait.neck", neck, layer: .behindSurface, fill: .solid(skin), stroke: ink,
      width: G.faceLineWidth)
    var collar = CharacterVectorPath()
    collar.move(195, 428)
    collar.line(216, 428)
    collar.line(256, 461)
    collar.line(296, 428)
    collar.line(317, 428)
    collar.quad(309, 465, 286, 485)
    collar.line(256, 461)
    collar.line(226, 485)
    collar.quad(203, 465, 195, 428)
    collar.close()
    add(
      "portrait.collar", collar, layer: .behindSurface, fill: .solid(direction.style.partColors.clothingDetail), stroke: ink,
      width: G.faceLineWidth)
    var trim = CharacterVectorPath()
    trim.move(219, 485)
    trim.line(256, 527)
    trim.line(293, 485)
    trim.move(230, 483)
    trim.line(256, 511)
    trim.line(282, 483)
    add("portrait.uniform.trim", trim, layer: .behindSurface, stroke: ink, width: 4)
    for left in [true, false] {
      let x = left ? 125.0 : 387.0
      let sign = left ? 1.0 : -1.0
      var hand = CharacterVectorPath()
      hand.move(x - sign * 14, 536)
      hand.cubic(x - sign * 12, 500, x + sign * 23, 503, x + sign * 29, 536)
      hand.close()
      add(
        left ? "portrait.hand.left" : "portrait.hand.right", hand,
        layer: .behindSurface, fill: .solid(skin), stroke: ink, width: 4)
      var cuff = CharacterVectorPath()
      cuff.move(x - sign * 9, 517)
      cuff.quad(x + sign * 11, 511, x + sign * 25, 532)
      add(
        left ? "portrait.cuff.left" : "portrait.cuff.right", cuff,
        layer: .behindSurface, stroke: ink, width: 3)
    }
    add(
      "portrait.face", G.face, layer: .surface, fill: .solid(skin), stroke: ink,
      width: G.faceLineWidth)
    add(
      "portrait.hair.fringe", G.fringe(hairstyle), layer: .surface,
      fill: .solid(style.hairColor))
  }

  private mutating func drawEye(left: Bool) {
    let source = left ? pose.eyes.left : pose.eyes.right
    let contour = (left ? pose.eyeContours.left : pose.eyeContours.right)
      .presentingSmile(as: direction.style.smileEyeShape)
    let frame = left ? featureLayout.left : featureLayout.right
    let x = frame.center.x + gazeX * G.gazeTravelX * featureLayout.expressionScale
    let y = frame.center.y + gazeY * G.gazeTravelY * featureLayout.expressionScale
    let id = left ? "eye.left" : "eye.right"
    add(
      id,
      CharacterCompactEyeGeometry.path(
        eye: source, contour: contour, left: left, center: .init(x: x, y: y),
        width: frame.width, height: frame.height, treatment: direction.style.eyeTreatment,
        thickness: 5.5 * featureLayout.expressionScale, oval: true,
        expressionWidth: G.expressionWidth * frame.width / G.eyeWidth),
      fill: .solid(direction.style.partColors.eyes), clips: faceFeatureClips)
  }

  private mutating func drawBrow(left: Bool) {
    let brow = left ? pose.brows.left : pose.brows.right
    // Brows are expression channels, not gaze channels. Keeping their anchor fixed prevents
    // the whole face from "swimming" when only attention changes.
    let frame = left ? featureLayout.left : featureLayout.right
    let x = frame.brow.x
    let y = frame.brow.y - brow.lift * G.browLiftTravel * featureLayout.expressionScale
    let half = frame.browHalfWidth
    let bend = brow.bend * G.browBendTravel * featureLayout.expressionScale
    var path = CharacterVectorPath()
    if style.boyViewpoint != nil {
      // Tapered ink silhouette rather than a uniform-width stroke; semantic bend/lift are shared.
      let arch = featureLayout.browArch
      path.move(x - half, y + 2)
      path.cubic(x - half * 0.56, y - arch - bend, x + half * 0.55, y - arch + 1 - bend, x + half, y)
      path.quad(x + half + 1, y + 3, x + half - 3, y + 3)
      path.quad(x, y - 2 - bend * 0.15, x - half, y + 4)
      path.close()
      let rotation = CharacterSceneTransform.around(x: x, y: y, angle: brow.angle)
      // Rotate the ink, not the face clipping boundary. Hair must stay stationary.
      path = path.mapped { point in
        .init(
          x: rotation.a * point.x + rotation.c * point.y + rotation.tx,
          y: rotation.b * point.x + rotation.d * point.y + rotation.ty)
      }
      add(
        left ? "eyebrow.left" : "eyebrow.right", path,
        fill: .solid(direction.style.partColors.brows), clips: faceFeatureClips)
    } else {
      path.move(x - half, y)
      path.quad(x, y - G.neutralBrowRise - bend, x + half, y)
      add(
        left ? "eyebrow.left" : "eyebrow.right", path,
        stroke: direction.style.partColors.brows, width: G.browLineWidth,
        local: .around(x: x, y: y, angle: brow.angle))
    }
  }

  private mutating func drawMouth() {
    // The portrait keeps lower-face placement fixed. Gaze is isolated to the eyes while the
    // common mouth pose still owns curvature, openness, width and speech articulation.
    let mouthColor = direction.style.partColors.mouth
    let active = pose.mouth.visible ? G.clamp(pose.mouth.opacity) : 0
    let x = featureLayout.mouth.x
    let y = featureLayout.mouth.y
    let open = G.clamp(pose.mouth.openness * active)
    let curve = G.clamp(pose.mouth.curvature * active, -1, 1)
    let half = featureLayout.mouthHalfWidth
      + G.clamp((pose.mouth.width - 0.68) * active, -0.3, 0.3) * 12 * featureLayout.expressionScale
    let skew = G.clamp(pose.mouth.skew * active, -1, 1) * 4 * featureLayout.expressionScale

    // Both lips open around a fixed anchor. A neutral open mouth is an O, not a smile.
    // At rest the same topology becomes a small closed line, with no threshold pop.
    let drop = curve * 14 * featureLayout.expressionScale
    let upper = drop - open * 25 * featureLayout.expressionScale * (1 - max(0, curve) * 0.85)
    let lower = drop + open * 32 * featureLayout.expressionScale
    var p = CharacterVectorPath()
    p.move(x - half, y - skew)
    p.cubic(x - half, y + upper, x + half, y + upper, x + half, y + skew)
    p.cubic(x + half, y + lower, x - half, y + lower, x - half, y - skew)
    p.close()
    add(
      "mouth", p,
      fill: direction.style.mouthTreatment == .filled ? .solid(mouthColor) : nil,
      stroke: mouthColor, width: featureLayout.mouthLineWidth, clips: faceFeatureClips)
  }

  mutating func add(
    _ id: String, _ path: CharacterVectorPath, layer: CharacterSceneLayer = .features,
    fill: CharacterScenePaint? = nil, stroke: CharacterColor? = nil,
    width: Double = 0, opacity: Double = 1,
    local: CharacterSceneTransform = .identity, clips: [CharacterVectorPath] = []
  ) {
    nodes.append(
      .init(
        id: id, layer: layer, path: path, fill: fill, stroke: stroke,
        lineWidth: width * direction.style.lineWidth / CharacterStyle.portrait.lineWidth,
        opacity: opacity, transform: transform.concatenating(local), clips: clips))
  }
}

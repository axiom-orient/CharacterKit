import Foundation

/// A drawing adapter, not a second semantic/motion engine. All motion is sampled by CharacterPose.
/// Texture coordinates retain the supplied 512px registration; the rig reserves optical padding for the shared recoil overshoot.
struct CharacterSEMIDrawing {
  // Authored geometry extent plus motion-safe padding; not a second contentInset policy.
  // A modest world-space reserve keeps the perked ear tips inside the viewport at the peak
  // surprise pose while preserving one shared head/ear/face transform across the whole acting arc.
  private static let opticalExtent = 384.0
  let pose: CharacterPose
  let transform: CharacterSceneTransform
  let simplified: Bool
  let expressionRig: CharacterSEMIExpressionRig
  var nodes: [CharacterSceneNode] = []

  static func nodes(
    pose: CharacterPose, board: CharacterRect,
    transform: CharacterSceneTransform, simplified: Bool
  ) -> [CharacterSceneNode] {
    let scale = min(board.width, board.height) / opticalExtent
    // Reserve top-edge room by moving the complete drawing frame together, not clipping the ears.
    let registration = CharacterSceneTransform(
      a: scale, b: 0, c: 0, d: scale,
      tx: board.midX - 256 * scale, ty: board.midY - 256 * scale + 8 * scale)
    var drawing = Self(pose: pose,
      transform: transform.concatenating(registration), simplified: simplified,
      expressionRig: .init(pose: pose))
    drawing.draw()
    return drawing.nodes
  }

  var colors: CharacterSEMIPalette { CharacterSEMIStyle.palette }
  var gazeX: Double { min(1, max(-1, pose.face.gazeX / 0.23)) }
  var gazeY: Double { min(1, max(-1, pose.face.gazeY / 0.24)) }
  var mouthArticulation: Double { expressionRig.mouthArticulation }
  var mouthCurvature: Double { expressionRig.mouthCurvature }
  var mouthOpenness: Double { expressionRig.mouthOpenness }
  var mouthWidth: Double { expressionRig.mouthWidth }
  var mouthSkew: Double { expressionRig.mouthSkew }
  var pixelScale: Double {
    let value = hypot(transform.a, transform.b)
    return value.isFinite && value > 0.000_001 ? value : 1
  }
  func readableStrokeWidth(_ designWidth: Double, minimumPixels: Double = 1.05) -> Double {
    min(12, max(designWidth, minimumPixels / pixelScale))
  }
  var whole: CharacterRect { .init(x: 0, y: 0, width: 512, height: 512) }
  var document: CharacterRect { .init(x: 211, y: 310, width: 87, height: 88) }
  var documentTransform: CharacterSceneTransform {
    let writing = writingIntensity
    let wave = sin(pose.writingMotionPhase * 2 * .pi)
    let pressure = writingSweep * writing
    return .around(x: 255, y: 355,
      angle: -pose.surface.angle * 0.18 - writing * 0.092 + wave * pressure * 0.020,
      offsetX: writing * 3.8 + wave * pressure * 1.6,
      offsetY: writing * 4.8 + pressure * 1.2)
  }

  var writingIntensity: Double {
    pose.writingVisible ? bounded(pose.writingOpacity, lower: 0, upper: 1) : 0
  }

  var writingSweep: Double {
    0.5 - 0.5 * cos(pose.writingMotionPhase * 2 * .pi)
  }

  func actingLocal(_ local: CharacterSceneTransform = .identity) -> CharacterSceneTransform {
    headActingTransform.concatenating(local)
  }

  mutating func draw() {
    body()
    eye(left: true)
    eye(left: false)
    nose()
    mouth()
    heldDocument()
    if pose.writingVisible { writing() }
    paws()
  }

  private mutating func body() {
    let rig = expressionRig
    image("tail", CharacterSEMIStyle.tail, layer: .behindSurface,
      local: .around(x: 326, y: 390,
        angle: min(0.42, max(-0.42,
          -pose.surface.angle * 1.30 + gazeX * 0.10 + rig.tailAngle + rig.communication * 0.10
            - writingIntensity * 0.060)),
        scaleX: rig.tailScaleX, scaleY: rig.tailScaleY,
        offsetX: rig.tailOffsetX + pose.surface.offsetX * 18 - writingIntensity * 2.0,
        offsetY: rig.tailOffsetY + pose.surface.offsetY * 30 + writingIntensity * 4.0))
    let torso = CharacterVectorPath.ellipse(.init(x: 177, y: 269, width: 155, height: 151))
    add("body", torso, layer: .behindSurface, fill: material(colors.surface,
      top: .init(x: 226, y: 288), bottom: .init(x: 279, y: 420)))
    for left in [true, false] {
      let x = left ? 208.0 : 292.0
      let sign = left ? -1.0 : 1.0
      add(left ? "foot.left" : "foot.right",
        .ellipse(.init(x: x - 29, y: 391, width: 58, height: 33)),
        layer: .behindSurface, fill: material(colors.surface,
          top: .init(x: x - 10, y: 393), bottom: .init(x: x + 10, y: 424)),
        local: .around(x: x, y: 401, angle: sign * pose.surface.angle * 0.25))
      let contour = left ? pose.eyeContours.left : pose.eyeContours.right
      let baseAngle = min(0.18, max(-0.18,
        sign * (contour.lidCompression * 0.12 + contour.innerPinch * 0.10
          - contour.circular * 0.07) + gazeX * 0.05 + pose.surface.angle * 0.10))
      let angle = rig.earAngle(left: left, base: baseAngle)
      // The right texture is authored four registered pixels farther out than the left one.
      // Use each cut edge's midpoint so both attachment roots land symmetrically on the head.
      let pivot = left ? 188.0 : 324.0
      let pivotY = 166.0
      let earLocal = actingLocal(.around(x: pivot, y: pivotY,
        angle: angle + (left ? -1.0 : 1.0) * writingIntensity * 0.020,
        scaleY: rig.earScaleY() - writingIntensity * 0.016,
        offsetY: rig.earOffsetY() + writingIntensity * 1.6))
      // Keep the fur root behind the authored ear surface; it supports the base without covering
      // the mint interior. The shared ear frame prevents a detached connector during acting.
      add(left ? "ear.left.root" : "ear.right.root",
        .ellipse(.init(x: pivot - 36, y: pivotY - 36, width: 73, height: 72)),
        layer: .behindSurface,
        fill: material(colors.surface,
          top: .init(x: pivot - 10, y: pivotY - 35),
          bottom: .init(x: pivot + 10, y: pivotY + 36)),
        local: earLocal)
      image(left ? "ear.left" : "ear.right",
        left ? CharacterSEMIStyle.earLeft : CharacterSEMIStyle.earRight,
        layer: .behindSurface, local: earLocal)
    }
    image("head", CharacterSEMIStyle.head, layer: .surface, local: headActingTransform)
  }


  private func bounded(_ value: Double, lower: Double, upper: Double) -> Double {
    min(upper, max(lower, value.isFinite ? value : lower))
  }

  private mutating func heldDocument() {
    let paper = CharacterVectorPath.roundedRectangle(document, radius: 5)
    add("document.shadow", paper, layer: .features, fill: .solid(colors.outline),
      opacity: 0.25, local: documentTransform.concatenating(.around(x: 255, y: 355, offsetY: 3)))
    add("document", paper, layer: .features,
      fill: material(colors.document, top: .init(x: 214, y: 311), bottom: .init(x: 287, y: 399)),
      local: documentTransform)
    add("document.tab", .roundedRectangle(.init(x: 219, y: 309, width: 19, height: 23), radius: 2),
      layer: .features, fill: .solid(colors.documentDetail), local: documentTransform)
    // Quiet printed lines are anatomy, not fake progress or claims of task completion.
    var lines = CharacterVectorPath()
    for row in 0..<3 {
      let y = 348 + Double(row) * 13
      lines.move(229, y)
      lines.line(row == 2 ? 265 : 281, y)
    }
    add("document.print", lines, layer: .features, stroke: colors.writing,
      width: 2.4, opacity: 0.24, local: documentTransform, clips: [paper])
  }

  private mutating func writing() {
    let sweep = writingSweep
    let phase = pose.writingMotionPhase * 2 * .pi
    let pressure = max(0, sin(phase)) * writingIntensity
    let wristRhythm = sin(phase * 1.7 + 0.45) * writingIntensity
    let row = Int((pose.writingMotionPhase * 3).rounded(.down)) % 3
    let baselineY = 349 + Double(row) * 13
    let tipX = 228 + sweep * 50 + wristRhythm * 2.4
    let tipY = baselineY + sin(phase) * 2.2 - 0.8 + pressure * 0.9
    let clip = CharacterVectorPath.roundedRectangle(document, radius: 5)

    var ink = CharacterVectorPath()
    ink.move(229, baselineY)
    ink.quad(233 + sweep * 12 + wristRhythm * 1.8, baselineY - 2.6 - pressure * 0.8, tipX, tipY)
    add("writing.ink", ink, layer: .features, stroke: colors.writing,
      width: 2.2 + pressure * 1.2, opacity: pose.writingOpacity, local: documentTransform, clips: [clip])

    var pencil = CharacterVectorPath()
    pencil.move(tipX, tipY)
    pencil.line(tipX + 5.5 + wristRhythm * 0.6, tipY - 9.5 - pressure * 0.4)
    pencil.line(tipX + 14.8 + wristRhythm * 1.2, tipY - 21.5 - pressure * 0.8)
    pencil.line(tipX + 28 + wristRhythm * 1.8, tipY - 40 - pressure * 1.1)
    add("writing.pencil", pencil, layer: .foreground, stroke: colors.writing,
      width: 4.2 + pressure * 0.5, opacity: pose.writingOpacity, local: documentTransform)

    if let progress = pose.writingProgress {
      var bar = CharacterVectorPath()
      bar.move(222, 386)
      bar.line(222 + 64 * progress, 386)
      add("writing.progress", bar, layer: .features, stroke: colors.writing,
        width: 2.5, opacity: pose.writingOpacity, local: documentTransform, clips: [clip])
    }
  }

  private mutating func paws() {
    let sweep = writingSweep
    let pressWave = max(0, sin(pose.writingMotionPhase * 2 * .pi))
    for left in [true, false] {
      let isWritingPaw = !left && pose.writingVisible
      let amount = isWritingPaw ? writingIntensity : 0
      let pressure = isWritingPaw ? amount * pressWave : writingIntensity * 0.18
      let anchorX = left ? 201.0 : 309.0
      let anchorY = left ? 350.0 : 346.0
      let dx: Double
      let dy: Double
      let angle: Double
      let scaleX: Double
      let scaleY: Double
      if left {
        dx = -writingIntensity * 5.8
        dy = -writingIntensity * 4.0 + pressure * 0.8
        angle = -pose.surface.angle * 0.18 + writingIntensity * 0.09
        scaleX = 1 + writingIntensity * 0.02
        scaleY = 1 - writingIntensity * 0.03
      } else {
        dx = (sweep * 18 - 19) * amount
        dy = (-11.6 + cos(pose.writingMotionPhase * 2 * .pi) * 3.0) * amount + pressure * 2.8
        angle = -pose.surface.angle * 0.20 - amount * 0.31 + (sweep - 0.5) * amount * 0.10
        scaleX = 1 + pressure * 0.05
        scaleY = 1 - pressure * 0.08
      }
      image(left ? "paw.left" : "paw.right",
        left ? CharacterSEMIStyle.pawLeft : CharacterSEMIStyle.pawRight,
        layer: .foreground,
        local: documentTransform.concatenating(.around(x: anchorX, y: anchorY,
          angle: angle,
          scaleX: scaleX, scaleY: scaleY,
          offsetX: dx, offsetY: dy)))
    }
  }

  func material(_ color: CharacterColor, top: CharacterVectorPoint,
    bottom: CharacterVectorPoint) -> CharacterScenePaint {
    guard !simplified else { return .solid(color) }
    func shade(_ factor: Double) -> CharacterColor {
      .init(uncheckedRed: min(1, color.red * factor), green: min(1, color.green * factor),
        blue: min(1, color.blue * factor), alpha: color.alpha)
    }
    return .linear(start: top, end: bottom, stops: [
      .init(location: 0, color: shade(1.30), opacity: 1),
      .init(location: 0.55, color: color, opacity: 1),
      .init(location: 1, color: shade(0.76), opacity: 1)])
  }

  mutating func add(_ id: String, _ path: CharacterVectorPath,
    layer: CharacterSceneLayer = .features, fill: CharacterScenePaint? = nil,
    stroke: CharacterColor? = nil, width: Double = 0, opacity: Double = 1,
    local: CharacterSceneTransform = .identity, clips: [CharacterVectorPath] = []
  ) {
    guard opacity > 0, !path.commands.isEmpty else { return }
    let identity = id.hasPrefix("eye.") || id.hasPrefix("mouth") || id == "nose" ? id : "semi.\(id)"
    nodes.append(.init(id: identity, layer: layer, path: path, fill: fill,
      stroke: stroke, lineWidth: width, opacity: opacity,
      transform: transform.concatenating(local), clips: clips))
  }

  private mutating func image(_ id: String, _ asset: CharacterImageAsset,
    layer: CharacterSceneLayer, local: CharacterSceneTransform = .identity
  ) {
    nodes.append(.init(id: "semi.\(id)", layer: layer, path: .init(), fill: nil,
      stroke: nil, lineWidth: 0, opacity: 1, transform: transform.concatenating(local),
      clips: [], image: .init(asset: asset, bounds: .init(whole), contentMode: .fit)))
  }
}

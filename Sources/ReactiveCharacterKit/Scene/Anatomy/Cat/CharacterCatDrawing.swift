import Foundation

/// Articulation only: no clock, semantic state, effects, platform images or resource reads.
struct CharacterCatDrawing {
  let pose: CharacterPose
  let direction: CharacterArtDirection
  let theme: CharacterProceduralCatTheme
  let transform: CharacterSceneTransform
  let simplified: Bool
  var nodes: [CharacterSceneNode] = []

  static func nodes(
    pose: CharacterPose, direction: CharacterArtDirection, theme: CharacterProceduralCatTheme, board: CharacterRect,
    transform: CharacterSceneTransform, simplified: Bool
  ) -> [CharacterSceneNode] {
    let scale = min(
      board.width / CharacterCatMetrics.width, board.height / CharacterCatMetrics.height)
    let local = CharacterSceneTransform(
      a: scale, b: 0, c: 0, d: scale,
      tx: board.midX - CharacterCatMetrics.width * scale / 2,
      ty: board.midY - CharacterCatMetrics.height * scale / 2)
    var drawing = Self(
      pose: pose, direction: direction, theme: theme,
      transform: transform.concatenating(local), simplified: simplified)
    drawing.draw()
    return drawing.nodes
  }

  var gazeX: Double { pose.face.gazeX / 0.23 }
  var gazeY: Double { pose.face.gazeY / 0.24 }
  var ink: CharacterColor {
    direction.style.partColors.mouth
  }
  var whole: CharacterRect {
    .init(x: 0, y: 0, width: CharacterCatMetrics.width, height: CharacterCatMetrics.height)
  }

  mutating func draw() {
    if direction.surface == .visible {
      switch theme {
      case .animated:
        drawAnimatedBody()
      case .simple2D:
        drawSimpleBody()
      }
    }
    if direction.components.contains(.eyes) {
      drawEye(left: true)
      drawEye(left: false)
    }
    if direction.surface == .visible { drawWhiskers() }
    if direction.components.contains(.mouth) { drawMouth() }
    if direction.components.contains(.nose) { drawNose() }
  }

  // MARK: - Shared articulation

  func earAngle(left: Bool) -> Double {
    let contour = left ? pose.eyeContours.left : pose.eyeContours.right
    let sign = left ? -1.0 : 1.0
    return CharacterCatMetrics.clamp(
      sign
        * (contour.lidCompression * 0.12 + contour.innerPinch * 0.12
          - contour.circular * 0.08 + contour.chevron * 0.10)
        + gazeY * sign * 0.045 + gazeX * 0.04 + pose.surface.angle * 0.12,
      -CharacterCatMetrics.maximumEarAngle, CharacterCatMetrics.maximumEarAngle)
  }

  func simpleEarAngle(left: Bool) -> Double {
    CharacterSimpleCatGeometry.earAngle(
      contour: left ? pose.eyeContours.left : pose.eyeContours.right,
      surfaceAngle: pose.surface.angle,
      left: left)
  }

  // MARK: - Animated authored cat

  mutating func drawAnimatedBody() {
    image(
      "cat.neck", CharacterCatAssets.neck, in: whole, layer: .behindSurface,
      local: .around(x: 264, y: 445, angle: -pose.surface.angle * 0.25))
    for left in [true, false] {
      let asset = left ? CharacterCatAssets.earLeft : CharacterCatAssets.earRight
      let pivotX = left ? 150.0 : 378.0
      image(
        left ? "cat.ear.left" : "cat.ear.right", asset,
        in: whole, layer: .behindSurface,
        local: .around(x: pivotX, y: 248, angle: earAngle(left: left)))

      // The moving ear owns the visible rotation; this fixed root owns only the hidden overlap.
      // Keeping a small unrotated fur base under the head prevents internal ear strokes from
      // tearing away from the skull when the upper ear rotates.
      image(
        left ? "cat.ear.left.base" : "cat.ear.right.base", asset,
        in: whole, layer: .behindSurface,
        clips: [animatedEarRootMask(left: left)])
    }
    image("cat.head", CharacterCatAssets.head, in: whole, layer: .surface)
  }

  func animatedEarRootMask(left: Bool) -> CharacterVectorPath {
    var p = CharacterVectorPath()
    if left {
      p.move(92, 192)
      p.cubic(118, 176, 190, 178, 224, 218)
      p.line(232, 314)
      p.line(94, 314)
    } else {
      p.move(288, 218)
      p.cubic(322, 178, 394, 176, 430, 198)
      p.line(430, 318)
      p.line(282, 314)
    }
    p.close()
    return p
  }

  // MARK: - Simple 2D cat

  mutating func drawSimpleBody() {
    let surface = direction.style.partColors.surface
    let innerEar = direction.style.partColors.mouthDetail

    // A silhouette behind the bust, not a second animated rig or foreground sticker.
    var tail = CharacterVectorPath()
    tail.move(349, 534)
    tail.cubic(397, 546, 424, 523, 412, 494)
    tail.cubic(397, 456, 441, 451, 451, 477)
    tail.cubic(477, 537, 415, 575, 346, 554)
    tail.close()
    add("cat.tail", tail, layer: .behindSurface, fill: .solid(surface))

    var neck = CharacterVectorPath()
    neck.move(173, 450)
    neck.cubic(142, 474, 126, 510, 116, 554)
    neck.line(396, 554)
    neck.cubic(386, 510, 370, 474, 339, 450)
    neck.close()
    add("cat.neck", neck, layer: .behindSurface, fill: .solid(surface))
    add(
      "cat.belly.patch", .ellipse(.init(x: 196, y: 481, width: 120, height: 110)),
      layer: .behindSurface, fill: .solid(innerEar), clips: [neck])

    for left in [true, false] {
      let outer = CharacterSimpleCatGeometry.ear(
        left: left, inner: false, angle: simpleEarAngle(left: left))
      let inner = CharacterSimpleCatGeometry.ear(
        left: left, inner: true, angle: simpleEarAngle(left: left))
      add(
        left ? "cat.ear.left" : "cat.ear.right", outer,
        layer: .behindSurface, fill: .solid(surface))
      add(
        left ? "cat.ear.left.inner" : "cat.ear.right.inner", inner,
        layer: .behindSurface, fill: .solid(innerEar), clips: [outer])
    }

    let head = CharacterVectorPath.ellipse(CharacterSimpleCatGeometry.headBounds)
    add("cat.head", head, layer: .surface, fill: .solid(surface))
    add(
      "cat.face.patch", .ellipse(CharacterSimpleCatGeometry.faceBounds),
      layer: .surface, fill: .solid(innerEar))
  }

  // MARK: - Nose / whiskers

  mutating func drawNose() {
    let x = theme == .simple2D ? 256 : 264 + gazeX * 12
    let y = theme == .simple2D ? 388 : 370 + gazeY * 5
    switch theme {
    case .animated:
      image(
        "nose", CharacterCatAssets.nose,
        in: .init(x: 245 + gazeX * 12, y: 361 + gazeY * 5, width: 39, height: 21),
        layer: .features)
    case .simple2D:
      var nose = CharacterVectorPath()
      let half = 10.0
      nose.move(x - half, y - 4)
      nose.quad(x, y - 10, x + half, y - 4)
      nose.quad(x + half * 0.55, y + 6, x, y + 9)
      nose.quad(x - half * 0.55, y + 6, x - half, y - 4)
      nose.close()
      add("nose", nose, fill: .solid(direction.style.partColors.nose))
    }
  }

  mutating func drawWhiskers() {
    switch theme {
    case .animated:
      for left in [true, false] {
        let sign = left ? -1.0 : 1.0
        let x = left ? 25.0 : 302.0
        let anchor = left ? 230.0 : 304.0
        let spread = CharacterCatMetrics.clamp(pose.mouth.curvature, -1, 1) * 0.035
        image(
          left ? "cat.whiskers.left" : "cat.whiskers.right",
          left ? CharacterCatAssets.whiskerLeft : CharacterCatAssets.whiskerRight,
          in: .init(x: x, y: 370, width: 202, height: 110), layer: .features,
          opacity: simplified ? 1 : 0.84,
          local: .around(
            x: anchor, y: 388, angle: sign * spread + gazeY * sign * 0.025,
            offsetX: gazeX * 6, offsetY: gazeY * 3))
      }
    case .simple2D:
      drawProceduralWhiskers()
    }
  }

  mutating func drawProceduralWhiskers() {
    let baseColor = direction.style.partColors.mouth
    let yBase = 390.0
    for left in [true, false] {
      let sign = left ? -1.0 : 1.0
      let rootX = left ? 83.0 : 429.0
      var p = CharacterVectorPath()
      for index in 0..<2 {
        let y = yBase + Double(index) * 25
        p.move(rootX, y)
        p.line(rootX + sign * 59, y + Double(index) * 10)
      }
      add(
        left ? "cat.whiskers.left" : "cat.whiskers.right", p,
        stroke: baseColor, width: CharacterSimpleCatGeometry.whiskerInkWidth)
    }
  }

  // MARK: - Scene node helpers

  mutating func add(
    _ id: String, _ path: CharacterVectorPath, layer: CharacterSceneLayer = .features,
    fill: CharacterScenePaint? = nil,
    stroke: CharacterColor? = nil, width: Double = 0, opacity: Double = 1,
    local: CharacterSceneTransform = .identity, clips: [CharacterVectorPath] = []
  ) {
    // A fully closed eye keeps its semantic part ID even when its aperture has zero opacity.
    nodes.append(
      .init(
        id: id, layer: layer, path: path, fill: fill, stroke: stroke,
        lineWidth: width * direction.style.lineWidth / CharacterStyle.cat.lineWidth,
        opacity: opacity,
        transform: transform.concatenating(local), clips: clips))
  }

  mutating func image(
    _ id: String, _ asset: CharacterImageAsset, in rect: CharacterRect,
    layer: CharacterSceneLayer, opacity: Double = 1,
    local: CharacterSceneTransform = .identity,
    clips: [CharacterVectorPath] = []
  ) {
    nodes.append(
      .init(
        id: id, layer: layer, path: .init(), fill: nil, stroke: nil,
        lineWidth: 0, opacity: opacity,
        transform: transform.concatenating(local), clips: clips,
        image: .init(asset: asset, bounds: .init(rect), contentMode: .fit)))
  }

  func color(_ r: Double, _ g: Double, _ b: Double) -> CharacterColor {
    .init(uncheckedRed: r, green: g, blue: b)
  }

  func mix(_ a: CharacterColor, _ b: CharacterColor, _ amount: Double) -> CharacterColor {
    .init(
      uncheckedRed: a.red + (b.red - a.red) * amount,
      green: a.green + (b.green - a.green) * amount,
      blue: a.blue + (b.blue - a.blue) * amount,
      alpha: a.alpha + (b.alpha - a.alpha) * amount)
  }
}

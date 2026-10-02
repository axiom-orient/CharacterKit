import Foundation

extension CharacterSceneBuilder {
  /// One immutable hybrid frame for both Canvas and SVG. No resource I/O occurs here.
  public static func scene(
    pose: CharacterPose, artDirection: CharacterArtDirection,
    width: Double, height: Double,
    environment: CharacterDesignEnvironment = .init(), includeBackground: Bool = true,
    overlayAccents: [CharacterAccentPose] = []
  ) throws -> CharacterScene {
    try CharacterSceneCompiler.compile(
      pose: pose, input: .art(artDirection), width: width, height: height,
      environment: environment, includeBackground: includeBackground, overlays: overlayAccents)
  }
}

struct CharacterArtDrawing {
  static func emit(
    pose: CharacterPose, direction artDirection: CharacterArtDirection,
    appearance: ResolvedCharacterAppearance,
    transform: CharacterSceneTransform, width: Double, height: Double,
    includeBackground: Bool, overlays: [CharacterAccentPose]
  ) -> [CharacterSceneNode] {
    let board = appearance.bounds
    let surface = pose.surface
    var drawing = CharacterArtDrawing(
      direction: artDirection, board: board, transform: transform,
      simplified: appearance.simplified)
    if includeBackground, let background = artDirection.assets.background {
      drawing.image(
        "art.background", background, in: .init(x: 0, y: 0, width: width, height: height),
        layer: .background, transform: .identity, contentMode: .fill)
    }
    if case .minimal = artDirection.anatomy, artDirection.surface == .visible {
      if let face = artDirection.assets.face {
        drawing.image("art.face", face, in: board, layer: .surface)
      } else {
        drawing.characterSurface()
      }
    }
    if artDirection.components.contains(.accessories) {
      for (index, accessory) in artDirection.assets.accessories.enumerated() {
        drawing.accessory(accessory, id: "art.accessory.\(index)", surface: surface)
      }
    }
    if artDirection.components.contains(.ornaments) {
      for (index, accent) in (pose.accents + overlays).enumerated() {
        drawing.accent(accent, id: "art.accent.\(index)")
      }
    }
    switch artDirection.anatomy {
    case .minimal:
      drawing.features(pose)
    case .cat(let theme):
      drawing.nodes += CharacterCatDrawing.nodes(
        pose: pose, direction: artDirection, theme: theme, board: board, transform: transform,
        simplified: drawing.simplified)
    case .reference(let reference):
      drawing.nodes += CharacterReferenceDrawing.nodes(
        pose: pose, direction: artDirection, appearance: reference, board: board,
        transform: transform, includeBackground: includeBackground)
    case .portrait(let portraitStyle):
      drawing.nodes += CharacterPortraitDrawing.nodes(
        pose: pose, direction: artDirection, style: portraitStyle,
        board: board, transform: transform, simplified: drawing.simplified)
    }
    if artDirection.components.contains(.writing), pose.writingVisible {
      drawing.writing(pose)
    }
    return drawing.nodes
  }


  let direction: CharacterArtDirection
  let board: CharacterRect
  let transform: CharacterSceneTransform
  let simplified: Bool
  var nodes: [CharacterSceneNode] = []

  var stroke: Double { max(0.5, min(board.width, board.height) * direction.style.lineWidth) }
  var eyeColor: CharacterColor { direction.style.partColors.eyes }

  mutating func add(
    _ id: String, _ path: CharacterVectorPath, layer: CharacterSceneLayer = .features,
    fill: CharacterScenePaint? = nil, stroke: CharacterColor? = nil, width: Double = 0,
    opacity: Double = 1, transform: CharacterSceneTransform? = nil,
    clips: [CharacterVectorPath] = []
  ) {
    guard opacity > 0, !path.commands.isEmpty else { return }
    nodes.append(
      .init(
        id: id, layer: layer, path: path, fill: fill, stroke: stroke,
        lineWidth: width, opacity: opacity, transform: transform ?? self.transform, clips: clips))
  }

  mutating func image(
    _ id: String, _ asset: CharacterImageAsset, in bounds: CharacterRect,
    layer: CharacterSceneLayer, opacity: Double = 1, transform: CharacterSceneTransform? = nil,
    contentMode: CharacterImageContentMode = .fit,
    clips: [CharacterVectorPath] = []
  ) {
    guard opacity > 0 else { return }
    nodes.append(
      .init(
        id: id, layer: layer, path: .init(), fill: nil, stroke: nil, lineWidth: 0,
        opacity: opacity, transform: transform ?? self.transform, clips: clips,
        image: .init(asset: asset, bounds: .init(bounds), contentMode: contentMode)))
  }

  func region(_ value: CharacterRegion) -> CharacterRect {
    CharacterGeometry.map(value, into: board)
  }

  /// Palette-driven character surface shared by Black, White and Arcade.
  /// Geometry never changes when only the palette changes.
  mutating func characterSurface() {
    let body = CharacterVectorPath.ellipse(board)
    let base = direction.style.partColors.surface
    let brightSurface = base.relativeLuminance > 0.5
    let deep = direction.style.partColors.surfaceShade
    let mid =
      brightSurface
      ? CharacterColor(
        uncheckedRed: min(1, base.red * 1.02), green: min(1, base.green * 1.02),
        blue: min(1, base.blue * 1.02), alpha: base.alpha)
      : CharacterColor(
        uncheckedRed: min(1, base.red * 2.4 + 0.04), green: min(1, base.green * 2.4 + 0.04),
        blue: min(1, base.blue * 2.4 + 0.04), alpha: base.alpha)
    let highlight = direction.style.partColors.surfaceHighlight
    let edge = direction.style.partColors.surfaceRim

    guard !simplified else {
      add("art.face", body, layer: .surface, fill: .solid(base))
      return
    }

    let shadowRadius = board.width * 0.41
    let shadowCenter = CharacterVectorPoint(x: board.midX, y: board.maxY + board.height * 0.035)
    add(
      "art.face.shadow",
      .ellipse(
        .init(
          x: shadowCenter.x - shadowRadius, y: shadowCenter.y - shadowRadius * 0.14,
          width: shadowRadius * 2, height: shadowRadius * 0.28)),
      layer: .behindSurface,
      fill: .radial(
        center: shadowCenter, radius: shadowRadius,
        stops: [
          .init(location: 0, color: deep, opacity: 0.22),
          .init(location: 1, color: deep, opacity: 0),
        ]),
      transform: self.transform)

    add(
      "art.face", body, layer: .surface,
      fill: .radial(
        center: .init(x: board.x + board.width * 0.30, y: board.y + board.height * 0.22),
        radius: board.width * 0.92,
        stops: [
          .init(location: 0, color: mid, opacity: 1),
          .init(location: 0.48, color: base, opacity: 1),
          .init(location: 1, color: deep, opacity: 1),
        ]),
      stroke: deep, width: board.width * 0.008)

    let glossBounds = CharacterRect(
      x: board.x + board.width * 0.13, y: board.y + board.height * 0.10,
      width: board.width * 0.34, height: board.height * 0.27)
    add(
      "art.face.gloss", .ellipse(glossBounds), layer: .surface,
      fill: .radial(
        center: .init(
          x: glossBounds.x + glossBounds.width * 0.27,
          y: glossBounds.y + glossBounds.height * 0.25),
        radius: glossBounds.width * 0.80,
        stops: [
          .init(location: 0, color: highlight, opacity: 0.12),
          .init(location: 0.42, color: highlight, opacity: 0.035),
          .init(location: 1, color: highlight, opacity: 0),
        ]),
      clips: [body])

    let innerInset = board.width * 0.018
    let inner = CharacterVectorPath.ellipse(
      .init(
        x: board.x + innerInset, y: board.y + innerInset,
        width: board.width - innerInset * 2, height: board.height - innerInset * 2))
    let topLeftClip = CharacterVectorPath.rectangle(
      .init(
        x: board.x, y: board.y, width: board.width * 0.68, height: board.height * 0.63))
    let lowerRightClip = CharacterVectorPath.rectangle(
      .init(
        x: board.x + board.width * 0.35, y: board.y + board.height * 0.42,
        width: board.width * 0.65, height: board.height * 0.58))
    add(
      "art.face.rim.highlight", inner, layer: .surface, stroke: edge,
      width: board.width * 0.008, opacity: 0.52, clips: [body, topLeftClip])
    add(
      "art.face.rim.shadow", inner, layer: .surface, stroke: deep,
      width: board.width * 0.012, opacity: 0.42, clips: [body, lowerRightClip])
  }
  func local(_ path: CharacterVectorPath, in rect: CharacterRect) -> CharacterVectorPath {
    path.mapped { .init(x: rect.x + $0.x * rect.width, y: rect.y + $0.y * rect.height) }
  }

  mutating func accessory(
    _ accessory: CharacterAccessoryAsset, id: String, surface: CharacterSurfacePose
  ) {
    let anchor: CharacterRect
    switch accessory.anchor {
    case .face: anchor = board
    case .eyes: anchor = region(direction.layout.eyes)
    case .nose: anchor = region(direction.layout.nose)
    case .mouth: anchor = region(direction.layout.mouth)
    case .writing: anchor = region(direction.layout.writing)
    }
    let x = anchor.x + anchor.width * accessory.centerX
    let y = anchor.y + anchor.height * accessory.centerY
    let w = anchor.width * accessory.width
    let h = anchor.height * accessory.height
    image(
      id, accessory.image, in: .init(x: x - w / 2, y: y - h / 2, width: w, height: h),
      layer: accessory.layer == .foreground ? .foreground : .behindFeatures,
      opacity: accessory.opacity,
      transform:
        transform
        .concatenating(secondaryResponse(accessory: accessory, surface: surface))
        .concatenating(.around(x: x, y: y, angle: accessory.angle)))
  }

  /// Small pose-relative follow-through, not a physics simulation or a second animation clock.
  /// Rigid props inherit position/rotation but attenuate cartoon squash/stretch; soft hood cloth
  /// follows the surface almost completely. The built-in catalog is the only policy owner.
  func secondaryResponse(
    accessory: CharacterAccessoryAsset, surface: CharacterSurfacePose
  ) -> CharacterSceneTransform {
    guard let spec = CharacterBuiltInAccessoryCatalog.spec(for: accessory.image) else {
      return .identity
    }

    let targetScaleX = 1 + (surface.scaleX - 1) * (1 - spec.squashRigidity)
    let targetScaleY = 1 + (surface.scaleY - 1) * (1 - spec.squashRigidity)
    return .around(
      x: board.midX,
      y: board.midY,
      angle: -surface.angle * spec.followLag,
      scaleX: targetScaleX / surface.scaleX,
      scaleY: targetScaleY / surface.scaleY,
      offsetX: -surface.offsetX * board.width * spec.followLag,
      offsetY: -surface.offsetY * board.height * spec.followLag
    )
  }

  /// Soft glow is explicit gradient geometry, not backend-specific blur filters.
  mutating func glow(
    _ id: String, bounds: CharacterRect, color: CharacterColor,
    amount: Double, transform: CharacterSceneTransform? = nil
  ) {
    guard !simplified, amount > 0 else { return }
    let radius = max(bounds.width * 0.9, 1)
    let ratio = max(1, bounds.height / max(bounds.width, 0.000_001))
    let t = (transform ?? self.transform).concatenating(
      .around(x: bounds.midX, y: bounds.midY, scaleY: ratio))
    let circle = CharacterRect(
      x: bounds.midX - radius, y: bounds.midY - radius,
      width: radius * 2, height: radius * 2)
    add(
      id, .ellipse(circle),
      fill: .radial(
        center: .init(x: bounds.midX, y: bounds.midY), radius: radius,
        stops: [
          .init(location: 0, color: color, opacity: min(1, amount * 0.55)),
          .init(location: 0.53, color: color, opacity: amount * 0.25),
          .init(location: 1, color: color, opacity: 0),
        ]), transform: t)
  }

  mutating func contourGlow(
    _ id: String, path: CharacterVectorPath,
    color: CharacterColor, amount: Double,
    transform: CharacterSceneTransform
  ) {
    guard !simplified, amount > 0 else { return }
    for (index, sample) in [
      (30.0, 0.020), (23, 0.030), (17, 0.045), (12, 0.070), (8, 0.100), (4, 0.14),
    ].enumerated() {
      add(
        id + ".\(index)", path, stroke: color, width: board.width / 600 * sample.0,
        opacity: min(1, sample.1 * amount), transform: transform)
    }
  }

  mutating func features(_ pose: CharacterPose) {
    if direction.components.contains(.eyes) {
      // Built-in faces stay crisp; motion is expressed by shape deformation, gaze, blink and
      // surface choreography rather than duplicate eye layers.
      eyes(pose.eyes, id: "eye", opacity: 1, contours: pose.eyeContours)
    }

    if direction.components.contains(.nose) {
      let r = region(direction.layout.nose)
      var p = CharacterVectorPath()
      p.move(r.midX + pose.noseOffsetX * r.width, r.y + r.height * 0.2)
      p.quad(r.midX - r.width * 0.12, r.maxY, r.midX + r.width * 0.12, r.maxY - r.height * 0.1)
      add(
        "nose", p, stroke: direction.style.partColors.nose, width: stroke * 0.5,
        clips: [.rectangle(r)])
    }
    if direction.components.contains(.mouth), direction.layout != .eyesOnly {
      mouth(pose.mouth, placement: pose.face.mouth, writingVisible: pose.writingVisible)
    }
  }

  mutating func eyes(
    _ pair: CharacterEyePairPose, id: String, opacity: Double,
    contours: CharacterEyeContourPair = .neutral
  ) {
    guard opacity > 0 else { return }
    let band = region(direction.layout.eyes)
    for (name, eye, contour) in [
      ("left", pair.left, contours.left),
      ("right", pair.right, contours.right),
    ] {
      let bounds: CharacterRect
      let half = CharacterEyeGeometry.halfBand(
        band,
        midX: band.x + (pair.left.centerX + pair.right.centerX) / 2 * band.width,
        left: name == "left")
      var size = CharacterEyeGeometry.size(
        width: eye.width * band.width * 1.26,
        height: eye.height * band.height * 1.85, eye: eye, contour: contour)
      let treatment = direction.style.eyeTreatment
      // Heart/crescent/angry topology stays emotion-owned. Treatment adjusts only base proportion.
      let specialTopology =
        contour.heart > 0.01 || contour.crescent > 0.01 || contour.innerPinch > 0.01
      let fitRegion = half
      if !specialTopology {
        let canonicalVertical = (width: size.width * 0.78, height: size.height * 1.30)
        switch treatment {
        case .vertical:
          size = canonicalVertical
        case .horizontal:
          size = (
            width: min(fitRegion.width * 0.92, canonicalVertical.height * 0.94),
            height: min(fitRegion.height, canonicalVertical.width * 1.06)
          )
        case .round:
          let side = min(
            max(canonicalVertical.width, canonicalVertical.height), min(half.width, half.height))
          size = (width: side, height: side)
        }
      }
      let capsule = CharacterGeometry.fitCapsule(
        preferredCenterX: band.x + eye.centerX * band.width,
        preferredCenterY: band.y + eye.centerY * band.height,
        preferredWidth: size.width, preferredHeight: size.height,
        angle: eye.angle, inside: fitRegion)
      bounds = .init(
        x: capsule.centerX - capsule.width / 2, y: capsule.centerY - capsule.height / 2,
        width: capsule.width, height: capsule.height)
      let t = transform.concatenating(
        .around(x: capsule.centerX, y: capsule.centerY, angle: capsule.angle))
      let label = "\(id).\(name)"
      let p = CharacterEyeGeometry.path(contour, in: bounds, left: name == "left")
      if id == "eye" {
        contourGlow(
          label + ".glow", path: p, color: eyeColor,
          amount: direction.featureGlow, transform: t)
      }
      add(
        label, p, fill: .solid(eyeColor), opacity: opacity,
        transform: t, clips: [.rectangle(band)])
    }
  }

  mutating func mouth(
    _ mouth: CharacterMouthPose,
    placement: CharacterFeaturePlacement,
    writingVisible: Bool
  ) {
    guard mouth.visible, mouth.opacity > 0 else { return }
    let band = placement.adjusted(region: region(direction.layout.mouth), within: board)
    let paths = CharacterMouthGeometry.paths(for: mouth, in: board, region: band)
    let mouthTransform = transform
    let light = direction.style.partColors.mouth
    let renderedFill: CharacterScenePaint?
    switch direction.style.mouthTreatment {
    case .outline:
      renderedFill = nil
    case .filled:
      renderedFill = .solid(paths.fill(light: light, dark: direction.style.partColors.surface))
    }
    add(
      "mouth", paths.outer, fill: renderedFill, stroke: light,
      width: max(0.7, board.width * 0.008), opacity: mouth.opacity,
      transform: mouthTransform)
    add(
      "mouth.teeth", paths.teeth, fill: .solid(direction.style.partColors.mouthDetail),
      opacity: paths.detailOpacity, transform: mouthTransform, clips: [paths.outer])
    add(
      "mouth.innerTongue", paths.tongue, fill: .solid(direction.style.partColors.tongue),
      opacity: paths.tongueOpacity, transform: mouthTransform, clips: [paths.outer])
    // Glyph metadata alone must never claim that the host is producing output.
    if writingVisible, mouth.glyph == .speechWave {
      add(
        "mouth.wave", CharacterMouthGeometry.speechWave(in: board), stroke: light,
        width: max(0.7, board.width * 0.006), opacity: 0.90,
        transform: mouthTransform, clips: [.rectangle(board)])
    }
  }

  mutating func writing(_ pose: CharacterPose) {
    let band = region(direction.layout.writing)
    let sweep = 0.5 - 0.5 * cos(pose.writingMotionPhase * 2 * Double.pi)
    var p = CharacterVectorPath()
    for row in 0..<2 {
      let y = band.y + band.height * (0.58 + Double(row) * 0.24)
      p.move(band.x + band.width * 0.08, y)
      p.line(band.x + band.width * (row == 0 ? 0.62 : 0.46), y)
    }
    let x = band.x + band.width * (0.35 + sweep * 0.3)
    p.move(x, band.y + band.height * 0.58)
    p.line(x + band.width * 0.25, band.y + band.height * 0.10)
    add(
      "writing", p, stroke: direction.style.partColors.writing,
      width: min(stroke * 0.6, band.height * 0.085),
      opacity: pose.writingOpacity, clips: [.rectangle(band)])
    if let progress = pose.writingProgress {
      var bar = CharacterVectorPath()
      bar.move(band.x, band.maxY - band.height * 0.04)
      bar.line(band.x + band.width * progress, band.maxY - band.height * 0.04)
      add(
        "writing.progress", bar, stroke: direction.style.partColors.writing,
        width: band.height * 0.04,
        opacity: pose.writingOpacity, clips: [.rectangle(band)])
    }
  }
}

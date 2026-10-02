import Foundation

extension CharacterSceneDrawing {
  mutating func drawSurface(pose: CharacterPose) {
    let r = design.profile.rendering
    guard r.surfaceVisible else { return }
    if r.shadow > 0, !compact, !simplified, mode == .sculpted {
      let x = face.midX + pose.surface.offsetX * face.width * 0.4
      let y = face.maxY + face.height * 0.045
      let radius = face.width * 0.43
      let circle = CharacterRect(
        x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
      add(
        "surface.shadow", .ellipse(circle), layer: .behindSurface,
        fill: .radial(
          center: .init(x: x, y: y), radius: radius,
          stops: [
            .init(location: 0, color: .designBlack, opacity: 1),
            .init(location: 1, color: .designBlack, opacity: 0),
          ]), opacity: r.shadow,
        transform: .around(x: x, y: y, scaleX: 1, scaleY: 0.13))
    }
    let shape = surfacePath(face)
    let fill: CharacterScenePaint
    if mode == .sculpted {
      let stops: [CharacterGradientStop] = [
        .init(location: 0, color: partColors.surface, opacity: 1),
        .init(location: 0.28, color: partColors.surface, opacity: 1),
        .init(location: 1, color: surfaceShade, opacity: 1),
      ]
      switch r.lighting {
      case .radial:
        fill = .radial(
          center: .init(x: face.x + face.width * 0.28, y: face.y + face.height * 0.20),
          radius: max(face.width, face.height) * 0.9, stops: stops)
      case .linear:
        fill = .linear(
          start: .init(x: face.x, y: face.y),
          end: .init(x: face.maxX, y: face.maxY), stops: stops)
      }
    } else {
      fill = .solid(partColors.surface)
    }
    add(
      "surface.body", shape, layer: .surface, fill: fill, stroke: palette.outline,
      width: mode == .outline ? strokeWidth : max(strokeWidth * 0.45, 0.65))
    if mode == .sculpted, r.highlight > 0, !compact, !simplified {
      let center = CharacterVectorPoint(
        x: face.x + face.width * 0.32, y: face.y + face.height * 0.17)
      let radius = min(face.width, face.height) * 0.42
      add(
        "surface.light", shape, layer: .surface,
        fill: .radial(
          center: center, radius: radius,
          stops: [
            .init(location: 0, color: palette.detail, opacity: r.highlight * 0.38),
            .init(location: 1, color: palette.detail, opacity: 0),
          ]))
      let inset = min(face.width, face.height) * 0.018
      let inner = CharacterRect(
        x: face.x + inset, y: face.y + inset,
        width: face.width - inset * 2, height: face.height - inset * 2)
      add(
        "surface.rim", surfacePath(inner), layer: .surface,
        stroke: palette.detail, width: max(0.5, strokeWidth * 0.28), opacity: r.highlight * 0.36)
    }
  }

  private func surfacePath(_ rect: CharacterRect) -> CharacterVectorPath {
    switch design.profile.rendering.silhouette {
    case .orb: .ellipse(rect)
    case .roundedRectangle:
      .roundedRectangle(
        rect, radius: min(rect.width, rect.height) * design.profile.rendering.cornerRadius)
    case .capsule: .roundedRectangle(rect, radius: min(rect.width, rect.height) / 2)
    }
  }

  mutating func drawFace(pose: CharacterPose) {
    if design.components.contains(.eyes) {
      let band = region(design.layout.eyes)
      if !simplified {
        if let pair = pose.farTrail {
          drawEyePair(pair, region: band, id: "eye.far", opacity: pose.farTrailOpacity)
        }
        if let pair = pose.nearTrail {
          drawEyePair(pair, region: band, id: "eye.near", opacity: pose.nearTrailOpacity)
        }
      }
      drawEyePair(pose.eyes, region: band, id: "eye", opacity: 1, contours: pose.eyeContours)
    }
    if design.components.contains(.nose) {
      let band = region(design.layout.nose)
      let x = region(design.layout.nose).midX
      var p = CharacterVectorPath()
      p.move(x + pose.noseOffsetX * band.width, band.y + band.height * 0.12)
      p.quad(
        x - band.width * 0.08, band.y + band.height * 0.85,
        x + band.width * 0.14, band.y + band.height * 0.78)
      add("nose", p, stroke: partColors.nose, clips: [.rectangle(band)])
    }
    if design.components.contains(.mouth), pose.mouth.visible {
      let mouthRegion = pose.face.mouth.adjusted(
        region: region(design.layout.mouth),
        within: face
      )
      drawMouth(pose.mouth, region: mouthRegion)
    }
    if design.components.contains(.writing), pose.writingVisible {
      drawWriting(pose, region: region(design.layout.writing))
    }
  }

  private mutating func drawEyePair(
    _ pair: CharacterEyePairPose, region band: CharacterRect,
    id: String, opacity: Double, contours: CharacterEyeContourPair = .neutral
  ) {
    guard opacity > 0 else { return }
    let r = design.profile.rendering
    let inset = min(strokeWidth * 0.6, band.width * 0.2, band.height * 0.2)
    let inner = CharacterRect(
      x: band.x + inset, y: band.y + inset,
      width: band.width - inset * 2, height: band.height - inset * 2)
    for (name, eye, contour) in [
      ("left", pair.left, contours.left), ("right", pair.right, contours.right),
    ] {
      let size = CharacterEyeGeometry.size(
        width: eye.width * band.width * r.eyeScaleX,
        height: eye.height * band.height * r.eyeScaleY, eye: eye, contour: contour)
      let capsule = CharacterGeometry.fitCapsule(
        preferredCenterX: band.x + (0.5 + (eye.centerX - 0.5) * r.eyeSpacing) * band.width,
        preferredCenterY: band.y + eye.centerY * band.height,
        preferredWidth: size.width,
        preferredHeight: size.height,
        angle: eye.angle,
        inside: CharacterEyeGeometry.halfBand(
          inner,
          midX: band.x
            + (0.5 + ((pair.left.centerX + pair.right.centerX) / 2 - 0.5)
              * r.eyeSpacing)
              * band.width,
          left: name == "left"))
      let rect = CharacterRect(
        x: capsule.centerX - capsule.width / 2,
        y: capsule.centerY - capsule.height / 2, width: capsule.width, height: capsule.height)
      let rotation = CharacterSceneTransform.around(
        x: capsule.centerX, y: capsule.centerY, angle: capsule.angle)
      let path = CharacterEyeGeometry.path(
        contour, in: rect, left: name == "left",
        ellipse: r.eyeStyle == .ellipse,
        corner: r.eyeStyle == .roundedRectangle ? r.eyeCornerRadius : 0.5)
      let rotated = path.transformed(rotation)
      // Very thin blinks remain filled so outline width cannot invert/erase them.
      let outline = mode == .outline && min(rect.width, rect.height) > strokeWidth * 2
      add(
        "\(id).\(name)", rotated, fill: outline ? nil : .solid(partColors.eyes),
        stroke: outline ? partColors.eyes : nil, opacity: opacity, clips: [.rectangle(band)])
      if id == "eye", !outline, mode == .sculpted, !compact, !simplified,
        r.highlight > 0, rect.height > strokeWidth * 4
      {
        let light = CharacterRect(
          x: rect.x + rect.width * 0.22, y: rect.y + rect.height * 0.14,
          width: rect.width * 0.20, height: min(rect.width * 0.20, rect.height * 0.14))
        add(
          "\(id).\(name).light", .ellipse(light).transformed(rotation),
          fill: .solid(palette.detail), opacity: r.highlight * 0.6,
          clips: [rotated, .rectangle(band)])
      }
    }
  }

  private mutating func drawMouth(_ mouth: CharacterMouthPose, region band: CharacterRect) {
    let paths = CharacterMouthGeometry.paths(
      for: mouth, in: face, region: band,
      minimumAspect: design.profile.rendering.minimumMouthAspect)
    let outline = design.profile.rendering.mouthStyle == .outline
    let line = min(strokeWidth * 0.5, band.height * 0.08)
    add(
      "mouth", paths.outer, fill: outline ? nil : .solid(partColors.mouth),
      stroke: partColors.mouth, width: line, opacity: mouth.opacity, clips: [.rectangle(band)])
    add(
      "mouth.teeth", paths.teeth, fill: .solid(partColors.mouthDetail),
      opacity: paths.detailOpacity, clips: [.rectangle(band), paths.outer])
    add(
      "mouth.innerTongue", paths.tongue, fill: .solid(partColors.tongue),
      opacity: paths.tongueOpacity, clips: [.rectangle(band), paths.outer])
  }

  private mutating func drawWriting(_ pose: CharacterPose, region band: CharacterRect) {
    let phase = min(1, max(0, pose.writingMotionPhase))
    let sweep = 0.5 - 0.5 * cos(phase * .pi * 2)
    let line = min(strokeWidth * 0.7, band.height * 0.085)
    for row in 0..<2 {
      let y = band.y + band.height * (0.58 + Double(row) * 0.24)
      var p = CharacterVectorPath()
      p.move(band.x + band.width * 0.08, y)
      p.line(band.x + band.width * (row == 0 ? 0.62 : 0.46), y)
      add(
        "writing.line.\(row)", p, stroke: partColors.writing, width: line,
        opacity: pose.writingOpacity, clips: [.rectangle(band)])
    }
    let pen = CharacterRect(
      x: band.x + band.width * (0.47 + sweep * 0.23),
      y: band.y + band.height * 0.06, width: band.width * 0.11, height: band.height * 0.65)
    let penPath = CharacterVectorPath.roundedRectangle(pen, radius: pen.width * 0.28)
      .transformed(.around(x: pen.midX, y: pen.midY, angle: .pi * 0.22))
    add(
      "writing.pen", penPath, fill: .solid(partColors.accent), opacity: pose.writingOpacity,
      clips: [.rectangle(band)])
    if let progress = pose.writingProgress {
      var p = CharacterVectorPath()
      p.move(band.x + band.width * 0.08, band.maxY - line)
      p.line(band.x + band.width * (0.08 + progress * 0.84), band.maxY - line)
      add(
        "writing.progress", p, stroke: partColors.writing, width: line,
        opacity: pose.writingOpacity, clips: [.rectangle(band)])
    }
  }
}

extension CharacterVectorPath {
  func transformed(_ t: CharacterSceneTransform) -> Self {
    mapped { .init(x: t.a * $0.x + t.c * $0.y + t.tx, y: t.b * $0.x + t.d * $0.y + t.ty) }
  }
}

// Conservative cubic-control bounds: the entire curve is contained by this envelope.
// Used by boundary validation and vector fitting, never by semantic state or the reference renderer.
extension CharacterMouthPose {
  var vectorBounds: CharacterRect? {
    guard let first = contour.first else { return nil }
    var minX = first.start.x
    var maxX = minX
    var minY = first.start.y
    var maxY = minY
    for s in contour {
      for p in [s.start, s.control1, s.control2, s.end] {
        minX = min(minX, p.x)
        maxX = max(maxX, p.x)
        minY = min(minY, p.y)
        maxY = max(maxY, p.y)
      }
    }
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

import Foundation

/// One numeric mouth rig shared by canonical minimal, art and reference scenes.
/// No glyph classifier, bitmap swap, inferred cheek marks or platform drawing state.
struct CharacterMouthPaths: Sendable, Equatable {
  let outer: CharacterVectorPath
  let teeth: CharacterVectorPath
  let tongue: CharacterVectorPath
  let detailOpacity: Double
  let tongueOpacity: Double
  let cavityAmount: Double

  func fill(light: CharacterColor, dark: CharacterColor) -> CharacterColor {
    .init(
      uncheckedRed: light.red + (dark.red - light.red) * cavityAmount,
      green: light.green + (dark.green - light.green) * cavityAmount,
      blue: light.blue + (dark.blue - light.blue) * cavityAmount,
      alpha: light.alpha + (dark.alpha - light.alpha) * cavityAmount)
  }
}

enum CharacterMouthGeometry {
  static func paths(
    for mouth: CharacterMouthPose, in canvas: CharacterRect,
    region: CharacterRect? = nil, minimumAspect: Double = 0
  ) -> CharacterMouthPaths {
    let band =
      region
      ?? CharacterRect(
        x: canvas.x + canvas.width * 0.27,
        y: canvas.y + canvas.height * 0.69, width: canvas.width * 0.46,
        height: canvas.height * 0.18)
    let curve = min(1, max(-1, mouth.curvature))
    let open = min(1, max(0, mouth.openness))
    let w = max(
      canvas.width * 0.27 * min(1.35, max(0.24, mouth.width)),
      (canvas.width * (0.009 + 0.16 * open)) * minimumAspect)
    let thickness = canvas.width * 0.009
    let rise = abs(curve) * w * 0.22
    let closedHeight = thickness + rise
    let openHeight = thickness + canvas.width * 0.16 * open
    let height = max(closedHeight, openHeight + rise * 0.25)
    let scale = min(1, band.width * 0.94 / w, band.height * 0.90 / height)
    let rect = CharacterRect(x: -w / 2, y: -height / 2, width: w, height: height)
    var closed = CharacterInkGeometry.ribbon(in: rect, thickness: thickness, rise: rise)
    if curve >= 0 {
      // Reflect the smile, reverse winding, then start again at the upper centre.
      // The resulting topology matches the opening and frown throughout an open/close.
      let reflected = closed.points.map { CharacterVectorPoint(x: $0.x, y: -$0.y) }
      var reversed = [reflected[0]]
      for i in stride(from: 34, through: 1, by: -3) {
        reversed += [reflected[i + 1], reflected[i], reflected[i - 1]]
      }
      var rotated = [reversed[18]]
      for segment in 0..<12 {
        let start = ((segment + 6) % 12) * 3
        rotated += [reversed[start + 1], reversed[start + 2], reversed[start + 3]]
      }
      closed = .init(rotated)
    }
    let opening = CharacterRect(
      x: -w / 2, y: -openHeight / 2,
      width: w, height: openHeight)
    // A rounded lower bowl, not a bent sausage: the smiling upper lip relaxes
    // while the lower half opens fully. Negative curvature mirrors the same rig.
    let direction = curve >= 0 ? 1.0 : -1.0
    let bend = abs(curve)
    let cavity = CharacterInkGeometry.ellipse(in: opening).mapped { point in
      let nx = point.x / (w / 2)
      let orientedY = point.y * direction
      let lipY = orientedY < 0 ? orientedY * (1 - bend * 0.86) : orientedY
      return .init(
        x: point.x,
        y: direction * (lipY - bend * openHeight * 0.45 * nx * nx))
    }
    let blend = min(1, max(0, (open - 0.035) / 0.30))
    let eased = blend * blend * (3 - 2 * blend)
    func placed(_ point: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(
        x: band.midX + point.x * scale,
        y: band.midY + (point.y - mouth.skew * point.x * 0.22) * scale)
    }
    let outer = closed.blended(to: cavity, amount: eased).mapped(placed).path
    let teeth = CharacterInkGeometry.capsule(
      in: .init(x: -w * 0.42, y: 0, width: w * 0.84, height: thickness * 1.6)
    ).mapped { point in
      let nx = min(1, abs(point.x / (w / 2)))
      let upperLip =
        -openHeight * 0.5 * sqrt(max(0, 1 - nx * nx))
        * (1 - max(0, curve) * 0.86) - max(0, curve) * openHeight * 0.45 * nx * nx
      return placed(.init(x: point.x, y: point.y + upperLip + thickness * 0.30))
    }.path
    let tongue = CharacterInkGeometry.ellipse(
      in: .init(
        x: -w * 0.28,
        y: openHeight * 0.26, width: w * 0.56, height: openHeight * 0.50)
    )
    .mapped(placed).path
    let detail = min(1, max(0, (open - 0.28) / 0.20)) * max(0, curve) * mouth.opacity
    return .init(
      outer: outer, teeth: teeth, tongue: tongue,
      detailOpacity: detail, tongueOpacity: detail * 0.68, cavityAmount: eased)
  }

  static func speechWave(in canvas: CharacterRect) -> CharacterVectorPath {
    var wave = CharacterVectorPath()
    let startX = canvas.x + canvas.width * 0.25
    let endX = canvas.x + canvas.width * 0.47
    let baseline = canvas.y + canvas.height * 0.77
    let amplitude = canvas.height * 0.035
    let step = (endX - startX) / 2
    wave.move(startX, baseline)
    wave.cubic(
      startX + step * 0.22, baseline - amplitude,
      startX + step * 0.72, baseline - amplitude,
      startX + step, baseline)
    wave.cubic(
      startX + step * 1.22, baseline + amplitude,
      startX + step * 1.72, baseline + amplitude,
      endX, baseline)
    return wave
  }
}

import Foundation

/// Flat ink eyes for the two compact anatomies. Consumes resolved channels, never emotions.
/// A blink morphs the silhouette into a finite-width line; it does not fade the eye away.
enum CharacterCompactEyeGeometry {
  static let sizeResponse = 0.28
  static func path(
    eye: CharacterEyePose, contour: CharacterEyeContour, left: Bool,
    center: CharacterVectorPoint, width: Double, height: Double,
    treatment: CharacterEyeTreatment, thickness: Double,
    oval: Bool = false, expressionWidth: Double? = nil
  ) -> CharacterVectorPath {
    func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double {
      min(b, max(a, x))
    }
    let response = sizeResponse
    var w = width * (1 + (clamp(eye.unblinkedWidth / 0.19, 0.72, 1.35) - 1) * response)
    var h = height * (1 + (clamp(eye.unblinkedHeight / 0.43, 0.70, 1.28) - 1) * response)
    w *= min(1.20, contour.widthScale)
    h *= contour.heightScale
    if treatment == .horizontal {
      // Keep the sideways reading wider than the canonical vertical eye, but preserve the
      // shared face safe area for the simple cat sheet and heart-eye expression.
      w *= 1.18
      h *= 0.38
    }
    if treatment == .round {
      w *= 1.10
      h *= 0.76
    }
    h += (w - h) * contour.circular
    let box = CharacterRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    let base = CharacterInkGeometry.capsule(in: box).blended(
      to: CharacterInkGeometry.ellipse(in: box), amount: oval ? 1 : contour.ellipse)
    let compressed = base.mapped { p in
      let inner = left ? (p.x - box.x) / box.width : (box.maxX - p.x) / box.width
      let amount = contour.lidCompression * 0.65 + contour.innerPinch * inner * 0.36
      return .init(x: p.x, y: p.y + (box.maxY - p.y) * min(0.86, amount))
    }
    let span = (expressionWidth ?? width) * w / width
    let smileBox = CharacterRect(
      x: center.x - span * 0.58, y: center.y - span * 0.23,
      width: span * 1.16, height: span * 0.46)
    let smile = CharacterInkGeometry.ribbon(in: smileBox, thickness: thickness, rise: span * 0.25)
    let chevron = CharacterInkGeometry.chevron(
      in: .init(x: center.x - span / 2, y: center.y - span * 0.45,
        width: span, height: span * 0.9), thickness: thickness, pointsRight: left)
    let heartSpan = span * 1.3
    let heartBox = CharacterRect(
      x: center.x - heartSpan / 2, y: center.y - heartSpan * 0.47,
      width: heartSpan, height: heartSpan * 0.94)
    let expressed =
      compressed
      .blended(to: smile, amount: contour.crescent)
      .blended(to: chevron, amount: contour.chevron)
      .blended(to: CharacterInkGeometry.heart(in: heartBox), amount: contour.heart)
    let closedBox = CharacterRect(
      x: center.x - w / 2, y: center.y - thickness / 2, width: w, height: thickness)
    let closed = CharacterInkGeometry.capsule(in: closedBox)
      .blended(to: smile, amount: contour.crescent)
      .blended(to: chevron, amount: contour.chevron)
    let angle = clamp(eye.angle, -0.24, 0.24)
    let cosine = cos(angle)
    let sine = sin(angle)
    return expressed.blended(to: closed, amount: clamp(eye.blink)).mapped { p in
      let x = p.x - center.x
      let y = p.y - center.y
      return .init(
        x: center.x + x * cosine - y * sine,
        y: center.y + x * sine + y * cosine)
    }.path
  }
}

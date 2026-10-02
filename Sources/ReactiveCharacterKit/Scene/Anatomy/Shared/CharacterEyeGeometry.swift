import Foundation

enum CharacterEyeGeometry {
  /// Each eye has its own half-space, including rotation. Wide-eye poses cannot merge.
  static func halfBand(_ band: CharacterRect, midX: Double, left: Bool) -> CharacterRect {
    let center = min(band.x + band.width * 0.70, max(band.x + band.width * 0.30, midX))
    let gap = band.width * 0.045
    return left
      ? .init(x: band.x, y: band.y, width: center - gap / 2 - band.x, height: band.height)
      : .init(
        x: center + gap / 2, y: band.y,
        width: band.maxX - center - gap / 2, height: band.height)
  }

  static func size(
    width: Double, height: Double, eye: CharacterEyePose,
    contour: CharacterEyeContour
  ) -> (width: Double, height: Double) {
    let w = width * contour.widthScale
    let h = height * contour.heightScale
    let roundHeight = w * min(1, eye.height / max(0.001, eye.width))
    return (w, h + (roundHeight - h) * contour.circular)
  }

  static func path(
    _ contour: CharacterEyeContour, in box: CharacterRect, left: Bool,
    ellipse: Bool = false, corner: Double = 0.5
  ) -> CharacterVectorPath {
    let base =
      ellipse
      ? CharacterInkGeometry.ellipse(in: box)
      : CharacterInkGeometry.capsule(in: box, corner: corner)
    let compressed = base.mapped { p in
      let inner = left ? (p.x - box.x) / box.width : (box.maxX - p.x) / box.width
      let compression = contour.lidCompression * 0.42 + contour.innerPinch * inner * 0.48
      return .init(x: p.x, y: p.y + (box.maxY - p.y) * compression)
    }
    // Aperture is already encoded in the physical eye bounds by the motion sampler.
    // Flatten the silhouette near a complete blink without changing expression ownership.
    let aperture = min(1, max(0, (box.height / box.width - 0.14) / 0.32))
    let shapeAmount = aperture * aperture * (3 - 2 * aperture)
    let smiling = CharacterInkGeometry.ribbon(
      in: box,
      thickness: box.width * 0.16, rise: box.width * 0.27)
    return
      compressed
      .blended(to: smiling, amount: max(contour.crescent, contour.chevron) * shapeAmount)
      .blended(to: CharacterInkGeometry.ellipse(in: box), amount: contour.ellipse)
      .blended(to: CharacterInkGeometry.heart(in: box), amount: contour.heart * shapeAmount).path
  }
}

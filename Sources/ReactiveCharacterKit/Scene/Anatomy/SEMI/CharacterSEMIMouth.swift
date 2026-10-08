import Foundation

extension CharacterSEMIDrawing {
  // The supplied line references share a rounded triangle, a short stem and
  // two J-shaped lip lobes. SEMI never creates a mouth interior, even for voice.
  mutating func nose() {
    let anchor = faceAnchorRig
    let x = anchor.noseX
    let y = anchor.noseY
    let half = 10.8
    var nose = CharacterVectorPath()
    nose.move(x - half, y - 3.0)
    nose.quad(x, y - 6.0, x + half, y - 3.0)
    nose.cubic(x + half + 0.7, y + 0.8, x + 4.0, y + 5.2, x, y + 6.8)
    nose.cubic(x - 4.0, y + 5.2, x - half - 0.7, y + 0.8, x - half, y - 3.0)
    nose.close()
    add("nose", nose, fill: .solid(colors.nose), local: headActingTransform)
  }

  mutating func mouth() {
    let rig = expressionRig
    let anchor = faceAnchorRig
    let writing = writingIntensity
    let speech = rig.mouthOpenness * (1 - writing * 0.45)
    let smile = max(0, rig.mouthCurvature)
    let negative = max(0, -rig.mouthCurvature)
    let sadness = rig.sadness * rig.mouthArticulation
    let tension = rig.tension * rig.mouthArticulation
    let frown = Self.lineEase(min(1,
      negative * 0.95 + sadness * 0.30 + tension * 0.12))
    let joy = rig.joy * rig.mouthArticulation
    let courtesy = rig.gratitudeCourtesy * rig.mouthArticulation
    let heaviness = rig.heaviness * rig.mouthArticulation
    let x = anchor.mouthX
    let noseBottomY = anchor.noseY + 6.8
    let designedHalf = max(8.8, min(14.0,
      9.8 + (rig.mouthWidth - 0.60) * 5.0 + joy * 1.8
        + frown * 1.2 - courtesy * 1.3 - heaviness * 0.7 + speech * 0.65))
    let half = max(designedHalf, min(30, 3.65 / pixelScale))
    let designedDepth = max(2.8,
      6.7 + smile * 1.3 + joy * 0.6 - tension * 2.0
        - heaviness * 2.4 - writing * 1.5)
    let depth = max(designedDepth, min(15, 2.0 / pixelScale))
    let turnUp = 0.7 + smile * 1.4 + joy * 0.5 - courtesy * 0.4
    let cornerDrop = max(8.0 + sadness * 1.3 + heaviness * 0.7,
      min(14, 1.8 / pixelScale))
    let asymmetry = rig.mouthSkew * 3.2 * rig.mouthArticulation
    let lipWidth = readableStrokeWidth(2.9 + tension * 0.3, minimumPixels: 1.0)

    let maximumDepth = max(
      depth * (1 - frown) + cornerDrop * frown * 0.30 + abs(asymmetry) * 0.5,
      -turnUp * (1 - frown) + cornerDrop * frown + abs(asymmetry))
    let desiredY = noseBottomY + 9.0 - writing * 2.6 - heaviness * 2.2
      + courtesy * 0.8 + speech * 0.25
    // The held document owns the lower boundary. Shorten the stem smoothly as
    // the face bows; keep every line attached to the same moving nose and head.
    let ceiling = lowerFaceCeiling(centerX: x, halfWidth: half,
      inkWidth: lipWidth)
    let minimumY = noseBottomY + 2.8
    let verticalFit = min(1, max(0, (ceiling - minimumY) / maximumDepth))
    let y = max(minimumY, min(desiredY, ceiling - maximumDepth * verticalFit))

    let leftTipY = y + (-turnUp * (1 - frown) + cornerDrop * frown - asymmetry) * verticalFit
    let rightTipY = y + (-turnUp * (1 - frown) + cornerDrop * frown + asymmetry) * verticalFit
    let lobeY = y + depth * (1 - frown) * verticalFit
    let shoulder = half * 0.60 * frown
    var lips = CharacterVectorPath()
    lips.move(x - half, leftTipY)
    lips.cubic(x - half, lobeY + (cornerDrop * frown * 0.30 - asymmetry * 0.5) * verticalFit,
      x - shoulder, lobeY, x, y)
    lips.cubic(x + shoulder, lobeY,
      x + half, lobeY + (cornerDrop * frown * 0.30 + asymmetry * 0.5) * verticalFit,
      x + half, rightTipY)
    add("mouth.lips", lips, stroke: colors.mouth, width: lipWidth,
      local: headActingTransform)

    var stem = CharacterVectorPath()
    stem.move(anchor.noseX, noseBottomY)
    stem.cubic(anchor.noseX, noseBottomY + (y - noseBottomY) * 0.45,
      x, y - (y - noseBottomY) * 0.28, x, y)
    add("mouth.philtrum", stem, stroke: colors.mouth,
      width: readableStrokeWidth(2.1, minimumPixels: 0.85), local: headActingTransform)

    whiskers(centerX: x, centerY: y, lipHalf: half)
  }


  private func lowerFaceCeiling(centerX: Double, halfWidth: Double,
    inkWidth: Double) -> Double {
    let head = transform.concatenating(headActingTransform)
    guard head.d > 0.000_01 else { return 299 }
    let paper = transform.concatenating(documentTransform)
    let corners = [
      CharacterVectorPoint(x: document.minX, y: document.minY),
      CharacterVectorPoint(x: document.maxX, y: document.minY),
      CharacterVectorPoint(x: document.minX, y: document.maxY),
      CharacterVectorPoint(x: document.maxX, y: document.maxY),
    ]
    let paperTop = corners.map { paper.b * $0.x + paper.d * $0.y + paper.ty }.min() ?? 310
    let tiltedEdge = max(head.b * (centerX - halfWidth), head.b * (centerX + halfWidth))
    let inkScale = max(hypot(head.a, head.b), hypot(head.c, head.d))
    let margin = 2.5 * pixelScale + inkWidth * inkScale / 2
    return (paperTop - margin - head.ty - tiltedEdge) / head.d
  }

  private static func lineEase(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
  }
}

import Foundation

extension CharacterFullBodyCatDrawing {
  private static let cream = CharacterColor(uncheckedRed: 0.98, green: 0.95, blue: 0.88)
  private static let eyeShade = CharacterColor(uncheckedRed: 0.86, green: 0.82, blue: 0.76)
  private static let noseCream = CharacterColor(uncheckedRed: 0.96, green: 0.89, blue: 0.81)
  private static let noseShade = CharacterColor(uncheckedRed: 0.84, green: 0.75, blue: 0.67)
  private static let browCream = CharacterColor(uncheckedRed: 0.82, green: 0.75, blue: 0.65)
  private static let cavity = CharacterColor(uncheckedRed: 0.19, green: 0.10, blue: 0.11)
  private static let contactShade = CharacterColor(uncheckedRed: 0.031, green: 0.021, blue: 0.015)

  mutating func drawFeatures(
    _ face: CharacterFullBodyCatArtwork.Face, usesApplique: Bool,
    turn: CharacterFeltCatTransition.FaceTurn? = nil
  ) {
    let isProfile = face.left == nil || face.right == nil
    let frontal = 1 - (turn?.amount ?? (isProfile ? 1 : 0))
    if let left = face.left {
      drawEye(left, left: true, faceAngle: face.eyeAngle, frontal: frontal,
        usesApplique: usesApplique)
    }
    if let right = face.right {
      drawEye(right, left: false, faceAngle: face.eyeAngle, frontal: frontal,
        usesApplique: usesApplique)
    }
    if let muzzle = face.muzzle {
      if let turn {
        drawMuzzle(muzzle, usesApplique: usesApplique, turn: turn)
      } else if isProfile {
        drawProfileMuzzle(muzzle, usesApplique: usesApplique)
      } else {
        drawMuzzle(muzzle, usesApplique: usesApplique)
      }
    }
  }

  private mutating func drawEye(
    _ anchor: CharacterFullBodyCatArtwork.Eye, left: Bool, faceAngle: Double, frontal: Double,
    usesApplique: Bool
  ) {
    let eye = left ? pose.eyes.left : pose.eyes.right
    let contour = left ? pose.eyeContours.left : pose.eyeContours.right
    let brow = left ? pose.brows.left : pose.brows.right
    let gaze = pose.face
    let width = anchor.width
    let visibility = Self.unit(width / 5)
    let localX = gaze.gazeX * (3 + 10 * frontal) * visibility
    let localY = gaze.gazeY * 10 - brow.lift * 2
    let cosine = cos(faceAngle)
    let sine = sin(faceAngle)
    let center = CharacterVectorPoint(
      x: anchor.center.x + localX * cosine - localY * sine,
      y: anchor.center.y + localX * sine + localY * cosine)
    let thickness = min(width * 0.65, max(1.9, min(3.0, 0.82 / pixelScale)))
    let shape = CharacterCompactEyeGeometry.path(
      eye: eye, contour: contour, left: left, center: center,
      width: width, height: anchor.height, treatment: .vertical, thickness: thickness,
      oval: true, expressionWidth: width + (max(11.8, width * 1.12) - width) * frontal * visibility)
    let transform = CharacterSceneTransform.around(
      x: center.x, y: center.y, angle: faceAngle + brow.angle * 0.55)
    if usesApplique {
      drawContactShade(left ? "left-eye" : "right-eye", shape, center: center,
        width: width, height: anchor.height, transform: transform)
    }
    let material = usesApplique
      ? Self.appliqueMaterial(center: center, height: anchor.height, isNose: false)
      : Self.creamMaterial(center: center, height: anchor.height,
        highlight: Self.cream, shade: Self.eyeShade)
    feature(left ? "eye.left" : "eye.right", shape, fill: material, local: transform)
    // Pair a raised crease with a smaller, lower stroke without moving either eye.
    let oppositeBrow = left ? pose.brows.right : pose.brows.left
    let oppositeContour = left ? pose.eyeContours.right : pose.eyeContours.left
    let raised = Self.unit((brow.lift - 0.29) * 5)
    let paired = Self.unit((oppositeBrow.lift - 0.29) * 5) * (1 - oppositeContour.circular) * 0.68
    let support = max(0, paired - raised)
    let crease = (raised + support) * (1 - contour.circular) * frontal * visibility
    if crease > 0 {
      let half = width * 0.46 * crease
      let y = center.y - anchor.height * 0.64 - 4 + support * 6
      let slant = sin(brow.angle) * half * 1.8
      let bend = (2 + max(0, brow.bend)) * Self.unit(crease * 4)
      var path = CharacterVectorPath()
      path.move(center.x - half, y - slant)
      path.quad(center.x, y - bend, center.x + half, y + slant)
      feature(
        left ? "brow.left" : "brow.right", path,
        stroke: Self.browCream, lineWidth: thickness * crease * 0.92, opacity: Self.unit(crease / 0.12),
        local: .around(x: center.x, y: center.y, angle: faceAngle))
    }
  }

  private mutating func drawProfileMuzzle(
    _ anchor: CharacterFullBodyCatArtwork.Muzzle, usesApplique: Bool
  ) {
    let nose = anchor.nose
    let noseCenter = CharacterVectorPoint(x: nose.midX, y: nose.midY)
    let x = anchor.junction.x
    let y = anchor.junction.y
    let inward: Double = x < nose.midX ? -1 : 1
    let offset = CharacterSceneTransform(
      a: 1, b: 0, c: 0, d: 1, tx: pose.face.gazeX * 0.7, ty: pose.face.gazeY)
    let articulation = pose.mouth.visible ? Self.unit(pose.mouth.opacity) : 0
    let opening = Self.unit((pose.mouth.openness * articulation - 0.025) / 0.65)
    let curvature = min(1, max(-1, pose.mouth.curvature * articulation))
    let ink = max(1.2, min(1.9, 0.68 / pixelScale))
    let lips = profileLips(x: x, y: y, inward: inward, opening: opening,
      curvature: curvature, closedPath: opening > 0)
    var stem = CharacterVectorPath()
    stem.move(nose.midX + inward * nose.width * 0.18, nose.midY + nose.height * 0.31)
    stem.quad(x - inward * 1.1, y - 1.1, x, y)

    let noseShape = CharacterVectorPath.ellipse(nose)
    if usesApplique {
      drawContactShade("nose", noseShape, center: noseCenter, width: nose.width,
        height: nose.height, transform: offset)
    }
    feature("mouth.philtrum", stem, stroke: Self.cream, lineWidth: ink * 0.69, local: offset)
    feature("mouth", lips, fill: opening > 0 ? .solid(Self.cavity) : nil,
      stroke: Self.cream, lineWidth: ink, local: offset)
    let material = usesApplique
      ? Self.appliqueMaterial(center: noseCenter, height: nose.height, isNose: true)
      : Self.creamMaterial(center: noseCenter, height: nose.height,
        highlight: Self.noseCream, shade: Self.noseShade)
    feature("nose", noseShape, fill: material, local: offset)
  }

  private mutating func drawMuzzle(
    _ anchor: CharacterFullBodyCatArtwork.Muzzle, usesApplique: Bool,
    turn: CharacterFeltCatTransition.FaceTurn? = nil
  ) {
    let nose = anchor.nose
    let x = anchor.junction.x
    let y = anchor.junction.y
    let dx = x - nose.midX
    let dy = y - nose.midY
    let side = turn?.amount ?? 0
    func towardProfile(_ front: Double, _ profile: Double) -> Double {
      front + (profile - front) * side
    }
    let angle = atan2(-dx, dy) * (1 - side)
    let gaze = pose.face
    let offsetX = gaze.gazeX * towardProfile(5, 0.7)
    let offsetY = gaze.gazeY * towardProfile(3, 1)
    let noseTransform = CharacterSceneTransform.around(
      x: nose.midX, y: nose.midY, angle: angle, offsetX: offsetX, offsetY: offsetY)
    let mouthTransform = CharacterSceneTransform.around(
      x: x, y: y, angle: angle, offsetX: offsetX, offsetY: offsetY)
    let articulation = pose.mouth.visible ? Self.unit(pose.mouth.opacity) : 0
    let openness = Self.unit(pose.mouth.openness * articulation)
    let curvature = min(1, max(-1, pose.mouth.curvature * articulation))
    let smile = max(0, curvature)
    let frown = max(0, -curvature)
    let skews = min(1, max(-1, pose.mouth.skew * articulation)) * 2.7
    let widthChange = min(0.35, max(-0.35, (pose.mouth.width - 0.68) * articulation))
    let half = (nose.width * 0.74 + 1.9) * (1 + widthChange + smile * 0.20)
    let openingProgress = Self.unit((openness - 0.035) / 0.56)
    let opening = openingProgress * openingProgress * (3 - 2 * openingProgress)
    let circular = max(pose.eyeContours.left.circular, pose.eyeContours.right.circular)
    let openHalf = half * (1 + smile * 0.11) * (1 - circular * 0.36)
    let ink = towardProfile(max(1.7, min(2.9, 0.82 / pixelScale)),
      max(1.2, min(1.9, 0.68 / pixelScale)))
    let profileOpening = Self.unit((openness - 0.025) / 0.65)
    let mouthOpens = towardProfile(opening, profileOpening) > 0

    let cornerY = y + 4.2 + frown * 2.8 - smile * 6.2
    let shoulderY = y + 3.8 + smile * 3.8 - frown * 4.2
    let openY = y + 4.2 + circular * 0.5
    let topY = openY - (3.8 + circular * 1.4)
    let bottomY = openY + (4.8 + circular * 1.5)
    func mix(_ closed: Double, _ open: Double) -> Double { closed + (open - closed) * opening }

    let span = mix(half, openHalf)
    let leftY = mix(cornerY - skews, openY - skews * 0.5)
    let rightY = mix(cornerY + skews, openY + skews * 0.5)
    let upperCenterY = mix(y, topY)
    let lowerCenterY = mix(y, bottomY)
    let topShoulderY = mix(shoulderY, topY)
    let bottomShoulderY = mix(shoulderY, bottomY)

    var lips = CharacterVectorPath()
    lips.move(x - span, leftY)
    lips.cubic(
      x - span * mix(0.68, 1), mix(leftY, topY),
      x - span * mix(0.10, 0.60), topShoulderY, x, upperCenterY)
    lips.cubic(
      x + span * mix(0.10, 0.60), topShoulderY,
      x + span * mix(0.68, 1), mix(rightY, topY), x + span, rightY)
    if mouthOpens {
      lips.cubic(
        x + span * mix(0.68, 1), mix(rightY, bottomY),
        x + span * mix(0.10, 0.60), bottomShoulderY, x, lowerCenterY)
      lips.cubic(
        x - span * mix(0.10, 0.60), bottomShoulderY,
        x - span * mix(0.68, 1), mix(leftY, bottomY), x - span, leftY)
      lips.close()
    }

    let gap = max(1, hypot(dx, dy) - nose.height * 0.34)
    var stem = CharacterVectorPath()
    if let turn, side > 0 {
      let profile = profileLips(x: x, y: y, inward: turn.inward, opening: profileOpening,
        curvature: curvature, closedPath: mouthOpens)
      lips = Self.blendLips(lips, profile, weight: side)
      stem.move(
        towardProfile(x, nose.midX + turn.inward * nose.width * 0.18),
        towardProfile(y - gap, nose.midY + nose.height * 0.31))
      stem.quad(towardProfile(x, x - turn.inward * 1.1),
        towardProfile((y - gap + upperCenterY) / 2, y - 1.1), x, towardProfile(upperCenterY, y))
    } else {
      stem.move(x, y - gap)
      stem.line(x, upperCenterY)
    }
    let noseShape = CharacterVectorPath.ellipse(nose)
    let noseCenter = CharacterVectorPoint(x: nose.midX, y: nose.midY)
    if usesApplique {
      drawContactShade("nose", noseShape, center: noseCenter, width: nose.width,
        height: nose.height, transform: noseTransform)
    }
    feature(
      "mouth.philtrum", stem, stroke: Self.cream, lineWidth: ink * 0.69,
      local: mouthTransform)
    feature(
      "mouth", lips, fill: mouthOpens ? .solid(Self.cavity) : nil,
      stroke: Self.cream, lineWidth: ink, local: mouthTransform)
    let material = usesApplique
      ? Self.appliqueMaterial(center: noseCenter, height: nose.height, isNose: true)
      : Self.creamMaterial(center: noseCenter, height: nose.height,
        highlight: Self.noseCream, shade: Self.noseShade)
    feature("nose", noseShape, fill: material, local: noseTransform)
  }

  /// A profile is one visible half of the muzzle. The hidden half has zero length so
  /// the same control points can be interpolated as the nose turns toward the silhouette.
  private func profileLips(
    x: Double, y: Double, inward: Double, opening: Double, curvature: Double, closedPath: Bool
  ) -> CharacterVectorPath {
    let span = inward * (5.6 + 3 * Self.unit(pose.mouth.width))
    let cornerY = y + 1.3 - 2.6 * curvature
    let farX = x + span
    var path = CharacterVectorPath()
    if inward > 0 {
      path.move(x, y)
      path.cubic(x, y, x, y, x, y)
      path.cubic(x + span * 0.31, y + 1.5 - 2.7 * opening,
        x + span * 0.71, cornerY + 0.3 - 1.8 * opening, farX, cornerY)
      if closedPath {
        path.cubic(x + span * 0.72, cornerY + opening * 5.6, x + span * 0.22, y + opening * 4.1, x, y)
        path.cubic(x, y, x, y, x, y)
      }
    } else {
      path.move(farX, cornerY)
      path.cubic(x + span * 0.71, cornerY + 0.3 - 1.8 * opening,
        x + span * 0.31, y + 1.5 - 2.7 * opening, x, y)
      path.cubic(x, y, x, y, x, y)
      if closedPath {
        path.cubic(x, y, x, y, x, y)
        path.cubic(x + span * 0.22, y + opening * 4.1, x + span * 0.72, cornerY + opening * 5.6, farX, cornerY)
      }
    }
    if closedPath { path.close() }
    return path
  }

  private static func blendLips(
    _ front: CharacterVectorPath, _ profile: CharacterVectorPath, weight: Double
  ) -> CharacterVectorPath {
    func mix(_ a: CharacterVectorPoint, _ b: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(x: a.x + (b.x - a.x) * weight, y: a.y + (b.y - a.y) * weight)
    }
    var path = CharacterVectorPath()
    path.commands = zip(front.commands, profile.commands).map { a, b in
      switch (a, b) {
      case (.move(let f), .move(let p)): .move(mix(f, p))
      case (.cubic(let f1, let f2, let fe), .cubic(let p1, let p2, let pe)):
        .cubic(control1: mix(f1, p1), control2: mix(f2, p2), end: mix(fe, pe))
      default: a
      }
    }
    return path
  }

  private mutating func drawContactShade(
    _ id: String, _ shape: CharacterVectorPath, center: CharacterVectorPoint,
    width: Double, height: Double, transform: CharacterSceneTransform
  ) {
    // Follow the animated contour so the shadow stays attached during a blink or gaze shift.
    let offset = CharacterSceneTransform.around(
      x: center.x, y: center.y, scaleX: 1.07, scaleY: 1.05, offsetX: 0.45, offsetY: 0.65)
    feature(
      "contact-shadow.\(id)", shape,
      fill: .radial(
        center: .init(x: center.x + width * 0.15, y: center.y + height * 0.29),
        radius: max(width, height) * 0.70,
        stops: [
          .init(location: 0, color: Self.contactShade, opacity: 0.58),
          .init(location: 1, color: Self.contactShade, opacity: 0),
        ]), local: transform.concatenating(offset))
  }

  private static func appliqueMaterial(
    center: CharacterVectorPoint, height: Double, isNose: Bool
  ) -> CharacterScenePaint {
    let highlight = isNose ? noseCream : cream
    let midtone = isNose
      ? CharacterColor(uncheckedRed: 0.91, green: 0.82, blue: 0.72)
      : CharacterColor(uncheckedRed: 0.93, green: 0.87, blue: 0.77)
    let shade = isNose
      ? CharacterColor(uncheckedRed: 0.80, green: 0.70, blue: 0.60)
      : CharacterColor(uncheckedRed: 0.81, green: 0.73, blue: 0.63)
    return .linear(
      start: .init(x: center.x - height * 0.31, y: center.y - height * 0.47),
      end: .init(x: center.x + height * 0.31, y: center.y + height * 0.63),
      stops: [
        .init(location: 0, color: highlight, opacity: 1),
        .init(location: 0.46, color: midtone, opacity: 1),
        .init(location: 1, color: shade, opacity: 1),
      ])
  }

  private static func creamMaterial(
    center: CharacterVectorPoint, height: Double, highlight: CharacterColor, shade: CharacterColor
  ) -> CharacterScenePaint {
    .linear(
      start: .init(x: center.x - height * 0.13, y: center.y - height * 0.42),
      end: .init(x: center.x + height * 0.13, y: center.y + height * 0.63),
      stops: [
        .init(location: 0, color: highlight, opacity: 1),
        .init(location: 0.40, color: highlight, opacity: 1),
        .init(location: 1, color: shade, opacity: 1),
      ])
  }

  private static func unit(_ value: Double) -> Double {
    min(1, max(0, value))
  }
}

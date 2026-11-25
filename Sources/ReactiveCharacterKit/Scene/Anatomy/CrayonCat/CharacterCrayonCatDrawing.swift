import Foundation

struct CharacterCrayonCatDrawing {
  private let pose: CharacterPose
  private let body: CharacterSceneTransform
  private let head: CharacterSceneTransform
  private let mirrored: Bool
  private var nodes: [CharacterSceneNode] = []

  static func nodes(
    pose: CharacterPose, motion: CharacterFullBodyCatMotion, board: CharacterRect,
    transform: CharacterSceneTransform, tone: CharacterDesignAppearance
  ) -> [CharacterSceneNode] {
    let placement = CharacterFullBodyCatStage.place(motion, on: transform.concatenating(registration(in: board)))
    let stance = CharacterCrayonCatStance(pose: motion.pose, facing: motion.puffDirection)
    if motion.crayonStances.isEmpty {
      var nodes = draw(stance, pose: pose, motion: motion, placement: placement, dark: tone == .dark)
      if stance.pose == .waving { addPawToes(to: &nodes, raised: 1) }
      return nodes
    }
    var result: [CharacterSceneNode] = []
    var total = 0.0
    for sample in motion.crayonStances {
      let next = draw(sample.stance, pose: pose, motion: motion, placement: .identity, dark: tone == .dark)
      total += sample.weight
      result = CharacterCrayonCatMorph.blend(result, next, progress: sample.weight / total)
    }
    let raised = motion.crayonStances.reduce(0.0) { $0 + ($1.stance.pose == .waving ? $1.weight : 0) }
    addPawToes(to: &result, raised: raised)
    return result.map { CharacterCrayonCatMorph.placed($0, by: placement) }
  }

  private static func addPawToes(to nodes: inout [CharacterSceneNode], raised: Double) {
    guard raised > 0.42, let index = nodes.firstIndex(where: { $0.id == "full-body-cat.paw.wave" })
    else { return }
    let paw = nodes[index]
    let contour = paw.path.commands
    guard contour.count == 6, case .cubic(_, _, let left) = contour[1],
      case .cubic(let capLeft, let capRight, let right) = contour[2]
    else { return }

    // Read the live cap after bending or morphing so the wax stays on the foot.
    let center = CharacterVectorPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
    let acrossX = right.x - left.x
    let acrossY = right.y - left.y
    let forwardX = (capLeft.x + capRight.x) / 2 - center.x
    let forwardY = (capLeft.y + capRight.y) / 2 - center.y
    func point(_ across: Double, _ forward: Double) -> CharacterVectorPoint {
      .init(x: center.x + across * acrossX + forward * forwardX,
            y: center.y + across * acrossY + forward * forwardY)
    }
    var toes = CharacterVectorPath()
    for (across, length) in [(-0.20, 0.28), (0.0, 0.38), (0.19, 0.26)] {
      let start = point(across, 0.40)
      let end = point(across * 0.77, 0.40 - length)
      toes.move(start.x, start.y)
      toes.line(end.x, end.y)
    }
    let influence = min(1, (raised - 0.42) / 0.46)
    nodes.insert(.init(id: "full-body-cat.paw.wave.toes", layer: .surface, path: toes,
      fill: nil, stroke: toeWax, lineWidth: 2.35, opacity: influence * influence * (3 - 2 * influence),
      transform: paw.transform, clips: [paw.path]), at: index + 1)
  }

  private static func draw(
    _ stance: CharacterCrayonCatStance, pose: CharacterPose, motion: CharacterFullBodyCatMotion,
    placement: CharacterSceneTransform, dark: Bool
  ) -> [CharacterSceneNode] {
    let art = CharacterCrayonCatGeometry.resolve(stance.pose)
    let mirrored = stance.pose == .puffed && stance.facing == .right
    let body = mirrored ? placement.concatenating(.around(x: 128, y: 0, scaleX: -1)) : placement
    let head = body.concatenating(rotation(at: art.headPivot, by: mirrored ? -motion.headAngle : motion.headAngle))
    var drawing = Self(pose: pose, body: body, head: head, mirrored: mirrored)
    drawing.draw(art, motion: motion, facingRight: stance.pose == .right, dark: dark)
    return drawing.nodes
  }

  static func faceBounds(for motion: CharacterFullBodyCatMotion, in board: CharacterRect) -> CharacterRect {
    let fallback = CharacterCrayonCatStance(pose: motion.pose, facing: motion.puffDirection)
    let samples = motion.crayonStances.isEmpty ? [.init(stance: fallback, weight: 1)] : motion.crayonStances
    let rect = samples.reduce(CharacterRect(x: 0, y: 0, width: 0, height: 0)) { sum, sample in
      let stance = sample.stance
      let face = CharacterCrayonCatGeometry.resolve(stance.pose).face?.bounds
        ?? .init(x: 0, y: 0, width: 256, height: 256)
      let x = stance.pose == .puffed && stance.facing == .right ? 256 - face.maxX : face.x
      return .init(x: sum.x + sample.weight * x, y: sum.y + sample.weight * face.y,
        width: sum.width + sample.weight * face.width, height: sum.height + sample.weight * face.height)
    }
    let placement = registration(in: board)
    return .init(x: rect.x * placement.a + placement.tx, y: rect.y * placement.d + placement.ty,
      width: rect.width * placement.a, height: rect.height * placement.d)
  }

  private static func registration(in board: CharacterRect) -> CharacterSceneTransform {
    let scale = board.width / 256
    return .init(a: scale, b: 0, c: 0, d: scale, tx: board.x, ty: board.y)
  }

  private mutating func draw(
    _ art: CharacterCrayonCatArtwork, motion: CharacterFullBodyCatMotion, facingRight: Bool, dark: Bool
  ) {
    let edge = dark ? Self.color(0.43, 0.385, 0.43) : Self.color(0.091, 0.080, 0.106)
    for part in art.parts {
      let transform: CharacterSceneTransform
      switch part.motion {
      case .body, .tail, .paw: transform = body
      case .head: transform = head
      case .leg(let leg):
        if let hip = part.pivot, let foot = part.foot {
          let step = motion.step(for: leg).transform(hip: hip, foot: foot, direction: facingRight ? 1 : -1)
          transform = body.concatenating(step)
        } else {
          transform = body
        }
      }
      let wag = part.id == "tail" ? motion.tailAngle : 0
      // The root stays attached while the tip follows through a wider arc.
      func animated(_ path: CharacterVectorPath) -> CharacterVectorPath {
        if case .paw = part.motion, motion.pawAngle != 0,
          let shoulder = art.pawPivot, let elbow = part.pivot {
          return Self.bentPaw(path, shoulder: shoulder, elbow: elbow, angle: motion.pawAngle)
        }
        guard wag != 0, let root = art.tailPivot else { return path }
        return path.mapped { point in
          let reach = min(1, hypot(point.x - root.x, point.y - root.y) / 65)
          let angle = wag * reach
          let dx = point.x - root.x
          let dy = point.y - root.y
          return .init(x: root.x + cos(angle) * dx - sin(angle) * dy,
            y: root.y + sin(angle) * dx + cos(angle) * dy)
        }
      }
      let fill = animated(part.path)
      // All fills cover overlapping outline strokes from behind, leaving one readable boundary.
      add("outline.\(part.id)", animated(part.outline), layer: .behindSurface,
        stroke: edge, width: part.outlined ? 4.4 : 3.4, transform: transform)
      add(part.id, fill, layer: .surface, fill: Self.wax(part.tone, dark: dark),
        transform: transform)
      add("wax.\(part.id)", animated(part.waxMarks), layer: .surface,
        stroke: Self.grain(part.tone, dark: dark), width: 1.55,
        transform: transform, clips: [fill])
    }
    if let face = art.face {
      if let left = face.left { drawEye(left, left: true, angle: face.eyeAngle) }
      if let right = face.right { drawEye(right, left: false, angle: face.eyeAngle) }
      if let muzzle = face.muzzle { drawMuzzle(muzzle) }
    }
  }

  private static func bentPaw(
    _ path: CharacterVectorPath, shoulder: CharacterVectorPoint, elbow: CharacterVectorPoint, angle: Double
  ) -> CharacterVectorPath {
    let dx = elbow.x - shoulder.x
    let dy = elbow.y - shoulder.y
    let span = dx * dx + dy * dy
    return path.mapped { point in
      // Leave the buried shoulder still and build up movement through the elbow.
      let along = ((point.x - shoulder.x) * dx + (point.y - shoulder.y) * dy) / span
      let amount = min(1, max(0, (along - 0.36) / 0.94))
      let turn = angle * amount * amount * (3 - 2 * amount)
      let x = point.x - elbow.x
      let y = point.y - elbow.y
      return .init(x: elbow.x + cos(turn) * x - sin(turn) * y,
        y: elbow.y + sin(turn) * x + cos(turn) * y)
    }
  }

  private mutating func drawEye(
    _ anchor: CharacterCrayonCatArtwork.Eye, left: Bool, angle: Double
  ) {
    let visualLeft = mirrored ? !left : left
    let horizontal = mirrored ? -1.0 : 1.0
    let eye = visualLeft ? pose.eyes.left : pose.eyes.right
    let contour = visualLeft ? pose.eyeContours.left : pose.eyeContours.right
    let brow = visualLeft ? pose.brows.left : pose.brows.right
    let gaze = pose.face
    let center = CharacterVectorPoint(x: anchor.center.x + gaze.gazeX * 4 * horizontal,
      y: anchor.center.y + gaze.gazeY * 3 - brow.lift * 2)
    let eyePath = CharacterCompactEyeGeometry.path(
      eye: eye, contour: contour, left: left, center: center,
      width: anchor.width, height: anchor.height, treatment: .vertical,
      thickness: 3.6, oval: true, expressionWidth: anchor.width * 1.35)
    let tilt = Self.rotation(at: center, by: angle + brow.angle * 0.56 * horizontal)
    let path = eyePath.mapped {
      .init(x: $0.x + 0.45 * sin($0.y * 0.41), y: $0.y + 0.47 * sin($0.x * 0.37))
    }
    let eyeTransform = head.concatenating(tilt)
    let side = visualLeft ? "left" : "right"
    add("eye.\(side)", path, layer: .features, fill: Self.eyeWax, transform: eyeTransform)

    let roundEye = (1 - eye.blink) * (1 - max(contour.crescent, contour.chevron,
      contour.heart, contour.innerPinch, contour.lidCompression))
    if roundEye > 0.10 {
      let pupilWidth = anchor.width * 0.52 * roundEye
      let pupilHeight = anchor.height * 0.57 * roundEye
      let pupil = CharacterRect(
        x: center.x + gaze.gazeX * 3.5 * horizontal - pupilWidth / 2,
        y: center.y + 1.35 + gaze.gazeY * 2.7 - pupilHeight / 2,
        width: pupilWidth, height: pupilHeight)
      add("pupil.\(side)", .ellipse(pupil), layer: .features,
        fill: Self.pupilWax, transform: eyeTransform, clips: [path])
    }

    let browStrength = min(1, abs(brow.angle) * 3 + abs(brow.lift) * 1.4 + abs(brow.bend) * 0.65)
    guard browStrength > 0 else { return }
    let browX = anchor.center.x + gaze.gazeX * 3.5 * horizontal
    let browY = center.y - anchor.height * 0.54 - 5 - brow.lift * 5
    let halfWidth = anchor.width * (0.44 + 0.12 * browStrength)
    let slant = brow.angle * horizontal * halfWidth * 1.35
    var eyebrow = CharacterVectorPath()
    eyebrow.move(browX - halfWidth, browY - slant)
    eyebrow.quad(browX - 0.8, browY - 0.8 - brow.bend * 8, browX + halfWidth, browY + slant)
    add(visualLeft ? "brow.left" : "brow.right", eyebrow, layer: .features,
      stroke: Self.browWax, width: 2.9 * browStrength,
      transform: head.concatenating(Self.rotation(at: center, by: angle)))
  }

  private mutating func drawMuzzle(_ muzzle: CharacterCrayonCatArtwork.Muzzle) {
    let x = muzzle.junction.x
    let y = muzzle.junction.y
    let angle = atan2(muzzle.nose.midX - x, y - muzzle.nose.midY)
    let local = head.concatenating(Self.rotation(at: muzzle.junction, by: angle))
    let smile = min(1, max(0, pose.mouth.curvature))
    let frown = min(1, max(0, -pose.mouth.curvature))
    // Keep resting lips as one line. Small aperture changes grow the same line into an opening.
    let opening = min(1, max(0, (pose.mouth.openness * pose.mouth.opacity - 0.045) / 0.955))
    let spread = min(1.36, max(0.56, pose.mouth.width + 0.27))
    let roundness = min(1, opening * 1.30) * (1 - smile) * (1 - frown)
    let bias = pose.mouth.skew * (mirrored ? -3.6 : 3.6)
    // The far corner disappears around the cheek in profile, while a rounded mouth stays legible.
    let farLip = 0.23 + 0.65 * roundness
    let left = 8.6 * spread * (muzzle.profileDirection < 0 ? farLip : 1)
    let right = 9.2 * spread * (muzzle.profileDirection > 0 ? farLip : 1)
    let corner = y + 2.6 - 5.8 * smile + 4.8 * frown + 1.1 * roundness
    let leftTip = corner - bias + 0.45
    let rightTip = corner + bias - 0.3
    let upper = y - 0.9 * frown - opening * (1.5 + 3.8 * roundness)
    let lipCurve = y + 6.0 - 7.4 * smile - 7.5 * frown - opening * (2.4 + 8 * roundness)
    var mouth = CharacterVectorPath()
    mouth.move(x - left, leftTip)
    mouth.quad(x - left * 0.31, lipCurve + 0.45, x, upper)
    mouth.quad(x + right * 0.41, lipCurve - 0.4, x + right, rightTip)
    if opening > 0 {
      let lower = upper + opening * (8.5 + 7.8 * roundness + 6.5 * smile)
      let lowerCurve = lipCurve + opening * (13.3 + 7 * roundness + 8 * smile)
      mouth.quad(x + right * 0.50, lowerCurve - 0.4, x + 0.45 * opening, lower)
      mouth.quad(x - left * 0.44, lowerCurve + 0.45, x - left, leftTip)
      mouth.close()
    }
    add("mouth", mouth, layer: .features, fill: opening > 0 ? Self.mouthInk : nil, stroke: Self.cream,
      width: 2.45, transform: local)
    var line = CharacterVectorPath()
    line.move(x, y - 6)
    line.line(x, upper)
    add("mouth.philtrum", line, layer: .features, stroke: Self.cream, width: 2.3, transform: local)
    let nose = muzzle.nose
    var noseMark = CharacterVectorPath()
    noseMark.move(nose.minX, nose.midY - 0.5)
    noseMark.cubic(nose.minX + 0.5, nose.minY - 0.7, nose.maxX - 0.4, nose.minY, nose.maxX, nose.midY)
    noseMark.quad(nose.maxX - 0.1, nose.midY + 1.25, nose.midX + 0.45, nose.maxY)
    noseMark.quad(nose.minX + 0.4, nose.midY + 1.62, nose.minX, nose.midY - 0.5)
    noseMark.close()
    let noseTransform = head.concatenating(.around(x: nose.midX, y: nose.midY, angle: angle))
    add("nose", noseMark, layer: .features, fill: Self.nose, transform: noseTransform)
    if muzzle.profileDirection == 0 {
      var cheeks = CharacterVectorPath()
      cheeks.move(x - 29.5, y - 7.6)
      cheeks.quad(x - 25.7, y - 7.3, x - 21.5, y - 6.1)
      cheeks.move(x - 26, y - 1)
      cheeks.line(x - 21.2, y - 1.8)
      cheeks.move(x + 20.5, y - 6)
      cheeks.quad(x + 25.2, y - 7.2, x + 29.2, y - 7.9)
      cheeks.move(x + 21, y - 1)
      cheeks.line(x + 25, y - 0.7)
      add("cheeks", cheeks, layer: .features, stroke: Self.cheekWax, width: 2.1, transform: local)
    }
  }

  private mutating func add(
    _ id: String, _ path: CharacterVectorPath, layer: CharacterSceneLayer,
    fill: CharacterColor? = nil, stroke: CharacterColor? = nil, width: Double = 0,
    transform: CharacterSceneTransform, clips: [CharacterVectorPath] = []
  ) {
    nodes.append(.init(id: "full-body-cat.\(id)", layer: layer, path: path,
      fill: fill.map { .solid($0) }, stroke: stroke, lineWidth: width,
      opacity: 1, transform: transform, clips: clips))
  }

  private static func rotation(at point: CharacterVectorPoint?, by angle: Double) -> CharacterSceneTransform {
    guard let point, angle != 0 else { return .identity }
    return .around(x: point.x, y: point.y, angle: angle)
  }

  private static func wax(_ tone: CharacterCrayonCatArtwork.Tone, dark: Bool) -> CharacterColor {
    switch (tone, dark) {
    case (.far, false): color(0.115, 0.098, 0.122)
    case (.near, false), (.tail, false): color(0.172, 0.148, 0.180)
    case (.torso, false): color(0.190, 0.162, 0.194)
    case (.head, false): color(0.211, 0.174, 0.209)
    case (.far, true): color(0.166, 0.144, 0.172)
    case (.near, true), (.tail, true): color(0.228, 0.197, 0.232)
    case (.torso, true): color(0.244, 0.210, 0.243)
    case (.head, true): color(0.270, 0.229, 0.264)
    }
  }

  private static func grain(_ tone: CharacterCrayonCatArtwork.Tone, dark: Bool) -> CharacterColor {
    let fill = wax(tone, dark: dark)
    return color(fill.red + 0.102, fill.green + 0.083, fill.blue + 0.073)
  }

  private static let cheekWax = color(0.654, 0.432, 0.408)
  private static let toeWax = color(0.78, 0.55, 0.49)
  private static let eyeWax = color(0.970, 0.864, 0.715)
  private static let pupilWax = color(0.326, 0.221, 0.221)
  private static let cream = color(0.976, 0.90, 0.775)
  private static let browWax = color(0.748, 0.586, 0.494)
  private static let nose = color(0.882, 0.665, 0.585)
  private static let mouthInk = color(0.15, 0.10, 0.09)

  private static func color(_ r: Double, _ g: Double, _ b: Double) -> CharacterColor {
    .init(uncheckedRed: r, green: g, blue: b)
  }
}

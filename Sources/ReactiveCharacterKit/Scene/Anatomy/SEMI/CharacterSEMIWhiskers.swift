import Foundation

extension CharacterSEMIDrawing {
  // Six strands share the sampled pose. Curl, reach and ripple are anatomy
  // projections; clocks, state and interruption remain presentation-owned.
  mutating func whiskers(centerX x: Double, centerY y: Double, lipHalf: Double) {
    let rig = expressionRig
    let motion = pose.detailMotion
    // A relaxed half-lid or body bob is not a sagging whisker cue.
    let heavy = rig.heaviness * (1 - rig.calmTrust)
    let happy = rig.joy
    let alert = rig.alert
    let distress = rig.anxiety * (1 - rig.surprise)
    let tension = max(distress, rig.tension)
    let impulse = min(1, motion.impulse * motion.amount)
    // Ordinary acting changes the direction and reach of extended shafts.
    // Retraction, curl and electric ripples belong to strong distress/impact cues.
    let compression = Self.whiskerEase(min(1, max(0,
      (distress - 0.32) / 0.50, (tension - 0.38) / 0.50,
      (impulse - 0.12) / 0.48)))
    let electric = compression
    let rootDistance = 18.8 + lipHalf * 0.06
    let rootSpacing = max(2.6, min(6, 0.8 / pixelScale))
    let reachScale = 1 + happy * 0.16 + alert * 0.08
      + rig.affection * 0.08 - compression * 0.22
    let fanScale = 1 + happy * 0.24 + alert * 0.12 - heavy * 0.12
    let directionLift = -happy * 0.15 - alert * 0.035
      - rig.affection * 0.05 + heavy * 0.40
    let head = transform.concatenating(headActingTransform)
    let protectedEyes = whiskerProtectedEyes()
    let paperRegion = whiskerPaperRegion()
    let paper = paperRegion?.bounds
    let inkWidth = readableStrokeWidth(1.65 + electric * 0.25, minimumPixels: 0.72)
    let edgeWidth = inkWidth + readableStrokeWidth(1.0, minimumPixels: 0.65)
    let inkScale = max(hypot(head.a, head.b), hypot(head.c, head.d))
    let clearance = edgeWidth * inkScale / 2 + max(0.55, pixelScale * 1.2)
    let releaseDistance = max(1, pixelScale * 9)
    let segments = 8
    var path = CharacterVectorPath()

    for left in [true, false] {
      let sign = left ? -1.0 : 1.0
      for strand in 0..<3 {
        let row = Double(strand - 1)
        let offset = row * 0.72 + sign * 0.18
        let sway = (motion.sway * cos(offset) + motion.swayQuadrature * sin(offset)) * motion.amount
        let breath = (motion.swayQuadrature * cos(offset) - motion.sway * sin(offset)) * motion.amount
        let flick = (motion.quiver * cos(offset) + motion.quiverQuadrature * sin(offset)) * motion.amount
        let shaftLength = max(10, 22 * [0.72, 1.0, 0.94][strand] * reachScale
          + breath * 1.6 + compression * flick * 0.8)
        let shaftSlope = row * 0.24 * fanScale + directionLift
          + sway * (0.11 + happy * 0.035) + row * breath * 0.025
        let root = CharacterVectorPoint(x: x + sign * rootDistance,
          y: y - 0.3 + row * rootSpacing)
        let shaftY = shaftSlope * shaftLength
        let gravity = 1.0 + heavy * 2.0
        let deepSag = Self.whiskerEase((heavy - 0.30) / 0.40)
        let tip = CharacterVectorPoint(x: root.x + sign * shaftLength,
          y: root.y + shaftY + gravity)
        let first = CharacterVectorPoint(x: root.x + sign * shaftLength / 3,
          y: root.y + shaftY / 3)
        let second = CharacterVectorPoint(x: root.x + sign * shaftLength * 2 / 3,
          y: root.y + shaftY * 2 / 3 + gravity / 3 - deepSag * 5.5)

        func sample(_ t: Double) -> CharacterVectorPoint {
          let u = 1 - t
          let w0 = u * u * u
          let w1 = 3 * u * u * t
          let w2 = 3 * u * t * t
          let w3 = t * t * t
          let bx = w0 * root.x + w1 * first.x + w2 * second.x + w3 * tip.x
          let by = w0 * root.y + w1 * first.y + w2 * second.y + w3 * tip.y
          let dx = 3 * u * u * (first.x - root.x)
            + 6 * u * t * (second.x - first.x) + 3 * t * t * (tip.x - second.x)
          let dy = 3 * u * u * (first.y - root.y)
            + 6 * u * t * (second.y - first.y) + 3 * t * t * (tip.y - second.y)
          let magnitude = max(0.000_001, hypot(dx, dy))
          let envelope = sin(.pi * t)
          let spatial = sin(4 * .pi * t + row * 0.35) * (0.85 + motion.quiverQuadrature * motion.amount * 0.40)
            + cos(4 * .pi * t + row * 0.35) * motion.quiver * motion.amount * 0.55
          let ripple = spatial * electric * envelope * (2.4 + impulse * 1.2)
          return .init(x: bx - dy / magnitude * ripple,
            y: by + dx / magnitude * ripple)
        }

        var knots = (0...segments).map { index in
          Self.whiskerApply(head, sample(Double(index) / Double(segments)))
        }
        let ordinary = compression < 0.02 && heavy < 0.45
        if ordinary {
          // Fit the complete shaft. Per-control obstacle pushes turn straight
          // whiskers into rails and S-hooks, so ordinary acting never uses them.
          let rawRoot = Self.whiskerApply(head, root)
          var best = knots
          var bestPenalty = Double.greatestFiniteMagnitude
          fit: for reachFactor in [1.0, 0.92, 0.84, 0.76] {
            let samples = (0...32).map { index in
              Self.whiskerApply(head, sample(Double(index) / 32 * reachFactor))
            }
            let limits = samples.map { p in
              (protectedEyes.compactMap {
                $0.extent(at: p.x, padding: clearance, lower: true)
              }.max().map { $0 + clearance },
               paperRegion?.extent(at: p.x, padding: clearance, lower: false)
                .map { $0 - clearance })
            }
            for angleFactor in [1.0, 0.85, 0.70, 0.55, 0.40] {
              var probes = samples.map { p in
                CharacterVectorPoint(x: p.x,
                  y: rawRoot.y + (p.y - rawRoot.y) * angleFactor)
              }
              var lowerShift = -Double.greatestFiniteMagnitude
              var upperShift = Double.greatestFiniteMagnitude
              for (p, limits) in zip(probes, limits) {
                if let eyeFloor = limits.0 {
                  lowerShift = max(lowerShift, eyeFloor - p.y)
                }
                if let paperTop = limits.1 {
                  upperShift = min(upperShift, paperTop - p.y)
                }
              }
              let shift = min(upperShift, max(lowerShift, 0))
              probes = probes.map { .init(x: $0.x, y: $0.y + shift) }
              let penalty = probes.reduce(0.0) { total, p in
                total + protectedEyes.reduce(0) { $0 + $1.penalty(p, clearance: clearance) }
                  + (paperRegion?.penalty(p, clearance: clearance) ?? 0)
              }
              if penalty < bestPenalty {
                best = (0...segments).map { probes[$0 * 4] }
                bestPenalty = penalty
              }
              if penalty == 0 { break fit }
            }
          }
          knots = best
        }
        var controls: [(CharacterVectorPoint, CharacterVectorPoint)] = []
        for index in 0..<segments {
          let before = knots[max(0, index - 1)]
          let after = knots[min(segments, index + 2)]
          let start = knots[index]
          let end = knots[index + 1]
          controls.append((
            .init(x: start.x + (end.x - before.x) / 6,
              y: start.y + (end.y - before.y) / 6),
            .init(x: end.x - (after.x - start.x) / 6,
              y: end.y - (after.y - start.y) / 6)))
        }

        // Constrain the curve hull, not just its endpoints. The peripheral
        // strands can rise or droop beside the face/card without crossing either.
        for _ in 0..<(ordinary ? 0 : 2) {
          for index in 0..<segments {
            var hull = [knots[index], controls[index].0, controls[index].1, knots[index + 1]]
            for eye in protectedEyes {
              let influence = Self.whiskerInfluence(hull, bounds: eye.bounds, release: releaseDistance)
              if influence > 0 {
                hull = hull.map { p in
                  .init(x: p.x, y: p.y + max(0, eye.bounds.maxY + clearance - p.y) * influence)
                }
              }
            }
            if let paper {
              let influence = Self.whiskerInfluence(hull, bounds: paper, release: releaseDistance)
              if influence > 0 {
                hull = hull.map { p in
                  .init(x: p.x, y: p.y - max(0, p.y - paper.minY + clearance) * influence)
                }
              }
            }
            knots[index] = hull[0]
            controls[index] = (hull[1], hull[2])
            knots[index + 1] = hull[3]
          }
        }
        let local = knots.map { Self.whiskerInverse(head, $0) }
        path.move(local[0].x, local[0].y)
        for index in 0..<segments {
          let c1 = Self.whiskerInverse(head, controls[index].0)
          let c2 = Self.whiskerInverse(head, controls[index].1)
          path.cubic(c1.x, c1.y, c2.x, c2.y, local[index + 1].x, local[index + 1].y)
        }
      }
    }
    add("mouth.whiskers.edge", path, stroke: colors.outline,
      width: edgeWidth,
      opacity: 0.72, local: headActingTransform)
    add("mouth.whiskers", path, stroke: colors.mouthDetail, width: inkWidth,
      opacity: 0.64 + electric * 0.12, local: headActingTransform)
  }

  private func whiskerProtectedEyes() -> [WhiskerInkRegion] {
    guard colors.eyes.alpha > 0.02 else { return [] }
    func unblinked(_ eye: CharacterEyePose) -> CharacterEyePose {
      .init(centerX: eye.centerX, centerY: eye.centerY,
        width: eye.unblinkedWidth, height: eye.unblinkedHeight, angle: eye.angle,
        unblinkedWidth: eye.unblinkedWidth, unblinkedHeight: eye.unblinkedHeight, blink: 0)
    }
    let source = pose
    let stable = CharacterPose(
      eyes: .init(left: unblinked(source.eyes.left), right: unblinked(source.eyes.right)),
      noseOffsetX: source.noseOffsetX, mouth: source.mouth, surface: source.surface,
      writingPhase: source.writingPhase, writingMotionPhase: source.writingMotionPhase,
      writingProgress: source.writingProgress, writingVisible: source.writingVisible,
      writingOpacity: source.writingOpacity, motionEnergy: source.motionEnergy,
      eyeContours: source.eyeContours, faceDynamics: source.faceDynamics,
      detailMotion: source.detailMotion)
    var proxy = Self(pose: stable, transform: transform,
      simplified: simplified, expressionRig: expressionRig)
    proxy.eye(left: true)
    proxy.eye(left: false)
    return proxy.nodes.compactMap { node in
      let principal = node.id == "eye.left" || node.id == "eye.right"
        || node.id == "eye.left.closed" || node.id == "eye.right.closed"
      guard principal, node.opacity > 0.02,
        node.fill != nil || node.stroke != nil else { return nil }
      let points = Self.whiskerFlatten(node.path).map { Self.whiskerApply(node.transform, $0) }
      let strokeScale = max(hypot(node.transform.a, node.transform.b),
        hypot(node.transform.c, node.transform.d))
      return WhiskerInkRegion(points: points, closed: node.fill != nil,
        radius: (node.stroke == nil ? 0 : node.lineWidth) * strokeScale / 2)

    }
  }

  private struct WhiskerInkRegion {
    let points: [CharacterVectorPoint]
    let closed: Bool
    let radius: Double
    let bounds: CharacterRect

    init(points: [CharacterVectorPoint], closed: Bool, radius: Double) {
      self.points = points
      self.closed = closed
      self.radius = radius
      self.bounds = CharacterSEMIDrawing.whiskerBounds(points)
    }

    func extent(at x: Double, padding: Double, lower: Bool) -> Double? {
      var values: [Double] = []
      for index in 0..<(closed ? points.count : max(0, points.count - 1)) {
        let a = points[index], b = points[(index + 1) % points.count]
        let minX = max(min(a.x, b.x), x - padding)
        let maxX = min(max(a.x, b.x), x + padding)
        guard minX <= maxX else { continue }
        if abs(b.x - a.x) < 0.000_001 { values += [a.y, b.y] }
        else {
          values += [minX, maxX].map { a.y + ($0 - a.x) / (b.x - a.x) * (b.y - a.y) }
        }
      }
      return (lower ? values.max() : values.min()).map { $0 + (lower ? radius : -radius) }
    }

    func penalty(_ p: CharacterVectorPoint, clearance: Double) -> Double {
      let margin = clearance + radius
      let box = bounds
      guard p.x >= box.minX - margin, p.x <= box.maxX + margin,
        p.y >= box.minY - margin, p.y <= box.maxY + margin else { return 0 }
      var inside = false
      var distance = Double.greatestFiniteMagnitude
      for index in 0..<(closed ? points.count : max(0, points.count - 1)) {
        let a = points[index], b = points[(index + 1) % points.count]
        let dx = b.x - a.x, dy = b.y - a.y
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy)
          / max(0.000_001, dx * dx + dy * dy)))
        distance = min(distance, hypot(p.x - a.x - t * dx, p.y - a.y - t * dy))
        if closed, (a.y > p.y) != (b.y > p.y),
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
      }
      return inside ? margin + distance : max(0, margin - distance)
    }
  }

  private static func whiskerFlatten(_ path: CharacterVectorPath) -> [CharacterVectorPoint] {
    var points: [CharacterVectorPoint] = []
    var start = CharacterVectorPoint(x: 0, y: 0)
    for command in path.commands {
      switch command {
      case .move(let p), .line(let p): points.append(p); start = p
      case .quad(let c, let end):
        for step in 1...24 {
          let t = Double(step) / 24, u = 1 - t
          points.append(.init(x: u * u * start.x + 2 * u * t * c.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * c.y + t * t * end.y))
        }
        start = end
      case .cubic(let c1, let c2, let end):
        for step in 1...24 {
          let t = Double(step) / 24, u = 1 - t
          points.append(.init(x: u * u * u * start.x + 3 * u * u * t * c1.x
            + 3 * u * t * t * c2.x + t * t * t * end.x,
            y: u * u * u * start.y + 3 * u * u * t * c1.y
            + 3 * u * t * t * c2.y + t * t * t * end.y))
        }
        start = end
      case .close: break
      }
    }
    return points
  }

  private func whiskerPaperRegion() -> WhiskerInkRegion? {
    let t = transform.concatenating(documentTransform)
    return .init(points: [
      .init(x: document.minX, y: document.minY), .init(x: document.maxX, y: document.minY),
      .init(x: document.maxX, y: document.maxY), .init(x: document.minX, y: document.maxY),
    ].map { Self.whiskerApply(t, $0) }, closed: true, radius: 0)
  }

  private static func whiskerBounds(_ points: [CharacterVectorPoint]) -> CharacterRect {
    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private static func whiskerInfluence(_ points: [CharacterVectorPoint],
    bounds: CharacterRect, release: Double) -> Double {
    let left = points.map(\.x).min() ?? 0
    let right = points.map(\.x).max() ?? 0
    let distance = max(0, bounds.minX - right, left - bounds.maxX)
    return 1 - whiskerEase(min(1, distance / release))
  }

  private static func whiskerApply(_ t: CharacterSceneTransform,
    _ p: CharacterVectorPoint) -> CharacterVectorPoint {
    .init(x: t.a * p.x + t.c * p.y + t.tx, y: t.b * p.x + t.d * p.y + t.ty)
  }

  private static func whiskerInverse(_ t: CharacterSceneTransform,
    _ p: CharacterVectorPoint) -> CharacterVectorPoint {
    let determinant = t.a * t.d - t.b * t.c
    guard abs(determinant) > 0.000_000_000_001 else { return p }
    let x = p.x - t.tx
    let y = p.y - t.ty
    return .init(x: (t.d * x - t.c * y) / determinant,
      y: (-t.b * x + t.a * y) / determinant)
  }

  private static func whiskerEase(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
  }
}

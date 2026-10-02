import Foundation

/// Shared, closed feature silhouettes. Every contour has twelve cubic segments, so a
/// capsule, closed smiling eye and heart morph without changing drawing topology.
/// Coordinates are physical face-space units; ribbon thickness never depends on aspect ratio.
struct CharacterInkContour {
  let points: [CharacterVectorPoint]

  init(_ points: [CharacterVectorPoint]) {
    precondition(points.count == 37)
    self.points = points
  }

  var path: CharacterVectorPath {
    var path = CharacterVectorPath()
    path.move(points[0].x, points[0].y)
    for i in stride(from: 1, to: points.count, by: 3) {
      path.cubic(
        points[i].x, points[i].y, points[i + 1].x, points[i + 1].y,
        points[i + 2].x, points[i + 2].y)
    }
    path.close()
    return path
  }

  func mapped(_ body: (CharacterVectorPoint) -> CharacterVectorPoint) -> Self {
    Self(points.map(body))
  }

  func blended(to other: Self, amount: Double) -> Self {
    let t = min(1, max(0, amount))
    return Self(
      zip(points, other.points).map { a, b in
        .init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
      })
  }
}

enum CharacterInkGeometry {
  private static let quarterHandle = 4.0 / 3 * tan(Double.pi / 8)

  /// Twelve segments, including degenerate straight edges for a circle. The topology does
  /// not switch at width == height, which is essential during tall-to-wide blinks.
  static func capsule(in r: CharacterRect, corner: Double = 0.5) -> CharacterInkContour {
    let radius = min(r.width, r.height) * min(0.5, max(0, corner))
    let k = radius * quarterHandle
    var p: [CharacterVectorPoint] = [.init(x: r.midX, y: r.y)]
    func line(_ x: Double, _ y: Double) {
      appendLine(x, y, to: &p)
    }
    func curve(
      _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
      _ x: Double, _ y: Double
    ) {
      p += [.init(x: x1, y: y1), .init(x: x2, y: y2), .init(x: x, y: y)]
    }
    line(r.maxX - radius, r.y)
    curve(r.maxX - radius + k, r.y, r.maxX, r.y + radius - k, r.maxX, r.y + radius)
    line(r.maxX, r.midY)
    line(r.maxX, r.maxY - radius)
    curve(
      r.maxX, r.maxY - radius + k, r.maxX - radius + k, r.maxY,
      r.maxX - radius, r.maxY)
    line(r.midX, r.maxY)
    line(r.x + radius, r.maxY)
    curve(r.x + radius - k, r.maxY, r.x, r.maxY - radius + k, r.x, r.maxY - radius)
    line(r.x, r.midY)
    line(r.x, r.y + radius)
    curve(r.x, r.y + radius - k, r.x + radius - k, r.y, r.x + radius, r.y)
    line(r.midX, r.y)
    return .init(p)
  }

  static func ellipse(in r: CharacterRect) -> CharacterInkContour {
    var points: [CharacterVectorPoint] = [.init(x: r.midX, y: r.y)]
    for index in 0..<12 {
      appendArc(
        center: .init(x: r.midX, y: r.midY), rx: r.width / 2, ry: r.height / 2,
        from: -.pi / 2 + Double(index) * .pi / 6, delta: .pi / 6, to: &points)
    }
    return .init(points)
  }

  /// A true inward > / <, not a bent smiling arc. The two straight arms have equal
  /// thickness, round end caps and a round outer join. Twelve cubics match all other ink.
  static func chevron(
    in r: CharacterRect, thickness: Double, pointsRight: Bool
  ) -> CharacterInkContour {
    let radius = min(r.width, r.height, max(0, thickness)) / 2
    let a = CharacterVectorPoint(x: r.minX + radius, y: r.minY + radius)
    let b = CharacterVectorPoint(x: r.maxX - radius, y: r.midY)
    let c = CharacterVectorPoint(x: a.x, y: r.maxY - radius)
    let dx = b.x - a.x
    let dy = b.y - a.y
    let length = hypot(dx, dy)
    let nx = dy / length
    let ny = dx / length
    let angle = atan2(ny, nx)
    let start = CharacterVectorPoint(x: a.x + nx * radius, y: a.y - ny * radius)
    var points = [start]
    func line(_ x: Double, _ y: Double) {
      appendLine(x, y, to: &points)
    }
    func arc(_ center: CharacterVectorPoint, _ from: Double, _ delta: Double) {
      appendArc(center: center, rx: radius, ry: radius, from: from, delta: delta, to: &points)
    }
    line((a.x + b.x) / 2 + nx * radius, (a.y + b.y) / 2 - ny * radius)
    line(b.x + nx * radius, b.y - ny * radius)
    arc(b, -angle, angle)
    arc(b, 0, angle)
    line(c.x + nx * radius, c.y + ny * radius)
    arc(c, angle, .pi / 2)
    arc(c, angle + .pi / 2, .pi / 2)
    let inside = CharacterVectorPoint(x: b.x - radius / nx, y: b.y)
    line(inside.x, inside.y)
    line((inside.x + a.x - nx * radius) / 2, (inside.y + a.y + ny * radius) / 2)
    line(a.x - nx * radius, a.y + ny * radius)
    arc(a, .pi - angle, .pi / 2)
    arc(a, .pi * 1.5 - angle, .pi / 2)
    points[36] = points[0]
    if !pointsRight {
      // Reflection reverses winding. Reverse control-point order as well so every
      // interpolated contour retains the same clockwise topology as the capsule.
      points = points.reversed().map { .init(x: 2 * r.midX - $0.x, y: $0.y) }
    }
    return .init(points)
  }

  /// A circular centreline swept by a disc: equal inner/outer radii difference everywhere,
  /// including both round end caps. This replaces tapered crescent polygons and open strokes.
  static func ribbon(in r: CharacterRect, thickness: Double, rise requestedRise: Double)
    -> CharacterInkContour
  {
    let thickness = min(r.width * 0.30, r.height, max(r.width * 0.025, thickness))
    let halfSpan = max(r.width * 0.001, (r.width - thickness) / 2)
    let rise = min(max(0, requestedRise), halfSpan * 0.90, max(0, r.height - thickness))
    // At zero curvature the circle radius is infinite. Use its exact straight-line limit,
    // blending over a tiny numerical interval rather than imposing a nonzero bend that
    // would flip at mouth curvature == 0.
    let minimumStableRise = r.width * 0.001
    if rise < minimumStableRise {
      let flat = flatRibbon(in: r, thickness: thickness)
      let stableBounds = CharacterRect(
        x: r.x,
        y: r.midY - (thickness + minimumStableRise) / 2,
        width: r.width, height: thickness + minimumStableRise * 1.01)
      let curved = ribbon(in: stableBounds, thickness: thickness, rise: minimumStableRise)
      return flat.blended(to: curved, amount: rise / minimumStableRise)
    }
    let radius = (halfSpan * halfSpan + rise * rise) / (2 * rise)
    let angle = 2 * atan(rise / halfSpan)
    let y = r.midY - (rise + thickness) / 2
    let center = CharacterVectorPoint(x: r.midX, y: y + thickness / 2 + radius)
    let right = CharacterVectorPoint(x: r.midX + halfSpan, y: y + thickness / 2 + rise)
    let left = CharacterVectorPoint(x: r.midX - halfSpan, y: right.y)
    let outer = radius + thickness / 2
    let inner = radius - thickness / 2
    var points: [CharacterVectorPoint] = [.init(x: r.midX, y: y)]
    func arc(
      _ center: CharacterVectorPoint, _ radius: Double, _ start: Double,
      _ delta: Double
    ) {
      appendArc(
        center: center, rx: radius, ry: radius, from: start,
        delta: delta / 2, to: &points)
      appendArc(
        center: center, rx: radius, ry: radius, from: start + delta / 2,
        delta: delta / 2, to: &points)
    }
    arc(center, outer, -.pi / 2, angle)
    arc(right, thickness / 2, -.pi / 2 + angle, .pi)
    arc(center, inner, -.pi / 2 + angle, -angle)
    arc(center, inner, -.pi / 2, -angle)
    arc(left, thickness / 2, -.pi / 2 - angle + .pi, .pi)
    arc(center, outer, -.pi / 2 - angle, angle)
    // Round-off in the final arc must not leave a seam at the top of the contour.
    points[36] = points[0]
    return .init(points)
  }

  private static func flatRibbon(in r: CharacterRect, thickness: Double) -> CharacterInkContour {
    let radius = thickness / 2
    let left = r.x + radius
    let right = r.maxX - radius
    let top = r.midY - radius
    let bottom = r.midY + radius
    var points: [CharacterVectorPoint] = [.init(x: r.midX, y: top)]
    func line(_ x: Double, _ y: Double) {
      appendLine(x, y, to: &points)
    }
    line((r.midX + right) / 2, top)
    line(right, top)
    appendArc(
      center: .init(x: right, y: r.midY), rx: radius, ry: radius,
      from: -.pi / 2, delta: .pi / 2, to: &points)
    appendArc(
      center: .init(x: right, y: r.midY), rx: radius, ry: radius,
      from: 0, delta: .pi / 2, to: &points)
    line((r.midX + right) / 2, bottom)
    line(r.midX, bottom)
    line((r.midX + left) / 2, bottom)
    line(left, bottom)
    appendArc(
      center: .init(x: left, y: r.midY), rx: radius, ry: radius,
      from: .pi / 2, delta: .pi / 2, to: &points)
    appendArc(
      center: .init(x: left, y: r.midY), rx: radius, ry: radius,
      from: .pi, delta: .pi / 2, to: &points)
    line((r.midX + left) / 2, top)
    line(r.midX, top)
    return .init(points)
  }

  static func heart(in r: CharacterRect) -> CharacterInkContour {
    // Six authored curves split in half exactly (de Casteljau), not a sampled polygon.
    let source: [(Double, Double)] = [
      (0.5, 0.23), (0.66, 0.01), (0.88, 0.00), (0.97, 0.20),
      (1.04, 0.40), (0.88, 0.59), (0.75, 0.72),
      (0.64, 0.83), (0.55, 0.94), (0.50, 0.98),
      (0.45, 0.94), (0.36, 0.83), (0.25, 0.72),
      (0.12, 0.59), (-0.04, 0.40), (0.03, 0.20),
      (0.12, 0.00), (0.34, 0.01), (0.50, 0.23),
    ]
    let original = source.map {
      CharacterVectorPoint(
        x: r.x + $0.0 * r.width,
        y: r.y + $0.1 * r.height)
    }
    func mid(_ a: CharacterVectorPoint, _ b: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    var points = [original[0]]
    for i in stride(from: 1, to: original.count, by: 3) {
      let a = original[i - 1]
      let b = original[i]
      let c = original[i + 1]
      let d = original[i + 2]
      let ab = mid(a, b)
      let bc = mid(b, c)
      let cd = mid(c, d)
      let abc = mid(ab, bc)
      let bcd = mid(bc, cd)
      let m = mid(abc, bcd)
      points += [ab, abc, m, bcd, cd, d]
    }
    return .init(points)
  }

  private static func appendLine(
    _ x: Double, _ y: Double, to points: inout [CharacterVectorPoint]
  ) {
    // Every shape seeds its starting point before appending a straight cubic.
    let start = points.last!
    points += [
      .init(x: start.x + (x - start.x) / 3, y: start.y + (y - start.y) / 3),
      .init(x: start.x + (x - start.x) * 2 / 3, y: start.y + (y - start.y) * 2 / 3),
      .init(x: x, y: y),
    ]
  }

  private static func appendArc(
    center: CharacterVectorPoint, rx: Double, ry: Double,
    from start: Double, delta: Double, to points: inout [CharacterVectorPoint]
  ) {
    let end = start + delta
    let k = 4.0 / 3 * tan(delta / 4)
    points += [
      .init(
        x: center.x + rx * (cos(start) - k * sin(start)),
        y: center.y + ry * (sin(start) + k * cos(start))),
      .init(
        x: center.x + rx * (cos(end) + k * sin(end)),
        y: center.y + ry * (sin(end) - k * cos(end))),
      .init(x: center.x + rx * cos(end), y: center.y + ry * sin(end)),
    ]
  }
}

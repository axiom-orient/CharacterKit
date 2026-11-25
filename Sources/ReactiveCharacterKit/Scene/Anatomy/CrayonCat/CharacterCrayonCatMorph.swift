import Foundation

enum CharacterCrayonCatMorph {
  private typealias Point = CharacterVectorPoint
  private typealias Path = CharacterVectorPath
  private typealias Node = CharacterSceneNode
  private static let nearForeleg = "full-body-cat.leg.near-front"
  private static let limbAliases: [String: String] = {
    let aliases = [
      "paw.wave": "leg.near-front", "near-fore": "leg.near-front",
      "far-fore": "leg.far-front", "fore": "leg.far-front",
      "near-hind": "leg.near-hind", "hind": "leg.near-hind", "far-hind": "leg.far-hind",
      "left-hind": "leg.near-hind", "right-hind": "leg.far-hind",
      "left-fore": "leg.near-front", "right-fore": "leg.far-front",
    ]
    // Filled shapes, their outlines, and their wax marks share a limb identity.
    return Dictionary(uniqueKeysWithValues: ["full-body-cat.", "full-body-cat.outline.", "full-body-cat.wax."]
      .flatMap { prefix in aliases.map { (prefix + $0.key, prefix + $0.value) } })
  }()

  static func blend(
    _ source: [CharacterSceneNode], _ destination: [CharacterSceneNode], progress: Double
  ) -> [CharacterSceneNode] {
    guard !source.isEmpty else { return destination }
    let target = Dictionary(uniqueKeysWithValues: destination.map { (anatomicalID($0.id), $0) })
    let previous = Set(source.map { anatomicalID($0.id) })
    let forelegHandoff = pawHandoff(from: source, to: target[nearForeleg], progress: progress)
    // Put newly visible legs behind the torso while preserving the outgoing painter order.
    let additions = destination.filter { !previous.contains(anatomicalID($0.id)) }.map {
      node($0, opacity: $0.opacity * visibility($0, weight: progress))
    }
    var torsoClip: Path?
    var headClip: Path?
    let joined = additions + source.map { first -> Node in
      let key = anatomicalID(first.id)
      guard let last = target[key] else {
        return node(first, opacity: first.opacity * visibility(first, weight: 1 - progress))
      }
      let paw = forelegHandoff.flatMap { key.hasSuffix(".leg.near-front") ? $0 : nil }
      let fromTransform = paw?.source.concatenating(first.transform) ?? first.transform
      let toTransform = paw?.destination.concatenating(last.transform) ?? last.transform
      let alignLayer = first.id.hasSuffix(".body") || first.transform.a * last.transform.a < 0
      func blendPath(_ a: Path, _ b: Path) -> Path {
        let contour = alignLayer || a.commands.contains { if case .line = $0 { true } else { false } }
        let path = mix(transformed(a, by: fromTransform),
          transformed(b, by: toTransform), progress, alignContour: contour)
        return paw.map { transformed(path, by: $0.stage) } ?? path
      }
      let id = last.id.hasSuffix(".paw.wave") ? last.id : first.id
      let path = blendPath(first.path, last.path)
      // Paint and crayon strokes follow the exact interpolated surface underneath them.
      let sharedClip: Path?
      switch key {
      case "full-body-cat.body":
        torsoClip = path
        sharedClip = nil
      case "full-body-cat.head":
        headClip = path
        sharedClip = nil
      case "full-body-cat.wax.body":
        sharedClip = torsoClip
      case "full-body-cat.wax.head":
        sharedClip = headClip
      default:
        sharedClip = nil
      }
      return .init(id: id, layer: first.layer, path: path,
        fill: paint(first.fill, last.fill, progress),
        stroke: color(first.stroke, last.stroke, progress),
        lineWidth: scalar(first.lineWidth, last.lineWidth, progress),
        opacity: scalar(first.opacity, last.opacity, progress), transform: .identity,
        clips: sharedClip.map { [$0] } ?? zip(first.clips, last.clips).map { blendPath($0.0, $0.1) })
    }
    // The torso covers the lifted leg's root and the cheek covers any crossing at the tip.
    let raised = joined.filter { $0.layer == .surface && $0.id.hasSuffix(".paw.wave") }
    guard !raised.isEmpty else { return joined }
    var paintOrder = joined.filter { $0.layer != .surface || !$0.id.hasSuffix(".paw.wave") }
    if let torso = paintOrder.firstIndex(where: { $0.id == "full-body-cat.body" }) {
      paintOrder.insert(contentsOf: raised, at: torso)
    }
    return paintOrder
  }

  private static func pawHandoff(
    from source: [Node], to last: Node?, progress: Double
  ) -> (source: CharacterSceneTransform, destination: CharacterSceneTransform, stage: CharacterSceneTransform)? {
    guard let first = source.first(where: { anatomicalID($0.id) == nearForeleg }),
      let last, first.id.hasSuffix(".paw.wave") || last.id.hasSuffix(".paw.wave"),
      let a = LimbAxis(first), let b = LimbAxis(last)
    else { return nil }
    // Rotate the foreleg as it rises so opposing contour points keep their width.
    let difference = b.angle - a.angle
    let angle = a.angle + atan2(sin(difference), cos(difference)) * progress
    let root = point(a.root, b.root, progress)
    let stage = CharacterSceneTransform.around(x: 0, y: 0, angle: angle, offsetX: root.x, offsetY: root.y)
    return (a.local, b.local, stage)
  }

  private struct LimbAxis {
    let root: Point
    let angle: Double

    init?(_ node: Node) {
      let commands = node.path.commands
      // A tube traces the two sides of the root and of the rounded pad in paired commands.
      guard commands.count == 6,
        case .move(let rootSide) = commands[0],
        case .cubic(_, _, let padSide) = commands[1],
        case .cubic(_, _, let otherPadSide) = commands[2],
        case .cubic(_, _, let otherRootSide) = commands[3]
      else { return nil }
      root = apply(node.transform, to: point(rootSide, otherRootSide, 0.5))
      let pad = apply(node.transform, to: point(padSide, otherPadSide, 0.5))
      angle = atan2(pad.y - root.y, pad.x - root.x)
    }

    var local: CharacterSceneTransform {
      .around(x: root.x, y: root.y, angle: -angle, offsetX: -root.x, offsetY: -root.y)
    }
  }

  private static func anatomicalID(_ id: String) -> String {
    limbAliases[id] ?? id
  }

  static func placed(_ source: CharacterSceneNode, by placement: CharacterSceneTransform) -> CharacterSceneNode {
    return .init(id: source.id, layer: source.layer, path: source.path,
      fill: source.fill, stroke: source.stroke, lineWidth: source.lineWidth,
      opacity: source.opacity, transform: placement.concatenating(source.transform), clips: source.clips)
  }

  private static func visibility(_ node: Node, weight: Double) -> Double {
    guard node.layer == .features else { return weight }
    // A newly visible feature waits for the head to turn underneath it.
    let visible = min(1, max(0, (weight - 0.48) / 0.52))
    return visible * visible * (3 - 2 * visible)
  }

  private static func node(_ node: Node, opacity: Double) -> Node {
    .init(id: node.id, layer: node.layer, path: node.path, fill: node.fill, stroke: node.stroke,
      lineWidth: node.lineWidth, opacity: opacity, transform: node.transform, clips: node.clips)
  }

  private static func mix(_ from: Path, _ to: Path, _ t: Double, alignContour: Bool = false) -> Path {
    if from == to { return from }
    let closed = from.commands.last == .close && to.commands.last == .close
    if !closed || (!alignContour && winding(from) * winding(to) >= 0) {
      if from.commands.count == to.commands.count {
        let commands = zip(from.commands, to.commands).compactMap { pair -> CharacterVectorCommand? in
          switch pair {
          case (.move(let a), .move(let b)): .move(point(a, b, t))
          case (.line(let a), .line(let b)): .line(point(a, b, t))
          case (.quad(let a, let e), .quad(let b, let f)):
            .quad(control: point(a, b, t), end: point(e, f, t))
          case (.cubic(let a, let b, let e), .cubic(let c, let d, let f)):
            .cubic(control1: point(a, c, t), control2: point(b, d, t), end: point(e, f, t))
          case (.close, .close): .close
          default: nil
          }
        }
        if commands.count == from.commands.count {
          var path = Path()
          path.commands = commands
          return path
        }
      }
    }
    guard closed, let a = contour(from), var b = contour(to) else { return t < 0.5 ? from : to }
    if signedArea(a) * signedArea(b) < 0 { b.reverse() }
    let offset = alignedOffset(from: centered(a), to: centered(b))
    var path = Path()
    path.commands.reserveCapacity(a.count + 1)
    for i in a.indices {
      let p = point(a[i], b[(i + offset) % b.count], t)
      if i == 0 { path.move(p.x, p.y) } else { path.line(p.x, p.y) }
    }
    path.close()
    return path
  }

  private static func alignedOffset(from first: [Point], to second: [Point]) -> Int {
    // Each cyclic offset is a contiguous window in the doubled contour.
    let repeated = second + second
    var best = 0
    var lowestCost = Double.infinity
    for offset in second.indices {
      var cost = 0.0
      for i in first.indices {
        let p = first[i]
        let q = repeated[i + offset]
        let dx = p.x - q.x
        let dy = p.y - q.y
        cost = cost + dx * dx + dy * dy
      }
      if cost < lowestCost {
        lowestCost = cost
        best = offset
      }
    }
    return best
  }

  /// Pair closed silhouettes by distance along their edge when the original curves differ.
  private static func contour(_ path: Path) -> [Point]? {
    guard case .move(let first) = path.commands.first else { return nil }
    var vertices = [first]
    for command in path.commands.dropFirst() {
      guard let start = vertices.last else { return nil }
      switch command {
      case .line(let end): vertices.append(end)
      case .quad(let control, let end):
        for index in 1...6 {
          let t = Double(index) / 6
          vertices.append(point(point(start, control, t), point(control, end, t), t))
        }
      case .cubic(let firstControl, let secondControl, let end):
        for index in 1...6 {
          let t = Double(index) / 6
          let a = point(start, firstControl, t)
          let b = point(firstControl, secondControl, t)
          let c = point(secondControl, end, t)
          vertices.append(point(point(a, b, t), point(b, c, t), t))
        }
      case .close: vertices.append(first)
      case .move: return nil
      }
    }
    var distances = [0.0]
    for (a, b) in zip(vertices, vertices.dropFirst()) {
      distances.append(distances[distances.count - 1] + ((a.x - b.x) * (a.x - b.x)
        + (a.y - b.y) * (a.y - b.y)).squareRoot())
    }
    guard let length = distances.last, length > 0 else { return nil }
    var segment = 0
    let count = 40
    return (0..<count).map { index in
      let distance = length * Double(index) / Double(count)
      while distances[segment + 1] <= distance { segment += 1 }
      let fraction = (distance - distances[segment]) / (distances[segment + 1] - distances[segment])
      return point(vertices[segment], vertices[segment + 1], fraction)
    }
  }

  private static func winding(_ path: Path) -> Double {
    let ends = path.commands.compactMap { command -> Point? in
      switch command {
      case .move(let p), .line(let p), .quad(_, let p), .cubic(_, _, let p): p
      case .close: nil
      }
    }
    return signedArea(ends)
  }

  private static func signedArea(_ points: [Point]) -> Double {
    points.indices.reduce(0) {
      let a = points[$1]
      let b = points[($1 + 1) % points.count]
      return $0 + a.x * b.y - a.y * b.x
    }
  }

  private static func centered(_ points: [Point]) -> [Point] {
    let count = Double(points.count)
    let x = points.reduce(0) { $0 + $1.x } / count
    let y = points.reduce(0) { $0 + $1.y } / count
    return points.map { .init(x: $0.x - x, y: $0.y - y) }
  }

  private static func apply(_ transform: CharacterSceneTransform, to p: Point) -> Point {
    .init(x: transform.a * p.x + transform.c * p.y + transform.tx,
      y: transform.b * p.x + transform.d * p.y + transform.ty)
  }

  private static func transformed(_ path: Path, by transform: CharacterSceneTransform) -> Path {
    transform == .identity ? path : path.mapped { apply(transform, to: $0) }
  }

  private static func paint(_ a: CharacterScenePaint?, _ b: CharacterScenePaint?, _ t: Double) -> CharacterScenePaint? {
    guard case .solid(let a) = a, case .solid(let b) = b,
      let mixed = color(a, b, t) else { return t < 0.5 ? a : b }
    return .solid(mixed)
  }

  private static func color(_ a: CharacterColor?, _ b: CharacterColor?, _ t: Double) -> CharacterColor? {
    guard let a, let b else { return t < 0.5 ? a : b }
    return .init(uncheckedRed: scalar(a.red, b.red, t), green: scalar(a.green, b.green, t),
      blue: scalar(a.blue, b.blue, t))
  }

  private static func point(_ a: Point, _ b: Point, _ t: Double) -> Point {
    .init(x: scalar(a.x, b.x, t), y: scalar(a.y, b.y, t))
  }

  private static func scalar(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

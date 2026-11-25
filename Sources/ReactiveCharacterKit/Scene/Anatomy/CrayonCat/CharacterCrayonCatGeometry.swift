import Foundation

/// Hand-drawn pose silhouettes on the shared 256-point stage.
enum CharacterCrayonCatGeometry {
  private typealias Artwork = CharacterCrayonCatArtwork
  private typealias Part = Artwork.Part
  private typealias Tone = Artwork.Tone
  private typealias Point = CharacterVectorPoint
  private typealias Path = CharacterVectorPath
  private typealias Rect = CharacterRect

  static func resolve(_ pose: CharacterFullBodyCatPose) -> CharacterCrayonCatArtwork {
    switch pose {
    case .standing: standing
    case .waving: waving
    case .loaf: loaf
    case .left: left
    case .right: right
    case .rear: rear
    case .upright: upright
    case .puffed: puffed
    case .bellyUp: bellyUp
    case .stretch: stretch
    }
  }

  private static let standing: Artwork = {
    let skull = Rect(x: 38, y: 52, width: 126, height: 124)
    let tailRoot = point(181, 164)
    return .init(
      face: frontFace(skull, offset: -8),
      parts: [
        tail(tailRoot, point(235, 167), point(237, 105), point(212, 107), width: 20),
        leg(.farHind, root: point(165, 174), ankle: point(162, 197), foot: point(163, 206), width: 16),
        leg(.farFront, root: point(126, 174), ankle: point(125, 197), foot: point(122, 207), width: 16),
        leg(.nearHind, root: point(180, 162), ankle: point(186, 194), foot: point(188, 212), width: 22),
        leg(.nearFront, root: point(113, 157), ankle: point(106, 193), foot: point(103, 212), width: 22),
        .init("body", outline { path in
          path.move(107, 144)
          path.cubic(122, 140, 136, 143, 155, 132)
          path.cubic(174, 122, 196, 134, 201, 155)
          path.cubic(210, 179, 194, 200, 175, 201)
          path.cubic(156, 200, 148, 193, 133, 192)
          path.cubic(111, 196, 99, 193, 96, 172)
          path.cubic(93, 159, 99, 150, 107, 144)
        }, .torso),
        head(skull),
      ],
      tailPivot: tailRoot, headPivot: point(118, 153))
  }()

  private static let waving: Artwork = {
    let skull = Rect(x: 67, y: 45, width: 121, height: 121)
    let tailRoot = point(167, 180)
    let shoulder = point(112, 164)
    let elbow = point(88, 174)
    let raisedPaw = point(68, 147)
    return .init(
      face: frontFace(skull, offset: -3),
      parts: [
        tail(tailRoot, point(208, 189), point(231, 166), point(213, 161), width: 18),
        restingLimb("far-hind", root: point(146, 185), ankle: point(146, 200),
                    foot: point(145, 207), width: 16, tone: .far),
        restingLimb("hind", root: point(163, 176), ankle: point(168, 198), foot: point(173, 212), width: 23),
        restingLimb("fore", root: point(122, 168), ankle: point(116, 194), foot: point(113, 212), width: 23),
        .init("paw.wave", tube(shoulder, point(92, 178), point(69, 173), raisedPaw, 24, 27),
              .near, motion: .paw, outlined: false, pivot: elbow, foot: raisedPaw),
        .init("body", outline { path in
          path.move(115, 137)
          path.cubic(102, 148, 99, 160, 103, 180)
          path.cubic(105, 199, 119, 205, 140, 205)
          path.cubic(163, 207, 183, 196, 182, 176)
          path.cubic(180, 162, 161, 150, 151, 144)
          path.cubic(136, 136, 124, 133, 115, 137)
        }, .torso),
        head(skull),
      ],
      tailPivot: tailRoot, pawPivot: shoulder, headPivot: point(127, 145))
  }()

  private static let loaf: Artwork = {
    let skull = Rect(x: 41, y: 105, width: 124, height: 114)
    return .init(
      face: frontFace(skull, offset: -3),
      parts: [
        // The legs stay tucked under the coat until a new pose moves them out.
        restingLimb("far-hind", root: point(165, 186), ankle: point(162, 198),
                    foot: point(161, 207), width: 16, tone: .far),
        restingLimb("far-fore", root: point(129, 184), ankle: point(125, 197),
                    foot: point(123, 209), width: 16, tone: .far),
        restingLimb("near-hind", root: point(179, 182), ankle: point(176, 197),
                    foot: point(174, 208), width: 18),
        restingLimb("near-fore", root: point(113, 194), ankle: point(110, 203),
                    foot: point(107, 209), width: 17),
        .init("body", outline { path in
          path.move(106, 162)
          path.cubic(130, 155, 146, 146, 170, 148)
          path.cubic(194, 149, 209, 169, 209, 191)
          path.cubic(211, 211, 198, 221, 174, 220)
          path.line(113, 222)
          path.cubic(88, 221, 86, 176, 106, 162)
        }, .torso),
        .init("tail", outline { path in
          path.move(196, 177)
          path.cubic(209, 181, 218, 193, 217, 205)
          path.cubic(215, 219, 198, 224, 181, 223)
          path.cubic(167, 223, 151, 218, 153, 209)
          path.cubic(155, 201, 167, 201, 178, 203)
          path.cubic(192, 206, 202, 196, 196, 177)
        }, .tail, outlined: false),
        head(skull),
      ],
      headPivot: point(106, 190))
  }()

  private static let left = profile(mirrored: false)
  private static let right = profile(mirrored: true)

  private static func profile(mirrored: Bool) -> Artwork {
    let skull = Rect(x: 32, y: 58, width: 113, height: 120)
    let tailRoot = point(179, 164)
    let cheek = point(107, 155)
    let eye = Artwork.Eye(mirrored ? 181 : 75, 130, 14, 16)
    let bounds = mirrored ? Rect(x: 111, y: 58, width: 113, height: 120) : skull
    let muzzle = Artwork.Muzzle(
      mirrored ? 206 : 50, 146, 9, 6, mouthX: mirrored ? 203 : 53, mouthY: 154,
      profileDirection: mirrored ? 1 : -1)
    let face = Artwork.Face(bounds, left: mirrored ? eye : nil, right: mirrored ? nil : eye, muzzle: muzzle)
    let parts: [Part] = [
      tail(tailRoot, point(234, 169), point(238, 106), point(213, 109), width: 20),
      leg(.farHind, root: point(163, 174), ankle: point(164, 194), foot: point(163, 205), width: 16),
      leg(.farFront, root: point(119, 170), ankle: point(119, 194), foot: point(116, 207), width: 16),
      leg(.nearHind, root: point(177, 160), ankle: point(183, 192), foot: point(186, 212), width: 22),
      leg(.nearFront, root: point(109, 158), ankle: point(101, 193), foot: point(98, 212), width: 22),
      .init("body", outline { path in
        path.move(104, 147)
        path.cubic(121, 141, 136, 144, 155, 133)
        path.cubic(177, 120, 199, 135, 202, 157)
        path.cubic(208, 177, 196, 198, 176, 199)
        path.cubic(155, 201, 148, 189, 133, 191)
        path.cubic(117, 195, 100, 191, 94, 176)
        path.cubic(91, 163, 96, 153, 104, 147)
      }, .torso),
      head(skull, profile: true),
    ]
    return .init(
      face: face, parts: mirrored ? parts.map(mirror) : parts,
      tailPivot: mirrored ? mirror(tailRoot) : tailRoot,
      headPivot: mirrored ? mirror(cheek) : cheek)
  }

  private static let rear: Artwork = {
    let skull = Rect(x: 65, y: 49, width: 124, height: 118)
    let tailRoot = point(128, 184)
    return .init(
      face: nil,
      parts: [
        head(skull),
        restingLimb("left-hind", root: point(107, 180), ankle: point(105, 201),
                    foot: point(101, 212), width: 23),
        restingLimb("right-hind", root: point(149, 180), ankle: point(151, 200),
                    foot: point(154, 212), width: 23),
        restingLimb("near-fore", root: point(110, 174), ankle: point(110, 189),
                    foot: point(109, 201), width: 16),
        restingLimb("far-fore", root: point(146, 174), ankle: point(147, 187),
                    foot: point(146, 199), width: 15, tone: .far),
        .init("body", outline { path in
          path.move(128, 137)
          path.cubic(151, 139, 169, 155, 169, 176)
          path.cubic(171, 199, 155, 213, 128, 213)
          path.cubic(102, 214, 85, 201, 87, 178)
          path.cubic(88, 158, 105, 139, 128, 137)
        }, .torso),
        .init("tail", tube(tailRoot, point(112, 163), point(159, 112), point(158, 96), 21, 15),
              .tail, motion: .tail, outlined: false),
      ],
      tailPivot: tailRoot, headPivot: point(128, 149))
  }()

  private static let upright: Artwork = {
    let skull = Rect(x: 63, y: 42, width: 127, height: 120)
    let tailRoot = point(154, 184)
    return .init(
      face: frontFace(skull),
      parts: [
        tail(tailRoot, point(207, 189), point(224, 138), point(200, 142), width: 18),
        restingLimb("left-hind", root: point(112, 176), ankle: point(107, 199),
                    foot: point(105, 212), width: 21),
        restingLimb("right-hind", root: point(146, 176), ankle: point(149, 199),
                    foot: point(151, 212), width: 21),
        .init("body", outline { path in
          path.move(126, 134)
          path.cubic(146, 134, 159, 155, 165, 176)
          path.cubic(172, 197, 154, 206, 127, 207)
          path.cubic(99, 207, 84, 194, 91, 174)
          path.cubic(96, 155, 108, 135, 126, 134)
        }, .torso),
        restingLimb("left-fore", root: point(103, 153), ankle: point(100, 172),
                    foot: point(115, 177), width: 19),
        restingLimb("right-fore", root: point(148, 152), ankle: point(151, 174),
                    foot: point(136, 178), width: 19),
        head(skull),
      ],
      tailPivot: tailRoot, headPivot: point(127, 146))
  }()

  private static let puffed: Artwork = {
    let skull = Rect(x: 26, y: 88, width: 112, height: 110)
    let tailRoot = point(185, 157)
    return .init(
      face: .init(
        skull, right: .init(67, 149, 16, 20),
        muzzle: .init(47, 166, 9, 6, mouthX: 50, mouthY: 173, profileDirection: -1)),
      parts: [
        .init("tail", outline { path in
          path.move(177, 151)
          path.cubic(194, 147, 209, 133, 209, 117)
          path.cubic(208, 106, 202, 96, 203, 84)
          path.cubic(205, 72, 212, 64, 220, 67)
          path.cubic(232, 71, 237, 92, 235, 106)
          path.cubic(233, 136, 216, 156, 185, 170)
          path.quad(177, 173, 177, 151)
        }, .tail, motion: .tail, raisedFur: true),
        restingLimb(
          "far-hind", root: point(162, 172), ankle: point(176, 196), foot: point(181, 207),
          width: 18, tone: .far),
        restingLimb(
          "far-fore", root: point(110, 170), ankle: point(111, 197), foot: point(101, 208),
          width: 18, tone: .far),
        restingLimb("near-hind", root: point(178, 162), ankle: point(190, 195),
                    foot: point(191, 212), width: 22),
        restingLimb("near-fore", root: point(109, 162), ankle: point(99, 195),
                    foot: point(93, 212), width: 22),
        .init("body", outline { path in
          path.move(98, 168)
          path.cubic(104, 143, 112, 124, 131, 116)
          path.cubic(138, 112, 137, 103, 145, 99)
          path.cubic(152, 95, 154, 101, 160, 98)
          path.cubic(166, 96, 168, 91, 176, 93)
          path.cubic(185, 95, 185, 101, 190, 104)
          path.cubic(203, 108, 202, 115, 199, 124)
          path.cubic(209, 137, 208, 159, 199, 177)
          path.cubic(197, 192, 185, 201, 173, 195)
          path.cubic(158, 184, 152, 168, 139, 172)
          path.cubic(119, 176, 121, 197, 105, 195)
          path.cubic(94, 193, 93, 180, 98, 168)
        }, .torso, raisedFur: true),
        head(skull, profile: true),
      ],
      tailPivot: tailRoot, headPivot: point(91, 170))
  }()

  private static let bellyUp: Artwork = {
    let skull = Rect(x: 32, y: 117, width: 112, height: 105)
    let pivot = point(skull.midX, skull.midY)
    let rotatedBounds = Rect(x: skull.midX - skull.height / 2, y: skull.midY - skull.width / 2,
                             width: skull.height, height: skull.width)
    let tailRoot = point(182, 197)
    return .init(
      face: .init(
        rotatedBounds, left: .init(98, 187, 14, 15), right: .init(98, 151, 14, 16),
        muzzle: .init(110, 170, 9, 6, mouthX: 117, mouthY: 170), eyeAngle: -.pi / 2),
      parts: [
        tail(tailRoot, point(215, 217), point(240, 193), point(220, 183), width: 19),
        restingLimb(
          "far-hind", root: point(171, 177), ankle: point(172, 155), foot: point(173, 139),
          width: 19, tone: .far),
        restingLimb(
          "far-fore", root: point(127, 176), ankle: point(124, 155), foot: point(124, 140),
          width: 18, tone: .far),
        .init("body", outline { path in
          path.move(113, 165)
          path.cubic(130, 155, 147, 149, 175, 152)
          path.cubic(199, 153, 211, 172, 208, 192)
          path.cubic(207, 212, 186, 221, 161, 220)
          path.cubic(137, 220, 118, 216, 105, 202)
          path.cubic(96, 191, 99, 175, 113, 165)
        }, .torso),
        restingLimb("near-hind", root: point(178, 184), ankle: point(193, 171),
                    foot: point(199, 157), width: 22),
        restingLimb("near-fore", root: point(131, 185), ankle: point(143, 175),
                    foot: point(143, 163), width: 21),
        head(skull) { p in
          point(pivot.x + p.y - pivot.y, pivot.y - (p.x - pivot.x))
        },
      ],
      tailPivot: tailRoot, headPivot: pivot)
  }()

  private static let stretch: Artwork = {
    let skull = Rect(x: 25, y: 96, width: 114, height: 111)
    let tailRoot = point(175, 151)
    return .init(
      face: frontFace(skull, offset: -4),
      parts: [
        tail(tailRoot, point(229, 144), point(233, 89), point(211, 96), width: 18),
        restingLimb(
          "far-hind", root: point(173, 170), ankle: point(189, 187), foot: point(208, 195),
          width: 19, tone: .far),
        restingLimb(
          "far-fore", root: point(105, 182), ankle: point(73, 199), foot: point(54, 205),
          width: 19, tone: .far),
        restingLimb("near-hind", root: point(175, 170), ankle: point(201, 189),
                    foot: point(218, 207), width: 22),
        restingLimb("near-fore", root: point(98, 177), ankle: point(63, 204),
                    foot: point(43, 213), width: 22),
        .init("body", outline { path in
          path.move(95, 174)
          path.cubic(117, 167, 131, 142, 154, 137)
          path.cubic(175, 130, 196, 139, 201, 156)
          path.cubic(209, 175, 193, 192, 169, 194)
          path.cubic(140, 195, 126, 208, 102, 208)
          path.cubic(82, 208, 80, 184, 95, 174)
        }, .torso),
        head(skull),
      ],
      tailPivot: tailRoot, headPivot: point(96, 172))
  }()

  private static func frontFace(_ bounds: Rect, offset: Double = 0) -> Artwork.Face {
    let x = bounds.midX + offset
    let eyeY = bounds.y + bounds.height * 0.578
    return .init(
      bounds, left: .init(x - 22, eyeY - 1.5, 14.6, 16), right: .init(x + 18, eyeY + 1, 13.5, 15),
      muzzle: .init(x - 1, eyeY + 13.5, 9.5, 6, mouthX: x, mouthY: eyeY + 20))
  }

  private static func head(
    _ bounds: Rect, profile: Bool = false, project: (Point) -> Point = { $0 }
  ) -> Part {
    .init("head", catHead(bounds, profile: profile).mapped(project), .head, motion: .head)
  }

  private static func catHead(_ bounds: Rect, profile: Bool = false) -> Path {
    let shape = outline { path in
      path.move(0.133, 0.353)
      path.cubic(0.111, 0.275, 0.049, 0.207, 0.080, 0.162)
      path.cubic(0.116, 0.113, 0.222, 0.151, 0.317, 0.201)
      path.cubic(0.411, 0.148, 0.548, 0.139, 0.648, 0.174)
      path.cubic(0.721, 0.104, 0.797, 0.012, 0.846, 0.049)
      path.cubic(0.894, 0.082, 0.892, 0.215, 0.877, 0.317)
      path.cubic(0.961, 0.408, 1.025, 0.495, 0.980, 0.663)
      path.cubic(0.946, 0.851, 0.824, 0.974, 0.608, 0.981)
      path.cubic(0.388, 1.002, 0.144, 0.981, 0.058, 0.803)
      path.cubic(-0.031, 0.640, 0.011, 0.472, 0.133, 0.353)
    }
    return shape.mapped { p in
      // Push the lower cheek forward in profile while keeping the ear roots broad.
      let muzzle = profile ? max(0, 1 - abs(p.y - 0.72) / 0.29) * max(0, 0.36 - p.x) * 0.18 : 0
      return point(bounds.minX + (p.x - muzzle) * bounds.width,
                   bounds.minY + p.y * bounds.height)
    }
  }

  private static func tail(_ root: Point, _ control1: Point, _ control2: Point, _ tip: Point,
                           width: Double) -> Part {
    // Follow the local tangent through the curl so the two sides never pinch together.
    let samples = (0...10).map { index -> (left: Point, right: Point) in
      let t = Double(index) / 10
      let u = 1 - t
      let a = u * u * u
      let b = 3 * u * u * t
      let c = 3 * u * t * t
      let d = t * t * t
      let center = point(a * root.x + b * control1.x + c * control2.x + d * tip.x,
                         a * root.y + b * control1.y + c * control2.y + d * tip.y)
      let dx = u * u * (control1.x - root.x) + 2 * u * t * (control2.x - control1.x) + t * t * (tip.x - control2.x)
      let dy = u * u * (control1.y - root.y) + 2 * u * t * (control2.y - control1.y) + t * t * (tip.y - control2.y)
      let tangent = unit(from: .init(x: 0, y: 0), to: point(dx, dy))
      let normal = point(-tangent.y, tangent.x)
      let radius = width / 2 * (1 - 0.26 * t)
      return (shift(center, by: normal, radius), shift(center, by: normal, -radius))
    }
    let contour = outline { path in
      func trace(_ edge: [Point], on path: inout Path) {
        for i in 1..<(edge.count - 1) {
          let a = edge[i]
          let b = edge[i + 1]
          path.quad(a.x, a.y, (a.x + b.x) / 2, (a.y + b.y) / 2)
        }
        if let end = edge.last { path.quad(end.x, end.y, end.x, end.y) }
      }
      let left = samples.map(\.left)
      let right = Array(samples.map(\.right).reversed())
      path.move(left[0].x, left[0].y)
      trace(left, on: &path)
      let tipTangent = unit(from: control2, to: tip)
      let capLeft = shift(left[left.count - 1], by: tipTangent, 0.49 * width)
      let capRight = shift(right[0], by: tipTangent, 0.49 * width)
      path.cubic(capLeft.x, capLeft.y, capRight.x, capRight.y, right[0].x, right[0].y)
      trace(right, on: &path)
    }
    return .init("tail", contour, .tail, motion: .tail)
  }

  private static func leg(_ identity: CharacterFullBodyCatLeg, root: Point, ankle: Point, foot: Point,
                          width: Double) -> Part {
    let part: (id: String, tone: Tone) =
      switch identity {
      case .nearFront: ("leg.near-front", .near)
      case .nearHind: ("leg.near-hind", .near)
      case .farFront: ("leg.far-front", .far)
      case .farHind: ("leg.far-hind", .far)
      }
    return .init(
      part.id, limb(root, ankle, foot, width), part.tone, motion: .leg(identity),
      outlined: false, pivot: root, foot: foot)
  }

  private static func restingLimb(_ id: String, root: Point, ankle: Point, foot: Point,
                                  width: Double, tone: Tone = .near) -> Part {
    .init(id, limb(root, ankle, foot, width), tone, outlined: false, pivot: root, foot: foot)
  }

  private static func limb(_ root: Point, _ ankle: Point, _ foot: Point, _ width: Double) -> Path {
    let control = point((root.x + ankle.x) / 2, (root.y + ankle.y) / 2)
    return tube(root, control, ankle, foot, width * 1.13, width)
  }

  /// A tapered filled curve with a rounded end, portable across both renderers.
  private static func tube(_ root: Point, _ c1: Point, _ c2: Point, _ tip: Point,
                           _ rootWidth: Double, _ tipWidth: Double) -> Path {
    let start = unit(from: root, to: c1)
    let end = unit(from: c2, to: tip)
    let a = point(-start.y, start.x)
    let b = point(-end.y, end.x)
    let h0 = rootWidth / 2
    let h1 = tipWidth / 2
    let startPlus = shift(root, by: a, h0)
    let startMinus = shift(root, by: a, -h0)
    let rootCapPlus = shift(startPlus, by: start, -h0 * 0.60)
    let rootCapMinus = shift(startMinus, by: start, -h0 * 0.60)
    let endPlus = shift(tip, by: b, h1)
    let endMinus = shift(tip, by: b, -h1)
    let capPlus = shift(endPlus, by: end, h1 * 1.33)
    let capMinus = shift(endMinus, by: end, h1 * 1.33)
    let c1Plus = shift(c1, by: a, h0)
    let c1Minus = shift(c1, by: a, -h0)
    let c2Plus = shift(c2, by: b, h1)
    let c2Minus = shift(c2, by: b, -h1)
    return outline { path in
      path.move(startPlus.x, startPlus.y)
      path.cubic(c1Plus.x, c1Plus.y, c2Plus.x, c2Plus.y, endPlus.x, endPlus.y)
      path.cubic(capPlus.x, capPlus.y, capMinus.x, capMinus.y, endMinus.x, endMinus.y)
      path.cubic(c2Minus.x, c2Minus.y, c1Minus.x, c1Minus.y, startMinus.x, startMinus.y)
      path.cubic(rootCapMinus.x, rootCapMinus.y, rootCapPlus.x, rootCapPlus.y, startPlus.x, startPlus.y)
    }
  }

  private static func outline(_ draw: (inout Path) -> Void) -> Path {
    var path = Path()
    draw(&path)
    path.close()
    return path
  }

  private static func point(_ x: Double, _ y: Double) -> Point { .init(x: x, y: y) }
  private static func mirror(_ p: Point) -> Point { point(256 - p.x, p.y) }

  private static func mirror(_ part: Part) -> Part {
    .init(part.id, part.path.mapped(mirror), part.tone, motion: part.motion, outlined: part.outlined,
          pivot: part.pivot.map(mirror), foot: part.foot.map(mirror))
  }

  private static func unit(from a: Point, to b: Point) -> Point {
    let length = hypot(b.x - a.x, b.y - a.y)
    return point((b.x - a.x) / length, (b.y - a.y) / length)
  }

  private static func shift(_ p: Point, by unit: Point, _ distance: Double) -> Point {
    point(p.x + unit.x * distance, p.y + unit.y * distance)
  }
}

enum CharacterFullBodyCatLeg: String, CaseIterable, Sendable {
  case nearFront, farFront, nearHind, farHind
}

/// Registration values are measured in the transparent PNGs, with the origin at the top left.
struct CharacterFullBodyCatArtwork {
  struct Part {
    let asset: CharacterImageAsset
    let pivot: CharacterVectorPoint
    var clip: CharacterVectorPath? = nil
  }

  struct Leg {
    let id: CharacterFullBodyCatLeg
    let art: Part
    let foot: CharacterVectorPoint

    var name: String {
      switch id {
      case .nearFront: "leg.near-front"
      case .farFront: "leg.far-front"
      case .nearHind: "leg.near-hind"
      case .farHind: "leg.far-hind"
      }
    }
  }

  struct Walk {
    let torso: CharacterImageAsset
    let torsoClip: CharacterVectorPath
    let legs: [Leg]
  }

  struct Eye {
    let center: CharacterVectorPoint
    let width: Double
    let height: Double

    init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
      center = .init(x: x, y: y)
      self.width = width
      self.height = height
    }
  }

  struct Muzzle {
    let nose: CharacterRect
    let junction: CharacterVectorPoint

    init(
      _ x: Double, _ y: Double, _ width: Double, _ height: Double,
      mouthX: Double, mouthY: Double
    ) {
      nose = .init(x: x - width / 2, y: y - height / 2, width: width, height: height)
      junction = .init(x: mouthX, y: mouthY)
    }
  }

  struct Face {
    let bounds: CharacterRect
    let left: Eye?
    let right: Eye?
    let muzzle: Muzzle?
    let eyeAngle: Double

    init(
      _ bounds: CharacterRect, left: Eye? = nil, right: Eye? = nil, muzzle: Muzzle? = nil,
      eyeAngle: Double = 0
    ) {
      self.bounds = bounds
      self.left = left
      self.right = right
      self.muzzle = muzzle
      self.eyeAngle = eyeAngle
    }

    var mirrored: Self {
      let size = CharacterFullBodyCatArtwork.size
      func reflect(_ eye: Eye?) -> Eye? {
        eye.map { .init(size - $0.center.x, $0.center.y, $0.width, $0.height) }
      }
      return .init(
        .init(x: size - bounds.maxX, y: bounds.y, width: bounds.width, height: bounds.height),
        left: reflect(right), right: reflect(left),
        muzzle: muzzle.map {
          .init(size - $0.nose.midX, $0.nose.midY, $0.nose.width, $0.nose.height,
            mouthX: size - $0.junction.x, mouthY: $0.junction.y)
        },
        eyeAngle: -eyeAngle
      )
    }
  }

  static let size = 256.0
  static let centerX = size / 2
  static let groundY = 224.0
  static let canvas = CharacterRect(x: 0, y: 0, width: size, height: size)

  let body: CharacterImageAsset
  let face: Face?
  let tail: Part?
  let paw: Part?
  let walk: Walk?

  private init(
    _ name: String, face: Face? = nil, tail: Part? = nil, paw: Part? = nil, walk: Walk? = nil
  ) {
    body = Self.asset(name)
    self.face = face
    self.tail = tail
    self.paw = paw
    self.walk = walk
  }

  static var assets: [CharacterImageAsset] {
    var seen = Set<CharacterImageAsset>()
    return CharacterFullBodyCatPose.allCases.flatMap { pose in
      let artwork = resolve(pose)
      let core = [artwork.body, artwork.tail?.asset, artwork.paw?.asset, artwork.walk?.torso]
        .compactMap { $0 }
      return core + (artwork.walk?.legs.map(\.art.asset) ?? [])
    }.filter { seen.insert($0).inserted }
  }

  static func resolve(_ pose: CharacterFullBodyCatPose) -> Self {
    switch pose {
    case .standing:
      Self(
        "stand",
        face: .init(
          .init(x: 43, y: 97, width: 97, height: 82),
          left: .init(63.5, 142, 8, 13), right: .init(96.5, 142.5, 8, 14),
          muzzle: .init(77.5, 151, 9, 6, mouthX: 78, mouthY: 157)),
        tail: .init(asset: asset("stand-tail"), pivot: .init(x: 166, y: 153.5)))
    case .waving:
      Self(
        "wave",
        face: .init(
          .init(x: 50, y: 81, width: 94, height: 84),
          left: .init(80.5, 125, 8, 13), right: .init(114.5, 125, 8, 13),
          muzzle: .init(97, 133, 9, 6, mouthX: 97, mouthY: 137)),
        paw: .init(asset: asset("wave-paw"), pivot: .init(x: 85, y: 176)))
    case .loaf:
      Self(
        "loaf",
        face: .init(
          .init(x: 45, y: 115, width: 114, height: 108),
          left: .init(77.5, 170.5, 10, 16), right: .init(117, 170.5, 9, 16),
          muzzle: .init(96, 181, 12, 7, mouthX: 96, mouthY: 187)))
    case .left:
      Self(
        "left",
        face: .init(
          .init(x: 18.1, y: 90.3, width: 83.3, height: 89.6),
          right: .init(27.2, 136.5, 7.7, 13.3),
          muzzle: .init(22.3, 147.8, 3.8, 3, mouthX: 24.1, mouthY: 153)),
        walk: leftWalk)
    case .right:
      Self(
        "right",
        face: .init(
          .init(x: 151.1, y: 90.3, width: 84, height: 86.1),
          left: .init(224.6, 137.2, 7, 12.6),
          muzzle: .init(233, 149, 3.8, 3, mouthX: 231, mouthY: 154)),
        walk: rightWalk)
    case .rear:
      Self("rear")
    case .upright:
      Self(
        "upright",
        face: .init(
          .init(x: 64, y: 73, width: 97, height: 72),
          left: .init(89.5, 110, 8, 12), right: .init(122.5, 110, 8, 13),
          muzzle: .init(104.5, 117.5, 8, 6, mouthX: 105, mouthY: 122)))
    case .puffed:
      Self(
        "puff",
        face: .init(
          .init(x: 34, y: 101, width: 79, height: 83),
          right: .init(44, 147, 7, 12),
          muzzle: .init(39.3, 158, 3.8, 3, mouthX: 41.1, mouthY: 163)))
    case .bellyUp:
      Self(
        "belly",
        face: .init(
          .init(x: 26.8, y: 141.2, width: 76.4, height: 81.9),
          left: .init(71, 197.8, 7.5, 12), right: .init(71, 160.5, 7.5, 12),
          muzzle: .init(82, 176.2, 9, 6, mouthX: 88.4, mouthY: 178), eyeAngle: -.pi / 2))
    case .stretch:
      Self(
        "stretch",
        face: .init(
          .init(x: 42, y: 90, width: 85, height: 87),
          left: .init(56.7, 134, 7.4, 13), right: .init(86.6, 136, 8.2, 13),
          muzzle: .init(69.8, 143.6, 9, 6, mouthX: 69, mouthY: 147)))
    }
  }

  private static let leftWalk = makeWalk(right: false)
  private static let rightWalk = makeWalk(right: true)

  private static func makeWalk(right: Bool) -> Walk {
    let side = right ? "right" : "left"
    func point(_ x: Double, _ y: Double) -> CharacterVectorPoint {
      .init(x: right ? size - x : x, y: y)
    }
    func leg(
      _ id: CharacterFullBodyCatLeg, _ name: String,
      _ hipX: Double, _ hipY: Double, _ footX: Double, _ footY: Double
    ) -> Leg {
      .init(
        id: id, art: .init(asset: asset("\(side)-walk-\(name)"), pivot: point(hipX, hipY),
          clip: !right && id == .nearFront ? leftNearForelegClip : nil),
        foot: point(footX, footY))
    }
    // Each hip is inside the opaque intersection of its leg and the clipped
    // torso. The gait maps the same toe anchors while these joints stay buried.
    let legs = right
      ? [
        leg(.farHind, "far-hind", 171, 191, 170.5, 213.5),
        leg(.farFront, "far-front", 76, 185.75, 64, 211),
        leg(.nearHind, "near-hind", 193.5, 185.5, 197.5, 218.5),
        leg(.nearFront, "near-front", 79.25, 186.75, 72.5, 219),
      ] : [
        leg(.farHind, "far-hind", 167, 191, 169, 212.5),
        leg(.farFront, "far-front", 64.25, 181, 47.5, 212),
        leg(.nearHind, "near-hind", 189, 185.75, 195.5, 218.5),
        leg(.nearFront, "near-front", 73.5, 184.75, 64.5, 219),
      ]
    return .init(torso: asset("\(side)-walk-body"), torsoClip: walkTorsoClip(right: right), legs: legs)
  }

  /// The source cut leaves overlap above each hip. This curve rounds the
  /// exposed chest and belly between that overlap and the moving legs.
  private static func walkTorsoClip(right: Bool) -> CharacterVectorPath {
    var path = CharacterVectorPath()
    path.move(0, 0)
    if right {
      path.line(0, 180.2)
      path.line(57, 180.2)
      path.cubic(62, 180.3, 68, 184, 75, 187.5)
      path.cubic(84, 190, 90, 197, 100, 200.5)
      path.cubic(113, 201.8, 133, 202.4, 146, 200.9)
      path.cubic(154, 200.1, 164, 195.25, 176, 192.3)
      path.cubic(188, 188.35, 199, 185.9, 207, 186.1)
      path.line(size, 186.1)
    } else {
      path.line(0, 179)
      path.line(45, 179)
      path.cubic(51, 179, 59, 180.8, 70, 185.6)
      path.cubic(79, 188.5, 87, 196, 97, 200.8)
      path.cubic(111, 203.2, 133, 203.25, 147, 201.15)
      path.cubic(155, 200.1, 165, 194.1, 176, 191.15)
      path.cubic(188, 187.6, 201, 185.2, 208, 185.25)
      path.line(size, 185.25)
    }
    path.line(size, 0)
    path.close()
    return right ? path.mapped { .init(x: size - $0.x, y: $0.y) } : path
  }

  private static let leftNearForelegClip: CharacterVectorPath = {
    // The inside edge of the upper leg is exposed in a stride. Trim its cut
    // corner above the paw pad so the planted outline still reaches the floor.
    var path = CharacterVectorPath()
    path.move(0, 0)
    path.line(size, 0)
    path.line(size, 194)
    path.line(96.2, 194)
    path.cubic(96.2, 197, 94.4, 200.3, 92.6, 201.8)
    path.cubic(92, 202.5, 91.8, 203.2, 91, 204.2)
    path.line(size, 207)
    path.line(size, size)
    path.line(0, size)
    path.close()
    return path
  }()

  private static func asset(_ name: String) -> CharacterImageAsset {
    .init(uncheckedName: "full-body-cat-\(name)", source: .package)
  }
}

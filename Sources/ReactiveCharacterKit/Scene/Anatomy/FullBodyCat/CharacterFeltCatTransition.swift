/// Describes an in-between synthesized from the approved wool textures by the render backend.
struct CharacterFeltCatTransition: Equatable, Sendable {
  enum Route: CaseIterable, Sendable {
    case left, right, stretch, bellyUp, loaf, waving, rear, upright, puffed, puffedRight

    init?(destination: CharacterFullBodyCatPose, puffDirection: CharacterFullBodyCatFacing = .left) {
      switch destination {
      case .left: self = .left
      case .right: self = .right
      case .stretch: self = .stretch
      case .bellyUp: self = .bellyUp
      case .loaf: self = .loaf
      case .waving: self = .waving
      case .rear: self = .rear
      case .upright: self = .upright
      case .puffed: self = puffDirection == .right ? .puffedRight : .puffed
      default: return nil
      }
    }

    var destination: CharacterFullBodyCatPose {
      switch self {
      case .left: .left
      case .right: .right
      case .stretch: .stretch
      case .bellyUp: .bellyUp
      case .loaf: .loaf
      case .waving: .waving
      case .rear: .rear
      case .upright: .upright
      case .puffed, .puffedRight: .puffed
      }
    }

    var entryDuration: Double {
      switch self {
      case .left, .right: 0.48
      case .stretch: 0.45
      case .bellyUp: 0.56
      case .loaf, .upright: 0.40
      case .waving: 0.28
      case .rear: 0.76
      case .puffed: 0.26
      case .puffedRight: 0.43
      }
    }

    var returnDuration: Double {
      switch self {
      case .left, .right: 0.48
      case .stretch: 0.43
      case .bellyUp: 0.57
      case .loaf, .upright: 0.40
      case .waving, .puffed: 0.30
      case .puffedRight: 0.40
      case .rear: 0.76
      }
    }

    var assetKey: String {
      switch self {
      case .bellyUp: "belly"
      case .waving: "wave"
      case .puffed: "puff"
      case .puffedRight: "puffright"
      default: destination.rawValue
      }
    }

    var puffDirection: CharacterFullBodyCatFacing? {
      switch self {
      case .puffed: .left
      case .puffedRight: .right
      default: nil
      }
    }

    struct Waypoint {
      let pose: CharacterFullBodyCatPose
      let index: Int
      let intervals: Int

      var progress: Double { Double(index) / Double(intervals) }
    }

    var intervals: Int {
      switch self {
      case .rear: 19
      case .puffedRight: 17
      default: CharacterFeltCatTransition.intervals
      }
    }

    var waypoint: Waypoint? {
      switch self {
      case .rear: .init(pose: .left, index: CharacterFeltCatTransition.intervals, intervals: intervals)
      case .puffedRight: .init(pose: .right, index: CharacterFeltCatTransition.intervals, intervals: intervals)
      default: nil
      }
    }

    var authoredFrames: Range<Int> {
      switch self {
      case .rear: 6..<12
      case .puffedRight: 1..<5
      default: 1..<intervals
      }
    }

    fileprivate var approach: Self? {
      switch self {
      case .rear: .left
      case .puffedRight: .right
      default: nil
      }
    }

    fileprivate func asset(at frame: Int) -> CharacterImageAsset {
      .init(uncheckedName: "\(CharacterFeltCatTransition.assetNamePrefix)\(assetKey)-\(frame)", source: .package)
    }
  }

  static let intervals = 12
  static let assetNamePrefix = "full-body-cat-transition-"
  static let entryAssets = Route.allCases.compactMap { route in
    route.authoredFrames.first.map { route.asset(at: $0) }
  }

  struct Segment: Sendable {
    let route: Route
    let from: Double
    let to: Double

    private var fraction: Double { abs(to - from) }
    var duration: Double { fraction * (to > from ? route.entryDuration : route.returnDuration) }
    // With the mixed easing curve, peak speed is 1.25 times the mean.
    var minimumAt60Hz: Double { fraction * Double(route.intervals) * 1.25 / 60 }

    func sample(fraction: Double) -> CharacterFeltCatTransition {
      let progress = from + (to - from) * CharacterFullBodyCatMotion.transitionProgress(fraction)
      return .init(route: route, progress: progress)
    }
  }

  static func travel(from departure: Route?, progress: Double, to arrival: Route?) -> [Segment] {
    if let departure, departure == arrival {
      return progress == 1 ? [] : [.init(route: departure, from: progress, to: 1)]
    }
    if let departure, let arrival, let waypoint = departure.waypoint, waypoint.pose == arrival.destination {
      return progress == waypoint.progress ? [] : [.init(route: departure, from: progress, to: waypoint.progress)]
    }
    if let departure, let arrival, let waypoint = arrival.waypoint, waypoint.pose == departure.destination {
      let finishDeparture: [Segment] = progress == 1 ? [] : [.init(route: departure, from: progress, to: 1)]
      return finishDeparture + [.init(route: arrival, from: waypoint.progress, to: 1)]
    }
    var segments: [Segment] = []
    if let departure, progress > 0 { segments.append(.init(route: departure, from: progress, to: 0)) }
    if let arrival { segments.append(.init(route: arrival, from: 0, to: 1)) }
    return segments
  }

  let route: Route
  let progress: Double

  var frameIndex: Int {
    Int((min(1, max(0, progress)) * Double(route.intervals)).rounded())
  }

  var frameAsset: CharacterImageAsset? {
    guard (1..<route.intervals).contains(frameIndex), frameIndex != route.waypoint?.index else { return nil }
    if let approach = route.approach, frameIndex < Self.intervals {
      return approach.asset(at: frameIndex)
    }
    return route.asset(at: authoredIndex)
  }

  var endpoint: CharacterFullBodyCatPose {
    if frameIndex == 0 { return .standing }
    if let waypoint = route.waypoint, frameIndex == waypoint.index { return waypoint.pose }
    return route.destination
  }

  var face: CharacterFullBodyCatArtwork.Face? {
    guard frameAsset != nil, faceOpacity > 0 else { return nil }
    if let approach = route.approach, frameIndex < Self.intervals {
      return CharacterFeltCatTransitionRegistration.frames(for: approach)[frameIndex - 1]
    }
    let authored = CharacterFeltCatTransitionRegistration.frames(for: route)
    if !authored.isEmpty { return authored[authoredIndex - 1] }
    return movingFace(at: Double(frameIndex) / Double(route.intervals))
  }

  private var authoredIndex: Int {
    switch route {
    case .rear: frameIndex - (Self.intervals - 5)   // The stored roll follows the fifth key.
    case .puffedRight: frameIndex - Self.intervals
    default: frameIndex
    }
  }

  var faceOpacity: Double {
    guard route == .rear else { return 1 }
    switch frameIndex {
    case 0...Self.intervals: return 1
    case Self.intervals + 1: return 0.75
    case Self.intervals + 2: return 0.35
    default: return 0
    }
  }

  private func movingFace(at progress: Double) -> CharacterFullBodyCatArtwork.Face? {
    typealias Artwork = CharacterFullBodyCatArtwork
    guard faceOpacity > 0, let standing = Artwork.resolve(.standing).face else { return nil }
    let resolved = Artwork.resolve(route.destination).face
    let end = (route == .puffedRight ? resolved?.mirrored : resolved) ?? .init(
      .init(x: 93, y: 94, width: 70, height: 83),
      left: .init(118, 136, 4, 7), right: .init(141, 136, 4, 7),
      muzzle: .init(130, 143, 4, 3, mouthX: 131, mouthY: 147))
    func mix(_ start: Double, _ finish: Double) -> Double { start + (finish - start) * progress }
    func eye(_ start: Artwork.Eye?, _ finish: Artwork.Eye?) -> Artwork.Eye? {
      guard let start else { return finish }
      if let finish {
        return .init(mix(start.center.x, finish.center.x), mix(start.center.y, finish.center.y),
          mix(start.width, finish.width), mix(start.height, finish.height))
      }
      guard progress < 0.86, let other = end.left ?? end.right else { return nil }
      return .init(mix(start.center.x, other.center.x + 5), mix(start.center.y, other.center.y),
        start.width * (1 - progress), start.height * (1 - progress))
    }
    let muzzle = standing.muzzle.flatMap { start in
      end.muzzle.map { finish in
        Artwork.Muzzle(
          mix(start.nose.midX, finish.nose.midX), mix(start.nose.midY, finish.nose.midY),
          mix(start.nose.width, finish.nose.width), mix(start.nose.height, finish.nose.height),
          mouthX: mix(start.junction.x, finish.junction.x), mouthY: mix(start.junction.y, finish.junction.y))
      }
    }
    let a = standing.bounds
    let b = end.bounds
    return .init(.init(x: mix(a.x, b.x), y: mix(a.y, b.y),
      width: mix(a.width, b.width), height: mix(a.height, b.height)),
      left: eye(standing.left, end.left), right: eye(standing.right, end.right),
      muzzle: muzzle, eyeAngle: mix(standing.eyeAngle, end.eyeAngle))
  }

  struct FaceTurn {
    let amount: Double
    let inward: Double
  }

  var faceTurn: FaceTurn? {
    guard route == .left || route == .right || route == .puffed || route == .puffedRight || route == .rear else {
      return nil
    }
    if route == .puffedRight, frameIndex >= Self.intervals {
      return .init(amount: 1, inward: -1)
    }
    // The rear turn uses the complete left approach before the face goes out of view.
    let yawKey = route == .rear ? min(frameIndex, Self.intervals) : frameIndex
    let progress = Double(yawKey) / Double(Self.intervals)
    let facesRight = route == .right || route == .puffedRight
    let begin = facesRight ? 0.50 : 0.17
    return .init(amount: max(0, (progress - begin) / (1 - begin)), inward: facesRight ? -1 : 1)
  }
}

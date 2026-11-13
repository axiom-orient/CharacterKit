import Testing
@testable import ReactiveCharacterKit

struct CharacterSEMIMouthOpacityTests {
  private func idlePose(detailMotion: CharacterDetailMotion = .still) -> CharacterPose {
    var pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    pose.detailMotion = detailMotion
    return pose
  }

  private func pose(
    basedOn source: CharacterPose,
    visible: Bool = true,
    opacity: Double,
    curvature: Double,
    openness: Double,
    width: Double = 0.68,
    skew: Double = 0
  ) -> CharacterPose {
    let rest = source.mouth
    let mouth = CharacterMouthPose(
      visible: visible, opacity: opacity, curvature: curvature, openness: openness,
      width: width, skew: skew, intrinsicAspect: rest.intrinsicAspect,
      detailOpacity: rest.detailOpacity, referenceGlyphOpacity: rest.referenceGlyphOpacity,
      glyph: rest.glyph, interior: rest.interior, contour: rest.contour, details: rest.details)
    return CharacterPose(
      eyes: source.eyes, nearTrail: source.nearTrail, farTrail: source.farTrail,
      nearTrailOpacity: source.nearTrailOpacity, farTrailOpacity: source.farTrailOpacity,
      noseOffsetX: source.noseOffsetX, mouth: mouth, surface: source.surface,
      writingPhase: source.writingPhase, writingMotionPhase: source.writingMotionPhase,
      writingProgress: source.writingProgress, writingVisible: source.writingVisible,
      writingOpacity: source.writingOpacity, accents: source.accents, motionEnergy: source.motionEnergy,
      eyeContours: source.eyeContours, brows: source.brows, faceDynamics: source.faceDynamics,
      detailMotion: source.detailMotion)
  }

  private func scene(_ pose: CharacterPose) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: pose, artDirection: .semiDocumentCat, width: 512, height: 512)
  }

  private func node(_ id: String, in scene: CharacterScene) throws -> CharacterSceneNode {
    try #require(scene.nodes.first { $0.id == id })
  }

  private func mouthNodes(in scene: CharacterScene) -> [CharacterSceneNode] {
    scene.nodes.filter { $0.id.hasPrefix("mouth.") }
  }

  private func expectClosedStrokeOnlyMouth(in scene: CharacterScene) throws {
    let mouth = mouthNodes(in: scene)
    #expect(!mouth.isEmpty)
    #expect(scene.nodes.contains { $0.id == "mouth.lips" })
    #expect(scene.nodes.contains { $0.id == "mouth.philtrum" })
    #expect(scene.nodes.contains { $0.id == "mouth.whiskers" })
    #expect(!scene.nodes.contains { ["mouth.opening", "mouth.tongue", "mouth.lowerLip"].contains($0.id) })

    let head = try node("semi.head", in: scene)
    for feature in mouth {
      #expect(feature.fill == nil)
      #expect(feature.stroke != nil)
      #expect(!feature.path.commands.isEmpty)
      let startsWithMove = feature.path.commands.first.map { command in
        if case .move = command { return true }
        return false
      } ?? false
      #expect(startsWithMove)
      #expect(!feature.path.commands.contains(.close))
      #expect(feature.clips.isEmpty)
      #expect(feature.transform == head.transform)
    }
  }

  private func transformedPoints(_ node: CharacterSceneNode) -> [CharacterVectorPoint] {
    let transform = node.transform
    func apply(_ point: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(
        x: transform.a * point.x + transform.c * point.y + transform.tx,
        y: transform.b * point.x + transform.d * point.y + transform.ty)
    }
    var points: [CharacterVectorPoint] = []
    for command in node.path.commands {
      switch command {
      case .move(let point), .line(let point):
        points.append(apply(point))
      case .quad(let control, let end):
        points.append(contentsOf: [apply(control), apply(end)])
      case .cubic(let control1, let control2, let end):
        points.append(contentsOf: [apply(control1), apply(control2), apply(end)])
      case .close:
        break
      }
    }
    return points
  }

  private func geometryDistance(_ lhs: CharacterSceneNode, _ rhs: CharacterSceneNode) -> Double {
    let left = transformedPoints(lhs)
    let right = transformedPoints(rhs)
    guard left.count == right.count else { return .infinity }
    return zip(left, right).reduce(0) { total, pair in
      total + abs(pair.0.x - pair.1.x) + abs(pair.0.y - pair.1.y)
    }
  }

  @Test
  func hiddenZeroAndNegativeOpacityKeepNeutralClosedLineGeometry() throws {
    let source = idlePose(detailMotion: .sample(time: 0.17, impulse: 0.6, amount: 0.85))
    let hiddenPose = pose(
      basedOn: source, visible: false, opacity: 1, curvature: 1, openness: 1, skew: 0.8)
    let zeroPose = pose(basedOn: source, opacity: 0, curvature: 1, openness: 1, skew: 0.8)
    let negativePose = pose(
      basedOn: source, opacity: -0.5, curvature: 1, openness: 1, skew: 0.8)
    #expect(hiddenPose.detailMotion == source.detailMotion)
    #expect(zeroPose.detailMotion == source.detailMotion)
    #expect(negativePose.detailMotion == source.detailMotion)
    let hidden = try scene(hiddenPose)
    let zero = try scene(zeroPose)
    let negative = try scene(negativePose)

    for frame in [hidden, zero, negative] {
      try expectClosedStrokeOnlyMouth(in: frame)
      let lips = try node("mouth.lips", in: frame)
      #expect(!lips.path.commands.isEmpty)
      #expect(try node("mouth.philtrum", in: frame).path.commands.count > 0)
    }

    #expect(transformedPoints(try node("mouth.lips", in: hidden))
      == transformedPoints(try node("mouth.lips", in: zero)))
    #expect(transformedPoints(try node("mouth.lips", in: zero))
      == transformedPoints(try node("mouth.lips", in: negative)))
    #expect(try node("semi.head", in: hidden).transform == node("semi.head", in: zero).transform)
  }

  @Test
  func fractionalOpacityProgressivelyChangesClosedLineCurvature() throws {
    let source = idlePose()
    let opacities = [0.0, 0.25, 0.5, 1.0]
    let frames = try opacities.map { opacity in
      try scene(pose(
        basedOn: source, opacity: opacity, curvature: 1, openness: 1, width: 1.0))
    }
    let restLips = try node("mouth.lips", in: frames[0])
    let quarterLips = try node("mouth.lips", in: frames[1])
    let halfLips = try node("mouth.lips", in: frames[2])
    let fullLips = try node("mouth.lips", in: frames[3])
    let quarterDistance = geometryDistance(restLips, quarterLips)
    let halfDistance = geometryDistance(restLips, halfLips)
    let fullDistance = geometryDistance(restLips, fullLips)

    for frame in frames { try expectClosedStrokeOnlyMouth(in: frame) }

    #expect(quarterDistance > 0)
    #expect(halfDistance > quarterDistance)
    #expect(fullDistance > halfDistance)
    let headAtZero = try node("semi.head", in: frames[0]).transform
    let headAtQuarter = try node("semi.head", in: frames[1]).transform
    let headAtHalf = try node("semi.head", in: frames[2]).transform
    let headAtFull = try node("semi.head", in: frames[3]).transform
    #expect(headAtQuarter != headAtZero)
    #expect(headAtHalf != headAtQuarter)
    #expect(headAtFull != headAtHalf)
  }

  @Test
  func fractionalOpacityProgressivelyChangesSkewContribution() throws {
    let source = idlePose()
    let opacities = [0.0, 0.25, 0.5, 1.0]
    let straight = try opacities.map { opacity in
      try scene(pose(basedOn: source, opacity: opacity, curvature: 0, openness: 0, skew: 0))
    }
    let skewed = try opacities.map { opacity in
      try scene(pose(basedOn: source, opacity: opacity, curvature: 0, openness: 0, skew: 0.8))
    }
    let distances = try opacities.indices.map { index in
      geometryDistance(
        try node("mouth.lips", in: straight[index]),
        try node("mouth.lips", in: skewed[index]))
    }

    #expect(distances[0] == 0)
    #expect(distances[1] > distances[0])
    #expect(distances[2] > distances[1])
    #expect(distances[3] > distances[2])
  }
}

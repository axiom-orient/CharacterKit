import Foundation
import Testing
@testable import ReactiveCharacterKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct CharacterSEMIVisualQualityTests {
  private let direction = CharacterArtDirection.semiDocumentCat

  private struct WhiskerShapeProfile {
    let roots: [CharacterVectorPoint]
    let tips: [CharacterVectorPoint]
    let slopes: [Double]
    let horizontalReaches: [Double]
    let arcLengths: [Double]
    let minimumOutwardProgress: [Double]
    let curveDeviationRatios: [Double]
    let endpointTangentTurns: [Double]
    let jointTangentTurns: [Double]
  }

  private func state(_ events: [CharacterEvent]) -> CharacterState {
    events.reduce(.idle) { ReactiveCharacter.act(state: $0, event: $1).stateAfter }
  }

  private func pose(
    _ state: CharacterState = .idle,
    time: Double = 0.8,
    reduced: Bool = false
  ) -> CharacterPose {
    ReactiveCharacter.pose(
      state: state, elapsed: time, reduceMotion: reduced,
      projection: direction.projection, motionProfile: direction.motionProfile)
  }

  private func semiPose(
    _ state: CharacterState = .idle,
    time: Double = 0.8,
    reduced: Bool = false
  ) -> CharacterPose {
    ReactiveCharacter.pose(
      state: state, elapsed: time, artDirection: direction, reduceMotion: reduced)
  }

  private func scene(
    _ pose: CharacterPose, direction: CharacterArtDirection? = nil,
    width: Double = 320, height: Double? = nil
  ) throws -> CharacterScene {
    let artDirection = direction ?? self.direction
    return try CharacterSceneBuilder.scene(
      pose: pose, artDirection: artDirection, width: width, height: height ?? width,
      includeBackground: false)
  }

  private func node(_ id: String, in scene: CharacterScene) throws -> CharacterSceneNode {
    try #require(scene.nodes.first { $0.id == id })
  }

  private func changingDetailMotion(
    of source: CharacterPose,
    time: Double,
    impulse: Double,
    amount: Double
  ) -> CharacterPose {
    var result = source
    result.detailMotion = CharacterDetailMotion.sample(time: time, impulse: impulse, amount: amount)
    return result
  }

  private func whiskerMotionStates() throws -> [(String, CharacterState)] {
    let taskID = try CharacterTaskID(validating: "whisker-motion")
    let bounceID = try CharacterAnimationID(validating: "whisker-bounce")
    let recoilID = try CharacterAnimationID(validating: "whisker-recoil")
    return [
      ("thinking", state([.agentStarted(taskID: taskID)])),
      ("writing", state([
        .agentStarted(taskID: taskID), .agentProgress(taskID: taskID, progress: 0.72),
      ])),
      ("cancelling", state([
        .agentStarted(taskID: taskID), .agentCancellationRequested(taskID: taskID),
      ])),
      ("chat", state([.chatStarted])),
      ("listening", state([.listeningStarted, .listeningLevelChanged(0.82)])),
      ("voice", state([.voiceStarted, .voiceLevelChanged(0.82)])),
      ("bounce", state([.animationStarted(id: bounceID, animation: .bounce)])),
      ("recoil", state([.animationStarted(id: recoilID, animation: .recoil)])),
    ]
  }

  private func points(_ node: CharacterSceneNode) -> [CharacterVectorPoint] {
    let transform = node.transform
    func apply(_ point: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(
        x: transform.a * point.x + transform.c * point.y + transform.tx,
        y: transform.b * point.x + transform.d * point.y + transform.ty)
    }
    var result: [CharacterVectorPoint] = []
    for command in node.path.commands {
      switch command {
      case .move(let point), .line(let point):
        result.append(apply(point))
      case .quad(let control, let end):
        result.append(contentsOf: [apply(control), apply(end)])
      case .cubic(let control1, let control2, let end):
        result.append(contentsOf: [apply(control1), apply(control2), apply(end)])
      case .close:
        break
      }
    }
    return result
  }

  private func sampledPoints(
    _ node: CharacterSceneNode,
    stepsPerSegment: Int = 16
  ) -> [CharacterVectorPoint] {
    let transform = node.transform
    func apply(_ point: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(
        x: transform.a * point.x + transform.c * point.y + transform.tx,
        y: transform.b * point.x + transform.d * point.y + transform.ty)
    }
    func mix(_ start: CharacterVectorPoint, _ end: CharacterVectorPoint, _ t: Double)
      -> CharacterVectorPoint {
      .init(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    var result: [CharacterVectorPoint] = []
    var current: CharacterVectorPoint?
    for command in node.path.commands {
      switch command {
      case .move(let point):
        current = point
        result.append(apply(point))
      case .line(let end):
        current = end
        result.append(apply(end))
      case .quad(let control, let end):
        guard let start = current else { continue }
        for step in 1...stepsPerSegment {
          let t = Double(step) / Double(stepsPerSegment)
          let first = mix(start, control, t)
          let second = mix(control, end, t)
          result.append(apply(mix(first, second, t)))
        }
        current = end
      case .cubic(let control1, let control2, let end):
        guard let start = current else { continue }
        for step in 1...stepsPerSegment {
          let t = Double(step) / Double(stepsPerSegment)
          let first = mix(start, control1, t)
          let second = mix(control1, control2, t)
          let third = mix(control2, end, t)
          let fourth = mix(first, second, t)
          let fifth = mix(second, third, t)
          result.append(apply(mix(fourth, fifth, t)))
        }
        current = end
      case .close:
        break
      }
    }
    return result
  }

  private func sampledBounds(_ node: CharacterSceneNode)
    -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let values = sampledPoints(node)
    return (
      values.map(\.x).min() ?? 0, values.map(\.y).min() ?? 0,
      values.map(\.x).max() ?? 0, values.map(\.y).max() ?? 0)
  }

  private func sampledSubpathArcLengths(
    _ node: CharacterSceneNode,
    stepsPerSegment: Int = 16
  ) -> [Double] {
    let transform = node.transform
    func apply(_ point: CharacterVectorPoint) -> CharacterVectorPoint {
      .init(
        x: transform.a * point.x + transform.c * point.y + transform.tx,
        y: transform.b * point.x + transform.d * point.y + transform.ty)
    }
    func distance(_ lhs: CharacterVectorPoint, _ rhs: CharacterVectorPoint) -> Double {
      hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
    func mix(_ start: CharacterVectorPoint, _ end: CharacterVectorPoint, _ t: Double)
      -> CharacterVectorPoint {
      .init(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    var lengths: [Double] = []
    var subpathStart: CharacterVectorPoint?
    var current: CharacterVectorPoint?
    var arcLength = 0.0
    func finishSubpath() {
      guard current != nil, subpathStart != nil else { return }
      lengths.append(arcLength)
    }

    for command in node.path.commands {
      switch command {
      case .move(let point):
        finishSubpath()
        let world = apply(point)
        subpathStart = world
        current = world
        arcLength = 0
      case .line(let end):
        let world = apply(end)
        if let current { arcLength += distance(current, world) }
        current = world
      case .quad(let control, let end):
        guard let start = current else { continue }
        let worldControl = apply(control)
        let worldEnd = apply(end)
        var previous = start
        for step in 1...stepsPerSegment {
          let t = Double(step) / Double(stepsPerSegment)
          let point = mix(mix(start, worldControl, t), mix(worldControl, worldEnd, t), t)
          arcLength += distance(previous, point)
          previous = point
        }
        current = worldEnd
      case .cubic(let control1, let control2, let end):
        guard let start = current else { continue }
        let worldControl1 = apply(control1)
        let worldControl2 = apply(control2)
        let worldEnd = apply(end)
        var previous = start
        for step in 1...stepsPerSegment {
          let t = Double(step) / Double(stepsPerSegment)
          let first = mix(start, worldControl1, t)
          let second = mix(worldControl1, worldControl2, t)
          let third = mix(worldControl2, worldEnd, t)
          let point = mix(mix(first, second, t), mix(second, third, t), t)
          arcLength += distance(previous, point)
          previous = point
        }
        current = worldEnd
      case .close:
        if let currentPoint = current, let startPoint = subpathStart {
          arcLength += distance(currentPoint, startPoint)
          current = startPoint
        }
      }
    }
    finishSubpath()
    return lengths
  }

  private func assertExtendedWhiskerReach(
    in scene: CharacterScene,
    context: String
  ) throws {
    let whiskers = sampledSubpathArcLengths(try node("mouth.whiskers", in: scene))
    let nose = sampledBounds(try node("nose", in: scene))
    let noseWidth = nose.maxX - nose.minX
    #expect(whiskers.count == 6 && noseWidth > 0,
      "\(context): six measured strands and registered nose width")
    for (index, length) in whiskers.enumerated() {
      let ratio = length / max(0.000_001, noseWidth)
      #expect(ratio >= 0.62,
        "\(context): ordinary strand \(index) remains extended; arc/nose ratio=\(ratio)")
      #expect(ratio <= 3.8,
        "\(context): ordinary strand \(index) stays within shortness cap; arc/nose ratio=\(ratio)")
    }
  }

  private func whiskerShapeProfile(_ node: CharacterSceneNode) -> WhiskerShapeProfile {
    func distance(_ lhs: CharacterVectorPoint, _ rhs: CharacterVectorPoint) -> Double {
      hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
    func mix(_ start: CharacterVectorPoint, _ end: CharacterVectorPoint, _ t: Double)
      -> CharacterVectorPoint {
      .init(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }
    func tangentTurn(_ lhs: CharacterVectorPoint, _ rhs: CharacterVectorPoint) -> Double {
      let dot = lhs.x * rhs.x + lhs.y * rhs.y
      let cross = lhs.x * rhs.y - lhs.y * rhs.x
      return atan2(abs(cross), dot)
    }

    var roots: [CharacterVectorPoint] = []
    var tips: [CharacterVectorPoint] = []
    var slopes: [Double] = []
    var horizontalReaches: [Double] = []
    var arcLengths: [Double] = []
    var minimumOutwardProgress: [Double] = []
    var curveDeviationRatios: [Double] = []
    var endpointTangentTurns: [Double] = []
    var jointTangentTurns: [Double] = []
    var root: CharacterVectorPoint?
    var current: CharacterVectorPoint?
    var samples: [CharacterVectorPoint] = []
    var firstTangent: CharacterVectorPoint?
    var previousEndTangent: CharacterVectorPoint?
    var maximumJointTangentTurn = 0.0
    func finishStrand() {
      guard let root, let current else { return }
      let chordX = current.x - root.x
      let chordY = current.y - root.y
      let chord = CharacterVectorPoint(x: chordX, y: chordY)
      let chordLength = max(0.000_001, hypot(chordX, chordY))
      let deviation = samples.map { point in
        abs(chordX * (point.y - root.y) - chordY * (point.x - root.x)) / chordLength
      }.max() ?? 0
      roots.append(root)
      tips.append(current)
      slopes.append((current.y - root.y) / max(0.000_001, abs(chordX)))
      horizontalReaches.append(abs(chordX))
      let outwardSign = roots.count <= 3 ? -1.0 : 1.0
      minimumOutwardProgress.append(zip(samples, samples.dropFirst()).map {
        outwardSign * ($0.1.x - $0.0.x)
      }.min() ?? 0)
      arcLengths.append(zip(samples, samples.dropFirst()).reduce(0.0) {
        $0 + distance($1.0, $1.1)
      })
      curveDeviationRatios.append(deviation / chordLength)
      if let firstTangent, let previousEndTangent {
        endpointTangentTurns.append(max(
          tangentTurn(firstTangent, chord), tangentTurn(previousEndTangent, chord)))
      }
      jointTangentTurns.append(maximumJointTangentTurn)
    }

    for command in node.path.commands {
      switch command {
      case .move(let point):
        finishStrand()
        root = point
        current = point
        samples = [point]
        firstTangent = nil
        previousEndTangent = nil
        maximumJointTangentTurn = 0
      case .line(let end):
        current = end
        samples.append(end)
      case .quad(let control, let end):
        guard let start = current else { continue }
        for step in 1...16 {
          let t = Double(step) / 16
          samples.append(mix(mix(start, control, t), mix(control, end, t), t))
        }
        current = end
      case .cubic(let control1, let control2, let end):
        guard let start = current else { continue }
        let startTangent = CharacterVectorPoint(
          x: control1.x - start.x, y: control1.y - start.y)
        let endTangent = CharacterVectorPoint(
          x: end.x - control2.x, y: end.y - control2.y)
        if let previousEndTangent {
          maximumJointTangentTurn = max(
            maximumJointTangentTurn, tangentTurn(previousEndTangent, startTangent))
        } else {
          firstTangent = startTangent
        }
        for step in 1...16 {
          let t = Double(step) / 16
          let first = mix(start, control1, t)
          let second = mix(control1, control2, t)
          let third = mix(control2, end, t)
          samples.append(mix(mix(first, second, t), mix(second, third, t), t))
        }
        current = end
        previousEndTangent = endTangent
      case .close:
        break
      }
    }
    finishStrand()
    return .init(roots: roots, tips: tips, slopes: slopes,
      horizontalReaches: horizontalReaches, arcLengths: arcLengths,
      minimumOutwardProgress: minimumOutwardProgress,
      curveDeviationRatios: curveDeviationRatios,
      endpointTangentTurns: endpointTangentTurns, jointTangentTurns: jointTangentTurns)
  }

  private func assertReferenceWhiskerFan(
    _ profile: WhiskerShapeProfile,
    context: String,
    middleSlopeLimit: Double? = 0.20
  ) {
    #expect(profile.roots.count == 6 && profile.tips.count == 6,
      "\(context): three individually rooted strands per cheek")
    #expect(profile.slopes.count == 6 && profile.arcLengths.count == 6)
    #expect(profile.horizontalReaches.count == 6)
    #expect(profile.curveDeviationRatios.count == 6)
    #expect(profile.minimumOutwardProgress.count == 6)
    #expect(profile.minimumOutwardProgress.allSatisfy { $0 >= -0.02 },
      "\(context): each shaft progresses outward without foldback; minimum steps=\(profile.minimumOutwardProgress)")

    for cheekStart in [0, 3] {
      let upperSlope = profile.slopes[cheekStart]
      let middleSlope = profile.slopes[cheekStart + 1]
      let lowerSlope = profile.slopes[cheekStart + 2]
      #expect(upperSlope < middleSlope - 0.01 && middleSlope < lowerSlope - 0.01,
        "\(context): upper, middle, and lower strands retain the reference fan order; slopes=\(upperSlope),\(middleSlope),\(lowerSlope)")
      if let middleSlopeLimit {
        #expect(abs(middleSlope) < middleSlopeLimit,
          "\(context): middle strand remains close to horizontal; slope=\(middleSlope)")
      }
      #expect(profile.horizontalReaches[cheekStart]
        < profile.horizontalReaches[cheekStart + 1] * 0.90,
        "\(context): upper strand stops distinctly before the middle strand")
      #expect(profile.horizontalReaches[cheekStart + 2]
        < profile.horizontalReaches[cheekStart + 1] * 0.99,
        "\(context): lower strand keeps its separately adjusted reach")

    }

    #expect(profile.curveDeviationRatios.allSatisfy { $0 < 0.10 },
      "\(context): whisker shafts keep a mild bow; bow/chord=\(profile.curveDeviationRatios)")
    #expect(profile.endpointTangentTurns.count == 6
      && profile.endpointTangentTurns.allSatisfy { $0 < 0.22 },
      "\(context): end tangents follow each shaft smoothly; turns=\(profile.endpointTangentTurns)")
    #expect(profile.jointTangentTurns.count == 6
      && profile.jointTangentTurns.allSatisfy { $0 < 0.14 },
      "\(context): sampled cubic joints stay continuous; turns=\(profile.jointTangentTurns)")
  }

  #if canImport(CoreGraphics)
    private func worldPath(_ node: CharacterSceneNode) -> CGPath {
      let path = CGMutablePath()
      func apply(_ point: CharacterVectorPoint) -> CGPoint {
        let transform = node.transform
        return CGPoint(
          x: CGFloat(transform.a * point.x + transform.c * point.y + transform.tx),
          y: CGFloat(transform.b * point.x + transform.d * point.y + transform.ty))
      }
      for command in node.path.commands {
        switch command {
        case .move(let point): path.move(to: apply(point))
        case .line(let point): path.addLine(to: apply(point))
        case .quad(let control, let end):
          path.addQuadCurve(to: apply(end), control: apply(control))
        case .cubic(let control1, let control2, let end):
          path.addCurve(to: apply(end), control1: apply(control1), control2: apply(control2))
        case .close: path.closeSubpath()
        }
      }
      return path
    }

    private func strokedWorldPath(_ node: CharacterSceneNode) -> CGPath? {
      guard node.stroke != nil, node.lineWidth > 0 else { return nil }
      let transform = node.transform
      let scale = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
      return worldPath(node).copy(
        strokingWithWidth: CGFloat(node.lineWidth * scale),
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 2)
    }

    private func visibleInkPath(_ node: CharacterSceneNode) -> CGPath? {
      guard node.opacity > 0.02 else { return nil }
      let result = CGMutablePath()
      var hasInk = false
      if node.fill != nil {
        result.addPath(worldPath(node))
        hasInk = true
      }
      if let stroke = strokedWorldPath(node) {
        result.addPath(stroke)
        hasInk = true
      }
      return hasInk ? result : nil
    }

    private func sampledIntersection(_ lhs: CGPath, _ rhs: CGPath) -> Bool {
      let overlap = lhs.boundingBoxOfPath.intersection(rhs.boundingBoxOfPath)
      guard !overlap.isNull, !overlap.isEmpty else { return false }
      var y = overlap.minY + 0.125
      while y < overlap.maxY {
        var x = overlap.minX + 0.125
        while x < overlap.maxX {
          let point = CGPoint(x: x, y: y)
          if lhs.contains(point) && rhs.contains(point) { return true }
          x += 0.5
        }
        y += 0.5
      }
      return false
    }

    private func assertWhiskerStrokeGeometry(
      in scene: CharacterScene,
      context: String
    ) throws {
      let whiskerNodes = scene.nodes.filter { $0.id.hasPrefix("mouth.whiskers") }
      #expect(whiskerNodes.contains { $0.id == "mouth.whiskers" })
      #expect(whiskerNodes.contains { $0.id == "mouth.whiskers.edge" })
      let mainWhiskers = try node("mouth.whiskers", in: scene)
      let strands = sampledSubpathArcLengths(mainWhiskers)
      let noseBounds = sampledBounds(try node("nose", in: scene))
      let noseWidth = noseBounds.maxX - noseBounds.minX
      #expect(strands.count == 6, "\(context): six individual whisker strands")
      #expect(noseWidth > 0, "\(context): nose width provides a registered length scale")
      for (index, length) in strands.enumerated() {
        let relativeLength = length / max(0.000_001, noseWidth)
        #expect(relativeLength <= 3.8,
          "\(context): strand \(index) stays short relative to nose width; arc ratio=\(relativeLength)")
      }
      let eyeContours = scene.nodes.filter {
        ($0.id == "eye.left" || $0.id == "eye.right"
          || $0.id == "eye.left.closed" || $0.id == "eye.right.closed")
      }
      let document = try node("semi.document", in: scene)
      let documentInk = try #require(visibleInkPath(document))
      for whiskerNode in whiskerNodes {
        guard let whiskerInk = strokedWorldPath(whiskerNode) else { continue }
        let bounds = whiskerInk.boundingBoxOfPath
        let transform = whiskerNode.transform
        let details = "worldBounds=\(bounds), transform=(\(transform.a),\(transform.b),\(transform.c),\(transform.d),\(transform.tx),\(transform.ty)), lineWidth=\(whiskerNode.lineWidth), opacity=\(whiskerNode.opacity)"
        #expect(bounds.minX >= 0 && bounds.maxX <= CGFloat(scene.width),
          "\(context): \(whiskerNode.id) stroke stays inside viewport horizontally; \(details)")
        #expect(bounds.minY >= 0 && bounds.maxY <= CGFloat(scene.height),
          "\(context): \(whiskerNode.id) stroke stays inside viewport vertically; \(details)")

        for eye in eyeContours {
          guard let eyeInk = visibleInkPath(eye) else { continue }
          #expect(!sampledIntersection(whiskerInk, eyeInk),
            "\(context): \(whiskerNode.id) stroke stays outside \(eye.id); whisker \(details), eyeBounds=\(eyeInk.boundingBoxOfPath), eyeOpacity=\(eye.opacity), eyeLineWidth=\(eye.lineWidth), eyeTransform=(\(eye.transform.a),\(eye.transform.b),\(eye.transform.c),\(eye.transform.d),\(eye.transform.tx),\(eye.transform.ty))")
        }

        #expect(!sampledIntersection(whiskerInk, documentInk),
          "\(context): \(whiskerNode.id) stroke stays outside held document; \(details), documentBounds=\(documentInk.boundingBoxOfPath)")
      }
    }
  #endif

  private func bounds(_ node: CharacterSceneNode) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let values = points(node)
    return (
      values.map(\.x).min() ?? 0, values.map(\.y).min() ?? 0,
      values.map(\.x).max() ?? 0, values.map(\.y).max() ?? 0)
  }

  private func distance(_ lhs: CharacterSceneNode, _ rhs: CharacterSceneNode) -> Double {
    let left = points(lhs)
    let right = points(rhs)
    guard left.count == right.count else { return .infinity }
    return zip(left, right).reduce(0) { total, pair in
      total + abs(pair.0.x - pair.1.x) + abs(pair.0.y - pair.1.y)
    }
  }

  private func eye(_ side: String, in scene: CharacterScene) throws -> CharacterSceneNode {
    try #require(scene.nodes.first { $0.id == "eye.\(side)" })
  }

  private func mouthNodes(in scene: CharacterScene) -> [CharacterSceneNode] {
    scene.nodes.filter { $0.id.hasPrefix("mouth.") }
  }

  private func facialLinesExcludingWhiskers(in scene: CharacterScene) -> [CharacterSceneNode] {
    mouthNodes(in: scene).filter { !$0.id.hasPrefix("mouth.whiskers") }
  }

  private func assertClosedStrokeOnlyMouth(in scene: CharacterScene) throws {
    let features = mouthNodes(in: scene)
    #expect(!features.isEmpty)
    for id in ["mouth.lips", "mouth.philtrum", "mouth.whiskers"] {
      #expect(scene.nodes.contains { $0.id == id })
    }
    #expect(!scene.nodes.contains { ["mouth.opening", "mouth.tongue", "mouth.lowerLip"].contains($0.id) })

    let head = try node("semi.head", in: scene)
    for feature in features {
      #expect(feature.fill == nil, "\(feature.id) is stroke-only")
      #expect(feature.stroke != nil, "\(feature.id) has a visible stroke")
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

  private func assertMouthStaysInsideFaceAndAboveDocument(
    in scene: CharacterScene, context: String = "mouth geometry"
  ) throws {
    let face = scene.faceBounds
    let documentTop = bounds(try node("semi.document", in: scene)).minY
    for feature in facialLinesExcludingWhiskers(in: scene) {
      let box = bounds(feature)
      let strokeRadius = feature.lineWidth * hypot(feature.transform.a, feature.transform.b) / 2
      #expect(box.minX >= face.x && box.maxX <= face.x + face.width,
        "\(context): \(feature.id) stays inside face bounds")
      #expect(box.minY >= face.y && box.maxY <= face.y + face.height,
        "\(context): \(feature.id) stays inside face bounds")
      #expect(box.maxY + strokeRadius < documentTop,
        "\(context): \(feature.id) keeps its stroke above the held document")
    }
  }

  private func upperEyeProfile(
    _ side: String, in scene: CharacterScene
  ) throws -> (innerRise: Double, upperDroop: Double) {
    let samples = points(try eye(side, in: scene))
    let outerCorner = try #require(samples.first)
    let upperCrown = try #require(samples.dropFirst(3).first)
    let innerCorner = try #require(samples.dropFirst(6).first)
    let (inner, outer) = side == "left"
      ? (innerCorner, outerCorner)
      : (outerCorner, innerCorner)
    return (
      outer.y - inner.y,
      upperCrown.y - (outer.y + inner.y) / 2)
  }

  @Test(arguments: [64.0, 128.0, 200.0, 320.0])
  func omegaIsReadableAtNativeReviewSize(_ size: Double) throws {
    let frame = try scene(pose(.idle, reduced: true), width: size)
    try assertClosedStrokeOnlyMouth(in: frame)
    let lips = try node("mouth.lips", in: frame)
    let box = bounds(lips)
    let renderedWidth = box.maxX - box.minX
    let renderedStroke = lips.lineWidth * hypot(lips.transform.a, lips.transform.b)

    #expect(renderedWidth >= max(6.5, size * 0.03), "\(size)px mouth width")
    #expect(renderedStroke >= 0.95, "\(size)px lip ink")
    try CharacterSceneValidation.validate(frame)
  }

  @Test(arguments: [200.0, 320.0])
  func mouthLinesStayInsideFaceAndAboveDocumentAtNativeSizes(_ size: Double) throws {
    let joy = try scene(pose(state([.emotionChanged(.joy)]), reduced: true), width: size)
    try assertClosedStrokeOnlyMouth(in: joy)
    let lips = try node("mouth.lips", in: joy)
    let mouthWidth = bounds(lips).maxX - bounds(lips).minX
    #expect(mouthWidth >= max(6.5, size * 0.03), "\(size)px closed-lip span")
    #expect(bounds(lips).minX > bounds(try eye("left", in: joy)).minX)
    #expect(bounds(lips).maxX < bounds(try eye("right", in: joy)).maxX)
    try assertMouthStaysInsideFaceAndAboveDocument(in: joy)
    try CharacterSceneValidation.validate(joy)
  }

  @Test(arguments: [64.0, 128.0, 200.0, 320.0])
  func mouthClearanceSurvivesAllExpressionsCommunicationAndMotion(_ size: Double) throws {
    var semanticStates = CharacterEmotion.allCases.map {
      ($0.rawValue, state([.emotionChanged($0)]))
    }
    semanticStates += [
      ("voice-0", state([.voiceStarted, .voiceLevelChanged(0)])),
      ("voice-05", state([.voiceStarted, .voiceLevelChanged(0.5)])),
      ("voice-1", state([.voiceStarted, .voiceLevelChanged(1)])),
      ("chat", state([.chatStarted])),
      ("listening", state([.listeningStarted, .listeningLevelChanged(1)])),
    ]
    let task = try CharacterTaskID(validating: "quality-writing")
    semanticStates.append(("writing", state([
      .agentStarted(taskID: task), .agentProgress(taskID: task, progress: 0.75)
    ])))

    for reduceMotion in [false, true] {
      let motionLabel = reduceMotion ? "reduced" : "animated"
      for (label, input) in semanticStates {
        let frame = try scene(pose(input, time: 0.8, reduced: reduceMotion), width: size)
        try assertClosedStrokeOnlyMouth(in: frame)
        try assertMouthStaysInsideFaceAndAboveDocument(
          in: frame, context: "\(size)px \(motionLabel) \(label)")
      }

      for animation in CharacterAnimation.allCases {
        let id = try CharacterAnimationID(validating: "clearance-\(animation.rawValue)")
        let input = state([.animationStarted(id: id, animation: animation)])
        for time in [0, animation.duration * 0.5, animation.duration + 0.05] {
          let frame = try scene(pose(input, time: time, reduced: reduceMotion), width: size)
          try assertClosedStrokeOnlyMouth(in: frame)
          try assertMouthStaysInsideFaceAndAboveDocument(
            in: frame, context: "\(size)px \(motionLabel) \(animation.rawValue) at \(time)s")
        }
      }
    }
  }

  @Test
  func joyAndGratitudeHaveDifferentSmileAndMouthContours() throws {
    let joy = try scene(pose(state([.emotionChanged(.joy)]), reduced: true))
    let gratitude = try scene(pose(state([.emotionChanged(.gratitude)]), reduced: true))
    let joyArc = bounds(try eye("left", in: joy))
    let gratitudeArc = bounds(try eye("left", in: gratitude))
    let joyArcWidth = joyArc.maxX - joyArc.minX
    let gratitudeArcWidth = gratitudeArc.maxX - gratitudeArc.minX
    try assertClosedStrokeOnlyMouth(in: joy)
    try assertClosedStrokeOnlyMouth(in: gratitude)

    #expect(joyArcWidth > gratitudeArcWidth * 1.10)
    #expect(try node("mouth.lips", in: joy).path != node("mouth.lips", in: gratitude).path)
  }

  @Test
  func sadnessFearAndFatigueTrustUseIndependentFaceCues() throws {
    let sadness = try scene(pose(state([.emotionChanged(.sadness)]), reduced: true))
    let fear = try scene(pose(state([.emotionChanged(.anxietyFear)]), reduced: true))
    let fatigue = try scene(pose(state([.emotionChanged(.fatigueBurden)]), reduced: true))
    let calmTrust = try scene(pose(state([.emotionChanged(.calmTrust)]), reduced: true))
    let sadnessEye = bounds(try eye("left", in: sadness))
    let fearEye = bounds(try eye("left", in: fear))
    let fatigueEye = bounds(try eye("left", in: fatigue))
    let calmEye = bounds(try eye("left", in: calmTrust))
    let sadnessHeight = sadnessEye.maxY - sadnessEye.minY
    let fearHeight = fearEye.maxY - fearEye.minY
    let fatigueHeight = fatigueEye.maxY - fatigueEye.minY
    let calmHeight = calmEye.maxY - calmEye.minY
    try assertClosedStrokeOnlyMouth(in: sadness)
    try assertClosedStrokeOnlyMouth(in: fear)
    try assertClosedStrokeOnlyMouth(in: fatigue)
    try assertClosedStrokeOnlyMouth(in: calmTrust)

    #expect(fearHeight > sadnessHeight * 1.08)
    #expect(fatigueHeight < calmHeight * 0.78)
    #expect(try node("mouth.lips", in: fatigue).path != node("mouth.lips", in: calmTrust).path)
    #expect(try node("semi.head", in: sadness).transform
      != node("semi.head", in: fear).transform)
    #expect(try node("semi.tail", in: fatigue).transform
      != node("semi.tail", in: calmTrust).transform)
  }

  @Test
  func SEMIEyesKeepPupilsClippedAndUseOnlyIntentionalExpressionLines() throws {
    let voice = state([.voiceStarted, .voiceLevelChanged(0.82)])
    let chat = state([.chatStarted])
    let listening = state([.listeningStarted, .listeningLevelChanged(0.82)])
    let inputs: [(String, CharacterState)] = [("idle", .idle)]
      + CharacterEmotion.allCases.map { ($0.rawValue, state([.emotionChanged($0)])) }
      + [("voice", voice), ("chat", chat), ("listening", listening)]

    for (label, input) in inputs {
      let frame = try scene(pose(input, reduced: true))
      #expect(!frame.nodes.contains {
        $0.id.hasSuffix(".lid.upper") || $0.id.hasSuffix(".lid.lower")
      }, "\(label) has no unrelated internal lid strokes")

      for side in ["left", "right"] {
        let eyeID = "eye.\(side)"
        let principal = try #require(frame.nodes.first {
          $0.id == eyeID || $0.id == eyeID + ".closed"
        }, "\(label) has a principal \(side) eye contour")
        #expect(principal.fill != nil || principal.stroke != nil,
          "\(label) principal \(side) eye remains visible")

        let aperture = frame.nodes.first { $0.id == eyeID && $0.fill != nil }
        if let aperture, aperture.opacity > 0.02 {
          let pupil = try #require(frame.nodes.first { $0.id == eyeID + ".pupil" },
            "\(label) visible \(side) eye keeps its pupil")
          let glint = try #require(frame.nodes.first { $0.id == eyeID + ".highlight" },
            "\(label) visible \(side) eye keeps its glint")
          #expect(pupil.opacity > 0 && pupil.clips == [aperture.path])
          #expect(glint.opacity > 0 && glint.clips == [aperture.path, pupil.path])
          #expect(pupil.transform == aperture.transform)
          #expect(glint.transform == aperture.transform)
        } else {
          #expect(!frame.nodes.contains {
            $0.id == eyeID + ".pupil" || $0.id == eyeID + ".highlight"
          }, "\(label) has no orphan pupil or glint without a visible aperture")
        }
      }
    }
  }

  @Test
  func blinkOnlyKeepsNeutralWhiskerShapeWhileTheEyesClose() throws {
    let blinkID = try CharacterAnimationID(validating: "neutral-whisker-blink")
    let blinkInput = state([.animationStarted(id: blinkID, animation: .blink)])
    var observedClosedEyes = false

    for time in [0.02, 0.097, 0.2, 0.4] {
      let idlePose = pose(.idle, time: time, reduced: false)
      let blinkPose = pose(blinkInput, time: time, reduced: false)
      let idleFrame = try scene(idlePose)
      let blinkFrame = try scene(blinkPose)

      try assertWhiskerStrokeGeometry(in: idleFrame, context: "idle at \(time)s")
      try assertWhiskerStrokeGeometry(in: blinkFrame, context: "blink at \(time)s")
      let idleShape = whiskerShapeProfile(try node("mouth.whiskers", in: idleFrame))
      let blinkShape = whiskerShapeProfile(try node("mouth.whiskers", in: blinkFrame))
      assertReferenceWhiskerFan(idleShape, context: "idle at \(time)s")
      assertReferenceWhiskerFan(blinkShape, context: "blink at \(time)s")
      #expect(zip(blinkShape.slopes, idleShape.slopes).allSatisfy {
        abs($0.0 - $0.1) < 0.06
      }, "blink-only preserves the same strand-angle profile as idle at \(time)s")
      #expect(zip(blinkShape.curveDeviationRatios, idleShape.curveDeviationRatios).allSatisfy {
        abs($0.0 - $0.1) < 0.02
      }, "blink-only curvature stays close to idle at \(time)s")
      for cheekStart in [0, 3] {
        let idleMiddle = idleShape.arcLengths[cheekStart + 1]
        let blinkMiddle = blinkShape.arcLengths[cheekStart + 1]
        let idleReachRatios = [
          idleShape.arcLengths[cheekStart] / idleMiddle,
          idleShape.arcLengths[cheekStart + 2] / idleMiddle,
        ]
        let blinkReachRatios = [
          blinkShape.arcLengths[cheekStart] / blinkMiddle,
          blinkShape.arcLengths[cheekStart + 2] / blinkMiddle,
        ]
        #expect(zip(blinkReachRatios, idleReachRatios).allSatisfy {
          abs($0.0 - $0.1) < 0.04
        }, "blink-only preserves the distinct strand reaches at \(time)s")
      }

      if blinkPose.eyes.left.blink > 0.99 && blinkPose.eyes.right.blink > 0.99 {
        observedClosedEyes = true
        #expect(try node("eye.left", in: blinkFrame).path
          != node("eye.left", in: idleFrame).path,
          "blink-only pose closes the actual left-eye aperture at \(time)s")
        #expect(!blinkFrame.nodes.contains { $0.id.hasSuffix(".pupil") },
          "closed blink frame hides pupils at \(time)s")
      }
    }

    #expect(observedClosedEyes, "sampled blink-only pose reaches closed eye geometry")
  }

  @Test
  func gratitudeSmileKeepsNonzeroVoiceResponseInClosedLipLine() throws {
    let gratitude = try scene(pose(state([.emotionChanged(.gratitude)]), reduced: true))
    let voiced = try scene(pose(state([
      .emotionChanged(.gratitude), .voiceStarted, .voiceLevelChanged(0.85)
    ]), reduced: true))
    try assertClosedStrokeOnlyMouth(in: gratitude)
    try assertClosedStrokeOnlyMouth(in: voiced)
    #expect(distance(try node("mouth.lips", in: gratitude), try node("mouth.lips", in: voiced)) > 0,
      "voice level must still articulate gratitude through the line contour")
  }

  @Test(arguments: [200.0, 320.0])
  func sadnessRaisesTheNasalCornerAndLetsTheUpperLidSettle(_ size: Double) throws {
    let sadness = try scene(pose(state([.emotionChanged(.sadness)]), reduced: true), width: size)
    let fear = try scene(pose(state([.emotionChanged(.anxietyFear)]), reduced: true), width: size)

    for side in ["left", "right"] {
      let sadProfile = try upperEyeProfile(side, in: sadness)
      let fearProfile = try upperEyeProfile(side, in: fear)
      #expect(sadProfile.innerRise > fearProfile.innerRise + size * 0.0045,
        "\(size)px \(side) eye inner corner should rise with sadness")
      #expect(sadProfile.upperDroop > fearProfile.upperDroop + size * 0.008,
        "\(size)px \(side) eye upper lid should settle with sadness")
    }
  }

  @Test
  func nosePhiltrumLipsAndWhiskersShareExactOpenLineJunctions() throws {
    let rest = try scene(pose(.idle, reduced: true))
    try assertClosedStrokeOnlyMouth(in: rest)
    let nose = try node("nose", in: rest)
    let lips = try node("mouth.lips", in: rest)
    let philtrum = try node("mouth.philtrum", in: rest)
    let whiskers = try node("mouth.whiskers", in: rest)
    #expect(lips.path.commands.count == 3)
    #expect(endpoint(nose.path.commands[2]) == startpoint(philtrum.path.commands.first))
    #expect(endpoint(philtrum.path.commands.last) == endpoint(lips.path.commands[1]))
    let roots = whiskers.path.commands.filter {
      if case .move = $0 { return true }
      return false
    }
    let cubicCount = whiskers.path.commands.filter {
      if case .cubic = $0 { return true }
      return false
    }.count
    #expect(roots.count == 6)
    #expect((24...48).contains(cubicCount), "six independent whiskers retain smooth secondary curves")

    let voiced = try scene(pose(state([.voiceStarted, .voiceLevelChanged(0.8)]), reduced: true))
    try assertClosedStrokeOnlyMouth(in: voiced)
    #expect(try node("mouth.lips", in: voiced).path != lips.path)
  }

  @Test(arguments: [64.0, 128.0, 200.0, 320.0])
  func neutralWhiskersKeepTheReferenceFanAndJoyChangesTheirCurves(
    _ size: Double
  ) throws {
    let neutral = try scene(pose(.idle, reduced: true), width: size)
    let joy = try scene(pose(state([.emotionChanged(.joy)]), reduced: true), width: size)
    try assertClosedStrokeOnlyMouth(in: neutral)
    try assertClosedStrokeOnlyMouth(in: joy)
    #if canImport(CoreGraphics)
      try assertWhiskerStrokeGeometry(in: neutral, context: "\(size)px neutral")
      try assertWhiskerStrokeGeometry(in: joy, context: "\(size)px joy")
    #endif

    let neutralWhiskers = try node("mouth.whiskers", in: neutral)
    let joyWhiskers = try node("mouth.whiskers", in: joy)
    let neutralShape = whiskerShapeProfile(neutralWhiskers)
    let joyShape = whiskerShapeProfile(joyWhiskers)
    assertReferenceWhiskerFan(neutralShape, context: "\(size)px neutral")
    #expect(joyWhiskers.path != neutralWhiskers.path,
      "\(size)px joy expression changes the six-strand curve geometry")
    #expect(joyShape.roots.count == 6 && joyShape.tips.count == 6)
  }

  #if canImport(CoreGraphics)
    @Test(arguments: [64.0, 128.0, 200.0, 320.0])
    func ordinaryWhiskersStayExtendedAndOutwardThroughTimedPoses(_ size: Double) throws {
      let ordinary: [(String, CharacterState)] = [
        ("idle", .idle),
        ("interest", state([.emotionChanged(.interest)])),
        ("calm", state([.emotionChanged(.calmTrust)])),
        ("gratitude", state([.emotionChanged(.gratitude)])),
        ("joy", state([.emotionChanged(.joy)])),
        ("affection", state([.emotionChanged(.affection)])),
        ("surprise", state([.emotionChanged(.surprise)])),
        ("chat", state([.chatStarted])),
        ("listening", state([.listeningStarted, .listeningLevelChanged(0.82)])),
        ("voice", state([.voiceStarted, .voiceLevelChanged(0.82)])),
      ]
      let times = [0.0, 0.073, 0.143, 0.286, 0.429]
      var firstPathByState: [String: CharacterVectorPath] = [:]
      var variedStates: Set<String> = []

      for (label, input) in ordinary {
        for time in times {
          let sampledPose = semiPose(input, time: time, reduced: false)
          let frame = try scene(sampledPose, width: size)
          try assertClosedStrokeOnlyMouth(in: frame)
          try CharacterSceneValidation.validate(frame)
          try assertWhiskerStrokeGeometry(in: frame, context: "\(size)px \(label) at \(time)s")
          try assertExtendedWhiskerReach(in: frame, context: "\(size)px \(label) at \(time)s")

          let whiskers = try node("mouth.whiskers", in: frame)
          let profile = whiskerShapeProfile(whiskers)
          assertReferenceWhiskerFan(
            profile, context: "\(size)px \(label) at \(time)s",
            middleSlopeLimit: label == "idle" ? 0.20 : nil)

          if let firstPath = firstPathByState[label] {
            if whiskers.path != firstPath { variedStates.insert(label) }
          } else {
            firstPathByState[label] = whiskers.path
          }
        }
      }

      for label in ["idle", "chat", "listening", "voice"] {
        #expect(variedStates.contains(label),
          "\(size)px \(label) motion changes the extended whisker fan over time")
      }

      let reducedFrames = try times.map { time in
        try scene(semiPose(.idle, time: time, reduced: true), width: size)
      }
      let reducedIsStatic = reducedFrames.dropFirst().allSatisfy { frame in
        guard let firstWhiskers = reducedFrames.first?.nodes.first(where: { $0.id == "mouth.whiskers" }),
          let whiskers = frame.nodes.first(where: { $0.id == "mouth.whiskers" }) else { return false }
        return whiskers.path == firstWhiskers.path && whiskers.transform == firstWhiskers.transform
      }
      #expect(reducedIsStatic, "\(size)px Reduce Motion freezes the resting fan")
    }

    @Test(arguments: [64.0, 128.0, 200.0, 320.0])
    func expressiveWhiskerCuesRemainSafeWhenTheyCurlOrSag(_ size: Double) throws {
      let recoilID = try CharacterAnimationID(validating: "expressive-whisker-recoil")
      let bounceID = try CharacterAnimationID(validating: "expressive-whisker-impact")
      let samples: [(String, CharacterState)] = [
        ("anxiety", state([.emotionChanged(.anxietyFear)])),
        ("fatigue", state([.emotionChanged(.fatigueBurden)])),
        ("recoil", state([.animationStarted(id: recoilID, animation: .recoil)])),
        ("impact", state([.animationStarted(id: bounceID, animation: .bounce)])),
      ]

      for (label, input) in samples {
        for time in [0.073, 0.143, 0.286, 0.429] {
          let frame = try scene(semiPose(input, time: time, reduced: false), width: size)
          try assertClosedStrokeOnlyMouth(in: frame)
          try CharacterSceneValidation.validate(frame)
          try assertWhiskerStrokeGeometry(in: frame,
            context: "\(size)px expressive \(label) at \(time)s")
        }
      }
    }

    @Test(arguments: [64.0, 128.0, 200.0, 320.0])
    func staticEmotionWhiskersStayInViewportAndClearEyeAndPaperInk(_ size: Double) throws {
      let inputs: [(String, CharacterState)] = [("idle", .idle)]
        + CharacterEmotion.allCases.map { ($0.rawValue, state([.emotionChanged($0)])) }

      for (label, input) in inputs {
        let frame = try scene(pose(input, time: 0.8, reduced: true), width: size)
        try assertClosedStrokeOnlyMouth(in: frame)
        try assertWhiskerStrokeGeometry(in: frame, context: "\(size)px reduced \(label)")
      }
    }

    @Test(arguments: [64.0, 128.0, 200.0, 320.0])
    func motionWhiskerSweepsStayInViewportAndClearEyeAndPaperInk(_ size: Double) throws {
      let times = [0.0, 0.073, 0.143, 0.286, 0.429]
      for (label, input) in try whiskerMotionStates() {
        for time in times {
          let animated = try scene(pose(input, time: time, reduced: false), width: size)
          try assertClosedStrokeOnlyMouth(in: animated)
          try assertWhiskerStrokeGeometry(
            in: animated, context: "\(size)px animated \(label) at \(time)s")
        }

        let stillA = try scene(pose(input, time: 0, reduced: true), width: size)
        try assertWhiskerStrokeGeometry(in: stillA, context: "\(size)px reduced \(label)")
        #expect(pose(input, time: 0, reduced: true).detailMotion == .still)
        #expect(pose(input, time: 0.8, reduced: true).detailMotion == .still)
      }
    }

    @Test
    func sampledWhiskerMotionIsContinuousAndReducedMotionFreezesTheShape() throws {
      let input = state([.emotionChanged(.anxietyFear)])
      let reducedTimes = [0.0, 0.09, 0.22, 0.41]
      let reducedPaths = try reducedTimes.map { time in
        let pose = pose(input, time: time, reduced: true)
        #expect(pose.detailMotion == .still)
        return try node("mouth.whiskers", in: scene(pose)).path
      }
      #expect(reducedPaths.dropFirst().allSatisfy { $0 == reducedPaths[0] })

      let motionTimes = (0...48).map { 0.10 + Double($0) / 240 }
      let poses = motionTimes.map { pose(input, time: $0, reduced: false) }
      #expect(poses.allSatisfy { $0.detailMotion.amount > 0 })
      let whiskers = try poses.map { try node("mouth.whiskers", in: scene($0)) }
      var largestStep = 0.0
      var largestSpan = 0.0
      for left in whiskers.indices {
        largestSpan = max(largestSpan, distance(whiskers[0], whiskers[left]))
        if left + 1 < whiskers.endIndex {
          largestStep = max(largestStep, distance(whiskers[left], whiskers[left + 1]))
        }
      }
      #expect(largestSpan > 0.1, "animated detail motion changes the sampled whisker shape")
      #expect(largestStep < largestSpan * 0.35,
        "adjacent 240 Hz detail samples remain continuous, step=\(largestStep), span=\(largestSpan)")
    }
  #endif

  @Test
  func filledAndOutlineTreatmentsKeepTheSameClosedLinesAndRespectColorRoles() throws {
    let input = state([.emotionChanged(.joy)])
    let sharedPose = pose(input, reduced: true)
    let colors = direction.style.partColors.replacing(
      mouth: try CharacterColor(red: 0.12, green: 0.70, blue: 0.92),
      mouthDetail: try CharacterColor(red: 0.88, green: 0.78, blue: 0.26),
      tongue: try CharacterColor(red: 0.92, green: 0.20, blue: 0.42),
      outline: try CharacterColor(red: 0.03, green: 0.04, blue: 0.08))
    let filledDirection = direction.replacingPartColors(colors)
      .replacingFaceTreatment(mouth: .filled)
    let outlineDirection = direction.replacingPartColors(colors)
      .replacingFaceTreatment(mouth: .outline)
    let filled = try scene(sharedPose, direction: filledDirection)
    let outline = try scene(sharedPose, direction: outlineDirection)
    try assertClosedStrokeOnlyMouth(in: filled)
    try assertClosedStrokeOnlyMouth(in: outline)
    let filledLips = try node("mouth.lips", in: filled)
    let outlineLips = try node("mouth.lips", in: outline)

    #expect(filledLips.path == outlineLips.path)
    #expect(filledLips.stroke == colors.mouth)
    #expect(outlineLips.stroke == colors.mouth)
    #expect(try node("mouth.philtrum", in: filled).stroke == colors.mouth)
    #expect(try node("mouth.whiskers", in: filled).stroke == colors.mouthDetail)
    #expect(filled.nodes.filter { $0.id.hasPrefix("mouth.") }.map(\.path)
      == outline.nodes.filter { $0.id.hasPrefix("mouth.") }.map(\.path))
    #expect(try node("mouth.whiskers", in: outline).stroke == colors.mouthDetail)
    #expect(try node("mouth.whiskers", in: filled).path
      == node("mouth.whiskers", in: outline).path)
  }

  @Test
  func speakingContourChangesWithoutFrameSizedJumpsAndDoesNotChangeState() throws {
    let input = state([.chatStarted])
    let before = ReactiveCharacter.inspect(state: input)
    let frames = try (0...70).map { index in
      try scene(pose(input, time: 0.04 + Double(index) * 0.005))
    }
    for frame in frames { try assertClosedStrokeOnlyMouth(in: frame) }
    let lips = try frames.map { try node("mouth.lips", in: $0) }
    var largestStep = 0.0
    var largestSpan = 0.0
    for left in lips.indices {
      for right in (left + 1)..<lips.endIndex {
        largestSpan = max(largestSpan, distance(lips[left], lips[right]))
      }
      if left + 1 < lips.endIndex {
        largestStep = max(largestStep, distance(lips[left], lips[left + 1]))
      }
    }
    #expect(largestSpan > 1.0)
    #expect(largestStep < largestSpan * 0.20)
    #expect(ReactiveCharacter.inspect(state: input) == before)
  }

  @Test(arguments: [0.2, 0.8])
  func blinkingDoesNotAttenuateVoiceMouth(_ level: Double) throws {
    var source = pose(state([.voiceStarted, .voiceLevelChanged(level)]), reduced: true)
    source.detailMotion = .sample(time: 0.073, impulse: 0.8, amount: 0.9)
    func closed(_ eye: CharacterEyePose) -> CharacterEyePose {
      .init(centerX: eye.centerX, centerY: eye.centerY, width: eye.width,
        height: eye.height, angle: eye.angle, unblinkedWidth: eye.unblinkedWidth,
        unblinkedHeight: eye.unblinkedHeight, blink: 1)
    }
    let blinked = CharacterPose(
      eyes: .init(left: closed(source.eyes.left), right: closed(source.eyes.right)),
      nearTrail: source.nearTrail, farTrail: source.farTrail,
      nearTrailOpacity: source.nearTrailOpacity, farTrailOpacity: source.farTrailOpacity,
      noseOffsetX: source.noseOffsetX, mouth: source.mouth, surface: source.surface,
      writingPhase: source.writingPhase, writingMotionPhase: source.writingMotionPhase,
      writingProgress: source.writingProgress, writingVisible: source.writingVisible,
      writingOpacity: source.writingOpacity, accents: source.accents,
      motionEnergy: source.motionEnergy, eyeContours: source.eyeContours,
      brows: source.brows, faceDynamics: source.faceDynamics,
      detailMotion: source.detailMotion)
    #expect(blinked.detailMotion == source.detailMotion)
    let openEyes = try scene(source)
    let closedEyes = try scene(blinked)
    try assertClosedStrokeOnlyMouth(in: openEyes)
    try assertClosedStrokeOnlyMouth(in: closedEyes)
    #expect(try eye("left", in: openEyes).path != eye("left", in: closedEyes).path)
    #expect(openEyes.nodes.filter { $0.id.hasPrefix("mouth.") }
      == closedEyes.nodes.filter { $0.id.hasPrefix("mouth.") })
  }

  @Test
  func reducedMotionIsStaticAndExtremeMotionsStayInsideViewportAtReviewSizes() throws {
    for emotion in [CharacterEmotion.joy, .gratitude, .sadness, .anxietyFear, .calmTrust, .fatigueBurden] {
      let input = state([.emotionChanged(emotion)])
      let early = try scene(pose(input, time: 0.2, reduced: true))
      let late = try scene(pose(input, time: 9.2, reduced: true))
      try assertClosedStrokeOnlyMouth(in: early)
      try assertClosedStrokeOnlyMouth(in: late)
      #expect(early == late, "\(emotion) reduced-motion geometry")
    }

    for animation in CharacterAnimation.allCases {
      let id = try CharacterAnimationID(validating: "quality-\(animation.rawValue)")
      let input = state([.animationStarted(id: id, animation: animation)])
      for size in [64.0, 128, 200, 320] {
        for time in [0.0, 0.12, 0.4, 0.8, animation.duration + 0.15] {
          let frame = try scene(pose(input, time: time), width: size)
          try CharacterSceneValidation.validate(frame)
          try assertClosedStrokeOnlyMouth(in: frame)
          for part in frame.nodes
          where part.image == nil && !part.path.commands.isEmpty
            && !part.id.hasPrefix("mouth.whiskers")
          {
            for point in points(part) {
              #expect((0...frame.width).contains(point.x),
                "\(animation) at \(size)px: \(part.id) x=\(point.x)")
              #expect((0...frame.height).contains(point.y),
                "\(animation) at \(size)px: \(part.id) y=\(point.y)")
            }
          }
        }
      }
    }
  }

  private func endpoint(_ command: CharacterVectorCommand?) -> CharacterVectorPoint? {
    guard let command else { return nil }
    return switch command {
    case .move(let point), .line(let point): point
    case .quad(_, let point), .cubic(_, _, let point): point
    case .close: nil
    }
  }

  private func startpoint(_ command: CharacterVectorCommand?) -> CharacterVectorPoint? {
    guard let command else { return nil }
    if case .move(let point) = command { return point }
    return nil
  }
}

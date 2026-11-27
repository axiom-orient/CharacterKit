import Foundation
import Testing
@testable import ReactiveCharacterKit

extension CharacterFeltCatTransition.Route {
  static let actionRoutes: [Self] = [.left, .right, .stretch, .bellyUp, .puffedRight]

  func testCue(style: CharacterFullBodyCatStyle = .felt) -> CharacterFullBodyCatAppearance {
    switch self {
    case .left: .init(action: .walk, style: style, walkDirection: .left)
    case .right: .init(action: .walk, style: style, walkDirection: .right)
    case .stretch: .init(action: .stretch, style: style)
    case .bellyUp: .init(action: .showBelly, style: style)
    case .puffedRight: .init(action: .startle, style: style, puffDirection: .right)
    default: .init(pose: destination, style: style)
    }
  }
}

struct CharacterFullBodyCatTests {
  @Test
  func aBodyCueReplaysExpiresAndCancelsIndependentlyOfExpression() {
    let first = CharacterFullBodyCatAppearance(pose: .loaf, action: .wave, actionTrigger: 1)
    var playback = CharacterFullBodyCatPlayback(appearance: first, at: 10)
    let mid = playback.sample(appearance: first, at: 10.63, reduceMotion: false)
    #expect(mid.pose == .waving)
    #expect(abs(mid.pawAngle) > 0.01)
    playback.update(appearance: first, at: 10.63)
    #expect(playback.sample(appearance: first, at: 10.63, reduceMotion: false) == mid)
    #expect(playback.sample(appearance: first, at: 20, reduceMotion: false).pose == .loaf)

    let repeatWave = CharacterFullBodyCatAppearance(pose: .loaf, action: .wave, actionTrigger: 2)
    #expect(playback.sample(appearance: repeatWave, at: 20, reduceMotion: false).pose == .loaf)
    playback.update(appearance: repeatWave, at: 20)
    #expect(playback.deadline == 20 + CharacterFullBodyCatAction.wave.duration)
    #expect(playback.sample(appearance: repeatWave, at: 20.6, reduceMotion: true)
      == .init(pose: .waving, usesGestureTransform: true))
    #expect(playback.sample(appearance: repeatWave, at: 21.41, reduceMotion: true) == .init(pose: .loaf))

    let cancel = CharacterFullBodyCatAppearance(pose: .standing)
    playback.update(appearance: cancel, at: 20.7)
    #expect(playback.deadline == nil)
    #expect(playback.sample(appearance: cancel, at: 20.7, reduceMotion: true) == .init(pose: .standing))
  }

  @Test(arguments: CharacterFullBodyCatStyle.allCases, CharacterFullBodyCatPose.allCases)
  func eachStyleExportsItsOwnArtwork(
    _ style: CharacterFullBodyCatStyle, _ restingPose: CharacterFullBodyCatPose
  ) throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, fullBodyCat: .init(pose: restingPose, style: style),
      width: 200, height: 140, reduceMotion: true)
    let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
    if style == .felt {
      #expect(body.image?.asset == CharacterFullBodyCatArtwork.resolve(restingPose).body)
      #expect(body.image?.bounds.width == 256)
    } else {
      #expect(scene.nodes.allSatisfy { $0.image == nil })
      #expect(!body.path.commands.isEmpty)
      let pigment = try #require(scene.nodes.first { $0.id == "full-body-cat.wax.body" })
      #expect(pigment.clips == [body.path])
      #expect(pigment.transform == body.transform)
    }
    #expect(scene.nodes.allSatisfy { $0.opacity == 1 })
    let svg = try CharacterSVGRenderer.render(scene)
    #expect(svg.contains("data:image/png;base64,") == (style == .felt))
    #expect(svg.contains("full-body-cat.body"))
    if restingPose == .rear {
      #expect(scene.nodes.allSatisfy { $0.layer != .features })
    }
  }

  @Test(arguments: CharacterFullBodyCatStyle.allCases)
  func fourBeatGaitLiftsOneFootAtATimeAndRespectsReduceMotion(_ style: CharacterFullBodyCatStyle) throws {
    var gait = CharacterFullBodyCatMotion(pose: .right, walkPhase: 0.12, walkStrength: 1)
    let footfalls: [CharacterFullBodyCatLeg] = [.farHind, .farFront, .nearHind, .nearFront]
    for (index, foot) in footfalls.enumerated() {
      gait.walkPhase = 0.12 + Double(index) * 0.25
      #expect(gait.step(for: foot).lift > 13)
      for grounded in footfalls where grounded != foot {
        #expect(gait.step(for: grounded).lift == 0)
      }
    }
    let left = CharacterFullBodyCatAppearance(pose: .left, action: .walk, style: style)
    let reduced = CharacterFullBodyCatMotion.sample(
      appearance: left, elapsed: 0.8, actionElapsed: 0.8, reduceMotion: true)
    #expect(reduced.pose == .left)
    #expect(reduced.walkPhase == nil)
    #expect(reduced.step(for: .nearFront) == .planted)

    let neutral = ReactiveCharacter.pose(state: .idle, elapsed: 0.6, reduceMotion: true, projection: .flat)
    let first = try CharacterSceneBuilder.scene(
      pose: neutral, fullBodyCat: left, width: 200, height: 200, actionElapsed: 0.90)
    let second = try CharacterSceneBuilder.scene(
      pose: neutral, fullBodyCat: left, width: 200, height: 200, actionElapsed: 1.12)
    #if os(iOS) || os(macOS)
      if style == .felt {
        let firstSkin = try #require(first.nodes.first { $0.id == "full-body-cat.body" }?.image?.feltWalk)
        let secondSkin = try #require(second.nodes.first { $0.id == "full-body-cat.body" }?.image?.feltWalk)
        #expect(firstSkin != secondSkin)
        return
      }
    #endif
    let firstLegs = first.nodes.filter { $0.id.hasPrefix("full-body-cat.leg.") }
    let secondLegs = second.nodes.filter { $0.id.hasPrefix("full-body-cat.leg.") }
    #expect(firstLegs.count == 4)
    #expect(secondLegs.count == 4)
    #expect(firstLegs != secondLegs)
    #expect(firstLegs.allSatisfy { ($0.image != nil) == (style == .felt) })
  }

  @Test
  func hopAnticipatesTucksAndReturnsToTheSelectedPose() throws {
    let cue = CharacterFullBodyCatAppearance(pose: .left, action: .hop)
    func sample(_ phase: Double, reduceMotion: Bool = false) -> CharacterFullBodyCatMotion {
      .sample(
        appearance: cue, elapsed: 0, actionElapsed: phase * CharacterFullBodyCatAction.hop.duration,
        reduceMotion: reduceMotion)
    }
    let beginning = sample(0)
    let crouch = sample(0.15)
    let airtime = sample(0.485)
    let landing = sample(0.80)
    let end = sample(1)
    #expect(beginning.bodyOffsetY == 0)
    #expect(crouch.breath < -0.07 && crouch.bodyWidth > 0.04)
    #expect(crouch.bodyOffsetY == 0)
    #expect(airtime.pose == .left && airtime.bodyOffsetY < -0.11)
    #expect(airtime.step(for: .nearFront).lift > airtime.step(for: .farFront).lift)
    #expect(airtime.step(for: .nearFront).offsetX < airtime.step(for: .nearHind).offsetX)
    #expect(landing.bodyOffsetY == 0 && landing.breath < -0.06)
    #expect(end == .init(pose: .left))
    #expect(sample(0.485, reduceMotion: true) == .init(pose: .left, usesGestureTransform: true))

    let fromBelly = CharacterFullBodyCatAppearance(pose: .bellyUp, action: .hop)
    let middle = CharacterFullBodyCatMotion.sample(
      appearance: fromBelly, elapsed: 0, actionElapsed: 0.6, reduceMotion: false)
    let finished = CharacterFullBodyCatMotion.sample(
      appearance: fromBelly, elapsed: 0, actionElapsed: try #require(fromBelly.actionDuration), reduceMotion: false)
    #expect(middle.pose == .standing)
    #expect(finished.pose == .bellyUp)
  }

  @Test(arguments: CharacterFeltCatTransition.Route.actionRoutes)
  func standingFeltActionsEnterAndReturnThroughTheRegisteredFrames(
    _ route: CharacterFeltCatTransition.Route
  ) throws {
    let cue = route.testCue()
    let action = try #require(cue.action)
    func sample(_ time: Double, reduceMotion: Bool = false) -> CharacterFullBodyCatMotion {
      .sample(appearance: cue, elapsed: 0, actionElapsed: time, reduceMotion: reduceMotion)
    }
    let entry = (0...60).compactMap { frame in
      sample(route.entryDuration * Double(frame) / 61).transition
    }
    let recovery = (0...60).compactMap { frame in
      sample(action.duration - route.returnDuration * Double(61 - frame) / 62).transition
    }
    #expect(entry.allSatisfy { $0.route == route })
    #expect(recovery.allSatisfy { $0.route == route })
    let frames = entry.map(\.frameIndex)
    let returningFrames = recovery.map(\.frameIndex)
    #expect(frames == frames.sorted())
    #expect(returningFrames == returningFrames.sorted(by: >))
    #expect(Set(frames) == Set(0...route.intervals))
    #expect(Set(returningFrames) == Set(0...route.intervals))

    let performed = sample(action.duration / 2)
    #expect(performed.pose == route.destination)
    #expect(performed.transition == nil)
    #expect(performed.hasLegMotion == (action == .walk))
    #expect(sample(action.duration).pose == .standing)
    #expect(sample(action.duration / 2, reduceMotion: true).transition == nil)
    #expect(sample(action.duration / 2, reduceMotion: true).pose == route.destination)
    let crayon = CharacterFullBodyCatMotion.sample(
      appearance: route.testCue(style: .crayon), elapsed: 0,
      actionElapsed: route.entryDuration / 2, reduceMotion: false)
    #expect(crayon.transition == nil)
  }

  @Test
  func feltWarmupUsesTheFirstAuthoredFrameOfEachRoute() {
    let routes = CharacterFeltCatTransition.Route.allCases
    let firstFrames = routes.compactMap { route in
      let routePrefix = CharacterFeltCatTransition.assetNamePrefix + route.assetKey + "-"
      return (1..<route.intervals).lazy.compactMap { index in
        CharacterFeltCatTransition(route: route, progress: Double(index) / Double(route.intervals)).frameAsset
      }.first { $0.name.hasPrefix(routePrefix) }
    }
    #expect(firstFrames.count == routes.count)
    #expect(CharacterFeltCatTransition.entryAssets == firstFrames)
  }

  @Test(arguments: CharacterFeltCatTransition.Route.allCases)
  func interruptingAPoseTransitionReversesFromTheCurrentlyVisibleFrame(
    _ route: CharacterFeltCatTransition.Route
  ) throws {
    let stand = CharacterFullBodyCatAppearance()
    let target = CharacterFullBodyCatAppearance(
      pose: route.destination, puffDirection: route.puffDirection ?? .left)
    var timeline = CharacterFullBodyCatPlayback(appearance: stand, at: 0)
    let first = timeline.sample(appearance: target, at: 1, reduceMotion: false)
    #expect(first.pose == .standing)
    timeline.update(appearance: target, at: 1)

    let halfTime = 1 + route.entryDuration * 0.5
    let forward = try #require(timeline.sample(
      appearance: target, at: halfTime, reduceMotion: false).transition)
    #expect(forward.frameAsset != nil)
    timeline.update(appearance: stand, at: halfTime)
    let switched = try #require(timeline.sample(
      appearance: stand, at: halfTime, reduceMotion: false).transition)
    #expect(switched.frameIndex == forward.frameIndex)
    let backing = try #require(timeline.sample(
      appearance: stand, at: halfTime + 0.07, reduceMotion: false).transition)
    #expect(backing.frameIndex < forward.frameIndex)
    let rest = timeline.sample(appearance: stand, at: halfTime + route.returnDuration, reduceMotion: false)
    #expect(rest.transition == nil)
    #expect(rest.pose == .standing)
  }

  @Test
  func switchingBetweenNonstandingPosesProcedurallyReturnsThroughStanding() throws {
    let loaf = CharacterFullBodyCatAppearance(pose: .loaf)
    let upright = CharacterFullBodyCatAppearance(pose: .upright)
    var timeline = CharacterFullBodyCatPlayback(appearance: loaf, at: 0)
    let first = timeline.sample(appearance: upright, at: 1, reduceMotion: false)
    #expect(first.pose == .loaf)
    timeline.update(appearance: upright, at: 1)

    let transitions = (0..<120).compactMap { frame in
      timeline.sample(appearance: upright, at: 1 + Double(frame) / 60, reduceMotion: false).transition
    }
    #expect(transitions.first?.route == .loaf)
    #expect(transitions.first?.endpoint == .loaf)
    #expect(transitions.last?.route == .upright)
    #expect(Set(transitions.map(\.route)) == [.loaf, .upright])
    let outgoing = transitions.filter { $0.route == .loaf }.map(\.frameIndex)
    let incoming = transitions.filter { $0.route == .upright }.map(\.frameIndex)
    #expect(outgoing.contains(0) || incoming.contains(0))
    #expect(outgoing == outgoing.sorted(by: >))
    #expect(incoming == incoming.sorted())
    let rest = timeline.sample(appearance: upright, at: 3, reduceMotion: false)
    #expect(rest.transition == nil)
    #expect(rest.pose == .upright)
  }

  @Test
  func switchingPuffDirectionTurnsThroughStandingAndStartleKeepsTheSelectedRest() throws {
    let left = CharacterFullBodyCatAppearance(pose: .puffed)
    let right = CharacterFullBodyCatAppearance(pose: .puffed, puffDirection: .right)
    var playback = CharacterFullBodyCatPlayback(appearance: left, at: 0)
    let start = 1.0
    let turn = start + CharacterFeltCatTransition.Route.puffed.returnDuration
    playback.update(appearance: right, at: start)

    let departing = playback.sample(appearance: right, at: start + 0.1, reduceMotion: false)
    #expect(departing.transition?.route == .puffed)
    let passing = playback.sample(appearance: right, at: turn, reduceMotion: false)
    #expect(passing.pose == .standing)
    let arriving = playback.sample(appearance: right, at: turn + 0.1, reduceMotion: false)
    #expect(arriving.transition?.route == .puffedRight)
    let settled = playback.sample(appearance: right, at: turn + 1, reduceMotion: false)
    #expect(settled.transition == nil && settled.mirrorsPuff)

    let cue = CharacterFullBodyCatAppearance(pose: .loaf, action: .startle, puffDirection: .right)
    let duration = try #require(cue.actionDuration)
    #expect(duration > CharacterFullBodyCatAction.startle.duration)
    let performed = CharacterFullBodyCatMotion.sample(
      appearance: cue, elapsed: 0, actionElapsed: duration / 2, reduceMotion: false)
    #expect(performed.pose == .puffed && performed.mirrorsPuff)
    let finished = CharacterFullBodyCatMotion.sample(
      appearance: cue, elapsed: 0, actionElapsed: duration, reduceMotion: false)
    #expect(finished.pose == .loaf && finished.transition == nil)
  }

  @Test
  func rightPuffSharesTheRightTurnBeforeItArches() {
    let rightTurn = CharacterFeltCatTransition.Route.right
    let rightPuff = CharacterFeltCatTransition.Route.puffedRight
    for frame in 1..<rightTurn.intervals {
      let turn = CharacterFeltCatTransition(
        route: rightTurn, progress: Double(frame) / Double(rightTurn.intervals))
      let puff = CharacterFeltCatTransition(
        route: rightPuff, progress: Double(frame) / Double(rightPuff.intervals))
      #expect(puff.frameAsset == turn.frameAsset)
      #expect(puff.face?.left?.center == turn.face?.left?.center)
      #expect(puff.face?.right?.center == turn.face?.right?.center)
      #expect(puff.face?.muzzle?.junction == turn.face?.muzzle?.junction)
    }
  }

  @Test(arguments: CharacterFullBodyCatStyle.allCases)
  func eachEmotionProducesDistinctStillFaceGeometry(_ style: CharacterFullBodyCatStyle) throws {
    var faces: [[CharacterSceneNode]] = []
    for emotion in CharacterEmotion.allCases {
      let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true, projection: .flat)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, fullBodyCat: .init(style: style), width: 92, height: 92, reduceMotion: true)
      let features = scene.nodes.filter { $0.layer == .features }
      #expect(features.count >= 4)
      #expect(!faces.contains(features), "Duplicated face for \(emotion)")
      faces.append(features)
    }
  }

  @Test(arguments: [.standing, .waving, .loaf, .upright, .bellyUp, .stretch] as [CharacterFullBodyCatPose])
  func feltCuriosityKeepsItsAsymmetryWithTwoBrows(_ restingPose: CharacterFullBodyCatPose) throws {
    let scene = try feltEmotionScene(.interest, restingPose: restingPose)
    let brows = feltBrows(in: scene)
    let left = try #require(brows.first { $0.id == "full-body-cat.brow.left" })
    let right = try #require(brows.first { $0.id == "full-body-cat.brow.right" })
    let leftEnds = try browEndpoints(left)
    let rightEnds = try browEndpoints(right)
    #expect(brows.count == 2)
    #expect(scene.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") }.count == 2)
    #expect(right.lineWidth > 0 && right.lineWidth < left.lineWidth)
    #expect(right.opacity > 0)
    #expect(hypot(rightEnds.end.x - rightEnds.start.x, rightEnds.end.y - rightEnds.start.y)
      < hypot(leftEnds.end.x - leftEnds.start.x, leftEnds.end.y - leftEnds.start.y))
    if restingPose == .standing {
      let leftY = (leftEnds.start.y + leftEnds.end.y) / 2
      let rightY = (rightEnds.start.y + rightEnds.end.y) / 2
      #expect(rightY > leftY)
    }
  }

  @Test(arguments: CharacterFullBodyCatPose.allCases)
  func feltBrowsStayExpressionAndViewDependent(_ restingPose: CharacterFullBodyCatPose) throws {
    let neutral = try feltEmotionScene(nil, restingPose: restingPose)
    let worry = try feltEmotionScene(.anxietyFear, restingPose: restingPose)
    let eyeCount = worry.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") }.count
    #expect(feltBrows(in: neutral).isEmpty)
    #expect(feltBrows(in: worry).count == (eyeCount == 2 ? 2 : 0))
    if eyeCount < 2 {
      let curiosity = try feltEmotionScene(.interest, restingPose: restingPose)
      #expect(feltBrows(in: curiosity).isEmpty)
    }
  }

  @Test(arguments: [CharacterFeltCatTransition.Route.left, .right])
  func feltBrowsFadeIntoEachSideView(_ route: CharacterFeltCatTransition.Route) throws {
    let pose = feltExpression(.interest)
    let appearance = CharacterFullBodyCatAppearance(pose: route.destination, style: .felt)
    let strengths = try (0...route.intervals).map { key in
      let transition = CharacterFeltCatTransition(
        route: route, progress: Double(key) / Double(route.intervals))
      let motion = CharacterFullBodyCatMotion(pose: transition.endpoint, transition: transition)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, fullBodyCat: appearance, motion: motion, width: 258, height: 258, environment: .init())
      return feltBrows(in: scene).reduce(0.0) { $0 + $1.lineWidth * $1.opacity }
    }
    let starting = try #require(strengths.first)
    #expect(starting > 0)
    #expect(strengths.contains { $0 > 0 && $0 < starting / 2 })
    #expect(strengths.last == 0)
    #expect(zip(strengths, strengths.dropFirst()).allSatisfy { before, after in after <= before + 1e-9 })
  }

  private func feltExpression(_ emotion: CharacterEmotion?) -> CharacterPose {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
    return ReactiveCharacter.pose(
      state: state, elapsed: 0, reduceMotion: true, projection: .flat, motionProfile: .expressive)
  }

  private func feltEmotionScene(
    _ emotion: CharacterEmotion?, restingPose: CharacterFullBodyCatPose
  ) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: feltExpression(emotion), fullBodyCat: .init(pose: restingPose, style: .felt),
      width: 258, height: 258, reduceMotion: true)
  }

  private func feltBrows(in scene: CharacterScene) -> [CharacterSceneNode] {
    scene.nodes.filter { $0.id.hasPrefix("full-body-cat.brow.") }
  }

  private func browEndpoints(_ brow: CharacterSceneNode) throws -> (
    start: CharacterVectorPoint, end: CharacterVectorPoint
  ) {
    let start = brow.path.commands.first.flatMap { command -> CharacterVectorPoint? in
      if case .move(let point) = command { return point }
      return nil
    }
    let end = brow.path.commands.last.flatMap { command -> CharacterVectorPoint? in
      if case .quad(_, let point) = command { return point }
      return nil
    }
    return (try #require(start), try #require(end))
  }

  @Test(arguments: CharacterFullBodyCatStyle.allCases)
  func smileBlinkAndSpeechKeepTheRaisedPawIndependent(_ style: CharacterFullBodyCatStyle) throws {
    var state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    state = ReactiveCharacter.reduce(state: state, event: .voiceStarted).state
    let action = CharacterFullBodyCatAppearance(action: .wave, style: style)
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.39, projection: .flat)
    let open = pose.applyingSpeechArticulation(.wide)
    let closed = pose.applyingSpeechArticulation(.closed)
    let openScene = try CharacterSceneBuilder.scene(
      pose: open, fullBodyCat: action, width: 210, height: 210, elapsed: 0.39)
    let closedScene = try CharacterSceneBuilder.scene(
      pose: closed, fullBodyCat: action, width: 210, height: 210, elapsed: 0.39)
    let nextPaw = try CharacterSceneBuilder.scene(
      pose: open, fullBodyCat: action, width: 210, height: 210, elapsed: 0.50)
    let paw = try #require(openScene.nodes.first { $0.id == "full-body-cat.paw.wave" })
    #expect(paw == closedScene.nodes.first { $0.id == paw.id })
    #expect(paw != nextPaw.nodes.first { $0.id == paw.id })
    let eyes = openScene.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") }
    #expect(eyes.count == 2)
    #expect(eyes == closedScene.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") })
    #expect(openScene.nodes.filter { $0.id.hasPrefix("full-body-cat.mouth") }
      != closedScene.nodes.filter { $0.id.hasPrefix("full-body-cat.mouth") })

    let blinking = ReactiveCharacter.reduce(state: state, event: .animationStarted(
      id: CharacterAnimationID(UUID()), animation: .blink)).state
    let blinkPose = ReactiveCharacter.pose(
      state: blinking, elapsed: 0.39, animationElapsed: 0.10, projection: .flat)
      .applyingSpeechArticulation(.wide)
    let blinkScene = try CharacterSceneBuilder.scene(
      pose: blinkPose, fullBodyCat: action, width: 210, height: 210, elapsed: 0.39)
    #expect(paw == blinkScene.nodes.first { $0.id == paw.id })
    #expect(eyes != blinkScene.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") })
  }
}

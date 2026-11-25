import Testing
@testable import ReactiveCharacterKit

struct CharacterFullBodyCatHandoffTests {
  @Test(arguments: CharacterFullBodyCatAction.allCases)
  func inPlaceFeltActionsEaseTheBodyAndExpressionAtTheirEdges(_ action: CharacterFullBodyCatAction) throws {
    let rest: CharacterFullBodyCatPose = switch action {
    case .wave: .waving
    case .walk: .right
    case .stretch: .stretch
    case .startle: .puffed
    case .showBelly: .bellyUp
    case .hop: .left
    }
    let appearance = CharacterFullBodyCatAppearance(pose: rest, action: action)
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: false, projection: .flat)
      .replacingSurface(.init(offsetX: 0.08, offsetY: -0.04, scaleX: 0.95, scaleY: 1.03, angle: 0.12))

    func body(at actionTime: Double) throws -> CharacterSceneTransform {
      let motion = CharacterFullBodyCatMotion.sample(
        appearance: appearance, elapsed: 0.5, actionElapsed: actionTime, reduceMotion: false)
      let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: appearance,
        motion: motion, width: 160, height: 160, environment: .init())
      return try #require(scene.nodes.first { $0.id == "full-body-cat.body" }).transform
    }

    for phase in [0, 0.09, 0.88, 0.92, 0.94, 1] {
      let boundary = phase * action.duration
      let before = try body(at: boundary - 0.00001)
      let after = try body(at: boundary + 0.00001)
      for point in [CharacterVectorPoint(x: 0, y: 0), .init(x: 256, y: 256)] {
        let dx = (after.a - before.a) * point.x + (after.c - before.c) * point.y + after.tx - before.tx
        let dy = (after.b - before.b) * point.x + (after.d - before.d) * point.y + after.ty - before.ty
        #expect(abs(dx) < 0.05 && abs(dy) < 0.05, "\(action) near phase \(phase)")
      }
    }
  }

  @Test
  func shortConnectedStartleShiversOnTheGroundAndSettlesBeforeReturning() throws {
    let appearance = CharacterFullBodyCatAppearance(pose: .waving, action: .startle, puffDirection: .right)
    let duration = try #require(appearance.actionDuration)
    let hold = (0...Int(duration * 1000)).compactMap { tick -> CharacterFullBodyCatMotion? in
      let motion = CharacterFullBodyCatMotion.sample(
        appearance: appearance, elapsed: 0, actionElapsed: Double(tick) / 1000, reduceMotion: false)
      return motion.pose == .puffed && motion.transition == nil ? motion : nil
    }
    #expect(hold.contains { $0.bristleSway < -0.05 })
    #expect(hold.contains { $0.bristleSway > 0.05 })
    #expect(hold.allSatisfy { $0.bodyOffsetY == 0 && $0.bodyAngle == 0 })
    #expect(abs(try #require(hold.last).bristleSway) < 0.00001)
  }

  @Test(arguments: [CharacterFeltCatTransition.Route.puffed, .puffedRight])
  func bristlePosePuffsAndShiversWithPlantedPaws(
    _ route: CharacterFeltCatTransition.Route
  ) throws {
    let facing = try #require(route.puffDirection)
    let stand = CharacterFullBodyCatAppearance()
    let bristle = CharacterFullBodyCatAppearance(pose: .puffed, puffDirection: facing)
    let begins = 1.0
    var playback = CharacterFullBodyCatPlayback(appearance: stand, at: 0)
    playback.update(appearance: bristle, at: begins)
    func motion(at time: Double, reduceMotion: Bool = false) -> CharacterFullBodyCatMotion {
      playback.sample(appearance: bristle, at: begins + time, reduceMotion: reduceMotion)
    }
    let entry = route.entryDuration
    let shiver = CharacterFullBodyCatMotion.bristleShiverDuration
    let windup = (0..<60).map { motion(at: entry * Double($0) / 60) }
    #expect(windup.contains { $0.breath < -0.10 })
    #expect(windup.allSatisfy { $0.bodyOffsetY == 0 })
    let swollen = motion(at: entry + shiver * 0.21)
    #expect(swollen.pose == .puffed && swollen.transition == nil && swollen.breath > 0.12)
    #expect(swollen.mirrorsPuff == (facing == .right))
    let direction: Double = facing == .left ? 1 : -1
    let tremors = [0.07, 0.21, 0.35, 0.49].map { motion(at: entry + shiver * $0) }
    let sways = tremors.map { $0.bristleSway * direction }
    #expect(sways[0] > 0.05 && sways[1] < -0.05 && sways[2] > 0.04 && sways[3] < -0.03)
    #expect(tremors.allSatisfy {
      $0.bodyOffsetY == 0 && $0.bodyOffsetX == 0 && $0.bodyAngle == 0 && $0.sharedSurfaceWeight == 0
    })

    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    func bodyTransform(_ motion: CharacterFullBodyCatMotion) throws -> CharacterSceneTransform {
      let scene = try CharacterSceneBuilder.scene(
        pose: face, fullBodyCat: bristle, motion: motion, width: 256, height: 256, environment: .init())
      return try #require(scene.nodes.first { $0.id == "full-body-cat.body" }).transform
    }
    let settled = motion(at: entry + shiver + 0.01)
    #expect(settled.pose == .puffed && settled.bristleSway == 0)
    let restingTransform = try bodyTransform(settled)
    for tremor in tremors {
      let active = try bodyTransform(tremor)
      let y = CharacterFullBodyCatArtwork.groundY
      for x in [84.0, 181.0] {
        #expect(abs((active.a - restingTransform.a) * x + (active.c - restingTransform.c) * y
          + active.tx - restingTransform.tx) < 0.00001)
        #expect(abs((active.b - restingTransform.b) * x + (active.d - restingTransform.d) * y
          + active.ty - restingTransform.ty) < 0.00001)
      }
    }
    let reduced = motion(at: 0.02, reduceMotion: true)
    #expect(reduced.pose == .puffed && reduced.bristleSway == 0 && reduced.breath == 0)

    let redirect = begins + entry + shiver * 0.21
    playback.update(appearance: stand, at: redirect)
    let cancelled = playback.sample(appearance: stand, at: redirect, reduceMotion: false)
    #expect(cancelled.pose == swollen.pose && cancelled.mirrorsPuff == swollen.mirrorsPuff)
    #expect(cancelled.bristleSway == swollen.bristleSway)
    #expect(abs(cancelled.breath - swollen.breath) < 0.00001)
    let returned = playback.sample(appearance: stand, at: redirect + 1, reduceMotion: false)
    #expect(returned.pose == .standing && returned.bristleSway == 0)
  }

  @Test
  func changingRestWithAnUnchangedCueTurnsFromTheVisibleFrameWithoutReplaying() throws {
    let walking = CharacterFullBodyCatAppearance(action: .walk, actionTrigger: 5, walkDirection: .right)
    let newRest = CharacterFullBodyCatAppearance(pose: .loaf, action: .walk, actionTrigger: 5, walkDirection: .right)
    let change = 0.17
    var playback = CharacterFullBodyCatPlayback(appearance: walking, at: 0)
    let visible = try #require(playback.sample(appearance: walking, at: change, reduceMotion: false).transition)
    #expect(visible.route == .right && visible.frameAsset != nil)
    #expect(playback.sample(appearance: newRest, at: change, reduceMotion: false).transition == visible)
    playback.update(appearance: newRest, at: change)
    #expect(playback.sample(appearance: newRest, at: change, reduceMotion: false).transition == visible)

    let settled = playback.sample(appearance: newRest, at: 1.2, reduceMotion: false)
    #expect(settled.pose == .loaf && settled.transition == nil && settled.walkPhase == nil)
    #expect(playback.deadline == CharacterFullBodyCatAction.walk.duration)
  }

  @Test
  func wavingFromBellyUpLeavesTimeForBothPoseRoutesAndTheWave() throws {
    let appearance = CharacterFullBodyCatAppearance(pose: .bellyUp, action: .wave)
    let playback = CharacterFullBodyCatPlayback(appearance: appearance, at: 0)
    let duration = try #require(appearance.actionDuration)
    let samples = (0...Int((duration * 60).rounded(.up))).map {
      playback.sample(appearance: appearance, at: Double($0) / 60, reduceMotion: false)
    }

    let bellyFrames = Set(samples.compactMap { motion in
      motion.transition?.route == .bellyUp ? motion.transition?.frameIndex : nil
    })
    let waveFrames = Set(samples.compactMap { motion in
      motion.transition?.route == .waving ? motion.transition?.frameIndex : nil
    })
    #expect(bellyFrames.count >= 11)
    #expect(waveFrames.count >= 9)
    #expect(samples.contains { $0.pose == .standing })
    #expect(samples.contains { $0.pose == .waving && abs($0.pawAngle) > 0.10 })
    #expect(samples.last?.pose == .bellyUp)
    #expect(samples.last?.usesGestureTransform == false)
  }

  @Test(arguments: [0.0, 0.25, 0.5, 0.75])
  func aRightStartleFromWavingShowsAllFiftyTwoKeyVisits(displayPhase: Double) throws {
    let appearance = CharacterFullBodyCatAppearance(pose: .waving, action: .startle, puffDirection: .right)
    let duration = try #require(appearance.actionDuration)
    #expect(duration > CharacterFullBodyCatAction.startle.duration && duration < 1.5)
    #expect(CharacterFullBodyCatAppearance(action: .startle, puffDirection: .right).actionDuration
      == CharacterFullBodyCatAction.startle.duration)
    let playback = CharacterFullBodyCatPlayback(appearance: appearance, at: 0)
    var visits: [String] = []
    var previous: String?
    let frameCount = Int((duration * 60).rounded(.up))
    for tick in 0...frameCount {
      let motion = playback.sample(appearance: appearance, at: (Double(tick) + displayPhase) / 60, reduceMotion: false)
      var current: String?
      if let transition = motion.transition, transition.frameAsset != nil {
        current = "\(transition.route.assetKey):\(transition.frameIndex)"
      }
      if let current, current != previous { visits.append(current) }
      previous = current
    }
    let wave = (1...11).map { "wave:\($0)" }
    let rightPuff = CharacterFeltCatTransition.Route.puffedRight
    let puff = (1..<rightPuff.intervals).filter { $0 != rightPuff.waypoint?.index }.map { "puffright:\($0)" }
    #expect(visits == Array(wave.reversed()) + puff + Array(puff.reversed()) + wave)
    #expect(playback.sample(appearance: appearance, at: duration, reduceMotion: false).pose == .waving)
  }

  @Test(arguments: [CharacterFullBodyCatPose.standing, .loaf, .bellyUp])
  func selectingAPoseDuringActionEntryKeepsTheVisibleFrame(_ selected: CharacterFullBodyCatPose) throws {
    let gesture = CharacterFullBodyCatAppearance(action: .showBelly)
    let selection = CharacterFullBodyCatAppearance(pose: selected)
    let time = 0.28
    var playback = CharacterFullBodyCatPlayback(appearance: gesture, at: 0)
    let visible = try #require(playback.sample(
      appearance: gesture, at: time, reduceMotion: false).transition)
    #expect(visible.frameAsset != nil)

    let pending = playback.sample(appearance: selection, at: time, reduceMotion: false)
    #expect(pending.transition == visible)
    playback.update(appearance: selection, at: time)
    #expect(playback.sample(appearance: selection, at: time, reduceMotion: false) == pending)

    let continuing = try #require(playback.sample(
      appearance: selection, at: time + 0.09, reduceMotion: false).transition)
    #expect(continuing.route == .bellyUp)
    if selected == .bellyUp {
      #expect(continuing.progress > visible.progress)
    } else {
      #expect(continuing.progress < visible.progress)
      let standing = playback.sample(
        appearance: selection, at: time + visible.progress * visible.route.returnDuration, reduceMotion: false)
      #expect(standing.pose == .standing)
    }
    #expect(playback.sample(appearance: selection, at: 3, reduceMotion: false).pose == selected)
    #expect(playback.sample(appearance: selection, at: time, reduceMotion: true).pose == selected)
  }

  @Test
  func cancellingAVisibleWalkSettlesItsCurrentStrideBeforeReturning() throws {
    let walk = CharacterFullBodyCatAppearance(action: .walk, walkDirection: .right)
    let rest = CharacterFullBodyCatAppearance()
    let time = 0.85
    var playback = CharacterFullBodyCatPlayback(appearance: walk, at: 0)
    let visible = playback.sample(appearance: walk, at: time, reduceMotion: false)
    #expect(visible.walkStrength > 0)
    playback.update(appearance: rest, at: time)

    let first = playback.sample(appearance: rest, at: time, reduceMotion: false)
    #expect(first.pose == visible.pose)
    #expect(first.step(for: .nearFront) == visible.step(for: .nearFront))
    #expect(first.bodyOffsetX == visible.bodyOffsetX)
    #expect(first.sharedSurfaceWeight == visible.sharedSurfaceWeight)
    let releasing = playback.sample(appearance: rest, at: time + 0.06, reduceMotion: false)
    #expect(releasing.pose == visible.pose)
    #expect(releasing.walkStrength > 0 && releasing.walkStrength < visible.walkStrength)
    let coastingPhase = try #require(releasing.walkPhase)
    let originalPhase = try #require(visible.walkPhase)
    #expect(coastingPhase > originalPhase)

    let departing = try #require(playback.sample(
      appearance: rest, at: time + 0.25, reduceMotion: false).transition)
    #expect(departing.route == .right)
    #expect(departing.frameAsset != nil)
    #expect(playback.sample(appearance: rest, at: time + 1, reduceMotion: false).pose == .standing)
    #expect(playback.deadline == nil)
  }

  @Test(arguments: [CharacterFullBodyCatAction.walk, .wave])
  func repeatedSelectionsShareTheSameSettleWindow(_ action: CharacterFullBodyCatAction) throws {
    let cue = CharacterFullBodyCatAppearance(action: action, walkDirection: .right)
    let began = action == .walk ? 0.93 : 0.60
    let firstRest = CharacterFullBodyCatAppearance(pose: .loaf)
    var baseline = CharacterFullBodyCatPlayback(appearance: cue, at: 0)
    baseline.update(appearance: firstRest, at: began)
    var retargeted = baseline
    var current = firstRest
    for (delay, pose) in [(0.035, CharacterFullBodyCatPose.stretch), (0.070, .upright), (0.105, .bellyUp)] {
      let time = began + delay
      let previous = retargeted.sample(appearance: current, at: time, reduceMotion: false)
      current = .init(pose: pose)
      retargeted.update(appearance: current, at: time)
      let sample = retargeted.sample(appearance: current, at: time, reduceMotion: false)
      #expect(sample == previous)

      let unretargeted = baseline.sample(appearance: firstRest, at: time + 0.005, reduceMotion: false)
      let continued = retargeted.sample(appearance: current, at: time + 0.005, reduceMotion: false)
      #expect(continued == unretargeted)
    }
    let leaving = retargeted.sample(appearance: current, at: began + 0.17, reduceMotion: false)
    #expect(leaving.transition?.frameAsset != nil)
    #expect(leaving.walkPhase == nil && leaving.pawAngle == 0)
    #expect(retargeted.sample(appearance: current, at: began + 1.5, reduceMotion: false).pose == .bellyUp)
  }

  @Test
  func coalescedFeltSelectionsDoNotSquashTheAlreadyVisibleRest() {
    let rest = CharacterFullBodyCatAppearance()
    let right = CharacterFullBodyCatAppearance(pose: .right)
    let time = 0.60
    var playback = CharacterFullBodyCatPlayback(appearance: rest, at: 0)
    let visible = playback.sample(appearance: rest, at: time, reduceMotion: false)
    playback.update(appearance: right, at: time)
    playback.update(appearance: rest, at: time)
    #expect(playback.sample(appearance: rest, at: time, reduceMotion: false) == visible)
  }

  @Test(arguments: [CharacterFeltCatTransition.Route.rear, .puffedRight])
  func aMatchingSideTakesTheShortTurnInBothDirections(_ destination: CharacterFeltCatTransition.Route) throws {
    let waypoint = try #require(destination.waypoint)
    let anchor = CharacterFullBodyCatAppearance(pose: waypoint.pose)
    let target = CharacterFullBodyCatAppearance(
      pose: destination.destination, puffDirection: destination.puffDirection ?? .left)
    var playback = CharacterFullBodyCatPlayback(appearance: anchor, at: 0)
    playback.update(appearance: target, at: 1)
    let first = playback.sample(appearance: target, at: 1, reduceMotion: false)
    #expect(first.pose == anchor.pose && first.transition?.frameAsset == nil)
    let progress = try #require(playback.sample(appearance: target, at: 1.10, reduceMotion: false).transition)
    #expect(progress.route == destination && progress.progress > waypoint.progress)
    #expect(playback.sample(appearance: target, at: 1.4, reduceMotion: false).pose == target.pose)

    playback.update(appearance: anchor, at: 2)
    let reverse = try #require(playback.sample(appearance: anchor, at: 2.10, reduceMotion: false).transition)
    #expect(reverse.route == destination && reverse.progress > waypoint.progress && reverse.progress < 1)
    #expect(playback.sample(appearance: anchor, at: 2.4, reduceMotion: false).pose == anchor.pose)
  }

  @Test(arguments: [CharacterFullBodyCatPose.loaf, .waving, .upright, .bellyUp, .stretch])
  func risingFromACompactPoseFinishesBeforeHopFlight(_ resting: CharacterFullBodyCatPose) throws {
    let route = try #require(CharacterFeltCatTransition.Route(destination: resting))
    let cue = CharacterFullBodyCatAppearance(pose: resting, action: .hop)
    func motion(_ time: Double) -> CharacterFullBodyCatMotion {
      .sample(appearance: cue, elapsed: 0, actionElapsed: time, reduceMotion: false)
    }
    let rising = motion(route.returnDuration * 0.6)
    #expect(rising.transition?.route == route && rising.bodyOffsetY == 0)
    let airborne = motion(route.returnDuration + CharacterFullBodyCatAction.hop.duration * 0.5)
    #expect(airborne.transition == nil && airborne.pose == .standing && airborne.bodyOffsetY < -0.10)
    let lowering = motion(route.returnDuration + CharacterFullBodyCatAction.hop.duration + route.entryDuration * 0.4)
    #expect(lowering.transition?.route == route && lowering.bodyOffsetY == 0)
    #expect(motion(try #require(cue.actionDuration)).pose == resting)
  }

  @Test(arguments: [0.17, 0.56, 1.01])
  func flippingStartleDirectionUsesTheOutgoingPuffBeforeTurning(_ time: Double) throws {
    let left = CharacterFullBodyCatAppearance(action: .startle, puffDirection: .left)
    let right = CharacterFullBodyCatAppearance(action: .startle, puffDirection: .right)
    var playback = CharacterFullBodyCatPlayback(appearance: left, at: 0)
    let visible = playback.sample(appearance: left, at: time, reduceMotion: false)
    playback.update(appearance: right, at: time)
    let first = playback.sample(appearance: right, at: time, reduceMotion: false)
    #expect(first.pose == visible.pose)
    #expect(first.transition == visible.transition)
    #expect(first.bodyAngle == visible.bodyAngle)
    #expect(!first.mirrorsPuff)
    #expect(playback.deadline == time + CharacterFullBodyCatAction.startle.duration)
    #expect(playback.sample(appearance: right, at: time, reduceMotion: true).mirrorsPuff)

    let frames = (0..<100).map {
      playback.sample(appearance: right, at: time + Double($0) / 60, reduceMotion: false)
    }
    let enteringRight = try #require(frames.firstIndex { $0.transition?.route == .puffedRight })
    #expect(frames[..<enteringRight].contains { $0.transition?.route == .puffed })
    #expect(frames[..<enteringRight].contains { $0.pose == .standing })
    #expect(frames[enteringRight...].contains { $0.mirrorsPuff })
    #expect(playback.sample(appearance: right, at: time + 2, reduceMotion: false).pose == .standing)
  }
}

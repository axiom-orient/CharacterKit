import Foundation

struct CharacterFullBodyCatMotion: Equatable, Sendable {
  var pose: CharacterFullBodyCatPose
  var breath = 0.0
  var tailAngle = 0.0
  var pawAngle = 0.0
  var bodyAngle = 0.0
  var bodyWidth = 0.0
  var bodyOffsetX = 0.0
  var bodyOffsetY = 0.0
  var bristleSway = 0.0
  var headAngle = 0.0
  var walkPhase: Double?
  var walkStrength = 0.0
  var walkTravel = 11.5
  var walkLift = 14.0
  var farStrideScale = 1.0
  var walkWeightShift = 0.0
  var hasFeltFootfall = false
  var pawTuck = 0.0
  var usesGestureTransform = false
  var transition: CharacterFeltCatTransition?
  var sharedSurfaceWeight: Double?
  var crayonStances: [CharacterCrayonCatStance.Sample] = []
  var puffDirection = CharacterFullBodyCatFacing.left

  var hasLegMotion: Bool { walkPhase != nil || pawTuck > 0 }
  var mirrorsPuff: Bool {
    pose == .puffed && transition?.frameAsset == nil
      && (transition?.route.puffDirection ?? puffDirection) == .right
  }

  func applyingActing(_ acting: CharacterBodyActing) -> Self {
    guard acting != .neutral, transition?.frameAsset == nil else { return self }
    var result = self
    result.tailAngle *= 1 + 0.5 * acting.vigor
    result.pawAngle *= 1 + 0.4 * acting.vigor + 0.12 * acting.lift
    if walkPhase != nil {
      // Alter swing height without moving the planted feet or restarting their beat.
      result.walkLift *= 1 + 0.48 * acting.vigor + 0.24 * acting.lift
      let pitchDirection: Double = pose == .right ? -1 : 1
      result.headAngle += pitchDirection * 0.035 * acting.lift * walkStrength
    }
    return result
  }

  static func sample(
    appearance: CharacterFullBodyCatAppearance, elapsed: Double,
    actionElapsed: Double, reduceMotion: Bool
  ) -> Self {
    var motion = Self(pose: appearance.pose, puffDirection: appearance.puffDirection)
    if !reduceMotion {
      let time = elapsed.isFinite ? max(0, elapsed) : 0
      motion.breath = wave(time, period: 3.4) * 0.011
      motion.tailAngle = wave(time, period: 2.9) * 0.105 + wave(time, period: 1.4) * 0.032
    }

    guard let action = appearance.action, actionElapsed.isFinite, actionElapsed >= 0 else { return motion }
    if !reduceMotion, let timing = connectedTiming(for: action, appearance: appearance) {
      if actionElapsed < timing.duration {
        motion.applyConnectedAction(action, timing: timing, elapsed: actionElapsed)
      }
      return motion
    }
    if !reduceMotion, action == .hop, let route = hopDeparture(for: appearance) {
      motion.applyConnectedHop(route: route, elapsed: actionElapsed)
      return motion
    }

    guard actionElapsed < action.duration else { return motion }
    let phase = actionElapsed / action.duration
    if !reduceMotion, appearance.style == .crayon {
      let target = action == .walk ? appearance.walkingPose
        : representativePose(for: action, resting: appearance.pose)
      motion.applyCrayonAction(action, target: target, phase: phase)
      return motion
    }
    if reduceMotion {
      return .init(pose: action == .walk ? appearance.walkingPose
        : representativePose(for: action, resting: appearance.pose), usesGestureTransform: true,
        puffDirection: appearance.puffDirection)
    }
    motion.sharedSurfaceWeight = gestureSurfaceWeight(elapsed: actionElapsed, duration: action.duration)
    if phase < 0.09, action != .hop, action != .startle {
      let prepare = sin(.pi * phase / 0.09)
      motion.breath -= prepare * 0.023
      motion.headAngle -= prepare * 0.04
      return motion
    }

    let easing = smooth((phase - 0.09) / 0.11) * (1 - smooth((phase - 0.79) / 0.14))
    switch action {
    case .hop:
      motion.applyHop(at: phase)
    case .wave:
      if phase < 0.94 {
        motion.pose = .waving
        motion.usesGestureTransform = true
        motion.pawAngle = wave(phase, period: 0.26) * 0.28 * easing
        motion.bodyAngle = -0.028 * easing
        motion.headAngle = 0.025 * easing
      }
    case .walk:
      if phase < 0.94 {
        motion.pose = appearance.walkingPose
        motion.usesGestureTransform = true
        motion.applyWalk(cycle: (phase - 0.09) * 2.7, strength: easing, felt: appearance.style == .felt)
      }
    case .stretch:
      if phase < 0.94 {
        motion.pose = .stretch
        motion.usesGestureTransform = true
        if appearance.style == .felt {
          let reach = smooth((phase - 0.09) / 0.27) * (1 - smooth((phase - 0.65) / 0.29))
          motion.breath -= 0.051 * reach
          motion.bodyWidth += 0.048 * reach
          motion.bodyOffsetX = -0.027 * reach
          motion.headAngle = -0.025 * reach
        } else {
          motion.breath -= 0.045 * easing
          motion.bodyOffsetX = -0.024 * easing
        }
      }
    case .startle:
      // The resting cat is already bristling, so it can wind up in place.
      let windup = 0.13
      motion.sharedSurfaceWeight = gestureSurfaceWeight(
        elapsed: actionElapsed, duration: action.duration, ramp: windup)
      if actionElapsed < windup {
        motion.usesGestureTransform = true
        motion.applyBristleCrouch(phase: actionElapsed / windup)
      } else if actionElapsed < windup + Self.bristleShiverDuration {
        motion.usesGestureTransform = true
        motion.applyBristleShiver(phase: (actionElapsed - windup) / Self.bristleShiverDuration,
          facing: appearance.puffDirection)
      }
    case .showBelly:
      if phase < 0.92 {
        motion.pose = .bellyUp
        motion.usesGestureTransform = true
        let rock = easing * (1 - smooth((phase - 0.79) / 0.13))
        motion.bodyAngle = ((1 - smooth(phase / 0.28)) * 0.13
          - smooth((phase - 0.70) / 0.22) * 0.10) * rock
        motion.bodyOffsetX = wave(phase, period: 1.8) * 0.038 * rock
      }
    }
    return motion
  }

  private mutating func applyCrayonAction(
    _ action: CharacterFullBodyCatAction, target: CharacterFullBodyCatPose, phase: Double
  ) {
    let entry: Double
    let exit: Double
    switch action {
    case .walk: (entry, exit) = (0.17, 0.19)
    case .wave: (entry, exit) = (0.25, 0.27)
    case .stretch: (entry, exit) = (0.36, 0.32)
    case .startle: (entry, exit) = (0.22, 0.28)
    case .showBelly: (entry, exit) = (0.33, 0.34)
    case .hop: (entry, exit) = (0.21, 0.21)
    }
    let turnDelay = action == .startle ? 0.065 : 0
    let shape = Self.smooth((phase - turnDelay) / (entry - turnDelay)) * Self.smooth((1 - phase) / exit)
    let strength = Self.smooth(phase / (entry + 0.10)) * Self.smooth((1 - phase) / (exit + 0.08))
    sharedSurfaceWeight = 1 - Self.smooth(min(phase, 1 - phase) / 0.15)
    let source = CharacterCrayonCatStance(pose: pose, facing: puffDirection)
    let destination = CharacterCrayonCatStance(pose: target, facing: puffDirection)
    if source != destination, shape > 0, shape < 1 {
      crayonStances = [.init(stance: source, weight: 1 - shape), .init(stance: destination, weight: shape)]
    }
    pose = shape > 0 ? target : source.pose

    switch action {
    case .hop:
      // Accentuate the crayon jump through the same planted takeoff and landing.
      pose = target
      applyHop(at: phase, exaggeration: 1.27)
      pose = shape > 0 ? target : source.pose
      let direction: Double = target == .right ? -1 : 1
      let lookUp = Self.motionAccent(phase, from: 0.10, peak: 0.28, to: 0.59)
      let nod = Self.motionAccent(phase, from: 0.68, peak: 0.80, to: 1)
      headAngle = direction * (-0.085 * lookUp + 0.095 * nod)
    case .walk:
      let cycle = (phase - entry * 0.5) * 2.9
      let direction: Double = target == .left ? 1 : -1
      applyWalk(cycle: cycle, strength: strength * shape, felt: false)
      farStrideScale = 0.78
      walkLift = 12.0
      headAngle = direction * walkStrength * (0.018 + 0.053 * Self.wave(cycle - 0.105, period: 0.5))
      tailAngle -= direction * 0.13 * walkStrength * Self.wave(cycle - 0.16, period: 0.5)
    case .wave:
      let time = phase * action.duration
      // The lifted wrist leads the greeting while the body and tail settle.
      pawAngle = (0.24 * Self.wave(time - 0.12, period: 0.35) - 0.055) * strength
      bodyAngle = -0.022 * strength
      headAngle = (0.032 + Self.wave(time - 0.21, period: 0.35) * 0.013) * strength
      tailAngle *= 1 - 0.70 * strength
    case .stretch:
      // Rock back onto the hind legs before the chest sinks into the reach.
      let brace = Self.motionAccent(phase, from: 0, peak: 0.10, to: 0.29)
      let reach = Self.smooth((phase - 0.13) / 0.27) * (1 - Self.smooth((phase - 0.57) / 0.35))
      let release = Self.motionAccent(phase, from: 0.68, peak: 0.84, to: 1)
      breath += 0.026 * brace - 0.086 * reach + 0.034 * release
      bodyWidth += -0.026 * brace + 0.082 * reach
      bodyOffsetX += 0.016 * brace - 0.031 * reach
      bodyAngle = 0.024 * brace - 0.027 * reach
      headAngle = 0.047 * brace - 0.075 * reach + 0.035 * release
      tailAngle += -0.17 * reach + 0.17 * release
    case .startle:
      let load = Self.motionAccent(phase, from: 0, peak: 0.095, to: 0.19)
      let flare = Self.motionAccent(phase, from: 0.145, peak: 0.24, to: 0.68)
      let timeSinceFlare = (phase - 0.17) * action.duration
      let tremor = Self.smooth(timeSinceFlare / 0.046)
        * (1 - Self.smooth((timeSinceFlare - 0.10) / 0.49))
      let period = 0.145
      let direction: Double = puffDirection == .left ? 1 : -1
      let shake = tremor * Self.wave(timeSinceFlare, period: period)
      let followThrough = tremor * Self.wave(timeSinceFlare - 0.028, period: period)
      // The stage shears above the planted feet. The tail follows a beat later.
      breath += -0.095 * load + 0.138 * flare + 0.017 * followThrough
      bodyWidth += 0.040 * load - 0.068 * flare
      bristleSway = direction * 0.11 * shake
      headAngle = direction * (0.073 * load - 0.060 * flare + 0.038 * followThrough)
      tailAngle = tailAngle * (1 - 0.74 * shape) + 0.10 * flare - 0.13 * followThrough
    case .showBelly:
      // Tip past center, give the coat a soft landing, then rock on the back.
      let brace = Self.motionAccent(phase, from: 0, peak: 0.085, to: 0.19)
      let turn = Self.motionAccent(phase, from: 0.075, peak: 0.24, to: 0.38)
      let landing = Self.motionAccent(phase, from: 0.28, peak: 0.38, to: 0.52)
      let unwind = Self.motionAccent(phase, from: 0.62, peak: 0.83, to: 1)
      let rock = Self.smooth((phase - 0.35) / 0.07) * (1 - Self.smooth((phase - 0.51) / 0.20))
        * Self.wave(phase - 0.37, period: 0.26)
      bodyAngle = 0.061 * brace - 0.155 * turn + 0.076 * rock + 0.104 * unwind
      bodyOffsetX += 0.012 * brace - 0.027 * turn - 0.018 * shape + 0.022 * unwind
      breath += -0.065 * landing + 0.026 * abs(rock)
      bodyWidth += 0.047 * landing
      headAngle = -0.039 * turn - 0.068 * rock
      tailAngle += -0.14 * turn + 0.22 * rock + 0.14 * unwind
    }
  }

  private static func motionAccent(_ phase: Double, from start: Double, peak: Double, to end: Double) -> Double {
    smooth((phase - start) / (peak - start)) * (1 - smooth((phase - peak) / (end - peak)))
  }

  static func duration(for action: CharacterFullBodyCatAction, appearance: CharacterFullBodyCatAppearance) -> Double {
    if action == .hop, let route = hopDeparture(for: appearance) {
      return route.returnDuration + action.duration + route.entryDuration
    }
    return connectedTiming(for: action, appearance: appearance)?.duration ?? action.duration
  }

  private static func hopDeparture(for appearance: CharacterFullBodyCatAppearance) -> CharacterFeltCatTransition.Route? {
    guard appearance.style == .felt, appearance.pose != .standing,
      representativePose(for: .hop, resting: appearance.pose) == .standing
    else { return nil }
    return .init(destination: appearance.pose, puffDirection: appearance.puffDirection)
  }

  private static func connectedTiming(
    for action: CharacterFullBodyCatAction, appearance: CharacterFullBodyCatAppearance
  ) -> ConnectedActionTiming? {
    guard appearance.style == .felt else { return nil }
    let route: CharacterFeltCatTransition.Route? = switch action {
    case .walk: .init(destination: appearance.walkingPose)
    case .stretch: .stretch
    case .showBelly: .bellyUp
    case .wave: .waving
    case .startle: appearance.puffDirection == .right ? .puffedRight : .puffed
    case .hop: nil
    }
    guard let route, appearance.pose != route.destination else { return nil }
    let rest = CharacterFeltCatTransition.Route(destination: appearance.pose, puffDirection: appearance.puffDirection)
    return ConnectedActionTiming(gesture: route, rest: rest, nominalDuration: action.duration)
  }

  private mutating func applyConnectedAction(
    _ action: CharacterFullBodyCatAction, timing: ConnectedActionTiming, elapsed: Double
  ) {
    usesGestureTransform = true
    let remaining = timing.duration - elapsed
    let surfaceRamp = action == .startle ? min(0.18, timing.entryDuration, timing.exitDuration) : 0.18
    sharedSurfaceWeight = Self.gestureSurfaceWeight(elapsed: elapsed, duration: timing.duration, ramp: surfaceRamp)
    if elapsed < timing.entryDuration {
      transition = timing.entry.sample(at: elapsed)
      if let transition, transition.route == timing.gesture {
        applyBristleApproach(transition)
      }
    } else if remaining < timing.exitDuration {
      transition = timing.exit.sample(at: timing.exitDuration - remaining)
    } else {
      pose = timing.gesture.destination
      let performed = elapsed - timing.entryDuration
      let left = remaining - timing.exitDuration
      let strength = Self.smooth(min(performed, left) / 0.19)
      switch timing.gesture {
      case .left, .right:
        applyWalk(cycle: performed * (2.7 / action.duration), strength: strength, felt: true)
      case .stretch:
        breath -= 0.051 * strength
        bodyWidth += 0.048 * strength
        bodyOffsetX = -0.027 * strength
        headAngle = -0.025 * strength
      case .bellyUp:
        bodyAngle = 0.028 * strength * Self.wave(performed, period: 0.73)
        breath += 0.014 * strength
      case .waving:
        pawAngle = Self.wave(performed, period: 0.31) * 0.31 * strength
        bodyAngle = -0.025 * strength
        headAngle = 0.025 * strength
      case .puffed, .puffedRight:
        let hold = timing.duration - timing.entryDuration - timing.exitDuration
        applyBristleShiver(phase: performed / min(Self.bristleShiverDuration, hold), facing: puffDirection)
      case .loaf, .rear, .upright: break
      }
    }
    if let transition { pose = transition.endpoint }
  }

  static let bristleShiverDuration = 0.42

  /// Hold the paws at the contact line while the wool gathers above them.
  fileprivate mutating func applyBristleApproach(_ transition: CharacterFeltCatTransition) {
    guard transition.route.puffDirection != nil else { return }
    let turnEnd = transition.route.waypoint?.progress ?? 0
    applyBristleCrouch(phase: (transition.progress - turnEnd) / (1 - turnEnd))
  }

  private mutating func applyBristleCrouch(phase: Double) {
    let crouch = Self.motionAccent(phase, from: 0, peak: 0.42, to: 0.92)
    breath -= 0.12 * crouch
  }

  /// The coat swells once, then its upper edge flicks from side to side as the tremor fades.
  fileprivate mutating func applyBristleShiver(
    phase: Double, facing: CharacterFullBodyCatFacing, amplitude: Double = 1
  ) {
    let swell = Self.smooth(phase / 0.16) * (1 - Self.smooth((phase - 0.28) / 0.63))
    let tremor = Self.smooth(phase / 0.095) * (1 - Self.smooth((phase - 0.19) / 0.66))
    let period = 0.28
    let tailSide: Double = facing == .left ? 1 : -1

    breath += amplitude * (0.145 * swell + 0.022 * tremor * Self.wave(phase + 0.035, period: period))
    bristleSway = amplitude * (tailSide * 0.075 * tremor * Self.wave(phase, period: period))
  }

  private struct ConnectedActionTiming {
    struct Travel {
      private let steps: [(segment: CharacterFeltCatTransition.Segment, duration: Double)]
      let duration: Double

      init(_ segments: [CharacterFeltCatTransition.Segment], scale: Double) {
        steps = segments.map { ($0, max($0.duration * scale, $0.minimumAt60Hz)) }
        duration = steps.reduce(0) { $0 + $1.duration }
      }

      func sample(at time: Double) -> CharacterFeltCatTransition? {
        var elapsed = time
        for (segment, duration) in steps {
          if elapsed < duration { return segment.sample(fraction: elapsed / duration) }
          elapsed -= duration
        }
        return steps.last?.segment.sample(fraction: 1)
      }
    }

    let gesture: CharacterFeltCatTransition.Route
    let duration: Double
    let entry: Travel
    let exit: Travel

    var entryDuration: Double { entry.duration }
    var exitDuration: Double { exit.duration }

    init(gesture: CharacterFeltCatTransition.Route, rest: CharacterFeltCatTransition.Route?, nominalDuration: Double) {
      self.gesture = gesture
      let hold = 0.28
      let entering = CharacterFeltCatTransition.travel(from: rest, progress: 1, to: gesture)
      let leaving = CharacterFeltCatTransition.travel(from: gesture, progress: 1, to: rest)
      let preferredTravel = (entering + leaving).reduce(0) { $0 + $1.duration }
      let scale = min(1, (nominalDuration - hold) / preferredTravel)
      entry = Travel(entering, scale: scale)
      exit = Travel(leaving, scale: scale)
      duration = max(nominalDuration, entry.duration + exit.duration + hold)
    }
  }

  private mutating func applyWalk(cycle: Double, strength: Double, felt: Bool) {
    walkPhase = cycle
    walkStrength = strength
    guard felt else {
      let beat = Self.wave(cycle, period: 0.5)
      breath += 0.018 * strength * beat
      headAngle = 0.045 * strength * beat
      return
    }

    // Blend out most idle breathing while the paws carry the gait, so the wool
    // silhouette and tail do not compress and rebound on every footfall.
    breath *= 1 - 0.75 * strength
    let direction: Double = pose == .left ? -1 : 1
    walkTravel = 9.8
    walkLift = 9.5
    farStrideScale = 0.72
    hasFeltFootfall = true
    walkWeightShift = 1.15 * strength * Self.wave(cycle - 0.14, period: 0.5)
    bodyOffsetX = walkWeightShift * direction / CharacterFullBodyCatArtwork.size
    headAngle = direction * strength * 0.009 * Self.wave(cycle - 0.28, period: 0.5)
  }

  private mutating func applyConnectedHop(route: CharacterFeltCatTransition.Route, elapsed: Double) {
    let airborneEnds = route.returnDuration + CharacterFullBodyCatAction.hop.duration
    let duration = airborneEnds + route.entryDuration
    guard elapsed < duration else { return }
    usesGestureTransform = true
    sharedSurfaceWeight = Self.gestureSurfaceWeight(elapsed: elapsed, duration: duration)
    if elapsed < route.returnDuration {
      transition = .init(route: route, progress: 1 - Self.transitionProgress(elapsed / route.returnDuration))
    } else if elapsed < airborneEnds {
      pose = .standing
      applyHop(at: (elapsed - route.returnDuration) / CharacterFullBodyCatAction.hop.duration)
    } else {
      transition = .init(route: route, progress: Self.transitionProgress((elapsed - airborneEnds) / route.entryDuration))
    }
    if let transition { pose = transition.endpoint }
  }

  private mutating func applyHop(at phase: Double, exaggeration: Double = 1) {
    usesGestureTransform = true
    let stance = Self.representativePose(for: .hop, resting: pose)
    if (0.14..<0.92).contains(phase) {
      pose = stance
    }
    // The squash is anchored to the floor. Only the flight curve lifts that anchor.
    let crouch = Self.smooth(phase / 0.15) * (1 - Self.smooth((phase - 0.15) / 0.13))
    let push = Self.smooth((phase - 0.17) / 0.10) * (1 - Self.smooth((phase - 0.27) / 0.15))
    let flight = min(1, max(0, (phase - 0.25) / 0.47))
    let arch = 4 * flight * (1 - flight)
    let landing = Self.smooth((phase - 0.72) / 0.08) * (1 - Self.smooth((phase - 0.80) / 0.18))
    let rebound = Self.smooth((phase - 0.83) / 0.07) * (1 - Self.smooth((phase - 0.90) / 0.10))
    let reshape = exaggeration * (-0.087 * crouch + 0.060 * push - 0.071 * landing + 0.019 * rebound)
    breath += reshape
    bodyWidth -= 0.62 * reshape
    bodyOffsetY -= 0.115 * arch * exaggeration
    tailAngle += exaggeration * (-0.16 * crouch + 0.19 * arch - 0.11 * landing)
    pawTuck = exaggeration * Self.smooth(flight / 0.33) * (1 - Self.smooth((flight - 0.56) / 0.44))
  }

  /// Four-beat gait. During stance the toe sweeps backwards along the floor.
  /// During swing it moves forward on a smooth lifted arc.
  func step(for leg: CharacterFullBodyCatLeg) -> CharacterFullBodyCatStep {
    guard let walkPhase else {
      let isFront = leg == .nearFront || leg == .farFront
      let isFar = leg == .farFront || leg == .farHind
      let tuck = pawTuck * (isFar ? 0.73 : 1)
      return .init(offsetX: tuck * (isFront ? -4 : 3), lift: tuck * (isFront ? 6 : 4.5))
    }
    let beat: Double
    switch leg {
    case .farHind: beat = 0
    case .farFront: beat = 0.25
    case .nearHind: beat = 0.5
    case .nearFront: beat = 0.75
    }
    let position = walkPhase - beat
    let cycle = position - floor(position)
    let swing = hasFeltFootfall ? Self.feltSwing : 0.24
    let strength = walkStrength * (leg == .farFront || leg == .farHind ? farStrideScale : 1)
    let travel = walkTravel * strength
    if cycle < swing {
      let forward = cycle / swing
      let arc = sin(.pi * forward)
      // Gather the paw early and slow the downward motion before the pad touches the floor.
      let lift = hasFeltFootfall
        ? Self.smooth(forward / 0.44) * (1 - Self.smooth((forward - 0.44) / 0.56))
        : arc * arc
      return .init(offsetX: travel * (2 * Self.smooth(forward) - 1) - walkWeightShift,
        lift: walkLift * strength * lift)
    }
    let back = (cycle - swing) / (1 - swing)
    let stance = hasFeltFootfall ? Self.stanceProgress(back) : Self.smooth(back)
    return .init(offsetX: travel * (1 - 2 * stance) - walkWeightShift, lift: 0)
  }

  private static let feltSwing = 0.25

  private static func stanceProgress(_ t: Double) -> Double {
    // A flat speed through the middle of contact, easing both reversals.
    let edge = 0.13
    func ramp(_ x: Double) -> Double { x * x / (2 * edge * (1 - edge)) }
    if t < edge { return ramp(t) }
    if t > 1 - edge { return 1 - ramp(1 - t) }
    return (t - 0.5 * edge) / (1 - edge)
  }

  private static func representativePose(
    for action: CharacterFullBodyCatAction, resting: CharacterFullBodyCatPose
  ) -> CharacterFullBodyCatPose {
    switch action {
    case .wave: .waving
    case .walk: resting == .left ? .left : .right
    case .stretch: .stretch
    case .startle: .puffed
    case .showBelly: .bellyUp
    case .hop:
      switch resting {
      case .standing, .left, .right, .rear, .puffed: resting
      case .loaf, .waving, .upright, .bellyUp, .stretch: .standing
      }
    }
  }

  private static func wave(_ time: Double, period: Double) -> Double {
    sin(2 * .pi * time.truncatingRemainder(dividingBy: period) / period)
  }

  fileprivate static func smooth(_ fraction: Double) -> Double {
    let value = min(max(fraction, 0), 1)
    return value * value * (3 - 2 * value)
  }

  private static func gestureSurfaceWeight(elapsed: Double, duration: Double, ramp: Double = 0.18) -> Double {
    1 - smooth(min(elapsed, duration - elapsed) / ramp)
  }

  static func transitionProgress(_ fraction: Double) -> Double {
    // Light easing keeps the first and last few authored frames moving too.
    let unit = min(1, max(0, fraction))
    return (unit + smooth(unit)) / 2
  }
}

struct CharacterFullBodyCatStep: Equatable, Sendable {
  let offsetX: Double
  let lift: Double

  static let planted = Self(offsetX: 0, lift: 0)

  /// Keeps the hip fixed and moves the paw to the requested ground or swing point.
  func transform(
    hip: CharacterVectorPoint, foot: CharacterVectorPoint, direction: Double
  ) -> CharacterSceneTransform {
    guard self != .planted else { return .identity }
    let dx = foot.x - hip.x
    let dy = foot.y - hip.y
    let length = hypot(dx, dy)
    guard length > 0 else { return .identity }
    let steppedX = dx + offsetX * direction
    let steppedY = dy - lift
    let align = CharacterSceneTransform.around(x: hip.x, y: hip.y, angle: -atan2(dy, dx))
    let reach = CharacterSceneTransform.around(
      x: hip.x, y: hip.y, scaleX: max(0.40, hypot(steppedX, steppedY) / length))
    let turn = CharacterSceneTransform.around(x: hip.x, y: hip.y, angle: atan2(steppedY, steppedX))
    return turn.concatenating(reach).concatenating(align)
  }
}

/// Uses the same monotonic time as the face, with a separate cue identity for body actions.
struct CharacterFullBodyCatPlayback {
  private struct Release {
    static let duration = 0.12

    let began: Double
    let source: CharacterFullBodyCatMotion

    var endsAt: Double { began + Self.duration }

    func apply(at time: Double, to motion: inout CharacterFullBodyCatMotion) {
      let elapsed = max(0, time - began)
      let weight = 1 - CharacterFullBodyCatMotion.smooth(elapsed / Self.duration)
      motion.breath += (source.breath - motion.breath) * weight
      motion.tailAngle += (source.tailAngle - motion.tailAngle) * weight
      motion.bodyAngle += (source.bodyAngle - motion.bodyAngle) * weight
      motion.bodyWidth += (source.bodyWidth - motion.bodyWidth) * weight
      motion.bodyOffsetX += (source.bodyOffsetX - motion.bodyOffsetX) * weight
      motion.bodyOffsetY += (source.bodyOffsetY - motion.bodyOffsetY) * weight
      motion.bristleSway += (source.bristleSway - motion.bristleSway) * weight
      motion.headAngle = source.headAngle * weight
      motion.pawAngle = source.pawAngle * weight
      motion.pawTuck = source.pawTuck * weight
      motion.walkPhase = source.walkPhase.map { phase in
        let coast = elapsed * (1 - 0.5 * elapsed / Self.duration)
        return phase + coast * (2.7 / CharacterFullBodyCatAction.walk.duration)
      }
      motion.walkStrength = source.walkStrength * weight
      motion.walkTravel = source.walkTravel
      motion.walkLift = source.walkLift
      motion.farStrideScale = source.farStrideScale
      motion.walkWeightShift = source.walkWeightShift * weight
      motion.hasFeltFootfall = source.hasFeltFootfall
      let surface = source.sharedSurfaceWeight ?? (source.usesGestureTransform ? 0 : 1)
      let targetSurface = motion.sharedSurfaceWeight ?? 1
      motion.sharedSurfaceWeight = targetSurface + (surface - targetSurface) * weight
    }
  }

  private struct RestTransition {
    let legs: [CharacterFeltCatTransition.Segment]
    let began: Double
    let source: CharacterFullBodyCatMotion
    let release: Release?
    let bristleArrival: CharacterFullBodyCatFacing?

    var remainingRelease: Double { max(0, (release?.endsAt ?? began) - began) }
    // Endpoint limbs are articulated separately. Let them settle before using a baked frame.
    var routeDelay: Double { source.transition?.frameAsset == nil ? remainingRelease : 0 }
    var arrivalTime: Double { routeDelay + legs.reduce(0) { $0 + $1.duration } }
    var duration: Double {
      max(remainingRelease, arrivalTime)
        + (bristleArrival == nil ? 0 : CharacterFullBodyCatMotion.bristleShiverDuration)
    }

    func sample(at time: Double, resting: CharacterFullBodyCatMotion) -> CharacterFullBodyCatMotion {
      let elapsed = max(0, time - began)

      var motion = resting
      if elapsed < routeDelay {
        motion.pose = source.pose
        motion.puffDirection = source.puffDirection
        motion.transition = source.transition
      } else if let bristleArrival, elapsed >= arrivalTime {
        let timeSinceArrival = max(0, elapsed - max(remainingRelease, arrivalTime))
        let phase = timeSinceArrival / CharacterFullBodyCatMotion.bristleShiverDuration
        motion.usesGestureTransform = true
        motion.sharedSurfaceWeight = CharacterFullBodyCatMotion.smooth((phase - 0.84) / 0.16)
        motion.applyBristleShiver(phase: phase, facing: bristleArrival)
      } else {
        var routeElapsed = elapsed - routeDelay
        for leg in legs {
          if routeElapsed < leg.duration {
            let frame = leg.sample(fraction: routeElapsed / leg.duration)
            motion.pose = frame.endpoint
            motion.transition = frame
            if bristleArrival != nil, leg.to > leg.from {
              motion.applyBristleApproach(frame)
            }
            break
          }
          routeElapsed -= leg.duration
        }
      }

      if bristleArrival != nil, elapsed < arrivalTime {
        let leavesRest = CharacterFullBodyCatMotion.smooth((elapsed - routeDelay) / 0.12)
        motion.sharedSurfaceWeight = 1 - leavesRest
      }
      if let release, time < release.endsAt { release.apply(at: time, to: &motion) }
      return motion
    }
  }

  private let began: Double
  private var appliedAppearance: CharacterFullBodyCatAppearance?
  private var actionStarted: Double
  private var animatedActionStarted: Double?
  private var restChangedAt: Double?
  private var restTransition: RestTransition?
  private var crayonHandoff: CharacterCrayonCatHandoff?

  init(appearance: CharacterFullBodyCatAppearance?, at time: Double) {
    began = time
    appliedAppearance = appearance
    actionStarted = time
    animatedActionStarted = time
  }

  mutating func update(appearance: CharacterFullBodyCatAppearance?, at time: Double) {
    guard appearance != appliedAppearance else { return }
    let changedRest = restChanged(to: appearance)
    let changedCue = appearance?.cue != appliedAppearance?.cue
    let changedStyle = appearance?.style != appliedAppearance?.style
    if changedRest || changedCue || changedStyle {
      let nextCrayonHandoff = crayonRestHandoff(to: appearance, at: time, changedRest: changedRest)
      restTransition = restHandoff(to: appearance, at: time)
      crayonHandoff = nextCrayonHandoff
      if changedRest || changedStyle {
        // A coalesced felt selection may already match the visible rest.
        let keepsFeltSurface = appearance?.style == .felt && !changedStyle
        restChangedAt = changedRest && restTransition == nil && crayonHandoff == nil && !keepsFeltSurface ? time : nil
      }
      if changedCue {
        actionStarted = time
        animatedActionStarted = time + (restTransition?.duration ?? crayonHandoff?.duration ?? 0)
      } else if changedRest, !changedStyle {
        // A new resting pose takes over visually without replaying the retained cue.
        animatedActionStarted = nil
      }
    }
    appliedAppearance = appearance
  }

  var deadline: Double? { appliedAppearance?.action.map { actionStarted + $0.duration } }

  func sample(
    appearance: CharacterFullBodyCatAppearance, at time: Double, reduceMotion: Bool
  ) -> CharacterFullBodyCatMotion {
    // SwiftUI can sample newer input before delivering onChange.
    if appliedAppearance != appearance {
      var pending = self
      pending.update(appearance: appearance, at: time)
      return pending.appliedSample(appearance: appearance, at: time, reduceMotion: reduceMotion)
    }
    return appliedSample(appearance: appearance, at: time, reduceMotion: reduceMotion)
  }

  private func idleSample(appearance: CharacterFullBodyCatAppearance, at time: Double) -> CharacterFullBodyCatMotion {
    CharacterFullBodyCatMotion.sample(
      appearance: appearance, elapsed: max(0, time - began), actionElapsed: -1, reduceMotion: false)
  }

  private func appliedSample(
    appearance: CharacterFullBodyCatAppearance, at time: Double, reduceMotion: Bool
  ) -> CharacterFullBodyCatMotion {
    if !reduceMotion, let handoff = restTransition, time < handoff.began + handoff.duration {
      return handoff.sample(at: time, resting: idleSample(appearance: appearance, at: time))
    }
    if !reduceMotion, let handoff = crayonHandoff, time < handoff.began + handoff.duration {
      return handoff.sample(at: time, resting: idleSample(appearance: appearance, at: time))
    }
    let start = animatedActionStarted.map { reduceMotion ? actionStarted : $0 }
    var motion = CharacterFullBodyCatMotion.sample(
      appearance: appearance, elapsed: max(0, time - began),
      actionElapsed: start.map { max(0, time - $0) } ?? -1, reduceMotion: reduceMotion)
    if !reduceMotion, !motion.usesGestureTransform, restTransition == nil, let restChangedAt {
      let progress = min(1, max(0, (time - restChangedAt) / 0.24))
      let settling = pow(1 - progress, 2) * cos(progress * .pi * 2)
      motion.breath -= settling * 0.033
      motion.headAngle += settling * 0.042
    }
    return motion
  }

  private func restChanged(to appearance: CharacterFullBodyCatAppearance?) -> Bool {
    if appearance?.pose != appliedAppearance?.pose { return true }
    return appearance?.pose == .puffed && appearance?.puffDirection != appliedAppearance?.puffDirection
  }

  private func crayonRestHandoff(
    to appearance: CharacterFullBodyCatAppearance?, at time: Double, changedRest: Bool
  ) -> CharacterCrayonCatHandoff? {
    guard let previous = appliedAppearance, previous.style == .crayon, appearance?.style == .crayon
    else { return nil }
    let visible = appliedSample(appearance: previous, at: time, reduceMotion: false)
    guard changedRest || !visible.crayonStances.isEmpty || (visible.sharedSurfaceWeight ?? 1) < 1
    else { return nil }
    return .init(began: time, source: visible)
  }

  private func restHandoff(
    to appearance: CharacterFullBodyCatAppearance?, at time: Double
  ) -> RestTransition? {
    guard let previous = appliedAppearance, previous.style == .felt,
      let appearance, appearance.style == .felt
    else { return nil }

    let visible = appliedSample(appearance: previous, at: time, reduceMotion: false)
    let ongoingRelease = restTransition?.release.flatMap { time < $0.endsAt ? $0 : nil }
    let ownsBodyTransform = visible.usesGestureTransform || (visible.sharedSurfaceWeight ?? 1) < 1
    guard restChanged(to: appearance) || visible.transition != nil || ownsBodyTransform || ongoingRelease != nil
    else { return nil }

    let departure = visible.transition?.route
      ?? CharacterFeltCatTransition.Route(destination: visible.pose, puffDirection: visible.puffDirection)
    let arrival = CharacterFeltCatTransition.Route(
      destination: appearance.pose, puffDirection: appearance.puffDirection)
    let progress = visible.transition?.progress ?? 1
    let legs = CharacterFeltCatTransition.travel(from: departure, progress: progress, to: arrival)
    // Retarget the route while the same paw or tail is settling. Restarting
    // that release on each selection can keep the character in its old pose.
    let release = ongoingRelease ?? (ownsBodyTransform ? Release(began: time, source: visible) : nil)
    let bristleArrival = restChanged(to: appearance) && !legs.isEmpty ? arrival?.puffDirection : nil
    let handoff = RestTransition(
      legs: legs, began: time, source: visible, release: release, bristleArrival: bristleArrival)
    return handoff.duration > 0 ? handoff : nil
  }
}

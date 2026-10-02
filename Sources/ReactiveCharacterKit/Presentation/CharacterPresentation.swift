import Foundation

public enum CharacterPresentationPhase: Sendable, Equatable {
  case performing
  case returningToNeutral(progress: Double)
  case neutralHold
  case gazeTransition(progress: Double)
}

public struct CharacterPresentationStatus: Sendable, Equatable {
  public let state: CharacterState
  public let phase: CharacterPresentationPhase
  public let remainingHandoffDuration: Double
}

/// Interruption-safe presentation runtime.
///
/// Semantic truth remains in `CharacterState`. This type owns only transient visual
/// continuity and independent layer clocks. Large semantic performances return through
/// neutral; ordinary gaze changes use a short saccade bridge and never reset activity,
/// emotion, communication or animation time.
public struct CharacterPresentationSession: Sendable, Equatable {
  private enum Timing {
    static let featureEntryDuration = 0.17
    static let mouthExitDuration = 0.062
  }

  private struct LayerClock: Sendable, Equatable {
    let elapsedAtAnchor: Double
    let anchorTime: Double

    init(elapsed: Double = 0, anchorTime: Double) {
      elapsedAtAnchor = max(0, elapsed)
      self.anchorTime = anchorTime
    }

    func elapsed(at time: Double) -> Double {
      elapsedAtAnchor + max(0, time - anchorTime)
    }
  }

  private struct Bridge: Sendable, Equatable {
    let from: CharacterPose
    let startedAt: Double
    let returnDuration: Double
    let neutralHoldDuration: Double
    let rebound: Double
  }

  private struct GazeBridge: Sendable, Equatable {
    let from: CharacterPose
    let startedAt: Double
    let duration: Double
    let amplitude: Double
  }

  private var targetState: CharacterState
  private var activityClock: LayerClock
  private var expressionClock: LayerClock
  private var communicationClock: LayerClock
  private var animationClock: LayerClock
  private var bridge: Bridge?
  private var gazeBridge: GazeBridge?

  public init(state: CharacterState = .idle, at time: Double = 0) {
    precondition(time.isFinite && time >= 0, "time must be finite and non-negative")
    targetState = state
    activityClock = LayerClock(anchorTime: time)
    expressionClock = LayerClock(anchorTime: time)
    communicationClock = LayerClock(anchorTime: time)
    animationClock = LayerClock(anchorTime: time)
    bridge = nil
    gazeBridge = nil
  }

  /// Accepts the newest semantic state.
  ///
  /// Returns `true` only for a full neutral handoff. Gaze-only changes are intentionally
  /// lighter: they preserve all layer clocks and use a crisp micro-saccade bridge.
  @discardableResult
  public mutating func update(
    state newState: CharacterState,
    at time: Double,
    reduceMotion: Bool = false,
    projection: CharacterProjection = .softSphere,
    motionProfile: CharacterMotionProfile = .expressive,
    transitionProfile: CharacterTransitionProfile = .expressive
  ) -> Bool {
    precondition(time.isFinite && time >= 0, "time must be finite and non-negative")

    let oldState = targetState
    let oldIdentity = oldState.performanceIdentity
    let newIdentity = newState.performanceIdentity
    let performanceChanged = newIdentity != oldIdentity

    let oldActivityElapsed = activityClock.elapsed(at: time)
    let oldExpressionElapsed = expressionClock.elapsed(at: time)
    let oldCommunicationElapsed = communicationClock.elapsed(at: time)
    let oldAnimationElapsed = animationClock.elapsed(at: time)

    // The semantic completion timer is deliberately scheduled with the hard handoff
    // budget so it can never end a one-shot before presentation actually starts.
    // By the time that cleanup arrives, the visual layer may already have expired and
    // fallen back to emotion/communication/activity. Cleanup must then be continuity-
    // preserving rather than creating a second neutral handoff.
    if isExpiredAnimationCleanup(
      oldState: oldState,
      newState: newState,
      oldAnimationElapsed: oldAnimationElapsed
    ) {
      targetState = newState
      animationClock = LayerClock(elapsed: 0, anchorTime: time)
      bridge = nil
      gazeBridge = nil
      return false
    }

    if reduceMotion {
      // Accessibility can change without a semantic state change. Reconcile it as
      // presentation input so an in-flight bridge cannot remain latched in the static
      // reduced-motion Canvas. Preserve elapsed layer time when semantic identity is
      // unchanged; restart only when the semantic performance itself changed.
      targetState = newState
      if performanceChanged {
        activityClock = LayerClock(anchorTime: time)
        expressionClock = LayerClock(anchorTime: time)
        communicationClock = LayerClock(anchorTime: time)
        animationClock = LayerClock(anchorTime: time)
      } else {
        activityClock = LayerClock(elapsed: oldActivityElapsed, anchorTime: time)
        expressionClock = LayerClock(elapsed: oldExpressionElapsed, anchorTime: time)
        communicationClock = LayerClock(elapsed: oldCommunicationElapsed, anchorTime: time)
        animationClock = LayerClock(elapsed: oldAnimationElapsed, anchorTime: time)
      }
      bridge = nil
      gazeBridge = nil
      return false
    }

    if performanceChanged {
      let current = pose(
        at: time,
        reduceMotion: reduceMotion,
        projection: projection,
        motionProfile: motionProfile
      )
      let neutral = neutralPose(projection: projection, motionProfile: motionProfile)
      let policy = transitionProfile
      let distance = poseDistance(current, neutral)
      let returnDuration = returnDuration(for: distance, profile: policy)
      let resumeAt = time + returnDuration + policy.neutralHoldDuration

      targetState = newState
      activityClock = LayerClock(
        elapsed: oldState.activity.motionIdentity == newState.activity.motionIdentity
          ? oldActivityElapsed : 0,
        anchorTime: resumeAt
      )
      let emotionRestart =
        oldState.emotion != newState.emotion
        || (newState.visualChannel == .emotion && oldState.visualChannel != .emotion)
      expressionClock = LayerClock(
        elapsed: emotionRestart ? 0 : oldExpressionElapsed,
        anchorTime: resumeAt
      )
      let communicationRestart =
        oldState.communication.presentationIdentity
        != newState.communication.presentationIdentity
        || (newState.visualChannel == .communication && oldState.visualChannel != .communication)
      communicationClock = LayerClock(
        elapsed: communicationRestart ? 0 : oldCommunicationElapsed,
        anchorTime: resumeAt
      )
      animationClock = LayerClock(
        elapsed: oldState.animation?.id == newState.animation?.id ? oldAnimationElapsed : 0,
        anchorTime: resumeAt
      )
      bridge = Bridge(
        from: current,
        startedAt: time,
        returnDuration: returnDuration,
        neutralHoldDuration: policy.neutralHoldDuration,
        rebound: policy.rebound
      )
      gazeBridge = nil
      return true
    }

    let gazeChanged = oldState.gazeIdentity != newState.gazeIdentity
    let currentPose =
      gazeChanged
      ? pose(
        at: time,
        reduceMotion: reduceMotion,
        projection: projection,
        motionProfile: motionProfile
      )
      : nil

    targetState = newState

    if gazeChanged, let currentPose {
      let target = rawPose(
        at: time,
        reduceMotion: reduceMotion,
        projection: projection,
        motionProfile: motionProfile
      ).eyes
      let amplitude = eyeCenterDistance(currentPose.eyes, target)
      let duration = reduceMotion ? 0 : gazeDuration(amplitude: amplitude)
      if duration > 0.000_001, amplitude > 0.002 {
        gazeBridge = GazeBridge(
          from: currentPose,
          startedAt: time,
          duration: duration,
          amplitude: amplitude
        )
      } else {
        gazeBridge = nil
      }
    }

    return false
  }

  public func pose(
    at time: Double,
    reduceMotion: Bool = false,
    projection: CharacterProjection = .softSphere,
    motionProfile: CharacterMotionProfile = .expressive
  ) -> CharacterPose {
    precondition(time.isFinite && time >= 0, "time must be finite and non-negative")

    // The requested sampling policy applies even before the host reconciles its session.
    // This does not mutate phase/clocks; update(reduceMotion:) still owns reconciliation.
    if reduceMotion {
      return rawPose(
        at: time, reduceMotion: true, projection: projection, motionProfile: motionProfile)
    }

    var featureBuildStart: Double?
    if let bridge {
      let local = max(0, time - bridge.startedAt)
      if local < bridge.returnDuration {
        let neutral = neutralPose(projection: projection, motionProfile: motionProfile)
        let linear = clamp(local / max(bridge.returnDuration, 0.000_001), lower: 0, upper: 1)
        let amount = cartoonReturnAmount(linear, rebound: bridge.rebound)
        return blendPose(
          from: bridge.from,
          to: neutral,
          amount: amount,
          fadeProgress: linear,
          mouthProgress: clamp(local / Timing.mouthExitDuration, lower: 0, upper: 1)
        )
      }
      if local < bridge.returnDuration + bridge.neutralHoldDuration {
        return neutralPose(projection: projection, motionProfile: motionProfile)
      }
      featureBuildStart = bridge.startedAt + bridge.returnDuration + bridge.neutralHoldDuration
    }

    var result = rawPose(
      at: time,
      reduceMotion: reduceMotion,
      projection: projection,
      motionProfile: motionProfile
    )

    if let gazeBridge {
      let local = max(0, time - gazeBridge.startedAt)
      if local < gazeBridge.duration {
        if local <= 0.000_001 {
          return gazeBridge.from
        }
        let progress = clamp(local / max(gazeBridge.duration, 0.000_001), lower: 0, upper: 1)
        let amount = gazeTransitionAmount(progress)
        result = applyingGazeBridge(
          to: result,
          from: gazeBridge.from,
          amount: amount,
          progress: progress,
          amplitude: gazeBridge.amplitude
        )
      }
    }

    // Retain the bridge for deterministic historical sampling, but do not rebuild
    // neutral geometry or blend completed features on every subsequent frame.
    if let featureBuildStart, time < featureBuildStart + Timing.featureEntryDuration {
      let progress = smoothStep(
        clamp((time - featureBuildStart) / Timing.featureEntryDuration, lower: 0, upper: 1))
      let neutral = neutralPose(projection: projection, motionProfile: motionProfile)
      result = applyingFeatureEntry(to: result, from: neutral, amount: progress)
    }

    return result
  }

  public func inspect(at time: Double) -> CharacterPresentationStatus {
    precondition(time.isFinite && time >= 0, "time must be finite and non-negative")

    if let bridge {
      let local = max(0, time - bridge.startedAt)
      let total = bridge.returnDuration + bridge.neutralHoldDuration
      if local < bridge.returnDuration {
        return CharacterPresentationStatus(
          state: targetState,
          phase: .returningToNeutral(
            progress: clamp(local / max(bridge.returnDuration, 0.000_001), lower: 0, upper: 1)
          ),
          remainingHandoffDuration: max(0, total - local)
        )
      }
      if local < total {
        return CharacterPresentationStatus(
          state: targetState,
          phase: .neutralHold,
          remainingHandoffDuration: max(0, total - local)
        )
      }
    }

    if let gazeBridge {
      let local = max(0, time - gazeBridge.startedAt)
      if local < gazeBridge.duration {
        return CharacterPresentationStatus(
          state: targetState,
          phase: .gazeTransition(
            progress: clamp(local / max(gazeBridge.duration, 0.000_001), lower: 0, upper: 1)
          ),
          remainingHandoffDuration: max(0, gazeBridge.duration - local)
        )
      }
    }

    return CharacterPresentationStatus(
      state: targetState,
      phase: .performing,
      remainingHandoffDuration: 0
    )
  }

  /// Reconciles a caller-owned presentation configuration change without changing
  /// semantic state or restarting independent layer clocks.
  ///
  /// Pose-shaping inputs such as projection and motion profile are presentation inputs
  /// rather than `CharacterState`. If one changes while a neutral or gaze bridge is active,
  /// that bridge contains a pose captured under the previous sampling configuration. Keeping
  /// it would mix two presentation coordinate systems. This method drops only those transient
  /// bridges and re-anchors the existing clocks at their current elapsed values. A
  /// transition-profile-only change does not require reconciliation because an existing
  /// bridge already owns the timing values captured when that bridge was created.
  public mutating func reconcilePresentationConfigurationChange(at time: Double) {
    precondition(time.isFinite && time >= 0, "time must be finite and non-negative")

    activityClock = LayerClock(elapsed: activityClock.elapsed(at: time), anchorTime: time)
    expressionClock = LayerClock(elapsed: expressionClock.elapsed(at: time), anchorTime: time)
    communicationClock = LayerClock(
      elapsed: communicationClock.elapsed(at: time),
      anchorTime: time
    )
    animationClock = LayerClock(elapsed: animationClock.elapsed(at: time), anchorTime: time)
    bridge = nil
    gazeBridge = nil
  }

  private func isExpiredAnimationCleanup(
    oldState: CharacterState,
    newState: CharacterState,
    oldAnimationElapsed: Double
  ) -> Bool {
    guard let oldAnimation = oldState.animation, newState.animation == nil else { return false }
    guard oldAnimationElapsed >= oldAnimation.animation.duration else { return false }
    guard oldState.activity == newState.activity,
      oldState.attention == newState.attention,
      oldState.emotion == newState.emotion,
      oldState.communication == newState.communication
    else {
      return false
    }
    return newState.visualChannel == oldState.fallbackVisualChannelExcludingAnimation
  }

  private func rawPose(
    at time: Double,
    reduceMotion: Bool,
    projection: CharacterProjection,
    motionProfile: CharacterMotionProfile
  ) -> CharacterPose {
    ReactiveCharacter.pose(
      state: targetState,
      elapsed: activityClock.elapsed(at: time),
      expressionElapsed: expressionClock.elapsed(at: time),
      communicationElapsed: communicationClock.elapsed(at: time),
      animationElapsed: animationClock.elapsed(at: time),
      reduceMotion: reduceMotion,
      projection: projection,
      motionProfile: motionProfile
    )
  }

  private func neutralPose(
    projection: CharacterProjection,
    motionProfile: CharacterMotionProfile
  ) -> CharacterPose {
    ReactiveCharacter.pose(
      state: .idle,
      elapsed: 0,
      expressionElapsed: 0,
      communicationElapsed: 0,
      animationElapsed: 0,
      reduceMotion: true,
      projection: projection,
      motionProfile: motionProfile
    )
  }

  private func returnDuration(
    for distance: Double,
    profile: CharacterTransitionProfile
  ) -> Double {
    let normalized = clamp(distance, lower: 0, upper: 1)
    let shaped = sqrt(normalized)
    return profile.minimumReturnDuration
      + (profile.maximumReturnDuration - profile.minimumReturnDuration) * shaped
  }

  private func gazeDuration(amplitude: Double) -> Double {
    let normalized = clamp(
      amplitude / CharacterPresentationPolicy.maximumGazeAmplitude,
      lower: 0,
      upper: 1
    )
    return CharacterPresentationPolicy.minimumGazeTransitionDuration
      + sqrt(normalized) * CharacterPresentationPolicy.gazeTransitionDurationRange
  }

  private func eyeCenterDistance(
    _ lhs: CharacterEyePairPose,
    _ rhs: CharacterEyePairPose
  ) -> Double {
    max(
      hypot(lhs.left.centerX - rhs.left.centerX, lhs.left.centerY - rhs.left.centerY),
      hypot(lhs.right.centerX - rhs.right.centerX, lhs.right.centerY - rhs.right.centerY)
    )
  }

  private func poseDistance(_ lhs: CharacterPose, _ rhs: CharacterPose) -> Double {
    let eyes = max(
      eyeDistance(lhs.eyes.left, rhs.eyes.left),
      eyeDistance(lhs.eyes.right, rhs.eyes.right)
    )
    let surface = min(
      1,
      abs(lhs.surface.offsetX - rhs.surface.offsetX) * 5
        + abs(lhs.surface.offsetY - rhs.surface.offsetY) * 5
        + abs(lhs.surface.scaleX - rhs.surface.scaleX) * 2.5
        + abs(lhs.surface.scaleY - rhs.surface.scaleY) * 2.5
        + abs(lhs.surface.angle - rhs.surface.angle) * 4
    )
    let mouth = min(
      1,
      abs(lhs.mouth.curvature - rhs.mouth.curvature) * 0.35
        + abs(lhs.mouth.openness - rhs.mouth.openness) * 0.65
        + lhs.mouth.opacity * 0.25
    )
    let secondary = min(
      1,
      lhs.motionEnergy * 0.6
        + Double(lhs.accents.count) * 0.08
        + lhs.writingOpacity * 0.18
    )
    return clamp(max(max(eyes, surface), max(mouth, secondary)), lower: 0, upper: 1)
  }

  private func eyeDistance(_ lhs: CharacterEyePose, _ rhs: CharacterEyePose) -> Double {
    min(
      1,
      abs(lhs.centerX - rhs.centerX) * 2.2
        + abs(lhs.centerY - rhs.centerY) * 2.2
        + abs(lhs.width - rhs.width) * 2.0
        + abs(lhs.height - rhs.height) * 2.0
        + abs(lhs.angle - rhs.angle) * 2.5
    )
  }

  private func cartoonReturnAmount(_ progress: Double, rebound: Double) -> Double {
    let p = clamp(progress, lower: 0, upper: 1)
    if rebound == 0 { return smoothStep(p) }

    if p < 0.18 {
      return 0.14 * easeOutCubic(p / 0.18)
    }
    if p < 0.82 {
      let local = (p - 0.18) / 0.64
      return mix(0.14, 1 + rebound, amount: easeOutQuint(local))
    }
    let local = (p - 0.82) / 0.18
    return mix(1 + rebound, 1, amount: smoothStep(local))
  }

  /// Eye darts move most of the distance immediately, then settle the final few percent.
  private func gazeTransitionAmount(_ progress: Double) -> Double {
    let p = clamp(progress, lower: 0, upper: 1)
    if p < 0.72 {
      return 0.94 * easeOutQuint(p / 0.72)
    }
    return mix(0.94, 1, amount: smoothStep((p - 0.72) / 0.28))
  }

  private func applyingGazeBridge(
    to pose: CharacterPose,
    from: CharacterPose,
    amount: Double,
    progress: Double,
    amplitude: Double
  ) -> CharacterPose {
    var eyes = blendEyePair(from.eyes, pose.eyes, amount: amount)

    // A large change of attention gets a tiny coordinated blink/compression during
    // acquisition. It is deliberately subtle so the gaze direction remains readable.
    if amplitude > 0.10, progress < 0.42 {
      let local = progress / 0.42
      let blink = sin(local * .pi) * 0.20
      eyes = CharacterEyePairPose(
        left: compressedEye(eyes.left, amount: blink),
        right: compressedEye(eyes.right, amount: blink)
      )
    }

    return CharacterPose(
      eyes: eyes,
      nearTrail: from.eyes,
      farTrail: pose.farTrail,
      nearTrailOpacity: max(pose.nearTrailOpacity, (1 - progress) * 0.18),
      farTrailOpacity: pose.farTrailOpacity,
      noseOffsetX: mix(from.noseOffsetX, pose.noseOffsetX, amount: amount),
      mouth: pose.mouth,
      surface: pose.surface,
      writingPhase: pose.writingPhase,
      writingMotionPhase: pose.writingMotionPhase,
      writingProgress: pose.writingProgress,
      writingVisible: pose.writingVisible,
      writingOpacity: pose.writingOpacity,
      accents: pose.accents,
      motionEnergy: max(pose.motionEnergy, (1 - progress) * 0.45),
      eyeContours: pose.eyeContours,
      brows: pose.brows,
      faceDynamics: pose.faceDynamics
    )
  }

  private func compressedEye(_ eye: CharacterEyePose, amount: Double) -> CharacterEyePose {
    let compression = clamp(amount, lower: 0, upper: 1)
    return CharacterEyePose(
      centerX: eye.centerX,
      centerY: eye.centerY,
      width: eye.width * (1 + compression * 0.08),
      height: max(0.035, eye.height * (1 - compression)),
      angle: eye.angle,
      unblinkedWidth: eye.unblinkedWidth * (1 + compression * 0.08),
      unblinkedHeight: eye.unblinkedHeight,
      blink: 1 - (1 - eye.blink) * (1 - compression)
    )
  }

  private func blendPose(
    from: CharacterPose,
    to: CharacterPose,
    amount: Double,
    fadeProgress: Double,
    mouthProgress: Double
  ) -> CharacterPose {
    let fade = 1 - clamp(fadeProgress, lower: 0, upper: 1)
    let nearTrail = from.nearTrail.map { blendEyePair($0, to.eyes, amount: amount) }
    let farTrail = from.farTrail.map { blendEyePair($0, to.eyes, amount: amount) }
    let mouthAmount = clamp(mouthProgress, lower: 0, upper: 1)
    let mouthOpacity = mix(from.mouth.opacity, to.mouth.opacity, amount: mouthAmount)
    let mouthContour = MouthGlyphLibrary.blend(
      from: from.mouth.contour,
      to: to.mouth.contour,
      amount: mouthAmount
    )
    // Interior geometry is not topology-compatible across glyphs. Fade it out
    // before the shared contour reaches neutral, and keep it suppressed while
    // the handoff is returning. This avoids a stale tooth/tongue set reading as
    // a detached second mouth during an interrupted transition.
    let detailReturn = 1 - smoothStep(mouthAmount / 0.64)
    let detailOpacity =
      from.mouth.detailOpacity * detailReturn
      + to.mouth.detailOpacity * smoothStep((mouthAmount - 0.78) / 0.22)
    let writingOpacity = from.writingOpacity * fade
    let reference = referenceGlyphTransition(
      from: from.mouth, to: to.mouth, progress: mouthAmount)

    return CharacterPose(
      eyes: blendEyePair(from.eyes, to.eyes, amount: amount),
      nearTrail: nearTrail,
      farTrail: farTrail,
      nearTrailOpacity: from.nearTrailOpacity * fade,
      farTrailOpacity: from.farTrailOpacity * fade,
      noseOffsetX: mix(from.noseOffsetX, to.noseOffsetX, amount: amount),
      mouth: CharacterMouthPose(
        visible: mouthOpacity > 0.002,
        opacity: mouthOpacity,
        curvature: mix(from.mouth.curvature, to.mouth.curvature, amount: mouthAmount),
        openness: max(0, mix(from.mouth.openness, to.mouth.openness, amount: mouthAmount)),
        width: max(0.20, mix(from.mouth.width, to.mouth.width, amount: mouthAmount)),
        skew: mix(from.mouth.skew, to.mouth.skew, amount: mouthAmount),
        intrinsicAspect: mix(
          from.mouth.intrinsicAspect,
          to.mouth.intrinsicAspect,
          amount: mouthAmount
        ),
        detailOpacity: clamp(detailOpacity, lower: 0, upper: 1),
        referenceGlyphOpacity: reference.opacity,
        glyph: reference.glyph,
        interior: mouthAmount >= 0.999 ? to.mouth.interior : from.mouth.interior,
        contour: mouthContour,
        // Detail paths are intentionally kept as a single authored set until
        // the contour has arrived.  Interpolating unrelated teeth/tongue
        // topology would briefly create a second-looking mouth.
        details: mouthAmount >= 0.999 ? to.mouth.details : from.mouth.details
      ),
      surface: CharacterSurfacePose(
        offsetX: mix(from.surface.offsetX, to.surface.offsetX, amount: amount),
        offsetY: mix(from.surface.offsetY, to.surface.offsetY, amount: amount),
        scaleX: max(0.72, mix(from.surface.scaleX, to.surface.scaleX, amount: amount)),
        scaleY: max(0.72, mix(from.surface.scaleY, to.surface.scaleY, amount: amount)),
        angle: mix(from.surface.angle, to.surface.angle, amount: amount)
      ),
      writingPhase: from.writingPhase,
      writingMotionPhase: from.writingMotionPhase,
      writingProgress: from.writingProgress,
      writingVisible: writingOpacity > 0.002,
      writingOpacity: writingOpacity,
      accents: from.accents.map { accent in
        CharacterAccentPose(
          kind: accent.kind,
          centerX: accent.centerX,
          centerY: accent.centerY,
          width: accent.width,
          height: accent.height,
          angle: accent.angle,
          opacity: accent.opacity * fade
        )
      },
      motionEnergy: from.motionEnergy * fade,
      eyeContours: from.eyeContours.blended(to: to.eyeContours, amount: amount),
      brows: from.brows.blended(to: to.brows, amount: amount),
      faceDynamics: from.faceDynamics.blended(to: to.faceDynamics, amount: amount)
    )
  }

  private func applyingFeatureEntry(
    to pose: CharacterPose,
    from neutral: CharacterPose,
    amount: Double
  ) -> CharacterPose {
    let progress = clamp(amount, lower: 0, upper: 1)
    if progress <= 0 { return neutral }
    if progress >= 1 { return pose }
    let source = neutral.mouth
    let mouth = pose.mouth
    let blendedContour = MouthGlyphLibrary.blend(
      from: source.contour,
      to: mouth.contour,
      amount: progress
    )
    let opacity = mouth.opacity * progress
    let reference = referenceGlyphTransition(from: source, to: mouth, progress: progress)
    return CharacterPose(
      eyes: blendEyePair(neutral.eyes, pose.eyes, amount: progress),
      nearTrail: pose.nearTrail.map { blendEyePair(neutral.eyes, $0, amount: progress) },
      farTrail: pose.farTrail.map { blendEyePair(neutral.eyes, $0, amount: progress) },
      nearTrailOpacity: pose.nearTrailOpacity * progress,
      farTrailOpacity: pose.farTrailOpacity * progress,
      noseOffsetX: mix(neutral.noseOffsetX, pose.noseOffsetX, amount: progress),
      mouth: CharacterMouthPose(
        visible: opacity > 0.002,
        opacity: opacity,
        curvature: mouth.curvature * progress,
        openness: mouth.openness * progress,
        width: mix(source.width, mouth.width, amount: progress),
        skew: mouth.skew * progress,
        intrinsicAspect: mix(
          source.intrinsicAspect,
          mouth.intrinsicAspect,
          amount: progress
        ),
        // The target's interior is revealed only after most of its contour
        // has arrived. The raw pose may also request an early fade-out for a
        // repeating cycle; multiplying preserves that request.
        detailOpacity: mouth.detailOpacity * smoothStep((progress - 0.48) / 0.52),
        referenceGlyphOpacity: reference.opacity,
        glyph: reference.glyph,
        interior: mouth.interior,
        contour: blendedContour,
        details: progress >= 0.999 ? mouth.details : source.details
      ),
      surface: CharacterSurfacePose(
        offsetX: mix(neutral.surface.offsetX, pose.surface.offsetX, amount: progress),
        offsetY: mix(neutral.surface.offsetY, pose.surface.offsetY, amount: progress),
        scaleX: mix(neutral.surface.scaleX, pose.surface.scaleX, amount: progress),
        scaleY: mix(neutral.surface.scaleY, pose.surface.scaleY, amount: progress),
        angle: mix(neutral.surface.angle, pose.surface.angle, amount: progress)
      ),
      writingPhase: pose.writingPhase,
      writingMotionPhase: pose.writingMotionPhase,
      writingProgress: pose.writingProgress,
      writingVisible: pose.writingVisible,
      writingOpacity: pose.writingOpacity * progress,
      accents: pose.accents.map { accent in
        CharacterAccentPose(
          kind: accent.kind, centerX: accent.centerX, centerY: accent.centerY,
          width: accent.width, height: accent.height, angle: accent.angle,
          opacity: accent.opacity * progress)
      },
      motionEnergy: pose.motionEnergy * progress,
      eyeContours: CharacterEyeContourPair.neutral.blended(to: pose.eyeContours, amount: progress),
      brows: CharacterBrowPairPose.neutral.blended(to: pose.brows, amount: progress),
      faceDynamics: neutral.faceDynamics.blended(to: pose.faceDynamics, amount: progress)
    )
  }

  /// Select a single reference glyph during the crossing; never cross-fade two authored mouths.
  private func referenceGlyphTransition(
    from source: CharacterMouthPose, to target: CharacterMouthPose, progress: Double
  ) -> (opacity: Double, glyph: CharacterMouthGlyph) {
    let sourceOpacity = source.referenceGlyphOpacity * (1 - smoothStep(progress / 0.24))
    let targetOpacity = target.referenceGlyphOpacity * smoothStep((progress - 0.76) / 0.24)
    if progress <= 0.001 {
      return (source.referenceGlyphOpacity, source.glyph)
    }
    if progress >= 0.999 {
      return (target.referenceGlyphOpacity, target.glyph)
    }
    if sourceOpacity > targetOpacity, sourceOpacity > 0.000_001 {
      return (sourceOpacity, source.glyph)
    }
    if targetOpacity > 0.000_001 { return (targetOpacity, target.glyph) }
    return (0, progress < 0.5 ? source.glyph : target.glyph)
  }

  private func blendEyePair(
    _ lhs: CharacterEyePairPose,
    _ rhs: CharacterEyePairPose,
    amount: Double
  ) -> CharacterEyePairPose {
    CharacterEyePairPose(
      left: blendEye(lhs.left, rhs.left, amount: amount),
      right: blendEye(lhs.right, rhs.right, amount: amount)
    )
  }

  private func blendEye(
    _ lhs: CharacterEyePose,
    _ rhs: CharacterEyePose,
    amount: Double
  ) -> CharacterEyePose {
    CharacterEyePose(
      centerX: mix(lhs.centerX, rhs.centerX, amount: amount),
      centerY: mix(lhs.centerY, rhs.centerY, amount: amount),
      width: max(0.035, mix(lhs.width, rhs.width, amount: amount)),
      height: max(0.035, mix(lhs.height, rhs.height, amount: amount)),
      angle: mix(lhs.angle, rhs.angle, amount: amount),
      unblinkedWidth: max(0.035, mix(lhs.unblinkedWidth, rhs.unblinkedWidth, amount: amount)),
      unblinkedHeight: max(0.035, mix(lhs.unblinkedHeight, rhs.unblinkedHeight, amount: amount)),
      blink: clamp(mix(lhs.blink, rhs.blink, amount: amount), lower: 0, upper: 1)
    )
  }

  private func mix(_ start: Double, _ end: Double, amount: Double) -> Double {
    start + (end - start) * amount
  }

  private func smoothStep(_ value: Double) -> Double {
    let t = clamp(value, lower: 0, upper: 1)
    return t * t * (3 - 2 * t)
  }

  private func easeOutCubic(_ value: Double) -> Double {
    let t = clamp(value, lower: 0, upper: 1)
    return 1 - pow(1 - t, 3)
  }

  private func easeOutQuint(_ value: Double) -> Double {
    let t = clamp(value, lower: 0, upper: 1)
    return 1 - pow(1 - t, 5)
  }

  private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
  }
}

enum CharacterCommunicationIdentity: Sendable, Hashable {
  case silent
  case chat
  case listening
  case voice
}

enum CharacterPerformanceIdentity: Sendable, Hashable {
  case neutral
  case activity(CharacterMotionIdentity)
  case emotion(CharacterEmotion)
  case communication(CharacterCommunicationIdentity)
  case animation(CharacterAnimationID)
}

enum CharacterGazeIdentity: Sendable, Hashable {
  case automatic
  case focus(CharacterPoint)
  case writing(CharacterPoint)
}

extension CharacterCommunication {
  var presentationIdentity: CharacterCommunicationIdentity {
    switch self {
    case .silent: .silent
    case .chat: .chat
    case .listening: .listening
    case .voice: .voice
    }
  }
}

extension CharacterState {
  var performanceIdentity: CharacterPerformanceIdentity {
    switch visualChannel {
    case .neutral:
      return .neutral
    case .activity:
      return .activity(activity.motionIdentity)
    case .emotion:
      return emotion.map(CharacterPerformanceIdentity.emotion) ?? .neutral
    case .communication:
      return communication == .silent
        ? .neutral
        : .communication(communication.presentationIdentity)
    case .animation:
      return animation.map { .animation($0.id) } ?? .neutral
    }
  }

  var gazeIdentity: CharacterGazeIdentity {
    switch attention {
    case .focus(let point):
      return .focus(point)
    case .automatic:
      if case .userWriting(let focus) = activity {
        return .writing(focus)
      }
      return .automatic
    }
  }
}

import Foundation

extension ReactiveCharacter {
  /// Produces deterministic renderer-independent SEMI presentation data.
  public static func pose(
    state: CharacterState,
    elapsed: Double,
    expressionElapsed: Double? = nil,
    communicationElapsed: Double? = nil,
    animationElapsed: Double? = nil,
    reduceMotion: Bool = false
  ) -> CharacterPose {
    CharacterMotion.sample(
      state: state,
      activityElapsed: elapsed,
      expressionElapsed: expressionElapsed ?? elapsed,
      communicationElapsed: communicationElapsed ?? expressionElapsed ?? elapsed,
      animationElapsed: animationElapsed ?? expressionElapsed ?? elapsed,
      reduceMotion: reduceMotion,
      projection: .softSphere,
      profile: .semi,
      detailMotionStyle: .semi
    )
  }
}


enum CharacterMotion {
  private struct EyeSample {
    let visualChannel: CharacterVisualChannel
    let expression: CharacterExpressionSample
    let animation: CharacterAnimationSample
    let frame: CharacterMotionFrame
    let eyes: CharacterEyePairPose
  }

  static func sample(
    state: CharacterState,
    activityElapsed: Double,
    expressionElapsed: Double,
    communicationElapsed: Double,
    animationElapsed: Double,
    reduceMotion: Bool,
    projection: CharacterProjection = .softSphere,
    profile: CharacterMotionProfile = .semi,
    voiceLevelOverride: Double? = nil,
    detailMotionStyle: CharacterDetailMotionStyle = .semi
  ) -> CharacterPose {
    let activityTime = reduceMotion ? 0 : validatedTime(activityElapsed)
    let expressionTime = reduceMotion ? 0 : validatedTime(expressionElapsed)
    let communicationTime = reduceMotion ? 0 : validatedTime(communicationElapsed)
    // Explicit one-shot time keeps advancing even under Reduce Motion so its
    // representative pose cannot become a permanent semantic latch.
    let animationTime = validatedTime(animationElapsed)
    let eyeSample = sampleEyes(
      state: state,
      activityElapsed: activityTime,
      expressionElapsed: expressionTime,
      animationElapsed: animationTime,
      reduceMotion: reduceMotion,
      projection: projection,
      profile: profile
    )
    let ownsActivity = eyeSample.visualChannel == .activity
    let expression = eyeSample.expression
    let animation = eyeSample.animation
    let frame = eyeSample.frame

    let trailEnergy = clamp(
      max(max(frame.motionEnergy, expression.trailBoost), animation.trailBoost),
      lower: 0,
      upper: 1
    )
    // Emotions, communication and work are expressed by the face and writing parts.
    // Decorations are an explicit host overlay only, never inferred from semantic state.
    let writingVisible = writingIsVisible(for: state.activity)
    let writingOpacity = writingVisible ? (ownsActivity ? 1.0 : 0.52) : 0
    let faceDynamics = CharacterFaceDynamics.sample(emotion: state.emotion, projection: projection)
    let surface = composeSurface(
      activitySurfacePose(
        activity: state.activity,
        elapsed: activityTime,
        reduceMotion: reduceMotion,
        intensity: profile.expressiveness * (ownsActivity ? 1 : 0.24)
      ),
      composeSurface(expression.surface, animation.surface)
    )
    let detailMotion = sampleDetailMotion(
      state: state,
      visualChannel: eyeSample.visualChannel,
      time: detailMotionClock(
        visualChannel: eyeSample.visualChannel,
        activity: activityTime,
        expression: expressionTime,
        communication: communicationTime,
        animation: animationTime
      ),
      trailEnergy: trailEnergy,
      surface: surface,
      expression: expression,
      voiceLevelOverride: voiceLevelOverride,
      reduceMotion: reduceMotion,
      profile: profile,
      detailMotionStyle: detailMotionStyle
    )

    return CharacterPose(
      eyes: eyeSample.eyes,
      noseOffsetX: frame.gazeX * 0.22,
      mouth: mouthPose(
        requested: state.mouthRequested,
        communication: state.communication,
        activity: state.activity,
        expression: expression,
        elapsed: communicationTime,
        reduceMotion: reduceMotion,
        voiceLevelOverride: voiceLevelOverride
      ),
      surface: surface,
      writingPhase: writingPhase(
        for: state.activity,
        elapsed: activityTime,
        reduceMotion: reduceMotion
      ),
      writingMotionPhase: writingMotionPhase(
        for: state.activity,
        elapsed: activityTime,
        reduceMotion: reduceMotion
      ),
      writingProgress: writingProgress(for: state.activity),
      writingVisible: writingVisible,
      writingOpacity: writingOpacity,
      motionEnergy: trailEnergy,
      eyeContours: expression.eyeContours,
      faceDynamics: faceDynamics,
      detailMotion: detailMotion
    )
  }

  private static func detailMotionClock(
    visualChannel: CharacterVisualChannel,
    activity: Double,
    expression: Double,
    communication: Double,
    animation: Double
  ) -> Double {
    switch visualChannel {
    case .neutral, .activity:
      activity
    case .emotion:
      expression
    case .communication:
      communication
    case .animation:
      animation
    }
  }

  private static func sampleDetailMotion(
    state: CharacterState,
    visualChannel: CharacterVisualChannel,
    time: Double,
    trailEnergy: Double,
    surface: CharacterSurfacePose,
    expression: CharacterExpressionSample,
    voiceLevelOverride: Double?,
    reduceMotion: Bool,
    profile: CharacterMotionProfile,
    detailMotionStyle: CharacterDetailMotionStyle
  ) -> CharacterDetailMotion {
    let isSEMIIdle = detailMotionStyle == .semi
      && visualChannel == .neutral
      && state.activity == .idle
      && state.emotion == nil
      && state.communication == .silent
    guard !reduceMotion, profile.expressiveness > 0,
      visualChannel != .neutral || isSEMIIdle
    else {
      return .still
    }

    let surfaceImpulse = clamp(
      hypot(surface.offsetX, surface.offsetY) * 5
        + abs(surface.scaleX - 1) * 2.5
        + abs(surface.scaleY - 1) * 2.5
        + abs(surface.angle) * 4,
      lower: 0,
      upper: 1
    )
    let secondaryEnergy = max(clamp(trailEnergy, lower: 0, upper: 1), surfaceImpulse)
    // A laugh, nod or curious lean can carry body energy without an impact.
    // Eyes and detail share the resolved owner, including visual expiry before host cleanup.
    let activeAnimation = visualChannel == .animation ? state.animation?.animation : nil
    let impulse: Double = switch activeAnimation {
    case .bounce, .recoil, .shake: secondaryEnergy
    default: 0
    }
    let expressionAmount = clamp(
      max(
        max(abs(expression.mouthCurvature) * 0.70, expression.mouthOpenness * 0.78),
        abs(expression.mouthSkew) * 0.65),
      lower: 0,
      upper: 1
    )
    let communicationAmount: Double = switch state.communication {
    case .silent:
      0
    case .chat:
      0.72
    case .listening:
      0.62
    case .voice(let level):
      clamp(0.30 + (voiceLevelOverride ?? level.value) * 0.58, lower: 0, upper: 1)
    }
    let activityAmount: Double = if isSEMIIdle { 0.20 } else {
      switch state.activity {
      case .idle:
        0.20
      case .userWriting, .agentWriting:
        0.48
      case .agentThinking:
        0.38
      case .agentCancelling:
        0.66
      case .success, .failure, .cancelled:
        0.72
      }
    }
    let baseAmount = max(
      max(expressionAmount, communicationAmount),
      max(activityAmount, secondaryEnergy)
    )
    let amount = clamp(baseAmount * min(profile.expressiveness, 1.5), lower: 0, upper: 1)
    return CharacterDetailMotion.sample(time: time, impulse: impulse, amount: amount)
  }

  static func motionFrame(
    for activity: CharacterActivity,
    elapsed: Double
  ) -> CharacterMotionFrame {
    let time = validatedTime(elapsed)
    switch activity {
    case .idle:
      return idleFrame(elapsed: time)
    case .userWriting(let focus):
      return activeWritingFrame(elapsed: time, base: userWritingTarget(focus: focus))
    case .agentThinking:
      return thinkingFrame(elapsed: time)
    case .agentWriting(_, let progress):
      return activeWritingFrame(elapsed: time, base: agentWritingTarget(progress: progress.value))
    case .agentCancelling:
      return cancellingFrame(elapsed: time)
    case .success:
      return terminalFrame(
        elapsed: time,
        target: boundedTarget(x: 0, y: -0.08, angle: 0, shape: .large),
        moveDuration: 0.075,
        settleDuration: 0.045
      )
    case .failure:
      return terminalFrame(
        elapsed: time,
        target: boundedTarget(x: 0, y: 0.18, angle: 0, shape: .wide),
        moveDuration: 0.090,
        settleDuration: 0.050
      )
    case .cancelled:
      return terminalFrame(
        elapsed: time,
        target: boundedTarget(x: -0.10, y: 0.13, angle: -0.035, shape: .tinyCircle),
        moveDuration: 0.085,
        settleDuration: 0.045
      )
    }
  }

  private static func baseGazeFrame(
    state: CharacterState,
    elapsed: Double,
    reduceMotion: Bool,
    profile: CharacterMotionProfile
  ) -> CharacterMotionFrame {
    if reduceMotion {
      return reducedMotionFrame(for: state.activity)
    }

    if state.activity.isIdle, state.communication != .silent {
      return conversationalGazeFrame(elapsed: elapsed)
    }

    let sampled = motionFrame(for: state.activity, elapsed: elapsed)
    return state.activity.isIdle
      ? scaledIdleFrame(sampled, strength: profile.idleStrength)
      : sampled
  }

  /// Keeps semantic attention alive without letting a non-activity layer inherit
  /// activity-specific eye-shape acting. Position, direction, energy and blink survive.
  private static func gazeOnlyFrame(_ frame: CharacterMotionFrame) -> CharacterMotionFrame {
    CharacterMotionFrame(
      gazeX: frame.gazeX,
      gazeY: frame.gazeY,
      angle: frame.angle * 0.45,
      eyeWidth: CharacterEyeShape.tall.width,
      eyeHeight: CharacterEyeShape.tall.height,
      motionEnergy: frame.motionEnergy * 0.72,
      directionX: frame.directionX,
      directionY: frame.directionY,
      blink: frame.blink
    )
  }

  private static func applyAttention(
    _ attention: CharacterAttention,
    to frame: CharacterMotionFrame
  ) -> CharacterMotionFrame {
    guard case .focus(let point) = attention else { return frame }
    let targetX = clamp((point.x - 0.5) * 0.42, lower: -0.21, upper: 0.21)
    let targetY = clamp((point.y - 0.5) * 0.42, lower: -0.21, upper: 0.21)
    let dx = targetX - frame.gazeX
    let dy = targetY - frame.gazeY
    let magnitude = hypot(dx, dy)
    return CharacterMotionFrame(
      gazeX: targetX,
      gazeY: targetY,
      angle: frame.angle,
      eyeWidth: frame.eyeWidth,
      eyeHeight: frame.eyeHeight,
      motionEnergy: max(frame.motionEnergy, min(0.35, magnitude * 1.2)),
      directionX: magnitude > 0.000_001 ? dx / magnitude : frame.directionX,
      directionY: magnitude > 0.000_001 ? dy / magnitude : frame.directionY,
      blink: frame.blink
    )
  }

  /// Conversational gaze is mostly held, with purposeful brief aversion instead of
  /// continuous wandering. This keeps speaking/listening eyes alive without noise.
  private static func conversationalGazeFrame(elapsed: Double) -> CharacterMotionFrame {
    let local = positiveRemainder(elapsed, modulus: 3.45)
    let front = boundedTarget(x: 0, y: -0.025, angle: 0, shape: .tall)
    let away = boundedTarget(x: -0.14, y: -0.10, angle: -0.035, shape: .tall)
    let other = boundedTarget(x: 0.10, y: -0.04, angle: 0.025, shape: .tall)

    if local < 1.15 { return hold(front) }
    if local < 1.25 {
      return transition(
        from: front, to: away, elapsed: local - 1.15, moveDuration: 0.067, settleDuration: 0.033)
    }
    if local < 1.88 { return hold(away) }
    if local < 1.98 {
      return transition(
        from: away, to: front, elapsed: local - 1.88, moveDuration: 0.067, settleDuration: 0.033)
    }
    if local < 2.72 { return hold(front) }
    if local < 2.81 {
      return transition(
        from: front, to: other, elapsed: local - 2.72, moveDuration: 0.060, settleDuration: 0.030)
    }
    if local < 3.08 { return hold(other) }
    if local < 3.17 {
      return transition(
        from: other, to: front, elapsed: local - 3.08, moveDuration: 0.060, settleDuration: 0.030)
    }
    return hold(front)
  }

  private static func ambientBlinkAmount(elapsed: Double) -> Double {
    // Emotion-specific blinks remain authoritative via max(). This layer only keeps
    // otherwise-static states alive. The interval pattern is deterministic so pose
    // sampling remains pure and reproducible.
    let cycle = positiveRemainder(elapsed, modulus: 16.4)
    let windows: [(Double, Double)] = [(3.15, 0.17), (7.62, 0.18), (11.05, 0.16), (15.12, 0.20)]
    for (start, duration) in windows where cycle >= start && cycle < start + duration {
      let local = cycle - start
      let half = duration * 0.42
      if local <= half {
        return smoothStep(local / max(half, 0.000_001))
      }
      return 1 - smoothStep((local - half) / max(duration - half, 0.000_001))
    }
    return 0
  }

  private static func visualChannel(
    for state: CharacterState, animationElapsed: Double
  ) -> CharacterVisualChannel {
    let expired = state.animation.map { animationElapsed >= $0.animation.duration } ?? false
    return state.visualChannel == .animation && expired
      ? state.fallbackVisualChannelExcludingAnimation : state.visualChannel
  }

  private static func sampleEyes(
    state: CharacterState,
    activityElapsed: Double,
    expressionElapsed: Double,
    animationElapsed: Double,
    reduceMotion: Bool,
    projection: CharacterProjection,
    profile: CharacterMotionProfile
  ) -> EyeSample {
    let animationTime = validatedTime(animationElapsed)
    let effectiveVisualChannel = visualChannel(for: state, animationElapsed: animationTime)
    let ownsActivity = effectiveVisualChannel == .activity
    let ownsEmotion = effectiveVisualChannel == .emotion
    let ownsAnimation = effectiveVisualChannel == .animation
    let expression: CharacterExpressionSample
    if let emotion = state.emotion {
      expression =
        ownsEmotion
        ? CharacterExpression.sample(
          emotion: emotion,
          elapsed: expressionElapsed,
          reduceMotion: reduceMotion,
          profile: profile
        )
        : stabilizedExpression(emotion: emotion, profile: profile)
    } else {
      expression = .neutral
    }
    let animation = CharacterAnimationMotion.sample(
      animation: ownsAnimation ? state.animation : nil,
      elapsed: animationTime,
      reduceMotion: reduceMotion,
      profile: profile
    )
    let sampledBase = baseGazeFrame(
      state: state,
      elapsed: activityElapsed,
      reduceMotion: reduceMotion,
      profile: profile
    )
    let useFullActivityGrammar = ownsActivity || effectiveVisualChannel == .neutral
    let base = useFullActivityGrammar ? sampledBase : gazeOnlyFrame(sampledBase)
    let frame = composedEyeFrame(
      base: base,
      state: state,
      activityElapsed: activityElapsed,
      expression: expression,
      animation: animation
    )
    return EyeSample(
      visualChannel: effectiveVisualChannel,
      expression: expression,
      animation: animation,
      frame: frame,
      eyes: eyePair(frame: frame, expression: expression, projection: projection)
    )
  }

  // Live eyes and trail samples use the same ordering. A visual owner controls
  // choreography, not the host's attention or writing-focus authority.
  private static func composedEyeFrame(
    base: CharacterMotionFrame,
    state: CharacterState,
    activityElapsed: Double,
    expression: CharacterExpressionSample,
    animation: CharacterAnimationSample
  ) -> CharacterMotionFrame {
    let blinked = withBlink(
      base,
      amount: max(base.blink, ambientBlinkAmount(elapsed: activityElapsed))
    )
    let expressed = applyExpression(blinked, activity: state.activity, expression: expression)
    let attended = applyAttention(state.attention, to: expressed)
    return applyAnimation(attended, animation: animation)
  }

  private static func stabilizedExpression(
    emotion: CharacterEmotion,
    profile: CharacterMotionProfile
  ) -> CharacterExpressionSample {
    let sample = CharacterExpression.sample(
      emotion: emotion,
      elapsed: 0.52,
      reduceMotion: false,
      profile: profile
    )
    return CharacterExpressionSample(
      gazeX: 0,
      gazeY: 0,
      // A stabilized expression must not erase the independent conversational gaze.
      idleMotionScale: 1,
      eyeWidthScale: sample.eyeWidthScale,
      eyeHeightScale: sample.eyeHeightScale,
      leftEyeScale: sample.leftEyeScale,
      rightEyeScale: sample.rightEyeScale,
      leftAngle: sample.leftAngle,
      rightAngle: sample.rightAngle,
      blink: 0,
      mouthCurvature: sample.mouthCurvature,
      mouthOpenness: sample.mouthOpenness,
      mouthWidth: sample.mouthWidth,
      mouthSkew: sample.mouthSkew,
      surface: .identity,
      trailBoost: 0,
      eyeContours: sample.eyeContours
    )
  }

  private static func applyExpression(
    _ frame: CharacterMotionFrame,
    activity: CharacterActivity,
    expression: CharacterExpressionSample
  ) -> CharacterMotionFrame {
    let idleScale: Double
    if case .idle = activity {
      idleScale = expression.idleMotionScale
    } else {
      idleScale = 1
    }

    return CharacterMotionFrame(
      gazeX: clamp(frame.gazeX * idleScale + expression.gazeX, lower: -0.23, upper: 0.23),
      gazeY: clamp(frame.gazeY * idleScale + expression.gazeY, lower: -0.24, upper: 0.24),
      angle: frame.angle,
      eyeWidth: frame.eyeWidth * expression.eyeWidthScale,
      eyeHeight: frame.eyeHeight * expression.eyeHeightScale,
      motionEnergy: clamp(
        max(frame.motionEnergy * max(idleScale, 0.25), expressionMotionEnergy(for: expression)), lower: 0,
        upper: 1),
      directionX: frame.directionX,
      directionY: frame.directionY,
      blink: max(frame.blink, expression.blink)
    )
  }

  private static func applyAnimation(
    _ frame: CharacterMotionFrame,
    animation: CharacterAnimationSample
  ) -> CharacterMotionFrame {
    CharacterMotionFrame(
      gazeX: clamp(frame.gazeX + animation.gazeX, lower: -0.23, upper: 0.23),
      gazeY: clamp(frame.gazeY + animation.gazeY, lower: -0.24, upper: 0.24),
      angle: clamp(frame.angle + animation.angle, lower: -0.16, upper: 0.16),
      eyeWidth: frame.eyeWidth * animation.eyeWidthScale,
      eyeHeight: frame.eyeHeight * animation.eyeHeightScale,
      motionEnergy: clamp(max(frame.motionEnergy, animation.trailBoost), lower: 0, upper: 1),
      directionX: animation.gazeX == 0 ? frame.directionX : animation.gazeX.sign == .minus ? -1 : 1,
      directionY: animation.gazeY == 0 ? frame.directionY : animation.gazeY.sign == .minus ? -1 : 1,
      blink: max(frame.blink, animation.blink)
    )
  }

  private static func composeSurface(
    _ lhs: CharacterSurfacePose,
    _ rhs: CharacterSurfacePose
  ) -> CharacterSurfacePose {
    CharacterSurfacePose(
      offsetX: lhs.offsetX + rhs.offsetX,
      offsetY: lhs.offsetY + rhs.offsetY,
      scaleX: lhs.scaleX * rhs.scaleX,
      scaleY: lhs.scaleY * rhs.scaleY,
      angle: lhs.angle + rhs.angle
    )
  }

  private static func expressionMotionEnergy(for expression: CharacterExpressionSample) -> Double {
    let mouthEnergy = expression.mouthOpenness * 0.55
    let gazeEnergy = min(1, abs(expression.gazeX) + abs(expression.gazeY)) * 0.9
    return max(0, max(mouthEnergy, gazeEnergy * 0.45))
  }

  private static func eyePair(
    frame: CharacterMotionFrame,
    expression: CharacterExpressionSample,
    projection: CharacterProjection
  ) -> CharacterEyePairPose {
    CharacterEyePairPose(
      left: eyePose(
        frame: frame,
        side: .left,
        expression: expression,
        projection: projection
      ),
      right: eyePose(
        frame: frame,
        side: .right,
        expression: expression,
        projection: projection
      )
    )
  }

  private enum EyeSide {
    case left
    case right
  }

  private static func eyePose(
    frame: CharacterMotionFrame,
    side: EyeSide,
    expression: CharacterExpressionSample,
    projection: CharacterProjection
  ) -> CharacterEyePose {
    let horizontalMotion = abs(frame.directionX) * frame.motionEnergy
    let verticalMotion = abs(frame.directionY) * frame.motionEnergy

    let widthDeformation =
      1
      + frame.motionEnergy * 0.08
      + horizontalMotion * 0.20
      - verticalMotion * 0.06
    let heightDeformation =
      1
      + frame.motionEnergy * 0.08
      + verticalMotion * 0.22
      - horizontalMotion * 0.10

    let widthBeforeBlink = frame.eyeWidth * widthDeformation
    let heightBeforeBlink = frame.eyeHeight * heightDeformation
    let blink = clamp(frame.blink, lower: 0, upper: 1)
    let blinkWidth = max(frame.eyeWidth, CharacterEyeShape.wide.width * 0.88)
    var width = mix(widthBeforeBlink, blinkWidth, amount: blink)
    var height = mix(heightBeforeBlink, 0.040, amount: blink)

    let centerX: Double
    let angleOffset: Double
    let sideScale: Double
    switch side {
    case .left:
      centerX = 0.34 + frame.gazeX
      angleOffset = expression.leftAngle
      sideScale = expression.leftEyeScale
    case .right:
      centerX = 0.66 + frame.gazeX
      angleOffset = expression.rightAngle
      sideScale = expression.rightEyeScale
    }

    width *= sideScale
    height *= sideScale

    let foreshortening = eyeForeshortening(centerX: centerX, projection: projection)
    let heightForeshortening = mix(1, foreshortening, amount: 0.35)
    width *= foreshortening
    height *= heightForeshortening
    let unblinkedWidth = widthBeforeBlink * sideScale * foreshortening
    let unblinkedHeight = heightBeforeBlink * sideScale * heightForeshortening

    return CharacterEyePose(
      centerX: centerX,
      centerY: 0.50 + frame.gazeY * 0.96,
      width: width,
      height: height,
      angle: frame.angle + angleOffset + frame.directionX * frame.motionEnergy * 0.045,
      unblinkedWidth: unblinkedWidth,
      unblinkedHeight: unblinkedHeight,
      blink: blink
    )
  }

  private static func eyeForeshortening(
    centerX: Double,
    projection: CharacterProjection
  ) -> Double {
    guard projection == .softSphere else { return 1 }

    let faceRadius = 0.48
    let neutralRadius = 0.16
    let radial = abs(centerX - 0.5)
    guard radial > neutralRadius else { return 1 }

    let clampedRadial = min(radial, faceRadius * 0.98)
    let neutralDepth = sqrt(max(0.000_001, 1 - pow(neutralRadius / faceRadius, 2)))
    let depth = sqrt(max(0.000_001, 1 - pow(clampedRadial / faceRadius, 2)))
    return clamp(depth / neutralDepth, lower: 0.58, upper: 1)
  }

  private static func idleFrame(elapsed: Double) -> CharacterMotionFrame {
    let duration = CharacterMotionReference.idleCycleDuration
    let local = positiveRemainder(elapsed, modulus: duration)
    let variant = CharacterPresentationVariation.index(
      elapsed: elapsed, interval: duration,
      count: CharacterPresentationVariation.idleShapes.count,
      seed: CharacterPresentationVariation.idleSeed)
    let side = variant.isMultiple(of: 2) ? -1.0 : 1.0
    let scale = CharacterPresentationVariation.idleGazeScales[variant]
    let shapes = CharacterPresentationVariation.idleShapes[variant]
    let front = CharacterGazeTarget.front
    let large = boundedTarget(
      x: side * 0.20 * scale, y: -0.23 * scale, angle: side * 0.055, shape: shapes[0])
    let circle = boundedTarget(
      x: -side * 0.15 * scale, y: -0.035, angle: -side * 0.065, shape: shapes[1])
    let tiny = boundedTarget(
      x: -side * 0.11 * scale, y: 0.18 * scale, angle: -side * 0.030, shape: shapes[2])
    let tall = boundedTarget(
      x: side * 0.14 * scale, y: -0.13 * scale, angle: side * 0.050, shape: shapes[3])
    let wide = boundedTarget(
      x: side * 0.18 * scale, y: 0.19 * scale, angle: side * 0.085, shape: shapes[4])

    var cursor =
      CharacterMotionReference.idleFrontHold
      + CharacterPresentationVariation.idleHoldOffsets[variant]
    if local < cursor { return hold(front) }

    if let value = segment(
      local: local, cursor: &cursor, from: front, to: large,
      move: CharacterMotionReference.largeMove, settle: CharacterMotionReference.largeSettle,
      holdDuration: CharacterMotionReference.largeHold)
    {
      return value
    }
    if let value = segment(
      local: local, cursor: &cursor, from: large, to: circle,
      move: CharacterMotionReference.circleMove, settle: CharacterMotionReference.circleSettle,
      holdDuration: CharacterMotionReference.circleHold)
    {
      return value
    }
    if let value = segment(
      local: local, cursor: &cursor, from: circle, to: tiny,
      move: CharacterMotionReference.tinyMove, settle: CharacterMotionReference.tinySettle,
      holdDuration: CharacterMotionReference.tinyHold)
    {
      return value
    }
    if let value = segment(
      local: local, cursor: &cursor, from: tiny, to: tall, move: CharacterMotionReference.tallMove,
      settle: CharacterMotionReference.tallSettle, holdDuration: CharacterMotionReference.tallHold)
    {
      return value
    }
    if let value = segment(
      local: local, cursor: &cursor, from: tall, to: wide, move: CharacterMotionReference.wideMove,
      settle: CharacterMotionReference.wideSettle, holdDuration: CharacterMotionReference.wideHold)
    {
      return value
    }

    let returnDuration = CharacterMotionReference.returnMove + CharacterMotionReference.returnSettle
    if local < cursor + returnDuration {
      return transition(
        from: wide, to: front, elapsed: local - cursor,
        moveDuration: CharacterMotionReference.returnMove,
        settleDuration: CharacterMotionReference.returnSettle)
    }
    return hold(front)
  }

  private static func segment(
    local: Double,
    cursor: inout Double,
    from: CharacterGazeTarget,
    to: CharacterGazeTarget,
    move: Double,
    settle: Double,
    holdDuration: Double
  ) -> CharacterMotionFrame? {
    let transitionDuration = move + settle
    if local < cursor + transitionDuration {
      return transition(
        from: from, to: to, elapsed: local - cursor, moveDuration: move, settleDuration: settle)
    }
    cursor += transitionDuration
    if local < cursor + holdDuration { return hold(to) }
    cursor += holdDuration
    return nil
  }

  private static func thinkingFrame(elapsed: Double) -> CharacterMotionFrame {
    let front = CharacterGazeTarget.front
    let left = boundedTarget(x: -0.18, y: -0.18, angle: -0.050, shape: .large)
    let right = boundedTarget(x: 0.16, y: -0.07, angle: 0.055, shape: .circle)
    let initialDuration = 0.080 + 0.040
    if elapsed < initialDuration {
      return transition(
        from: front, to: left, elapsed: elapsed, moveDuration: 0.080, settleDuration: 0.040)
    }

    let local = positiveRemainder(elapsed - initialDuration, modulus: 1.48)
    if local < 0.56 { return hold(left) }
    if local < 0.665 {
      return transition(
        from: left, to: right, elapsed: local - 0.56, moveDuration: 0.070, settleDuration: 0.035)
    }
    if local < 1.12 { return hold(right) }
    if local < 1.23 {
      return transition(
        from: right, to: left, elapsed: local - 1.12, moveDuration: 0.075, settleDuration: 0.035)
    }
    return hold(left)
  }

  private static func activeWritingFrame(
    elapsed: Double,
    base: CharacterGazeTarget
  ) -> CharacterMotionFrame {
    let initialDuration = 0.075 + 0.040
    if elapsed < initialDuration {
      return transition(
        from: .front, to: base, elapsed: elapsed, moveDuration: 0.075, settleDuration: 0.040)
    }

    let cycleDuration = 0.98
    let cycleTime = elapsed - initialDuration
    let pairedPhase = positiveRemainder(cycleTime, modulus: cycleDuration * 2)
    let local = positiveRemainder(cycleTime, modulus: cycleDuration)
    let side = pairedPhase < cycleDuration ? 1.0 : -1.0
    let circle = boundedTarget(
      x: base.x + side * 0.14, y: base.y - 0.08, angle: side * 0.055, shape: .circle)
    let tiny = boundedTarget(
      x: base.x - side * 0.11, y: base.y + 0.045, angle: -side * 0.040, shape: .tinyCircle)

    if local < 0.30 { return hold(base) }
    if local < 0.400 {
      return transition(
        from: base, to: circle, elapsed: local - 0.30, moveDuration: 0.065, settleDuration: 0.035)
    }
    if local < 0.54 { return hold(circle) }
    if local < 0.640 {
      return transition(
        from: circle, to: tiny, elapsed: local - 0.54, moveDuration: 0.065, settleDuration: 0.035)
    }
    if local < 0.77 { return hold(tiny) }
    if local < 0.870 {
      return transition(
        from: tiny, to: base, elapsed: local - 0.77, moveDuration: 0.065, settleDuration: 0.035)
    }
    return hold(base)
  }

  private static func cancellingFrame(elapsed: Double) -> CharacterMotionFrame {
    let target = boundedTarget(x: -0.12, y: 0.18, angle: -0.040, shape: .wide)
    let transitionDuration = 0.080 + 0.045
    var frame =
      elapsed < transitionDuration
      ? transition(
        from: .front, to: target, elapsed: elapsed, moveDuration: 0.080, settleDuration: 0.045)
      : hold(target)

    let blinkStart = 0.050
    if elapsed >= blinkStart, elapsed < blinkStart + CharacterMotionReference.blinkDuration {
      frame = withBlink(frame, amount: blinkAmount(elapsed: elapsed - blinkStart))
    }
    return frame
  }

  private static func terminalFrame(
    elapsed: Double,
    target: CharacterGazeTarget,
    moveDuration: Double,
    settleDuration: Double
  ) -> CharacterMotionFrame {
    let duration = moveDuration + settleDuration
    guard elapsed < duration else { return hold(target) }
    return transition(
      from: .front, to: target, elapsed: elapsed, moveDuration: moveDuration,
      settleDuration: settleDuration)
  }

  private static func transition(
    from: CharacterGazeTarget,
    to: CharacterGazeTarget,
    elapsed: Double,
    moveDuration: Double,
    settleDuration: Double
  ) -> CharacterMotionFrame {
    let deltaX = to.x - from.x
    let deltaY = to.y - from.y
    let magnitude = max(hypot(deltaX, deltaY), 0.000_001)
    let directionX = deltaX / magnitude
    let directionY = deltaY / magnitude

    let acquire = CharacterGazeTarget(
      x: to.x - deltaX * 0.055,
      y: to.y - deltaY * 0.055,
      angle: to.angle - (to.angle - from.angle) * 0.045,
      shape: CharacterEyeShape(
        width: to.shape.width - (to.shape.width - from.shape.width) * 0.035,
        height: to.shape.height - (to.shape.height - from.shape.height) * 0.035
      )
    )

    if elapsed < moveDuration {
      let progress = clamp(elapsed / moveDuration, lower: 0, upper: 1)
      let eased = easeOutQuint(progress)
      let energy = pow(sin(progress * .pi), 0.42)
      return frame(
        from: from, to: acquire, amount: eased, motionEnergy: energy, directionX: directionX,
        directionY: directionY)
    }

    let settleProgress = clamp(
      (elapsed - moveDuration) / max(settleDuration, 0.000_001), lower: 0, upper: 1)
    let eased = easeOutCubic(settleProgress)
    return frame(
      from: acquire, to: to, amount: eased, motionEnergy: 0.46 * (1 - eased),
      directionX: directionX, directionY: directionY)
  }

  private static func frame(
    from: CharacterGazeTarget,
    to: CharacterGazeTarget,
    amount: Double,
    motionEnergy: Double,
    directionX: Double,
    directionY: Double
  ) -> CharacterMotionFrame {
    CharacterMotionFrame(
      gazeX: mix(from.x, to.x, amount: amount),
      gazeY: mix(from.y, to.y, amount: amount),
      angle: mix(from.angle, to.angle, amount: amount),
      eyeWidth: mix(from.shape.width, to.shape.width, amount: amount),
      eyeHeight: mix(from.shape.height, to.shape.height, amount: amount),
      motionEnergy: clamp(motionEnergy, lower: 0, upper: 1),
      directionX: directionX,
      directionY: directionY,
      blink: 0
    )
  }

  private static func hold(_ target: CharacterGazeTarget) -> CharacterMotionFrame {
    CharacterMotionFrame(
      gazeX: target.x,
      gazeY: target.y,
      angle: target.angle,
      eyeWidth: target.shape.width,
      eyeHeight: target.shape.height,
      motionEnergy: 0,
      directionX: 0,
      directionY: 0,
      blink: 0
    )
  }

  private static func withBlink(_ frame: CharacterMotionFrame, amount: Double)
    -> CharacterMotionFrame
  {
    CharacterMotionFrame(
      gazeX: frame.gazeX,
      gazeY: frame.gazeY,
      angle: frame.angle,
      eyeWidth: frame.eyeWidth,
      eyeHeight: frame.eyeHeight,
      motionEnergy: frame.motionEnergy,
      directionX: frame.directionX,
      directionY: frame.directionY,
      blink: amount
    )
  }

  private static func blinkAmount(elapsed: Double) -> Double {
    if elapsed < CharacterMotionReference.blinkClose {
      return smoothStep(elapsed / CharacterMotionReference.blinkClose)
    }
    let afterClose = elapsed - CharacterMotionReference.blinkClose
    if afterClose < CharacterMotionReference.blinkHold { return 1 }
    let opening = afterClose - CharacterMotionReference.blinkHold
    guard opening < CharacterMotionReference.blinkOpen else { return 0 }
    return 1 - smoothStep(opening / CharacterMotionReference.blinkOpen)
  }

  private static func reducedMotionFrame(for activity: CharacterActivity) -> CharacterMotionFrame {
    switch activity {
    case .idle:
      hold(.front)
    case .userWriting(let focus):
      hold(userWritingTarget(focus: focus))
    case .agentThinking:
      hold(boundedTarget(x: -0.12, y: -0.13, angle: -0.035, shape: .large))
    case .agentWriting(_, let progress):
      hold(agentWritingTarget(progress: progress.value))
    case .agentCancelling:
      withBlink(hold(boundedTarget(x: -0.10, y: 0.16, angle: -0.035, shape: .wide)), amount: 0.72)
    case .success:
      hold(boundedTarget(x: 0, y: -0.06, angle: 0, shape: .large))
    case .failure:
      hold(boundedTarget(x: 0, y: 0.18, angle: 0, shape: .wide))
    case .cancelled:
      hold(boundedTarget(x: -0.08, y: 0.12, angle: -0.030, shape: .tinyCircle))
    }
  }

  private static func userWritingTarget(focus: CharacterPoint) -> CharacterGazeTarget {
    boundedTarget(
      x: (focus.x - 0.5) * 0.30,
      y: 0.16 + (focus.y - 0.5) * 0.12,
      angle: -0.030,
      shape: .tall
    )
  }

  private static func agentWritingTarget(progress: Double) -> CharacterGazeTarget {
    boundedTarget(
      x: (progress - 0.5) * 0.26,
      y: 0.19,
      angle: -0.025 + progress * 0.050,
      shape: .tall
    )
  }

  private static func boundedTarget(
    x: Double,
    y: Double,
    angle: Double,
    shape: CharacterEyeShape
  ) -> CharacterGazeTarget {
    CharacterGazeTarget(
      x: clamp(x, lower: -0.21, upper: 0.21),
      y: clamp(y, lower: -0.23, upper: 0.22),
      angle: clamp(angle, lower: -0.10, upper: 0.10),
      shape: shape
    )
  }

  private static func writingPhase(
    for activity: CharacterActivity,
    elapsed: Double,
    reduceMotion: Bool
  ) -> Double {
    switch activity {
    case .userWriting:
      reduceMotion ? 0.62 : CharacterPeriodicArithmetic.phase(time: elapsed, rate: 1.65, period: 1)
    case .agentWriting(_, let progress):
      progress.value
    default:
      0
    }
  }

  private static func writingMotionPhase(
    for activity: CharacterActivity,
    elapsed: Double,
    reduceMotion: Bool
  ) -> Double {
    guard writingIsVisible(for: activity) else { return 0 }
    return reduceMotion ? 0.62 : CharacterPeriodicArithmetic.phase(time: elapsed, rate: 1.65, period: 1)
  }

  private static func writingProgress(for activity: CharacterActivity) -> Double? {
    switch activity {
    case .agentWriting(_, let progress):
      progress.value
    default:
      nil
    }
  }

  private static func writingIsVisible(for activity: CharacterActivity) -> Bool {
    switch activity {
    case .userWriting, .agentWriting:
      true
    default:
      false
    }
  }

  private static func mouthPose(
    requested: Bool,
    communication: CharacterCommunication,
    activity: CharacterActivity,
    expression: CharacterExpressionSample,
    elapsed: Double,
    reduceMotion: Bool,
    voiceLevelOverride: Double?
  ) -> CharacterMouthPose {
    let outputWritingVisible = activity.isAgentWriting
    guard requested else {
      return CharacterMouthPose(
        visible: false,
        opacity: 0,
        curvature: 0,
        openness: 0,
        width: expression.mouthWidth,
        skew: 0
      )
    }

    // Agent output can articulate independently from host communication. Listening audio
    // never drives this mouth; the writing activity supplies its own output choreography.
    let effectiveCommunication: CharacterCommunication =
      !communication.requestsMouth && outputWritingVisible ? .chat : communication

    let speechOpen: Double
    switch effectiveCommunication {
    case .silent, .listening:
      speechOpen = 0
    case .chat:
      if reduceMotion {
        speechOpen = 0.22
      } else {
        speechOpen = CharacterPresentationVariation.speechOpenness(elapsed: elapsed)
      }
    case .voice(let level):
      let presentedLevel = clamp(voiceLevelOverride ?? level.value, lower: 0, upper: 1)
      speechOpen = 0.10 + presentedLevel * 0.78
    }

    let runtimeWidth = clamp(expression.mouthWidth, lower: 0.25, upper: 1)
    let runtimeSkew = clamp(expression.mouthSkew, lower: -1, upper: 1)
    let runtimeOpenness = max(expression.mouthOpenness, speechOpen)

    return CharacterMouthPose(
      visible: true,
      opacity: 1,
      curvature: expression.mouthCurvature,
      // Authored expression and host speech own articulation.
      openness: clamp(runtimeOpenness, lower: 0, upper: 1),
      width: runtimeWidth,
      skew: runtimeSkew
    )
  }

  /// Activity contributes presentation-only motion. Semantic activity remains reducer-owned;
  /// this sampler is deterministic and does not create another state machine.
  private static func activitySurfacePose(
    activity: CharacterActivity,
    elapsed: Double,
    reduceMotion: Bool,
    intensity: Double
  ) -> CharacterSurfacePose {
    guard !reduceMotion, intensity > 0 else { return .identity }
    let t = validatedTime(elapsed)
    switch activity {
    case .agentThinking:
      let hover = CharacterPeriodicArithmetic.sine(time: t, rate: 2.15)
      let drift = CharacterPeriodicArithmetic.sine(time: t, rate: 1.07, offset: 0.8)
      return CharacterSurfacePose(
        offsetY: (-0.008 + hover * 0.010) * intensity,
        scaleX: 1 - hover * 0.004 * intensity,
        scaleY: 1 + hover * 0.006 * intensity,
        angle: drift * 0.018 * intensity
      )
    case .userWriting, .agentWriting:
      let angle = t * 2 * Double.pi / 0.98
      let stroke = angle.isFinite ? sin(angle)
        : CharacterPeriodicArithmetic.sine(time: t, rate: 2 * Double.pi / 0.98)
      return CharacterSurfacePose(
        offsetX: stroke * 0.003 * intensity,
        offsetY: -abs(stroke) * 0.004 * intensity,
        angle: stroke * 0.006 * intensity
      )
    case .agentCancelling:
      let tremor = CharacterPeriodicArithmetic.sine(time: t, rate: 22) * 0.006 * intensity
      return CharacterSurfacePose(offsetX: tremor, angle: tremor * 0.8)
    case .success:
      let pulse = max(0, sin(min(t, 0.7) * Double.pi / 0.7))
      return CharacterSurfacePose(
        offsetY: -pulse * 0.018 * intensity,
        scaleX: 1 + pulse * 0.014 * intensity,
        scaleY: 1 + pulse * 0.022 * intensity
      )
    case .failure:
      let settle = min(1, t / 0.55)
      return CharacterSurfacePose(
        offsetY: settle * 0.012 * intensity,
        scaleX: 1 + settle * 0.006 * intensity,
        scaleY: 1 - settle * 0.012 * intensity
      )
    case .cancelled:
      return CharacterSurfacePose(angle: -0.018 * intensity)
    case .idle:
      return .identity
    }
  }

  /// Scales idle gaze and eye grammar while preserving blink and direction.
  private static func scaledIdleFrame(
    _ frame: CharacterMotionFrame,
    strength: Double
  ) -> CharacterMotionFrame {
    let s = clamp(strength, lower: 0, upper: 1.5)
    return CharacterMotionFrame(
      gazeX: frame.gazeX * s,
      gazeY: frame.gazeY * s,
      angle: frame.angle * s,
      eyeWidth: mix(CharacterEyeShape.tall.width, frame.eyeWidth, amount: min(s, 1)),
      eyeHeight: mix(CharacterEyeShape.tall.height, frame.eyeHeight, amount: min(s, 1)),
      motionEnergy: clamp(frame.motionEnergy * s, lower: 0, upper: 1),
      directionX: frame.directionX,
      directionY: frame.directionY,
      blink: frame.blink
    )
  }

  private static func mix(_ start: Double, _ end: Double, amount: Double) -> Double {
    start + (end - start) * amount
  }

  private static func smoothStep(_ value: Double) -> Double {
    let t = clamp(value, lower: 0, upper: 1)
    return t * t * (3 - 2 * t)
  }

  private static func easeOutCubic(_ value: Double) -> Double {
    let t = clamp(value, lower: 0, upper: 1)
    return 1 - pow(1 - t, 3)
  }

  private static func easeOutQuint(_ value: Double) -> Double {
    let t = clamp(value, lower: 0, upper: 1)
    return 1 - pow(1 - t, 5)
  }

  private static func positiveRemainder(_ value: Double, modulus: Double) -> Double {
    let result = value.truncatingRemainder(dividingBy: modulus)
    return result >= 0 ? result : result + modulus
  }

  private static func validatedTime(_ value: Double) -> Double {
    precondition(value.isFinite && value >= 0, "elapsed time must be finite and non-negative")
    return value
  }

  private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
  }

}

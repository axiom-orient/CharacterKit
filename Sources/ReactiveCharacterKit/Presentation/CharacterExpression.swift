import Foundation

enum CharacterExpression {
  private enum ReactionTiming {
    static let snapDelay = 0.02
    static let fearDuration = 0.36
    static let angerDuration = 0.30
    static let recoilDelay = 0.04
    static let recoilDuration = 0.42
  }

  static func sample(
    emotion: CharacterEmotion?, elapsed: Double, reduceMotion: Bool,
    profile: CharacterMotionProfile
  ) -> CharacterExpressionSample {
    var sample = baseSample(
      emotion: emotion, elapsed: elapsed, reduceMotion: reduceMotion, profile: profile)
    sample.eyeContours = CharacterEyeContourPair.neutral.blended(
      to: eyeContours(for: emotion),
      amount: min(1, profile.expressiveness))
    return sample
  }

  /// One emotion-to-silhouette owner for every renderer and motion profile.
  /// Tempo and amplification change acting, never which eye shape an emotion means.
  private static func eyeContours(for emotion: CharacterEmotion?) -> CharacterEyeContourPair {
    func pair(_ left: CharacterEyeContour, _ right: CharacterEyeContour? = nil)
      -> CharacterEyeContourPair
    { .init(left: left, right: right ?? left) }
    switch emotion {
    case nil: return .neutral
    case .joy: return pair(.init(crescent: 1, widthScale: 1.30, heightScale: 0.92))
    case .affection: return pair(.init(widthScale: 1.36, heightScale: 0.68, heart: 1))
    case .gratitude: return pair(.init(crescent: 1, widthScale: 1.13, heightScale: 0.52))
    case .interest:
      return pair(
        .init(widthScale: 0.90, heightScale: 0.96),
        .init(lidCompression: 0.14, widthScale: 0.86, heightScale: 0.94))
    case .surprise: return pair(.init(ellipse: 1, widthScale: 1.42, circular: 1))
    case .calmTrust: return pair(.init(lidCompression: 0.30, widthScale: 1.25, heightScale: 0.48))
    case .sadness: return pair(.init(lidCompression: 0.12, widthScale: 0.84, heightScale: 1.02))
    case .anxietyFear:
      return pair(
        .init(ellipse: 1, widthScale: 0.90, heightScale: 0.97),
        .init(ellipse: 1, widthScale: 0.83, heightScale: 0.94))
    case .angerIrritation:
      return pair(
        .init(lidCompression: 0.48, innerPinch: 0.94, widthScale: 1.25, heightScale: 0.80))
    case .disgustContempt:
      return pair(
        .init(lidCompression: 0.94, innerPinch: 0.58, widthScale: 1.25, heightScale: 0.62),
        .init(lidCompression: 0.10, innerPinch: 0.05, widthScale: 0.85, heightScale: 0.82))
    case .shameGuilt:
      return pair(
        .init(lidCompression: 0.24, widthScale: 0.76, heightScale: 0.80),
        .init(lidCompression: 0.36, widthScale: 0.76, heightScale: 0.80))
    case .fatigueBurden:
      return pair(.init(lidCompression: 0.65, widthScale: 1.28, heightScale: 0.72))
    }
  }

  private static func baseSample(
    emotion: CharacterEmotion?,
    elapsed: Double,
    reduceMotion: Bool,
    profile: CharacterMotionProfile
  ) -> CharacterExpressionSample {
    guard let emotion else { return .neutral }

    if reduceMotion {
      return reducedSample(emotion: emotion, profile: profile)
    }

    let t = max(0, elapsed)
    let intensity = profile.expressiveness
    let entry = entryBeat(t)
    let settle = settleBeat(t)

    switch emotion {
    case .joy:
      // Anticipation, two unequal laughs, then a readable hold. No metronomic hopping.
      let laughPhase = t.truncatingRemainder(dividingBy: 3.6)
      let bounce =
        window(laughPhase, start: 0.08, peak: 0.23, end: 0.48)
        + 0.58 * window(laughPhase, start: 0.58, peak: 0.73, end: 0.96)
      let lift = bounce * 0.043
      let tilt = CharacterPeriodicArithmetic.sine(time: t, rate: 2.3) * bounce * 0.024
      let blink = periodicBlink(elapsed: t + 0.62, period: 4.8, duration: 0.15)
      return make(
        gazeY: -0.022 - entry.snap * 0.040 + bounce * -0.010,
        idleMotionScale: 0.28,
        eyeWidthScale: 1.10 + entry.snap * 0.18 + bounce * 0.09,
        eyeHeightScale: 0.50 - entry.anticipation * 0.11 + entry.snap * 0.06 - bounce * 0.08,
        leftAngle: -0.060,
        rightAngle: 0.060,
        blink: blink,
        mouthCurvature: 0.94,
        mouthOpenness: 0.42 + entry.snap * 0.10 + bounce * 0.16,
        mouthWidth: 0.94,
        surface: .init(
          offsetY: (-entry.snap * 0.028 + settle * 0.008 - lift) * intensity,
          scaleX: 1 + (entry.anticipation * 0.060 - entry.snap * 0.032 + bounce * 0.018)
            * intensity,
          scaleY: 1 + (-entry.anticipation * 0.078 + entry.snap * 0.066 - bounce * 0.012)
            * intensity,
          angle: tilt * intensity
        ),
        trailBoost: max(entry.snap * 0.78, bounce * 0.36) * intensity,
        intensity: intensity
      )

    case .affection:
      let heartPhase = t.truncatingRemainder(dividingBy: 4.2)
      let heartBeat =
        window(heartPhase, start: 0.10, peak: 0.26, end: 0.48)
        + 0.65 * window(heartPhase, start: 0.58, peak: 0.73, end: 0.94)
      let blink = periodicBlink(elapsed: t + 0.20, period: 3.6, duration: 0.28)
      let sway = oneShotPulse(elapsed: t, delay: 0.10, duration: 1.10)
      return make(
        gazeX: sway * 0.018,
        gazeY: 0.010,
        idleMotionScale: 0.18,
        eyeWidthScale: 0.98 + heartBeat * 0.12,
        eyeHeightScale: 0.72 + heartBeat * 0.10,
        leftEyeScale: 0.96,
        rightEyeScale: 1.02,
        leftAngle: -0.040,
        rightAngle: 0.040,
        blink: blink,
        mouthCurvature: 0.78,
        mouthOpenness: 0.015 + heartBeat * 0.018,
        mouthWidth: 0.74,
        surface: .init(
          offsetX: sway * 0.012 * intensity,
          offsetY: -heartBeat * 0.006 * intensity,
          scaleX: 1 + heartBeat * 0.025 * intensity,
          scaleY: 1 + heartBeat * 0.025 * intensity,
          angle: sway * 0.035 * intensity
        ),
        trailBoost: entry.snap * 0.25 * intensity,
        intensity: intensity
      )

    case .gratitude:
      // One bow acknowledges the event; a persistent emotion does not repeat the bow.
      let descent = smoothStep(min(1, max(0, (t - 0.12) / 0.38)))
      let release = smoothStep(min(1, max(0, (t - 0.72) / 0.55)))
      let bow = descent * (1 - release)
      let sparkle = positivePulse(elapsed: t + 0.25, period: 2.35, width: 0.18)
      let blink = periodicBlink(elapsed: t + 0.30, period: 4.3, duration: 0.22)
      return make(
        gazeX: -0.012,
        gazeY: 0.072 + bow * 0.055,
        idleMotionScale: 0.12,
        eyeWidthScale: 0.96,
        eyeHeightScale: 0.67 - bow * 0.12,
        leftAngle: -0.060,
        rightAngle: 0.060,
        blink: blink,
        mouthCurvature: 0.60,
        mouthOpenness: 0.010 + sparkle * 0.012,
        mouthWidth: 0.62,
        surface: .init(
          offsetY: bow * 0.048 * intensity,
          scaleX: 1 - bow * 0.010 * intensity,
          scaleY: 1 - bow * 0.040 * intensity
        ),
        trailBoost: sparkle * 0.10 * intensity,
        intensity: intensity
      )

    case .interest:
      let scan = dart(elapsed: t, period: 1.56)
      let ping = positivePulse(elapsed: t + 0.22, period: 1.56, width: 0.17)
      return make(
        gazeX: scan * 0.090,
        gazeY: -0.058 - ping * 0.022,
        idleMotionScale: 0.10,
        eyeWidthScale: 1.12 + ping * 0.14,
        eyeHeightScale: 1.20 + ping * 0.18,
        leftEyeScale: 1.08,
        rightEyeScale: 0.94,
        leftAngle: -0.026,
        rightAngle: 0.012,
        mouthCurvature: 0.12,
        mouthOpenness: 0.055 + ping * 0.18,
        mouthWidth: 0.56,
        surface: .init(
          offsetX: scan * 0.018 * intensity,
          offsetY: -ping * 0.010 * intensity,
          scaleX: 1 + ping * 0.018 * intensity,
          scaleY: 1 + ping * 0.032 * intensity,
          // Curiosity is staged as a whole-head question: readable tilt plus a small searching arc.
          angle: (-0.108 + scan * 0.034) * intensity
        ),
        trailBoost: (abs(scan) * 0.45 + ping * 0.30) * intensity,
        intensity: intensity
      )

    case .surprise:
      let shock = entry.snap
      return make(
        gazeY: -0.058 - shock * 0.020,
        idleMotionScale: 0.08,
        eyeWidthScale: 1.30 + shock * 0.22,
        eyeHeightScale: 1.38 + shock * 0.34,
        mouthOpenness: 0.84 + shock * 0.14,
        mouthWidth: 0.38,
        surface: .init(
          offsetY: -shock * 0.028 * intensity,
          scaleX: 1 + (entry.anticipation * 0.050 - shock * 0.040) * intensity,
          scaleY: 1 + (-entry.anticipation * 0.085 + shock * 0.100) * intensity
        ),
        trailBoost: shock * 0.90 * intensity,
        intensity: intensity
      )

    case .calmTrust:
      let blink = periodicBlink(elapsed: t + 0.8, period: 4.4, duration: 0.30)
      return make(
        idleMotionScale: 0, eyeWidthScale: 0.98, eyeHeightScale: 0.78,
        blink: blink, mouthCurvature: 0.42, mouthOpenness: 0.015, mouthWidth: 0.68,
        intensity: intensity)

    case .sadness:
      let sink = oneShotPulse(elapsed: t, delay: 0.06, duration: 0.70)
      let sigh = positivePulse(elapsed: t + 0.7, period: 3.25, width: 0.22)
      let blink = periodicBlink(elapsed: t + 0.55, period: 4.7, duration: 0.26)
      return make(
        gazeX: -sink * 0.012,
        gazeY: 0.112 + sink * 0.046 + sigh * 0.014,
        idleMotionScale: 0.08,
        eyeWidthScale: 0.92,
        eyeHeightScale: 0.70 - sigh * 0.06,
        leftAngle: -0.125,
        rightAngle: 0.125,
        blink: blink,
        mouthCurvature: -0.94,
        mouthWidth: 0.70,
        surface: .init(
          offsetY: (sink * 0.040 + sigh * 0.015) * intensity,
          scaleX: 1 + (sink * 0.025 + sigh * 0.012) * intensity,
          scaleY: 1 - (sink * 0.050 + sigh * 0.018) * intensity,
          angle: -sink * 0.024 * intensity
        ),
        trailBoost: entry.snap * 0.15 * intensity,
        intensity: intensity
      )

    case .anxietyFear:
      let panic = oneShotPulse(
        elapsed: t, delay: ReactionTiming.snapDelay, duration: ReactionTiming.fearDuration)
      let jitterGate = smoothStep(panic)
      let jitterX = (CharacterPeriodicArithmetic.sine(time: t, rate: 25)
        + CharacterPeriodicArithmetic.sine(time: t, rate: 39, offset: 0.8)) * 0.012 * jitterGate
      let jitterY = CharacterPeriodicArithmetic.sine(time: t, rate: 31, offset: 0.4) * 0.007 * jitterGate
      let blink = periodicBlink(elapsed: t + 0.25, period: 2.3, duration: 0.17)
      return make(
        gazeX: 0.046 + jitterX,
        gazeY: -0.014 + jitterY,
        idleMotionScale: 0.06,
        eyeWidthScale: 1.20 + panic * 0.12,
        eyeHeightScale: 1.16 + panic * 0.24,
        leftEyeScale: 1.06,
        rightEyeScale: 0.96,
        leftAngle: 0.036,
        rightAngle: -0.032,
        blink: blink,
        mouthCurvature: -0.10,
        mouthOpenness: 0.30 + panic * 0.18,
        mouthWidth: 0.56,
        surface: .init(
          offsetX: jitterX * 0.86 * intensity,
          offsetY: jitterY * 0.78 * intensity,
          scaleX: 1 + panic * 0.024 * intensity,
          scaleY: 1 + panic * 0.042 * intensity,
          angle: jitterX * 0.72 * intensity
        ),
        trailBoost: (panic * 0.65 + jitterGate * 0.25) * intensity,
        intensity: intensity
      )

    case .angerIrritation:
      let snap = oneShotPulse(
        elapsed: t, delay: ReactionTiming.snapDelay, duration: ReactionTiming.angerDuration)
      let shake = CharacterPeriodicArithmetic.sine(time: t, rate: 28) * snap
      return make(
        gazeX: shake * 0.012,
        gazeY: 0.022,
        idleMotionScale: 0.05,
        eyeWidthScale: 1.14 + snap * 0.06,
        eyeHeightScale: 0.56 - snap * 0.055,
        leftAngle: 0.200,
        rightAngle: -0.200,
        mouthCurvature: -0.74,
        mouthOpenness: 0.015 + snap * 0.055,
        mouthWidth: 0.88,
        surface: .init(
          offsetX: shake * 0.018 * intensity,
          offsetY: -snap * 0.014 * intensity,
          scaleX: 1 + snap * 0.055 * intensity,
          scaleY: 1 - snap * 0.040 * intensity,
          angle: shake * 0.022 * intensity
        ),
        trailBoost: snap * 0.70 * intensity,
        intensity: intensity
      )

    case .disgustContempt:
      let recoil = oneShotPulse(
        elapsed: t, delay: ReactionTiming.recoilDelay, duration: ReactionTiming.recoilDuration)
      return make(
        gazeX: 0.060 + recoil * 0.024,
        gazeY: 0.024,
        idleMotionScale: 0.08,
        eyeWidthScale: 1.00,
        eyeHeightScale: 0.68,
        leftEyeScale: 0.72,
        rightEyeScale: 1.04,
        leftAngle: 0.155,
        rightAngle: -0.030,
        mouthCurvature: -0.16,
        mouthOpenness: 0.025,
        mouthWidth: 0.68,
        mouthSkew: 0.78,
        surface: .init(
          offsetX: recoil * -0.030 * intensity,
          offsetY: recoil * 0.010 * intensity,
          scaleX: 1 - recoil * 0.022 * intensity,
          scaleY: 1 + recoil * 0.010 * intensity,
          angle: recoil * -0.040 * intensity
        ),
        trailBoost: recoil * 0.22 * intensity,
        intensity: intensity
      )

    case .shameGuilt:
      let shrink = oneShotPulse(elapsed: t, delay: 0.08, duration: 0.75)
      let peek = positivePulse(elapsed: t + 1.25, period: 3.20, width: 0.16)
      let blink = periodicBlink(elapsed: t + 0.50, period: 3.8, duration: 0.24)
      return make(
        gazeX: -0.110 + peek * 0.060,
        gazeY: 0.180 - peek * 0.034,
        idleMotionScale: 0.04,
        eyeWidthScale: 0.88 + peek * 0.05,
        eyeHeightScale: 0.68 + peek * 0.04,
        leftEyeScale: 0.90,
        rightEyeScale: 0.96,
        leftAngle: -0.070,
        rightAngle: 0.060,
        blink: blink,
        mouthCurvature: -0.24,
        mouthWidth: 0.48,
        mouthSkew: -0.18,
        surface: .init(
          offsetY: shrink * 0.030 * intensity,
          scaleX: 1 - shrink * 0.052 * intensity,
          scaleY: 1 - shrink * 0.060 * intensity,
          angle: -0.024 * intensity
        ),
        trailBoost: peek * 0.12 * intensity,
        intensity: intensity
      )

    case .fatigueBurden:
      let yawn = positivePulse(elapsed: t + 0.42, period: 5.6, width: 0.22)
      let blink = periodicBlink(elapsed: t, period: 2.55, duration: 0.46)
      return make(
        gazeX: -0.020,
        gazeY: 0.152 + yawn * 0.016,
        idleMotionScale: 0.03,
        eyeWidthScale: 1.00,
        eyeHeightScale: 0.52 - yawn * 0.08,
        leftEyeScale: 0.90,
        rightEyeScale: 1.00,
        leftAngle: -0.040,
        rightAngle: 0.022,
        blink: blink,
        mouthCurvature: -0.12,
        mouthOpenness: 0.10 + yawn * 0.72,
        mouthWidth: 0.48 - yawn * 0.08,
        surface: .init(
          offsetY: (0.014 + yawn * 0.022) * intensity,
          scaleX: 1 + yawn * 0.018 * intensity,
          scaleY: 1 - yawn * 0.034 * intensity,
          angle: yawn * 0.025 * intensity
        ),
        trailBoost: 0,
        intensity: intensity
      )
    }
  }

  private static func reducedSample(
    emotion: CharacterEmotion,
    profile: CharacterMotionProfile
  ) -> CharacterExpressionSample {
    // Reduce Motion removes time-varying choreography, not semantic facial readability.
    // Keep the static expression at the selected profile strength (capped at the authored 1× pose)
    // while reduced samples remain deterministic and free of bounce/jitter/hover.
    let i = min(profile.expressiveness, 1)
    switch emotion {
    case .joy:
      return make(
        eyeWidthScale: 1.12, eyeHeightScale: 0.50, leftAngle: -0.06, rightAngle: 0.06,
        mouthCurvature: 1.00, mouthOpenness: 0.42, mouthWidth: 0.96, intensity: i)
    case .affection:
      return make(
        eyeWidthScale: 0.98, eyeHeightScale: 0.72, leftEyeScale: 0.96, rightEyeScale: 1.02,
        leftAngle: -0.04, rightAngle: 0.04, blink: 0.08, mouthCurvature: 0.74,
        mouthOpenness: 0.03, mouthWidth: 0.78, intensity: i)
    case .gratitude:
      return make(
        gazeY: 0.09, eyeWidthScale: 0.96, eyeHeightScale: 0.67,
        leftAngle: -0.06, rightAngle: 0.06, blink: 0.06,
        mouthCurvature: 0.56, mouthOpenness: 0.02, mouthWidth: 0.66, intensity: i)
    case .interest:
      return make(
        gazeY: -0.06, eyeWidthScale: 1.12, eyeHeightScale: 1.20,
        leftEyeScale: 1.08, rightEyeScale: 0.94, leftAngle: -0.026, rightAngle: 0.012,
        mouthCurvature: 0.12, mouthOpenness: 0.10, mouthWidth: 0.56,
        surface: .init(angle: -0.108 * i), intensity: i)
    case .surprise:
      return make(
        gazeY: -0.06, eyeWidthScale: 1.34, eyeHeightScale: 1.52, mouthOpenness: 0.90,
        mouthWidth: 0.38, intensity: i)
    case .calmTrust:
      return make(
        eyeWidthScale: 0.98, eyeHeightScale: 0.78, blink: 0.05, mouthCurvature: 0.42,
        mouthOpenness: 0.015, mouthWidth: 0.68, intensity: i)
    case .sadness:
      return make(
        gazeY: 0.13, eyeWidthScale: 0.92, eyeHeightScale: 0.70,
        leftAngle: -0.125, rightAngle: 0.125, blink: 0.08,
        mouthCurvature: -0.94, mouthWidth: 0.70, intensity: i)
    case .anxietyFear:
      return make(
        gazeX: 0.05, eyeWidthScale: 1.20, eyeHeightScale: 1.20,
        leftEyeScale: 1.06, rightEyeScale: 0.96, leftAngle: 0.036, rightAngle: -0.032,
        blink: 0.06, mouthCurvature: -0.10, mouthOpenness: 0.34, mouthWidth: 0.56, intensity: i)
    case .angerIrritation:
      return make(
        gazeY: 0.02, eyeWidthScale: 1.14, eyeHeightScale: 0.56, leftAngle: 0.20,
        rightAngle: -0.20, mouthCurvature: -0.74, mouthOpenness: 0.03, mouthWidth: 0.88,
        intensity: i)
    case .disgustContempt:
      return make(
        gazeX: 0.06, gazeY: 0.02, eyeHeightScale: 0.68, leftEyeScale: 0.72, rightEyeScale: 1.04,
        leftAngle: 0.155, rightAngle: -0.03, mouthCurvature: -0.16, mouthOpenness: 0.025,
        mouthWidth: 0.68, mouthSkew: 0.78, intensity: i)
    case .shameGuilt:
      return make(
        gazeX: -0.11, gazeY: 0.18, eyeWidthScale: 0.88, eyeHeightScale: 0.68,
        leftEyeScale: 0.90, rightEyeScale: 0.96, leftAngle: -0.07, rightAngle: 0.06,
        blink: 0.10, mouthCurvature: -0.24, mouthWidth: 0.48, mouthSkew: -0.18,
        intensity: i)
    case .fatigueBurden:
      return make(
        gazeX: -0.02, gazeY: 0.155, eyeHeightScale: 0.52, leftEyeScale: 0.90, blink: 0.34,
        mouthCurvature: -0.12, mouthOpenness: 0.24, mouthWidth: 0.48,
        surface: .init(offsetY: 0.006 * i), intensity: i)
    }
  }

  private static func make(
    gazeX: Double = 0,
    gazeY: Double = 0,
    idleMotionScale: Double = 0.1,
    eyeWidthScale: Double = 1,
    eyeHeightScale: Double = 1,
    leftEyeScale: Double = 1,
    rightEyeScale: Double = 1,
    leftAngle: Double = 0,
    rightAngle: Double = 0,
    blink: Double = 0,
    mouthCurvature: Double = 0,
    mouthOpenness: Double = 0,
    mouthWidth: Double = 0.68,
    mouthSkew: Double = 0,
    surface: CharacterSurfacePose = .identity,
    trailBoost: Double = 0,
    intensity: Double
  ) -> CharacterExpressionSample {
    CharacterExpressionSample(
      gazeX: gazeX * intensity,
      gazeY: gazeY * intensity,
      idleMotionScale: idleMotionScale,
      eyeWidthScale: max(0.05, mix(1, eyeWidthScale, amount: intensity)),
      eyeHeightScale: max(0.05, mix(1, eyeHeightScale, amount: intensity)),
      leftEyeScale: max(0.05, mix(1, leftEyeScale, amount: intensity)),
      rightEyeScale: max(0.05, mix(1, rightEyeScale, amount: intensity)),
      leftAngle: leftAngle * intensity,
      rightAngle: rightAngle * intensity,
      blink: blink * min(1, max(0.45, intensity)),
      mouthCurvature: mouthCurvature * intensity,
      mouthOpenness: mouthOpenness * intensity,
      mouthWidth: mix(0.68, mouthWidth, amount: intensity),
      mouthSkew: mouthSkew * intensity,
      surface: surface,
      trailBoost: trailBoost
    )
  }

  private struct EntryBeat {
    let anticipation: Double
    let snap: Double
  }

  private static func entryBeat(_ elapsed: Double) -> EntryBeat {
    let anticipation = window(elapsed, start: 0, peak: 0.055, end: 0.100)
    let snap = window(elapsed, start: 0.070, peak: 0.120, end: 0.240)
    return EntryBeat(anticipation: anticipation, snap: snap)
  }

  private static func settleBeat(_ elapsed: Double) -> Double {
    window(elapsed, start: 0.22, peak: 0.32, end: 0.48)
  }

  private static func dart(elapsed: Double, period: Double) -> Double {
    let local = positiveRemainder(elapsed + 0.20, modulus: period)
    if local < 0.075 { return easeOutQuint(local / 0.075) }
    if local < 0.34 { return 1 }
    if local < 0.42 { return mix(1, -0.80, amount: easeOutQuint((local - 0.34) / 0.08)) }
    if local < 0.72 { return -0.80 }
    if local < 0.80 { return mix(-0.80, 0, amount: easeOutQuint((local - 0.72) / 0.08)) }
    return 0
  }

  private static func oneShotPulse(elapsed: Double, delay: Double, duration: Double) -> Double {
    guard elapsed >= delay, elapsed <= delay + duration else { return 0 }
    let x = (elapsed - delay) / max(duration, 0.000_001)
    return sin(x * .pi)
  }

  private static func periodicBlink(elapsed: Double, period: Double, duration: Double) -> Double {
    let local = positiveRemainder(elapsed, modulus: period)
    guard local < duration else { return 0 }
    let half = duration / 2
    if local <= half { return smoothStep(local / max(half, 0.000_001)) }
    return 1 - smoothStep((local - half) / max(half, 0.000_001))
  }

  private static func positivePulse(elapsed: Double, period: Double, width: Double) -> Double {
    let local = positiveRemainder(elapsed, modulus: period) / max(period, 0.000_001)
    guard local < width else { return 0 }
    let normalized = local / max(width, 0.000_001)
    return smoothStep(sin(normalized * .pi))
  }

  private static func window(_ value: Double, start: Double, peak: Double, end: Double) -> Double {
    guard value >= start, value <= end else { return 0 }
    if value <= peak {
      return smoothStep((value - start) / max(peak - start, 0.000_001))
    }
    return 1 - smoothStep((value - peak) / max(end - peak, 0.000_001))
  }

  private static func smoothStep(_ value: Double) -> Double {
    let t = min(max(value, 0), 1)
    return t * t * (3 - 2 * t)
  }

  private static func easeOutQuint(_ value: Double) -> Double {
    let t = min(max(value, 0), 1)
    return 1 - pow(1 - t, 5)
  }

  private static func mix(_ start: Double, _ end: Double, amount: Double) -> Double {
    start + (end - start) * amount
  }

  private static func positiveRemainder(_ value: Double, modulus: Double) -> Double {
    let result = value.truncatingRemainder(dividingBy: modulus)
    return result >= 0 ? result : result + modulus
  }
}

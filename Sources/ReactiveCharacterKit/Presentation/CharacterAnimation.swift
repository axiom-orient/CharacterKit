import Foundation

struct CharacterAnimationSample: Sendable, Equatable {
  let gazeX: Double
  let gazeY: Double
  let eyeWidthScale: Double
  let eyeHeightScale: Double
  let angle: Double
  let blink: Double
  let surface: CharacterSurfacePose
  let trailBoost: Double

  static let neutral = Self(
    gazeX: 0,
    gazeY: 0,
    eyeWidthScale: 1,
    eyeHeightScale: 1,
    angle: 0,
    blink: 0,
    surface: .identity,
    trailBoost: 0
  )
}

enum CharacterAnimationMotion {
  static func sample(
    animation: CharacterAnimationState?,
    elapsed: Double,
    reduceMotion: Bool,
    profile: CharacterMotionProfile
  ) -> CharacterAnimationSample {
    guard let animation else { return .neutral }
    if reduceMotion {
      return reducedSample(animation.animation, intensity: profile.expressiveness * 0.30)
    }

    let local = min(max(0, elapsed), animation.animation.duration)
    let i = profile.expressiveness

    switch animation.animation {
    case .bounce:
      let anticipate = window(local, start: 0.02, peak: 0.08, end: 0.14)
      let launch = window(local, start: 0.10, peak: 0.22, end: 0.38)
      let land = window(local, start: 0.35, peak: 0.44, end: 0.58)
      return .init(
        gazeX: 0,
        gazeY: -launch * 0.025,
        eyeWidthScale: 1 + anticipate * 0.06 - launch * 0.04 + land * 0.08,
        eyeHeightScale: 1 - anticipate * 0.10 + launch * 0.11 - land * 0.08,
        angle: 0,
        blink: 0,
        surface: .init(
          offsetY: (-launch * 0.065 + land * 0.022) * i,
          scaleX: 1 + (anticipate * 0.105 - launch * 0.050 + land * 0.105) * i,
          scaleY: 1 + (-anticipate * 0.125 + launch * 0.060 - land * 0.090) * i
        ),
        trailBoost: max(launch, land) * 0.85 * i
      )

    case .nod:
      let down1 = window(local, start: 0.08, peak: 0.20, end: 0.34)
      let down2 = window(local, start: 0.38, peak: 0.49, end: 0.62) * 0.65
      let nod = max(down1, down2)
      return .init(
        gazeX: 0,
        gazeY: nod * 0.065,
        eyeWidthScale: 1 + nod * 0.03,
        eyeHeightScale: 1 - nod * 0.08,
        angle: 0,
        blink: 0,
        surface: .init(
          offsetY: nod * 0.025 * i,
          scaleX: 1 + nod * 0.018 * i,
          scaleY: 1 - nod * 0.020 * i
        ),
        trailBoost: nod * 0.26 * i
      )

    case .shake:
      let gate = window(local, start: 0.05, peak: 0.20, end: 0.86)
      let wave = sin(local * 34.0) * gate
      return .init(
        gazeX: wave * 0.055,
        gazeY: 0,
        eyeWidthScale: 1 + abs(wave) * 0.045,
        eyeHeightScale: 1 - abs(wave) * 0.025,
        angle: wave * 0.045,
        blink: 0,
        surface: .init(
          offsetX: wave * 0.050 * i,
          scaleX: 1 + abs(wave) * 0.040 * i,
          scaleY: 1 - abs(wave) * 0.032 * i,
          angle: wave * 0.052 * i
        ),
        trailBoost: abs(wave) * 0.90 * i
      )

    case .peek:
      let direction = stableDirection(animation.id.rawValue)
      let anticipate = window(local, start: 0.04, peak: 0.12, end: 0.20)
      let peek = plateau(local, riseStart: 0.16, riseEnd: 0.28, fallStart: 1.22, fallEnd: 1.40)
      return .init(
        gazeX: direction * (peek * 0.15 - anticipate * 0.045),
        gazeY: -peek * 0.035,
        eyeWidthScale: 1 + peek * 0.07,
        eyeHeightScale: 1 + peek * 0.10,
        angle: direction * peek * 0.055,
        blink: 0,
        surface: .init(
          offsetX: direction * peek * 0.082 * i,
          offsetY: peek * -0.018 * i,
          scaleX: 1 - peek * 0.035 * i,
          scaleY: 1 + peek * 0.025 * i,
          angle: direction * peek * 0.050 * i
        ),
        trailBoost: max(anticipate, min(1, peek * 0.30)) * 0.45 * i
      )

    case .recoil:
      let hit = window(local, start: 0.04, peak: 0.13, end: 0.34)
      let settle = window(local, start: 0.30, peak: 0.46, end: 0.68)
      return .init(
        gazeX: 0,
        gazeY: -hit * 0.025 + settle * 0.010,
        eyeWidthScale: 1 + hit * 0.16,
        eyeHeightScale: 1 + hit * 0.22 - settle * 0.04,
        angle: 0,
        blink: 0,
        surface: .init(
          offsetY: hit * 0.075 * i - settle * 0.024 * i,
          scaleX: 1 - hit * 0.090 * i + settle * 0.040 * i,
          scaleY: 1 + hit * 0.145 * i - settle * 0.050 * i
        ),
        trailBoost: hit * 0.95 * i
      )

    case .celebrate:
      let hop1 = window(local, start: 0.04, peak: 0.20, end: 0.43)
      let hop2 = window(local, start: 0.52, peak: 0.68, end: 0.92) * 0.80
      let hop = max(hop1, hop2)
      let twist = sin(local * 8.5) * hop
      return .init(
        gazeX: twist * 0.035,
        gazeY: -hop * 0.040,
        eyeWidthScale: 1 + hop * 0.10,
        eyeHeightScale: 1 - hop * 0.05,
        angle: twist * 0.055,
        blink: 0,
        surface: .init(
          offsetX: twist * 0.032 * i,
          offsetY: -hop * 0.062 * i,
          scaleX: 1 + hop * 0.075 * i,
          scaleY: 1 + hop * 0.055 * i,
          angle: twist * 0.095 * i
        ),
        trailBoost: hop * 0.95 * i
      )

    case .sigh:
      let inhale = window(local, start: 0.05, peak: 0.32, end: 0.62)
      let exhale = window(local, start: 0.58, peak: 0.90, end: 1.42)
      return .init(
        gazeX: -exhale * 0.015,
        gazeY: exhale * 0.075,
        eyeWidthScale: 1 + inhale * 0.025,
        eyeHeightScale: 1 + inhale * 0.06 - exhale * 0.16,
        angle: 0,
        blink: exhale * 0.34,
        surface: .init(
          offsetY: exhale * 0.045 * i,
          scaleX: 1 + inhale * 0.030 * i + exhale * 0.048 * i,
          scaleY: 1 + inhale * 0.048 * i - exhale * 0.045 * i
        ),
        trailBoost: 0
      )

    case .blink:
      let blink = oneShotBlink(elapsed: local, start: 0.025, duration: 0.18)
      let winkBounce = window(local, start: 0.02, peak: 0.10, end: 0.22)
      return .init(
        gazeX: 0,
        gazeY: 0,
        eyeWidthScale: 1 + winkBounce * 0.025,
        eyeHeightScale: 1,
        angle: 0,
        blink: blink,
        surface: .init(
          scaleX: 1 + winkBounce * 0.008 * i,
          scaleY: 1 - winkBounce * 0.008 * i
        ),
        trailBoost: 0
      )
    }
  }

  private static func reducedSample(
    _ animation: CharacterAnimation,
    intensity: Double
  ) -> CharacterAnimationSample {
    switch animation {
    case .bounce, .celebrate, .recoil:
      return .init(
        gazeX: 0,
        gazeY: -0.015 * intensity,
        eyeWidthScale: 1.03,
        eyeHeightScale: 1.04,
        angle: 0,
        blink: 0,
        surface: .identity,
        trailBoost: 0
      )
    case .nod, .sigh:
      return .init(
        gazeX: 0,
        gazeY: 0.025 * intensity,
        eyeWidthScale: 1,
        eyeHeightScale: 0.95,
        angle: 0,
        blink: animation == .sigh ? 0.18 : 0,
        surface: .identity,
        trailBoost: 0
      )
    case .shake, .peek:
      return .init(
        gazeX: animation == .peek ? 0.035 * intensity : 0,
        gazeY: 0,
        eyeWidthScale: 1,
        eyeHeightScale: 1,
        angle: 0,
        blink: 0,
        surface: .identity,
        trailBoost: 0
      )
    case .blink:
      return .init(
        gazeX: 0,
        gazeY: 0,
        eyeWidthScale: 1,
        eyeHeightScale: 1,
        angle: 0,
        blink: 0.72,
        surface: .identity,
        trailBoost: 0
      )
    }
  }

  private static func window(_ value: Double, start: Double, peak: Double, end: Double) -> Double {
    guard value >= start, value <= end else { return 0 }
    if value <= peak {
      return smoothStep((value - start) / max(peak - start, 0.000_001))
    }
    return 1 - smoothStep((value - peak) / max(end - peak, 0.000_001))
  }

  private static func plateau(
    _ value: Double,
    riseStart: Double,
    riseEnd: Double,
    fallStart: Double,
    fallEnd: Double
  ) -> Double {
    if value < riseStart || value > fallEnd { return 0 }
    if value < riseEnd {
      return smoothStep((value - riseStart) / max(riseEnd - riseStart, 0.000_001))
    }
    if value <= fallStart { return 1 }
    return 1 - smoothStep((value - fallStart) / max(fallEnd - fallStart, 0.000_001))
  }

  private static func stableDirection(_ rawValue: String) -> Double {
    let sum = rawValue.utf8.reduce(0) { ($0 + Int($1)) & 0xffff }
    return sum.isMultiple(of: 2) ? -1 : 1
  }

  private static func oneShotBlink(elapsed: Double, start: Double, duration: Double) -> Double {
    guard elapsed >= start, elapsed < start + duration else { return 0 }
    let local = elapsed - start
    let close = duration * 0.40
    if local <= close { return smoothStep(local / max(close, 0.000_001)) }
    return 1 - smoothStep((local - close) / max(duration - close, 0.000_001))
  }

  private static func smoothStep(_ value: Double) -> Double {
    let t = min(max(value, 0), 1)
    return t * t * (3 - 2 * t)
  }

}

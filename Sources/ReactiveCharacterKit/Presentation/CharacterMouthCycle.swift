import Foundation

/// Timing for the optional agent-output waveform.
enum CharacterMouthCycle {
  struct Sample {
    let outputWave: Bool
    let blendWeight: Double
  }
  static func sample(
    emotion: CharacterEmotion?,
    expressionElapsed: Double,
    communication: CharacterCommunication,
    communicationElapsed: Double,
    reduceMotion: Bool
  ) -> Sample {
    if reduceMotion { return stable(emotion == nil && communication.requestsMouth) }
    if let emotion {
      switch emotion {
      case .joy:
        return scheduled([0.20, 0.28, 0.38], elapsed: expressionElapsed)
      case .affection:
        return scheduled([0.56, 0.74], elapsed: expressionElapsed + 0.22)
      case .gratitude:
        return scheduled([0.58, 0.44], elapsed: expressionElapsed + 0.08)
      case .interest:
        return scheduled([0.42, 0.36], elapsed: expressionElapsed + 0.10, waveIndex: 1)
      case .surprise:
        return scheduled([0.54, 0.42], elapsed: expressionElapsed)
      case .calmTrust:
        return scheduled([0.78, 0.50], elapsed: expressionElapsed + 0.18)
      case .sadness:
        return scheduled([0.62, 1.18], elapsed: expressionElapsed)
      case .anxietyFear:
        return scheduled([0.28, 0.30, 0.40], elapsed: expressionElapsed + 0.04)
      case .angerIrritation:
        return scheduled([0.32, 0.28], elapsed: expressionElapsed + 0.06)
      case .disgustContempt:
        return scheduled([0.46, 0.62], elapsed: expressionElapsed + 0.18)
      case .shameGuilt:
        return scheduled([0.72, 0.42], elapsed: expressionElapsed + 0.12)
      case .fatigueBurden:
        return scheduled([0.92, 0.76], elapsed: expressionElapsed + 0.36)
      }
    }

    switch communication {
    case .silent, .listening: return stable(false)
    case .chat, .voice:
      return scheduled([0.36, 0.36, 0.36], elapsed: communicationElapsed, waveIndex: 0)
    }
  }

  private static func stable(_ outputWave: Bool) -> Sample {
    Sample(outputWave: outputWave, blendWeight: 1)
  }

  private static func scheduled(_ durations: [Double], elapsed: Double, waveIndex: Int? = nil) -> Sample {
    let durations = durations.map { max($0, 0.22) }
    let total = durations.reduce(0, +)
    let remainder = elapsed.truncatingRemainder(dividingBy: total)
    let phase = remainder >= 0 ? remainder : remainder + total
    var offset = 0.0
    for index in durations.indices {
      let duration = durations[index]
      guard phase < offset + duration || index == durations.count - 1 else { offset += duration; continue }
      let local = max(0, phase - offset)
      let build = min(0.17, duration - 0.045)
      let returning = min(0.062, max(0.045, duration - build))
      let hold = min(0.04, max(0, duration - build - returning))
      let returnStart = duration - returning - hold
      let amount: Double
      if local < build {
        let progress = min(1, max(0, local / max(build, 0.000_001)))
        amount = 1 - pow(1 - progress, 3)
      } else if local < returnStart { amount = 1 }
      else if local < duration - hold {
        amount = 1 - smooth((local - returnStart) / max(returning, 0.000_001))
      } else { return Sample(outputWave: false, blendWeight: 0) }
      return Sample(outputWave: index == waveIndex, blendWeight: smooth((amount - 0.90) / 0.10))
    }
    return Sample(outputWave: false, blendWeight: 0)
  }

  private static func smooth(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
  }
}

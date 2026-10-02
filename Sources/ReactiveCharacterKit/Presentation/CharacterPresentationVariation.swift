import Foundation

/// A bounded deterministic variation bank. It never consumes RNG state or mutates a semantic clock.
/// Seeds are internal authoring choices, not a new public session/identity contract.
enum CharacterPresentationVariation {
  static let bankSize = 4096
  static let idleSeed: UInt64 = 0x4155_5241
  static let speechSeed: UInt64 = 0x4348_4154
  static let syllableDuration = 0.36
  static let maximumAccents = 8
  static let idleHoldOffsets = [0.0, 0.22, -0.16, 0.35, -0.10, 0.08]
  static let idleGazeScales = [1.0, 0.66, 0.90, 0.72, 0.82, 0.58]
  static let idleShapes: [[CharacterEyeShape]] = [
    [.large, .circle, .tinyCircle, .tall, .wide],
    [.circle, .tall, .tinyCircle, .large, .wide],
    [.tall, .tinyCircle, .circle, .wide, .large],
    [.large, .tall, .wide, .circle, .tinyCircle],
    [.circle, .large, .tall, .tinyCircle, .wide],
    [.tall, .circle, .wide, .large, .tinyCircle],
  ]

  private struct SpeechBeat: Sendable {
    let height: Double
    let start: Double
    let peak: Double
    let hold: Double
    let end: Double
  }

  private static let speechBeats: [SpeechBeat] = [
    .init(height: 0.24, start: 0.03, peak: 0.22, hold: 0.32, end: 0.78),
    .init(height: 0.36, start: 0.08, peak: 0.30, hold: 0.48, end: 0.91),
    .init(height: 0.30, start: 0.02, peak: 0.20, hold: 0.38, end: 0.82),
    .init(height: 0.42, start: 0.05, peak: 0.26, hold: 0.42, end: 0.88),
    .init(height: 0.18, start: 0.12, peak: 0.34, hold: 0.46, end: 0.94),
    .init(height: 0.28, start: 0.04, peak: 0.24, hold: 0.36, end: 0.80),
  ]

  static func index(elapsed: Double, interval: Double, count: Int, seed: UInt64) -> Int {
    precondition(elapsed.isFinite && elapsed >= 0)
    precondition(interval.isFinite && interval > 0 && count > 0)
    let period = interval * Double(bankSize)
    precondition(period.isFinite && period > 0)
    // Bound the floating value BEFORE integer conversion (including elapsed == 1e20).
    let slot = UInt64(floor(elapsed.truncatingRemainder(dividingBy: period) / interval))
    var bits = slot &+ seed &+ 0x9E37_79B9_7F4A_7C15
    bits = (bits ^ (bits >> 30)) &* 0xBF58_476D_1CE4_E5B9
    bits = (bits ^ (bits >> 27)) &* 0x94D0_49BB_1331_11EB
    bits ^= bits >> 31
    return Int(bits % UInt64(count))
  }

  static func speechOpenness(elapsed: Double, seed: UInt64 = speechSeed) -> Double {
    let variant = index(elapsed: elapsed, interval: syllableDuration, count: 8, seed: seed)
    let phase = elapsed.truncatingRemainder(dividingBy: syllableDuration) / syllableDuration
    // Two silent beats and six asymmetric attack/hold/release shapes. Every boundary is closed.
    guard variant < speechBeats.count else { return 0.10 }
    let beat = speechBeats[variant]
    func ease(_ t: Double) -> Double {
      let p = min(1, max(0, t))
      return p * p * (3 - 2 * p)
    }
    let amount: Double
    if phase < beat.peak {
      amount = ease((phase - beat.start) / (beat.peak - beat.start))
    } else if phase < beat.hold {
      amount = 1
    } else {
      amount = 1 - ease((phase - beat.hold) / (beat.end - beat.hold))
    }
    return 0.10 + beat.height * amount
  }
}

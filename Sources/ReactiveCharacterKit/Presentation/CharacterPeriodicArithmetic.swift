import Foundation

/// Pure arithmetic for finite, nonnegative presentation time. Ordinary samples keep their
/// original operation order; only overflow uses a bounded periodic argument.
enum CharacterPeriodicArithmetic {
  static func phase(time: Double, rate: Double, period: Double) -> Double {
    let scaled = time * rate
    if scaled.isFinite {
      return scaled.truncatingRemainder(dividingBy: period)
    }
    return (time.truncatingRemainder(dividingBy: period / rate) * rate)
      .truncatingRemainder(dividingBy: period)
  }

  static func sine(time: Double, rate: Double, offset: Double = 0) -> Double {
    let angle = time * rate + offset
    if angle.isFinite { return sin(angle) }
    let turn = 2 * Double.pi
    let reduced = time.truncatingRemainder(dividingBy: turn / rate)
    return sin(reduced * rate + offset)
  }

  /// An overflowing tempo still represents a late sample. Saturating that nonperiodic
  /// time preserves completed entry/reaction gates instead of restarting them at zero.
  static func scaledTime(_ time: Double, rate: Double) -> Double {
    let scaled = time * rate
    return scaled.isFinite ? scaled : .greatestFiniteMagnitude
  }
}

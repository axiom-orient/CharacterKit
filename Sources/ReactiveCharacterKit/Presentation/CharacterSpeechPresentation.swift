import Foundation

/// One shared 45ms mouth retarget, sampled on the renderer's existing monotonic clock.
/// It never resets emotion, gaze, action or communication clocks.
struct CharacterSpeechPresentation: Sendable, Equatable {
  private struct Sample: Sendable, Equatable {
    let articulation: CharacterSpeechArticulation
    let weight: Double
    static let inactive = Self(articulation: .closed, weight: 0)
  }
  private var from = Sample.inactive
  private var target = Sample.inactive
  private var changedAt = 0.0

  mutating func update(_ value: CharacterSpeechArticulation?, at time: Double) {
    let next = Sample(articulation: value ?? .closed, weight: value == nil ? 0 : 1)
    guard next != target else { return }
    from = sample(at: time); target = next; changedAt = time
  }

  func apply(to pose: CharacterPose, at time: Double, reduceMotion: Bool) -> CharacterPose {
    let value = reduceMotion ? target : sample(at: time)
    return pose.applyingSpeechArticulation(value.articulation, weight: value.weight)
  }

  private func sample(at time: Double) -> Sample {
    let t = min(1, max(0, (time - changedAt) / 0.045))
    let eased = t * t * (3 - 2 * t)
    func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * eased }
    return Sample(articulation: .init(
      uncheckedOpenness: mix(from.articulation.openness, target.articulation.openness),
      width: mix(from.articulation.width, target.articulation.width)), weight: mix(from.weight, target.weight))
  }
}

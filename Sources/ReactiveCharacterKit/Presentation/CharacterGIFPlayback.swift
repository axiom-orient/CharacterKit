import Foundation

/// Presentation-only one-shot clock. Semantic state remains owned by the reducer and host.
struct CharacterGIFPlayback {
  struct Sample {
    let emotion: CharacterEmotion
    let elapsed: Double
    let opacity: Double
  }

  private struct Handoff {
    let sample: Sample
    let startedAt: Double
    let duration: Double
  }

  private(set) var emotion: CharacterEmotion?
  private var startedAt: Double
  private var handoff: Handoff?

  init(emotion: CharacterEmotion?, at time: Double) {
    self.emotion = emotion
    self.startedAt = time
  }

  mutating func update(
    emotion next: CharacterEmotion?, at time: Double,
    duration: (CharacterEmotion) -> Double, force: Bool = false
  ) {
    guard next != emotion || force else { return }
    let visible = sample(at: time, duration: duration)
    let current = visible.flatMap { $0.opacity > 0.000_001 ? $0 : nil }
    let returnDuration = current == nil ? 0 : 0.18
    handoff = current.map { Handoff(sample: $0, startedAt: time, duration: returnDuration) }
    emotion = next
    startedAt = time + returnDuration
  }

  func sample(at time: Double, duration: (CharacterEmotion) -> Double) -> Sample? {
    if let handoff, time < startedAt {
      let progress = min(1, max(0, (time - handoff.startedAt) / handoff.duration))
      return Sample(emotion: handoff.sample.emotion, elapsed: handoff.sample.elapsed,
        opacity: handoff.sample.opacity * (1 - progress))
    }
    guard let emotion else { return nil }
    let elapsed = max(0, time - startedAt)
    let total = duration(emotion)
    guard elapsed < total else { return nil }
    // All clips enter and leave through the very same neutral image, even when
    // generated boundary frames differ slightly between source GIFs.
    let edge = min(0.18, total / 4)
    let opacity = min(1, min(elapsed / edge, (total - elapsed) / edge))
    return Sample(emotion: emotion, elapsed: elapsed, opacity: max(0, opacity))
  }
}

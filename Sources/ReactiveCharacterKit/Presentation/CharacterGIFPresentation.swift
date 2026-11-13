import Foundation

/// Composes authored emotion time with the existing orthogonal pose clocks.
/// No semantic state or completion effects are manufactured by this adapter.
struct CharacterGIFPresentation {
  struct Sample {
    let emotion: CharacterGIFPlayback.Sample?
    let pose: CharacterPose
    let speechWeight: Double
  }

  private var poseSession: CharacterPresentationSession
  private var playback: CharacterGIFPlayback
  private var speechFrom: Double = 0
  private var speechTarget: Double
  private var speechChangedAt: Double

  init(state: CharacterState, at time: Double) {
    poseSession = CharacterPresentationSession(state: Self.liveState(state), at: time)
    playback = CharacterGIFPlayback(emotion: state.emotion, at: time)
    speechTarget = Self.speaks(state) ? 1 : 0
    speechChangedAt = time
    speechFrom = speechTarget
  }

  mutating func update(state next: CharacterState, at time: Double, reduceMotion: Bool,
    replay: Bool = false, duration: (CharacterEmotion) -> Double) {
    let target = Self.speaks(next) ? 1.0 : 0.0
    if target != speechTarget {
      speechFrom = speechWeight(at: time)
      speechTarget = target
      speechChangedAt = time
    }
    playback.update(emotion: next.emotion, at: time, duration: duration, force: replay)
    poseSession.update(state: Self.liveState(next), at: time, reduceMotion: reduceMotion,
      projection: .flat, motionProfile: .companion, transitionProfile: .soft)
  }

  func sample(at time: Double, reduceMotion: Bool, duration: (CharacterEmotion) -> Double) -> Sample {
    Sample(emotion: playback.sample(at: time, duration: duration),
      pose: poseSession.pose(at: time, reduceMotion: reduceMotion, projection: .flat,
        motionProfile: .companion),
      speechWeight: reduceMotion ? speechTarget : speechWeight(at: time))
  }

  private func speechWeight(at time: Double) -> Double {
    let t = min(1, max(0, (time - speechChangedAt) / 0.12))
    let eased = t * t * (3 - 2 * t)
    return speechFrom + (speechTarget - speechFrom) * eased
  }

  private static func liveState(_ state: CharacterState) -> CharacterState {
    // The GIF owns emotion geometry. Project only live input into the shared rig to
    // avoid applying a second emotional pose after the authored clip has returned.
    state.replacing(emotion: nil)
  }

  private static func speaks(_ state: CharacterState) -> Bool {
    switch state.communication {
    case .voice, .chat: return true
    case .listening, .silent:
      if case .agentWriting = state.activity { return true }
      return false
    }
  }
}

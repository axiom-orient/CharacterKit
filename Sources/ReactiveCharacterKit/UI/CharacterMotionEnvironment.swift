#if os(iOS) || os(macOS)
  import SwiftUI

  private struct CharacterReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
  }

  private struct CharacterSpeechKey: EnvironmentKey {
    static let defaultValue: CharacterSpeechArticulation? = nil
  }

  private struct CharacterBackgroundKey: EnvironmentKey {
    static let defaultValue = true
  }

  extension EnvironmentValues {
    var characterSpeechArticulation: CharacterSpeechArticulation? {
      get { self[CharacterSpeechKey.self] }
      set { self[CharacterSpeechKey.self] = newValue }
    }

    var characterBackgroundVisible: Bool {
      get { self[CharacterBackgroundKey.self] }
      set { self[CharacterBackgroundKey.self] = newValue }
    }

    var characterReducedMotion: Bool {
      get { self[CharacterReducedMotionKey.self] }
      set { self[CharacterReducedMotionKey.self] = newValue }
    }
  }

  extension View {
    /// Feeds timed speech geometry to vector, layered and GIF characters. The input
    /// is used only during chat/voice output; nil restores ordinary articulation.
    public func characterSpeechArticulation(_ value: CharacterSpeechArticulation?) -> some View {
      environment(\.characterSpeechArticulation, value)
    }

    /// Selects an authored stage or a transparent character without replacing the pose session.
    public func characterIncludesBackground(_ enabled: Bool) -> some View {
      environment(\.characterBackgroundVisible, enabled)
    }

    /// Adds a host preference without attempting to change the system setting.
    /// A host cannot disable the user's system Reduce Motion preference.
    public func characterReduceMotion(_ enabled: Bool) -> some View {
      environment(\.characterReducedMotion, enabled)
    }
  }
#endif

#if os(iOS) || os(macOS)
  import SwiftUI

  private struct CharacterReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
  }

  extension EnvironmentValues {
    var characterReducedMotion: Bool {
      get { self[CharacterReducedMotionKey.self] }
      set { self[CharacterReducedMotionKey.self] = newValue }
    }
  }

  extension View {
    /// Adds a host preference without overriding the user's system Reduce Motion setting.
    public func characterReduceMotion(_ enabled: Bool) -> some View {
      environment(\.characterReducedMotion, enabled)
    }
  }
#endif

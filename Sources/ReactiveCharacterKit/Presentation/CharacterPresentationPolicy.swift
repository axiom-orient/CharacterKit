import Foundation

/// Bounded presentation timing policy shared by semantic receipts and the transient session.
/// This is configuration owned by the SDK, not mutable runtime state.
enum CharacterPresentationPolicy {
  static let maximumGazeAmplitude = 0.42
  static let minimumGazeTransitionDuration = 0.070
  static let gazeTransitionDurationRange = 0.065
  static let maximumGazeTransitionDuration =
    minimumGazeTransitionDuration + gazeTransitionDurationRange
}

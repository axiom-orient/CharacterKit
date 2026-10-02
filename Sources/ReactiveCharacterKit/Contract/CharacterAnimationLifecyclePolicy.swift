/// Shared lifecycle budget for presentation handoff before a one-shot begins.
/// The host still owns the completion timer and reports its identity-guarded event.
enum CharacterAnimationLifecyclePolicy {
  static let maximumHandoffDuration: Double = 1.0
}

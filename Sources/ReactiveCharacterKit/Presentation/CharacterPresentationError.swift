/// Invalid presentation tuning. Semantic input and effect failures belong to the reducer contract.
public enum CharacterPresentationError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidMotionProfile(field: String, value: Double)
  case invalidTransitionProfile(field: String, value: Double)

  public var description: String {
    switch self {
    case .invalidMotionProfile(let field, let value):
      "motionProfile.\(field) is invalid: \(value)"
    case .invalidTransitionProfile(let field, let value):
      "transitionProfile.\(field) is invalid: \(value)"
    }
  }
}

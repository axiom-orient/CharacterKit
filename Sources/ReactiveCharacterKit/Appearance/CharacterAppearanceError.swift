/// Invalid appearance configuration. These failures never become semantic action dispositions.
public enum CharacterAppearanceError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalidRegion(name: String, reason: String)
  case invalidStyle(field: String, value: Double)
  case nonFiniteColorComponent(field: String, value: Double)
  case colorComponentOutOfRange(field: String, value: Double)

  public var description: String {
    switch self {
    case .invalidRegion(let name, let reason):
      "region \(name) is invalid: \(reason)"
    case .invalidStyle(let field, let value):
      "style.\(field) is invalid: \(value)"
    case .nonFiniteColorComponent(let field, let value):
      "\(field) must be finite; received \(value)"
    case .colorComponentOutOfRange(let field, let value):
      "\(field) must be in 0...1; received \(value)"
    }
  }
}

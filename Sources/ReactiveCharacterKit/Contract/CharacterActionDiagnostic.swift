import Foundation

/// Versioned observation of a reducer disposition, not state persistence or effect completion.
/// Codes and detail keys are stable; messages are for people. Numeric inputs are strings so
/// rejected NaN/infinity can be encoded with an ordinary JSONEncoder.
public struct CharacterActionDiagnostic: Sendable, Equatable, Encodable {
  public let schema = "characterkit.action-diagnostic/1"
  public let status: String
  public let code: String
  public let message: String
  public let details: [String: String]

  public init(disposition: CharacterDisposition) {
    switch disposition {
    case .accepted:
      status = "accepted"
      code = "accepted"
      message = "Action accepted"
      details = [:]
    case .ignored(let reason):
      status = "ignored"
      switch reason {
      case .duplicate:
        code = "duplicate"
        message = "Duplicate action"
        details = [:]
      case .staleTask(let expected, let received):
        code = "stale_task"
        message = "Task identity is stale"
        details = ["expected": expected.rawValue, "received": received.rawValue]
      case .noActiveTask(let received):
        code = "no_active_task"
        message = "No active task"
        details = ["received": received.rawValue]
      case .staleAnimation(let expected, let received):
        code = "stale_animation"
        message = "Animation identity is stale"
        details = ["expected": expected.rawValue, "received": received.rawValue]
      case .noActiveAnimation(let received):
        code = "no_active_animation"
        message = "No active animation"
        details = ["received": received.rawValue]
      case .eventNotApplicable:
        code = "event_not_applicable"
        message = "Event is not applicable"
        details = [:]
      }
    case .rejected(let error):
      status = "rejected"
      message = error.description
      switch error {
      case .emptyTaskID:
        code = "empty_task_id"
        details = [:]
      case .emptyAnimationID:
        code = "empty_animation_id"
        details = [:]
      case .animationIdentityConflict(let id):
        code = "animation_identity_conflict"
        details = ["id": id.rawValue]
      case .emptyFailureField(let field):
        code = "empty_failure_field"
        details = ["field": field]
      case .nonFiniteValue(let field, let value):
        code = "non_finite_value"
        details = ["field": field, "value": String(value)]
      case .outOfRange(let field, let value):
        code = "out_of_range"
        details = ["field": field, "value": String(value)]
      case .progressRegressed(let previous, let received):
        code = "progress_regressed"
        details = ["previous": String(previous), "received": String(received)]
      }
    }
  }
}

extension CharacterDisposition {
  public var diagnostic: CharacterActionDiagnostic { .init(disposition: self) }
}

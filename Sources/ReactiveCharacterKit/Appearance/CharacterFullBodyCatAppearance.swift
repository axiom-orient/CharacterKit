import Foundation

/// The source-art cat and its hand-drawn crayon counterpart use the same pose contract.
public enum CharacterFullBodyCatStyle: String, CaseIterable, Sendable {
  case felt, crayon
}

/// Authored poses of the full-body cat. Each pose uses its own face and joint anchors.
public enum CharacterFullBodyCatPose: String, CaseIterable, Sendable {
  case standing, waving, loaf, left, right, rear, upright, puffed, bellyUp, stretch
}

public enum CharacterFullBodyCatWalkDirection: String, CaseIterable, Sendable {
  case left, right

  var pose: CharacterFullBodyCatPose { self == .left ? .left : .right }
}

public enum CharacterFullBodyCatFacing: String, CaseIterable, Sendable {
  case left, right
}

/// One-shot body gestures. CharacterState continues to drive expression, gaze, and speech.
public enum CharacterFullBodyCatAction: String, CaseIterable, Sendable {
  case wave, walk, stretch, startle, showBelly, hop

  /// Nominal gesture duration in seconds. A felt pose can take longer to enter and return.
  public var duration: Double {
    switch self {
    case .wave: 1.40
    case .walk: 2.54
    case .stretch: 1.40
    case .startle: 1.20
    case .showBelly: 1.80
    case .hop: 1.22
    }
  }
}

/// Body input independent of changes to emotion, attention, and voice level.
public struct CharacterFullBodyCatAppearance: Equatable, Sendable {
  public let pose: CharacterFullBodyCatPose
  public let action: CharacterFullBodyCatAction?
  public let actionTrigger: UInt64
  public let style: CharacterFullBodyCatStyle
  public let walkDirection: CharacterFullBodyCatWalkDirection?
  public let puffDirection: CharacterFullBodyCatFacing

  /// Change the trigger to replay the same gesture. Clear the action to cancel it.
  /// When the gesture finishes, the renderer returns to the current resting pose.
  /// Walking defaults to the resting side profile, or right when there is no side profile.
  /// Puff direction applies to the puffed pose and the startle gesture.
  public init(
    pose: CharacterFullBodyCatPose = .standing,
    action: CharacterFullBodyCatAction? = nil,
    actionTrigger: UInt64 = 0,
    style: CharacterFullBodyCatStyle = .felt,
    walkDirection: CharacterFullBodyCatWalkDirection? = nil,
    puffDirection: CharacterFullBodyCatFacing = .left
  ) {
    self.pose = pose
    self.action = action
    self.actionTrigger = actionTrigger
    self.style = style
    self.walkDirection = walkDirection
    self.puffDirection = puffDirection
  }

  /// Full-motion duration in seconds, including any travel to and from the resting pose.
  public var actionDuration: Double? {
    action.map { CharacterFullBodyCatMotion.duration(for: $0, appearance: self) }
  }

  var walkingPose: CharacterFullBodyCatPose {
    walkDirection?.pose ?? (pose == .left ? .left : .right)
  }

  var cue: Cue? {
    action.map {
      Cue(action: $0, trigger: actionTrigger, walkDirection: $0 == .walk ? walkDirection : nil,
        puffDirection: $0 == .startle ? puffDirection : nil)
    }
  }

  struct Cue: Equatable, Sendable {
    let action: CharacterFullBodyCatAction
    let trigger: UInt64
    let walkDirection: CharacterFullBodyCatWalkDirection?
    let puffDirection: CharacterFullBodyCatFacing?
  }
}

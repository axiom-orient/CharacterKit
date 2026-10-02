import Foundation

/// Stable identity for one externally owned asynchronous agent operation.
public struct CharacterTaskID: Sendable, Hashable, CustomStringConvertible {
  public let rawValue: String

  public init(_ uuid: UUID) {
    rawValue = uuid.uuidString.lowercased()
  }

  public init(validating rawValue: String) throws {
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw CharacterError.emptyTaskID
    }
    self.rawValue = normalized
  }

  public var description: String { rawValue }
}

/// Stable identity for one explicitly requested presentation animation.
public struct CharacterAnimationID: Sendable, Hashable, CustomStringConvertible {
  public let rawValue: String

  public init(_ uuid: UUID) {
    rawValue = uuid.uuidString.lowercased()
  }

  public init(validating rawValue: String) throws {
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw CharacterError.emptyAnimationID
    }
    self.rawValue = normalized
  }

  public var description: String { rawValue }
}

/// Small semantic animation vocabulary usable by both humans and agents.
/// These are presentation intents, not UI gestures or renderer operations.
public enum CharacterAnimation: String, Sendable, Equatable, Hashable, CaseIterable {
  case bounce
  case nod
  case shake
  case peek
  case recoil
  case celebrate
  case sigh
  case blink

  /// Canonical one-shot duration. The reducer emits a completion scheduling effect
  /// so time remains outside semantic state.
  public var duration: Double {
    switch self {
    case .bounce: 0.82
    case .nod: 0.78
    case .shake: 0.92
    case .peek: 1.46
    case .recoil: 0.76
    case .celebrate: 1.42
    case .sigh: 1.82
    case .blink: 0.24
    }
  }
}

public struct CharacterAnimationState: Sendable, Equatable, Hashable {
  public let id: CharacterAnimationID
  public let animation: CharacterAnimation

  public init(id: CharacterAnimationID, animation: CharacterAnimation) {
    self.id = id
    self.animation = animation
  }
}

/// A normalized point in `0...1` space.
public struct CharacterPoint: Sendable, Hashable {
  public let x: Double
  public let y: Double

  public init(validatingX x: Double, y: Double) throws {
    guard x.isFinite, y.isFinite else {
      throw CharacterError.nonFiniteValue(
        field: "focus",
        value: x.isFinite ? y : x
      )
    }
    guard (0...1).contains(x), (0...1).contains(y) else {
      throw CharacterError.outOfRange(
        field: "focus",
        value: (0...1).contains(x) ? y : x
      )
    }
    self.x = x
    self.y = y
  }

  public static let center = Self(uncheckedX: 0.5, y: 0.5)

  private init(uncheckedX x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A validated monotonic progress value in `0...1`.
public struct CharacterProgress: Sendable, Hashable, Comparable {
  public let value: Double

  public init(validating value: Double) throws {
    guard value.isFinite else {
      throw CharacterError.nonFiniteValue(field: "progress", value: value)
    }
    guard (0...1).contains(value) else {
      throw CharacterError.outOfRange(field: "progress", value: value)
    }
    self.value = value
  }

  public static let zero = Self(unchecked: 0)
  public static let complete = Self(unchecked: 1)

  private init(unchecked value: Double) {
    self.value = value
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.value < rhs.value
  }
}

/// Normalized audio activity. Speaking drives articulation; listening never opens the mouth.
public struct CharacterVoiceLevel: Sendable, Hashable {
  public let value: Double

  public init(validating value: Double) throws {
    guard value.isFinite else {
      throw CharacterError.nonFiniteValue(field: "voiceLevel", value: value)
    }
    guard (0...1).contains(value) else {
      throw CharacterError.outOfRange(field: "voiceLevel", value: value)
    }
    self.value = value
  }

  public static let zero = Self(unchecked: 0)

  private init(unchecked value: Double) {
    self.value = value
  }
}

/// Preserves actionable failure context instead of collapsing it into a generic state.
public struct CharacterFailure: Sendable, Hashable {
  public let operation: String
  public let cause: String
  public let context: String?

  public init(
    operation: String,
    cause: String,
    context: String? = nil
  ) throws {
    let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedCause = cause.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedOperation.isEmpty else {
      throw CharacterError.emptyFailureField(field: "operation")
    }
    guard !normalizedCause.isEmpty else {
      throw CharacterError.emptyFailureField(field: "cause")
    }
    self.operation = normalizedOperation
    self.cause = normalizedCause
    self.context = context
  }
}

/// Semantic activity. This is independent from emotion and communication.
public enum CharacterActivity: Sendable, Equatable {
  case idle
  case userWriting(focus: CharacterPoint)
  case agentThinking(taskID: CharacterTaskID)
  case agentWriting(taskID: CharacterTaskID, progress: CharacterProgress)
  case agentCancelling(taskID: CharacterTaskID)
  case success(taskID: CharacterTaskID)
  case failure(taskID: CharacterTaskID, failure: CharacterFailure)
  case cancelled(taskID: CharacterTaskID)
}

/// Explicit gaze target. `.automatic` lets the package choose gaze from activity,
/// conversation and deterministic ambient behavior; `.focus` is a caller-owned target.
public enum CharacterAttention: Sendable, Equatable, Hashable {
  case automatic
  case focus(CharacterPoint)
}

/// Supported discrete expressions.
///
/// The raw values are stable serialization labels. The renderer treats these as
/// stylized presentation intents rather than universal claims about human faces.
public enum CharacterEmotion: String, Sendable, Equatable, Hashable, CaseIterable {
  case joy
  case affection
  case gratitude
  case interest
  case surprise
  case calmTrust = "calm_trust"
  case sadness
  case anxietyFear = "anxiety_fear"
  case angerIrritation = "anger_irritation"
  case disgustContempt = "disgust_contempt"
  case shameGuilt = "shame_guilt"
  case fatigueBurden = "fatigue_burden"
}

/// Explicit host-owned communication. Listening captures audio; voice represents speech output.
public enum CharacterCommunication: Sendable, Equatable {
  case silent
  case chat
  case listening(level: CharacterVoiceLevel)
  case voice(level: CharacterVoiceLevel)
}

/// Semantic owner of large presentation motion.
///
/// Orthogonal state can coexist, but only the latest meaningful channel owns the
/// next large choreography. The reducer is the single authority that changes it.
public enum CharacterVisualChannel: Sendable, Equatable, Hashable {
  case neutral
  case activity
  case emotion
  case communication
  case animation
}

/// Stored semantic presentation owners. Neutral and animation are derived states and therefore
/// cannot enter the reducer-owned recency list.
enum CharacterSemanticVisualChannel: Sendable, Equatable, Hashable {
  case activity
  case emotion
  case communication

  var publicChannel: CharacterVisualChannel {
    switch self {
    case .activity: .activity
    case .emotion: .emotion
    case .communication: .communication
    }
  }
}

/// The sole semantic state read by the presentation layer.
///
/// The host owns this opaque value and changes it only through `ReactiveCharacter.reduce`, directly or via `ReactiveCharacter.act`.
/// Its public properties are observations, not a complete reconstruction format: the reducer
/// also preserves internal visual-owner recency so a temporary owner can restore the newest
/// still-active semantic channel. Keep the complete value in memory; durable restoration must
/// replay host-persisted semantic inputs from `ReactiveCharacter.initialState`.
/// Activity, attention, emotion, communication and explicit action remain independent;
/// `visualChannel` owns only large choreography and never replaces those semantic values.
public struct CharacterState: Sendable, Equatable {
  public let activity: CharacterActivity
  public let attention: CharacterAttention
  public let emotion: CharacterEmotion?
  public let communication: CharacterCommunication
  public let animation: CharacterAnimationState?
  public let visualChannel: CharacterVisualChannel

  // The reducer-owned semantic recency is authoritative. visualChannel is a public, immutable
  // projection materialized by the only internal initializer to preserve its established API shape.
  let semanticVisualRecency: [CharacterSemanticVisualChannel]

  init(
    activity: CharacterActivity,
    attention: CharacterAttention,
    emotion: CharacterEmotion?,
    communication: CharacterCommunication,
    animation: CharacterAnimationState?,
    semanticVisualRecency: [CharacterSemanticVisualChannel]
  ) {
    self.activity = activity
    self.attention = attention
    self.emotion = emotion
    self.communication = communication
    self.animation = animation
    self.semanticVisualRecency = semanticVisualRecency
    visualChannel =
      animation != nil
      ? .animation
      : semanticVisualRecency.first?.publicChannel ?? .neutral
  }

  public static let idle = Self(
    activity: .idle,
    attention: .automatic,
    emotion: nil,
    communication: .silent,
    animation: nil,
    semanticVisualRecency: []
  )
}

/// Every semantic input, asynchronous result, cancellation request, expression,
/// and communication change enters here.
public enum CharacterEvent: Sendable, Equatable {
  case userWritingBegan(focus: CharacterPoint)
  case userWritingChanged(focus: CharacterPoint)
  case userWritingEnded
  case agentStarted(taskID: CharacterTaskID)
  case agentProgress(taskID: CharacterTaskID, progress: Double)
  case agentCancellationRequested(taskID: CharacterTaskID)
  case agentSucceeded(taskID: CharacterTaskID)
  case agentFailed(taskID: CharacterTaskID, failure: CharacterFailure)
  case agentCancelled(taskID: CharacterTaskID)

  case attentionFocused(CharacterPoint)
  case attentionReleased

  case emotionChanged(CharacterEmotion?)
  case chatStarted
  case listeningStarted
  case listeningLevelChanged(Double)
  case voiceStarted
  case voiceLevelChanged(Double)
  case communicationEnded

  case animationStarted(id: CharacterAnimationID, animation: CharacterAnimation)
  case animationEnded(id: CharacterAnimationID)

  case reset
}

/// Side effects requested by the pure reducer. The host executes them and feeds any
/// asynchronous completion back as a `CharacterEvent`. Animation-end delays include
/// the hard presentation handoff budget so cleanup cannot race visual start.
public enum CharacterEffect: Sendable, Equatable {
  case cancelAgent(taskID: CharacterTaskID)
  case scheduleAnimationEnd(id: CharacterAnimationID, after: Double)
}

public enum CharacterIgnoreReason: Sendable, Equatable {
  case duplicate
  case staleTask(expected: CharacterTaskID, received: CharacterTaskID)
  case noActiveTask(received: CharacterTaskID)
  case staleAnimation(expected: CharacterAnimationID, received: CharacterAnimationID)
  case noActiveAnimation(received: CharacterAnimationID)
  case eventNotApplicable
}

public enum CharacterError: Error, Sendable, Equatable, CustomStringConvertible {
  case emptyTaskID
  case emptyAnimationID
  case animationIdentityConflict(id: CharacterAnimationID)
  case emptyFailureField(field: String)
  case nonFiniteValue(field: String, value: Double)
  case outOfRange(field: String, value: Double)
  case progressRegressed(previous: Double, received: Double)

  public var description: String {
    switch self {
    case .emptyTaskID:
      "taskID must not be empty"
    case .emptyAnimationID:
      "animationID must not be empty"
    case .animationIdentityConflict(let id):
      "animationID \(id.rawValue) is already bound to a different animation"
    case .emptyFailureField(let field):
      "failure.\(field) must not be empty"
    case .nonFiniteValue(let field, let value):
      "\(field) must be finite; received \(value)"
    case .outOfRange(let field, let value):
      "\(field) must be in 0...1; received \(value)"
    case .progressRegressed(let previous, let received):
      "progress must be monotonic; previous \(previous), received \(received)"
    }
  }
}

public enum CharacterDisposition: Sendable, Equatable {
  case accepted
  case ignored(CharacterIgnoreReason)
  case rejected(CharacterError)
}

public struct CharacterTransition: Sendable, Equatable {
  public let state: CharacterState
  public let effects: [CharacterEffect]
  public let disposition: CharacterDisposition

  init(
    state: CharacterState,
    effects: [CharacterEffect] = [],
    disposition: CharacterDisposition
  ) {
    self.state = state
    self.effects = effects
    self.disposition = disposition
  }
}

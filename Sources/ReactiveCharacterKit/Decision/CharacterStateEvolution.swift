import Foundation

/// Reducer-owned reconstruction and semantic queries; no presentation clock or host effect.
extension CharacterState {
  /// Semantic request shared by inspection and pose composition. Listening alone is silent.
  var mouthRequested: Bool {
    emotion != nil || communication.requestsMouth || activity.isAgentWriting
  }

  func replacing(
    activity: CharacterActivity,
    clearingAnimation: Bool = false,
    promoting: CharacterSemanticVisualChannel? = nil
  ) -> CharacterState {
    rebuilt(
      activity: activity,
      attention: attention,
      emotion: emotion,
      communication: communication,
      animation: clearingAnimation ? nil : animation,
      promoting: promoting
    )
  }

  func replacing(attention: CharacterAttention) -> CharacterState {
    rebuilt(
      activity: activity,
      attention: attention,
      emotion: emotion,
      communication: communication,
      animation: animation
    )
  }

  func replacing(
    emotion: CharacterEmotion?,
    clearingAnimation: Bool = false,
    promoting: CharacterSemanticVisualChannel? = nil
  ) -> CharacterState {
    rebuilt(
      activity: activity,
      attention: attention,
      emotion: emotion,
      communication: communication,
      animation: clearingAnimation ? nil : animation,
      promoting: promoting
    )
  }

  func replacing(
    communication: CharacterCommunication,
    clearingAnimation: Bool = false,
    promoting: CharacterSemanticVisualChannel? = nil
  ) -> CharacterState {
    rebuilt(
      activity: activity,
      attention: attention,
      emotion: emotion,
      communication: communication,
      animation: clearingAnimation ? nil : animation,
      promoting: promoting
    )
  }

  func replacingAnimation(_ animation: CharacterAnimationState?) -> CharacterState {
    rebuilt(
      activity: activity,
      attention: attention,
      emotion: emotion,
      communication: communication,
      animation: animation
    )
  }

  var fallbackVisualChannelExcludingAnimation: CharacterVisualChannel {
    semanticVisualRecency.first?.publicChannel ?? .neutral
  }

  private func rebuilt(
    activity: CharacterActivity,
    attention: CharacterAttention,
    emotion: CharacterEmotion?,
    communication: CharacterCommunication,
    animation: CharacterAnimationState?,
    promoting: CharacterSemanticVisualChannel? = nil
  ) -> CharacterState {
    var recency = semanticVisualRecency.filter { channel in
      isAvailableSemanticVisualChannel(
        channel,
        activity: activity,
        emotion: emotion,
        communication: communication
      )
    }

    if let promoted = promoting,
      isAvailableSemanticVisualChannel(
        promoted,
        activity: activity,
        emotion: emotion,
        communication: communication
      )
    {
      recency.removeAll { $0 == promoted }
      recency.insert(promoted, at: 0)
    }

    return CharacterState(
      activity: activity,
      attention: attention,
      emotion: emotion,
      communication: communication,
      animation: animation,
      semanticVisualRecency: recency
    )
  }

  private func isAvailableSemanticVisualChannel(
    _ channel: CharacterSemanticVisualChannel,
    activity: CharacterActivity,
    emotion: CharacterEmotion?,
    communication: CharacterCommunication
  ) -> Bool {
    switch channel {
    case .activity:
      !activity.isIdle
    case .emotion:
      emotion != nil
    case .communication:
      communication != .silent
    }
  }

}

extension CharacterActivity {
  var isAgentWriting: Bool {
    if case .agentWriting = self { return true }
    return false
  }

  var isIdle: Bool {
    if case .idle = self { return true }
    return false
  }

  var canRequestCancellation: Bool {
    switch self {
    case .agentThinking, .agentWriting:
      true
    default:
      false
    }
  }

  var activeTaskID: CharacterTaskID? {
    switch self {
    case .agentThinking(let taskID),
      .agentWriting(let taskID, _),
      .agentCancelling(let taskID):
      taskID
    case .idle,
      .userWriting,
      .success,
      .failure,
      .cancelled:
      nil
    }
  }

  var terminalTaskID: CharacterTaskID? {
    switch self {
    case .success(let taskID),
      .failure(let taskID, _),
      .cancelled(let taskID):
      taskID
    case .idle,
      .userWriting,
      .agentThinking,
      .agentWriting,
      .agentCancelling:
      nil
    }
  }

  var knownTaskID: CharacterTaskID? {
    activeTaskID ?? terminalTaskID
  }
}

extension CharacterCommunication {
  var requestsMouth: Bool {
    switch self {
    case .silent, .listening: false
    case .chat, .voice: true
    }
  }
}

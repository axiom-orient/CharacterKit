import Foundation

/// Pure state-transition authority for the reactive character.
public enum ReactiveCharacter: Sendable {
  public static let initialState = CharacterState.idle

  public static func reduce(
    state: CharacterState,
    event: CharacterEvent
  ) -> CharacterTransition {
    switch event {
    case .userWritingBegan(let focus):
      if case .userWriting(let current) = state.activity, current == focus, state.animation == nil {
        return ignored(state, .duplicate)
      }
      return accepted(
        state.replacing(
          activity: .userWriting(focus: focus), clearingAnimation: true, promoting: .activity),
        effects: cancellationEffect(for: state.activity)
      )

    case .userWritingChanged(let focus):
      guard case .userWriting(let current) = state.activity else {
        return ignored(state, .eventNotApplicable)
      }
      guard current != focus else {
        return ignored(state, .duplicate)
      }
      return accepted(state.replacing(activity: .userWriting(focus: focus)))

    case .userWritingEnded:
      guard case .userWriting = state.activity else {
        return ignored(state, .eventNotApplicable)
      }
      return accepted(state.replacing(activity: .idle))

    case .agentStarted(let taskID):
      if state.activity.knownTaskID == taskID {
        return ignored(state, .duplicate)
      }
      return accepted(
        state.replacing(
          activity: .agentThinking(taskID: taskID), clearingAnimation: true,
          promoting: .activity),
        effects: cancellationEffect(for: state.activity)
      )

    case .agentProgress(let taskID, let rawProgress):
      let progress: CharacterProgress
      do {
        progress = try CharacterProgress(validating: rawProgress)
      } catch let error as CharacterError {
        return rejected(state, error)
      } catch {
        preconditionFailure("CharacterProgress exposes only CharacterError")
      }

      switch state.activity {
      case .agentThinking(let expected):
        guard expected == taskID else {
          return ignored(
            state,
            .staleTask(expected: expected, received: taskID)
          )
        }
        return accepted(
          state.replacing(
            activity: .agentWriting(taskID: taskID, progress: progress),
            promoting: .activity
          )
        )

      case .agentWriting(let expected, let previous):
        guard expected == taskID else {
          return ignored(
            state,
            .staleTask(expected: expected, received: taskID)
          )
        }
        if progress == previous {
          return ignored(state, .duplicate)
        }
        guard progress > previous else {
          return rejected(
            state,
            .progressRegressed(
              previous: previous.value,
              received: progress.value
            )
          )
        }
        return accepted(
          state.replacing(
            activity: .agentWriting(taskID: taskID, progress: progress)
          )
        )

      case .agentCancelling(let expected):
        guard expected == taskID else {
          return ignored(
            state,
            .staleTask(expected: expected, received: taskID)
          )
        }
        return ignored(state, .eventNotApplicable)

      default:
        return taskMismatch(state: state, received: taskID)
      }

    case .agentCancellationRequested(let taskID):
      switch state.activity {
      case .agentThinking(let expected), .agentWriting(let expected, _):
        guard expected == taskID else {
          return ignored(
            state,
            .staleTask(expected: expected, received: taskID)
          )
        }
        return accepted(
          state.replacing(
            activity: .agentCancelling(taskID: taskID), clearingAnimation: true,
            promoting: .activity),
          effects: [.cancelAgent(taskID: taskID)]
        )

      case .agentCancelling(let expected):
        guard expected == taskID else {
          return ignored(
            state,
            .staleTask(expected: expected, received: taskID)
          )
        }
        return ignored(state, .duplicate)

      default:
        return taskMismatch(state: state, received: taskID)
      }

    case .agentSucceeded(let taskID):
      return finish(
        state: state,
        taskID: taskID,
        terminal: .success(taskID: taskID)
      )

    case .agentFailed(let taskID, let failure):
      return finish(
        state: state,
        taskID: taskID,
        terminal: .failure(taskID: taskID, failure: failure)
      )

    case .agentCancelled(let taskID):
      return finish(
        state: state,
        taskID: taskID,
        terminal: .cancelled(taskID: taskID)
      )

    case .attentionFocused(let point):
      let nextAttention = CharacterAttention.focus(point)
      guard state.attention != nextAttention else {
        return ignored(state, .duplicate)
      }
      return accepted(state.replacing(attention: nextAttention))

    case .attentionReleased:
      guard state.attention != .automatic else {
        return ignored(state, .duplicate)
      }
      return accepted(state.replacing(attention: .automatic))

    case .emotionChanged(let emotion):
      if emotion == nil {
        guard state.emotion != nil else {
          return ignored(state, .duplicate)
        }
        return accepted(state.replacing(emotion: nil))
      }

      guard state.emotion != emotion || state.visualChannel != .emotion || state.animation != nil
      else {
        return ignored(state, .duplicate)
      }
      return accepted(
        state.replacing(
          emotion: emotion,
          clearingAnimation: true,
          promoting: .emotion
        )
      )

    case .chatStarted:
      guard
        state.communication != .chat || state.visualChannel != .communication
          || state.animation != nil
      else {
        return ignored(state, .duplicate)
      }
      return accepted(
        state.replacing(
          communication: .chat,
          clearingAnimation: true,
          promoting: .communication
        )
      )

    case .listeningStarted:
      if case .listening = state.communication,
        state.visualChannel == .communication,
        state.animation == nil
      {
        return ignored(state, .duplicate)
      }
      return accepted(
        state.replacing(
          communication: .listening(level: .zero),
          clearingAnimation: true,
          promoting: .communication
        )
      )

    case .voiceStarted:
      if case .voice = state.communication,
        state.visualChannel == .communication,
        state.animation == nil
      {
        return ignored(state, .duplicate)
      }
      return accepted(
        state.replacing(
          communication: .voice(level: .zero),
          clearingAnimation: true,
          promoting: .communication
        )
      )

    case .listeningLevelChanged(let rawLevel), .voiceLevelChanged(let rawLevel):
      let level: CharacterVoiceLevel
      do {
        level = try CharacterVoiceLevel(validating: rawLevel)
      } catch let error as CharacterError {
        return rejected(state, error)
      } catch {
        preconditionFailure("CharacterVoiceLevel exposes only CharacterError")
      }

      let previous: CharacterVoiceLevel
      let next: CharacterCommunication
      switch (event, state.communication) {
      case (.listeningLevelChanged, .listening(let current)):
        previous = current
        next = .listening(level: level)
      case (.voiceLevelChanged, .voice(let current)):
        previous = current
        next = .voice(level: level)
      default:
        return ignored(state, .eventNotApplicable)
      }
      guard previous != level else {
        return ignored(state, .duplicate)
      }
      return accepted(state.replacing(communication: next))

    case .communicationEnded:
      guard state.communication != .silent else {
        return ignored(state, .duplicate)
      }
      return accepted(state.replacing(communication: .silent))

    case .animationStarted(let id, let animation):
      if let current = state.animation {
        if current.id == id {
          if current.animation == animation {
            return ignored(state, .duplicate)
          }
          return rejected(state, .animationIdentityConflict(id: id))
        }
      }
      return accepted(
        state.replacingAnimation(CharacterAnimationState(id: id, animation: animation)),
        effects: [
          .scheduleAnimationEnd(
            id: id,
            after: animation.duration + CharacterAnimationLifecyclePolicy.maximumHandoffDuration
          )
        ]
      )

    case .animationEnded(let id):
      guard let current = state.animation else {
        return ignored(state, .noActiveAnimation(received: id))
      }
      guard current.id == id else {
        return ignored(state, .staleAnimation(expected: current.id, received: id))
      }
      return accepted(state.replacingAnimation(nil))

    case .reset:
      if state == initialState {
        return ignored(state, .duplicate)
      }
      return accepted(
        initialState,
        effects: cancellationEffect(for: state.activity)
      )
    }
  }

  private static func finish(
    state: CharacterState,
    taskID: CharacterTaskID,
    terminal: CharacterActivity
  ) -> CharacterTransition {
    if state.activity.terminalTaskID == taskID {
      if state.activity == terminal {
        return ignored(state, .duplicate)
      }
      return ignored(state, .eventNotApplicable)
    }

    guard let expected = state.activity.activeTaskID else {
      return ignored(state, .noActiveTask(received: taskID))
    }
    guard expected == taskID else {
      return ignored(
        state,
        .staleTask(expected: expected, received: taskID)
      )
    }
    return accepted(
      state.replacing(activity: terminal, clearingAnimation: true, promoting: .activity))
  }

  private static func taskMismatch(
    state: CharacterState,
    received: CharacterTaskID
  ) -> CharacterTransition {
    if let expected = state.activity.activeTaskID {
      return ignored(
        state,
        .staleTask(expected: expected, received: received)
      )
    }
    if state.activity.knownTaskID == received {
      return ignored(state, .duplicate)
    }
    return ignored(state, .noActiveTask(received: received))
  }

  private static func cancellationEffect(
    for activity: CharacterActivity
  ) -> [CharacterEffect] {
    switch activity {
    case .agentThinking(let taskID), .agentWriting(let taskID, _):
      [.cancelAgent(taskID: taskID)]
    case .agentCancelling,
      .idle,
      .userWriting,
      .success,
      .failure,
      .cancelled:
      []
    }
  }

  private static func accepted(
    _ state: CharacterState,
    effects: [CharacterEffect] = []
  ) -> CharacterTransition {
    CharacterTransition(
      state: state,
      effects: effects,
      disposition: .accepted
    )
  }

  private static func ignored(
    _ state: CharacterState,
    _ reason: CharacterIgnoreReason
  ) -> CharacterTransition {
    CharacterTransition(
      state: state,
      disposition: .ignored(reason)
    )
  }

  private static func rejected(
    _ state: CharacterState,
    _ error: CharacterError
  ) -> CharacterTransition {
    CharacterTransition(
      state: state,
      disposition: .rejected(error)
    )
  }
}

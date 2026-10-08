#if os(iOS) || os(macOS)
  import SwiftUI

  /// SEMI renderer for reducer-owned semantic state.
  @available(iOS 16.0, macOS 13.0, *)
  public struct ReactiveCharacterView: View {
    private let state: CharacterState
    private let accessibilityLabel: String
    private let hostAccessibilityValue: String?

    public init(
      state: CharacterState,
      accessibilityLabel: String = "SEMI",
      accessibilityValue: String? = nil
    ) {
      self.state = state
      self.accessibilityLabel = accessibilityLabel
      self.hostAccessibilityValue = accessibilityValue
    }

    public var body: some View {
      CharacterTimelineView(state: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
      if let hostAccessibilityValue { return hostAccessibilityValue }
      var values = [activityAccessibilityValue]
      if let emotion = state.emotion { values.append("Emotion: \(emotion.rawValue)") }
      switch state.communication {
      case .silent:
        break
      case .chat:
        values.append("Chatting")
      case .listening(let level):
        values.append("Listening, input level \(Int((level.value * 100).rounded())) percent")
      case .voice:
        values.append("Speaking")
      }
      return values.joined(separator: ", ")
    }

    private var activityAccessibilityValue: String {
      switch state.activity {
      case .idle:
        "Idle"
      case .userWriting:
        "User is writing"
      case .agentThinking:
        "Agent is thinking"
      case .agentWriting(_, let progress):
        "Agent is writing, \(Int((progress.value * 100).rounded())) percent"
      case .agentCancelling:
        "Agent cancellation requested"
      case .success:
        "Completed"
      case .failure(_, let failure):
        "Failed: \(failure.operation), \(failure.cause)"
      case .cancelled:
        "Cancelled"
      }
    }
  }
#endif

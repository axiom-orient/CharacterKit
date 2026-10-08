import Foundation
import ReactiveCharacterKit
import SwiftUI

struct HostDemoView: View {
  @State private var semanticState = CharacterState.idle
  @State private var emotion: CharacterEmotion? = .joy
  @State private var progressDraft = 0.42
  @State private var communicationLevel = 0.5
  @State private var animation = CharacterAnimation.bounce
  @State private var reduceMotion = false
  @State private var characterIdentity = UUID()
  @State private var previousTaskID: CharacterTaskID?
  @State private var animationEndTasks: [CharacterAnimationID: Task<Void, Never>] = [:]
  @State private var diagnostics: [String] = []
  @State private var lastEffectSummary = "No effects requested"

  private var activeTaskID: CharacterTaskID? {
    switch semanticState.activity {
    case .agentThinking(let id), .agentWriting(let id, _), .agentCancelling(let id): id
    case .idle, .userWriting, .success, .failure, .cancelled: nil
    }
  }

  private var canRequestCancellation: Bool {
    switch semanticState.activity {
    case .agentThinking, .agentWriting: true
    default: false
    }
  }

  private var canSetCommunicationLevel: Bool {
    switch semanticState.communication {
    case .listening, .voice: true
    case .silent, .chat: false
    }
  }

  private var stateSummary: String {
    let activity: String
    switch semanticState.activity {
    case .idle:
      activity = "Idle"
    case .userWriting:
      activity = "User writing"
    case .agentThinking(let id):
      activity = "Agent thinking · \(id.rawValue)"
    case .agentWriting(let id, let progress):
      activity = "Agent writing · \(id.rawValue) · \(percent(progress.value))"
    case .agentCancelling(let id):
      activity = "Cancellation requested · \(id.rawValue)"
    case .success(let id):
      activity = "Observed success · \(id.rawValue)"
    case .failure(let id, let failure):
      activity = "Observed failure · \(id.rawValue) · \(failure.operation)"
    case .cancelled(let id):
      activity = "Observed cancellation · \(id.rawValue)"
    }

    let communication: String
    switch semanticState.communication {
    case .silent:
      communication = "Silent"
    case .chat:
      communication = "Chat"
    case .listening(let level):
      communication = "Listening · \(percent(level.value))"
    case .voice(let level):
      communication = "Speaking · \(percent(level.value))"
    }

    let expression = semanticState.emotion?.rawValue ?? "none"
    let activeAnimation = semanticState.animation.map { $0.animation.rawValue } ?? "none"
    return "\(activity) · \(communication) · Emotion \(expression) · Animation \(activeAnimation)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      HStack(alignment: .top, spacing: 18) {
        characterPanel
          .frame(width: 330)

        Divider()

        HostDemoControls(
          state: semanticState,
          emotion: $emotion,
          progressDraft: $progressDraft,
          communicationLevel: $communicationLevel,
          animation: $animation,
          reduceMotion: $reduceMotion,
          activeTaskID: activeTaskID,
          canRequestCancellation: canRequestCancellation,
          canSetCommunicationLevel: canSetCommunicationLevel,
          onSend: apply(event:source:),
          onStartTask: startTask,
          onInjectStaleProgress: injectStaleProgress,
          onRequestCancellation: requestCancellation,
          onReportSuccess: reportSuccess,
          onReportFailure: reportFailure,
          onReportCancelled: reportCancelled,
          onStartAnimation: startAnimation,
          onEndAnimation: reportAnimationEnded,
          onReset: reset,
          onRecreateCharacterView: recreateCharacterView
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      diagnosticsPanel
    }
    .padding(18)
    .frame(minWidth: 1040, minHeight: 780)
    .onDisappear {
      for task in animationEndTasks.values { task.cancel() }
      animationEndTasks.removeAll()
    }
    .onChange(of: communicationLevel) { newValue in
      let bounded = min(1, max(0, newValue))
      switch semanticState.communication {
      case .listening:
        apply(event: .listeningLevelChanged(bounded), source: "Host slider")
      case .voice:
        apply(event: .voiceLevelChanged(bounded), source: "Host slider")
      case .silent, .chat:
        break
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("CharacterKit · Native host input demo")
        .font(.title2.weight(.semibold))
      Text("This window injects host events into the SDK. No agent, network request, or business operation is running.")
        .font(.callout)
        .foregroundStyle(.secondary)
      Text("\(stateSummary)\nEffect plan: \(lastEffectSummary)")
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .accessibilityIdentifier("semanticStateSummary")
    }
  }

  private var characterPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      ReactiveCharacterView(
        state: semanticState,
        accessibilityLabel: "Character preview",
        accessibilityValue: stateSummary
      )
      .frame(width: 300, height: 300)
      .id(characterIdentity)
      .characterReduceMotion(reduceMotion)
      .accessibilityIdentifier("demoCharacter")

      Text("SEMI · Reduce Motion: \(reduceMotion ? "On" : "Off")")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
  }

  private var diagnosticsPanel: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Reducer and host diagnostics")
          .font(.headline)
        Spacer()
        Text("Newest first · \(diagnostics.count) entries")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          if diagnostics.isEmpty {
            Text("Choose a control to send the first CharacterEvent.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(diagnostics.indices, id: \.self) { index in
              Text(diagnostics[index])
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("diagnostic-\(index)")
            }
          }
        }
      }
      .frame(height: 150)
      .padding(8)
      .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
      .accessibilityIdentifier("diagnosticList")
    }
  }

  private func apply(event: CharacterEvent, source: String) {
    let receipt = ReactiveCharacter.act(state: semanticState, event: event)
    semanticState = receipt.stateAfter

    let scheduledIDs = Array(animationEndTasks.keys)
    let plan = receipt.effectPlan(scheduledAnimationIDs: scheduledIDs)
    var effectNotes: [String] = []

    for id in plan.animationIDsToCancel {
      if let task = animationEndTasks.removeValue(forKey: id) {
        task.cancel()
        effectNotes.append("cancel timer \(id.rawValue)")
      }
    }

    for effect in plan.effects {
      switch effect {
      case .cancelAgent(let taskID):
        // No external runner is attached; the effect request is observable, not executed.
        effectNotes.append("cancelAgent requested for \(taskID.rawValue); no runner attached")
      case .scheduleAnimationEnd(let id, let after):
        scheduleAnimationEnd(id: id, after: after)
        effectNotes.append("scheduled animationEnded \(id.rawValue) after \(String(format: "%.2f", after))s")
      }
    }

    let diagnostic = receipt.diagnostic
    let details = diagnostic.details.keys.sorted().map { key in
      "\(key)=\(diagnostic.details[key] ?? "")"
    }.joined(separator: ", ")
    let suffix = details.isEmpty ? "" : " · \(details)"
    appendDiagnostic("\(source) · \(diagnostic.status)/\(diagnostic.code) · \(diagnostic.message)\(suffix)")
    lastEffectSummary = effectNotes.isEmpty ? "No effects requested" : effectNotes.joined(separator: "; ")
    appendDiagnostic("state · \(stateSummary)")
    if !effectNotes.isEmpty { appendDiagnostic("host effect plan · \(lastEffectSummary)") }
  }

  private func startTask() {
    if let activeTaskID { previousTaskID = activeTaskID }
    let taskID = CharacterTaskID(UUID())
    progressDraft = 0
    apply(event: .agentStarted(taskID: taskID), source: "Host button")
  }

  private func injectStaleProgress() {
    guard let activeTaskID else { return }
    let staleID = previousTaskID.flatMap { $0 == activeTaskID ? nil : $0 } ?? CharacterTaskID(UUID())
    apply(event: .agentProgress(taskID: staleID, progress: 0.95), source: "Injected stale callback")
  }

  private func requestCancellation() {
    guard canRequestCancellation, let activeTaskID else { return }
    apply(event: .agentCancellationRequested(taskID: activeTaskID), source: "Host button")
  }

  private func reportSuccess() {
    guard let activeTaskID else { return }
    apply(event: .agentSucceeded(taskID: activeTaskID), source: "Observed host result")
  }

  private func reportFailure() {
    guard let activeTaskID,
          let failure = try? CharacterFailure(
            operation: "host-demo", cause: "Failure event injected by the user")
    else { return }
    apply(event: .agentFailed(taskID: activeTaskID, failure: failure), source: "Observed host result")
  }

  private func reportCancelled() {
    guard let activeTaskID else { return }
    apply(event: .agentCancelled(taskID: activeTaskID), source: "Observed host result")
  }

  private func startAnimation() {
    apply(
      event: .animationStarted(id: CharacterAnimationID(UUID()), animation: animation),
      source: "Host button")
  }

  private func reportAnimationEnded() {
    guard let id = semanticState.animation?.id else { return }
    apply(event: .animationEnded(id: id), source: "Observed host timer result")
  }

  private func reset() {
    progressDraft = 0
    communicationLevel = 0.5
    apply(event: .reset, source: "Host button")
  }

  private func recreateCharacterView() {
    characterIdentity = UUID()
    appendDiagnostic("UI probe · Character view identity replaced; host CharacterState retained")
  }

  private func scheduleAnimationEnd(id: CharacterAnimationID, after delay: Double) {
    animationEndTasks[id]?.cancel()
    animationEndTasks[id] = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      animationEndTasks[id] = nil
      guard semanticState.animation?.id == id else {
        appendDiagnostic("Host timer · stale animation timer suppressed · \(id.rawValue)")
        return
      }
      apply(event: .animationEnded(id: id), source: "Host timer")
    }
  }

  private func appendDiagnostic(_ line: String) {
    diagnostics.insert(line, at: 0)
    if diagnostics.count > 60 { diagnostics.removeLast(diagnostics.count - 60) }
  }

  private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

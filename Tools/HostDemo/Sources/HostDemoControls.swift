import ReactiveCharacterKit
import SwiftUI

struct HostDemoControls: View {
  let state: CharacterState
  @Binding var emotion: CharacterEmotion?
  @Binding var progressDraft: Double
  @Binding var communicationLevel: Double
  @Binding var animation: CharacterAnimation
  @Binding var reduceMotion: Bool
  let activeTaskID: CharacterTaskID?
  let canRequestCancellation: Bool
  let canSetCommunicationLevel: Bool
  let onSend: (CharacterEvent, String) -> Void
  let onStartTask: () -> Void
  let onInjectStaleProgress: () -> Void
  let onRequestCancellation: () -> Void
  let onReportSuccess: () -> Void
  let onReportFailure: () -> Void
  let onReportCancelled: () -> Void
  let onStartAnimation: () -> Void
  let onEndAnimation: () -> Void
  let onReset: () -> Void
  let onRecreateCharacterView: () -> Void

  private var communicationDescription: String {
    switch state.communication {
    case .silent: "Silent"
    case .chat: "Chat"
    case .listening(let level): "Listening · \(percent(level.value))"
    case .voice(let level): "Speaking · \(percent(level.value))"
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        appearanceControls
        communicationControls
        taskControls
        animationControls
        motionControls
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.trailing, 4)
    }
    .accessibilityIdentifier("hostControls")
  }

  private var appearanceControls: some View {
    GroupBox("Appearance and emotion") {
      VStack(alignment: .leading, spacing: 10) {
        Picker("Emotion", selection: $emotion) {
          Text("None").tag(nil as CharacterEmotion?)
          ForEach(CharacterEmotion.allCases, id: \.self) { value in
            Text(value.rawValue).tag(Optional(value))
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("emotionPicker")

        HStack {
          Button("Send emotion event") {
            onSend(.emotionChanged(emotion), "Host button")
          }
          .accessibilityIdentifier("sendEmotionButton")
          Button("Recreate Character view", action: onRecreateCharacterView)
            .accessibilityIdentifier("recreateCharacterViewButton")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var communicationControls: some View {
    GroupBox("Communication events") {
      VStack(alignment: .leading, spacing: 10) {
        Text("Current channel: \(communicationDescription)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("communicationState")

        HStack {
          Button("Start chat") { onSend(.chatStarted, "Host button") }
            .accessibilityIdentifier("startChatButton")
          Button("Start listening") {
            communicationLevel = 0
            onSend(.listeningStarted, "Host button")
          }
          .accessibilityIdentifier("startListeningButton")
          Button("Start voice") {
            communicationLevel = 0
            onSend(.voiceStarted, "Host button")
          }
          .accessibilityIdentifier("startVoiceButton")
        }

        HStack {
          Text("Level")
          Slider(value: $communicationLevel, in: 0...1)
            .accessibilityLabel("Listening or speaking level")
            .accessibilityIdentifier("communicationLevelSlider")
            .disabled(!canSetCommunicationLevel)
          Text(percent(communicationLevel))
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }

        Button("End communication") {
          onSend(.communicationEnded, "Host button")
        }
        .accessibilityIdentifier("endCommunicationButton")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var taskControls: some View {
    GroupBox("Agent task events") {
      VStack(alignment: .leading, spacing: 10) {
        Text("Active task: \(activeTaskID?.rawValue ?? "none")")
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .accessibilityIdentifier("activeTaskID")

        Button("Start / replace task", action: onStartTask)
          .accessibilityIdentifier("startTaskButton")

        HStack {
          Text("Progress")
          Slider(value: $progressDraft, in: 0...1)
            .accessibilityIdentifier("progressSlider")
          Text(percent(progressDraft))
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }

        HStack {
          Button("Send progress event") {
            guard let activeTaskID else { return }
            onSend(.agentProgress(taskID: activeTaskID, progress: progressDraft), "Host button")
          }
          .disabled(activeTaskID == nil)
          .accessibilityIdentifier("sendProgressButton")

          Button("Inject stale progress", action: onInjectStaleProgress)
            .disabled(activeTaskID == nil)
            .accessibilityIdentifier("injectStaleProgressButton")
        }

        HStack {
          Button("Request cancellation", action: onRequestCancellation)
            .disabled(!canRequestCancellation)
            .accessibilityIdentifier("requestCancellationButton")
          Button("Inject observed success", action: onReportSuccess)
            .disabled(activeTaskID == nil)
            .accessibilityIdentifier("reportSuccessButton")
        }

        HStack {
          Button("Inject observed failure", action: onReportFailure)
            .disabled(activeTaskID == nil)
            .accessibilityIdentifier("reportFailureButton")
          Button("Inject observed cancellation", action: onReportCancelled)
            .disabled(activeTaskID == nil)
            .accessibilityIdentifier("reportCancelledButton")
        }

        Text("These controls inject event values only. No agent task runs; cancelAgent requests are reported in the log and require an observed result event.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var animationControls: some View {
    GroupBox("One-shot animation events") {
      VStack(alignment: .leading, spacing: 10) {
        Picker("Animation", selection: $animation) {
          ForEach(CharacterAnimation.allCases, id: \.self) { value in
            Text(value.rawValue).tag(value)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("animationPicker")

        HStack {
          Button("Start one-shot", action: onStartAnimation)
            .accessibilityIdentifier("startAnimationButton")
          Button("Inject observed animation end", action: onEndAnimation)
            .disabled(state.animation == nil)
            .accessibilityIdentifier("endAnimationButton")
        }

        Text("Host animation-end tasks are cancellable and checked against the animation ID before the event is sent.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var motionControls: some View {
    GroupBox("Presentation controls") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle("Host Reduce Motion", isOn: $reduceMotion)
          .accessibilityIdentifier("reduceMotionToggle")
        Button("Reset semantic state", action: onReset)
          .accessibilityIdentifier("resetButton")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

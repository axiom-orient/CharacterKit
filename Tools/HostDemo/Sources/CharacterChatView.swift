import CharacterChat
import ReactiveCharacterKit
import SwiftUI

struct CharacterChatView: View {
  @StateObject private var model = CharacterChatModel()
  @StateObject private var capture = CharacterCaptureController()
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    CharacterChatContent(model: model, openWindow: openWindow)
      .background(CharacterCaptureAnchor(controller: capture).frame(width: 0, height: 0))
      .frame(minWidth: 960, minHeight: 720)
      .onAppear { model.reviewCapture = { try capture.save(to: $0) } }
      .onDisappear { model.stop(); model.reviewCapture = nil }
  }
}

private struct CharacterChatContent: View {
  @ObservedObject var model: CharacterChatModel
  @State private var appearance = CharacterDemoAppearance.norwegianGIF
  @State private var draft = "정말 고마워요. 함께 이야기하니 행복해요!"
  @State private var emotionChoice = "automatic"
  @State private var voice = true
  @State private var reducedMotion = false
  let openWindow: OpenWindowAction

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("CharacterKit · 채팅 스튜디오").font(.title2.bold())
          Text("같은 대사를 각 캐릭터의 표정과 말하기로 표현합니다.").foregroundStyle(.secondary)
        }
        Spacer()
        Button("13종 비교") { openWindow(id: "all-characters") }
        Button("입력 검사기") { openWindow(id: "host-inspector") }
      }
      HStack(alignment: .top, spacing: 22) {
        VStack(spacing: 14) {
          characterStage
          comparison
          gazeControls
          HStack {
            Toggle("모션 감소", isOn: $reducedMotion).toggleStyle(.switch)
            Spacer()
            Menu("동작 더하기") {
              ForEach(CharacterAnimation.allCases, id: \.self) { action in
                Button(action.rawValue) { model.act(action) }
              }
            }.accessibilityIdentifier("chatActionMenu")
          }
        }.frame(width: 360)
        VStack(alignment: .leading, spacing: 12) {
          transcript
          composer
          examples
        }.frame(maxWidth: .infinity)
      }
      HStack {
        if model.phase == .preparing { ProgressView().controlSize(.small) }
        Text(model.timingDescription).font(.caption).foregroundStyle(.secondary)
        Spacer()
        if model.duration > 0 {
          Text("\(model.elapsed, specifier: "%.1f") / \(model.duration, specifier: "%.1f")초")
            .font(.caption.monospacedDigit())
        }
      }
    }
    .padding(20)
    .frame(minWidth: 960, minHeight: 720)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { model.reviewCharacter = appearance.label }
    .onChange(of: appearance) { model.reviewCharacter = $0.label }
    .onChange(of: voice) { _ in model.stop() }
  }

  private var characterStage: some View {
    VStack(spacing: 8) {
      Picker("캐릭터", selection: $appearance) {
        ForEach(CharacterDemoAppearance.allCases) { Text($0.label).tag($0) }
      }.accessibilityIdentifier("chatCharacterPicker")
        .disabled(model.touring && model.reviewFolder != nil)
        .help("시연 저장 중에는 기록 대상 캐릭터를 고정합니다. 중지하면 변경할 수 있습니다.")
      appearance.view(state: model.state, playbackTrigger: model.replayTrigger,
        accessibilityLabel: appearance.label, accessibilityValue: model.emotionTitle)
        .characterSpeechArticulation(model.articulation)
        .characterIncludesBackground(false)
        .characterReduceMotion(reducedMotion)
        .frame(height: 240)
        .accessibilityIdentifier("chatCharacter")
      Text(model.emotionTitle).font(.headline).accessibilityIdentifier("chatCurrentEmotion")
      Text(model.currentClause).font(.callout).foregroundStyle(.secondary)
        .lineLimit(2).frame(height: 38)
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 18))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08)))
  }

  private var comparison: some View {
    HStack(spacing: 10) {
      CharacterDemoAppearance.catSimple.view(state: model.state, playbackTrigger: model.replayTrigger,
        accessibilityLabel: "Simple 2D 동시 비교", accessibilityValue: model.emotionTitle)
        .characterSpeechArticulation(model.articulation)
        .characterIncludesBackground(false).characterReduceMotion(reducedMotion)
        .frame(width: 130, height: 120)
      VStack(alignment: .leading, spacing: 8) {
        Text("Simple 2D").font(.headline)
        Text("같은 대사 · 같은 감정").font(.caption).foregroundStyle(.secondary)
        Button("화남 같이 보기") { playSample(CharacterChatSample.all[8]) }
          .accessibilityIdentifier("chatSimpleAngerButton")
      }
      Spacer(minLength: 0)
    }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 14))
  }

  private var gazeControls: some View {
    HStack(spacing: 7) {
      Text("시선").font(.caption).foregroundStyle(.secondary)
      Button("자동") { model.releaseFocus() }
      ForEach(Array(zip(["←", "↑", "●", "↓", "→"], [(-1,0),(0,-1),(0,0),(0,1),(1,0)]).enumerated()), id: \.offset) { index, item in
        Button(item.0) { model.focus(x: Double(item.1.0 + 1) / 2, y: Double(item.1.1 + 1) / 2) }
          .accessibilityLabel(["왼쪽 보기", "위 보기", "가운데 보기", "아래 보기", "오른쪽 보기"][index])
          .accessibilityIdentifier("chatGaze\(index)")
      }
    }.buttonStyle(.bordered).controlSize(.small)
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if model.messages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle).foregroundStyle(.tint)
              Text("어떤 이야기를 해볼까요?").font(.title3.bold())
              Text("대사를 입력하면 문장에 따라 감정이 바뀝니다. 아래 예시로 12감정과 말하기를 바로 확인할 수 있어요.")
                .foregroundStyle(.secondary)
            }.padding(20)
          }
          ForEach(model.messages) { message in
            VStack(alignment: .leading, spacing: 5) {
              Text(message.source).font(.caption).foregroundStyle(.secondary)
              Text(highlighted(message)).font(.body).textSelection(.enabled)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(model.activeMessage == message.id ? 0.13 : 0.05),
              in: RoundedRectangle(cornerRadius: 12))
            .id(message.id)
          }
        }.padding(12)
      }
      .onChange(of: model.messages.last?.id) { _ in
        if let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
      }
    }
    .frame(minHeight: 190, maxHeight: .infinity)
    .background(.background, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)))
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Picker("다음 대사 감정", selection: $emotionChoice) {
          Text("내용에서 추정").tag("automatic")
          Text("기본 표정").tag("neutral")
          ForEach(CharacterChatSample.all) { Text($0.title).tag($0.emotion.rawValue) }
        }.accessibilityIdentifier("chatEmotionPicker")
        Toggle("음성 포함", isOn: $voice).accessibilityIdentifier("chatVoiceToggle")
      }
      TextEditor(text: $draft).font(.body).scrollContentBackground(.hidden).frame(height: 72)
        .padding(5).background(.background, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("캐릭터가 말할 대사").accessibilityIdentifier("chatComposer")
      HStack {
        Text("\(draft.count) / \(CharacterChatPlan.maximumCharacters)자 · ⌘↵ 재생")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("중지") { model.stop() }.disabled(!model.busy && !model.touring)
          .accessibilityIdentifier("chatStopButton")
        Button(voice ? "대사 말하기" : "표정 재생") { playDraft() }
          .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.count > CharacterChatPlan.maximumCharacters)
          .accessibilityIdentifier("chatSendButton")
      }
      if case .failed(let error) = model.phase {
        Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("chatError")
      }
    }
  }

  private var examples: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("12감정 예시").font(.headline)
        Spacer()
        Button("시연 저장") { model.tour(voice: voice, record: true) }
          .disabled(model.touring).accessibilityIdentifier("chatRecordTourButton")
        Button(model.touring ? "12감정 시연 중" : "12감정 이어서 보기") { model.tour(voice: voice) }
          .disabled(model.touring).accessibilityIdentifier("chatEmotionTourButton")
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
        ForEach(CharacterChatSample.all) { sample in
          Button(sample.title) { playSample(sample) }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("chatSample-\(sample.emotion.rawValue)")
        }
      }
      if let folder = model.reviewFolder {
        Text("시연 기록: \(folder.path)").font(.caption).textSelection(.enabled)
          .accessibilityIdentifier("chatReviewFolder")
      }
      Text("예시는 감정을 직접 지정합니다. 자유 대사의 자동 추정은 로컬 표현 규칙을 사용합니다.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func playDraft() {
    let selection: CharacterChatEmotion
    if emotionChoice == "automatic" { selection = .automatic }
    else if let emotion = CharacterEmotion(rawValue: emotionChoice) { selection = .emotion(emotion) }
    else { selection = .neutral }
    model.play(text: draft, emotion: selection, voice: voice)
  }
  private func playSample(_ sample: CharacterChatSample) {
    draft = sample.text
    model.play(text: sample.text, emotion: .emotion(sample.emotion), voice: voice)
  }
  private func highlighted(_ message: CharacterChatModel.Message) -> AttributedString {
    var text = AttributedString(message.text)
    if model.activeMessage == message.id, let nsRange = model.spokenRange,
      let range = Range(nsRange, in: message.text),
      let attributedRange = Range(range, in: text) {
      text[attributedRange].backgroundColor = .accentColor.opacity(0.25)
    }
    return text
  }
}

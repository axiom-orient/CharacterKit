import ReactiveCharacterKit
import SwiftUI

/// A host-only comparison surface. Every cell runs the real SDK view with identical inputs.
struct CharacterShowcaseView: View {
  @StateObject private var model = CharacterShowcaseModel()

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Button(model.running ? "시연 중" : "전체 동작 시연·프레임 저장") { model.start() }
          .disabled(model.running)
          .accessibilityIdentifier("startShowcaseButton")
        Button("현재 화면 저장") { model.saveCurrent() }
          .disabled(model.running)
          .accessibilityIdentifier("saveShowcaseFrameButton")
        Button("중지") { model.stop() }.disabled(!model.running)
        Spacer()
        Text(model.message).font(.caption).textSelection(.enabled)
      }
      CharacterCaptureSurface(controller: model.capture, content: CharacterShowcaseGrid(model: model))
        .frame(width: 1120, height: 700)
    }
    .padding(12)
    .frame(width: 1144, height: 746)
  }
}

private struct CharacterShowcaseGrid: View {
  @ObservedObject var model: CharacterShowcaseModel
  private let columns = Array(repeating: GridItem(.fixed(210), spacing: 10), count: 5)

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("CharacterKit · \(CharacterDemoAppearance.allCases.count)종 실제 렌더러 비교").font(.title2.bold())
        Spacer()
        Text(model.phase).font(.headline).foregroundStyle(.blue)
      }
      Text("동일한 호스트 이벤트 입력 · 감정 / 말하기 음량 / 시선 / 작업 / 8가지 동작")
        .font(.callout).foregroundStyle(.secondary)
      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(CharacterDemoAppearance.allCases) { appearance in
          VStack(spacing: 3) {
            appearance.view(state: model.state, playbackTrigger: model.trigger,
              accessibilityLabel: appearance.label)
            .frame(width: 172, height: 150)
            .characterIncludesBackground(false)
            Text(appearance.label).font(.system(size: 12, weight: .semibold))
            Text(appearance == .norwegianGIF ? "12감정 GIF + 실시간 얼굴 리그" : "공유 포즈 렌더러")
              .font(.system(size: 10)).foregroundStyle(.secondary)
          }
          .frame(width: 210, height: 192)
          .background(.white, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.18)))
        }
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(width: 1120, height: 700)
    .background(Color(red: 0.94, green: 0.95, blue: 0.97))
    .environment(\.colorScheme, .light)
  }
}

@MainActor
private final class CharacterShowcaseModel: ObservableObject {
  @Published var state = CharacterState.idle
  @Published var trigger = 0
  @Published var phase = "기본 표정"
  @Published var message = "실제 SwiftUI 렌더러를 한 화면에서 비교합니다"
  @Published var running = false
  let capture = CharacterCaptureController()
  private var task: Task<Void, Never>?
  private var output: URL?
  private var frameNumber = 0
  private var observations: [[String: Any]] = []

  func stop() { task?.cancel(); task = nil; running = false }

  func saveCurrent() {
    do {
      let directory = try directory()
      try capture.save(to: directory.appendingPathComponent("overview.png"))
      message = directory.path
    } catch { message = "저장 실패: \(error.localizedDescription)" }
  }

  func start() {
    stop(); output = nil; running = true; frameNumber = 0; observations = []
    task = Task { @MainActor in
      do {
        let output = try directory()
        state = .idle; phase = "기본 표정"
        try await Task.sleep(nanoseconds: 300_000_000)
        try capture.save(to: output.appendingPathComponent("overview.png"))
        let phases = Self.phases
        for item in phases {
          try Task.checkCancellation()
          phase = item.label
          message = item.label
          state = .idle
          for event in item.events { send(event) }
          if item.replay { trigger &+= 1 }
          let start = ContinuousClock.now
          while true {
            let frameStarted = ContinuousClock.now
            try Task.checkCancellation()
            let elapsed = start.duration(to: .now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if seconds >= item.duration { break }
            if let animation = state.animation, seconds >= animation.animation.duration + 1 {
              send(.animationEnded(id: animation.id))
            }
            if item.kind == .voice { send(.voiceLevelChanged((sin(seconds * 4) + 1) / 2)) }
            if item.kind == .listening { send(.listeningLevelChanged((sin(seconds * 4) + 1) / 2)) }
            if item.kind == .writing, let id = item.taskID {
              send(.agentProgress(taskID: id, progress: min(1, seconds / item.duration)))
            }
            // Capture after the host input has propagated through the native view graph.
            try await Task.sleep(nanoseconds: 25_000_000)
            let filename = String(format: "frame-%05d.png", frameNumber)
            try capture.save(to: output.appendingPathComponent(filename))
            observations.append(["frame": filename, "phase": item.label,
              "secondsInPhase": seconds, "captureUptime": ProcessInfo.processInfo.systemUptime,
              "emotion": state.emotion?.rawValue ?? "none"])
            frameNumber += 1
            let spent = frameStarted.duration(to: .now).components
            let spentSeconds = Double(spent.seconds) + Double(spent.attoseconds) / 1e18
            if spentSeconds < 0.1 {
              try await Task.sleep(nanoseconds: UInt64((0.1 - spentSeconds) * 1e9))
            }
          }
        }
        let json = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: output.appendingPathComponent("observations.json"))
        let inventory = try JSONSerialization.data(withJSONObject:
          CharacterDemoAppearance.allCases.map { ["id": $0.rawValue, "label": $0.label] },
          options: [.prettyPrinted, .sortedKeys])
        try inventory.write(to: output.appendingPathComponent("characters.json"))
        state = .idle; phase = "시연 완료 · 기본 표정"; running = false
        message = "완료: \(output.path)"
      } catch is CancellationError { running = false; message = "시연 중지됨" }
      catch { running = false; message = "시연 실패: \(error.localizedDescription)" }
    }
  }

  private func send(_ event: CharacterEvent) { state = ReactiveCharacter.reduce(state: state, event: event).state }

  private func directory() throws -> URL {
    if let output { return output }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CharacterKit-Showcase-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    output = url
    return url
  }

  private enum Kind { case ordinary, voice, listening, writing }
  private struct Phase {
    let label: String
    let duration: Double
    var events: [CharacterEvent] = []
    var kind: Kind = .ordinary
    var replay = false
    var taskID: CharacterTaskID?
  }
  private static var phases: [Phase] {
    var result = [Phase(label: "기본 표정", duration: 1.5)]
    let labels = ["기쁨", "애정", "감사", "관심", "놀람", "신뢰", "슬픔", "불안", "화남", "불쾌", "부끄러움", "피곤함"]
    for (emotion, label) in zip(CharacterEmotion.allCases, labels) {
      result.append(Phase(label: "감정 · \(label)", duration: 2.4, events: [.emotionChanged(emotion)], replay: true))
    }
    for (index, item) in zip(CharacterEmotion.allCases, labels).enumerated() {
      let (emotion, label) = item
      if let target = try? CharacterPoint(validatingX: index.isMultiple(of: 2) ? 0 : 1, y: 0.5) {
        result.append(Phase(label: "감정 + 말하기 + 시선 · \(label)", duration: 2.6,
          events: [.emotionChanged(emotion), .voiceStarted, .attentionFocused(target)],
          kind: .voice, replay: true))
      }
    }
    result.append(Phase(label: "말하기 · 음량 0↔1", duration: 4, events: [.voiceStarted], kind: .voice))
    for (label, x, y) in [("왼쪽",0.0,0.5),("오른쪽",1.0,0.5),("위",0.5,0.0),("아래",0.5,1.0)] {
      if let point = try? CharacterPoint(validatingX: x, y: y) {
        result.append(Phase(label: "시선 · \(label)", duration: 1.3, events: [.attentionFocused(point)]))
      }
    }
    result.append(Phase(label: "듣기 · 입은 닫힘", duration: 2, events: [.listeningStarted], kind: .listening))
    let taskID = CharacterTaskID(UUID())
    result.append(Phase(label: "작업 진행 · 0→100%", duration: 2.4, events: [.agentStarted(taskID: taskID)], kind: .writing, taskID: taskID))
    for action in CharacterAnimation.allCases {
      result.append(Phase(label: "동작 · \(action.rawValue)", duration: action.duration + 1.35,
        events: [.animationStarted(id: CharacterAnimationID(UUID()), animation: action)]))
    }
    result.append(Phase(label: "호스트 초기화 → 기본 표정", duration: 2))
    return result
  }
}

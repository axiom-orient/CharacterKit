import AVFoundation
import CharacterChat
import Foundation
import ReactiveCharacterKit
import SwiftUI

@MainActor
final class CharacterChatModel: ObservableObject {
  struct Message: Identifiable {
    let id: UUID
    let text: String
    let source: String
  }
  enum Phase: Equatable { case idle, preparing, playing, failed(String) }
  @Published private(set) var state = CharacterState.idle
  @Published private(set) var articulation: CharacterSpeechArticulation?
  @Published private(set) var replayTrigger = 0
  @Published private(set) var phase = Phase.idle
  @Published private(set) var messages: [Message] = []
  @Published private(set) var activeMessage: UUID?
  @Published private(set) var spokenRange: NSRange?
  @Published private(set) var currentClause = "대사를 입력하거나 감정 예시를 선택해 보세요."
  @Published private(set) var timingDescription = "재생할 대사를 기다리는 중"
  @Published private(set) var elapsed = 0.0
  @Published private(set) var duration = 0.0
  @Published private(set) var touring = false
  @Published private(set) var reviewFolder: URL?
  var reviewCapture: ((URL) throws -> Void)?
  var reviewCharacter = ""
  private var reviewRecords: [[String: Any]] = []
  private var capturedMessage = false
  private var cueStartedAt = 0.0
  private var audioFacts: [String: Any] = [:]
  private let synthesizer = AVSpeechSynthesizer()
  private var player: AVAudioPlayer?
  private var collector: CharacterSpeechAudioCollector?
  private var plan: CharacterChatPlan?
  private var cueIndex: Int?
  private var operation = UUID()
  private var playbackTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var animationTask: Task<Void, Never>?
  private var tourTask: Task<Void, Never>?

  var busy: Bool { phase == .preparing || phase == .playing }
  var emotionTitle: String { CharacterChatSample.title(for: state.emotion) }

  func play(text: String, emotion: CharacterChatEmotion, voice: Bool) {
    cancelTour()
    begin(text: text, emotion: emotion, voice: voice)
  }

  func tour(voice: Bool, record: Bool = false) {
    stop()
    reviewFolder = nil; reviewRecords = []
    if record {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CharacterKit-Chat-\(UUID().uuidString)")
      do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); reviewFolder = folder }
      catch { fail(error.localizedDescription); return }
    }
    touring = true
    tourTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for sample in CharacterChatSample.all {
        guard !Task.isCancelled else { return }
        begin(text: sample.text, emotion: .emotion(sample.emotion), voice: voice)
        while busy && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(60)) }
        guard !Task.isCancelled else { return }
        if case .failed = phase { break }
        try? await Task.sleep(for: .milliseconds(900))
      }
      guard !Task.isCancelled else { return }
      if let reviewFolder {
        do {
          try reviewCapture?(reviewFolder.appendingPathComponent("neutral-after-tour.png"))
          let report: [String: Any] = ["source": "Live native SDK views; captured on audio/text playback clock",
            "requestedExpressions": 12, "capturedExpressions": reviewRecords.count, "frames": reviewRecords]
          try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: reviewFolder.appendingPathComponent("evidence.json"))
        } catch { phase = .failed("시연 기록 저장 실패: \(error.localizedDescription)") }
      }
      touring = false
    }
  }

  func stop() {
    cancelTour()
    stopPlayback()
    phase = .idle; currentClause = "재생을 멈췄습니다. 새 대사를 입력해 보세요."
  }

  func focus(x: Double, y: Double) {
    if let point = try? CharacterPoint(validatingX: x, y: y) { send(.attentionFocused(point)) }
  }
  func releaseFocus() { send(.attentionReleased) }
  func act(_ animation: CharacterAnimation) {
    send(.animationStarted(id: CharacterAnimationID(UUID()), animation: animation))
  }

  private func begin(text: String, emotion: CharacterChatEmotion, voice: Bool) {
    stopPlayback()
    do {
      let plan = try CharacterChatPlan(text: text, emotion: emotion)
      self.plan = plan; cueIndex = nil; capturedMessage = false; audioFacts = [:]
      let id = UUID()
      activeMessage = id
      messages.append(Message(id: id, text: text, source: emotion == .automatic ? "내용에서 추정" : "감정 직접 지정"))
      if messages.count > 40 { messages.removeFirst(messages.count - 40) }
      if voice { prepareAudio(text: text) }
      else {
        let track = try CharacterSpeechTrack.textPreview(text)
        timingDescription = "텍스트 재생 · 소리 없음 · 읽는 속도 추정"
        start(track: track, audio: nil)
      }
    } catch { fail(error.localizedDescription) }
  }

  private func prepareAudio(text: String) {
    let language = text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } ? "ko-KR" : "en-US"
    guard let voice = AVSpeechSynthesisVoice(language: language) else {
      fail("\(language) 음성이 설치되어 있지 않습니다. 텍스트 모드를 사용할 수 있습니다."); return
    }
    phase = .preparing; currentClause = "음성을 준비하고 있습니다…"
    let token = operation
    let collector = CharacterSpeechAudioCollector(text: text) { [weak self] result in
      Task { @MainActor [weak self] in
        guard let self, self.operation == token, self.phase == .preparing else { return }
        self.timeoutTask?.cancel(); self.timeoutTask = nil
        switch result {
        case .failure(let error): self.fail(error.localizedDescription)
        case .success(let prepared):
          self.audioFacts = ["audioFrames": prepared.frameCount, "sampleRate": prepared.sampleRate,
            "wordMarkers": prepared.wordCount]
          do {
            let player = try AVAudioPlayer(contentsOf: prepared.url)
            player.prepareToPlay()
            self.timingDescription = "음성 재생 시간·음량에 맞춤 · 모음 모양은 글자에서 추정"
            self.start(track: prepared.track, audio: player)
          } catch { self.fail(error.localizedDescription) }
        }
      }
    }
    self.collector = collector
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice; utterance.rate = 0.46
    synthesizer.write(utterance, toBufferCallback: { collector.receive($0) },
      toMarkerCallback: { collector.markers($0) })
    timeoutTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(15)) } catch { return }
      guard let self, self.operation == token, self.phase == .preparing else { return }
      self.fail("음성 준비 시간이 초과되었습니다. 다시 재생하거나 텍스트 모드를 사용해 주세요.")
    }
  }

  private func start(track: CharacterSpeechTrack, audio: AVAudioPlayer?) {
    self.player = audio
    duration = track.duration; elapsed = 0
    phase = .playing
    send(audio == nil ? .chatStarted : .voiceStarted)
    applyCue(0)
    if let audio, !audio.play() { fail("오디오 출력을 시작하지 못했습니다."); return }
    let token = operation
    let start = ContinuousClock.now
    playbackTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, operation == token else { return }
        let time: Double
        if let audio {
          time = audio.currentTime
          if !audio.isPlaying { finish(); return }
        } else {
          let delta = start.duration(to: .now).components
          time = Double(delta.seconds) + Double(delta.attoseconds) / 1e18
        }
        if time >= track.duration { finish(); return }
        elapsed = time
        let frame = track.frame(at: time)
        articulation = frame.articulation; spokenRange = frame.utf16Range
        if let offset = frame.utf16Range?.location, let index = plan?.cueIndex(atUTF16Offset: offset) {
          applyCue(index)
        }
        if audio != nil { send(.voiceLevelChanged(frame.level)) }
        if touring, let folder = reviewFolder, !capturedMessage, time - cueStartedAt >= 0.80,
          let emotion = state.emotion, let reviewCapture {
          do {
            // Let the native view graph consume this host frame before recording it.
            try await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled, operation == token else { return }
            let name = emotion.rawValue + ".png"
            try reviewCapture(folder.appendingPathComponent(name))
            var record = audioFacts
            record["emotion"] = emotion.rawValue; record["image"] = name
            record["character"] = reviewCharacter
            record["playbackSeconds"] = time; record["cueSeconds"] = time - cueStartedAt
            record["mouthOpenness"] = frame.articulation.openness
            record["mouthWidth"] = frame.articulation.width
            record["mode"] = audio == nil ? "textPreview" : "audioClock"
            record["attention"] = String(describing: state.attention)
            record["animation"] = state.animation?.animation.rawValue ?? "none"
            reviewRecords.append(record); capturedMessage = true
          } catch { fail("시연 화면 저장 실패: \(error.localizedDescription)"); return }
        }
        do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
      }
    }
  }

  private func applyCue(_ index: Int) {
    guard index != cueIndex, let plan, plan.cues.indices.contains(index) else { return }
    cueIndex = index; cueStartedAt = elapsed
    let cue = plan.cues[index]
    currentClause = cue.text
    send(.emotionChanged(cue.emotion)); replayTrigger &+= 1
    if let animation = cue.animation { act(animation) }
  }

  private func finish() {
    let fullDuration = duration
    stopPlayback()
    elapsed = fullDuration; phase = .idle
    currentClause = "대사를 마쳤습니다. 기본 표정으로 돌아왔어요."
  }

  private func fail(_ message: String) {
    stopPlayback()
    phase = .failed(message); currentClause = message
  }

  private func stopPlayback() {
    operation = UUID()
    playbackTask?.cancel(); playbackTask = nil
    timeoutTask?.cancel(); timeoutTask = nil
    player?.stop(); player = nil
    synthesizer.stopSpeaking(at: .immediate)
    collector?.cancel(); collector = nil
    articulation = nil; spokenRange = nil; activeMessage = nil
    plan = nil; cueIndex = nil
    send(.communicationEnded); send(.emotionChanged(nil))
  }

  private func cancelTour() { tourTask?.cancel(); tourTask = nil; touring = false }

  private func send(_ event: CharacterEvent) {
    let oldID = state.animation?.id
    let transition = ReactiveCharacter.reduce(state: state, event: event)
    state = transition.state
    if oldID != state.animation?.id { animationTask?.cancel(); animationTask = nil }
    for effect in transition.effects {
      if case .scheduleAnimationEnd(let id, let delay) = effect {
        animationTask = Task { @MainActor [weak self] in
          do { try await Task.sleep(for: .seconds(delay)) } catch { return }
          guard let self, self.state.animation?.id == id else { return }
          self.send(.animationEnded(id: id))
        }
      }
    }
  }
}

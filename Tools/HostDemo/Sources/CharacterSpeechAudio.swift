import AVFoundation
import CharacterChat
import Foundation

struct CharacterPreparedSpeech: Sendable {
  let url: URL
  let track: CharacterSpeechTrack
  let wordCount: Int
  let frameCount: Int
  let sampleRate: Double
}

enum CharacterSpeechAudioError: Error, Sendable, LocalizedError {
  case failed(String)
  var errorDescription: String? {
    switch self { case .failed(let message): message }
  }
}

/// AVSpeechSynthesizer invokes these callbacks on its own queue. The lock protects
/// every mutable field, including the file writer and cancellation/completion ownership.
/// No audio buffer or framework object crosses to the UI actor.
final class CharacterSpeechAudioCollector: @unchecked Sendable {
  private let lock = NSLock()
  private let text: String
  private let url: URL
  private let completion: @Sendable (Result<CharacterPreparedSpeech, CharacterSpeechAudioError>) -> Void
  private var writer: AVAudioFile?
  private var format: AVAudioFormat?
  private var energy: [Double] = []
  private var rawWords: [(offset: Int, range: NSRange)] = []
  private var frames = 0
  private var windowFrames = 0
  private var sumSquares = 0.0
  private var finished = false

  init(text: String, completion: @escaping @Sendable (Result<CharacterPreparedSpeech, CharacterSpeechAudioError>) -> Void) {
    self.text = text; self.completion = completion
    url = FileManager.default.temporaryDirectory.appendingPathComponent("CharacterKit-Speech-\(UUID().uuidString).caf")
  }

  func markers(_ markers: [AVSpeechSynthesisMarker]) {
    lock.lock(); defer { lock.unlock() }
    guard !finished else { return }
    for marker in markers where marker.mark == .word {
      rawWords.append((marker.byteSampleOffset, marker.textRange))
    }
  }

  func receive(_ buffer: AVAudioBuffer) {
    lock.lock()
    guard !finished else { lock.unlock(); return }
    var result: Result<CharacterPreparedSpeech, CharacterSpeechAudioError>?
    do {
      guard let pcm = buffer as? AVAudioPCMBuffer else {
        throw CharacterSpeechAudioError.failed("음성 합성기가 PCM 오디오를 제공하지 않았습니다.")
      }
      if pcm.frameLength == 0 {
        writer = nil // Close the complete file before constructing the player.
        guard let format, frames > 0 else { throw CharacterSpeechAudioError.failed("합성된 음성이 비어 있습니다.") }
        if windowFrames > 0 { energy.append(sqrt(sumSquares / Double(windowFrames))) }
        let duration = Double(frames) / format.sampleRate
        let reference = max(0.035, energy.sorted()[min(energy.count - 1, Int(Double(energy.count) * 0.90))])
        let normalized = energy.map { min(1, max(0, ($0 - reference * 0.035) / reference)) }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let validWords = rawWords.filter {
          $0.range.location >= 0 && $0.range.location <= text.utf16.count && $0.range.length > 0
            && $0.range.length <= text.utf16.count - $0.range.location
        }
        let words = validWords.sorted { $0.offset < $1.offset }.map {
          CharacterSpeechWord(time: Double($0.offset) / Double(bytesPerFrame) / format.sampleRate,
            utf16Range: (text as NSString).rangeOfComposedCharacterSequences(for: $0.range))
        }
        guard !words.isEmpty else {
          throw CharacterSpeechAudioError.failed("이 음성은 단어 시간 정보를 제공하지 않습니다. 다른 음성 또는 텍스트 모드를 선택해 주세요.")
        }
        let track = try CharacterSpeechTrack(text: text, duration: duration, energy: normalized, words: words)
        finished = true
        result = .success(.init(url: url, track: track, wordCount: words.count,
          frameCount: frames, sampleRate: format.sampleRate))
      } else {
        if format == nil {
          let sampleRate = pcm.format.sampleRate
          guard sampleRate.isFinite, sampleRate >= 8000, pcm.format.channelCount > 0 else {
            throw CharacterSpeechAudioError.failed("지원하지 않는 음성 형식입니다.")
          }
          format = pcm.format
          writer = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
            commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
        }
        guard pcm.format == format else { throw CharacterSpeechAudioError.failed("합성 중 음성 형식이 변경되었습니다.") }
        guard Double(frames + Int(pcm.frameLength)) / pcm.format.sampleRate <= CharacterSpeechTrack.maximumDuration else {
          throw CharacterSpeechAudioError.failed("음성이 120초를 초과했습니다. 대사를 나누어 주세요.")
        }
        try writer?.write(from: pcm)
        let channels = Int(pcm.format.channelCount)
        let windowSize = max(1, Int(pcm.format.sampleRate * CharacterSpeechTrack.energyInterval))
        for frame in 0..<Int(pcm.frameLength) {
          var power = 0.0
          for channel in 0..<channels {
            let c = pcm.format.isInterleaved ? 0 : channel
            let i = pcm.format.isInterleaved ? frame * channels + channel : frame
            let sample: Double
            if let data = pcm.floatChannelData { sample = Double(data[c][i]) }
            else if let data = pcm.int16ChannelData { sample = Double(data[c][i]) / 32768 }
            else if let data = pcm.int32ChannelData { sample = Double(data[c][i]) / 2147483648 }
            else { throw CharacterSpeechAudioError.failed("지원하지 않는 PCM 샘플 형식입니다.") }
            power += sample * sample / Double(channels)
          }
          sumSquares += power; windowFrames += 1; frames += 1
          if windowFrames == windowSize {
            energy.append(sqrt(sumSquares / Double(windowFrames)))
            sumSquares = 0; windowFrames = 0
          }
        }
      }
    } catch {
      finished = true; writer = nil
      try? FileManager.default.removeItem(at: url)
      result = .failure(.failed(error.localizedDescription))
    }
    lock.unlock()
    if let result { completion(result) }
  }

  deinit { cancel() }

  func cancel() {
    lock.lock(); defer { lock.unlock() }
    finished = true; writer = nil
    try? FileManager.default.removeItem(at: url)
  }
}

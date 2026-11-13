#if os(iOS) || os(macOS)
  import CoreGraphics
  import Foundation
  import ImageIO
  import XCTest
  @testable import ReactiveCharacterKit

  @MainActor
  final class CharacterGIFLiveTests: XCTestCase {
    private func send(_ event: CharacterEvent, to state: CharacterState = .idle) -> CharacterState {
      ReactiveCharacter.reduce(state: state, event: event).state
    }

    func testVoiceAndGazeDoNotRestartEmotionAndRemainLiveAfterItEnds() throws {
      let gifs = try CharacterGIFSet.norwegianForest.get()
      var state = send(.emotionChanged(.sadness))
      var runtime = CharacterGIFPresentation(state: state, at: 0)
      state = send(.voiceStarted, to: state)
      state = send(.voiceLevelChanged(0.9), to: state)
      state = send(.attentionFocused(try CharacterPoint(validatingX: 1, y: 0.2)), to: state)
      runtime.update(state: state, at: 0.6, reduceMotion: false, duration: gifs.duration(for:))
      let during = runtime.sample(at: 1, reduceMotion: false, duration: gifs.duration(for:))
      XCTAssertEqual(try XCTUnwrap(during.emotion).elapsed, 1, accuracy: 1e-9)
      let after = runtime.sample(at: 3, reduceMotion: false, duration: gifs.duration(for:))
      XCTAssertNil(after.emotion)
      XCTAssertEqual(after.speechWeight, 1, accuracy: 1e-9)
      XCTAssertGreaterThan(after.pose.mouth.openness, 0.7)
      XCTAssertGreaterThan((after.pose.eyes.left.centerX + after.pose.eyes.right.centerX) / 2, 0.5)
      XCTAssertEqual(state.emotion, .sadness)
    }

    func testListeningNeverArticulatesAndSpeechExitIsContinuous() throws {
      let gifs = try CharacterGIFSet.norwegianForest.get()
      let listening = send(.listeningLevelChanged(1), to: send(.listeningStarted))
      let listen = CharacterGIFPresentation(state: listening, at: 0)
      XCTAssertEqual(listen.sample(at: 1, reduceMotion: false, duration: gifs.duration(for:)).speechWeight, 0)
      var runtime = CharacterGIFPresentation(state: send(.voiceStarted), at: 0)
      runtime.update(state: .idle, at: 1, reduceMotion: false, duration: gifs.duration(for:))
      XCTAssertEqual(runtime.sample(at: 1, reduceMotion: false, duration: gifs.duration(for:)).speechWeight, 1)
      XCTAssertEqual(runtime.sample(at: 1.06, reduceMotion: false, duration: gifs.duration(for:)).speechWeight, 0.5, accuracy: 1e-9)
      XCTAssertEqual(runtime.sample(at: 1.2, reduceMotion: false, duration: gifs.duration(for:)).speechWeight, 0)
    }

    func testActionsExpireWithoutDroppingSpeechOrAttentionAndReducedMotionIsStatic() throws {
      let gifs = try CharacterGIFSet.norwegianForest.get()
      var state = send(.voiceLevelChanged(0.8), to: send(.voiceStarted))
      state = send(.attentionFocused(try CharacterPoint(validatingX: 0, y: 0.5)), to: state)
      for action in CharacterAnimation.allCases {
        let acting = send(.animationStarted(id: CharacterAnimationID(UUID()), animation: action), to: state)
        let runtime = CharacterGIFPresentation(state: acting, at: 0)
        let samples = stride(from: 0.02, through: action.duration, by: 0.04).map {
          runtime.sample(at: $0, reduceMotion: false, duration: gifs.duration(for:))
        }
        XCTAssertTrue(samples.contains { $0.pose.surface != .identity || $0.pose.eyes.left.blink > 0.1 }, action.rawValue)
        let late = runtime.sample(at: 20, reduceMotion: false, duration: gifs.duration(for:))
        let control = CharacterGIFPresentation(state: state, at: 0)
          .sample(at: 20, reduceMotion: false, duration: gifs.duration(for:))
        XCTAssertEqual(late.pose.surface, control.pose.surface, action.rawValue)
        XCTAssertEqual(late.pose.mouth.openness, control.pose.mouth.openness, accuracy: 1e-9)
        XCTAssertEqual(late.pose.eyes.left.centerX, control.pose.eyes.left.centerX, accuracy: 1e-9)
        let reduced = runtime.sample(at: 0.1, reduceMotion: true, duration: gifs.duration(for:))
        XCTAssertEqual(reduced.pose.surface, .identity, action.rawValue)
      }
    }

    func testRigPreservesSilhouetteAndExportsActualCombinationReview() throws {
      let gifs = try CharacterGIFSet.norwegianForest.get()
      let rig = try CharacterGIFRig(gifs: gifs)
      let baseline = CharacterGIFRig.Bitmap(gifs.neutral)
      let face = CharacterGIFRig.face(in: baseline)
      XCTAssertNotNil(face.eyes[0]); XCTAssertNotNil(face.eyes[1])
      var samples: [(String, CharacterState, Double, Double)] = [("neutral", .idle, 0, 0)]
      for (name, x, y) in [("left", 0.0, 0.5), ("right", 1.0, 0.5), ("up", 0.5, 0.0), ("down", 0.5, 1.0)] {
        samples.append((name, send(.attentionFocused(try CharacterPoint(validatingX: x, y: y))), 0, 0.5))
      }
      for level in [0.0, 0.5, 1.0] {
        samples.append(("voice-\(level)", send(.voiceLevelChanged(level), to: send(.voiceStarted)), 1, 0.5))
      }
      let id = CharacterAnimationID(UUID())
      samples.append(("blink", send(.animationStarted(id: id, animation: .blink)), 0, 0.11))
      let directory = ProcessInfo.processInfo.environment["CHARACTERKIT_RIG_REVIEW_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
      }
      if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
      for (name, state, speech, time) in samples {
        let pose = ReactiveCharacter.pose(state: state, elapsed: time, projection: .flat, motionProfile: .companion)
        let image = rig.render(gifs.neutral, pose: pose, speechWeight: speech)
        let pixels = CharacterGIFRig.Bitmap(image).pixels
        for i in stride(from: 3, to: pixels.count, by: 4) {
          XCTAssertEqual(pixels[i], baseline.pixels[i], "Silhouette: \(name)")
        }
        if name != "neutral" { XCTAssertTrue(pixels != baseline.pixels, name) }
        if let directory { try save(image, to: directory.appendingPathComponent(name + ".png")) }
      }
      for emotion in CharacterEmotion.allCases {
        let image = try XCTUnwrap(gifs.image(for: emotion, elapsed: 0.96, reduceMotion: false))
        let bitmap = CharacterGIFRig.Bitmap(image)
        let landmarks = CharacterGIFRig.face(in: bitmap)
        let eyes = landmarks.eyes.compactMap { $0 }
        if eyes.count == 2 {
          // The nose must be above the mouth, even in compressed fear/sadness poses.
          let eyeY = eyes.map(\.midY).reduce(0, +) / 2
          XCTAssertLessThan(landmarks.nose.y - eyeY, 29, emotion.rawValue)
        }
        let state = send(.voiceLevelChanged(0.8), to: send(.voiceStarted))
        let pose = ReactiveCharacter.pose(state: state, elapsed: 0.5, projection: .flat, motionProfile: .companion)
        let articulated = rig.render(image, pose: pose, speechWeight: 1)
        if let directory { try save(articulated, to: directory.appendingPathComponent("emotion-\(emotion.rawValue)-voice.png")) }
      }
    }

    func testConcurrentCharactersKeepIndependentFrameCaches() throws {
      let gifs = try CharacterGIFSet.norwegianForest.get()
      let first = CharacterGIFFrameCache(), second = CharacterGIFFrameCache()
      let joy = try XCTUnwrap(gifs.image(for: .joy, elapsed: 0.8, reduceMotion: false, cache: first))
      let sad = try XCTUnwrap(gifs.image(for: .sadness, elapsed: 0.8, reduceMotion: false, cache: second))
      XCTAssertTrue(try gifs.image(for: .joy, elapsed: 0.8, reduceMotion: false, cache: first) === joy)
      _ = try gifs.image(for: .surprise, elapsed: 0.8, reduceMotion: false, cache: first)
      XCTAssertTrue(try gifs.image(for: .sadness, elapsed: 0.8, reduceMotion: false, cache: second) === sad)
    }

    private func save(_ image: CGImage, to url: URL) throws {
      let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
  }
#endif

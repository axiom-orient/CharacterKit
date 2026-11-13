import XCTest
@testable import ReactiveCharacterKit

final class CharacterGIFPlaybackTests: XCTestCase {
  private func duration(_ emotion: CharacterEmotion) -> Double { 2 }

  func testEmotionReturnsToSharedNeutralAndDoesNotLoop() throws {
    var playback = CharacterGIFPlayback(emotion: nil, at: 0)
    playback.update(emotion: .joy, at: 1, duration: duration)
    XCTAssertEqual(try XCTUnwrap(playback.sample(at: 1, duration: duration)).opacity, 0)
    XCTAssertEqual(try XCTUnwrap(playback.sample(at: 2, duration: duration)).emotion, .joy)
    XCTAssertNil(playback.sample(at: 3, duration: duration))
    XCTAssertNil(playback.sample(at: 20, duration: duration))
    playback.update(emotion: .joy, at: 21, duration: duration)
    XCTAssertNil(playback.sample(at: 21.5, duration: duration))
    playback.update(emotion: .joy, at: 22, duration: duration, force: true)
    XCTAssertEqual(try XCTUnwrap(playback.sample(at: 22, duration: duration)).opacity, 0)
    XCTAssertEqual(try XCTUnwrap(playback.sample(at: 23, duration: duration)).emotion, .joy)
  }

  func testInterruptedEmotionReturnsToNeutralBeforeNextStarts() throws {
    var playback = CharacterGIFPlayback(emotion: .joy, at: 0)
    let before = try XCTUnwrap(playback.sample(at: 1, duration: duration))
    playback.update(emotion: .sadness, at: 1, duration: duration)
    let interrupted = try XCTUnwrap(playback.sample(at: 1, duration: duration))
    XCTAssertEqual(interrupted.emotion, .joy)
    XCTAssertEqual(interrupted.elapsed, before.elapsed)
    XCTAssertEqual(interrupted.opacity, before.opacity, accuracy: 1e-12)
    let returning = try XCTUnwrap(playback.sample(at: 1.09, duration: duration))
    XCTAssertEqual(returning.emotion, .joy)
    XCTAssertEqual(returning.opacity, 0.5, accuracy: 1e-12)
    let next = try XCTUnwrap(playback.sample(at: 1.18, duration: duration))
    XCTAssertEqual(next.emotion, .sadness)
    XCTAssertEqual(next.opacity, 0, accuracy: 1e-12)
    XCTAssertNil(playback.sample(at: 3.18, duration: duration))
  }
}

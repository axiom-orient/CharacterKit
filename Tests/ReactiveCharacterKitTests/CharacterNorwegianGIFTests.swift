#if os(iOS) || os(macOS)
  import CoreGraphics
  import XCTest
  @testable import ReactiveCharacterKit

  @MainActor
  final class CharacterNorwegianGIFTests: XCTestCase {
    private func pixels(_ image: CGImage) throws -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
      let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return bytes
    }

    func testEveryBundledEmotionBeginsAndEndsWithTheSameNeutralPixels() throws {
      let set = try CharacterGIFSet.norwegianForest.get()
      let neutral = try pixels(set.neutral)
      XCTAssertEqual(set.neutral.width, 288)
      XCTAssertEqual(set.neutral.height, 288)
      var expressions = Set<Data>()
      for emotion in CharacterEmotion.allCases {
        let duration = set.duration(for: emotion)
        XCTAssertEqual(duration, 1.92, accuracy: 0.01)
        let first = try XCTUnwrap(set.image(for: emotion, elapsed: 0, reduceMotion: false))
        let last = try XCTUnwrap(set.image(for: emotion, elapsed: duration - 0.01, reduceMotion: false))
        let middle = try XCTUnwrap(set.image(for: emotion, elapsed: duration / 2, reduceMotion: false))
        XCTAssertTrue(try pixels(first) == neutral, "First frame: \(emotion.rawValue)")
        XCTAssertTrue(try pixels(last) == neutral, "Last frame: \(emotion.rawValue)")
        let expression = try pixels(middle)
        XCTAssertTrue(expression != neutral, "Motion: \(emotion.rawValue)")
        expressions.insert(Data(expression))
        XCTAssertNil(try set.image(for: emotion, elapsed: duration, reduceMotion: false))
      }
      XCTAssertEqual(expressions.count, CharacterEmotion.allCases.count)
    }
  }
#endif

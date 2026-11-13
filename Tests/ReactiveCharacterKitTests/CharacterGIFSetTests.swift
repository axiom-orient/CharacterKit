#if os(iOS) || os(macOS)
  import Foundation
  import ImageIO
  import UniformTypeIdentifiers
  import XCTest
  @testable import ReactiveCharacterKit

  @MainActor
  final class CharacterGIFSetTests: XCTestCase {
    private func image(_ red: CGFloat, width: Int = 2) throws -> CGImage {
      let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 2,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      return try XCTUnwrap(context.makeImage())
    }

    private func data(type: UTType, frames: [CGImage]) throws -> Data {
      let data = NSMutableData()
      let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
        data, type.identifier as CFString, frames.count, nil))
      for frame in frames {
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary
        CGImageDestinationAddImage(destination, frame, properties)
      }
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      return data as Data
    }

    func testCompleteSetDecodesFramesAndEndsWithoutLooping() throws {
      let first = try image(0)
      let second = try image(1)
      let neutral = try data(type: .png, frames: [first])
      let gif = try data(type: .gif, frames: [first, second])
      let gifs = Dictionary(uniqueKeysWithValues: CharacterEmotion.allCases.map { ($0, gif) })
      let set = try CharacterGIFSet(neutralData: neutral, emotionGIFs: gifs)

      XCTAssertEqual(set.duration(for: .joy), 0.4, accuracy: 0.01)
      let start = try XCTUnwrap(set.image(for: .joy, elapsed: 0.05, reduceMotion: false))
      let later = try XCTUnwrap(set.image(for: .joy, elapsed: 0.25, reduceMotion: false))
      XCTAssertFalse(start === later)
      XCTAssertNil(try set.image(for: .joy, elapsed: 0.4, reduceMotion: false))
    }

    func testMissingEmotionIsReported() throws {
      let neutral = try data(type: .png, frames: [image(0)])
      XCTAssertThrowsError(try CharacterGIFSet(neutralData: neutral, emotionGIFs: [:])) {
        guard case CharacterGIFSetError.missingEmotion = $0 else {
          return XCTFail("Unexpected error: \($0)")
        }
      }
    }

    func testDifferentCanvasSizeIsRejected() throws {
      let neutral = try data(type: .png, frames: [image(0)])
      let gif = try data(type: .gif, frames: [image(0, width: 3), image(1, width: 3)])
      let gifs = Dictionary(uniqueKeysWithValues: CharacterEmotion.allCases.map { ($0, gif) })
      XCTAssertThrowsError(try CharacterGIFSet(neutralData: neutral, emotionGIFs: gifs)) {
        guard case CharacterGIFSetError.invalidGIF = $0 else {
          return XCTFail("Unexpected error: \($0)")
        }
      }
    }
  }
#endif

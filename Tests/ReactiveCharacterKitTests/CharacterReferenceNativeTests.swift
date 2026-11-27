#if os(iOS) || os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import ReactiveCharacterKit

@MainActor
struct CharacterReferenceNativeTests {
  @Test(arguments: [CharacterReferenceAppearance.headsetFree(), .mascot(variant: .white), .mascot(variant: .hero)])
  func motionKeepsAuthoredArtworkInsideViewport(appearance: CharacterReferenceAppearance) throws {
    let direction = appearance.artDirection
    let id = try CharacterAnimationID(validating: "reference-viewport")
    let startled = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    let motions: [(CharacterAnimation, Double)] = [(.bounce, 0.25), (.celebrate, 0.15), (.recoil, 0.15)]
    for (width, height) in [(160.0, 160.0), (160.0, 238.0)] {
      let neutralPose = ReactiveCharacter.pose(state: .idle, elapsed: 0, artDirection: direction, reduceMotion: true)
      let neutral = try CharacterSceneBuilder.scene(
        pose: neutralPose, artDirection: direction, width: width, height: height, includeBackground: true)
      let body = try #require(neutral.nodes.first { $0.id == "reference.body" })
      let backdrop = try #require(neutral.nodes.first { $0.id == "reference.background" })
      let artWidth = Double(appearance.nativeWidth)
      let artHeight = Double(appearance.nativeHeight)
      let scale = min(width / artWidth, height / artHeight)
      #expect(neutral.surfaceTransform == .identity)
      #expect(body.transform == CharacterSceneTransform(
        a: scale, b: 0, c: 0, d: scale,
        tx: width / 2 - artWidth * scale / 2, ty: height / 2 - artHeight * scale / 2))
      #expect(backdrop.transform == body.transform)

      for (motion, fraction) in motions {
        let animated = ReactiveCharacter.reduce(
          state: startled, event: .animationStarted(id: id, animation: motion)).state
        let pose = ReactiveCharacter.pose(state: animated, elapsed: motion.duration * fraction, artDirection: direction)
        let scene = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction, width: width, height: height, includeBackground: true)
        let movingBody = try #require(scene.nodes.first { $0.id == "reference.body" })
        let staticBackdrop = try #require(scene.nodes.first { $0.id == "reference.background" })
        #expect(movingBody.transform != body.transform)
        #expect(staticBackdrop.transform == backdrop.transform)

        let transparent = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction, width: width, height: height, includeBackground: false)
        try expectUnclippedRaster(CharacterScenePNGRenderer.render(transparent))
      }
    }
  }

  private func expectUnclippedRaster(_ data: Data) throws {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let width = image.width
    let height = image.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    try rgba.withUnsafeMutableBytes { bytes in
      let context = try #require(CGContext(
        data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
          CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)).rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { rgba[(y * width + x) * 4 + 3] }
    #expect(alphaAt(width / 2, height / 2) > 120)
    #expect((0..<width).allSatisfy { alphaAt($0, 0) < 120 && alphaAt($0, height - 1) < 120 })
    #expect((0..<height).allSatisfy { alphaAt(0, $0) < 120 && alphaAt(width - 1, $0) < 120 })
  }
}
#endif

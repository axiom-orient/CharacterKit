#if os(iOS) || os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ReactiveCharacterKit

/// Runs only on an Apple SDK/runtime; Linux never counts this as passed.
@MainActor
struct CharacterSEMINativeTests {
  @Test(arguments: CharacterEmotion.allCases)
  func nativePNGUsesRealBundledLayers(emotion: CharacterEmotion) throws {
    let direction = CharacterArtDirection.semiDocumentCat
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8,
      projection: direction.projection, motionProfile: direction.motionProfile)
    let scene = try CharacterSceneBuilder.scene(pose: pose, artDirection: direction,
      width: 320, height: 320, includeBackground: false)
    let png = try CharacterScenePNGRenderer.render(scene, scale: 2)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 640)
    #expect(image.height == 640)
    #expect(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene).isEmpty)
  }

  @Test
  func nativePNGDrawsBundledHeadAndEarsAndKeepsTransparentPadding() throws {
    let direction = CharacterArtDirection.semiDocumentCat
    let pose = ReactiveCharacter.pose(
      state: .idle, elapsed: 0, reduceMotion: true,
      projection: direction.projection, motionProfile: direction.motionProfile)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 320, height: 320, includeBackground: false)
    let headAndEars = scene.nodes.filter {
      ["semi.head", "semi.ear.left", "semi.ear.right"].contains($0.id)
    }
    #expect(Set(headAndEars.compactMap { $0.image?.asset.name }) == [
      "semi-head", "semi-ear-left", "semi-ear-right",
    ])

    let isolatedScene = replacingNodes(in: scene, with: headAndEars)
    let isolatedPNG = try CharacterScenePNGRenderer.render(isolatedScene, scale: 2)
    let isolated = try rasterize(isolatedPNG)
    #expect(isolated.width == 640)
    #expect(isolated.height == 640)
    #expect(isolated.nontransparentPixelCount > 100)
    #expect(isolated.alphaAt(x: 0, y: 0) == 0)
    #expect(isolated.alphaAt(x: isolated.width - 1, y: 0) == 0)
    #expect(isolated.alphaAt(x: 0, y: isolated.height - 1) == 0)
    #expect(isolated.alphaAt(x: isolated.width - 1, y: isolated.height - 1) == 0)

    let fullPNG = try CharacterScenePNGRenderer.render(scene, scale: 2)
    let full = try rasterize(fullPNG)
    let vectorsOnly = try rasterize(CharacterScenePNGRenderer.render(
      replacingNodes(in: scene, with: scene.nodes.filter { $0.image == nil }), scale: 2))
    #expect(full.nontransparentPixelCount > isolated.nontransparentPixelCount)
    #expect(full.differingPixelCount(from: vectorsOnly) > 100)
    #expect(full.alphaAt(x: 0, y: 0) == 0)
    #expect(full.alphaAt(x: full.width - 1, y: full.height - 1) == 0)
  }

  private func replacingNodes(in scene: CharacterScene, with nodes: [CharacterSceneNode])
    -> CharacterScene
  {
    CharacterScene(
      width: scene.width, height: scene.height, faceBounds: scene.faceBounds,
      surfaceTransform: scene.surfaceTransform, nodes: nodes,
      effectiveMode: scene.effectiveMode, isCompact: scene.isCompact)
  }

  private func rasterize(_ data: Data) throws -> NativeRaster {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let didDraw = bytes.withUnsafeMutableBytes { storage -> Bool in
      guard let context = CGContext(
        data: storage.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
          CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)).rawValue)
      else { return false }
      context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    guard didDraw else { throw NativeRasterError.bitmapContextUnavailable }
    return NativeRaster(width: image.width, height: image.height, rgba: bytes)
  }
}

private struct NativeRaster {
  let width: Int
  let height: Int
  let rgba: [UInt8]

  var nontransparentPixelCount: Int {
    stride(from: 3, to: rgba.count, by: 4).reduce(0) { $0 + (rgba[$1] > 0 ? 1 : 0) }
  }

  func alphaAt(x: Int, y: Int) -> UInt8 {
    rgba[(y * width + x) * 4 + 3]
  }

  func differingPixelCount(from other: Self) -> Int {
    guard width == other.width, height == other.height else { return .max }
    return (0..<(width * height)).reduce(0) { count, pixel in
      let start = pixel * 4
      return count + (rgba[start..<(start + 4)] == other.rgba[start..<(start + 4)] ? 0 : 1)
    }
  }
}

private enum NativeRasterError: Error {
  case bitmapContextUnavailable
}
#endif

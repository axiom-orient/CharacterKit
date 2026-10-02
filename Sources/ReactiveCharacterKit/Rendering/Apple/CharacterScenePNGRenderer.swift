#if os(iOS) || os(macOS)
  import Foundation
  import SwiftUI
  import ImageIO
  import UniformTypeIdentifiers
  #if os(iOS)
    import UIKit
  #endif

  public enum CharacterPNGExportError: Error, Sendable, Equatable {
    case invalidScale(Double)
    case pixelBudgetExceeded(width: Double, height: Double)
    case renderingUnavailable
    case encodingFailed
  }

  /// Native raster output from the exact same validated scene as Canvas and SVG.
  /// No placeholder/error image may be reported as a successful PNG export.
  @available(iOS 16.0, macOS 13.0, *)
  @MainActor
  public enum CharacterScenePNGRenderer {
    public static let maximumPixelDimension = 8192.0
    public static let maximumPixelCount = 16_777_216.0

    public static func render(_ scene: CharacterScene, scale: Double = 1) throws -> Data {
      try CharacterSceneValidation.validate(scene)
      guard scale.isFinite, scale > 0 else { throw CharacterPNGExportError.invalidScale(scale) }
      let width = ceil(scene.width * scale)
      let height = ceil(scene.height * scale)
      guard width.isFinite, height.isFinite,
        width <= maximumPixelDimension, height <= maximumPixelDimension,
        width * height <= maximumPixelCount
      else { throw CharacterPNGExportError.pixelBudgetExceeded(width: width, height: height) }
      var seen = Set<CharacterImageAsset>()
      for node in scene.nodes {
        guard let asset = node.image?.asset, seen.insert(asset).inserted else { continue }
        guard CharacterPlatformImageLoader.named(asset) != nil else {
          throw CharacterImageResolutionError.unavailable(name: asset.name, source: asset.source)
        }
      }
      let renderer = ImageRenderer(content: CharacterSceneCanvas(scene: scene))
      renderer.scale = CGFloat(scale)
      renderer.isOpaque = false
      #if os(iOS)
        // iOS uses the native UIImage PNG encoder.
        guard let image = renderer.uiImage else { throw CharacterPNGExportError.renderingUnavailable }
        guard let data = image.pngData() else { throw CharacterPNGExportError.encodingFailed }
        return data
      #else
        guard let image = renderer.cgImage else { throw CharacterPNGExportError.renderingUnavailable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
          throw CharacterPNGExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CharacterPNGExportError.encodingFailed }
        return data as Data
      #endif
    }
  }
#endif

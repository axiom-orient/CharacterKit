import Foundation

#if os(iOS) || os(macOS)
  import SwiftUI
  #if os(iOS)
    import UIKit
    typealias CharacterPlatformImage = UIImage
  #else
    import AppKit
    typealias CharacterPlatformImage = NSImage
  #endif

  enum CharacterReferenceResourceError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    var description: String {
      switch self { case .unavailable(let name): "Unavailable character image: \(name)" }
    }
  }

  /// Platform image I/O only. Pose, scene construction and geometry are shared unchanged.
  enum CharacterPlatformImageLoader {
    static func load(url: URL?, name: String) throws -> CharacterPlatformImage {
      guard let url, let image = CharacterPlatformImage(contentsOfFile: url.path) else {
        throw CharacterReferenceResourceError.unavailable(name)
      }
      return image
    }
    static func named(_ asset: CharacterImageAsset) -> CharacterPlatformImage? {
      let bundle: Bundle = asset.source == .package ? .module : .main
      #if os(iOS)
        return UIImage(named: asset.name, in: bundle, compatibleWith: nil)
      #else
        return bundle.image(forResource: NSImage.Name(asset.name))
      #endif
    }
  }
  extension CharacterPlatformImage {
    var characterSwiftUIImage: Image {
      #if os(iOS)
        Image(uiImage: self)
      #else
        Image(nsImage: self)
      #endif
    }
  }
#endif

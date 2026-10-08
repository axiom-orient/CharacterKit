#if os(iOS) || os(macOS)
  import SwiftUI
  #if os(iOS)
    import UIKit
    typealias CharacterPlatformImage = UIImage
  #else
    import AppKit
    typealias CharacterPlatformImage = NSImage
  #endif

  extension CharacterRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
  }

  extension CharacterColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
  }

  extension CharacterSceneTransform {
    var cgTransform: CGAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
  }

  extension CharacterVectorPoint {
    var cgPoint: CGPoint { .init(x: x, y: y) }
  }

  enum CharacterPlatformImageLoader {
    static func named(_ asset: CharacterImageAsset) -> CharacterPlatformImage? {
      #if os(iOS)
        UIImage(named: asset.name, in: .module, compatibleWith: nil)
      #else
        Bundle.module.image(forResource: NSImage.Name(asset.name))
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

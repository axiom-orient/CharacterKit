#if os(iOS) || os(macOS)
  import SwiftUI

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
#endif

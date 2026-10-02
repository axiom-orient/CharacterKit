#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  enum CharacterImageOverlayRenderer {
    static func draw(
      context: inout GraphicsContext,
      coordinateSpace: CharacterRect,
      layout: CharacterLayout,
      overlays: [CharacterAccessoryOverlay],
      layer: CharacterAccessoryLayer,
      enabled: Bool
    ) {
      guard enabled else { return }
      for overlay in overlays
      where overlay.placement.layer == layer && overlay.placement.opacity > 0 {
        let placement = overlay.placement
        let image = overlay.tint == nil ? overlay.image : overlay.image.renderingMode(.template)
        var resolved = context.resolve(image)
        if let tint = overlay.tint { resolved.shading = .color(tint.swiftUIColor) }
        let envelope = CharacterAccessoryGeometry.envelope(
          for: placement, face: coordinateSpace, layout: layout)
        guard
          let fitted = CharacterAccessoryGeometry.aspectFit(
            image: CharacterSize(width: resolved.size.width, height: resolved.size.height),
            in: envelope
          )
        else { continue }
        var part = context
        part.opacity *= placement.opacity
        part.translateBy(x: envelope.midX, y: envelope.midY)
        part.rotate(by: .radians(placement.angle))
        part.draw(
          resolved,
          in: CGRect(
            x: -fitted.width / 2, y: -fitted.height / 2, width: fitted.width, height: fitted.height)
        )
      }
    }

  }
#endif

#if os(iOS) || os(macOS)
  import Foundation
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterArtFrame: View {
    let pose: CharacterPose
    let direction: CharacterArtDirection
    let overlayAccents: [CharacterAccentPose]
    let accessoryOverlays: [CharacterAccessoryOverlay]
    @Environment(\.characterBackgroundVisible) private var includesBackground
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
      GeometryReader { geometry in
        if geometry.size.width >= 1, geometry.size.height >= 1 {
          let result = Result {
            try CharacterSceneBuilder.scene(
              pose: pose, artDirection: direction,
              width: geometry.size.width, height: geometry.size.height,
              environment: .init(
                increasedContrast: contrast == .increased,
                reduceTransparency: reduceTransparency),
              includeBackground: includesBackground, overlayAccents: overlayAccents)
          }
          switch result {
          case .success(let scene):
            CharacterSceneCanvas(
              scene: scene,
              layout: direction.components.contains(.accessories) ? direction.layout : nil,
              accessoryOverlays: accessoryOverlays
            )
            .accessibilityValue(
              Text(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene)))
          case .failure(let error):
            Text("Character rendering failed: \(String(describing: error))")
              .font(.caption)
              .accessibilityIdentifier("character.art.error")
          }
        }
      }
    }

  }
#endif

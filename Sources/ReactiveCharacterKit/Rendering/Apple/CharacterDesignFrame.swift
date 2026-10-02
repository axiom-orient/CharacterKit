#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterDesignFrame: View {
    let pose: CharacterPose
    let design: CharacterDesign
    let partColors: CharacterPartColors?
    let overlayAccents: [CharacterAccentPose]
    let accessoryOverlays: [CharacterAccessoryOverlay]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.characterBackgroundVisible) private var includesBackground
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
      GeometryReader { geometry in
        // Sub-point size is a normal intermediate layout state, not a drawable character.
        if geometry.size.width >= 1, geometry.size.height >= 1 {
          let result = Result {
            try CharacterSceneBuilder.scene(
              pose: pose, design: design,
              width: geometry.size.width, height: geometry.size.height,
              environment: .init(
                appearance: colorScheme == .dark ? .dark : .light,
                increasedContrast: colorSchemeContrast == .increased,
                reduceTransparency: reduceTransparency,
                partColors: partColors
              ), includeBackground: includesBackground, overlayAccents: overlayAccents
            )
          }
          switch result {
          case .success(let scene):
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) {
              context, _ in
              CharacterSceneCanvasRenderer.draw(
                scene: scene, context: &context, design: design, overlays: accessoryOverlays
              )
            }
            .accessibilityValue(
              Text(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene)))
          case .failure(let error):
            Text("Character rendering failed: \(String(describing: error))")
              .font(.caption)
              .foregroundStyle(.primary)
              .accessibilityIdentifier("character.design.error")
          }
        }
      }
    }
  }
#endif

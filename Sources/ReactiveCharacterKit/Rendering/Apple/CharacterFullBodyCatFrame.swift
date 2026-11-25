#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterFullBodyCatFrame: View {
    let pose: CharacterPose
    let appearance: CharacterFullBodyCatAppearance
    let motion: CharacterFullBodyCatMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
      GeometryReader { geometry in
        if geometry.size.width >= 1, geometry.size.height >= 1 {
          let result = Result {
            try CharacterSceneBuilder.scene(
              pose: pose, fullBodyCat: appearance, motion: motion,
              width: geometry.size.width, height: geometry.size.height,
              environment: .init(
                appearance: colorScheme == .dark ? .dark : .light,
                increasedContrast: contrast == .increased, reduceTransparency: reduceTransparency))
          }
          switch result {
          case .success(let scene):
            CharacterSceneCanvas(scene: scene)
              .accessibilityValue(Text(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene)))
          case .failure(let error):
            Text("Character rendering failed: \(String(describing: error))")
              .font(.caption)
              .accessibilityIdentifier("character.fullBodyCat.error")
          }
        }
      }
    }
  }
#endif

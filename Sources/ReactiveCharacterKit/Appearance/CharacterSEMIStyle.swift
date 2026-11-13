import Foundation

extension CharacterArtDirection {
  /// A charcoal document cat. Fur is authored; eyes, mouth and articulation use the shared pose.
  /// This does not add an animation player, task state or a communication channel.
  public static let semiDocumentCat: Self = {
    do {
      return try Self(
        name: "SEMI Document Cat", components: .default.union([.nose, .writing]),
        style: .semiDocumentCat, projection: .softSphere, motionProfile: .cartoon,
        transitionProfile: .cartoon, contentInset: canonicalContentInset,
        anatomy: .semiDocumentCat)
    } catch { preconditionFailure("Invalid built-in SEMI art direction: \(error)") }
  }()
}

extension CharacterStyle {
  /// Eyes own the cream aperture; outline owns the pupil. Authored fur keeps its source colors.
  /// Accessory/accessoryDetail own the document and its mint tab, not communication state.
  public static let semiDocumentCat: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 0.115, green: 0.118, blue: 0.12),
          eyes: CharacterColor(red: 0.97, green: 0.95, blue: 0.86),
          nose: CharacterColor(red: 0.40, green: 0.79, blue: 0.73),
          mouth: CharacterColor(red: 0.88, green: 0.87, blue: 0.80),
          mouthDetail: CharacterColor(red: 0.86, green: 0.86, blue: 0.80),
          tongue: CharacterColor(red: 0.86, green: 0.48, blue: 0.57),
          writing: CharacterColor(red: 0.19, green: 0.39, blue: 0.36),
          accent: CharacterColor(red: 0.47, green: 0.82, blue: 0.75),
          accessory: CharacterColor(red: 0.94, green: 0.93, blue: 0.86),
          accessoryDetail: CharacterColor(red: 0.48, green: 0.80, blue: 0.71),
          outline: CharacterColor(red: 0.025, green: 0.026, blue: 0.027)),
        eyeTreatment: .vertical, mouthTreatment: .outline, lineWidth: 0.009)
    } catch { preconditionFailure("Invalid built-in SEMI style: \(error)") }
  }()
}

/// Resource references only. Authoring source and deterministic preparation live in Artwork/Tools.
enum CharacterSEMIAssets {
  static let head = asset("head")
  static let earLeft = asset("ear-left")
  static let earRight = asset("ear-right")
  static let pawLeft = asset("paw-left")
  static let pawRight = asset("paw-right")
  static let tail = asset("tail")
  static let all = [head, earLeft, earRight, pawLeft, pawRight, tail]

  private static func asset(_ part: String) -> CharacterImageAsset {
    .init(uncheckedName: "semi-\(part)", source: .package)
  }
}

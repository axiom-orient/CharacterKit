import Foundation

/// One visual authority for CharacterKit-owned accessory placement and occlusion.
enum CharacterBuiltInAccessoryID: CaseIterable {
  case headset
  case hood
  case baseballCap
  case bunnyEars
}

struct CharacterBuiltInAccessorySpec {
  let image: CharacterImageAsset
  let anchor: CharacterAssetAnchor
  let layer: CharacterAssetLayer
  let centerX: Double
  let centerY: Double
  let width: Double
  let height: Double
  let angle: Double
  let opacity: Double
  let accessibilityLabel: String
  let followLag: Double
  let squashRigidity: Double
  let hardOcclusion: [CharacterRect]

  var referenceRect: CharacterRect {
    CharacterRect(
      x: centerX - width / 2, y: centerY - height / 2,
      width: width, height: height)
  }

  var asset: CharacterAccessoryAsset {
    CharacterAccessoryAsset(
      uncheckedImage: image, anchor: anchor, layer: layer,
      centerX: centerX, centerY: centerY, width: width, height: height,
      angle: angle, opacity: opacity, accessibilityLabel: accessibilityLabel)
  }
}

enum CharacterBuiltInAccessoryCatalog {
  /// The headset wraps around the face rather than occupying face feature space.
  static let headsetAttachmentScale = 1.30

  static func headset(image: CharacterImageAsset) -> CharacterBuiltInAccessorySpec {
    CharacterBuiltInAccessorySpec(
      image: image,
      anchor: .face,
      layer: .behindFeatures,
      centerX: 0.50,
      centerY: 0.50,
      width: headsetAttachmentScale,
      height: headsetAttachmentScale,
      angle: 0,
      opacity: 1,
      accessibilityLabel: "Headset",
      followLag: 0,
      squashRigidity: 0,
      hardOcclusion: [
        .init(x: 0.18, y: 0.06, width: 0.64, height: 0.15),
        .init(x: 0.09, y: 0.16, width: 0.19, height: 0.23),
        .init(x: 0.72, y: 0.16, width: 0.19, height: 0.23),
        .init(x: 0.04, y: 0.34, width: 0.20, height: 0.32),
        .init(x: 0.76, y: 0.34, width: 0.20, height: 0.32),
        .init(x: 0.84, y: 0.57, width: 0.10, height: 0.16),
        .init(x: 0.79, y: 0.69, width: 0.10, height: 0.10),
      ])
  }

  static let headset = headset(image: .arcadeHeadset)

  static let hood = CharacterBuiltInAccessorySpec(
    image: .hood, anchor: .face, layer: .behindFeatures,
    centerX: 0.50, centerY: 0.48, width: 1.08, height: 1.08,
    angle: 0, opacity: 1, accessibilityLabel: "Hood",
    followLag: 0.008, squashRigidity: 0.12, hardOcclusion: [])

  static let baseballCap = CharacterBuiltInAccessorySpec(
    image: .baseballCap, anchor: .face, layer: .foreground,
    centerX: 0.50, centerY: 0.19, width: 1.00, height: 0.80,
    angle: 0, opacity: 1, accessibilityLabel: "Baseball cap",
    followLag: 0.016, squashRigidity: 0.74,
    hardOcclusion: [.init(x: 0.05, y: -0.05, width: 0.90, height: 0.40)])

  static let bunnyEars = CharacterBuiltInAccessorySpec(
    image: .bunnyEars, anchor: .face, layer: .foreground,
    centerX: 0.50, centerY: 0.09, width: 0.60, height: 0.58,
    angle: 0, opacity: 1, accessibilityLabel: "Bunny ears",
    followLag: 0.028, squashRigidity: 0.48,
    hardOcclusion: [
      .init(x: 0.12, y: -0.03, width: 0.20, height: 0.34),
      .init(x: 0.68, y: -0.03, width: 0.20, height: 0.34),
    ])

  static func spec(for id: CharacterBuiltInAccessoryID) -> CharacterBuiltInAccessorySpec {
    switch id {
    case .headset: headset
    case .hood: hood
    case .baseballCap: baseballCap
    case .bunnyEars: bunnyEars
    }
  }

  static func spec(for image: CharacterImageAsset) -> CharacterBuiltInAccessorySpec? {
    guard image.source == .package else { return nil }
    if [.blackHeadset, .whiteHeadset, .arcadeHeadset].contains(image) {
      return headset(image: image)
    }
    for id in CharacterBuiltInAccessoryID.allCases {
      let candidate = spec(for: id)
      if candidate.image == image { return candidate }
    }
    return nil
  }

}

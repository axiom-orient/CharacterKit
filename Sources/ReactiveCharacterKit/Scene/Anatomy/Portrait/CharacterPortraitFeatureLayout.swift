import Foundation

/// Authored placement, not expression state. The same eye/brow/mouth channels drive both rigs.
struct CharacterPortraitFeatureLayout {
  struct Eye {
    let center: CharacterVectorPoint
    let width: Double
    let height: Double
    let brow: CharacterVectorPoint
    let browHalfWidth: Double
  }

  let left: Eye
  let right: Eye
  let mouth: CharacterVectorPoint
  let mouthHalfWidth: Double
  let mouthLineWidth: Double
  let nose: CharacterVectorPoint
  let browArch: Double
  let expressionScale: Double
  let accessoryTransform: CharacterSceneTransform
  let capTransform: CharacterSceneTransform

  static let boySourceBounds = CharacterRect(x: 20, y: 80, width: 704, height: 848)

  static func sourceBounds(for style: CharacterPortraitStyle) -> CharacterRect {
    style.boyViewpoint == nil
      ? .init(x: 0, y: 0, width: CharacterPortraitGeometry.width,
              height: CharacterPortraitGeometry.height)
      : boySourceBounds
  }

  static func resolve(_ style: CharacterPortraitStyle) -> Self {
    guard let viewpoint = style.boyViewpoint else { return classic }
    switch viewpoint {
    case .front: return boyFront
    case .threeQuarterRight: return boyQuarter
    }
  }

  private typealias G = CharacterPortraitGeometry

  private static let classic = Self(
    left: .init(center: .init(x: G.eyeCenters.left, y: G.eyeY), width: G.eyeWidth, height: G.eyeHeight,
                brow: .init(x: G.eyeCenters.left, y: G.browY), browHalfWidth: G.browHalfWidth),
    right: .init(center: .init(x: G.eyeCenters.right, y: G.eyeY), width: G.eyeWidth, height: G.eyeHeight,
                 brow: .init(x: G.eyeCenters.right, y: G.browY), browHalfWidth: G.browHalfWidth),
    mouth: G.mouthCenter, mouthHalfWidth: G.mouthHalfWidth, mouthLineWidth: G.mouthLineWidth,
    nose: .init(x: 256, y: 324), browArch: G.neutralBrowRise, expressionScale: 1, accessoryTransform: .identity, capTransform: .identity)

  private static let boyFront = Self(
    left: .init(center: .init(x: 282.6, y: 563.4), width: 49, height: 83,
                brow: .init(x: 282, y: 485), browHalfWidth: 33),
    right: .init(center: .init(x: 479.7, y: 564.2), width: 49.5, height: 83,
                 brow: .init(x: 486, y: 487), browHalfWidth: 33),
    mouth: .init(x: 378.5, y: 646), mouthHalfWidth: 19.7, mouthLineWidth: 5.2,
    nose: .init(x: 378, y: 584), browArch: 14, expressionScale: 1.42,
    accessoryTransform: .init(a: 1.48, b: 0, c: 0, d: 1.48, tx: -6.9, ty: 53),
    capTransform: .init(a: 1.48, b: 0, c: 0, d: 1.48, tx: -6.9, ty: 53))

  private static let boyQuarter = Self(
    left: .init(center: .init(x: 384.4, y: 566.2), width: 45.4, height: 82,
                brow: .init(x: 384, y: 488), browHalfWidth: 36),
    right: .init(center: .init(x: 535.8, y: 567.0), width: 38.1, height: 80,
                 brow: .init(x: 541, y: 492), browHalfWidth: 24),
    mouth: .init(x: 462.7, y: 647.5), mouthHalfWidth: 17.4, mouthLineWidth: 5.2,
    nose: .init(x: 461, y: 586), browArch: 17, expressionScale: 1.38,
    accessoryTransform: .init(a: 1.40, b: 0, c: -0.11, d: 1.48, tx: 51, ty: 53),
    capTransform: .init(a: 1.50, b: 0, c: -0.11, d: 1.48, tx: -10, ty: 53))
}

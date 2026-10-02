import Foundation

extension CharacterFeaturePlacement {
  /// Maps renderer-neutral placement into an authored mouth region while keeping the design's
  /// region authoritative. Offsets are face-relative; scaling is local to the mouth region.
  func adjusted(region: CharacterRect, within face: CharacterRect) -> CharacterRect {
    let width = region.width * scaleX
    let height = region.height * scaleY
    return CharacterRect(
      x: region.midX - width * 0.5 + offsetX * face.width,
      y: region.midY - height * 0.5 + offsetY * face.height,
      width: width,
      height: height
    )
  }

  /// Same placement for scene-node renderers that keep canonical path geometry immutable.
  func transform(anchorX: Double, anchorY: Double, face: CharacterRect) -> CharacterSceneTransform {
    .around(
      x: anchorX,
      y: anchorY,
      scaleX: scaleX,
      scaleY: scaleY,
      offsetX: offsetX * face.width,
      offsetY: offsetY * face.height
    )
  }
}

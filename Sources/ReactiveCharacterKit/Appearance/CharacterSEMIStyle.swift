import Foundation

/// Package-owned image identity. CharacterKit intentionally does not expose arbitrary host artwork.
public struct CharacterImageAsset: Sendable, Equatable, Hashable {
  public let name: String
  init(_ name: String) { self.name = name }
}

struct CharacterSEMIPalette: Sendable, Equatable {
  let surface = CharacterColor(uncheckedRed: 0.115, green: 0.118, blue: 0.12)
  let eyes = CharacterColor(uncheckedRed: 0.97, green: 0.95, blue: 0.86)
  let nose = CharacterColor(uncheckedRed: 0.40, green: 0.79, blue: 0.73)
  let mouth = CharacterColor(uncheckedRed: 0.88, green: 0.87, blue: 0.80)
  let mouthDetail = CharacterColor(uncheckedRed: 0.86, green: 0.86, blue: 0.80)
  let writing = CharacterColor(uncheckedRed: 0.19, green: 0.39, blue: 0.36)
  let document = CharacterColor(uncheckedRed: 0.94, green: 0.93, blue: 0.86)
  let documentDetail = CharacterColor(uncheckedRed: 0.48, green: 0.80, blue: 0.71)
  let outline = CharacterColor(uncheckedRed: 0.025, green: 0.026, blue: 0.027)
}

enum CharacterSEMIStyle {
  static let palette = CharacterSEMIPalette()
  static let contentInset = 0.12

  static let head = CharacterImageAsset("semi-head")
  static let earLeft = CharacterImageAsset("semi-ear-left")
  static let earRight = CharacterImageAsset("semi-ear-right")
  static let pawLeft = CharacterImageAsset("semi-paw-left")
  static let pawRight = CharacterImageAsset("semi-paw-right")
  static let tail = CharacterImageAsset("semi-tail")
  static let assets = [head, earLeft, earRight, pawLeft, pawRight, tail]
}

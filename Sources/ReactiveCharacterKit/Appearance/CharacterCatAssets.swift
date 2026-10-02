/// Immutable package artwork references. No scene construction or resource I/O.
enum CharacterCatAssets {
  static let head = asset("cat-head")
  static let neck = asset("cat-neck")
  static let earLeft = asset("cat-ear-left")
  static let earRight = asset("cat-ear-right")
  static let nose = asset("cat-nose")
  static let whiskerLeft = asset("cat-whiskers-left")
  static let whiskerRight = asset("cat-whiskers-right")
  static let pawPad = asset("cat-paw-pad")
  static let body = [neck, earLeft, earRight, head]
  static let whiskers = [whiskerLeft, whiskerRight]
  static let supplemental = [pawPad]
  static let all = body + [nose] + whiskers + supplemental

  private static func asset(_ name: String) -> CharacterImageAsset {
    .init(uncheckedName: name, source: .package)
  }
}

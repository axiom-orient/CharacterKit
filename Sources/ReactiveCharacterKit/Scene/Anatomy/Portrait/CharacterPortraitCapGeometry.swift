import Foundation

/// Authored in the original portrait space; the rig applies one transform to both paths.
/// The shared lower edge is the cap/hair boundary, including outside the crown silhouette.
enum CharacterPortraitCapGeometry {
  private static func lowerEdge(_ p: inout CharacterVectorPath) {
    p.cubic(110, 197, 178, 177, 256, 176)
    p.cubic(326, 176, 395, 190, 462, 234)
  }

  static let crown: CharacterVectorPath = {
    var p = CharacterVectorPath()
    p.move(55, 216)
    lowerEdge(&p)
    p.cubic(465, 103, 390, 34, 258, 36)
    p.cubic(139, 34, 53, 96, 55, 216)
    p.close()
    return p
  }()

  static let hairVisibility: CharacterVectorPath = {
    var p = CharacterVectorPath()
    // Extend beyond the source sheet to hide side cowlicks, not just the top spike.
    p.move(-512, 216)
    p.line(55, 216)
    lowerEdge(&p)
    p.line(1024, 234)
    p.line(1024, 1086)
    p.line(-512, 1086)
    p.close()
    return p
  }()
}

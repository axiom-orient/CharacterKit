import Foundation

/// Fixed procedural geometry for the portrait anatomy.
/// Semantic expression remains owned by `CharacterPose`; this type only maps it into drawing space.
enum CharacterPortraitGeometry {
  static let width = 512.0
  static let height = 560.0
  static let eyeCenters = (left: 191.0, right: 321.0)
  static let eyeY = 316.0
  static let eyeWidth = 32.0
  static let eyeHeight = 58.0
  static let expressionWidth = 48.0
  static let browY = 264.0
  static let browHalfWidth = 21.0
  static let gazeTravelX = 8.0
  static let gazeTravelY = 7.0
  static let mouthCenter = CharacterVectorPoint(x: 256, y: 378)
  static let browLiftTravel = 18.0
  static let browBendTravel = 12.0
  static let neutralBrowRise = 3.0
  static let browLineWidth = 5.2
  static let faceLineWidth = 4.0
  static let mouthHalfWidth = 14.0
  static let mouthLineWidth = 4.2

  static let face: CharacterVectorPath = {
    var p = CharacterVectorPath()
    p.move(100, 216)
    p.cubic(101, 157, 170, 129, 256, 129)
    p.cubic(342, 129, 411, 157, 412, 216)
    p.line(412, 334)
    p.cubic(414, 404, 355, 429, 256, 429)
    p.cubic(157, 429, 98, 404, 100, 334)
    p.close()
    return p
  }()

  static func backHair(_ style: CharacterPortraitStyle.ClassicHairstyle) -> CharacterVectorPath {
    var p = CharacterVectorPath()
    switch style {
    case .bob:
      p.move(36, 248)
      p.cubic(41, 98, 132, 38, 256, 38)
      p.cubic(380, 38, 471, 98, 476, 248)
      p.line(479, 371)
      p.cubic(481, 413, 461, 437, 420, 440)
      p.quad(355, 449, 309, 431)
      p.line(203, 431)
      p.quad(157, 449, 92, 440)
      p.cubic(51, 437, 31, 413, 33, 371)
      p.close()
    case .sidePart:
      p.move(99, 228)
      p.cubic(101, 120, 171, 65, 271, 59)
      p.cubic(364, 63, 416, 121, 416, 223)
      p.line(416, 369)
      p.cubic(391, 399, 353, 412, 326, 402)
      p.line(187, 402)
      p.cubic(150, 416, 116, 395, 99, 362)
      p.close()
    }
    return p
  }

  static func fringe(_ style: CharacterPortraitStyle.ClassicHairstyle) -> CharacterVectorPath {
    var p = CharacterVectorPath()
    switch style {
    case .bob:
      p.move(89, 120)
      p.line(423, 120)
      p.line(423, 236)
      p.line(354, 236)
      p.line(342, 177)
      p.line(340, 236)
      p.line(265, 236)
      p.line(259, 174)
      p.line(253, 236)
      p.line(176, 236)
      p.line(175, 174)
      p.line(160, 236)
      p.line(89, 236)
      p.close()
      for left in [true, false] {
        func x(_ value: Double) -> Double { left ? value : width - value }
        p.move(x(82), 230)
        p.line(x(109), 230)
        p.line(x(111), 330)
        p.quad(x(110), 365, x(125), 389)
        p.quad(x(79), 391, x(80), 338)
        p.close()
      }
    case .sidePart:
      p.move(130, 119)
      p.cubic(177, 88, 259, 83, 343, 108)
      p.cubic(311, 127, 285, 153, 261, 205)
      p.cubic(225, 176, 184, 160, 132, 166)
      p.close()
    }
    return p
  }

  static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
    min(upper, max(lower, value))
  }

  static func clipCenter(_ style: CharacterPortraitStyle.Hairstyle) -> CharacterVectorPoint {
    switch style {
    case .bob: .init(x: 411, y: 202)
    case .sidePart: .init(x: 375, y: 153)
    case .crop: .init(x: 369, y: 155)
    }
  }
}

import Foundation

struct CharacterSize: Sendable, Equatable {
  let width: Double
  let height: Double
}

struct CharacterRect: Sendable, Equatable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  var minX: Double { x }
  var minY: Double { y }
  var maxX: Double { x + width }
  var maxY: Double { y + height }
  var midX: Double { x + width / 2 }
  var midY: Double { y + height / 2 }
}

struct CharacterCapsule: Sendable, Equatable {
  let centerX: Double
  let centerY: Double
  let width: Double
  let height: Double
  let angle: Double
}

enum CharacterGeometry {
  static func fullRect(in size: CharacterSize) -> CharacterRect {
    CharacterRect(
      x: 0,
      y: 0,
      width: max(size.width, 0),
      height: max(size.height, 0)
    )
  }

  static func inscribedSquare(in size: CharacterSize) -> CharacterRect {
    let width = max(size.width, 0)
    let height = max(size.height, 0)
    let side = min(width, height)
    return CharacterRect(
      x: (width - side) / 2,
      y: (height - side) / 2,
      width: side,
      height: side
    )
  }

  static func coordinateSpace(
    in size: CharacterSize,
    surface: CharacterSurface
  ) -> CharacterRect {
    switch surface {
    case .visible:
      inscribedSquare(in: size)
    case .transparent:
      fullRect(in: size)
    }
  }

  static func map(
    _ region: CharacterRegion,
    into bounds: CharacterRect
  ) -> CharacterRect {
    CharacterRect(
      x: bounds.x + region.x * bounds.width,
      y: bounds.y + region.y * bounds.height,
      width: region.width * bounds.width,
      height: region.height * bounds.height
    )
  }

  static func fitCapsule(
    preferredCenterX: Double,
    preferredCenterY: Double,
    preferredWidth: Double,
    preferredHeight: Double,
    angle: Double,
    inside region: CharacterRect
  ) -> CharacterCapsule {
    let safeWidth = max(preferredWidth, 0.000_001)
    let safeHeight = max(preferredHeight, 0.000_001)
    let cosine = abs(cos(angle))
    let sine = abs(sin(angle))
    let preferredExtentX = cosine * safeWidth / 2 + sine * safeHeight / 2
    let preferredExtentY = sine * safeWidth / 2 + cosine * safeHeight / 2
    let scale = min(
      1,
      region.width / max(preferredExtentX * 2, 0.000_001),
      region.height / max(preferredExtentY * 2, 0.000_001)
    )
    let width = safeWidth * scale
    let height = safeHeight * scale
    let extentX = cosine * width / 2 + sine * height / 2
    let extentY = sine * width / 2 + cosine * height / 2
    let centerX = clamp(
      preferredCenterX,
      lower: region.minX + extentX,
      upper: region.maxX - extentX
    )
    let centerY = clamp(
      preferredCenterY,
      lower: region.minY + extentY,
      upper: region.maxY - extentY
    )
    return CharacterCapsule(
      centerX: centerX,
      centerY: centerY,
      width: width,
      height: height,
      angle: angle
    )
  }

  private static func clamp(
    _ value: Double,
    lower: Double,
    upper: Double
  ) -> Double {
    guard lower <= upper else { return (lower + upper) / 2 }
    return min(max(value, lower), upper)
  }
}

import Foundation

struct CharacterSize: Sendable, Equatable { let width: Double; let height: Double }

struct CharacterRect: Sendable, Equatable {
  let x: Double; let y: Double; let width: Double; let height: Double
  var minX: Double { x }; var minY: Double { y }; var maxX: Double { x + width }; var maxY: Double { y + height }
  var midX: Double { x + width / 2 }; var midY: Double { y + height / 2 }
}

enum CharacterGeometry {
  static func inscribedSquare(in size: CharacterSize) -> CharacterRect {
    let width = max(size.width, 0), height = max(size.height, 0), side = min(width, height)
    return CharacterRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
  }
}

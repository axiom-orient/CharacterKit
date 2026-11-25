import Foundation

/// Fixed marks are authored in the part's own coordinates, so the grain moves with the wax.
enum CharacterCrayonCatMarks {
  private typealias Path = CharacterVectorPath
  private typealias Rect = CharacterRect

  static func looseContour(_ path: CharacterVectorPath) -> CharacterVectorPath {
    path.mapped { point in
      let pressure = 1.45 + 0.95 * sin(point.x * 0.074 + point.y * 0.085)
      return .init(
        x: point.x + pressure * sin(point.y * 0.131 + point.x * 0.054),
        y: point.y + pressure * sin(point.x * 0.122 - point.y * 0.065))
    }
  }

  static func strokePatch(
    in path: CharacterVectorPath, tone: CharacterCrayonCatArtwork.Tone, raisedFur: Bool
  ) -> CharacterVectorPath {
    guard let bounds = controlBounds(of: path) else { return .init() }
    let broad = tone == .head || tone == .torso
    // Leave the middle of the face quiet, and follow the slant of the cheek and haunch.
    let patches: [(x: Double, y: Double, slope: Double)] = switch tone {
    case .head: [(0.14, 0.32, 0.56), (0.66, 0.31, -0.12), (0.09, 0.75, 0.26), (0.63, 0.83, 0.23)]
    case .torso where raisedFur: [(0.48, 0.29, 0.82), (0.67, 0.36, 0.88), (0.40, 0.60, 0.26), (0.68, 0.65, 0.41)]
    case .torso: [(0.21, 0.46, 0.57), (0.50, 0.34, 0.20), (0.40, 0.77, -0.16), (0.68, 0.69, 0.39)]
    case .tail where raisedFur: [(0.53, 0.27, 0.82), (0.46, 0.56, 0.65)]
    case .tail, .near, .far: [(0.22, 0.48, 0.5), (0.49, 0.73, 0.23)]
    }
    var marks = Path()
    for (index, patch) in patches.enumerated() {
      for pass in 0..<(broad ? 5 : 3) {
        let sample = Double(index * 7 + pass + 1)
        let advance = Double(pass) - (broad ? 2 : 1)
        let x = bounds.x + bounds.width * (patch.x + 0.045 * advance + 0.043 * sin(sample * 2.4))
        let y = bounds.y + bounds.height * (patch.y + 0.028 * advance + 0.031 * cos(sample * 3.1))
        let length = min(bounds.width * 0.22,
          (broad ? 2.0 : 1.5) + (broad ? 12 : 5) * pow(0.5 + 0.5 * sin(sample * 2.15), 2))
        let rise = length * (patch.slope + 0.16 * sin(sample * 1.4))
        marks.move(x, y)
        marks.quad(x + length * 0.44, y - rise * 0.46 - sin(sample) * 1.5, x + length, y - rise)
      }
    }
    return marks
  }

  private static func controlBounds(of path: Path) -> Rect? {
    let points = path.commands.flatMap { command -> [CharacterVectorPoint] in
      return switch command {
      case .move(let point), .line(let point): [point]
      case .quad(let control, let end): [control, end]
      case .cubic(let first, let second, let end): [first, second, end]
      case .close: []
      }
    }
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
    else { return nil }
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

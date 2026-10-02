import Foundation

public struct CharacterVectorPoint: Sendable, Equatable {
  public let x: Double
  public let y: Double
}

public enum CharacterVectorCommand: Sendable, Equatable {
  case move(CharacterVectorPoint)
  case line(CharacterVectorPoint)
  case quad(control: CharacterVectorPoint, end: CharacterVectorPoint)
  case cubic(
    control1: CharacterVectorPoint, control2: CharacterVectorPoint, end: CharacterVectorPoint)
  case close
}

/// Backend-neutral geometry. No SwiftUI, CoreGraphics, image handles or state effects.
public struct CharacterVectorPath: Sendable, Equatable {
  public internal(set) var commands: [CharacterVectorCommand] = []

  mutating func move(_ x: Double, _ y: Double) { commands.append(.move(.init(x: x, y: y))) }
  mutating func line(_ x: Double, _ y: Double) { commands.append(.line(.init(x: x, y: y))) }
  mutating func quad(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
    commands.append(.quad(control: .init(x: cx, y: cy), end: .init(x: x, y: y)))
  }
  mutating func cubic(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double
  ) {
    commands.append(
      .cubic(control1: .init(x: x1, y: y1), control2: .init(x: x2, y: y2), end: .init(x: x, y: y)))
  }
  mutating func close() { commands.append(.close) }
}

extension CharacterVectorPath {
  static func rectangle(_ r: CharacterRect) -> Self {
    var p = Self()
    p.move(r.minX, r.minY)
    p.line(r.maxX, r.minY)
    p.line(r.maxX, r.maxY)
    p.line(r.minX, r.maxY)
    p.close()
    return p
  }

  static func roundedRectangle(_ r: CharacterRect, radius: Double) -> Self {
    let v = max(0, min(radius, r.width / 2, r.height / 2))
    let k = 0.5522847498307936 * v
    var p = Self()
    p.move(r.minX + v, r.minY)
    p.line(r.maxX - v, r.minY)
    p.cubic(r.maxX - v + k, r.minY, r.maxX, r.minY + v - k, r.maxX, r.minY + v)
    p.line(r.maxX, r.maxY - v)
    p.cubic(r.maxX, r.maxY - v + k, r.maxX - v + k, r.maxY, r.maxX - v, r.maxY)
    p.line(r.minX + v, r.maxY)
    p.cubic(r.minX + v - k, r.maxY, r.minX, r.maxY - v + k, r.minX, r.maxY - v)
    p.line(r.minX, r.minY + v)
    p.cubic(r.minX, r.minY + v - k, r.minX + v - k, r.minY, r.minX + v, r.minY)
    p.close()
    return p
  }

  static func ellipse(_ r: CharacterRect) -> Self {
    let k = 0.5522847498307936
    let rx = r.width / 2
    let ry = r.height / 2
    var p = Self()
    p.move(r.midX, r.minY)
    p.cubic(r.midX + rx * k, r.minY, r.maxX, r.midY - ry * k, r.maxX, r.midY)
    p.cubic(r.maxX, r.midY + ry * k, r.midX + rx * k, r.maxY, r.midX, r.maxY)
    p.cubic(r.midX - rx * k, r.maxY, r.minX, r.midY + ry * k, r.minX, r.midY)
    p.cubic(r.minX, r.midY - ry * k, r.midX - rx * k, r.minY, r.midX, r.minY)
    p.close()
    return p
  }

  func mapped(_ convert: (CharacterVectorPoint) -> CharacterVectorPoint) -> Self {
    var result = Self()
    result.commands = commands.map { command in
      switch command {
      case .move(let p): .move(convert(p))
      case .line(let p): .line(convert(p))
      case .quad(let c, let e): .quad(control: convert(c), end: convert(e))
      case .cubic(let c1, let c2, let e):
        .cubic(control1: convert(c1), control2: convert(c2), end: convert(e))
      case .close: .close
      }
    }
    return result
  }
}

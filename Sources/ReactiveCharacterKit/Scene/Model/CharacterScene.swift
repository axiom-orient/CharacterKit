import Foundation

public enum CharacterSceneLayer: Int, CaseIterable, Sendable, Equatable {
  case background, behindSurface, surface, behindFeatures, features, foreground
}

public struct CharacterRenderBounds: Sendable, Equatable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  init(_ rect: CharacterRect) {
    x = rect.x; y = rect.y; width = rect.width; height = rect.height
  }

  var rect: CharacterRect { .init(x: x, y: y, width: width, height: height) }
}

public struct CharacterSceneTransform: Sendable, Equatable {
  public let a: Double
  public let b: Double
  public let c: Double
  public let d: Double
  public let tx: Double
  public let ty: Double

  public static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

  func concatenating(_ other: Self) -> Self {
    Self(
      a: a * other.a + c * other.b, b: b * other.a + d * other.b,
      c: a * other.c + c * other.d, d: b * other.c + d * other.d,
      tx: a * other.tx + c * other.ty + tx, ty: b * other.tx + d * other.ty + ty)
  }

  static func around(
    x: Double, y: Double, angle: Double = 0,
    scaleX: Double = 1, scaleY: Double = 1, offsetX: Double = 0, offsetY: Double = 0
  ) -> Self {
    let cosine = cos(angle), sine = sin(angle)
    let a = cosine * scaleX, b = sine * scaleX
    let c = -sine * scaleY, d = cosine * scaleY
    return Self(
      a: a, b: b, c: c, d: d,
      tx: x + offsetX - a * x - c * y,
      ty: y + offsetY - b * x - d * y)
  }
}

public struct CharacterGradientStop: Sendable, Equatable {
  public let location: Double
  public let color: CharacterColor
  public let opacity: Double

  init(location: Double, color: CharacterColor, opacity: Double) {
    self.location = location; self.color = color; self.opacity = opacity
  }
}

public enum CharacterScenePaint: Sendable, Equatable {
  case solid(CharacterColor)
  case linear(start: CharacterVectorPoint, end: CharacterVectorPoint, stops: [CharacterGradientStop])
  case radial(center: CharacterVectorPoint, radius: Double, stops: [CharacterGradientStop])
}

public enum CharacterImageContentMode: Sendable, Equatable { case fit, fill }

public struct CharacterSceneImage: Sendable, Equatable {
  public let asset: CharacterImageAsset
  public let bounds: CharacterRenderBounds
  public let contentMode: CharacterImageContentMode
}

public struct CharacterSceneNode: Sendable, Equatable {
  public let id: String
  public let layer: CharacterSceneLayer
  public let path: CharacterVectorPath
  public let fill: CharacterScenePaint?
  public let stroke: CharacterColor?
  public let lineWidth: Double
  public let opacity: Double
  public let transform: CharacterSceneTransform
  public let clips: [CharacterVectorPath]
  public let image: CharacterSceneImage?

  init(
    id: String, layer: CharacterSceneLayer, path: CharacterVectorPath,
    fill: CharacterScenePaint?, stroke: CharacterColor?, lineWidth: Double,
    opacity: Double, transform: CharacterSceneTransform, clips: [CharacterVectorPath],
    image: CharacterSceneImage? = nil
  ) {
    self.id = id; self.layer = layer; self.path = path; self.fill = fill; self.stroke = stroke
    self.lineWidth = lineWidth; self.opacity = opacity; self.transform = transform
    self.clips = clips; self.image = image
  }
}

/// Immutable SEMI frame. Renderers consume it and never mutate semantic state.
public struct CharacterScene: Sendable, Equatable {
  public let width: Double
  public let height: Double
  public let faceBounds: CharacterRenderBounds
  public let surfaceTransform: CharacterSceneTransform
  public let nodes: [CharacterSceneNode]
  public let isCompact: Bool
}

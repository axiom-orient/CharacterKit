import Foundation

enum CharacterRenderLimits {
  static let viewport: ClosedRange<Double> = 1...16_384
  static let maximumOverlayAccents = 32
  static let artCompactBelow: Double = 64
}

/// One postcondition owner for backend-neutral scene output.
/// Builders may perform intermediate floating-point composition, but a successful scene
/// must contain only finite geometry before it reaches Canvas or SVG serialization.
enum CharacterSceneValidation {
  static func validated(_ scene: CharacterScene) throws -> CharacterScene {
    try validate(scene)
    return scene
  }

  static func validate(_ scene: CharacterScene) throws {
    try finite([scene.width, scene.height], path: "scene.viewport")
    try finite(
      [scene.faceBounds.x, scene.faceBounds.y, scene.faceBounds.width, scene.faceBounds.height],
      path: "scene.faceBounds")
    try transform(scene.surfaceTransform, path: "scene.surfaceTransform")

    var identifiers = Set<String>()
    for (index, node) in scene.nodes.enumerated() {
      let path = "scene.nodes[\(index)](\(node.id))"
      guard !node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CharacterDesignError.invalid(path: path + ".id", reason: "empty node identity")
      }
      guard identifiers.insert(node.id).inserted else {
        throw CharacterDesignError.invalid(path: path + ".id", reason: "duplicate node identity")
      }
      try finite([node.lineWidth, node.opacity], path: path)
      guard node.lineWidth >= 0, (0...1).contains(node.opacity) else {
        throw CharacterDesignError.invalid(path: path, reason: "invalid line width or opacity")
      }
      try transform(node.transform, path: "\(path).transform")
      try vectorPath(node.path, path: "\(path).path")
      for (clipIndex, clip) in node.clips.enumerated() {
        try vectorPath(clip, path: "\(path).clips[\(clipIndex)]")
      }
      if let image = node.image {
        try finite(
          [image.bounds.x, image.bounds.y, image.bounds.width, image.bounds.height],
          path: "\(path).image.bounds")
        guard image.bounds.width >= 0, image.bounds.height >= 0 else {
          throw CharacterDesignError.invalid(
            path: "\(path).image.bounds", reason: "negative image extent")
        }
      }
      if let fill = node.fill {
        try paint(fill, path: "\(path).fill")
      }
      if let stroke = node.stroke {
        try color(stroke, path: "\(path).stroke")
      }
    }
  }

  private static func transform(_ value: CharacterSceneTransform, path: String) throws {
    try finite([value.a, value.b, value.c, value.d, value.tx, value.ty], path: path)
  }

  private static func vectorPath(_ value: CharacterVectorPath, path: String) throws {
    for (index, command) in value.commands.enumerated() {
      let points: [CharacterVectorPoint]
      switch command {
      case .move(let point), .line(let point):
        points = [point]
      case .quad(let control, let end):
        points = [control, end]
      case .cubic(let control1, let control2, let end):
        points = [control1, control2, end]
      case .close:
        points = []
      }
      for point in points {
        try finite([point.x, point.y], path: "\(path).commands[\(index)]")
      }
    }
  }

  private static func paint(_ value: CharacterScenePaint, path: String) throws {
    switch value {
    case .solid(let solid):
      try color(solid, path: path)
    case .linear(let start, let end, let stops):
      try finite([start.x, start.y, end.x, end.y], path: path)
      try gradientStops(stops, path: path)
    case .radial(let center, let radius, let stops):
      try finite([center.x, center.y, radius], path: path)
      guard radius >= 0 else {
        throw CharacterDesignError.invalid(path: path, reason: "negative gradient radius")
      }
      try gradientStops(stops, path: path)
    }
  }

  private static func gradientStops(_ stops: [CharacterGradientStop], path: String) throws {
    for (index, stop) in stops.enumerated() {
      let stopPath = "\(path).stops[\(index)]"
      try finite([stop.location, stop.opacity], path: stopPath)
      guard (0...1).contains(stop.location), (0...1).contains(stop.opacity) else {
        throw CharacterDesignError.invalid(
          path: stopPath, reason: "gradient location and opacity must be within 0...1")
      }
      try color(stop.color, path: "\(stopPath).color")
    }
  }

  private static func color(_ value: CharacterColor, path: String) throws {
    let components = [value.red, value.green, value.blue, value.alpha]
    try finite(components, path: path)
    guard components.allSatisfy({ (0...1).contains($0) }) else {
      throw CharacterDesignError.invalid(
        path: path, reason: "color components must be within 0...1")
    }
  }

  private static func finite(_ values: [Double], path: String) throws {
    guard values.allSatisfy(\.isFinite) else {
      throw CharacterDesignError.invalid(path: path, reason: "composed geometry must be finite")
    }
  }
}

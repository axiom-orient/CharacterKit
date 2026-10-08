import Foundation

enum CharacterSceneValidation {
  static func validated(_ scene: CharacterScene) throws -> CharacterScene {
    try validate(scene)
    return scene
  }

  static func validate(pose: CharacterPose) throws {
    let surface = pose.surface
    guard [surface.offsetX, surface.offsetY, surface.scaleX, surface.scaleY, surface.angle,
      pose.motionEnergy, pose.noseOffsetX, pose.writingMotionPhase, pose.writingOpacity,
      pose.mouth.opacity, pose.mouth.curvature, pose.mouth.openness, pose.mouth.width,
      pose.mouth.skew].allSatisfy(\.isFinite),
      surface.scaleX > 0, surface.scaleY > 0
    else { throw CharacterSceneError.invalidPose("surface/mouth/writing") }
    for pair in [pose.eyes] {
      for eye in [pair.left, pair.right] {
        guard [eye.centerX, eye.centerY, eye.width, eye.height, eye.angle].allSatisfy(\.isFinite),
          eye.width > 0, eye.height > 0 else { throw CharacterSceneError.invalidPose("eye") }
      }
    }
  }

  static func validate(_ scene: CharacterScene) throws {
    try finite([scene.width, scene.height], path: "scene.viewport")
    try finite([scene.faceBounds.x, scene.faceBounds.y, scene.faceBounds.width, scene.faceBounds.height], path: "scene.faceBounds")
    try transform(scene.surfaceTransform, path: "scene.surfaceTransform")
    var identifiers = Set<String>()
    var previousLayer = CharacterSceneLayer.background.rawValue
    for (index, node) in scene.nodes.enumerated() {
      let path = "scene.nodes[\(index)](\(node.id))"
      guard node.layer.rawValue >= previousLayer else { throw CharacterSceneError.invalidScene(path: path + ".layer", reason: "noncanonical painter order") }
      previousLayer = node.layer.rawValue
      guard !node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CharacterSceneError.invalidScene(path: path + ".id", reason: "empty node identity") }
      guard identifiers.insert(node.id).inserted else { throw CharacterSceneError.invalidScene(path: path + ".id", reason: "duplicate node identity") }
      try finite([node.lineWidth, node.opacity], path: path)
      guard node.lineWidth >= 0, (0...1).contains(node.opacity) else { throw CharacterSceneError.invalidScene(path: path, reason: "invalid line width or opacity") }
      try transform(node.transform, path: path + ".transform")
      try vectorPath(node.path, path: path + ".path")
      for (clipIndex, clip) in node.clips.enumerated() { try vectorPath(clip, path: "\(path).clips[\(clipIndex)]") }
      if let image = node.image {
        try finite([image.bounds.x, image.bounds.y, image.bounds.width, image.bounds.height], path: path + ".image.bounds")
        guard image.bounds.width >= 0, image.bounds.height >= 0 else { throw CharacterSceneError.invalidScene(path: path + ".image.bounds", reason: "negative image extent") }
      }
      if let fill = node.fill { try paint(fill, path: path + ".fill") }
      if let stroke = node.stroke { try color(stroke, path: path + ".stroke") }
    }
  }

  private static func transform(_ value: CharacterSceneTransform, path: String) throws {
    try finite([value.a, value.b, value.c, value.d, value.tx, value.ty], path: path)
  }
  private static func vectorPath(_ value: CharacterVectorPath, path: String) throws {
    for (index, command) in value.commands.enumerated() {
      let points: [CharacterVectorPoint]
      switch command {
      case .move(let p), .line(let p): points = [p]
      case .quad(let c, let p): points = [c, p]
      case .cubic(let c1, let c2, let p): points = [c1, c2, p]
      case .close: points = []
      }
      for p in points { try finite([p.x, p.y], path: "\(path).commands[\(index)]") }
    }
  }
  private static func paint(_ value: CharacterScenePaint, path: String) throws {
    switch value {
    case .solid(let value): try color(value, path: path)
    case .linear(let start, let end, let stops):
      try finite([start.x, start.y, end.x, end.y], path: path); try gradientStops(stops, path: path)
    case .radial(let center, let radius, let stops):
      try finite([center.x, center.y, radius], path: path)
      guard radius >= 0 else { throw CharacterSceneError.invalidScene(path: path, reason: "negative gradient radius") }
      try gradientStops(stops, path: path)
    }
  }
  private static func gradientStops(_ stops: [CharacterGradientStop], path: String) throws {
    for (index, stop) in stops.enumerated() {
      let p = "\(path).stops[\(index)]"
      try finite([stop.location, stop.opacity], path: p)
      guard (0...1).contains(stop.location), (0...1).contains(stop.opacity) else { throw CharacterSceneError.invalidScene(path: p, reason: "gradient location and opacity must be within 0...1") }
      try color(stop.color, path: p + ".color")
    }
  }
  private static func color(_ value: CharacterColor, path: String) throws {
    let components = [value.red, value.green, value.blue, value.alpha]
    try finite(components, path: path)
    guard components.allSatisfy({ (0...1).contains($0) }) else { throw CharacterSceneError.invalidScene(path: path, reason: "color components must be within 0...1") }
  }
  private static func finite(_ values: [Double], path: String) throws {
    guard values.allSatisfy(\.isFinite) else { throw CharacterSceneError.invalidScene(path: path, reason: "composed geometry must be finite") }
  }
}

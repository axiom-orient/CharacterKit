import Foundation

public enum CharacterSceneError: Error, Sendable, Equatable {
  case invalidViewport(width: Double, height: Double)
  case invalidPose(String)
  case invalidScene(path: String, reason: String)
}

/// Single scene entry point for the one product character: SEMI.
public enum CharacterSceneBuilder {
  public static func scene(
    pose: CharacterPose,
    width: Double,
    height: Double
  ) throws -> CharacterScene {
    guard width.isFinite, height.isFinite, (1...16_384).contains(width), (1...16_384).contains(height) else {
      throw CharacterSceneError.invalidViewport(width: width, height: height)
    }
    try CharacterSceneValidation.validate(pose: pose)

    let outer = CharacterGeometry.inscribedSquare(in: .init(width: width, height: height))
    let inset = min(outer.width, outer.height) * CharacterSEMIStyle.contentInset
    let board = CharacterRect(
      x: outer.x + inset, y: outer.y + inset,
      width: outer.width - inset * 2, height: outer.height - inset * 2)
    let surface = pose.surface
    let transform = CharacterSceneTransform.around(
      x: board.midX, y: board.midY, angle: surface.angle,
      scaleX: surface.scaleX, scaleY: surface.scaleY,
      offsetX: surface.offsetX * board.width, offsetY: surface.offsetY * board.height)
    let compact = min(board.width, board.height) < 64
    let emitted = CharacterSEMIDrawing.nodes(
      pose: pose, board: board, transform: transform, simplified: compact)
    var buckets: [Int: [CharacterSceneNode]] = [:]
    for node in emitted { buckets[node.layer.rawValue, default: []].append(node) }
    let ordered = CharacterSceneLayer.allCases.flatMap { buckets[$0.rawValue] ?? [] }
    return try CharacterSceneValidation.validated(CharacterScene(
      width: width, height: height, faceBounds: .init(board), surfaceTransform: transform,
      nodes: ordered, isCompact: compact))
  }
}

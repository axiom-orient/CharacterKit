import Foundation

public enum CharacterSceneBuilder {
  /// Builds one deterministic vector frame. Bounds are points, not physical pixels.
  /// The finite 1...16384-point interval prevents accidentally unbounded render targets.
  public static func scene(
    pose: CharacterPose, design: CharacterDesign, width: Double, height: Double,
    environment: CharacterDesignEnvironment = .init(), includeBackground: Bool = false,
    overlayAccents: [CharacterAccentPose] = []
  ) throws -> CharacterScene {
    try CharacterSceneCompiler.compile(
      pose: pose, input: .design(design), width: width, height: height,
      environment: environment, includeBackground: includeBackground, overlays: overlayAccents)
  }

}

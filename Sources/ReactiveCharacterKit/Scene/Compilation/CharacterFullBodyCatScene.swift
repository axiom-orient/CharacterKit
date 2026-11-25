enum CharacterFullBodyCatStage {
  /// The body and its live face share one deformation around the paw contact line.
  static func place(_ motion: CharacterFullBodyCatMotion, on stage: CharacterSceneTransform) -> CharacterSceneTransform {
    let ground = CharacterFullBodyCatArtwork.groundY
    let size = CharacterFullBodyCatArtwork.size
    let body = CharacterSceneTransform.around(
      x: CharacterFullBodyCatArtwork.centerX, y: ground,
      angle: motion.bodyAngle, scaleX: 1 + motion.bodyWidth, scaleY: 1 + motion.breath,
      offsetX: motion.bodyOffsetX * size, offsetY: motion.bodyOffsetY * size)
    let sway = CharacterSceneTransform(
      a: 1, b: 0, c: -motion.bristleSway, d: 1, tx: motion.bristleSway * ground, ty: 0)
    return stage.concatenating(body).concatenating(sway)
  }
}

extension CharacterSceneBuilder {
  /// Renders deterministic artwork for the same full-body cat used by the SwiftUI view.
  /// The caller supplies its sampled face and the elapsed time for the body and its active gesture.
  public static func scene(
    pose: CharacterPose, fullBodyCat: CharacterFullBodyCatAppearance,
    width: Double, height: Double, elapsed: Double = 0, actionElapsed: Double? = nil,
    reduceMotion: Bool = false, environment: CharacterDesignEnvironment = .init()
  ) throws -> CharacterScene {
    let motion = CharacterFullBodyCatMotion.sample(
      appearance: fullBodyCat, elapsed: elapsed,
      actionElapsed: actionElapsed ?? elapsed, reduceMotion: reduceMotion)
    return try scene(
      pose: pose, fullBodyCat: fullBodyCat, motion: motion,
      width: width, height: height, environment: environment)
  }

  static func scene(
    pose: CharacterPose, fullBodyCat: CharacterFullBodyCatAppearance, motion: CharacterFullBodyCatMotion,
    width: Double, height: Double, environment: CharacterDesignEnvironment
  ) throws -> CharacterScene {
    let actedMotion = motion.applyingActing(pose.bodyActing)
    return try CharacterSceneCompiler.compile(
      pose: pose, input: .fullBodyCat(fullBodyCat, actedMotion), width: width, height: height,
      environment: environment, includeBackground: false, overlays: [])
  }
}

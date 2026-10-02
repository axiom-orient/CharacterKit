import Foundation

extension CharacterPose {
  /// Replaces only the visual surface transform. A host can supply any sampled 2D choreography
  /// without altering emotion/task ownership or adding another reducer. Scene builders validate
  /// finite values and positive scale at the rendering boundary.
  public func replacingSurface(_ surface: CharacterSurfacePose) -> CharacterPose {
    CharacterPose(
      eyes: eyes, nearTrail: nearTrail, farTrail: farTrail,
      nearTrailOpacity: nearTrailOpacity, farTrailOpacity: farTrailOpacity,
      noseOffsetX: noseOffsetX, mouth: mouth, surface: surface,
      writingPhase: writingPhase, writingMotionPhase: writingMotionPhase,
      writingProgress: writingProgress, writingVisible: writingVisible,
      writingOpacity: writingOpacity, accents: accents, motionEnergy: motionEnergy,
      eyeContours: eyeContours, brows: brows, faceDynamics: faceDynamics)
  }
}

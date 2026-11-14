import Foundation

extension CharacterPose {
  /// Replaces only the visual surface transform. A host can supply any sampled 2D choreography
  /// without altering emotion/task ownership or adding another reducer. Scene builders validate
  /// finite values and positive scale at the rendering boundary.
  public func replacingSurface(_ surface: CharacterSurfacePose) -> CharacterPose {
    replacing(surface: surface, mouth: mouth)
  }

  /// Apply only while the host is producing speech. Keeps the current expression,
  /// eyes, gaze, action and all surface/detail motion intact.
  public func applyingSpeechArticulation(
    _ articulation: CharacterSpeechArticulation, weight: Double = 1
  ) -> CharacterPose {
    precondition(weight.isFinite && (0...1).contains(weight))
    guard weight > 0 else { return self }
    let open = mouth.openness + (articulation.openness - mouth.openness) * weight
    let width = mouth.width + (articulation.width - mouth.width) * weight
    let definition = MouthGlyphLibrary.definition(for: mouth.glyph, openness: open,
      width: width, curvature: mouth.curvature, skew: mouth.skew)
    let next = CharacterMouthPose(visible: true, opacity: mouth.opacity + (1 - mouth.opacity) * weight,
      curvature: mouth.curvature, openness: open, width: width, skew: mouth.skew,
      intrinsicAspect: MouthGlyphLibrary.intrinsicAspect(for: mouth.glyph, openness: open, width: width),
      detailOpacity: mouth.detailOpacity, referenceGlyphOpacity: mouth.referenceGlyphOpacity,
      glyph: mouth.glyph, interior: definition.interior, contour: definition.segments, details: definition.details)
    return replacing(surface: surface, mouth: next)
  }

  private func replacing(surface: CharacterSurfacePose, mouth: CharacterMouthPose) -> CharacterPose {
    CharacterPose(
      eyes: eyes, nearTrail: nearTrail, farTrail: farTrail,
      nearTrailOpacity: nearTrailOpacity, farTrailOpacity: farTrailOpacity,
      noseOffsetX: noseOffsetX, mouth: mouth, surface: surface,
      writingPhase: writingPhase, writingMotionPhase: writingMotionPhase,
      writingProgress: writingProgress, writingVisible: writingVisible,
      writingOpacity: writingOpacity, accents: accents, motionEnergy: motionEnergy,
      eyeContours: eyeContours, brows: brows, faceDynamics: faceDynamics,
      detailMotion: detailMotion)
  }
}

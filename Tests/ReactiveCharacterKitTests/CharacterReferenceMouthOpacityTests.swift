import Testing

@testable import ReactiveCharacterKit

struct CharacterReferenceMouthOpacityTests {
  @Test(arguments: [0.25, 0.5, 1.0])
  func articulationFadesTeethAndTongueOnce(opacity: Double) throws {
    let rest = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    let mouth = CharacterMouthPose(
      visible: true, opacity: opacity, curvature: 1, openness: 1, width: 0.7, skew: 0,
      intrinsicAspect: rest.mouth.intrinsicAspect, detailOpacity: rest.mouth.detailOpacity,
      referenceGlyphOpacity: rest.mouth.referenceGlyphOpacity, glyph: rest.mouth.glyph,
      interior: rest.mouth.interior, contour: rest.mouth.contour, details: rest.mouth.details)
    let pose = CharacterPose(
      eyes: rest.eyes, nearTrail: rest.nearTrail, farTrail: rest.farTrail,
      nearTrailOpacity: rest.nearTrailOpacity, farTrailOpacity: rest.farTrailOpacity,
      noseOffsetX: rest.noseOffsetX, mouth: mouth, surface: rest.surface,
      writingPhase: rest.writingPhase, writingMotionPhase: rest.writingMotionPhase,
      writingProgress: rest.writingProgress, writingVisible: rest.writingVisible,
      writingOpacity: rest.writingOpacity, accents: rest.accents, motionEnergy: rest.motionEnergy)
    let appearance = CharacterReferenceAppearance.headsetFree()
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: appearance.artDirection, width: 512, height: 560)
    let contour = try #require(scene.nodes.first { $0.id == "reference.mouth.articulated" })
    let teeth = try #require(scene.nodes.first { $0.id == "reference.mouth.teeth" })
    let tongue = try #require(scene.nodes.first { $0.id == "reference.mouth.tongue" })

    #expect(contour.opacity == opacity)
    #expect(teeth.opacity == contour.opacity)
    #expect(abs(tongue.opacity - contour.opacity * 0.68) < 1e-12)
    #expect(teeth.clips == [contour.path])
    #expect(tongue.clips == [contour.path])
    #expect((scene.nodes.first { $0.id == "reference.mouth" }?.opacity ?? 0) == 1 - opacity)
  }
}

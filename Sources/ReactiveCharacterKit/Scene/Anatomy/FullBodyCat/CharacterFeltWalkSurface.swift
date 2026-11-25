/// A shared textured skin for the torso and near paws, with far paws occluded behind it.
struct CharacterFeltWalkSurface: Hashable, Sendable {
  struct Step: Hashable, Sendable {
    // A subpixel key lets Canvas and PNG reuse the same generated surface.
    let horizontal: Int
    let vertical: Int

    var x: Float { Float(horizontal) / 8 }
    var y: Float { Float(vertical) / 8 }

    init(x: Double, y: Double) {
      horizontal = Int((x * 8).rounded())
      vertical = Int((y * 8).rounded())
    }
  }

  let right: Bool
  let nearFront: Step
  let nearHind: Step
  let farFront: Step
  let farHind: Step

  init?(motion: CharacterFullBodyCatMotion, rig: CharacterFullBodyCatArtwork.Walk) {
    guard motion.hasFeltFootfall, motion.walkPhase != nil, motion.walkStrength > 0 else { return nil }
    let right = motion.pose == .right
    let direction = right ? 1.0 : -1.0
    func step(_ id: CharacterFullBodyCatLeg) -> Step? {
      guard let leg = rig.legs.first(where: { $0.id == id }) else { return nil }
      let sample = motion.step(for: id)
      let center = CharacterFullBodyCatArtwork.centerX
      let ground = CharacterFullBodyCatArtwork.groundY
      let size = CharacterFullBodyCatArtwork.size
      let x = leg.foot.x - center + (sample.offsetX + motion.walkWeightShift) * direction
      let y = leg.foot.y - ground - sample.lift
      // Keep planted coordinates in stage space when the coat compresses.
      let localX = center + (x - motion.bodyOffsetX * size) / (1 + motion.bodyWidth)
      let localY = ground + (y - motion.bodyOffsetY * size) / (1 + motion.breath)
      let span = leg.foot.y - leg.art.pivot.y + 4
      return .init(x: localX - leg.foot.x, y: max(-0.55 * span, localY - leg.foot.y))
    }
    guard let nearFront = step(.nearFront), let nearHind = step(.nearHind),
      let farFront = step(.farFront), let farHind = step(.farHind)
    else { return nil }
    self.right = right
    self.nearFront = nearFront
    self.nearHind = nearHind
    self.farFront = farFront
    self.farHind = farHind
  }
}

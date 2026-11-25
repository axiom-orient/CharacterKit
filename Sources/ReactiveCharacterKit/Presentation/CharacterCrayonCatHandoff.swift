struct CharacterCrayonCatStance: Equatable, Sendable {
  let pose: CharacterFullBodyCatPose
  let facing: CharacterFullBodyCatFacing

  struct Sample: Equatable, Sendable {
    let stance: CharacterCrayonCatStance
    var weight: Double
  }
}

struct CharacterCrayonCatHandoff {
  let began: Double
  let source: CharacterFullBodyCatMotion
  let duration = 0.30

  func sample(at time: Double, resting: CharacterFullBodyCatMotion) -> CharacterFullBodyCatMotion {
    let phase = max(0, min(1, (time - began) / duration))
    let progress = phase * phase * (3 - 2 * phase)
    let weight = 1 - progress
    guard progress > 0 else { return source }

    var result = source
    let destination = CharacterCrayonCatStance(pose: resting.pose, facing: resting.puffDirection)
    let previous = CharacterCrayonCatStance(pose: source.pose, facing: source.puffDirection)
    let stances = source.crayonStances.isEmpty ? [.init(stance: previous, weight: 1)] : source.crayonStances
    result.crayonStances = stances.map { .init(stance: $0.stance, weight: $0.weight * weight) }
    if let index = result.crayonStances.firstIndex(where: { $0.stance == destination }) {
      result.crayonStances[index].weight += progress
    } else {
      result.crayonStances.append(.init(stance: destination, weight: progress))
    }
    result.breath = resting.breath + (source.breath - resting.breath) * weight
    result.tailAngle = resting.tailAngle + (source.tailAngle - resting.tailAngle) * weight
    result.pawAngle *= weight
    result.bodyAngle *= weight
    result.bodyWidth *= weight
    result.bodyOffsetX *= weight
    result.bodyOffsetY *= weight
    result.bristleSway *= weight
    result.headAngle *= weight
    result.pawTuck *= weight
    result.walkStrength *= weight
    result.walkWeightShift *= weight
    result.sharedSurfaceWeight = 1 - (1 - (source.sharedSurfaceWeight ?? 1)) * weight
    return result
  }
}

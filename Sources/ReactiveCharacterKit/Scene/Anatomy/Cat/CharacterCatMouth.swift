import Foundation

extension CharacterCatDrawing {
  mutating func drawMouth() {
    if theme == .simple2D {
      drawSimpleMouth()
      return
    }
    let clamp = CharacterCatMetrics.clamp
    // A rest muzzle is anatomy, not a synthetic chat/voice state.
    let articulation = pose.mouth.visible ? pose.mouth.opacity : 0
    let rawOpen = clamp(pose.mouth.openness * articulation, 0, 1)
    let open = clamp(
      (rawOpen - CharacterCatMetrics.mouthRestDeadband)
        / (1 - CharacterCatMetrics.mouthRestDeadband), 0, 1)
    let smile = clamp(pose.mouth.curvature * articulation, -1, 1)
    let x = 264 + gazeX * CharacterCatMetrics.maximumMuzzleTravel
    let y = 385 + gazeY * 5
    let width = 46 + clamp(pose.mouth.width - 0.68, -0.25, 0.35) * 40
    let height =
      CharacterCatMetrics.maximumMouthOpen * open
      * (1 + max(0, smile) * 0.80)
    let skew = clamp(pose.mouth.skew, -1, 1) * 5 * articulation
    var philtrum = CharacterVectorPath()
    philtrum.move(x, y - 11)
    philtrum.quad(x - 1, y - 3, x, y + 3)
    add("cat.philtrum", philtrum, stroke: ink, width: 2.0)
    var lips = CharacterVectorPath()
    lips.move(x - width / 2, y + 15 - smile * 10 + skew)
    lips.cubic(
      x - width * 0.33, y + 17 + smile * 4,
      x - 4, y + 10, x, y + 3)
    lips.cubic(
      x + 4, y + 10, x + width * 0.34, y + 17 + smile * 4,
      x + width / 2, y + 15 - smile * 10 - skew)
    if open > 0 {
      var cavity = CharacterVectorPath()
      let rx = max(width * (0.30 + max(0, smile) * 0.43), height * 0.35)
      let cavityOpacity = clamp(open / 0.08, 0, 1)
      cavity.move(x - rx, y + 10)
      cavity.quad(x, y + 3 - smile * 4, x + rx, y + 10)
      cavity.cubic(
        x + rx * 0.87, y + height * 0.85 + 12,
        x + rx * 0.39, y + height + 16, x, y + height + 16)
      cavity.cubic(
        x - rx * 0.45, y + height + 16,
        x - rx * 0.89, y + height * 0.86 + 12, x - rx, y + 10)
      cavity.close()
      let fill: CharacterScenePaint? =
        direction.style.mouthTreatment == .filled
        ? .linear(
          start: .init(x: x, y: y), end: .init(x: x, y: y + height + 16),
          stops: [
            .init(location: 0, color: ink, opacity: 1),
            .init(
              location: 1, color: mix(ink, direction.style.partColors.tongue, 0.32),
              opacity: 1),
          ]) : nil
      add("mouth", cavity, fill: fill, stroke: ink, width: 2.4, opacity: cavityOpacity)
      let tongue = CharacterRect(
        x: x - rx * 0.82, y: y + height * 0.68 + 12,
        width: rx * 1.64, height: max(3, height * 0.48))
      add(
        "mouth.tongue", .ellipse(tongue),
        fill: .linear(
          start: .init(x: x, y: tongue.minY), end: .init(x: x, y: tongue.maxY),
          stops: [
            .init(
              location: 0, color: mix(direction.style.partColors.tongue, .designWhite, 0.20),
              opacity: 1),
            .init(location: 1, color: direction.style.partColors.tongue, opacity: 1),
          ]),
        opacity: clamp(open * 3, 0, 1) * cavityOpacity, clips: [cavity])
      if smile > 0.4, open > 0.25 {
        for sign in [-1.0, 1.0] {
          var tooth = CharacterVectorPath()
          let tx = x + sign * rx * 0.64
          tooth.move(tx - 3, y + 9)
          tooth.line(tx + 3, y + 9)
          tooth.quad(tx + 2, y + 17, tx - sign * 2, y + 19)
          tooth.close()
          add(
            sign < 0 ? "mouth.canine.left" : "mouth.canine.right", tooth,
            fill: .solid(direction.style.partColors.mouthDetail),
            opacity: clamp((smile - 0.4) / 0.2, 0, 1) * clamp((open - 0.25) / 0.10, 0, 1),
            clips: [cavity])
        }
      }
    } else {
      add("mouth", lips, stroke: ink, width: 2.1)
    }
    // A lip line is present over an open mouth as well; no second bitmap mouth is crossfaded.
    if open > 0 { add("mouth.lip", lips, stroke: ink, width: 2.1) }
  }

  private mutating func drawSimpleMouth() {
    let active = pose.mouth.visible ? pose.mouth.opacity : 0
    let open = min(1, max(0, pose.mouth.openness * active))
    let curve = min(1, max(-1, pose.mouth.curvature * active))
    let width = 12 + (pose.mouth.width - 0.68) * active * 20
    let x = 256.0
    let y = 405.0
    let frown = max(0, -curve)
    let smile = max(0, curve)
    let cavityAmount = min(1, max(0, (open - 0.03) / 0.12))
    // The reference's tiny peaked muzzle, without a separate philtrum/nose.
    var lips = CharacterVectorPath()
    lips.move(x - width, y + 6)
    lips.quad(
      x - width * 0.45, y + 7 + smile * 6 - frown * 28,
      x, y - 2 - smile * 3 - frown * 13)
    lips.quad(x + width * 0.45, y + 7 + smile * 6 - frown * 28, x + width, y + 6)
    add("mouth.lip", lips, stroke: ink, width: 5.6, opacity: 1 - cavityAmount)
    var cavity = CharacterVectorPath()
    cavity.move(x - width, y)
    cavity.cubic(
      x - width, y - open * 20 + curve * 12,
      x + width, y - open * 20 + curve * 12, x + width, y)
    cavity.cubic(
      x + width, y + open * 35 + curve * 12,
      x - width, y + open * 35 + curve * 12, x - width, y)
    cavity.close()
    add(
      "mouth", cavity,
      fill: direction.style.mouthTreatment == .filled ? .solid(ink) : nil,
      stroke: ink, width: 3.5, opacity: cavityAmount)
  }
}

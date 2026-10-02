import Foundation

/// Accessory geometry is authored in the original portrait coordinate space.
/// One rig transform fits it to Boy; it never owns the face, pose or camera state.
extension CharacterPortraitDrawing {
  mutating func drawEyewear() {
    guard style.eyewear != .none else { return }
    let y = style.eyewear == .loweredSunglasses ? 344.0 : 298.0
    let frame = direction.style.partColors.outline
    let lens = direction.style.partColors.accessory
    for left in [true, false] {
      let x = left ? 127.0 : 278.0
      var p = CharacterVectorPath()
      p.move(x, y - 23)
      p.cubic(x + 24, y - 33, x + 82, y - 32, x + 106, y - 18)
      p.cubic(x + 116, y - 6, x + 110, y + 31, x + 93, y + 41)
      p.cubic(x + 67, y + 53, x + 28, y + 44, x + 14, y + 24)
      p.quad(x + 1, y + 5, x, y - 23)
      p.close()
      let id = left ? "portrait.glasses.left" : "portrait.glasses.right"
      addAccessory(id, p, layer: .foreground, fill: .solid(lens), stroke: frame, width: 9)
      if !simplified {
        var shine = CharacterVectorPath()
        shine.move(x + 48, y - 30)
        shine.line(x + 73, y - 30)
        shine.line(x + 25, y + 47)
        shine.line(x + 6, y + 47)
        shine.close()
        addAccessory(
          id + ".reflection", shine, layer: .foreground, fill: .solid(direction.style.partColors.mouthDetail),
          opacity: 0.10, clips: [p])
      }
    }
    var bridge = CharacterVectorPath()
    bridge.move(234, y - 13)
    bridge.quad(256, y - 27, 278, y - 13)
    bridge.move(126, y - 16)
    bridge.line(103, y - 23)
    bridge.move(387, y - 16)
    bridge.line(408, y - 23)
    addAccessory("portrait.glasses.bridge", bridge, layer: .foreground, stroke: frame, width: 9)
  }

  mutating func drawHairAccessory() {
    if style.hairAccessory == .backwardCap {
      drawCap()
      return
    }
    if style.hairAccessory == .flower {
      let anchor = G.clipCenter(style.hairstyle)
      for petal in 0..<5 {
        let angle = -.pi / 2 + Double(petal) * 2 * .pi / 5
        addAccessory(
          "portrait.hair.flower.petal.\(petal)",
          .ellipse(
            .init(
              x: anchor.x + cos(angle) * 15 - 11, y: anchor.y + sin(angle) * 15 - 11,
              width: 22, height: 22)), layer: .foreground, fill: .solid(direction.style.partColors.mouthDetail))
      }
      addAccessory(
        "portrait.hair.flower.center",
        .ellipse(.init(x: anchor.x - 6.5, y: anchor.y - 6.5, width: 13, height: 13)),
        layer: .foreground, fill: .solid(style.hairColor))
      return
    }
    guard style.hairAccessory != .none else { return }
    var p = CharacterVectorPath()
    let anchor = G.clipCenter(style.hairstyle)
    p.move(anchor.x - 10, anchor.y - 7)
    p.line(anchor.x + 10, anchor.y + 7)
    if style.hairAccessory == .cross {
      p.move(anchor.x - 7, anchor.y + 10)
      p.line(anchor.x + 7, anchor.y - 10)
    }
    addAccessory(
      "portrait.hair.clip", p, layer: .foreground,
      stroke: direction.style.partColors.accent, width: 7)
  }

  mutating func drawCap() {
    let crown = direction.style.partColors.accessory
    let seam = CharacterColor(
      uncheckedRed: crown.red * (17.0 / 23), green: crown.green * (17.0 / 23),
      blue: crown.blue * (17.0 / 23), alpha: crown.alpha)
    let strap = direction.style.partColors.accessoryDetail
    var rear = CharacterVectorPath()
    rear.move(423, 178)
    rear.cubic(452, 179, 471, 213, 473, 252)
    rear.quad(462, 264, 440, 259)
    rear.close()
    addCap(
      "portrait.hair.cap.rearBrim", rear, layer: .foreground,
      fill: .solid(crown), stroke: ink, width: 5)
    addCap(
      "portrait.hair.cap.button", .ellipse(.init(x: 243, y: 29, width: 30, height: 14)),
      layer: .foreground, fill: .solid(ink))
    let cap = CharacterPortraitCapGeometry.crown
    addCap(
      "portrait.hair.cap.crown", cap, layer: .foreground,
      fill: .solid(crown), stroke: ink, width: 5)
    var seams = CharacterVectorPath()
    seams.move(243, 38)
    seams.quad(179, 73, 164, 188)
    seams.move(267, 38)
    seams.quad(292, 71, 297, 98)
    addCap(
      "portrait.hair.cap.seams", seams, layer: .foreground,
      stroke: seam, width: 3.5, clips: [cap])
    var opening = CharacterVectorPath()
    opening.move(218, 170)
    opening.cubic(219, 111, 235, 94, 285, 94)
    opening.cubic(332, 94, 354, 117, 355, 185)
    opening.close()
    addCap("portrait.hair.cap.opening", opening, layer: .foreground, fill: .solid(ink))
    var band = CharacterVectorPath()
    band.move(220, 149)
    band.line(351, 162)
    band.line(348, 186)
    band.line(218, 173)
    band.close()
    addCap("portrait.hair.cap.strap", band, layer: .foreground, fill: .solid(strap))
    let buckle = CharacterVectorPath.roundedRectangle(
      .init(x: 336, y: 155, width: 26, height: 31), radius: 4)
    addCap(
      "portrait.hair.cap.buckle", buckle, layer: .foreground,
      fill: .solid(ink), stroke: direction.style.partColors.mouthDetail, width: 5,
      local: .around(x: 349, y: 170, angle: 0.10))
  }


  private mutating func addAccessory(
    _ id: String, _ path: CharacterVectorPath, layer: CharacterSceneLayer = .features,
    fill: CharacterScenePaint? = nil, stroke: CharacterColor? = nil,
    width: Double = 0, opacity: Double = 1,
    local: CharacterSceneTransform = .identity, clips: [CharacterVectorPath] = []
  ) {
    add(id, path, layer: layer, fill: fill, stroke: stroke, width: width, opacity: opacity,
        local: featureLayout.accessoryTransform.concatenating(local), clips: clips)
  }
}

// A cap fits the hair volume, not the eye/glasses anchors. Its clip uses this exact same rig.
extension CharacterPortraitDrawing {
  private mutating func addCap(
    _ id: String, _ path: CharacterVectorPath, layer: CharacterSceneLayer,
    fill: CharacterScenePaint? = nil, stroke: CharacterColor? = nil,
    width: Double = 0, local: CharacterSceneTransform = .identity,
    clips: [CharacterVectorPath] = []
  ) {
    add(id, path, layer: layer, fill: fill, stroke: stroke, width: width,
        local: featureLayout.capTransform.concatenating(local), clips: clips)
  }
}

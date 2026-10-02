import Foundation

extension CharacterBoyArtwork {
  struct Parts {
    let outline: CharacterVectorPath
    let face: CharacterVectorPath
    let skin: [(String, CharacterVectorPath)]
    let clothingDetail: [(String, CharacterVectorPath)]
    let uniform: [(String, CharacterVectorPath)]
    let hairBack: CharacterVectorPath
    let hairFringe: CharacterVectorPath
    let highlights: [CharacterVectorPath]
  }

  static func parts(_ viewpoint: CharacterPortraitStyle.BoyViewpoint) -> Parts {
    switch viewpoint {
    case .front: return front
    case .threeQuarterRight: return quarter
    }
  }

  private static let front = Parts(
    outline: Front.outline, face: Front.face,
    skin: [
      ("portrait.ear.left", Front.earLeft), ("portrait.ear.right", Front.earRight),
      ("portrait.neck", Front.neck),
      ("portrait.hand.left", Front.handLeft), ("portrait.hand.right", Front.handRight),
    ],
    clothingDetail: [
      ("portrait.collar.left", Front.collarLeft), ("portrait.collar.right", Front.collarRight),
      ("portrait.cuff.left", Front.cuffLeft), ("portrait.cuff.right", Front.cuffRight),
    ],
    uniform: [
      ("portrait.shoulders", Front.shoulders), ("portrait.uniform.inset", Front.uniformInset),
      ("portrait.uniform.trim", Front.uniformTrim),
    ],
    hairBack: Front.hairBack, hairFringe: Front.hairFringe,
    highlights: [Front.hairHighlight0, Front.hairHighlight1])

  private static let quarter = Parts(
    outline: Quarter.outline, face: Quarter.face,
    // The near ear and neck are continuous with the face in this view, not duplicate patches.
    skin: [
      ("portrait.ear.right", Quarter.earRight),
      ("portrait.hand.left", Quarter.handLeft), ("portrait.hand.right", Quarter.handRight),
    ],
    clothingDetail: [
      ("portrait.collar.left", Quarter.collarLeft), ("portrait.collar.right", Quarter.collarRight),
      ("portrait.cuff.left", Quarter.cuffLeft), ("portrait.cuff.right", Quarter.cuffRight),
    ],
    uniform: [
      ("portrait.shoulders", Quarter.shoulders), ("portrait.uniform.inset", Quarter.uniformInset),
      ("portrait.uniform.trim", Quarter.uniformTrim),
    ],
    hairBack: Quarter.hairBack, hairFringe: Quarter.hairFringe,
    highlights: [Quarter.hairHighlight0, Quarter.hairHighlight1,
                 Quarter.hairHighlight2, Quarter.hairHighlight3])
}

extension CharacterPortraitDrawing {
  var faceFeatureClips: [CharacterVectorPath] {
    guard let viewpoint = style.boyViewpoint else { return [] }
    return [CharacterBoyArtwork.parts(viewpoint).face]
  }

  mutating func drawBoyHead(_ viewpoint: CharacterPortraitStyle.BoyViewpoint) {
    let parts = CharacterBoyArtwork.parts(viewpoint)
    // A cap hides the cowlick rather than allowing the top spike to protrude through its crown.
    let hairClips: [CharacterVectorPath] = style.hairAccessory == .backwardCap
      && direction.components.contains(.accessories)
      ? [CharacterPortraitCapGeometry.hairVisibility.mapped { point in
          let t = featureLayout.capTransform
          return .init(x: t.a * point.x + t.c * point.y + t.tx,
                       y: t.b * point.x + t.d * point.y + t.ty)
        }] : []
    add("portrait.outline", parts.outline, layer: .behindSurface,
        fill: .solid(ink), clips: hairClips)
    for (id, path) in parts.uniform {
      add(id, path, layer: .behindSurface, fill: .solid(direction.style.partColors.accent))
    }
    for (id, path) in parts.skin {
      add(id, path, layer: .surface, fill: .solid(direction.style.partColors.surface))
    }
    for (id, path) in parts.clothingDetail {
      add(id, path, layer: .surface, fill: .solid(direction.style.partColors.clothingDetail))
    }
    add("portrait.face", parts.face, layer: .surface,
        fill: .solid(direction.style.partColors.surface))
    add("portrait.hair.back", parts.hairBack, layer: .surface,
        fill: .solid(hairColor(multiplier: 0.59)), clips: hairClips)
    add("portrait.hair.fringe", parts.hairFringe, layer: .surface,
        fill: .solid(style.hairColor), clips: hairClips)
    if !simplified {
      for (index, highlight) in parts.highlights.enumerated() {
        add("portrait.hair.highlight.\(index)", highlight, layer: .surface,
            fill: .solid(hairColor(multiplier: 1.87)), clips: hairClips)
      }
    }
  }

  private func hairColor(multiplier: Double) -> CharacterColor {
    CharacterColor(
      uncheckedRed: min(1, style.hairColor.red * multiplier),
      green: min(1, style.hairColor.green * multiplier),
      blue: min(1, style.hairColor.blue * multiplier), alpha: style.hairColor.alpha)
  }
}

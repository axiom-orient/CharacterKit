/// The crayon pose catalog owns drawing geometry and the joints that move each part.
struct CharacterCrayonCatArtwork {
  enum Motion {
    case body, head, tail, paw
    case leg(CharacterFullBodyCatLeg)
  }

  enum Tone {
    case tail, torso, near, far, head
  }

  struct Part {
    let id: String
    let path: CharacterVectorPath
    let tone: Tone
    let motion: Motion
    let outlined: Bool
    let pivot: CharacterVectorPoint?
    let foot: CharacterVectorPoint?
    let outline: CharacterVectorPath
    let waxMarks: CharacterVectorPath

    init(
      _ id: String, _ path: CharacterVectorPath, _ tone: Tone, motion: Motion = .body,
      outlined: Bool = true, pivot: CharacterVectorPoint? = nil, foot: CharacterVectorPoint? = nil,
      raisedFur: Bool = false
    ) {
      self.id = id
      self.path = path
      self.tone = tone
      self.motion = motion
      self.outlined = outlined
      self.pivot = pivot
      self.foot = foot
      self.outline = CharacterCrayonCatMarks.looseContour(path)
      self.waxMarks = CharacterCrayonCatMarks.strokePatch(in: path, tone: tone, raisedFur: raisedFur)
    }
  }

  typealias Eye = CharacterFullBodyCatArtwork.Eye

  struct Muzzle {
    let nose: CharacterRect
    let junction: CharacterVectorPoint
    let profileDirection: Double

    init(
      _ x: Double, _ y: Double, _ width: Double, _ height: Double,
      mouthX: Double, mouthY: Double, profileDirection: Double = 0
    ) {
      nose = .init(x: x - width / 2, y: y - height / 2, width: width, height: height)
      junction = .init(x: mouthX, y: mouthY)
      self.profileDirection = profileDirection
    }
  }

  struct Face {
    let bounds: CharacterRect
    let left: Eye?
    let right: Eye?
    let muzzle: Muzzle?
    let eyeAngle: Double

    init(_ bounds: CharacterRect, left: Eye? = nil, right: Eye? = nil,
         muzzle: Muzzle? = nil, eyeAngle: Double = 0) {
      self.bounds = bounds
      self.left = left
      self.right = right
      self.muzzle = muzzle
      self.eyeAngle = eyeAngle
    }
  }

  let face: Face?
  let parts: [Part]
  let tailPivot: CharacterVectorPoint?
  let pawPivot: CharacterVectorPoint?
  let headPivot: CharacterVectorPoint

  init(face: Face?, parts: [Part], tailPivot: CharacterVectorPoint? = nil,
       pawPivot: CharacterVectorPoint? = nil, headPivot: CharacterVectorPoint) {
    self.face = face
    self.parts = parts
    self.tailPivot = tailPivot
    self.pawPivot = pawPivot
    self.headPivot = headPivot
  }
}

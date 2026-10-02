import Foundation

/// Immutable geometry compiled from the externally maintained reference rig. No resource I/O or state.
enum CharacterReferenceArtworkID: String, CaseIterable, Sendable {
  case mascotHero = "mascot-hero"
  case mascotBare = "mascot-bare"
  case mascotWhite = "mascot-white"
  case mascotBlack = "mascot-black"
  case mascotArcade = "mascot-arcade"
  case norwegianHero = "norwegian-hero"
  case norwegianWarm = "norwegian-warm"
  case norwegianSilver = "norwegian-silver"
  case norwegianCream = "norwegian-cream"
}

struct CharacterReferenceRig: Sendable {
  enum Part: String, Sendable {
    case body, headsetShell, headsetMetal, headsetCushions, headsetLight
    case earLeft, earRight, mane, eyeLeft, eyeRight, irisLeft, irisRight, nose, mouth

    var isHardware: Bool {
      switch self {
      case .headsetShell, .headsetMetal, .headsetCushions, .headsetLight: true
      default: false
      }
    }
    var isIris: Bool { self == .irisLeft || self == .irisRight }
    var isLeft: Bool { self == .eyeLeft || self == .irisLeft || self == .earLeft }
  }

  struct Layer: Sendable {
    let part: Part
    let asset: String
    let pivotX: Double
    let pivotY: Double
    let frame: CharacterRect
  }

  let id: CharacterReferenceArtworkID
  let width: Double
  let height: Double
  let layers: [Layer]
}

/// Articulation limits are visual policy, not semantic state or user settings.
enum CharacterReferenceMotionPolicy {
  static let minimumEyeScale = 0.035
  static let maximumEyeScale = 1.25
  static let maximumEarAngle = 0.05
  static let maximumGazeX = 0.23
  static let maximumGazeY = 0.24
  static let irisTravelFraction = 0.095
  static let eyeTravelFraction = 0.085
  static let earRootOverlap = 7.0
}

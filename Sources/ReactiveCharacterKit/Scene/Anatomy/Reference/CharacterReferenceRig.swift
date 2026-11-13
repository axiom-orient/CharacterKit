import Foundation

/// Immutable geometry compiled from the externally maintained reference rig. No resource I/O or state.
enum CharacterReferenceArtworkID: String, CaseIterable, Sendable {
  case mascotHero = "mascot-hero"
  case mascotBare = "mascot-bare"
  case mascotWhite = "mascot-white"
  case mascotBlack = "mascot-black"
  case mascotArcade = "mascot-arcade"
}

struct CharacterReferenceRig: Sendable {
  enum Part: String, Sendable {
    case body, headsetShell, headsetMetal, headsetCushions, headsetLight
    case eyeLeft, eyeRight, mouth

    var isHardware: Bool {
      switch self {
      case .headsetShell, .headsetMetal, .headsetCushions, .headsetLight: true
      default: false
      }
    }
    var isLeft: Bool { self == .eyeLeft }
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
  static let maximumGazeX = 0.23
  static let maximumGazeY = 0.24
  static let eyeTravelFraction = 0.085
}

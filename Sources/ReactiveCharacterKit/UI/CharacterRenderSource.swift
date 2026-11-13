#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  enum CharacterRenderSource {
    case design(CharacterDesign, partColors: CharacterPartColors?)
    case artDirection(CharacterArtDirection)

    var components: CharacterComponents {
      switch self {
      case .design(let design, _): design.components
      case .artDirection(let direction): direction.components
      }
    }

    var projection: CharacterProjection {
      switch self {
      case .design(let design, _): design.projection
      case .artDirection(let direction): direction.projection
      }
    }

    var motionProfile: CharacterMotionProfile {
      switch self {
      case .design(let design, _): design.motionProfile
      case .artDirection(let direction): direction.motionProfile
      }
    }

    var transitionProfile: CharacterTransitionProfile {
      switch self {
      case .design(let design, _): design.transitionProfile
      case .artDirection(let direction): direction.transitionProfile
      }
    }

    var designFramesPerSecond: Int? {
      guard case .design(let design, _) = self else { return nil }
      return design.profile.rendering.framesPerSecond
    }

    var artDirection: CharacterArtDirection? {
      guard case .artDirection(let direction) = self else { return nil }
      return direction
    }

    var design: CharacterDesign? {
      guard case .design(let design, _) = self else { return nil }
      return design
    }
  }

#endif

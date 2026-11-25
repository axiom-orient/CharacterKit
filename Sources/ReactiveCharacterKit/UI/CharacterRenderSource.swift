#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  enum CharacterRenderSource {
    case design(CharacterDesign, partColors: CharacterPartColors?)
    case artDirection(CharacterArtDirection)
    case fullBodyCat(CharacterFullBodyCatAppearance)

    var components: CharacterComponents {
      switch self {
      case .design(let design, _): design.components
      case .artDirection(let direction): direction.components
      case .fullBodyCat: [.eyes, .mouth, .nose]
      }
    }

    var projection: CharacterProjection {
      switch self {
      case .design(let design, _): design.projection
      case .artDirection(let direction): direction.projection
      case .fullBodyCat: .flat
      }
    }

    var motionProfile: CharacterMotionProfile {
      switch self {
      case .design(let design, _): design.motionProfile
      case .artDirection(let direction): direction.motionProfile
      case .fullBodyCat: .expressive
      }
    }

    var transitionProfile: CharacterTransitionProfile {
      switch self {
      case .design(let design, _): design.transitionProfile
      case .artDirection(let direction): direction.transitionProfile
      case .fullBodyCat: .expressive
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

    var fullBodyCat: CharacterFullBodyCatAppearance? {
      guard case .fullBodyCat(let appearance) = self else { return nil }
      return appearance
    }
  }

#endif

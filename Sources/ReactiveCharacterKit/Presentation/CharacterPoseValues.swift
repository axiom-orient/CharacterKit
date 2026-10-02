import Foundation

/// Whole-character presentation transform used for anticipation, impact and settling.
/// Coordinates are normalized to the character's own diameter.
public struct CharacterSurfacePose: Sendable, Equatable {
  public let offsetX: Double
  public let offsetY: Double
  public let scaleX: Double
  public let scaleY: Double
  public let angle: Double

  public init(
    offsetX: Double = 0,
    offsetY: Double = 0,
    scaleX: Double = 1,
    scaleY: Double = 1,
    angle: Double = 0
  ) {
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.angle = angle
  }

  public static let identity = Self()
}

/// Small temporary visual objects used to dramatize emotion with minimal geometry.
public enum CharacterAccentKind: Sendable, Equatable {
  case heart
  case sparkle
  case ring
  case ray
  case sweatDrop
  case tearDrop
  case puff
}

/// Renderer-independent transient ornament pose.
public struct CharacterAccentPose: Sendable, Equatable {
  public let kind: CharacterAccentKind
  public let centerX: Double
  public let centerY: Double
  public let width: Double
  public let height: Double
  public let angle: Double
  public let opacity: Double

  public init(
    kind: CharacterAccentKind,
    centerX: Double,
    centerY: Double,
    width: Double,
    height: Double,
    angle: Double,
    opacity: Double
  ) {
    self.kind = kind
    self.centerX = centerX
    self.centerY = centerY
    self.width = width
    self.height = height
    self.angle = angle
    self.opacity = opacity
  }
}

public struct CharacterEyePose: Sendable, Equatable {
  public let centerX: Double
  public let centerY: Double
  public let width: Double
  public let height: Double
  public let angle: Double

  // Renderer-internal decomposition. Public width/height remain the stable projected result.
  // Cat rendering needs the pre-blink aperture and blink channel separately so gaze/projection
  // cannot be mistaken for eyelid closure.
  let unblinkedWidth: Double
  let unblinkedHeight: Double
  let blink: Double

  init(
    centerX: Double, centerY: Double, width: Double, height: Double, angle: Double,
    unblinkedWidth: Double? = nil, unblinkedHeight: Double? = nil, blink: Double = 0
  ) {
    self.centerX = centerX
    self.centerY = centerY
    self.width = width
    self.height = height
    self.angle = angle
    self.blink = blink
    self.unblinkedWidth = unblinkedWidth ?? width
    self.unblinkedHeight = unblinkedHeight ?? height
  }
}

public struct CharacterEyePairPose: Sendable, Equatable {
  public let left: CharacterEyePose
  public let right: CharacterEyePose
}

public struct CharacterMouthPose: Sendable, Equatable {
  public let visible: Bool
  public let opacity: Double
  public let curvature: Double
  public let openness: Double
  public let width: Double
  public let skew: Double
  /// Reference-glyph metadata retained for articulation and source coverage.
  /// Built-in face geometry consumes the numeric pose above, never a bitmap crossfade.
  let intrinsicAspect: Double
  let detailOpacity: Double
  let referenceGlyphOpacity: Double

  let glyph: CharacterMouthGlyph
  let interior: CharacterMouthInterior
  let contour: [MouthCubicSegment]
  let details: [MouthDetailPath]
}

/// Renderer-independent presentation output.
/// Consumers can use this with the built-in SwiftUI view or a custom renderer.
public struct CharacterPose: Sendable, Equatable {
  public let eyes: CharacterEyePairPose
  public let nearTrail: CharacterEyePairPose?
  public let farTrail: CharacterEyePairPose?
  public let nearTrailOpacity: Double
  public let farTrailOpacity: Double
  public let noseOffsetX: Double
  public let mouth: CharacterMouthPose
  public let surface: CharacterSurfacePose
  /// Preserved public activity phase. For agent writing this remains the
  /// monotonic task progress used by existing custom renderers.
  public let writingPhase: Double
  /// Independent motion phase so the built-in writing gesture stays alive even
  /// when agent progress is temporarily unchanged.
  public let writingMotionPhase: Double
  /// Monotonic agent-writing progress when available; nil for freehand input.
  public let writingProgress: Double?
  public let writingVisible: Bool
  public let writingOpacity: Double
  public let accents: [CharacterAccentPose]
  public let motionEnergy: Double
  /// Internal built-in contour payload. Public eye/pose fields remain unchanged.
  var eyeContours: CharacterEyeContourPair = .neutral
  /// Internal eyebrow payload for face models that render brows.
  var brows: CharacterBrowPairPose = .neutral
  /// Renderer-neutral lower-face coupling resolved from the final eyes.
  var faceDynamics: CharacterFaceDynamics = .neutral
}

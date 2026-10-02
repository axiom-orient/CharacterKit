import Foundation

/// Cat-specific artwork that does not own semantic character state.
///
/// Supplemental assets are reusable host-facing resources, not a fourth cat theme and not a
/// second accessory state machine. The enum is the single authority for package resource names.
public enum CharacterCatSupplementalAsset: String, CaseIterable, Sendable, Hashable, Identifiable {
  case pawPad = "cat-paw-pad"

  public enum Representation: String, CaseIterable, Sendable, Hashable, Identifiable {
    case png
    case svg

    public var id: String { rawValue }
  }

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .pawPad: "Cat Paw Pad"
    }
  }

  /// PNG artwork reference for integrations that already consume `CharacterImageAsset`.
  public var pngImageAsset: CharacterImageAsset {
    switch self {
    case .pawPad: .catPawPad
    }
  }

  /// Standalone animated paw, through the existing face/session/scene pipeline.
  /// Only the shared surface transform moves; this does not invent facial emotions or a clock.
  public var artDirection: CharacterArtDirection {
    switch self {
    case .pawPad: Self.pawDirection
    }
  }

  private static let pawDirection = CharacterArtDirection.pawAsset(
    .catPawPad, name: "Cat Paw Pad")


}

extension CharacterImageAsset {
  public static let catPawPad = Self(uncheckedName: "cat-paw-pad", source: .package)
}

extension CharacterAccessoryPlacement {
  /// Canonical foreground sticker slot for the built-in paw pad.
  /// Placement is presentation-only and follows the face surface pose.
  public static let catPawSticker = try! Self(
    anchor: .face,
    layer: .foreground,
    centerX: 0.83,
    centerY: 0.80,
    width: 0.20,
    height: 0.20,
    angle: -0.10,
    opacity: 1
  )
}

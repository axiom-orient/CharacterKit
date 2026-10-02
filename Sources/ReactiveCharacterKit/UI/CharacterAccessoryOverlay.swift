#if os(iOS) || os(macOS)
  import SwiftUI

  /// Caller-owned artwork. The package does not load files or perform network I/O
  /// for custom attachments. Changing an overlay never restarts semantic animation.
  @available(iOS 16.0, macOS 13.0, *)
  public struct CharacterAccessoryOverlay {
    public let image: Image
    public let placement: CharacterAccessoryPlacement
    public let tint: CharacterColor?
    public let accessibilityLabel: String?

    public init(
      image: Image,
      placement: CharacterAccessoryPlacement,
      tint: CharacterColor? = nil,
      accessibilityLabel: String? = nil
    ) {
      self.image = image
      self.placement = placement
      self.tint = tint
      self.accessibilityLabel = accessibilityLabel
    }
  }
#endif

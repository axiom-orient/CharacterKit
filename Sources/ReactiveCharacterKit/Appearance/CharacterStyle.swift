import Foundation

/// Presentation-only base eye proportion.
///
/// `vertical` is the single canonical built-in eye. `horizontal` is that same base eye projected
/// into a wide horizontal proportion. Special expression topology (heart/crescent/angry) remains
/// owned by semantic emotion and is not replaced by this enum.
public enum CharacterEyeTreatment: String, Sendable, Equatable, CaseIterable {
  case vertical
  case horizontal
  case round
}

/// Presentation-only mouth treatment. It never changes the semantic mouth gesture.
public enum CharacterMouthTreatment: String, Sendable, Equatable, CaseIterable {
  case outline
  case filled
}

/// Default-renderer appearance. Pose generation is color-independent.
public struct CharacterStyle: Sendable, Equatable {
  public let partColors: CharacterPartColors
  public let eyeTreatment: CharacterEyeTreatment
  public let mouthTreatment: CharacterMouthTreatment
  public let lineWidth: Double
  /// Flat portrait/simple-cat smile geometry. Other anatomies keep their existing eye grammar.
  public let smileEyeShape: CharacterSmileEyeShape

  public init(
    partColors: CharacterPartColors = .default,
    eyeTreatment: CharacterEyeTreatment = .vertical,
    mouthTreatment: CharacterMouthTreatment = .outline,
    lineWidth: Double = 0.018
  ) throws {
    guard lineWidth.isFinite, lineWidth > 0, lineWidth <= 0.08 else {
      throw CharacterAppearanceError.invalidStyle(field: "lineWidth", value: lineWidth)
    }
    self.partColors = partColors
    self.eyeTreatment = eyeTreatment
    self.mouthTreatment = mouthTreatment
    self.lineWidth = lineWidth
    self.smileEyeShape = .arc
  }

  private init(
    uncheckedPartColors partColors: CharacterPartColors,
    eyeTreatment: CharacterEyeTreatment,
    mouthTreatment: CharacterMouthTreatment,
    lineWidth: Double,
    smileEyeShape: CharacterSmileEyeShape = .arc
  ) {
    self.partColors = partColors
    self.eyeTreatment = eyeTreatment
    self.mouthTreatment = mouthTreatment
    self.lineWidth = lineWidth
    self.smileEyeShape = smileEyeShape
  }

  public func replacingPartColors(_ partColors: CharacterPartColors) -> Self {
    Self(
      uncheckedPartColors: partColors, eyeTreatment: eyeTreatment,
      mouthTreatment: mouthTreatment, lineWidth: lineWidth, smileEyeShape: smileEyeShape)
  }

  public func replacingFaceTreatment(
    eyes: CharacterEyeTreatment? = nil,
    mouth: CharacterMouthTreatment? = nil
  ) -> Self {
    Self(
      uncheckedPartColors: partColors,
      eyeTreatment: eyes ?? eyeTreatment, mouthTreatment: mouth ?? mouthTreatment,
      lineWidth: lineWidth, smileEyeShape: smileEyeShape)
  }

  public func replacingSmileEyeShape(_ shape: CharacterSmileEyeShape) -> Self {
    Self(
      uncheckedPartColors: partColors, eyeTreatment: eyeTreatment,
      mouthTreatment: mouthTreatment, lineWidth: lineWidth, smileEyeShape: shape)
  }

  public static let `default` = Self(
    uncheckedPartColors: .default, eyeTreatment: .vertical,
    mouthTreatment: .outline, lineWidth: 0.018
  )
}

import Foundation

/// Shared numeric mechanism. Each public accessory contract supplies its own bounds and error.
enum CharacterAccessoryValidation {
  static func validate(
    centerX: Double, centerY: Double, width: Double, height: Double,
    angle: Double, opacity: Double,
    centerRange: ClosedRange<Double>, maximumSize: Double,
    invalidValue: (String, Double) -> any Error
  ) throws {
    for (field, value, lower, upper) in [
      ("centerX", centerX, centerRange.lowerBound, centerRange.upperBound),
      ("centerY", centerY, centerRange.lowerBound, centerRange.upperBound),
      ("width", width, 0.0, maximumSize), ("height", height, 0.0, maximumSize),
      ("angle", angle, -2 * Double.pi, 2 * Double.pi), ("opacity", opacity, 0.0, 1.0),
    ] {
      guard value.isFinite, value >= lower, value <= upper else {
        throw invalidValue(field, value)
      }
    }
    guard width > 0 else { throw invalidValue("width", width) }
    guard height > 0 else { throw invalidValue("height", height) }
  }
}

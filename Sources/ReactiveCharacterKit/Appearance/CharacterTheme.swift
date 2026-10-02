import Foundation

/// Three minimal palettes and one articulated cat theme.
///
/// Theme changes are presentation-only. They never change semantic state, animation identity,
/// cancellation, task ownership, or expression meaning.
public enum CharacterTheme: String, CaseIterable, Sendable, Hashable, Identifiable {
  case black
  case white
  case arcade
  case cat

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .black: "흑"
    case .white: "백"
    case .arcade: "아케이드"
    case .cat: "고양이"
    }
  }

  public var artDirection: CharacterArtDirection {
    switch self {
    case .black: .black
    case .white: .white
    case .arcade: .arcade
    case .cat: .cat
    }
  }

  /// Creates one reusable presentation configuration for a host application.
  /// This changes appearance only; semantic state and task/animation identity remain untouched.
  public func configured(
    eyes: CharacterEyeTreatment? = nil,
    mouth: CharacterMouthTreatment? = nil,
    partColors: CharacterPartColors? = nil
  ) -> CharacterArtDirection {
    var direction = artDirection.replacingFaceTreatment(eyes: eyes, mouth: mouth)
    if let partColors { direction = direction.replacingPartColors(partColors) }
    return direction
  }
}

extension CharacterArtDirection {
  private static func builtIn(
    name: String, style: CharacterStyle, assets: CharacterAssetPack
  ) -> Self {
    do {
      return try Self(
        name: name,
        components: .default.union(.writing),
        layout: .standard,
        style: style,
        projection: .softSphere,
        motionProfile: .cartoon,
        transitionProfile: .cartoon,
        assets: assets,
        featureGlow: 0,
        ornamentGlow: 0,
        contentInset: Self.canonicalContentInset)
    } catch { preconditionFailure("Invalid built-in \(name) art direction: \(error)") }
  }

  /// Near-black face with white features.
  public static let black = builtIn(name: "Black", style: .black, assets: .black)

  /// Near-white face with black features.
  public static let white = builtIn(name: "White", style: .white, assets: .white)

  /// Near-black face with restrained cyan/blue/amber accents.
  public static let arcade = builtIn(name: "Arcade", style: .arcade, assets: .arcade)
}

extension CharacterStyle {
  public static let black: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 9.0 / 255, green: 9.0 / 255, blue: 11.0 / 255),
          eyes: CharacterColor(red: 250.0 / 255, green: 250.0 / 255, blue: 250.0 / 255),
          mouth: CharacterColor(red: 250.0 / 255, green: 250.0 / 255, blue: 250.0 / 255),
          mouthDetail: CharacterColor(red: 9.0 / 255, green: 9.0 / 255, blue: 11.0 / 255),
          tongue: CharacterColor(red: 214.0 / 255, green: 214.0 / 255, blue: 210.0 / 255),
          writing: CharacterColor(red: 250.0 / 255, green: 250.0 / 255, blue: 250.0 / 255),
          accent: CharacterColor(red: 250.0 / 255, green: 250.0 / 255, blue: 250.0 / 255)
        ),
        eyeTreatment: .vertical,
        mouthTreatment: .outline,
        lineWidth: 0.012)
    } catch { preconditionFailure("Invalid built-in Black style: \(error)") }
  }()

  public static let white: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 247.0 / 255, green: 247.0 / 255, blue: 246.0 / 255),
          eyes: CharacterColor(red: 11.0 / 255, green: 11.0 / 255, blue: 13.0 / 255),
          mouth: CharacterColor(red: 11.0 / 255, green: 11.0 / 255, blue: 13.0 / 255),
          mouthDetail: CharacterColor(red: 247.0 / 255, green: 247.0 / 255, blue: 246.0 / 255),
          tongue: CharacterColor(red: 43.0 / 255, green: 43.0 / 255, blue: 48.0 / 255),
          writing: CharacterColor(red: 11.0 / 255, green: 11.0 / 255, blue: 13.0 / 255),
          accent: CharacterColor(red: 11.0 / 255, green: 11.0 / 255, blue: 13.0 / 255)
        ),
        eyeTreatment: .vertical,
        mouthTreatment: .outline,
        lineWidth: 0.012)
    } catch { preconditionFailure("Invalid built-in White style: \(error)") }
  }()

  public static let arcade: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 7.0 / 255, green: 10.0 / 255, blue: 15.0 / 255),
          eyes: CharacterColor(red: 0, green: 229.0 / 255, blue: 1),
          mouth: CharacterColor(red: 250.0 / 255, green: 250.0 / 255, blue: 250.0 / 255),
          mouthDetail: CharacterColor(red: 7.0 / 255, green: 10.0 / 255, blue: 15.0 / 255),
          tongue: CharacterColor(red: 0, green: 102.0 / 255, blue: 1),
          writing: CharacterColor(red: 0, green: 102.0 / 255, blue: 1),
          accent: CharacterColor(red: 1, green: 200.0 / 255, blue: 61.0 / 255)
        ),
        eyeTreatment: .vertical,
        mouthTreatment: .outline,
        lineWidth: 0.012)
    } catch { preconditionFailure("Invalid built-in Arcade style: \(error)") }
  }()
}

extension CharacterArtDirection {
  /// Authored black-fur layers with continuously articulated eyes, ears and mouth.
  /// Uses exactly the same CharacterPose and presentation session as the minimal themes.
  public static let cat: Self = {
    do {
      return try Self(
        name: "Cat", components: .default.union([.nose, .writing]),
        style: .cat, motionProfile: .cartoon, transitionProfile: .cartoon,
        contentInset: canonicalContentInset, anatomy: .cat(.animated))
    } catch { preconditionFailure("Invalid built-in cat art direction: \(error)") }
  }()
}

extension CharacterStyle {
  public static let cat: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 0.10, green: 0.105, blue: 0.14),
          eyes: CharacterColor(red: 0.12, green: 0.40, blue: 0.91),
          nose: CharacterColor(red: 0.69, green: 0.41, blue: 0.44),
          mouth: CharacterColor(red: 0.07, green: 0.045, blue: 0.075),
          mouthDetail: CharacterColor(red: 0.98, green: 0.96, blue: 0.93),
          tongue: CharacterColor(red: 0.85, green: 0.44, blue: 0.49),
          writing: CharacterColor(red: 0.49, green: 0.71, blue: 0.98),
          accent: CharacterColor(red: 0.69, green: 0.84, blue: 1.0)),
        eyeTreatment: .vertical, mouthTreatment: .filled,
        lineWidth: 0.009)
    } catch { preconditionFailure("Invalid built-in cat style: \(error)") }
  }()
}

extension CharacterArtDirection {
  /// Flat, icon-like cat anatomy. It shares the same pose/session authority as every other theme.
  public static let catSimple2D: Self = {
    do {
      return try Self(
        name: "Cat Simple 2D", components: .default.union([.writing]),
        style: .catSimple2D, motionProfile: .cartoon, transitionProfile: .cartoon,
        contentInset: canonicalContentInset, anatomy: .cat(.simple2D))
    } catch { preconditionFailure("Invalid built-in simple 2D cat art direction: \(error)") }
  }()

  /// Norwegian Forest Cat breed variant. Emotion and motion contracts are unchanged.
  public static let catNorwegianForest: Self = .reference(.norwegianForest(.hero))

}

extension CharacterStyle {
  /// Intentionally flat palette for the lightweight 2D cat.
  public static let catSimple2D: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 0.075, green: 0.078, blue: 0.09),
          eyes: CharacterColor(red: 0.055, green: 0.045, blue: 0.06),
          nose: CharacterColor(red: 0.91, green: 0.46, blue: 0.52),
          mouth: CharacterColor(red: 0.055, green: 0.045, blue: 0.06),
          mouthDetail: CharacterColor(red: 0.98, green: 0.97, blue: 0.95),
          tongue: CharacterColor(red: 0.91, green: 0.46, blue: 0.52),
          writing: CharacterColor(red: 0.055, green: 0.045, blue: 0.06),
          accent: CharacterColor(red: 0.95, green: 0.56, blue: 0.62)),
        eyeTreatment: .vertical, mouthTreatment: .filled,
        lineWidth: 0.010)
    } catch { preconditionFailure("Invalid built-in Simple 2D cat style: \(error)") }
  }()

  /// Procedural feature palette over the authored warm, silver or cream Norwegian coat.
  public static let catNorwegianForest: Self = {
    do {
      return try Self(
        partColors: CharacterPartColors(
          surface: CharacterColor(red: 0.095, green: 0.098, blue: 0.12),
          eyes: CharacterColor(red: 0.50, green: 0.72, blue: 0.27),
          nose: CharacterColor(red: 0.69, green: 0.41, blue: 0.44),
          mouth: CharacterColor(red: 0.07, green: 0.045, blue: 0.075),
          mouthDetail: CharacterColor(red: 0.98, green: 0.96, blue: 0.93),
          tongue: CharacterColor(red: 0.85, green: 0.44, blue: 0.49),
          writing: CharacterColor(red: 0.50, green: 0.72, blue: 0.27),
          accent: CharacterColor(red: 0.63, green: 0.66, blue: 0.72)),
        eyeTreatment: .vertical, mouthTreatment: .filled,
        lineWidth: 0.009)
    } catch { preconditionFailure("Invalid built-in Norwegian Forest Cat style: \(error)") }
  }()
}

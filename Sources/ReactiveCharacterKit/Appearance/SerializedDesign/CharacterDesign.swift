import Foundation

public enum CharacterDesignError: Error, Sendable, Equatable, CustomStringConvertible {
  case invalid(path: String, reason: String)
  case unsupportedSchema(String)
  case resourceNotFound(String)
  case oversizedData(Int)
  case invalidViewport(width: Double, height: Double)
  case invalidPose(String)

  public var description: String {
    switch self {
    case .invalid(let path, let reason): "\(path): \(reason)"
    case .unsupportedSchema(let schema): "Unsupported design schema: \(schema)"
    case .resourceNotFound(let name): "Missing bundled design: \(name)"
    case .oversizedData(let count): "Design JSON is \(count) bytes; maximum is \(CharacterDesign.maximumProfileBytes)"
    case .invalidViewport(let width, let height): "Invalid viewport: \(width) × \(height)"
    case .invalidPose(let field): "Invalid presentation geometry: \(field)"
    }
  }
}

public struct CharacterDesignDiagnostic: Sendable, Equatable {
  public let path: String
  public let message: String
}

/// A fully validated, immutable runtime design. No file access occurs during drawing.
public struct CharacterDesign: Sendable, Equatable {
  public static let maximumProfileBytes = 131_072
  public let profile: CharacterDesignProfile
  public let lightPalette: CharacterDesignPalette
  public let darkPalette: CharacterDesignPalette
  public let layout: CharacterLayout
  public let faceRegion: CharacterRegion
  public let components: CharacterComponents
  public let motionProfile: CharacterMotionProfile
  public let transitionProfile: CharacterTransitionProfile
  public let projection: CharacterProjection
  public let accessories: [CharacterDesignedAccessory]
  public let diagnostics: [CharacterDesignDiagnostic]

  public init(profile: CharacterDesignProfile) throws {
    guard profile.schema == "characterkit.design/1" else {
      throw CharacterDesignError.unsupportedSchema(profile.schema)
    }
    try Self.validateIdentifier(profile.id, path: "id")
    try Self.validateLabel(profile.name, path: "name")
    let light = try CharacterDesignPalette(profile.palettes.light, path: "palettes.light")
    let dark = try CharacterDesignPalette(profile.palettes.dark, path: "palettes.dark")
    let l = profile.layout
    try Self.range(l.aspectRatio, 0.25...4, "layout.aspectRatio")
    try Self.range(l.inset, 0...0.25, "layout.inset")
    try Self.range(l.alignmentX, 0...1, "layout.alignmentX")
    try Self.range(l.alignmentY, 0...1, "layout.alignmentY")
    let face = try l.face.region(path: "layout.face")
    let layout = try CharacterLayout(
      eyes: l.eyes.region(path: "layout.eyes"), nose: l.nose.region(path: "layout.nose"),
      mouth: l.mouth.region(path: "layout.mouth"), writing: l.writing.region(path: "layout.writing")
    )
    guard !profile.components.isEmpty,
      Set(profile.components.map(\.rawValue)).count == profile.components.count
    else {
      throw CharacterDesignError.invalid(path: "components", reason: "must be nonempty and unique")
    }
    var components: CharacterComponents = []
    for component in profile.components {
      switch component {
      case .eyes: components.insert(.eyes)
      case .nose: components.insert(.nose)
      case .mouth: components.insert(.mouth)
      case .writing: components.insert(.writing)
      case .ornaments: components.insert(.ornaments)
      case .accessories: components.insert(.accessories)
      }
    }
    let regions: [(CharacterComponents, String, CharacterRegion)] = [
      (.eyes, "eyes", layout.eyes), (.nose, "nose", layout.nose),
      (.mouth, "mouth", layout.mouth), (.writing, "writing", layout.writing),
    ]
    for i in regions.indices where components.contains(regions[i].0) {
      for j in regions.indices where j > i && components.contains(regions[j].0) {
        let a = regions[i].2
        let b = regions[j].2
        if a.x < b.x + b.width && b.x < a.x + a.width
          && a.y < b.y + b.height && b.y < a.y + a.height
        {
          throw CharacterDesignError.invalid(
            path: "layout.\(regions[j].1)",
            reason: "enabled feature regions must not overlap (\(regions[i].1))"
          )
        }
      }
    }
    let r = profile.rendering
    for (value, allowed, path) in [
      (r.cornerRadius, 0.0...0.5, "cornerRadius"),
      (r.eyeCornerRadius, 0.0...0.5, "eyeCornerRadius"),
      (r.eyeScaleX, 0.35...1.5, "eyeScaleX"), (r.eyeScaleY, 0.35...1.5, "eyeScaleY"),
      (r.eyeSpacing, 0.5...1.5, "eyeSpacing"),
      (r.minimumMouthAspect, 0.05...1.0, "minimumMouthAspect"),
      (r.lineWidth, 0.002...0.06, "lineWidth"),
      (r.minimumStrokeWidth, 0.25...4.0, "minimumStrokeWidth"),
      (r.highlight, 0.0...1.0, "highlight"), (r.shadow, 0.0...0.5, "shadow"),
      (r.compactBelow, 0.0...256.0, "compactBelow"),
    ] { try Self.range(value, allowed, "rendering.\(path)") }
    guard [15, 30, 60, 120].contains(r.framesPerSecond) else {
      throw CharacterDesignError.invalid(
        path: "rendering.framesPerSecond", reason: "must be 15, 30, 60 or 120")
    }
    let m = profile.motion
    let motion = try CharacterMotionProfile(
      expressiveness: m.expressiveness, trailStrength: m.trailStrength,
      accentStrength: m.accentStrength, idleStrength: m.idleStrength
    )
    let t = profile.transition
    let transition = try CharacterTransitionProfile(
      minimumReturnDuration: t.minimumReturnDuration,
      maximumReturnDuration: t.maximumReturnDuration,
      neutralHoldDuration: t.neutralHoldDuration, rebound: t.rebound
    )
    guard profile.accessories.count <= 16 else {
      throw CharacterDesignError.invalid(path: "accessories", reason: "maximum is 16")
    }
    var ids = Set<String>()
    var accessories: [CharacterDesignedAccessory] = []
    for (index, item) in profile.accessories.enumerated() {
      let path = "accessories[\(index)]"
      try Self.validateIdentifier(item.id, path: "\(path).id")
      try Self.validateLabel(item.label, path: "\(path).label")
      guard ids.insert(item.id).inserted else {
        throw CharacterDesignError.invalid(path: "\(path).id", reason: "duplicate ID: \(item.id)")
      }
      try Self.range(item.width, 0.0001...4, "\(path).width")
      try Self.range(item.height, 0.0001...4, "\(path).height")
      let placement: CharacterAccessoryPlacement
      do {
        placement = try CharacterAccessoryPlacement(
          anchor: item.anchor, layer: item.layer, centerX: item.centerX, centerY: item.centerY,
          width: item.width, height: item.height, angle: item.angle, opacity: item.opacity
        )
      } catch {
        throw CharacterDesignError.invalid(path: path, reason: String(describing: error))
      }
      accessories.append(
        CharacterDesignedAccessory(
          id: item.id, label: item.label, glyph: item.glyph, placement: placement, color: item.color
        ))
    }
    self.profile = profile
    lightPalette = light
    darkPalette = dark
    self.layout = layout
    faceRegion = face
    self.components = components
    motionProfile = motion
    transitionProfile = transition
    projection = m.projection == .flat ? .flat : .softSphere
    self.accessories = accessories
    var diagnostics: [CharacterDesignDiagnostic] = []
    for (name, palette) in [("light", light), ("dark", dark)] {
      let ratio = min(
        palette.feature.contrastRatio(with: palette.surface),
        palette.feature.contrastRatio(with: palette.surfaceShade))
      if ratio < 3 {
        diagnostics.append(
          .init(
            path: "palettes.\(name).feature",
            message:
              "Feature/surface endpoint contrast is \(ratio):1, below the 3:1 design target. This is not a full accessibility audit."
          ))
      }
    }
    self.diagnostics = diagnostics
  }

  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumProfileBytes else {
      throw CharacterDesignError.oversizedData(data.count)
    }
    try CharacterDesignJSONGuard.check(data)
    return try Self(profile: JSONDecoder().decode(CharacterDesignProfile.self, from: data))
  }

  /// Load once at the host boundary, not from a per-frame callback.
  public static func load(_ preset: CharacterDesignPreset) throws -> Self {
    try decode(CharacterDesignResourceLoader.data(for: preset))
  }

  public func encodedProfile() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(profile)
  }

  public func palette(for appearance: CharacterDesignAppearance) -> CharacterDesignPalette {
    appearance == .dark ? darkPalette : lightPalette
  }

  /// Resolved per-part colors for runtime customization without mutating the authored profile.
  public func partColors(for appearance: CharacterDesignAppearance) -> CharacterPartColors {
    palette(for: appearance).partColors
  }

  private static func range(_ value: Double, _ allowed: ClosedRange<Double>, _ path: String) throws
  {
    guard value.isFinite, allowed.contains(value) else {
      throw CharacterDesignError.invalid(path: path, reason: "must be finite and within \(allowed)")
    }
  }

  private static func validateIdentifier(_ value: String, path: String) throws {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
    guard !value.isEmpty, value.utf8.count <= 64,
      value.unicodeScalars.allSatisfy({ allowed.contains($0) })
    else {
      throw CharacterDesignError.invalid(
        path: path, reason: "use 1...64 lowercase ASCII letters, digits, -, _ or .")
    }
  }

  private static func validateLabel(_ value: String, path: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.unicodeScalars.count <= 80,
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw CharacterDesignError.invalid(
        path: path, reason: "use 1...80 characters without control characters")
    }
  }
}

extension CharacterDesignProfile {
  public func compile() throws -> CharacterDesign { try CharacterDesign(profile: self) }
}

extension CharacterDesignRegion {
  func region(path: String) throws -> CharacterRegion {
    guard width >= 0.0001, height >= 0.0001 else {
      throw CharacterDesignError.invalid(
        path: path, reason: "normalized dimensions must be at least 0.0001")
    }
    return try CharacterRegion(name: path, x: x, y: y, width: width, height: height)
  }
}

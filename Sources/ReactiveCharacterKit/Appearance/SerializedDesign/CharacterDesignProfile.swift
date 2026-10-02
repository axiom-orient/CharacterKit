import Foundation

/// Editable versioned authoring data. Call `compile()` before applying it.
/// JSON fields are required except palette eye, which inherits feature when omitted.
public struct CharacterDesignProfile: Codable, Sendable, Equatable {
  public var schema: String
  public var id: String
  public var name: String
  public var palettes: CharacterDesignPalettes
  public var layout: CharacterDesignLayout
  public var rendering: CharacterDesignRendering
  public var motion: CharacterDesignMotion
  public var transition: CharacterDesignTransition
  public var components: [CharacterDesignComponent]
  public var accessories: [CharacterDesignAccessory]

  public init(
    schema: String = "characterkit.design/1",
    id: String,
    name: String,
    palettes: CharacterDesignPalettes,
    layout: CharacterDesignLayout,
    rendering: CharacterDesignRendering,
    motion: CharacterDesignMotion,
    transition: CharacterDesignTransition,
    components: [CharacterDesignComponent],
    accessories: [CharacterDesignAccessory] = []
  ) {
    self.schema = schema
    self.id = id
    self.name = name
    self.palettes = palettes
    self.layout = layout
    self.rendering = rendering
    self.motion = motion
    self.transition = transition
    self.components = components
    self.accessories = accessories
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, id, name, palettes, layout, rendering, motion, transition, components, accessories
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    schema = try values.decode(String.self, forKey: .schema)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    palettes = try values.decode(CharacterDesignPalettes.self, forKey: .palettes)
    layout = try values.decode(CharacterDesignLayout.self, forKey: .layout)
    rendering = try values.decode(CharacterDesignRendering.self, forKey: .rendering)
    motion = try values.decode(CharacterDesignMotion.self, forKey: .motion)
    transition = try values.decode(CharacterDesignTransition.self, forKey: .transition)
    components = try values.decode([CharacterDesignComponent].self, forKey: .components)
    accessories = try values.decode([CharacterDesignAccessory].self, forKey: .accessories)
  }
}

public struct CharacterDesignRegion: Codable, Sendable, Equatable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(
    x: Double,
    y: Double,
    width: Double,
    height: Double
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case x, y, width, height
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    x = try values.decode(Double.self, forKey: .x)
    y = try values.decode(Double.self, forKey: .y)
    width = try values.decode(Double.self, forKey: .width)
    height = try values.decode(Double.self, forKey: .height)
  }
}

public struct CharacterDesignLayout: Codable, Sendable, Equatable {
  public var aspectRatio: Double
  public var fit: CharacterDesignFit
  public var inset: Double
  public var alignmentX: Double
  public var alignmentY: Double
  public var face: CharacterDesignRegion
  public var eyes: CharacterDesignRegion
  public var nose: CharacterDesignRegion
  public var mouth: CharacterDesignRegion
  public var writing: CharacterDesignRegion

  public init(
    aspectRatio: Double = 1,
    fit: CharacterDesignFit = .contain,
    inset: Double = 0.025,
    alignmentX: Double = 0.5,
    alignmentY: Double = 0.5,
    face: CharacterDesignRegion,
    eyes: CharacterDesignRegion,
    nose: CharacterDesignRegion,
    mouth: CharacterDesignRegion,
    writing: CharacterDesignRegion
  ) {
    self.aspectRatio = aspectRatio
    self.fit = fit
    self.inset = inset
    self.alignmentX = alignmentX
    self.alignmentY = alignmentY
    self.face = face
    self.eyes = eyes
    self.nose = nose
    self.mouth = mouth
    self.writing = writing
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case aspectRatio, fit, inset, alignmentX, alignmentY, face, eyes, nose, mouth, writing
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    aspectRatio = try values.decode(Double.self, forKey: .aspectRatio)
    fit = try values.decode(CharacterDesignFit.self, forKey: .fit)
    inset = try values.decode(Double.self, forKey: .inset)
    alignmentX = try values.decode(Double.self, forKey: .alignmentX)
    alignmentY = try values.decode(Double.self, forKey: .alignmentY)
    face = try values.decode(CharacterDesignRegion.self, forKey: .face)
    eyes = try values.decode(CharacterDesignRegion.self, forKey: .eyes)
    nose = try values.decode(CharacterDesignRegion.self, forKey: .nose)
    mouth = try values.decode(CharacterDesignRegion.self, forKey: .mouth)
    writing = try values.decode(CharacterDesignRegion.self, forKey: .writing)
  }
}

public struct CharacterDesignRendering: Codable, Sendable, Equatable {
  public var surfaceVisible: Bool
  public var mode: CharacterRenderMode
  public var lighting: CharacterSurfaceLighting
  public var silhouette: CharacterSilhouette
  public var cornerRadius: Double
  public var eyeStyle: CharacterEyeStyle
  public var eyeCornerRadius: Double
  public var eyeScaleX: Double
  public var eyeScaleY: Double
  public var eyeSpacing: Double
  public var mouthStyle: CharacterMouthStyle
  public var minimumMouthAspect: Double
  public var lineWidth: Double
  public var minimumStrokeWidth: Double
  public var highlight: Double
  public var shadow: Double
  public var compactBelow: Double
  public var framesPerSecond: Int

  public init(
    surfaceVisible: Bool = true,
    mode: CharacterRenderMode = .sculpted,
    lighting: CharacterSurfaceLighting = .radial,
    silhouette: CharacterSilhouette = .orb,
    cornerRadius: Double = 0.32,
    eyeStyle: CharacterEyeStyle = .capsule,
    eyeCornerRadius: Double = 0.5,
    eyeScaleX: Double = 1,
    eyeScaleY: Double = 1,
    eyeSpacing: Double = 1,
    mouthStyle: CharacterMouthStyle = .filled,
    minimumMouthAspect: Double = 0.35,
    lineWidth: Double = 0.012,
    minimumStrokeWidth: Double = 1,
    highlight: Double = 0.28,
    shadow: Double = 0.16,
    compactBelow: Double = 72,
    framesPerSecond: Int = 60
  ) {
    self.surfaceVisible = surfaceVisible
    self.mode = mode
    self.lighting = lighting
    self.silhouette = silhouette
    self.cornerRadius = cornerRadius
    self.eyeStyle = eyeStyle
    self.eyeCornerRadius = eyeCornerRadius
    self.eyeScaleX = eyeScaleX
    self.eyeScaleY = eyeScaleY
    self.eyeSpacing = eyeSpacing
    self.mouthStyle = mouthStyle
    self.minimumMouthAspect = minimumMouthAspect
    self.lineWidth = lineWidth
    self.minimumStrokeWidth = minimumStrokeWidth
    self.highlight = highlight
    self.shadow = shadow
    self.compactBelow = compactBelow
    self.framesPerSecond = framesPerSecond
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case surfaceVisible, mode, lighting, silhouette, cornerRadius, eyeStyle, eyeCornerRadius,
      eyeScaleX, eyeScaleY, eyeSpacing, mouthStyle, minimumMouthAspect, lineWidth,
      minimumStrokeWidth, highlight,
      shadow, compactBelow, framesPerSecond
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    surfaceVisible = try values.decode(Bool.self, forKey: .surfaceVisible)
    mode = try values.decode(CharacterRenderMode.self, forKey: .mode)
    lighting = try values.decode(CharacterSurfaceLighting.self, forKey: .lighting)
    silhouette = try values.decode(CharacterSilhouette.self, forKey: .silhouette)
    cornerRadius = try values.decode(Double.self, forKey: .cornerRadius)
    eyeStyle = try values.decode(CharacterEyeStyle.self, forKey: .eyeStyle)
    eyeCornerRadius = try values.decode(Double.self, forKey: .eyeCornerRadius)
    eyeScaleX = try values.decode(Double.self, forKey: .eyeScaleX)
    eyeScaleY = try values.decode(Double.self, forKey: .eyeScaleY)
    eyeSpacing = try values.decode(Double.self, forKey: .eyeSpacing)
    mouthStyle = try values.decode(CharacterMouthStyle.self, forKey: .mouthStyle)
    minimumMouthAspect = try values.decode(Double.self, forKey: .minimumMouthAspect)
    lineWidth = try values.decode(Double.self, forKey: .lineWidth)
    minimumStrokeWidth = try values.decode(Double.self, forKey: .minimumStrokeWidth)
    highlight = try values.decode(Double.self, forKey: .highlight)
    shadow = try values.decode(Double.self, forKey: .shadow)
    compactBelow = try values.decode(Double.self, forKey: .compactBelow)
    framesPerSecond = try values.decode(Int.self, forKey: .framesPerSecond)
  }
}

public struct CharacterDesignMotion: Codable, Sendable, Equatable {
  public var projection: CharacterDesignProjection
  public var expressiveness: Double
  public var trailStrength: Double
  public var accentStrength: Double
  public var idleStrength: Double

  public init(
    projection: CharacterDesignProjection = .softSphere,
    expressiveness: Double = 1,
    trailStrength: Double = 1,
    accentStrength: Double = 1,
    idleStrength: Double = 1
  ) {
    self.projection = projection
    self.expressiveness = expressiveness
    self.trailStrength = trailStrength
    self.accentStrength = accentStrength
    self.idleStrength = idleStrength
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case projection, expressiveness, trailStrength, accentStrength, idleStrength
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    projection = try values.decode(CharacterDesignProjection.self, forKey: .projection)
    expressiveness = try values.decode(Double.self, forKey: .expressiveness)
    trailStrength = try values.decode(Double.self, forKey: .trailStrength)
    accentStrength = try values.decode(Double.self, forKey: .accentStrength)
    idleStrength = try values.decode(Double.self, forKey: .idleStrength)
  }
}

public struct CharacterDesignTransition: Codable, Sendable, Equatable {
  public var minimumReturnDuration: Double
  public var maximumReturnDuration: Double
  public var neutralHoldDuration: Double
  public var rebound: Double

  public init(
    minimumReturnDuration: Double = 0.16,
    maximumReturnDuration: Double = 0.68,
    neutralHoldDuration: Double = 0.08,
    rebound: Double = 0.045
  ) {
    self.minimumReturnDuration = minimumReturnDuration
    self.maximumReturnDuration = maximumReturnDuration
    self.neutralHoldDuration = neutralHoldDuration
    self.rebound = rebound
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case minimumReturnDuration, maximumReturnDuration, neutralHoldDuration, rebound
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.characterDesignContainer(keyedBy: CodingKeys.self)
    minimumReturnDuration = try values.decode(Double.self, forKey: .minimumReturnDuration)
    maximumReturnDuration = try values.decode(Double.self, forKey: .maximumReturnDuration)
    neutralHoldDuration = try values.decode(Double.self, forKey: .neutralHoldDuration)
    rebound = try values.decode(Double.self, forKey: .rebound)
  }
}

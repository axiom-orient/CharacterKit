#if os(iOS) || os(macOS)
  import SwiftUI

  /// Native adapter for an already-built vector frame. Supply accessibility semantics at the host.
  @available(iOS 16.0, macOS 13.0, *)
  public struct CharacterSceneCanvas: View {
    private let scene: CharacterScene
    private let overlayLayout: CharacterLayout?
    private let accessoryOverlays: [CharacterAccessoryOverlay]

    public init(
      scene: CharacterScene,
      layout: CharacterLayout? = nil,
      accessoryOverlays: [CharacterAccessoryOverlay] = []
    ) {
      self.scene = scene
      self.overlayLayout = layout
      self.accessoryOverlays = accessoryOverlays
    }

    public var body: some View {
      Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
        CharacterSceneCanvasRenderer.draw(
          scene: scene, context: &context, layout: overlayLayout,
          overlays: accessoryOverlays
        )
      }
      .frame(width: scene.width, height: scene.height)
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  enum CharacterSceneCanvasRenderer {
    static func missingImageAccessibilityValue(in scene: CharacterScene) -> String {
      var seen = Set<CharacterImageAsset>()
      return scene.nodes.compactMap { node -> String? in
        guard let image = node.image, seen.insert(image.asset).inserted else { return nil }
        return CharacterPlatformImageLoader.named(image.asset) == nil
          ? "Missing image: \(image.asset.name)" : nil
      }.joined(separator: ", ")
    }

    static func draw(
      scene: CharacterScene, context: inout GraphicsContext,
      design: CharacterDesign? = nil, layout: CharacterLayout? = nil,
      overlays: [CharacterAccessoryOverlay] = []
    ) {
      let resolvedLayout = design?.layout ?? layout
      let overlaysEnabled = design?.components.contains(.accessories) ?? (layout != nil)
      var nodesByLayer: [Int: [CharacterSceneNode]] = [:]
      for node in scene.nodes { nodesByLayer[node.layer.rawValue, default: []].append(node) }
      for stage in CharacterSceneLayer.allCases {
        for node in nodesByLayer[stage.rawValue] ?? [] {
          var part = context
          part.concatenate(node.transform.cgTransform)
          for clip in node.clips { part.clip(to: path(clip)) }
          part.opacity *= node.opacity
          if let image = node.image {
            let rect = image.bounds.rect.cgRect
            if let uiImage = CharacterPlatformImageLoader.named(image.asset) {
              let size = uiImage.size
              let scale =
                image.contentMode == .fit
                ? min(rect.width / size.width, rect.height / size.height)
                : max(rect.width / size.width, rect.height / size.height)
              let destination = CGRect(
                x: rect.midX - size.width * scale / 2,
                y: rect.midY - size.height * scale / 2,
                width: size.width * scale, height: size.height * scale)
              part.clip(to: Path(rect))
              part.draw(part.resolve(uiImage.characterSwiftUIImage), in: destination)
            } else {
              // A named required resource failing to resolve is visible, never silently skipped.
              part.stroke(Path(rect), with: .color(.red), lineWidth: 2)
              part.draw(
                Text("Missing image: \(image.asset.name)").foregroundColor(.red),
                at: CGPoint(x: rect.midX, y: rect.midY))
            }
          }
          let shape = path(node.path)
          if let fill = node.fill { part.fill(shape, with: shading(fill)) }
          if let stroke = node.stroke {
            part.stroke(
              shape, with: .color(stroke.swiftUIColor),
              style: StrokeStyle(lineWidth: node.lineWidth, lineCap: .round, lineJoin: .round))
          }
        }
        if let resolvedLayout, let layer = imageLayer(stage), !overlays.isEmpty {
          var part = context
          part.concatenate(scene.surfaceTransform.cgTransform)
          CharacterImageOverlayRenderer.draw(
            context: &part, coordinateSpace: scene.faceBounds.rect, layout: resolvedLayout,
            overlays: overlays, layer: layer, enabled: overlaysEnabled
          )
        }
      }
    }

    private static func imageLayer(_ stage: CharacterSceneLayer) -> CharacterAccessoryLayer? {
      switch stage {
      case .behindSurface: .behindSurface
      case .behindFeatures: .behindFeatures
      case .foreground: .foreground
      default: nil
      }
    }

    private static func shading(_ paint: CharacterScenePaint) -> GraphicsContext.Shading {
      switch paint {
      case .solid(let color):
        return .color(color.swiftUIColor)
      case .linear(let start, let end, let stops):
        return .linearGradient(gradient(stops), startPoint: start.cgPoint, endPoint: end.cgPoint)
      case .radial(let center, let radius, let stops):
        return .radialGradient(
          gradient(stops), center: center.cgPoint, startRadius: 0, endRadius: radius)
      }
    }

    private static func gradient(_ stops: [CharacterGradientStop]) -> Gradient {
      Gradient(
        stops: stops.map {
          .init(color: $0.color.swiftUIColor.opacity($0.opacity), location: $0.location)
        })
    }

    static func path(_ source: CharacterVectorPath) -> Path {
      var path = Path()
      for command in source.commands {
        switch command {
        case .move(let p): path.move(to: p.cgPoint)
        case .line(let p): path.addLine(to: p.cgPoint)
        case .quad(let c, let p): path.addQuadCurve(to: p.cgPoint, control: c.cgPoint)
        case .cubic(let c1, let c2, let p):
          path.addCurve(to: p.cgPoint, control1: c1.cgPoint, control2: c2.cgPoint)
        case .close: path.closeSubpath()
        }
      }
      return path
    }
  }
#endif

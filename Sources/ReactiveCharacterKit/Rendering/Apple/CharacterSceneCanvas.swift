#if os(iOS) || os(macOS)
  import SwiftUI

  /// Native adapter for an already-built SEMI scene.
  @available(iOS 16.0, macOS 13.0, *)
  public struct CharacterSceneCanvas: View {
    private let scene: CharacterScene

    public init(scene: CharacterScene) {
      self.scene = scene
    }

    public var body: some View {
      Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
        CharacterSceneCanvasRenderer.draw(scene: scene, context: &context)
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

    static func draw(scene: CharacterScene, context: inout GraphicsContext) {
      for node in scene.nodes {
        var part = context
        part.concatenate(node.transform.cgTransform)
        for clip in node.clips { part.clip(to: path(clip)) }
        part.opacity *= node.opacity

        if let image = node.image {
          let rect = image.bounds.rect.cgRect
          if let platformImage = CharacterPlatformImageLoader.named(image.asset) {
            let size = platformImage.size
            guard size.width > 0, size.height > 0 else { continue }
            let scale = image.contentMode == .fit
              ? min(rect.width / size.width, rect.height / size.height)
              : max(rect.width / size.width, rect.height / size.height)
            let destination = CGRect(
              x: rect.midX - size.width * scale / 2,
              y: rect.midY - size.height * scale / 2,
              width: size.width * scale,
              height: size.height * scale
            )
            part.clip(to: Path(rect))
            part.draw(part.resolve(platformImage.characterSwiftUIImage), in: destination)
          } else {
            // Required resources fail visibly instead of disappearing from the frame.
            part.stroke(Path(rect), with: .color(.red), lineWidth: 2)
            part.draw(
              Text("Missing image: \(image.asset.name)").foregroundColor(.red),
              at: CGPoint(x: rect.midX, y: rect.midY)
            )
          }
        }

        let shape = path(node.path)
        if let fill = node.fill { part.fill(shape, with: shading(fill)) }
        if let stroke = node.stroke {
          part.stroke(
            shape,
            with: .color(stroke.swiftUIColor),
            style: StrokeStyle(lineWidth: node.lineWidth, lineCap: .round, lineJoin: .round)
          )
        }
      }
    }

    private static func shading(_ paint: CharacterScenePaint) -> GraphicsContext.Shading {
      switch paint {
      case .solid(let color):
        .color(color.swiftUIColor)
      case .linear(let start, let end, let stops):
        .linearGradient(gradient(stops), startPoint: start.cgPoint, endPoint: end.cgPoint)
      case .radial(let center, let radius, let stops):
        .radialGradient(gradient(stops), center: center.cgPoint, startRadius: 0, endRadius: radius)
      }
    }

    private static func gradient(_ stops: [CharacterGradientStop]) -> Gradient {
      Gradient(stops: stops.map {
        .init(color: $0.color.swiftUIColor.opacity($0.opacity), location: $0.location)
      })
    }

    static func path(_ source: CharacterVectorPath) -> Path {
      var path = Path()
      for command in source.commands {
        switch command {
        case .move(let point): path.move(to: point.cgPoint)
        case .line(let point): path.addLine(to: point.cgPoint)
        case .quad(let control, let point): path.addQuadCurve(to: point.cgPoint, control: control.cgPoint)
        case .cubic(let control1, let control2, let point):
          path.addCurve(to: point.cgPoint, control1: control1.cgPoint, control2: control2.cgPoint)
        case .close: path.closeSubpath()
        }
      }
      return path
    }
  }
#endif

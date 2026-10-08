import Foundation

/// A second backend for the same frame consumed by SwiftUI Canvas.
/// Hybrid frames embed explicit local PNG layers; never scripts, remote URLs or fallbacks.
public enum CharacterSVGRenderer {
  private static let numberLocale = Locale(identifier: "en_US_POSIX")

  public static func render(
    _ scene: CharacterScene, title: String = "Reactive character",
    idPrefix: String = "character"
  ) throws -> String {
    try CharacterSceneValidation.validate(scene)
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    guard !idPrefix.isEmpty, idPrefix.utf8.count <= 80,
      idPrefix.unicodeScalars.allSatisfy({ allowed.contains($0) })
    else {
      throw CharacterSceneError.invalidScene(
        path: "idPrefix", reason: "use 1...80 ASCII letters, digits, -, _ or .")
    }
    guard title.count <= 512,
      title.unicodeScalars.allSatisfy({ scalar in
        // XML 1.0 excludes these scalars even though they are not controls.
        !CharacterSet.controlCharacters.contains(scalar)
          && scalar.value != 0xFFFE && scalar.value != 0xFFFF
      })
    else {
      throw CharacterSceneError.invalidScene(
        path: "title", reason: "use at most 512 XML characters without controls")
    }
    let prefix = "ck-\(idPrefix)"
    var definitions: [String] = []
    var elements: [String] = []
    // Local to this frame, keyed by serialized geometry. userSpaceOnUse resolves at each node.
    var clipIDs: [String: String] = [:]
    // One source payload per exact asset in this export; no cross-frame resource cache.
    var embeddedImages: [CharacterImageAsset: String] = [:]
    for (index, node) in scene.nodes.enumerated() {
      let name = "\(prefix)-n\(index)"
      let data = pathData(node.path)
      let matrix = [
        node.transform.a, node.transform.b, node.transform.c, node.transform.d,
        node.transform.tx, node.transform.ty,
      ].map(number).joined(separator: " ")
      var part = "<g data-part=\"\(escape(node.id))\" transform=\"matrix(\(matrix))\">"
      for path in node.clips {
        let data = pathData(path)
        let clipID: String
        if let existing = clipIDs[data] {
          clipID = existing
        } else {
          clipID = "\(prefix)-clip\(clipIDs.count)"
          clipIDs[data] = clipID
          definitions.append(
            "<clipPath id=\"\(clipID)\" clipPathUnits=\"userSpaceOnUse\"><path d=\"\(data)\"/></clipPath>"
          )
        }
        part += "<g clip-path=\"url(#\(clipID))\">"
      }
      if let image = node.image {
        let encodedImage: String
        if let cached = embeddedImages[image.asset] {
          encodedImage = cached
        } else {
          encodedImage = try CharacterImageResources.png(image.asset).base64EncodedString()
          embeddedImages[image.asset] = encodedImage
        }
        let r = image.bounds
        let fit = image.contentMode == .fit ? "xMidYMid meet" : "xMidYMid slice"
        part +=
          "<image x=\"\(number(r.x))\" y=\"\(number(r.y))\" width=\"\(number(r.width))\" height=\"\(number(r.height))\" opacity=\"\(number(node.opacity))\" preserveAspectRatio=\"\(fit)\" xlink:href=\"data:image/png;base64,\(encodedImage)\"/>"
      }
      if let fill = node.fill {
        let paint = paint(fill, id: "\(name)-fill", definitions: &definitions)
        part +=
          "<path d=\"\(data)\" fill=\"\(paint.value)\" fill-opacity=\"\(number(paint.opacity * node.opacity))\"/>"
      }
      if let stroke = node.stroke {
        part +=
          "<path d=\"\(data)\" fill=\"none\" stroke=\"\(hex(stroke))\" stroke-width=\"\(number(node.lineWidth))\" stroke-opacity=\"\(number(node.opacity * stroke.alpha))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
      }
      part += String(repeating: "</g>", count: node.clips.count + 1)
      elements.append(part)
    }
    let imageNamespace =
      scene.nodes.contains { $0.image != nil }
      ? " xmlns:xlink=\"http://www.w3.org/1999/xlink\"" : ""
    return """
      <svg xmlns="http://www.w3.org/2000/svg"\(imageNamespace) width="\(number(scene.width))" height="\(number(scene.height))" viewBox="0 0 \(number(scene.width)) \(number(scene.height))" role="img" aria-labelledby="\(prefix)-title" color-interpolation="sRGB">
      <title id="\(prefix)-title">\(escape(title))</title>
      <defs>\(definitions.joined())</defs>
      \(elements.joined(separator: "\n"))
      </svg>
      """
  }

  private static func paint(_ paint: CharacterScenePaint, id: String, definitions: inout [String])
    -> (value: String, opacity: Double)
  {
    switch paint {
    case .solid(let color): return (hex(color), color.alpha)
    case .linear(let start, let end, let stops):
      definitions.append(
        "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(number(start.x))\" y1=\"\(number(start.y))\" x2=\"\(number(end.x))\" y2=\"\(number(end.y))\">\(stopData(stops))</linearGradient>"
      )
    case .radial(let center, let radius, let stops):
      definitions.append(
        "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(number(center.x))\" cy=\"\(number(center.y))\" r=\"\(number(radius))\">\(stopData(stops))</radialGradient>"
      )
    }
    return ("url(#\(id))", 1)
  }

  private static func stopData(_ stops: [CharacterGradientStop]) -> String {
    stops.map {
      "<stop offset=\"\(number($0.location))\" stop-color=\"\(hex($0.color))\" stop-opacity=\"\(number($0.opacity * $0.color.alpha))\"/>"
    }.joined()
  }

  private static func pathData(_ path: CharacterVectorPath) -> String {
    func point(_ p: CharacterVectorPoint) -> String { "\(number(p.x)) \(number(p.y))" }
    return path.commands.map { command in
      switch command {
      case .move(let p): "M\(point(p))"
      case .line(let p): "L\(point(p))"
      case .quad(let c, let e): "Q\(point(c)) \(point(e))"
      case .cubic(let c1, let c2, let e): "C\(point(c1)) \(point(c2)) \(point(e))"
      case .close: "Z"
      }
    }.joined(separator: " ")
  }

  static func number(_ value: Double) -> String {
    String(format: "%.6f", locale: numberLocale, value == 0 ? 0 : value)
  }

  static func hex(_ c: CharacterColor) -> String {
    String(
      format: "#%02X%02X%02X", Int((c.red * 255).rounded()),
      Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
  }
}

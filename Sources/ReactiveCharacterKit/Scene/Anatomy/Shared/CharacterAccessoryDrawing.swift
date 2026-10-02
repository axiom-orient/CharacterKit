import Foundation

extension CharacterSceneDrawing {
  mutating func drawAccessory(_ item: CharacterDesignedAccessory) {
    guard item.placement.opacity > 0 else { return }
    let envelope = CharacterAccessoryGeometry.envelope(
      for: item.placement, face: face, layout: design.layout)
    let layer: CharacterSceneLayer
    switch item.placement.layer {
    case .behindSurface: layer = .behindSurface
    case .behindFeatures: layer = .behindFeatures
    case .foreground: layer = .foreground
    }
    let rotation = transform.concatenating(
      .around(x: envelope.midX, y: envelope.midY, angle: item.placement.angle))
    let color = usesRuntimePartColors ? partColors.accessory : palette.color(for: item.color)
    let detail = usesRuntimePartColors ? partColors.accessoryDetail : palette.detail
    let outline = usesRuntimePartColors ? partColors.accessoryDetail : palette.outline
    let line = min(strokeWidth * 1.05, min(envelope.width, envelope.height) * 0.10)
    let prefix = "accessory.\(item.id)"
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CharacterRect {
      .init(x: x, y: y, width: w, height: h)
    }
    func paint(_ path: CharacterVectorPath) -> CharacterVectorPath { localPath(path, in: envelope) }
    switch item.glyph {
    case .roundGlasses:
      for (index, x) in [0.04, 0.57].enumerated() {
        let lens = paint(.roundedRectangle(rect(x, 0.13, 0.39, 0.72), radius: 0.16))
        if !simplified {
          add(
            "\(prefix).lens.\(index)", lens, layer: layer, fill: .solid(detail),
            opacity: item.placement.opacity * 0.055, transform: rotation)
        }
        add(
          "\(prefix).frame.\(index)", lens, layer: layer, stroke: color,
          width: line, opacity: item.placement.opacity, transform: rotation)
      }
      var bridge = CharacterVectorPath()
      bridge.move(0.43, 0.44)
      bridge.quad(0.50, 0.32, 0.57, 0.44)
      bridge.move(0.00, 0.32)
      bridge.line(0.04, 0.42)
      bridge.move(0.96, 0.42)
      bridge.line(1.00, 0.32)
      add(
        "\(prefix).bridge", paint(bridge), layer: layer, stroke: color,
        width: line, opacity: item.placement.opacity, transform: rotation)
    case .visor:
      let body = paint(.roundedRectangle(rect(0.02, 0.10, 0.96, 0.80), radius: 0.20))
      add(
        "\(prefix).body", body, layer: layer, fill: .solid(color),
        stroke: outline, width: line * 0.7, opacity: item.placement.opacity,
        transform: rotation)
      var stripe = CharacterVectorPath()
      stripe.move(0.20, 0.39)
      stripe.line(0.80, 0.39)
      add(
        "\(prefix).stripe", paint(stripe), layer: layer, stroke: detail,
        width: line, opacity: item.placement.opacity, transform: rotation)
    case .crown:
      var p = CharacterVectorPath()
      p.move(0.08, 0.27)
      p.line(0.29, 0.46)
      p.line(0.50, 0.07)
      p.line(0.71, 0.46)
      p.line(0.92, 0.27)
      p.line(0.84, 0.87)
      p.quad(0.50, 0.98, 0.16, 0.87)
      p.close()
      add(
        "\(prefix).body", paint(p), layer: layer, fill: .solid(color), stroke: outline,
        width: line * 0.55, opacity: item.placement.opacity, transform: rotation)
      add(
        "\(prefix).gem", paint(.ellipse(rect(0.435, 0.55, 0.13, 0.18))), layer: layer,
        fill: .solid(detail), opacity: item.placement.opacity, transform: rotation)
    case .bowTie:
      var p = CharacterVectorPath()
      p.move(0.06, 0.16)
      p.quad(0.02, 0.50, 0.06, 0.84)
      p.line(0.48, 0.58)
      p.line(0.48, 0.42)
      p.close()
      p.move(0.94, 0.16)
      p.quad(0.98, 0.50, 0.94, 0.84)
      p.line(0.52, 0.58)
      p.line(0.52, 0.42)
      p.close()
      add(
        "\(prefix).wings", paint(p), layer: layer, fill: .solid(color),
        stroke: outline, width: line * 0.5, opacity: item.placement.opacity,
        transform: rotation)
      add(
        "\(prefix).knot", paint(.roundedRectangle(rect(0.41, 0.27, 0.18, 0.46), radius: 0.07)),
        layer: layer, fill: .solid(color), stroke: detail, width: line * 0.45,
        opacity: item.placement.opacity, transform: rotation)
    case .badge:
      add(
        "\(prefix).body", paint(.ellipse(rect(0.06, 0.06, 0.88, 0.88))), layer: layer,
        fill: .solid(color), stroke: outline, width: line * 0.6,
        opacity: item.placement.opacity, transform: rotation)
      var p = CharacterVectorPath()
      p.move(0.50, 0.22)
      p.line(0.57, 0.43)
      p.line(0.78, 0.50)
      p.line(0.57, 0.57)
      p.line(0.50, 0.78)
      p.line(0.43, 0.57)
      p.line(0.22, 0.50)
      p.line(0.43, 0.43)
      p.close()
      add(
        "\(prefix).mark", paint(p), layer: layer, fill: .solid(detail),
        opacity: item.placement.opacity, transform: rotation)
    case .headphones:
      var arch = CharacterVectorPath()
      arch.move(0.09, 0.66)
      arch.cubic(0.06, -0.10, 0.94, -0.10, 0.91, 0.66)
      add(
        "\(prefix).arch", paint(arch), layer: layer, stroke: color,
        width: line * 1.45, opacity: item.placement.opacity, transform: rotation)
      for (index, x) in [0.015, 0.84].enumerated() {
        add(
          "\(prefix).cup.\(index)",
          paint(.roundedRectangle(rect(x, 0.47, 0.145, 0.47), radius: 0.06)),
          layer: layer, fill: .solid(color), stroke: outline,
          width: line * 0.6, opacity: item.placement.opacity, transform: rotation)
      }
    case .halo:
      let ring = paint(.ellipse(rect(0.06, 0.16, 0.88, 0.66)))
      add(
        "\(prefix).ring", ring, layer: layer, stroke: color,
        width: line * 1.5, opacity: item.placement.opacity, transform: rotation)
      if mode == .sculpted, !simplified, !compact {
        add(
          "\(prefix).light", ring, layer: layer, stroke: detail,
          width: line * 0.38, opacity: item.placement.opacity * 0.7, transform: rotation)
      }
    }
  }
}

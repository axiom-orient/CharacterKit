import Foundation

extension CharacterDesignLayout {
  func artboard(width: Double, height: Double) -> CharacterRect {
    let padding = min(width, height) * inset
    let availableWidth = width - padding * 2
    let availableHeight = height - padding * 2
    if fit == .stretch {
      return .init(x: padding, y: padding, width: availableWidth, height: availableHeight)
    }
    let scale =
      fit == .contain
      ? min(availableWidth / aspectRatio, availableHeight)
      : max(availableWidth / aspectRatio, availableHeight)
    let w = aspectRatio * scale
    let h = scale
    return .init(
      x: padding + (availableWidth - w) * alignmentX,
      y: padding + (availableHeight - h) * alignmentY, width: w, height: h)
  }
}

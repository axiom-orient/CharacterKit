import Foundation

extension CharacterCatDrawing {
  mutating func drawEye(left: Bool) {
    if theme == .simple2D {
      let source = left ? pose.eyes.left : pose.eyes.right
      let contour = (left ? pose.eyeContours.left : pose.eyeContours.right)
        .presentingSmile(as: direction.style.smileEyeShape)
      let center = CharacterVectorPoint(
        x: (left ? CharacterSimpleCatGeometry.eyeCenters.left
          : CharacterSimpleCatGeometry.eyeCenters.right) + min(1, max(-1, gazeX)) * 10,
        y: CharacterSimpleCatGeometry.eyeY + min(1, max(-1, gazeY)) * 8)
      add(
        left ? "eye.left" : "eye.right",
        CharacterCompactEyeGeometry.path(
          eye: source, contour: contour, left: left, center: center,
          width: CharacterSimpleCatGeometry.eyeWidth,
          height: CharacterSimpleCatGeometry.eyeHeight, treatment: direction.style.eyeTreatment,
          thickness: CharacterSimpleCatGeometry.eyeInkWidth,
          expressionWidth: CharacterSimpleCatGeometry.expressionWidth),
        fill: .solid(direction.style.partColors.eyes))
      return
    }
    let source = left ? pose.eyes.left : pose.eyes.right
    let contour = left ? pose.eyeContours.left : pose.eyeContours.right
    let eye = CharacterCatEye(
      eye: source, contour: contour, left: left,
      treatment: direction.style.eyeTreatment, gazeX: gazeX, gazeY: gazeY)
    let id = left ? "eye.left" : "eye.right"
    let aperture = eye.aperture(left: left)
    let local = CharacterSceneTransform.around(x: eye.centerX, y: eye.centerY, angle: eye.angle)
    let visible = eye.closure < 1 - CharacterCatMetrics.closedThreshold ? 1.0 : 0.0
    let white = color(0.98, 0.965, 0.955)
    let shade = color(0.72, 0.71, 0.76)
    let scleraFill: CharacterScenePaint =
      if simplified {
        .solid(white)
      } else {
        .linear(
          start: .init(x: eye.centerX, y: eye.centerY - eye.height / 2),
          end: .init(x: eye.centerX, y: eye.centerY + eye.height / 2),
          stops: [
            .init(location: 0, color: shade, opacity: 1),
            .init(location: 0.22, color: white, opacity: 1),
            .init(location: 1, color: color(0.91, 0.91, 0.94), opacity: 1),
          ])
      }
    add(
      id, aperture, fill: scleraFill, stroke: ink,
      width: 2.4, opacity: visible, local: local)

    // Iris remains anatomically large. Surprise is expressed primarily by eyelid opening and pupil
    // dilation, rather than shrinking the iris into a human-like dot.
    let irisScale = 1 - eye.surprise * 0.16
    let irisWidth = CharacterCatMetrics.irisWidth * irisScale
    let irisHeight = CharacterCatMetrics.irisHeight * irisScale
    let ix = eye.centerX + CharacterCatMetrics.maximumGazeTravel * gazeX + (left ? 9 : -9)
    let iy = eye.centerY + 6 + CharacterCatMetrics.maximumGazeTravel * gazeY * 0.55
    let iris = CharacterRect(
      x: ix - irisWidth / 2, y: iy - irisHeight / 2,
      width: irisWidth, height: irisHeight)
    let irisPath = CharacterVectorPath.ellipse(iris)
    let base = direction.style.partColors.eyes
    let deep = mix(base, color(0.015, 0.02, 0.07), 0.78)
    let lightTarget = color(0.72, 0.96, 1)
    let light = mix(base, lightTarget, 0.65)
    let irisFill: CharacterScenePaint =
      if simplified {
        .solid(base)
      } else {
        .linear(
          start: .init(x: ix, y: iris.minY), end: .init(x: ix, y: iris.maxY),
          stops: [
            .init(location: 0, color: deep, opacity: 1),
            .init(location: 0.35, color: mix(base, deep, 0.58), opacity: 1),
            .init(location: 0.68, color: base, opacity: 1),
            .init(location: 1, color: light, opacity: 1),
          ])
      }
    add(
      id + ".iris", irisPath, fill: irisFill,
      stroke: mix(ink, deep, 0.5), width: 2.2,
      opacity: visible, local: local, clips: [aperture])
    if !simplified {
      irisFibers(
        id: id, in: iris, centerX: ix, centerY: iy,
        color: light, local: local, clips: [aperture, irisPath], opacity: visible)
      let caustic = CharacterRect(
        x: ix - irisWidth * 0.24, y: iy + irisHeight * 0.25,
        width: irisWidth * 0.48, height: irisHeight * 0.22)
      add(
        id + ".iris.caustic", .ellipse(caustic),
        fill: .radial(
          center: .init(x: caustic.midX, y: caustic.midY), radius: caustic.width * 0.68,
          stops: [
            .init(location: 0, color: lightTarget, opacity: 0.94),
            .init(location: 0.58, color: light, opacity: 0.7),
            .init(location: 1, color: light, opacity: 0),
          ]),
        opacity: visible, local: local, clips: [aperture, irisPath])
    }

    // Feline default: a long, narrow vertical slit. Strong surprise dilates the pupil rather than
    // changing the eye into a human round pupil. Affection may still morph into the authored heart.
    let dilation = CharacterCatMetrics.clamp(eye.surprise * 0.82 + eye.heart * 0.22, 0, 1)
    let pupilWidth =
      irisWidth
      * (CharacterCatMetrics.pupilBaseWidthRatio
        + dilation * CharacterCatMetrics.pupilDilationWidthGain - eye.pinch * 0.025)
    let pupilHeight =
      irisHeight
      * (CharacterCatMetrics.pupilBaseHeightRatio
        - dilation * CharacterCatMetrics.pupilDilationHeightLoss)
    let pupilBounds = CharacterRect(
      x: ix - pupilWidth / 2, y: iy - pupilHeight / 2,
      width: pupilWidth, height: pupilHeight)
    let pupil = pupilContour(in: pupilBounds, heart: eye.heart)
    add(
      id + ".pupil", pupil, fill: .solid(color(0.006, 0.018, 0.05)),
      opacity: visible, local: local, clips: [aperture, irisPath])

    // Corneal highlights follow the eye surface/light source more than the iris. They move only a
    // fraction of the gaze distance while staying clipped to the current iris.
    let surfaceGlintX =
      ix - CharacterCatMetrics.maximumGazeTravel * gazeX
      * CharacterCatMetrics.glintHorizontalGazeFollow
    let surfaceGlintY =
      iy - CharacterCatMetrics.maximumGazeTravel * gazeY
      * CharacterCatMetrics.glintVerticalGazeFollow
    let glint = CharacterRect(
      x: surfaceGlintX + irisWidth * 0.10, y: surfaceGlintY - irisHeight * 0.44,
      width: irisWidth * 0.23, height: irisHeight * 0.16)
    add(
      id + ".highlight", .ellipse(glint), fill: .solid(.designWhite),
      opacity: visible, local: local, clips: [aperture, irisPath])
    let small = CharacterRect(
      x: surfaceGlintX - irisWidth * 0.34, y: surfaceGlintY - irisHeight * 0.13,
      width: irisWidth * 0.10, height: irisWidth * 0.11)
    add(
      id + ".highlight.small", .ellipse(small), fill: .solid(.designWhite),
      opacity: visible * 0.86, local: local, clips: [aperture, irisPath])
    let lid = eye.upperLid(left: left)
    add(id + ".lid", lid, stroke: ink, width: 6.0, local: local)

    // A short eye is not the same thing as a one-line eye. Keep a lower contour visible for
    // compact/half-closed states, while allowing a fully closed blink or crescent to resolve to
    // the single authored upper-lid stroke. This mirrors the reference cat's sleepy almond:
    // upper lid descends, lower lid remains a separate soft boundary.
    let compactness = CharacterCatMetrics.clamp(
      (CharacterCatMetrics.eyeHeight * 0.78 - eye.height)
        / (CharacterCatMetrics.eyeHeight * 0.32))
    let closureAccent =
      eye.closure < 0.92
      ? CharacterCatMetrics.clamp((eye.closure - 0.08) / 0.68)
      : 0
    let lowerVisibility = max(compactness * (1 - eye.closure), closureAccent)
    let lower = eye.lowerLid(left: left)
    add(
      id + ".lid.lower", lower, stroke: ink,
      width: 4.0 + lowerVisibility * 1.2,
      opacity: lowerVisibility * 0.92, local: local)
  }

  private func pupilContour(in rect: CharacterRect, heart: Double) -> CharacterVectorPath {
    let count = CharacterCatMetrics.pupilContourSamples
    var points: [CharacterVectorPoint] = []
    for index in 0..<count {
      let t = Double(index) * 2.0 * Double.pi / Double(count)
      let sine = sin(t)
      let hx = sine * sine * sine
      let harmonics = 13.0 * cos(t) - 5.0 * cos(2.0 * t)
      let hy = -(harmonics - 2.0 * cos(3.0 * t) - cos(4.0 * t)) / 17.0
      let dx = sine * (1.0 - heart) + hx * heart * 1.5
      let dy = -cos(t) * (1.0 - heart) + hy * heart
      points.append(
        .init(
          x: rect.midX + rect.width * 0.5 * dx,
          y: rect.midY + rect.height * 0.5 * dy))
    }
    var path = CharacterVectorPath()
    path.move(points[0].x, points[0].y)
    for i in 0..<count {
      let previous = points[(i + count - 1) % count]
      let current = points[i]
      let next = points[(i + 1) % count]
      let after = points[(i + 2) % count]
      path.cubic(
        current.x + (next.x - previous.x) / 6, current.y + (next.y - previous.y) / 6,
        next.x - (after.x - current.x) / 6, next.y - (after.y - current.y) / 6,
        next.x, next.y)
    }
    path.close()
    return path
  }

  private mutating func irisFibers(
    id: String, in rect: CharacterRect, centerX x: Double, centerY y: Double,
    color: CharacterColor, local: CharacterSceneTransform,
    clips: [CharacterVectorPath], opacity: Double
  ) {
    var path = CharacterVectorPath()
    let rx = rect.width / 2
    let ry = rect.height / 2
    for i in 0..<CharacterCatMetrics.irisFiberCount {
      let theta = Double(i) * 2 * .pi / Double(CharacterCatMetrics.irisFiberCount)
      let length = 0.58 + 0.13 * sin(Double(i) * 2.4)
      path.move(x + cos(theta) * rx * 0.89, y + sin(theta) * ry * 0.89)
      path.quad(
        x + cos(theta + 0.04) * rx * 0.73, y + sin(theta + 0.04) * ry * 0.73,
        x + cos(theta + 0.07) * rx * length, y + sin(theta + 0.07) * ry * length)
    }
    add(
      id + ".iris.fibers", path, stroke: color, width: rect.width * 0.017,
      opacity: opacity * 0.15, local: local, clips: clips)
  }
}

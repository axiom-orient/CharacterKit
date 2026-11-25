// Usage: swift Artwork/FullBodyCat/prepare_assets.swift SOURCE_JPG OUTPUT_DIRECTORY
// Requires macOS 14 or later. The runtime receives only the finished PNG files.
import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import Vision

private let size = 256
private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

private struct Pixel {
  var r: Double
  var g: Double
  var b: Double
  var alpha: Double = 1

  var luma: Double { (2 * r + 3 * g + b) / 6 }
}

private struct FacePatch {
  let bounds: CGRect

  init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
    bounds = CGRect(x: x, y: y, width: width, height: height)
  }

  init(bounds: CGRect) { self.bounds = bounds }
}

private struct Pose {
  let name: String
  let crop: CGRect
  let centerX: Double
  let groundY: Double
  let scale: Double
  let scaleY: Double
  let face: [FacePatch]

  init(_ name: String, _ x: Int, _ y: Int, _ width: Int, _ height: Int,
       centerX: Double, groundY: Double, scale: Double = 1, scaleY: Double? = nil,
       face: [FacePatch] = []) {
    self.name = name
    crop = CGRect(x: x, y: y, width: width, height: height)
    self.centerX = centerX
    self.groundY = groundY
    self.scale = scale
    self.scaleY = scaleY ?? scale
    self.face = face
  }

  var stageRect: CGRect {
    CGRect(x: 128 + (crop.minX - centerX) * scale,
           y: 224 + (crop.minY - groundY) * scaleY,
           width: crop.width * scale, height: crop.height * scaleY)
  }

  func registeredPoint(x: Double, y: Double) -> CGPoint {
    CGPoint(x: 128 + (x - centerX) * scale, y: 224 + (y - groundY) * scaleY)
  }

  func sourcePoint(for stage: CGPoint) -> CGPoint {
    CGPoint(x: centerX + (stage.x - 128) / scale, y: groundY + (stage.y - 224) / scaleY)
  }
}

private let poses: [Pose] = [
  .init("stand", 860, 243, 241, 162, centerX: 985, groundY: 396, face: [
    .init(912, 304, 17, 21), .init(945, 303, 17, 22), .init(922, 317, 26, 25),
  ]),
  .init("wave", 859, 436, 243, 160, centerX: 979, groundY: 591, face: [
    .init(924, 482, 16, 21), .init(958, 482, 16, 21), .init(936, 494, 26, 24),
  ]),
  .init("loaf", 1130, 242, 243, 160, centerX: 1250, groundY: 395, face: [
    .init(1190, 330, 19, 24), .init(1230, 330, 19, 24), .init(1205, 344, 28, 30),
  ]),
  .init("left", 426, 33, 387, 229, centerX: 614, groundY: 255, scale: 0.7, face: [
    .init(462, 117, 17, 27),
  ]),
  .init("right", 428, 306, 382, 230, centerX: 619, groundY: 525, scale: 0.7, face: [
    .init(748, 389, 17, 25),
  ]),
  .init("rear", 104, 297, 235, 240, centerX: 218, groundY: 528, scale: 0.73),
  .init("upright", 1433, 243, 190, 163, centerX: 1532, groundY: 401, face: [
    .init(1485, 277, 17, 20), .init(1519, 277, 16, 20), .init(1497, 288, 25, 24),
  ]),
  .init("puff", 1121, 433, 239, 163, centerX: 1244, groundY: 589, face: [
    .init(1153, 502, 15, 20),
  ]),
  .init("belly", 1391, 463, 260, 137, centerX: 1522, groundY: 589, scale: 0.92, face: [
    .init(1450, 511, 21, 17), .init(1450, 551, 21, 18), .init(1462, 526, 26, 27),
  ]),
  .init("stretch", 237, 665, 289, 217, centerX: 383, groundY: 875, scale: 0.82, face: [
    .init(288, 754, 17, 24), .init(323, 756, 20, 24), .init(300, 770, 25, 29),
  ]),
]

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

private func decode(_ image: CGImage, preservingAlpha: Bool = false) -> [Pixel] {
  guard let context = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
    bytesPerRow: image.width * 4, space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
    let buffer = context.data?.assumingMemoryBound(to: UInt8.self)
  else { fail("Cannot read source pixels.") }

  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return (0..<(image.width * image.height)).map { index in
    let offset = index * 4
    if preservingAlpha {
      let alpha = Double(buffer[offset + 3]) / 255
      guard alpha > 0 else { return Pixel(r: 0, g: 0, b: 0, alpha: 0) }
      return Pixel(
        r: Double(buffer[offset]) / alpha, g: Double(buffer[offset + 1]) / alpha,
        b: Double(buffer[offset + 2]) / alpha, alpha: alpha)
    }
    return Pixel(r: Double(buffer[offset]), g: Double(buffer[offset + 1]), b: Double(buffer[offset + 2]))
  }
}

private func foregroundConfidence(_ image: CGImage) throws -> [Float] {
  let request = VNGenerateForegroundInstanceMaskRequest()
  let handler = VNImageRequestHandler(cgImage: image)
  try handler.perform([request])
  guard let result = request.results?.first, !result.allInstances.isEmpty else {
    fail("Vision did not find a foreground object.")
  }
  let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
  CVPixelBufferLockBaseAddress(mask, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
  guard let address = CVPixelBufferGetBaseAddress(mask),
    CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float
  else { fail("Unexpected Vision matte format.") }
  let stride = CVPixelBufferGetBytesPerRow(mask)
  return (0..<image.height).flatMap { y in
    let row = address.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
    return Array(UnsafeBufferPointer(start: row, count: image.width))
  }
}

private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

private struct Raster {
  let width: Int
  let height: Int
  var pixels: [Pixel]

  func indices(near index: Int, radius: Int) -> [Int] {
    let x = index % width
    let y = index / width
    return (max(0, y - radius)...min(height - 1, y + radius)).flatMap { row in
      (max(0, x - radius)...min(width - 1, x + radius)).map { row * width + $0 }
    }
  }

  func distanceSquared(_ a: Int, _ b: Int) -> Int {
    let dx = a % width - b % width
    let dy = a / width - b / width
    return dx * dx + dy * dy
  }

  func nearbyFurColor(_ index: Int, original: [Pixel], interior: [Bool]) -> Pixel? {
    let samples = indices(near: index, radius: 5)
      .filter { interior[$0] && original[$0].luma < 122 }
      .sorted { distanceSquared(index, $0) < distanceSquared(index, $1) }
      .prefix(8)
    guard !samples.isEmpty else { return nil }
    var total = 0.0
    var color = Pixel(r: 0, g: 0, b: 0)
    for sample in samples {
      let weight = 1 / Double(distanceSquared(index, sample) + 2)
      color.r += original[sample].r * weight
      color.g += original[sample].g * weight
      color.b += original[sample].b * weight
      total += weight
    }
    return Pixel(r: color.r / total, g: color.g / total, b: color.b / total)
  }

  mutating func cutOut(confidence: [Float], pose: Pose) {
    // Vision identifies the subject. The image contrast supplies the precise
    // contour, including holes between legs and narrow edges on the ears.
    let original = pixels
    let features = pixels.indices.map { index in
      let x = Double(index % width) + pose.crop.minX
      let y = Double(index / width) + pose.crop.minY
      return pose.face.contains { $0.bounds.contains(CGPoint(x: x, y: y)) }
    }
    let region = pixels.indices.map { index in
      features[index] || (confidence[index] > 0.19 && original[index].luma < 132)
    }
    let solid = pixels.indices.map { index in
      features[index] || (region[index] && indices(near: index, radius: 1).allSatisfy { region[$0] })
    }
    let interior = pixels.indices.map { index in
      solid[index] && indices(near: index, radius: 1).allSatisfy { solid[$0] }
    }

    for index in pixels.indices {
      // Keep the decoded source colours of the opaque felt interior.
      if interior[index] || features[index] { continue }
      let pixel = original[index]
      guard solid[index] || (confidence[index] > 0.025 && pixel.luma < 228) else {
        pixels[index].alpha = 0
        continue
      }
      let nearby = indices(near: index, radius: 3)
      guard let foreground = nearbyFurColor(index, original: original, interior: interior)
        ?? nearbyFurColor(index, original: original, interior: solid)
      else {
        pixels[index].alpha = 0
        continue
      }
      let lightNeighbors = nearby.filter { original[$0].luma > 218 }
      let backdrop = lightNeighbors.isEmpty ? 243.0 :
        lightNeighbors.reduce(0) { $0 + original[$1].luma } / Double(lightNeighbors.count)
      let matte = (backdrop - pixel.luma) / max(backdrop - foreground.luma, 1)
      let alpha = solid[index] ? 1 : clamp((matte - 0.14) / 0.78)
      // The original RGB in this transition still contains the paper and floor
      // shadow. Refine the alpha against that paper but carry local felt colour.
      let texture = solid[index] && abs(pixel.luma - foreground.luma) < 13 ? 0.55 : 0
      pixels[index] = Pixel(
        r: foreground.r + (pixel.r - foreground.r) * texture,
        g: foreground.g + (pixel.g - foreground.g) * texture,
        b: foreground.b + (pixel.b - foreground.b) * texture,
        alpha: alpha >= 0.035 ? alpha : 0)
    }
    repairCutoutHoles(original: original)
  }

  mutating func normalizeTransparentMaster() {
    let matte = pixels.map(\.alpha)
    for index in pixels.indices where matte[index] >= 0.97 {
      if indices(near: index, radius: 2).allSatisfy({ matte[$0] >= 0.97 }) {
        pixels[index].alpha = 1
      }
    }
    let original = pixels
    let interior = original.map { $0.alpha == 1 }
    for index in pixels.indices where matte[index] < 0.97 {
      let alpha = matte[index]
      if alpha < 0.035 {
        pixels[index].alpha = 0
      } else if var wool = nearbyFurColor(index, original: original, interior: interior) {
        wool.alpha = alpha
        pixels[index] = wool
      }
    }
  }

  mutating func trimMasterFaceEdge(_ edge: MasterFaceEdge, in pose: Pose) {
    let original = pixels
    let wool = original.map { $0.alpha >= 0.97 && $0.luma < 98 }
    let firstY = edge.xAtY[0][0]
    let lastY = edge.xAtY[edge.xAtY.count - 1][0]
    for index in pixels.indices where original[index].alpha > 0 {
      let y = Double(index / width) + pose.crop.minY
      guard (firstY...lastY).contains(y) else { continue }
      let x = Double(index % width) + pose.crop.minX
      let boundary = coordinate(at: y, along: edge.xAtY)
      let inward = edge.keepLargerX ? x - boundary : boundary - x
      let alpha = min(original[index].alpha, clamp(inward / 2 + 0.5))
      if inward < 13 && original[index].luma >= 88,
        var color = nearbyFurColor(index, original: original, interior: wool)
      {
        color.alpha = alpha
        pixels[index] = color
      } else {
        pixels[index].alpha = alpha
      }
    }
  }

  private mutating func repairCutoutHoles(original: [Pixel]) {
    // Close only enclosed, dark, tiny holes. Bright, open gaps between
    // the feet and beneath the neck remain part of the silhouette.
    var visited = Set<Int>()
    let matte = pixels.map(\.alpha)
    for index in pixels.indices where matte[index] < 0.98 && !visited.contains(index) {
      var component = [index]
      visited.insert(index)
      var cursor = 0
      var touchesBorder = false
      while cursor < component.count {
        let current = component[cursor]
        let x = current % width
        let y = current / width
        if x == 0 || x == width - 1 || y == 0 || y == height - 1 {
          touchesBorder = true
        }
        var neighbors: [Int] = []
        if x > 0 { neighbors.append(current - 1) }
        if x < width - 1 { neighbors.append(current + 1) }
        if y > 0 { neighbors.append(current - width) }
        if y < height - 1 { neighbors.append(current + width) }
        for neighbor in neighbors where matte[neighbor] < 0.98 {
          if visited.insert(neighbor).inserted { component.append(neighbor) }
        }
        cursor += 1
      }
      if !touchesBorder && component.count <= 24 && component.allSatisfy({ original[$0].luma < 132 }) {
        for member in component {
          pixels[member] = original[member]
        }
      }
    }
  }

  private func partAlpha(_ alpha: Double, coverage: Double, over: Double) -> Double {
    guard alpha < 1 else { return coverage }
    // Two masks retain their opaque common root. Their shared antialias
    // pixels contribute just one silhouette's worth of opacity at rest.
    let remaining = (alpha - over) / (1 - over)
    return min(alpha * coverage, max(0, remaining))
  }

  mutating func removeFaceInk(in pose: Pose, passes: Int = 150, highResolution: Bool = false) {
    // Solve toward the dark surrounding wool separately in RGB. The masks
    // cover the original features and their local shadows, within the matte.
    let original = pixels
    let facePixels = pixels.indices.filter { index in
      let point = CGPoint(x: Double(index % width) + pose.crop.minX,
                          y: Double(index / width) + pose.crop.minY)
      return pixels[index].alpha > 0.97 && pose.face.contains { $0.bounds.contains(point) }
    }
    let masked: [Int]
    if highResolution {
      // The ivory features are distinct from the charcoal face. Retouch their
      // immediate contours and leave the larger registered fur patches intact.
      let feather = max(2, Int(ceil(0.78 / pose.scale)))
      var cream = [Bool](repeating: false, count: pixels.count)
      for index in facePixels where original[index].luma >= 92 { cream[index] = true }
      masked = facePixels.filter { index in
        indices(near: index, radius: feather).contains { cream[$0] }
      }
    } else {
      masked = facePixels
    }
    let maskedSet = Set(masked)
    guard !masked.isEmpty else { return }

    let surroundings = masked.flatMap { indices(near: $0, radius: 1) }
      .filter { !maskedSet.contains($0) && original[$0].alpha > 0.97 && original[$0].luma < 115 }
    guard !surroundings.isEmpty else { fail("No viable texture around the face in \(pose.name).") }
    let reference = surroundings.sorted { original[$0].luma < original[$1].luma }
    let initial = original[reference[reference.count / 2]]
    for index in masked {
      pixels[index] = initial
    }

    for _ in 0..<passes {
      for index in masked {
        let neighbors = [index - 1, index + 1, index - width, index + width].filter {
          pixels.indices.contains($0) && original[$0].alpha > 0.97
        }
        let valid = neighbors.filter { maskedSet.contains($0) || original[$0].luma < 115 }
        guard !valid.isEmpty else { continue }
        let divisor = Double(valid.count)
        let sums = valid.reduce((0.0, 0.0, 0.0)) { sum, other in
          (sum.0 + pixels[other].r, sum.1 + pixels[other].g, sum.2 + pixels[other].b)
        }
        pixels[index] = Pixel(r: sums.0 / divisor, g: sums.1 / divisor, b: sums.2 / divisor)
      }
    }

    let textureOffsets = [(0, -30), (11, -28), (-11, -28), (18, -16), (-18, -16),
                          (14, 13), (-14, 13), (0, 28)]
    let offsets = textureOffsets.map {
      (Int((Double($0.0) / pose.scale).rounded()), Int((Double($0.1) / pose.scaleY).rounded()))
    }
    for index in masked {
      if highResolution {
        let x = index % width
        let y = index / width
        let donor = offsets.first { dx, dy in
          let xx = x + dx
          let yy = y + dy
          guard (2..<(width - 2)).contains(xx), (2..<(height - 2)).contains(yy) else { return false }
          let center = yy * width + xx
          return indices(near: center, radius: 2).allSatisfy {
            !maskedSet.contains($0) && original[$0].alpha > 0.97 && original[$0].luma < 92
          }
        }
        if let (dx, dy) = donor {
          let center = (y + dy) * width + x + dx
          let ring = indices(near: center, radius: 2)
          let mean = ring.reduce(0.0) { $0 + original[$1].luma } / Double(ring.count)
          let detail = (original[center].luma - mean) * 0.94
          pixels[index].r += detail
          pixels[index].g += detail
          pixels[index].b += detail
          continue
        }
      }
      // Modest texture from the nearby unaffected wool, without reusing the
      // facial shapes or introducing random values between runs.
      let nearby = reference[(index * 29 + index / width * 17) % reference.count]
      let ring = indices(near: nearby, radius: 1).filter {
        !maskedSet.contains($0) && original[$0].alpha > 0.97 && original[$0].luma < 115
      }
      guard !ring.isEmpty else { continue }
      let mean = ring.reduce(0.0) { $0 + original[$1].luma } / Double(ring.count)
      let detail = (original[nearby].luma - mean) * 0.48
      pixels[index].r += detail
      pixels[index].g += detail
      pixels[index].b += detail
    }
  }

  func splitAppendage(of pose: Pose, registeredLike reference: Pose? = nil, rumpContour: [[Double]]? = nil)
    -> (body: Raster, part: Raster, suffix: String)?
  {
    guard pose.name == "stand" || pose.name == "wave" else { return nil }
    var body = self
    var part = self
    for index in pixels.indices {
      let rawX = Double(index % width) + pose.crop.minX
      let rawY = Double(index / width) + pose.crop.minY
      let stage = pose.registeredPoint(x: rawX, y: rawY)
      let original = reference?.sourcePoint(for: stage)
      let x = original.map { Double($0.x) } ?? rawX
      let y = original.map { Double($0.y) } ?? rawY
      if pose.name == "stand" {
        let dx = x - 1003
        let contour = 318 + dx * 0.10 + dx * dx * 0.013
        let tailLeft = 1014 + max(0, y - 319) * 0.22
        let tailCoverage = clamp(min(x - tailLeft, contour + 14 - y) + 0.5)
        let referenceBodyAlpha = pixels[index].alpha * (1 - clamp(min(x - 1022, contour - y) + 0.5))
        if let rumpContour {
          // Keep the near-side wool on the body and preserve the tail's
          // existing hidden overlap for rotation.
          let back = coordinate(at: stage.x, along: rumpContour)
          let aboveBack = min(stage.x - rumpContour[0][0], back - stage.y)
          body.pixels[index].alpha *= 1 - clamp(aboveBack / pose.scaleY + 0.5)
        } else {
          body.pixels[index].alpha = referenceBodyAlpha
        }
        part.pixels[index].alpha = partAlpha(pixels[index].alpha, coverage: tailCoverage, over: referenceBodyAlpha)
      } else {
        // The upper lip of the paw belongs to the moving layer where it
        // extends past the cheek. Keep the original junction further in.
        let upperLip = 2.7 * clamp((923 - x) / 14)
        let top = 516 + max(0, x - 908) * 0.66 - upperLip
        let bottom = 558 + max(0, x - 922) * 0.25
        let wrist = 935 + (y - 539) * 0.10
        let depth = clamp((y - 516) / 41)
        let chest = 912 + 17 * (1 - pow(1 - depth, 3))
        let footprint = min(y - top, bottom - y, chest - x)
        let pawCoverage = clamp(min(y - top, bottom - y, wrist + 10 - x) + 0.5)
        body.pixels[index].alpha *= 1 - clamp(footprint + 0.5)
        part.pixels[index].alpha = partAlpha(
          pixels[index].alpha, coverage: pawCoverage, over: body.pixels[index].alpha)
      }
    }
    return (body, part, pose.name == "stand" ? "tail" : "paw")
  }

  func splitMasterPaw(_ cut: MasterPawCut, in pose: Pose)
    -> (body: Raster, part: Raster, suffix: String)
  {
    var body = self
    var paw = self
    for index in pixels.indices {
      let alpha = pixels[index].alpha
      guard alpha > 0 else { continue }
      let x = Double(index % width) + pose.crop.minX
      let y = Double(index / width) + pose.crop.minY
      let top = coordinate(at: x, along: cut.top)
      let chest = coordinate(at: y, along: cut.chest)
      let inPaw = min(y - top, cut.bottomY - y)
      let underBody = min(inPaw, chest - x)
      let reach = clamp(min(inPaw, cut.overlapRightX - x) / 2 + 0.5)
      body.pixels[index].alpha *= 1 - clamp(underBody / 2 + 0.5)
      paw.pixels[index].alpha = partAlpha(alpha, coverage: reach, over: body.pixels[index].alpha)
    }
    return (body, paw, "paw")
  }

  func splitWalkingProfile(of pose: Pose) -> [(String, Raster)] {
    precondition(pose.name == "left")
    var torso = self
    var nearFront = self
    var farFront = self
    var nearHind = self
    var farHind = self

    for index in pixels.indices {
      let x = Double(index % width) + pose.crop.minX
      let y = Double(index / width) + pose.crop.minY

      // The belly and chest overlap the original leg pixels by 14 points.
      // All four moving pieces are painted under this fixed torso.
      let frontEdge = 214 + (x - 516) * 0.29
      let frontArea = min(575 - x, y - frontEdge)
      let hindEdge = 226 - 0.005 * pow(x - 650, 2)
      let hindArea = min(x - 648, y - hindEdge)
      torso.pixels[index].alpha *= 1 - clamp(max(frontArea, hindArea) + 0.5)

      let frontRoot = min(575.5 - x, y - frontEdge + 14)
      let frontSeam = 522 - (y - 225) * 0.53
      let farFrontToe = 249 - 0.014 * pow(x - 506, 2)
      let nearFrontCoverage = clamp(min(frontRoot, x - frontSeam) + 0.5)
      let farFrontCoverage = clamp(min(frontRoot, frontSeam + 5 - x, farFrontToe - y) + 0.5)
      nearFront.pixels[index].alpha = partAlpha(
        pixels[index].alpha, coverage: nearFrontCoverage, over: torso.pixels[index].alpha)
      let frontOverlap = torso.pixels[index].alpha + nearFront.pixels[index].alpha *
        (1 - torso.pixels[index].alpha)
      farFront.pixels[index].alpha = partAlpha(
        pixels[index].alpha, coverage: farFrontCoverage, over: frontOverlap)

      let hindRoot = min(x - 647.5, y - hindEdge + 14)
      let hindSeam = 689 - (y - 235) * 0.22
      let farHindToe = 249.5 - 0.012 * pow(x - 675, 2)
      let nearHindCoverage = clamp(min(hindRoot, x - hindSeam) + 0.5)
      let farHindCoverage = clamp(min(hindRoot, hindSeam + 5 - x, farHindToe - y) + 0.5)
      nearHind.pixels[index].alpha = partAlpha(
        pixels[index].alpha, coverage: nearHindCoverage, over: torso.pixels[index].alpha)
      let hindOverlap = torso.pixels[index].alpha + nearHind.pixels[index].alpha *
        (1 - torso.pixels[index].alpha)
      farHind.pixels[index].alpha = partAlpha(
        pixels[index].alpha, coverage: farHindCoverage, over: hindOverlap)
    }

    return [("body", torso), ("near-front", nearFront), ("far-front", farFront),
            ("near-hind", nearHind), ("far-hind", farHind)]
  }

  func registered(to pose: Pose, mirror: Bool = false, pixelsPerPoint: Int = 1) -> CGImage {
    let bytes = pixels.flatMap { pixel -> [UInt8] in
      let alpha = pixel.alpha
      return [pixel.r * alpha, pixel.g * alpha, pixel.b * alpha, alpha * 255].map {
        UInt8(clamping: Int($0.rounded()))
      }
    }
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
      | CGBitmapInfo.byteOrder32Big.rawValue)
    let outputSide = size * pixelsPerPoint
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let raster = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: sRGB, bitmapInfo: info, provider: provider, decode: nil,
        shouldInterpolate: true, intent: .defaultIntent),
      let context = CGContext(
        data: nil, width: outputSide, height: outputSide, bitsPerComponent: 8, bytesPerRow: outputSide * 4,
        space: sRGB, bitmapInfo: info.rawValue)
    else { fail("Cannot register \(pose.name).") }

    let density = Double(pixelsPerPoint)
    let rect = pose.stageRect.applying(.init(scaleX: density, y: density))
    context.interpolationQuality =
      pose.scale * density == 1 && pose.scaleY * density == 1 ? .none : .low
    if mirror {
      context.translateBy(x: Double(outputSide), y: 0)
      context.scaleBy(x: -1, y: 1)
    }
    context.draw(raster, in: CGRect(x: rect.minX, y: Double(outputSide) - rect.maxY,
      width: rect.width, height: rect.height))
    guard let result = context.makeImage() else { fail("Cannot draw \(pose.name).") }
    return result
  }
}

private func write(_ image: CGImage, named name: String, to output: URL) throws {
  try writePNG(image, to: output.appendingPathComponent("full-body-cat-" + name + ".png"))
}

private func writePNG(_ image: CGImage, to path: URL) throws {
  let data = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
  else { fail("Cannot create PNG encoder.") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("Cannot encode \(path.lastPathComponent).") }
  try (data as Data).write(to: path, options: .atomic)
  print("Wrote \(path.lastPathComponent)")
}

private struct MasterPawCut: Decodable {
  let top: [[Double]]
  let chest: [[Double]]
  let overlapRightX: Double
  let bottomY: Double

  var valid: Bool {
    [top, chest].allSatisfy(isOrderedCurve)
  }
}

private struct MasterFaceEdge: Decodable {
  let xAtY: [[Double]]
  let keepLargerX: Bool
}

private func isOrderedCurve(_ samples: [[Double]]) -> Bool {
  samples.count >= 2 && samples.allSatisfy { $0.count == 2 }
    && zip(samples, samples.dropFirst()).allSatisfy { a, b in a[0] < b[0] }
}

private func coordinate(at input: Double, along samples: [[Double]]) -> Double {
  let first = samples[0]
  if input <= first[0] { return first[1] }
  for (a, b) in zip(samples, samples.dropFirst()) where input <= b[0] {
    return a[1] + (b[1] - a[1]) * (input - a[0]) / (b[0] - a[0])
  }
  return samples[samples.count - 1][1]
}

private struct HeroCalibration: Decodable {
  struct Placement: Decodable {
    let sourceAnchor: [Double]
    let stageAnchor: [Double]
    let scaleX: Double
    let scaleY: Double
  }

  let pose: String
  let sourceSHA256: String
  let sourceCrop: [Int]
  let eyes: [[Double]]?
  let groundY: Double
  let joint: [Double]?
  let pixelsPerPoint: Int
  let removeBakedFace: Bool?
  let preserveReferenceSilhouette: Bool?
  let alignGround: Bool?
  let pawCut: MasterPawCut?
  let rumpContour: [[Double]]?
  let placement: Placement?
  let sourceFacePatches: [[Double]]?
  let sourceFaceEdge: MasterFaceEdge?
  let stageWarp: MasterStageWarp?
}

private struct HeroReferenceManifest: Decodable {
  struct Registration: Decodable {
    struct Eye: Decodable { let center: [Double] }
    struct Appendage: Decodable { let pivot: [Double] }

    let eyes: [Eye]
    let appendage: Appendage?
  }

  let poses: [String: Registration]
}

private struct HeroBounds: Encodable {
  let minX: Int
  let minY: Int
  let maxX: Int
  let maxY: Int
}

private struct HeroReport: Encodable {
  let pose: String
  let sourcePixelSize: [Int]
  let outputPixelSize: [Int]
  let renderPixelsPerInputPixel: Double
  let verticalScaleRelativeToHorizontal: Double
  let sourceHadTransparency: Bool
  let referenceBounds: HeroBounds
  let candidateBounds: HeroBounds
  let candidateSilhouetteIoU: Double
  let outputSilhouetteIoU: Double
  let registeredEyes: [[Double]]?
  let groundOffsetPoints: Double
  let jointOffsetPoints: Double?
  let preservesReferenceSilhouette: Bool
  let transferredPixels: Int
  let totalOpaqueOutputPixels: Int
}

private func loadImage(_ url: URL) -> CGImage {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { fail("Cannot decode \(url.lastPathComponent).") }
  return image
}

private func heroContext(width: Int, height: Int) -> CGContext {
  guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
  else { fail("Cannot create hero preview context.") }
  return context
}

private func composed(_ layers: [CGImage], side: Int) -> CGImage {
  let preview = heroContext(width: side, height: side)
  preview.interpolationQuality = .low
  let area = CGRect(x: 0, y: 0, width: side, height: side)
  for layer in layers { preview.draw(layer, in: area) }
  guard let image = preview.makeImage() else { fail("Cannot compose hero layers.") }
  return image
}

private func finishStandingTail(_ image: CGImage, density: Int, rumpContour: [[Double]]) -> CGImage {
  let side = size * density
  let d = Double(density)
  let outline = CGMutablePath()
  outline.move(to: CGPoint(x: 0, y: 0))
  outline.addLines(between: [CGPoint(x: 256, y: 0), CGPoint(x: 256, y: 148), CGPoint(x: 188, y: 148)])
  outline.addCurve(to: .init(x: 176, y: 158),
    control1: .init(x: 182, y: 152), control2: .init(x: 178, y: 155.9))
  outline.addCurve(to: .init(x: 161.5, y: 161.5),
    control1: .init(x: 171, y: 162.5), control2: .init(x: 165, y: 165))
  outline.addCurve(to: .init(x: 159.2, y: 150.6),
    control1: .init(x: 159.7, y: 159.4), control2: .init(x: 159.7, y: 154.1))
  outline.addCurve(to: .init(x: 162, y: 141.8),
    control1: .init(x: 158.6, y: 145.75), control2: .init(x: 159.9, y: 145.1))
  outline.addCurve(to: .init(x: 166.5, y: 132),
    control1: .init(x: 162.5, y: 139.5), control2: .init(x: 165, y: 135))
  outline.addLine(to: CGPoint(x: 0, y: 132))
  outline.closeSubpath()

  let context = heroContext(width: side, height: side)
  var placement = CGAffineTransform(a: d, b: 0, c: 0, d: -d, tx: 0, ty: Double(side))
  guard let path = outline.copy(using: &placement) else { fail("Cannot position the standing tail contour.") }
  context.addPath(path)
  context.clip()
  context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
  guard let clipped = context.makeImage() else { fail("Cannot finish the standing tail contour.") }

  let original = decode(clipped, preservingAlpha: true)
  let wool: [ClosedRange<Int>?] = (0..<side).map { y in
    let row = original[(y * side)..<((y + 1) * side)]
    guard let first = row.firstIndex(where: { $0.alpha >= 0.97 }),
      let last = row.lastIndex(where: { $0.alpha >= 0.97 }) else { return nil }
    return (first - y * side)...(last - y * side)
  }
  var finished = original
  func ease(_ unit: Double) -> Double {
    let t = clamp(unit)
    return t * t * (3 - 2 * t)
  }
  func blendColor(_ first: Pixel, _ second: Pixel, _ amount: Double) -> Pixel {
    Pixel(r: first.r + (second.r - first.r) * amount,
          g: first.g + (second.g - first.g) * amount,
          b: first.b + (second.b - first.b) * amount, alpha: first.alpha)
  }
  for y in 0..<side {
    guard let row = wool[y] else { continue }
    let stageY = (Double(y) + 0.5) / d
    let donorY = max(0, y - 15 * density)
    for x in max(0, row.lowerBound - 4)...min(side - 1, row.upperBound + 4) {
      let index = y * side + x
      let pixel = original[index]
      guard pixel.alpha > 0 else { continue }
      let stageX = (Double(x) + 0.5) / d
      let across = clamp(Double(x - row.lowerBound) / Double(max(1, row.upperBound - row.lowerBound)))
      let back = coordinate(at: stageX, along: rumpContour)
      let underlap = ease((stageY - back + 3.5) / 4)
      var felt = pixel
      if underlap > 0, let donor = wool[donorY] {
        // The hidden rump imprint needs the same dye and fibres as the tail.
        let donorX = Int((Double(donor.lowerBound) + Double(donor.upperBound - donor.lowerBound)
          * (0.20 + 0.64 * across)).rounded())
        felt = blendColor(felt, original[donorY * side + donorX], underlap)
      }
      if pixel.alpha < 0.97 && row.count > 4 {
        let inset = min(3, row.count / 4)
        let inner = min(row.upperBound - inset, max(row.lowerBound + inset, x))
        var edgeWool = original[y * side + inner]
        if underlap > 0 { edgeWool = blendColor(edgeWool, felt, underlap) }
        felt = blendColor(felt, edgeWool, 0.65 * ease((0.97 - pixel.alpha) / 0.62))
      }
      let cap = 1 - ease((stageY - 83) / 17)
      let roundedLight = sin(.pi * across) * 3.8 * ease(1 - abs(across - 0.35) / 0.56)
      let shadowSide = 1.7 * ease((across - 0.56) / 0.44)
      let luma = felt.luma
      let light = luma + roundedLight - shadowSide - 3.1 * underlap - max(0, luma - 45) * (0.13 + 0.12 * cap)
      finished[index] = Pixel(r: light + 0.94 * (felt.r - luma),
        g: light + 0.94 * (felt.g - luma), b: light + 0.94 * (felt.b - luma), alpha: pixel.alpha)
    }
  }
  let stage = Pose("finished standing tail", 0, 0, side, side, centerX: Double(side) / 2,
                   groundY: Double(224 * density), scale: 1 / d)
  return Raster(width: side, height: side, pixels: finished).registered(to: stage, pixelsPerPoint: density)
}

private func silhouette(_ layers: [CGImage]) -> (mask: [Bool], bounds: HeroBounds) {
  let image = composed(layers, side: size)
  let mask = decode(image, preservingAlpha: true).map { $0.alpha >= 0.5 }
  let visible = mask.indices.filter { mask[$0] }
  guard let minX = visible.map({ $0 % size }).min(),
    let maxX = visible.map({ $0 % size }).max(),
    let first = visible.first, let last = visible.last
  else { fail("No visible hero silhouette.") }
  return (mask, .init(minX: minX, minY: first / size, maxX: maxX, maxY: last / size))
}

private func overlap(_ first: [Bool], _ second: [Bool]) -> Double {
  var intersection = 0
  var union = 0
  for i in first.indices {
    if first[i] || second[i] { union += 1 }
    if first[i] && second[i] { intersection += 1 }
  }
  return Double(intersection) / Double(max(1, union))
}

private struct MasterStageWarp: Decodable {
  let x: [[Double]]?
  let y: [[Double]]?

  var valid: Bool {
    [x, y].compactMap { $0 }.allSatisfy { axis in
      guard isOrderedCurve(axis), axis.first == [0, 0], axis.last == [256, 256] else { return false }
      return zip(axis, axis.dropFirst()).allSatisfy { first, last in first[1] < last[1] }
    }
  }

  func stagePoint(_ value: CGPoint) -> [Double] {
    [
      x.map { coordinate(at: value.x, along: $0) } ?? Double(value.x),
      y.map { coordinate(at: value.y, along: $0) } ?? Double(value.y),
    ]
  }

  func apply(_ image: CGImage, density: Int) -> CGImage {
    guard x != nil || y != nil else { return image }
    let side = size * density
    let d = Double(density)
    let original = decode(image, preservingAlpha: true)
    let inverseX = x?.map { [$0[1], $0[0]] }
    let inverseY = y?.map { [$0[1], $0[0]] }
    func samples(_ curve: [[Double]]?) -> [(Int, Int, Double)] {
      (0..<side).map { index in
        guard let curve else { return (index, index, 0) }
        let mapped = coordinate(at: (Double(index) + 0.5) / d, along: curve) * d - 0.5
        let px = min(Double(side - 1), max(0, mapped))
        let initial = Int(px)
        return (initial, min(initial + 1, side - 1), px - Double(initial))
      }
    }
    let horizontal = samples(inverseX)
    let vertical = samples(inverseY)
    var pixels: [Pixel] = []
    pixels.reserveCapacity(side * side)
    let clear = Pixel(r: 0, g: 0, b: 0, alpha: 0)
    for (top, bottom, verticalFraction) in vertical {
      for (left, right, horizontalFraction) in horizontal {
        let candidates = [
          (top * side + left, (1 - horizontalFraction) * (1 - verticalFraction)),
          (top * side + right, horizontalFraction * (1 - verticalFraction)),
          (bottom * side + left, (1 - horizontalFraction) * verticalFraction),
          (bottom * side + right, horizontalFraction * verticalFraction),
        ]
        var color = clear
        for (index, weight) in candidates where weight > 0 {
          let pixel = original[index]
          let coverage = pixel.alpha * weight
          color.alpha += coverage
          color.r += coverage * pixel.r
          color.g += coverage * pixel.g
          color.b += coverage * pixel.b
        }
        if color.alpha > 0 {
          color.r /= color.alpha
          color.g /= color.alpha
          color.b /= color.alpha
        }
        pixels.append(color)
      }
    }
    let stage = Pose("shape-aligned master", 0, 0, side, side, centerX: Double(side) / 2,
                     groundY: Double(224 * density), scale: 1 / d)
    return Raster(width: side, height: side, pixels: pixels)
      .registered(to: stage, pixelsPerPoint: density)
  }
}

private func feltDetail(from image: CGImage) -> [Double] {
  let pixels = decode(image, preservingAlpha: true)
  let width = image.width
  let luma = pixels.map(\.luma)
  let inward = [0, -2, 2, -2 * width, 2 * width,
                 -2 * width - 2, -2 * width + 2, 2 * width - 2, 2 * width + 2]
  var detail = [Double](repeating: 0, count: pixels.count)
  for y in 2..<(image.height - 2) {
    for x in 2..<(width - 2) {
      let index = y * width + x
      guard inward.allSatisfy({ pixels[index + $0].alpha >= 0.995 }) else { continue }
      let mean = inward.reduce(0.0) { $0 + luma[index + $1] } / Double(inward.count)
      // Keep thin wool fibres without transferring a generated shape or tonal edge.
      detail[index] = min(15, max(-15, (luma[index] - mean) * 0.92))
    }
  }
  return detail
}

private func addingDetail(_ detail: [Double], to layer: CGImage, density: Int)
  -> (image: CGImage, count: Int)
{
  let outputSide = size * density
  let base = composed([layer], side: outputSide)
  var raster = Raster(width: outputSide, height: outputSide, pixels: decode(base, preservingAlpha: true))
  var count = 0
  for index in detail.indices where raster.pixels[index].alpha >= 0.995 && abs(detail[index]) > 0.1 {
    raster.pixels[index].r += detail[index]
    raster.pixels[index].g += detail[index]
    raster.pixels[index].b += detail[index]
    if abs(detail[index]) >= 1 { count += 1 }
  }
  let stage = Pose("high-resolution stage", 0, 0, outputSide, outputSide,
                   centerX: Double(outputSide) / 2, groundY: Double(224 * density),
                   scale: 1 / Double(density))
  return (raster.registered(to: stage, pixelsPerPoint: density), count)
}

private func writeHeroComparison(_ legacy: CGImage, _ candidate: CGImage, to output: URL) throws {
  let panel = 512
  let context = heroContext(width: panel * 2, height: panel * 2)
  context.interpolationQuality = .low
  for (column, image) in [legacy, candidate].enumerated() {
    for row in 0..<2 {
      let x = column * panel
      let y = row * panel
      let rect = CGRect(x: x, y: y, width: panel, height: panel)
      let gray = row == 0 ? 0.08 : 0.94
      context.setFillColor(gray: gray, alpha: 1)
      context.fill(rect)
      context.draw(image, in: rect)
    }
  }
  guard let image = context.makeImage() else { fail("Cannot draw loaded legacy and hero images.") }
  try writePNG(image, to: output.appendingPathComponent("comparison.png"))
}

private func prepareHero(_ arguments: [String]) throws {
  guard arguments.count == 6 else {
    fail("Expected --hero SOURCE_IMAGE CALIBRATION_JSON REFERENCE_PNG_DIRECTORY REVIEW_DIRECTORY.")
  }
  let input = URL(fileURLWithPath: arguments[2])
  let calibrationURL = URL(fileURLWithPath: arguments[3])
  let referenceDirectory = URL(fileURLWithPath: arguments[4], isDirectory: true)
  let output = URL(fileURLWithPath: arguments[5], isDirectory: true)
  guard referenceDirectory.standardizedFileURL.resolvingSymlinksInPath()
    != output.standardizedFileURL.resolvingSymlinksInPath()
  else { fail("Use a separate review directory for the hero candidate.") }
  let calibration = try JSONDecoder().decode(HeroCalibration.self, from: Data(contentsOf: calibrationURL))
  let manifestURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("manifest.json")
  let manifest = try JSONDecoder().decode(HeroReferenceManifest.self, from: Data(contentsOf: manifestURL))
  guard let reference = poses.first(where: { $0.name == calibration.pose }),
    let anchors = manifest.poses[calibration.pose],
    [3, 4].contains(calibration.pixelsPerPoint),
    calibration.sourceCrop.count == 4,
    calibration.eyes?.allSatisfy({ $0.count == 2 }) ?? true
  else { fail("Check the hero pose, dimensions, and source eye positions in the calibration.") }
  if let cut = calibration.pawCut, calibration.pose != "wave" || !cut.valid {
    fail("The source paw contour requires ordered coordinate pairs for the waving pose.")
  }
  if let contour = calibration.rumpContour, calibration.pose != "stand" || !isOrderedCurve(contour) {
    fail("The standing rump requires ordered [x, y] pairs on the registered stage.")
  }
  if let edge = calibration.sourceFaceEdge, !isOrderedCurve(edge.xAtY) {
    fail("The face silhouette trim requires ordered source [y, x] points.")
  }
  if let warp = calibration.stageWarp, !warp.valid {
    fail("A stage warp must give increasing source and destination coordinates from 0 to 256.")
  }
  let inputBytes = try Data(contentsOf: input)
  let hash = SHA256.hash(data: inputBytes).map { String(format: "%02x", $0) }.joined()
  guard hash == calibration.sourceSHA256 else { fail("Hero source SHA-256 does not match calibration.") }
  let full = loadImage(input)
  let cropValues = calibration.sourceCrop
  let crop = CGRect(x: cropValues[0], y: cropValues[1], width: cropValues[2], height: cropValues[3])
  guard crop.width >= 64, crop.height >= 64, crop.width * crop.height <= 3_000_000,
    CGRect(x: 0, y: 0, width: full.width, height: full.height).contains(crop),
    let image = full.cropping(to: crop)
  else { fail("Hero crop must be inside the source image and contain at most three million pixels.") }

  let density = calibration.pixelsPerPoint
  let fit = calibration.placement ?? matchHorizontalEyes(calibration, reference: anchors)
  guard fit.sourceAnchor.count == 2, fit.stageAnchor.count == 2,
    crop.contains(CGPoint(x: fit.sourceAnchor[0], y: fit.sourceAnchor[1])),
    CGRect(x: 0, y: 0, width: size, height: size).contains(CGPoint(x: fit.stageAnchor[0], y: fit.stageAnchor[1]))
  else { fail("The hero placement anchor must be inside the source crop and stage.") }
  let scale = fit.scaleX
  let verticalScale = fit.scaleY
  guard scale.isFinite && scale > 0 && scale * Double(density) <= 1.04 else {
    fail("This source has too few samples for the chosen stage density. Use a higher-resolution image or 3×.")
  }
  guard (0.86...1.14).contains(verticalScale / scale),
    verticalScale * Double(density) <= 1.04
  else { fail("The source feet and pose dimensions differ too much for a light alignment.") }
  let centerX = fit.sourceAnchor[0] + (128 - fit.stageAnchor[0]) / scale
  let groundY = fit.sourceAnchor[1] + (224 - fit.stageAnchor[1]) / verticalScale
  let registered = Pose(calibration.pose, cropValues[0], cropValues[1], cropValues[2], cropValues[3],
                        centerX: centerX, groundY: groundY, scale: scale, scaleY: verticalScale)
  let face = masterFacePatches(calibration, reference: reference, registered: registered)
  let pose = Pose(calibration.pose, cropValues[0], cropValues[1], cropValues[2], cropValues[3],
                  centerX: centerX, groundY: groundY, scale: scale, scaleY: verticalScale, face: face)

  var raster = Raster(width: image.width, height: image.height, pixels: decode(image, preservingAlpha: true))
  let transparentCount = raster.pixels.reduce(0) { $0 + ($1.alpha < 0.005 ? 1 : 0) }
  let sourceHasAlpha = transparentCount > image.width * image.height / 100
  if sourceHasAlpha {
    raster.normalizeTransparentMaster()
  } else {
    raster.cutOut(confidence: try foregroundConfidence(image), pose: pose)
  }
  let outputSide = size * density
  func register(_ raster: Raster) -> CGImage {
    let positioned = raster.registered(to: pose, pixelsPerPoint: density)
    return calibration.stageWarp?.apply(positioned, density: density) ?? positioned
  }
  let initial = register(raster)
  let passes = min(1600, max(150, Int(150 / (scale * scale))))
  raster.removeFaceInk(in: pose, passes: passes, highResolution: true)
  if let edge = calibration.sourceFaceEdge { raster.trimMasterFaceEdge(edge, in: pose) }
  let registeredRaster = register(raster)
  let split = calibration.pawCut.map { raster.splitMasterPaw($0, in: pose) }
    ?? raster.splitAppendage(of: pose, registeredLike: reference, rumpContour: calibration.rumpContour)
  let names = split.map { [pose.name, pose.name + "-" + $0.suffix] } ?? [pose.name]
  let legacy = names.map { loadImage(referenceDirectory.appendingPathComponent("full-body-cat-" + $0 + ".png")) }
  let highResolution = split.map {
    let part = register($0.part)
    let finishedPart = calibration.rumpContour.map { finishStandingTail(part, density: density, rumpContour: $0) }
    return [register($0.body), finishedPart ?? part]
  } ?? [registeredRaster]

  let preserve = calibration.preserveReferenceSilhouette ?? true
  let detail = preserve ? feltDetail(from: registeredRaster) : []
  var transferred = 0
  let result = preserve ? legacy.map { layer in
    let styled = addingDetail(detail, to: layer, density: density)
    transferred += styled.count
    return styled.image
  } : highResolution
  func painterOrder(_ images: [CGImage]) -> [CGImage] {
    pose.name == "stand" ? Array(images.reversed()) : images
  }

  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  for (name, layer) in zip(names, result) { try write(layer, named: name, to: output) }
  try writePNG(initial, to: output.appendingPathComponent("registered-source.png"))
  let referenceAlpha = silhouette(painterOrder(legacy))
  let candidateAlpha = silhouette([registeredRaster])
  let resultAlpha = silhouette(painterOrder(result))
  try writeHeroComparison(
    composed(painterOrder(legacy), side: outputSide), composed(painterOrder(result), side: outputSide), to: output)

  let jointError: Double? = calibration.joint.flatMap { source in
    guard source.count == 2, let destination = anchors.appendage?.pivot else { return nil }
    let registered = pose.registeredPoint(x: source[0], y: source[1])
    return hypot(registered.x - destination[0], registered.y - destination[1])
  }
  let report = HeroReport(
    pose: pose.name, sourcePixelSize: [image.width, image.height], outputPixelSize: [outputSide, outputSide],
    renderPixelsPerInputPixel: scale * Double(density), verticalScaleRelativeToHorizontal: verticalScale / scale,
    sourceHadTransparency: sourceHasAlpha,
    referenceBounds: referenceAlpha.bounds, candidateBounds: candidateAlpha.bounds,
    candidateSilhouetteIoU: overlap(referenceAlpha.mask, candidateAlpha.mask),
    outputSilhouetteIoU: overlap(referenceAlpha.mask, resultAlpha.mask),
    registeredEyes: calibration.eyes?.map { eye in
      let point = pose.registeredPoint(x: eye[0], y: eye[1])
      return calibration.stageWarp?.stagePoint(point) ?? [Double(point.x), Double(point.y)]
    },
    groundOffsetPoints: (calibration.groundY - groundY) * verticalScale, jointOffsetPoints: jointError,
    preservesReferenceSilhouette: preserve, transferredPixels: transferred,
    totalOpaqueOutputPixels: decode(composed(painterOrder(result), side: outputSide), preservingAlpha: true)
      .filter { $0.alpha >= 0.995 }.count)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let summary = try encoder.encode(report)
  try summary.write(to: output.appendingPathComponent("report.json"), options: .atomic)
  print(String(decoding: summary, as: UTF8.self))
}

private func matchHorizontalEyes(_ calibration: HeroCalibration, reference: HeroReferenceManifest.Registration)
  -> HeroCalibration.Placement
{
  let targetEyes = reference.eyes.map(\.center)
  guard let eyes = calibration.eyes, eyes.count == 2, targetEyes.count == 2,
    eyes[0][0] < eyes[1][0], targetEyes[0][0] < targetEyes[1][0]
  else { fail("A profile, back or rotated belly pose requires explicit source and stage placement anchors.") }
  let scale = (targetEyes[1][0] - targetEyes[0][0]) / (eyes[1][0] - eyes[0][0])
  let sourceEyeX = (eyes[0][0] + eyes[1][0]) / 2
  let sourceEyeY = (eyes[0][1] + eyes[1][1]) / 2
  let targetEyeX = (targetEyes[0][0] + targetEyes[1][0]) / 2
  let targetEyeY = (targetEyes[0][1] + targetEyes[1][1]) / 2
  let verticalScale = calibration.alignGround == true
    ? (224 - targetEyeY) / (calibration.groundY - sourceEyeY)
    : scale
  return .init(
    sourceAnchor: [sourceEyeX, sourceEyeY], stageAnchor: [targetEyeX, targetEyeY],
    scaleX: scale, scaleY: verticalScale)
}

private func masterFacePatches(_ calibration: HeroCalibration, reference: Pose, registered: Pose)
  -> [FacePatch]
{
  if calibration.removeBakedFace == false { return [] }
  if let patches = calibration.sourceFacePatches {
    return patches.map { patch in
      guard patch.count == 4 else { fail("Each source face patch needs x, y, width, and height.") }
      let bounds = CGRect(x: patch[0], y: patch[1], width: patch[2], height: patch[3])
      guard registered.crop.contains(bounds), bounds.width > 0, bounds.height > 0
      else { fail("Each source face patch must be inside the source crop.") }
      return FacePatch(bounds: bounds)
    }
  }
  return reference.face.map { patch in
    let a = registered.sourcePoint(for: reference.registeredPoint(x: patch.bounds.minX, y: patch.bounds.minY))
    let b = registered.sourcePoint(for: reference.registeredPoint(x: patch.bounds.maxX, y: patch.bounds.maxY))
    return FacePatch(bounds: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).integral)
  }
}

private func prepare() throws {
  let arguments = CommandLine.arguments
  if arguments.count >= 2 && arguments[1] == "--hero" {
    try prepareHero(arguments)
    return
  }
  guard arguments.count == 3 else { fail("Expected SOURCE_JPG and OUTPUT_DIRECTORY.") }
  let input = URL(fileURLWithPath: arguments[1])
  let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
  let original = try Data(contentsOf: input)
  let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
  guard hash == "82c449c8cda29031f4cee1890d3a552026e024cf4d0990f59fe817466667ae51"
  else { fail("This registration is specific to the supplied 1672×941 source.") }
  guard let source = CGImageSourceCreateWithData(original as CFData, nil),
    let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { fail("Cannot decode the source sheet.") }
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

  for pose in poses {
    guard let image = sheet.cropping(to: pose.crop) else { fail("Cannot crop \(pose.name).") }
    var raster = Raster(width: image.width, height: image.height, pixels: decode(image))
    raster.cutOut(confidence: try foregroundConfidence(image), pose: pose)
    raster.removeFaceInk(in: pose)
    if let split = raster.splitAppendage(of: pose) {
      try write(split.body.registered(to: pose), named: pose.name, to: output)
      try write(split.part.registered(to: pose), named: pose.name + "-" + split.suffix, to: output)
    } else {
      try write(raster.registered(to: pose), named: pose.name, to: output)
    }
    if pose.name == "left" {
      for (name, layer) in raster.splitWalkingProfile(of: pose) {
        try write(layer.registered(to: pose), named: "left-walk-\(name)", to: output)
        try write(layer.registered(to: pose, mirror: true), named: "right-walk-\(name)", to: output)
      }
    }
  }
}

try prepare()

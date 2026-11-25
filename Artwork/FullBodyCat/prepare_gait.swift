// Usage: swift -O Artwork/FullBodyCat/prepare_gait.swift ALIGNED_PROFILE_PNG CUTS_JSON REVIEW_DIRECTORY
// Splits a face-cleared sRGB profile at 4 pixels per point. Stage coordinates run down from the top.
import CoreGraphics
import Foundation
import ImageIO

private let side = 1024
private let bytesPerRow = side * 4
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
private let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
  | CGBitmapInfo.byteOrder32Big.rawValue)

private enum Layer: Int, CaseIterable {
  case body, nearFront, farFront, nearHind, farHind

  var filename: String {
    switch self {
    case .body: "body"
    case .nearFront: "near-front"
    case .farFront: "far-front"
    case .nearHind: "near-hind"
    case .farHind: "far-hind"
    }
  }
}

private struct Cut: Decodable {
  let limit: Double
  let body: [[Double]]
  let shoulder: [[Double]]
  let seam: [[Double]]?
  let farToe: [[Double]]?
  let hiddenFar: HiddenLeg?

  var valid: Bool {
    guard (0...256).contains(limit) else { return false }
    var curves = [body, shoulder]
    if let hiddenFar {
      guard hiddenFar.valid else { return false }
    } else {
      guard let seam, let farToe else { return false }
      curves += [seam, farToe]
    }
    return curves.allSatisfy { curve in
      curve.count >= 2 && curve.allSatisfy { pair in
        pair.count == 2 && pair.allSatisfy { (0...256).contains($0) }
      } && zip(curve, curve.dropFirst()).allSatisfy { $0[0] < $1[0] }
    }
  }

  func sample(_ curve: [[Double]], at point: Double) -> Double {
    guard point > curve[0][0] else { return curve[0][1] }
    for (start, end) in zip(curve, curve.dropFirst()) where point < end[0] {
      return start[1] + (end[1] - start[1]) * (point - start[0]) / (end[0] - start[0])
    }
    return curve[curve.count - 1][1]
  }

  func coverage(x: Double, y: Double, front: Bool) -> (body: Double, near: Double, far: Double) {
    let section = front ? limit - x : x - limit
    let bodyEdge = y - sample(body, at: x)
    // The torso covers the extra joint area. The far leg continues beneath the near leg.
    let depth = min(14, max(0, section) + 0.5)
    let root = min(section + 0.5, bodyEdge + depth, y - sample(shoulder, at: x))
    func feather(_ distance: Double) -> Double { min(1, max(0, distance * 2 + 0.5)) }
    let torso = 1 - feather(min(section, bodyEdge))
    if let hiddenFar {
      return (torso, feather(root), feather(min(root, hiddenFar.edge(x: x, y: y))))
    }
    guard let seam, let farToe else { preconditionFailure("Missing visible leg contours.") }
    let siblingEdge = x - sample(seam, at: y)
    let toeEdge = sample(farToe, at: x) - y
    // Let the moving roots overlap, but do not carry part of the adjacent toe into a stride.
    let underlap = 0.65 + 3.35 * min(1, max(0, (208 - y) / 12))
    let near = min(root, max(siblingEdge, -toeEdge))
    let far = min(root, -siblingEdge + underlap, toeEdge + underlap)
    return (torso, feather(near), feather(far))
  }
}

private struct HiddenLeg: Decodable {
  let hip: [Double]
  let paw: [Double]
  let radius: Double

  var valid: Bool {
    [hip, paw].allSatisfy { $0.count == 2 && $0.allSatisfy { (0...256).contains($0) } }
      && hip != paw && (1...20).contains(radius)
  }

  func edge(x: Double, y: Double) -> Double {
    let dx = paw[0] - hip[0]
    let dy = paw[1] - hip[1]
    let projection = min(1, max(0, ((x - hip[0]) * dx + (y - hip[1]) * dy) / (dx * dx + dy * dy)))
    return radius - hypot(x - (hip[0] + dx * projection), y - (hip[1] + dy * projection))
  }
}

private struct Calibration: Decodable {
  let direction: String
  let front: Cut
  let hind: Cut
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

private func decode(_ url: URL) -> [UInt8] {
  guard let decoder = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil),
    image.width == side, image.height == side,
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
      bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmap.rawValue),
    let data = context.data
  else { fail("The aligned profile must be a \(side) × \(side) PNG.") }
  context.setBlendMode(.copy)
  context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
  let bytes = data.assumingMemoryBound(to: UInt8.self)
  return Array(UnsafeBufferPointer(start: bytes, count: bytesPerRow * side))
}

private func remainingAlpha(_ alpha: Double, coverage: Double, over top: Double) -> Double {
  // Opaque common areas stay intact under each joint. A translucent source edge belongs
  // to a single visible silhouette even if it passes between two layers.
  guard alpha < 1 else { return coverage }
  guard top < alpha else { return 0 }
  return min(alpha * coverage, (alpha - top) / (1 - top))
}

private func writePNG(_ bytes: [UInt8], to url: URL) throws {
  let output = NSMutableData()
  guard let provider = CGDataProvider(data: Data(bytes) as CFData),
    let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmap, provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent),
    let encoder = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
  else { fail("Cannot create \(url.lastPathComponent).") }
  CGImageDestinationAddImage(encoder, image, nil)
  guard CGImageDestinationFinalize(encoder) else { fail("Cannot encode \(url.lastPathComponent).") }
  try (output as Data).write(to: url, options: .atomic)
}

private func prepareGait(_ arguments: [String]) throws {
  guard arguments.count == 4 else { fail("Expected ALIGNED_PROFILE_PNG CUTS_JSON REVIEW_DIRECTORY.") }
  let input = URL(fileURLWithPath: arguments[1])
  let cutFile = URL(fileURLWithPath: arguments[2])
  let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
  let calibration = try JSONDecoder().decode(Calibration.self, from: Data(contentsOf: cutFile))
  guard ["left", "right"].contains(calibration.direction),
    calibration.front.valid, calibration.hind.valid, calibration.front.limit < calibration.hind.limit
  else { fail("Check profile direction, section limits and ordered two-coordinate curves.") }
  let source = decode(input)
  var result = Layer.allCases.map { _ in [UInt8](repeating: 0, count: source.count) }
  var largestAlphaError = 0.0

  for row in 0..<side {
    let y = (Double(row) + 0.5) / 4
    for column in 0..<side {
      let offset = row * bytesPerRow + column * 4
      let inputAlpha = Double(source[offset + 3])
      guard inputAlpha > 0 else { continue }
      let columnX = (Double(column) + 0.5) / 4
      let x = calibration.direction == "right" ? 256 - columnX : columnX
      let alpha = inputAlpha / 255
      let isFront = x < (calibration.front.limit + calibration.hind.limit) / 2
      let cut = isFront ? calibration.front : calibration.hind
      let masks = cut.coverage(x: x, y: y, front: isFront)
      let body = alpha * masks.body
      let near = remainingAlpha(alpha, coverage: masks.near, over: body)
      let covered = body + near * (1 - body)
      let far = remainingAlpha(alpha, coverage: masks.far, over: covered)
      let found = covered + far * (1 - covered)
      largestAlphaError = max(largestAlphaError, abs(found - alpha))

      func write(_ layer: Layer, amount: Double) {
        let layerAlpha = UInt8(clamping: Int((amount * 255).rounded()))
        guard layerAlpha > 0 else { return }
        let factor = Double(layerAlpha) / inputAlpha
        for channel in 0..<3 {
          result[layer.rawValue][offset + channel] = UInt8(clamping:
            Int((Double(source[offset + channel]) * factor).rounded()))
        }
        result[layer.rawValue][offset + 3] = layerAlpha
      }

      write(.body, amount: body)
      write(isFront ? .nearFront : .nearHind, amount: near)
      write(isFront ? .farFront : .farHind, amount: far)
    }
  }

  guard largestAlphaError < 1.0 / 255 else { fail("The leg cuts leave a hole in the resting silhouette.") }
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  for layer in Layer.allCases {
    let name = "full-body-cat-\(calibration.direction)-walk-\(layer.filename).png"
    let bytes = result[layer.rawValue]
    guard stride(from: 3, to: bytes.count, by: 4).contains(where: { bytes[$0] > 240 })
    else { fail("\(name) did not receive any visible material.") }
    try writePNG(bytes, to: output.appendingPathComponent(name))
    print("Wrote \(name).")
  }
}

try prepareGait(CommandLine.arguments)

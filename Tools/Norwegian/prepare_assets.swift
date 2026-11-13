// Usage: swift Tools/Norwegian/prepare_assets.swift INPUT_DIRECTORY OUTPUT_DIRECTORY
// Requires ffmpeg and gifsicle on PATH. Originals remain outside the package resource bundle.
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

let emotions = ["joy", "affection", "gratitude", "interest", "surprise", "calm_trust",
  "sadness", "anxiety_fear", "anger_irritation", "disgust_contempt", "shame_guilt", "fatigue_burden"]
let args = CommandLine.arguments
guard args.count == 3 else { fail("Expected input and output directories") }
let input = URL(fileURLWithPath: args[1], isDirectory: true)
let output = URL(fileURLWithPath: args[2], isDirectory: true)
let fm = FileManager.default
let scratch = fm.temporaryDirectory.appendingPathComponent("norwegian-\(UUID().uuidString)")
try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }
let side = 288, frameCount = 12
let sourceFrames = [0, 1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 15]

func source(_ name: String) throws -> CGImageSource {
  let url = input.appendingPathComponent(name + ".gif")
  guard let result = CGImageSourceCreateWithURL(url as CFURL, nil),
    CGImageSourceGetCount(result) == 16 else { fail("Missing or invalid GIF: \(name)") }
  return result
}
func frame(_ source: CGImageSource, _ index: Int) -> CGImage {
  guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
    fail("Cannot decode frame \(index)")
  }
  return image
}
func canvas(_ image: CGImage) -> CGImage {
  let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let scale = min(Double(side - 12) / Double(image.width), Double(side - 12) / Double(image.height))
  let w = Double(image.width) * scale, h = Double(image.height) * scale
  c.interpolationQuality = .high
  c.draw(image, in: CGRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
  return c.makeImage()!
}
func pixels(_ image: CGImage) -> [UInt8] {
  var bytes = [UInt8](repeating: 0, count: side * side * 4)
  let c = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
  return bytes
}
func png(_ image: CGImage, _ url: URL) {
  let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(d, image, nil)
  guard CGImageDestinationFinalize(d) else { fail("Cannot encode PNG") }
}
func run(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["ffmpeg", "-v", "error", "-y"] + arguments
  try process.run(); process.waitUntilExit()
  guard process.terminationStatus == 0 else { fail("ffmpeg failed: \(arguments)") }
}
func optimize(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["gifsicle"] + arguments
  try process.run(); process.waitUntilExit()
  guard process.terminationStatus == 0 else { fail("gifsicle failed") }
}

let sources = try emotions.map(source)
let neutral = canvas(frame(sources[0], 0))
let neutralPixels = pixels(neutral)
var provenance: [String: String] = [:]
for (clip, emotion) in emotions.enumerated() {
  let original = try Data(contentsOf: input.appendingPathComponent(emotion + ".gif"))
  provenance[emotion] = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
  for index in 0..<frameCount {
    let image: CGImage
    if index == 0 || index == frameCount - 1 {
      image = neutral
    } else {
      // Ease the generated neutral boundary into the single canonical neutral.
      let edge = min(index, frameCount - 1 - index)
      let weight = min(1, Double(edge) / 2)
      let current = pixels(canvas(frame(sources[clip], sourceFrames[index])))
      var mixed = zip(neutralPixels, current).map { a, b in
        UInt8((Double(a) * (1 - weight) + Double(b) * weight).rounded())
      }
      let c = CGContext(data: &mixed, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      image = c.makeImage()!
    }
    png(image, scratch.appendingPathComponent(String(format: "%04d.png", clip * frameCount + index)))
  }
}
let palette = scratch.appendingPathComponent("palette.png").path
try run(["-i", scratch.appendingPathComponent("%04d.png").path,
  "-vf", "palettegen=max_colors=128:reserve_transparent=1", "-frames:v", "1", palette])
try fm.createDirectory(at: output, withIntermediateDirectories: true)
for (clip, emotion) in emotions.enumerated() {
  try run(["-framerate", "25/4", "-start_number", String(clip * frameCount),
    "-i", scratch.appendingPathComponent("%04d.png").path, "-i", palette,
    "-lavfi", "paletteuse=dither=none:diff_mode=rectangle:alpha_threshold=128",
    "-frames:v", String(frameCount), "-gifflags", "+transdiff", "-loop", "-1",
    output.appendingPathComponent("norwegian-\(emotion).gif").path])
}
// Lossless frame-difference optimization preserves eyes and fur without adding speckle.
for emotion in emotions {
  let file = output.appendingPathComponent("norwegian-\(emotion).gif").path
  try optimize(["-O3", "--batch", file])
}
// Decode the quantized canonical frame so the standalone neutral has exactly the GIF's pixels.
let first = CGImageSourceCreateWithURL(output.appendingPathComponent("norwegian-joy.gif") as CFURL, nil)!
png(frame(first, 0), output.appendingPathComponent("norwegian-neutral.png"))
let manifest = try JSONSerialization.data(withJSONObject: provenance, options: [.prettyPrinted, .sortedKeys])
try manifest.write(to: output.appendingPathComponent("source-sha256.json"))
print("Prepared \(emotions.count) one-shot GIFs and one canonical neutral at \(output.path)")

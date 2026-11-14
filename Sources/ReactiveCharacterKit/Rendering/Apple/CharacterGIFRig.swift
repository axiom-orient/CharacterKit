#if os(iOS) || os(macOS)
  import CoreGraphics
  import Foundation

  /// Local texture articulation. Eye boundaries and fur stay authored pixels; only
  /// the iris interior is warped. Speech and blink reuse registered authored patches.
  @MainActor
  final class CharacterGIFRig {
    struct Bitmap {
      let width: Int
      let height: Int
      let pixels: [UInt8]

      init(_ image: CGImage) {
        width = image.width; height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = bytes
      }

      func channel(_ x: Double, _ y: Double, _ channel: Int) -> Double {
        let xx = min(Double(width - 1), max(0, x)), yy = min(Double(height - 1), max(0, y))
        let x0 = Int(xx), y0 = Int(yy), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = xx - Double(x0), fy = yy - Double(y0)
        func value(_ x: Int, _ y: Int) -> Double { Double(pixels[(y * width + x) * 4 + channel]) }
        return (value(x0, y0) * (1 - fx) + value(x1, y0) * fx) * (1 - fy)
          + (value(x0, y1) * (1 - fx) + value(x1, y1) * fx) * fy
      }
    }

    struct Face {
      let eyes: [CGRect?]
      let nose: CGPoint
    }

    private struct SpeechTexture {
      let emotion: CharacterEmotion
      let open: Bitmap
      let face: Face
      let closed: Bitmap
      let closedFace: Face
    }

    private let gifs: CharacterGIFSet
    private var speechTexture: SpeechTexture?
    private let neutral: Bitmap
    private let speaking: Bitmap
    private let closedEyes: Bitmap
    private let neutralFace: Face
    private let speakingFace: Face
    private var cachedID: ObjectIdentifier?
    private var cachedImage: CGImage?
    private var cachedBitmap: Bitmap?
    private var cachedFace: Face?

    init(gifs: CharacterGIFSet) throws {
      self.gifs = gifs
      neutral = Bitmap(gifs.neutral)
      speaking = Bitmap(try gifs.image(for: .joy, elapsed: gifs.duration(for: .joy) / 2,
        reduceMotion: false)!)
      closedEyes = Bitmap(try gifs.image(for: .calmTrust, elapsed: gifs.duration(for: .calmTrust) / 2,
        reduceMotion: false)!)
      neutralFace = Self.face(in: neutral)
      speakingFace = Self.face(in: speaking)
    }

    func render(_ image: CGImage, pose: CharacterPose, speechWeight: Double,
      emotion: CharacterEmotion? = nil, expressionWeight: Double = 0) throws -> CGImage {
      let gazeX = min(0.23, max(-0.23, (pose.eyes.left.centerX + pose.eyes.right.centerX) / 2 - 0.5))
      let gazeY = min(0.24, max(-0.24, (pose.eyes.left.centerY + pose.eyes.right.centerY) / 2 - 0.5))
      let blink = max(pose.eyes.left.blink, pose.eyes.right.blink)
      guard abs(gazeX) + abs(gazeY) > 0.0001 || blink > 0.001 || speechWeight > 0.001 else {
        return image
      }
      let id = ObjectIdentifier(image)
      if id != cachedID {
        let bitmap = Bitmap(image)
        cachedBitmap = bitmap; cachedFace = Self.face(in: bitmap); cachedID = id
        cachedImage = image
      }
      let source = cachedBitmap!, face = cachedFace!
      var output = source.pixels
      let dx = gazeX * Double(source.width) * 0.060
      let dy = gazeY * Double(source.height) * 0.042

      for (side, eye) in face.eyes.enumerated() {
        guard let eye else { continue } // Authored closed eyelids do not acquire a false iris.
        let center = CGPoint(x: eye.midX, y: eye.midY)
        let rx = max(18, eye.width / 2 + 10), ry = max(11, eye.height / 2 + 6)
        visit(center: center, rx: rx, ry: ry, source: source) { x, y, r2 in
          let weight = Self.smooth(min(1, max(0, (1 - r2) / 0.65)))
          write(&output, x, y, source: source, sx: Double(x) - dx * weight,
            sy: Double(y) - dy * weight, opacity: 1)
        }
        let eyeBlink = side == 0 ? pose.eyes.left.blink : pose.eyes.right.blink
        if eyeBlink > 0.001 {
          // Centers measured on the shared 288px calm-trust closed-eye artwork.
          let closedCenter = CGPoint(x: side == 0 ? 108 : 184, y: 132)
          visit(center: center, rx: 34, ry: 29, source: source) { x, y, r2 in
            let alpha = Self.smooth(min(1, max(0, (1 - r2) / 0.35))) * eyeBlink
            write(&output, x, y, source: closedEyes,
              sx: Double(x) - center.x + closedCenter.x,
              sy: Double(y) - center.y + closedCenter.y, opacity: alpha)
          }
        }
      }

      if speechWeight > 0.001 {
        let beforeMouth = output
        paintMouth(&output, source: source, face: face, pose: pose, weight: speechWeight,
          closed: neutral, closedFace: neutralFace, opened: speaking, openFace: speakingFace)
        let mix = min(1, max(0, expressionWeight))
        if let emotion, mix > 0.001 {
          let texture = try texture(for: emotion)
          var expressive = beforeMouth
          paintMouth(&expressive, source: source, face: face, pose: pose, weight: speechWeight,
            closed: texture.closed, closedFace: texture.closedFace,
            opened: texture.open, openFace: texture.face)
          // Both passes fully remove the old mouth. Blend their results, rather than
          // stacking two partial masks that could leave a second mouth underneath.
          let center = CGPoint(x: face.nose.x, y: face.nose.y + 15)
          visit(center: center, rx: 35, ry: 24, source: source) { x, y, _ in
            let i = (y * source.width + x) * 4
            for c in 0..<4 {
              output[i + c] = UInt8((Double(output[i + c]) * (1 - mix)
                + Double(expressive[i + c]) * mix).rounded())
            }
          }
        }
      }

      let provider = CGDataProvider(data: Data(output) as CFData)!
      return CGImage(width: source.width, height: source.height, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
        shouldInterpolate: true, intent: .defaultIntent)!
    }

    private func paintMouth(_ output: inout [UInt8], source: Bitmap, face: Face,
      pose: CharacterPose, weight: Double, closed: Bitmap, closedFace: Face,
      opened: Bitmap, openFace: Face) {
      let center = CGPoint(x: face.nose.x, y: face.nose.y + 15)
      // The closed patch removes the clip's mouth before articulation; it never
      // replaces eyes or broad fur regions. All seams lie in the white muzzle.
      visit(center: center, rx: 35, ry: 24, source: source) { x, y, r2 in
        let top = Self.smooth(min(1, max(0, (Double(y) - face.nose.y - 3) / 5)))
        let alpha = Self.smooth(min(1, max(0, (1 - r2) / 0.45))) * top * weight
        write(&output, x, y, source: closed,
          sx: Double(x) - face.nose.x + closedFace.nose.x,
          sy: Double(y) - face.nose.y + closedFace.nose.y, opacity: alpha)
      }
      let openness = min(1, max(0, pose.mouth.openness))
      let articulation = max(0, openness - 0.10)
      let openWeight = Self.smooth(min(1, articulation / 0.15))
      let scaleY = 0.25 + articulation
      let scaleX = 0.45 + min(1, pose.mouth.width) * 0.75
      visit(center: center, rx: 33, ry: 24, source: source) { x, y, _ in
        let u = (Double(x) - center.x) / scaleX
        let v = (Double(y) - center.y) / scaleY
        let r2 = u * u / (32 * 32) + v * v / (23 * 23)
        let sy = openFace.nose.y + 19 + v
        let top = Self.smooth(min(1, max(0, (sy - openFace.nose.y - 5) / 4)))
        let alpha = Self.smooth(min(1, max(0, (1 - r2) / 0.45))) * top * weight * openWeight
        write(&output, x, y, source: opened, sx: openFace.nose.x + u,
          sy: sy, opacity: alpha)
      }
    }

    private func texture(for emotion: CharacterEmotion) throws -> SpeechTexture {
      if let speechTexture, speechTexture.emotion == emotion { return speechTexture }
      let opening: CharacterEmotion
      switch emotion {
      case .joy, .affection, .gratitude, .calmTrust: opening = .joy
      case .angerIrritation: opening = .angerIrritation
      case .anxietyFear, .sadness, .shameGuilt, .disgustContempt: opening = .anxietyFear
      case .interest: opening = .interest
      case .surprise: opening = .surprise
      case .fatigueBurden: opening = .fatigueBurden
      }
      let opened = Bitmap(try gifs.image(for: opening,
        elapsed: gifs.duration(for: opening) / 2, reduceMotion: false)!)
      let closed: Bitmap
      switch emotion {
      case .sadness, .shameGuilt, .disgustContempt, .affection, .gratitude, .calmTrust:
        closed = Bitmap(try gifs.image(for: emotion,
          elapsed: gifs.duration(for: emotion) / 2, reduceMotion: false)!)
      case .angerIrritation, .anxietyFear:
        closed = Bitmap(try gifs.image(for: .sadness,
          elapsed: gifs.duration(for: .sadness) / 2, reduceMotion: false)!)
      default: closed = neutral
      }
      let result = SpeechTexture(emotion: emotion, open: opened, face: Self.face(in: opened),
        closed: closed, closedFace: Self.face(in: closed))
      speechTexture = result
      return result
    }

    private func visit(center: CGPoint, rx: Double, ry: Double, source: Bitmap,
      body: (Int, Int, Double) -> Void) {
      let x0 = max(0, Int(center.x - rx)), x1 = min(source.width - 1, Int(center.x + rx))
      let y0 = max(0, Int(center.y - ry)), y1 = min(source.height - 1, Int(center.y + ry))
      guard x0 <= x1, y0 <= y1 else { return }
      for y in y0...y1 { for x in x0...x1 {
        let u = (Double(x) - center.x) / rx, v = (Double(y) - center.y) / ry
        let r2 = u * u + v * v
        if r2 < 1 { body(x, y, r2) }
      } }
    }

    private func write(_ output: inout [UInt8], _ x: Int, _ y: Int, source: Bitmap,
      sx: Double, sy: Double, opacity: Double) {
      guard opacity > 0 else { return }
      let i = (y * source.width + x) * 4
      for channel in 0..<4 {
        output[i + channel] = UInt8(min(255, max(0,
          (Double(output[i + channel]) * (1 - opacity)
            + source.channel(sx, sy, channel) * opacity).rounded())))
      }
    }

    static func face(in bitmap: Bitmap) -> Face {
      let w = bitmap.width, h = bitmap.height
      var eyes: [CGRect?] = []
      for side in 0...1 {
        var x0 = w, x1 = 0, y0 = h, y1 = 0, count = 0
        let range = side == 0 ? Int(Double(w) * 0.23)..<w / 2 : w / 2..<Int(Double(w) * 0.77)
        for y in Int(Double(h) * 0.26)..<Int(Double(h) * 0.58) {
          for x in range {
            let i = (y * w + x) * 4
            let r = Int(bitmap.pixels[i]), g = Int(bitmap.pixels[i + 1]), b = Int(bitmap.pixels[i + 2])
            if g > r + 8, g > b + 15, bitmap.pixels[i + 3] > 200 {
              x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y); count += 1
            }
          }
        }
        eyes.append(count > 8 ? CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1) : nil)
      }
      var nx = 0.0, ny = 0.0, count = 0.0
      let visibleEyes = eyes.compactMap { $0 }
      let centerX = visibleEyes.isEmpty ? Double(w) * 0.51
        : visibleEyes.map(\.midX).reduce(0, +) / Double(visibleEyes.count)
      let eyeY = visibleEyes.isEmpty ? Double(h) * 0.44
        : visibleEyes.map(\.midY).reduce(0, +) / Double(visibleEyes.count)
      let minY = max(0, Int(eyeY + 8)), maxY = min(h, Int(eyeY + 30))
      for y in minY..<maxY {
        for x in max(0, Int(centerX - 14))..<min(w, Int(centerX + 14)) {
          let i = (y * w + x) * 4
          let r = Int(bitmap.pixels[i]), g = Int(bitmap.pixels[i + 1]), b = Int(bitmap.pixels[i + 2])
          if r > 170, r > g + 30, r > b + 15, b > 80 {
            nx += Double(x); ny += Double(y); count += 1
          }
        }
      }
      return Face(eyes: eyes, nose: count > 0 ? CGPoint(x: nx / count, y: ny / count)
        : CGPoint(x: Double(w) * 0.51, y: Double(h) * 0.54))
    }

    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
  }
#endif

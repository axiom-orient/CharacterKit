#if os(iOS) || os(macOS)
  import CoreGraphics
  import Foundation
  import ImageIO
  import UniformTypeIdentifiers

  /// Deforms the connected near-side skin and reveals the far paws behind it.
  enum CharacterFeltWalkRenderer {
    private static let size = 1024
    private static let density: Float = 4
    private static let firstRow = 164 * 4
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let bitmap = CGBitmapInfo.byteOrder32Big.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))

    private struct Axis: Sendable {
      let root: Float
      let span: Float

      init(_ leg: CharacterFullBodyCatArtwork.Leg) {
        root = Float(leg.art.pivot.y) - 4
        span = Float(leg.foot.y) - root
      }

      func inverseRows(_ step: CharacterFeltWalkSurface.Step) -> [Row] {
        (firstRow..<size).map { pixel in
          let destination = (Float(pixel) + 0.5) / density
          var source = destination
          for _ in 0..<5 {
            let t = unit((source - root) / span)
            let delta = source + step.y * ease(t) - destination
            source -= delta / (1 + step.y * 6 * t * (1 - t) / span)
          }
          let offset = step.x * ease(unit((source - root) / span))
          return Row(x: offset * density, y: source * density - 0.5)
        }
      }
    }

    private struct Row {
      let x: Float
      let y: Float
    }

    private struct Texture: Sendable {
      let pixels: [UInt32]
      let first: Float
      let last: Float

      init(_ pixels: [UInt32]) {
        self.pixels = pixels
        var left = size
        var right = 0
        for index in firstRow * size..<pixels.count where pixels[index] != 0 {
          let column = index % size
          left = min(left, column)
          right = max(right, column)
        }
        first = Float(max(0, left - 1))
        last = Float(min(size - 2, right + 1))
      }

      @inline(__always)
      func sample(x: Float, y: Float) -> UInt32 {
        guard x >= first, x <= last, y >= 0, y < Float(size - 1) else { return 0 }
        let x0 = Int(x), y0 = Int(y)
        let top = y0 * size + x0
        let bottom = top + size
        let a = pixels[top], b = pixels[top + 1], c = pixels[bottom], d = pixels[bottom + 1]
        if a | b | c | d == 0 { return 0 }
        let tx = x - Float(x0), ty = y - Float(y0)
        let lower = rgba(c) * (1 - tx) + rgba(d) * tx
        let upper = rgba(a) * (1 - tx) + rgba(b) * tx
        return packed(upper * (1 - ty) + lower * ty)
      }
    }

    private struct Binding: Sendable {
      let front: Axis
      let hind: Axis
      let farFront: Axis
      let farHind: Axis
      let skin: Texture
      let hiddenFront: Texture
      let hiddenHind: Texture

      init?(_ pose: CharacterFullBodyCatPose) {
        guard let rig = CharacterFullBodyCatArtwork.resolve(pose).walk,
          let front = rig.legs.first(where: { $0.id == .nearFront }),
          let hind = rig.legs.first(where: { $0.id == .nearHind }),
          let farFront = rig.legs.first(where: { $0.id == .farFront }),
          let farHind = rig.legs.first(where: { $0.id == .farHind }),
          let frontWool = read(front.art.asset, clip: front.art.clip), let hindWool = read(hind.art.asset),
          let farFrontWool = read(farFront.art.asset), let farHindWool = read(farHind.art.asset),
          var skin = read(rig.torso, clip: rig.torsoClip)
        else { return nil }
        // Join the registered artwork before it moves. Both sides of each cut
        // are now in the same texture with one displacement at every pixel.
        for index in firstRow * size..<skin.count {
          skin[index] = over(skin[index], over(frontWool[index], hindWool[index]))
        }
        self.front = Axis(front)
        self.hind = Axis(hind)
        self.farFront = Axis(farFront)
        self.farHind = Axis(farHind)
        self.skin = Texture(skin)
        hiddenFront = Texture(farFrontWool)
        hiddenHind = Texture(farHindWool)
      }
    }

    private final class Key: NSObject {
      let surface: CharacterFeltWalkSurface
      init(_ surface: CharacterFeltWalkSurface) { self.surface = surface }
      override var hash: Int { surface.hashValue }
      override func isEqual(_ object: Any?) -> Bool { (object as? Key)?.surface == surface }
    }

    // NSCache supplies synchronization and bounds the weight of transient 1024px frames.
    private final class FrameCache: @unchecked Sendable {
      let frames = NSCache<Key, CGImage>()
      init() { frames.totalCostLimit = size * size * 4 * 5 }
    }

    private static let left = Binding(.left)
    private static let right = Binding(.right)
    private static let cache = FrameCache()
    private static let weight: [SIMD2<Float>] = (0..<size).map { pixel in
      let x = (Float(pixel) + 0.5) / density
      return SIMD2(ease(unit((133 - x) / 39)), ease(unit((x - 132) / 39)))
    }

    static func hasSource(_ surface: CharacterFeltWalkSurface) -> Bool {
      (surface.right ? right : left) != nil
    }

    static func prepare(_ pose: CharacterFullBodyCatPose) {
      _ = pose == .right ? right : left
    }

    static func image(_ surface: CharacterFeltWalkSurface) -> CGImage? {
      let key = Key(surface)
      if let image = cache.frames.object(forKey: key) { return image }
      guard let binding = surface.right ? right : left,
        let image = image(data: render(surface, binding: binding))
      else { return nil }
      cache.frames.setObject(image, forKey: key, cost: size * size * 4)
      return image
    }

    static func png(_ surface: CharacterFeltWalkSurface, name: String) throws -> Data {
      guard let image = image(surface) else {
        throw CharacterImageResolutionError.unavailable(name: name, source: .package)
      }
      let bytes = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(
        bytes, UTType.png.identifier as CFString, 1, nil)
      else { throw CharacterImageResolutionError.invalidPNG(name: name) }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw CharacterImageResolutionError.invalidPNG(name: name) }
      return bytes as Data
    }

    private static func render(_ surface: CharacterFeltWalkSurface, binding: Binding) -> Data {
      let front = binding.front.inverseRows(surface.nearFront)
      let hind = binding.hind.inverseRows(surface.nearHind)
      let farFront = binding.farFront.inverseRows(surface.farFront)
      let farHind = binding.farHind.inverseRows(surface.farHind)
      // Paint into aligned final image storage, then transfer ownership to Data.
      let count = binding.skin.pixels.count
      let pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
      let result = UnsafeMutableBufferPointer(start: pixels, count: count)
      _ = result.initialize(from: binding.skin.pixels)
      for index in front.indices {
        let row = index + firstRow
        let y = Float(row)
        let frontRow = front[index], hindRow = hind[index]
        let frontFarRow = farFront[index], hindFarRow = farHind[index]
        let frontRise = frontRow.y - y, hindRise = hindRow.y - y
        // At these rows the whole existing coat, including every motion extent,
        // stays within the interior of the stage.
        for column in (18 * 4)..<(238 * 4) {
          let x = Float(column)
          let w = weight[surface.right ? size - column - 1 : column]
          let near = binding.skin.sample(x: x - frontRow.x * w.x - hindRow.x * w.y,
            y: y + frontRise * w.x + hindRise * w.y)
          let index = row * size + column
          if near >> 24 == 255 {
            result[index] = near
          } else {
            let front = binding.hiddenFront.sample(x: x - frontFarRow.x, y: frontFarRow.y)
            let hind = binding.hiddenHind.sample(x: x - hindFarRow.x, y: hindFarRow.y)
            result[index] = over(near, over(front, hind))
          }
        }
      }
      return Data(bytesNoCopy: pixels, count: count * MemoryLayout<UInt32>.stride,
        deallocator: .custom { bytes, byteCount in
          let pixels = bytes.assumingMemoryBound(to: UInt32.self)
          pixels.deinitialize(count: byteCount / MemoryLayout<UInt32>.stride)
          pixels.deallocate()
        })
    }

    private static func read(_ asset: CharacterImageAsset, clip: CharacterVectorPath? = nil) -> [UInt32]? {
      guard let data = try? CharacterImageResources.png(asset),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == size, image.height == size
      else { return nil }
      var pixels = [UInt32](repeating: 0, count: size * size)
      let success = pixels.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: size, height: size,
          bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: bitmap.rawValue)
        else { return false }
        if let clip {
          var transform = CGAffineTransform(a: CGFloat(density), b: 0, c: 0, d: -CGFloat(density),
            tx: 0, ty: CGFloat(size))
          guard let mask = CharacterSceneCanvasRenderer.path(clip).cgPath.copy(using: &transform) else { return false }
          context.addPath(mask)
          context.clip()
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return true
      }
      return success ? pixels : nil
    }

    private static func image(data: Data) -> CGImage? {
      guard let provider = CGDataProvider(data: data as CFData) else { return nil }
      return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: size * 4, space: colorSpace, bitmapInfo: bitmap, provider: provider,
        decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    @inline(__always)
    private static func unit(_ value: Float) -> Float { min(1, max(0, value)) }

    @inline(__always)
    private static func ease(_ value: Float) -> Float { value * value * (3 - 2 * value) }

    @inline(__always)
    private static func rgba(_ p: UInt32) -> SIMD4<Float> {
      .init(Float(p & 255), Float((p >> 8) & 255), Float((p >> 16) & 255), Float(p >> 24))
    }

    @inline(__always)
    private static func packed(_ p: SIMD4<Float>) -> UInt32 {
      UInt32(p.x + 0.5) | (UInt32(p.y + 0.5) << 8) | (UInt32(p.z + 0.5) << 16) | (UInt32(p.w + 0.5) << 24)
    }

    @inline(__always)
    private static func over(_ foreground: UInt32, _ background: UInt32) -> UInt32 {
      if foreground >> 24 == 255 || background == 0 { return foreground }
      if foreground == 0 { return background }
      return packed(rgba(foreground) + rgba(background) * (1 - Float(foreground >> 24) / 255))
    }
  }
#endif

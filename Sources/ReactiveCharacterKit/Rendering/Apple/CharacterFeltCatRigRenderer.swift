#if os(iOS) || os(macOS)
  import CoreGraphics
  import Foundation
  import ImageIO
  import UniformTypeIdentifiers

  /// Renders transient poses from vector contours, inverse texture maps, and bundled wool.
  enum CharacterFeltCatRigRenderer {
    static let pixelSize = 640
    private static let stageSize: Float = 256
    private static let mapSize = 17
    private static let namePrefix = "full-body-cat-transition-"
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))

    private struct Layer: Decodable {
      let paths: [[Int]]
      let a: Mapping
      let b: Mapping?
      let mix: Float?
    }

    private struct Mapping: Decodable {
      let asset: String
      let affine: [Float]?
      let grid: [Int]?

      var hasCoordinates: Bool { affine?.count == 6 || grid?.count == 2 * mapSize * mapSize }

      var sampler: Sampler? {
        if let affine, affine.count == 6 {
          return .affine(
            horizontal: .init(affine[0], affine[2]),
            vertical: .init(affine[1], affine[3]),
            translation: .init(affine[4], affine[5]))
        }
        if let grid, grid.count == 2 * mapSize * mapSize {
          let coordinates = stride(from: 0, to: grid.count, by: 2).map {
            SIMD2<Float>(Float(grid[$0]), Float(grid[$0 + 1])) / 16
          }
          return .grid(coordinates)
        }
        return nil
      }
    }

    private enum Sampler {
      case affine(horizontal: SIMD2<Float>, vertical: SIMD2<Float>, translation: SIMD2<Float>)
      case grid([SIMD2<Float>])

      @inline(__always)
      func source(x: Float, y: Float) -> SIMD2<Float> {
        switch self {
        case .affine(let horizontal, let vertical, let translation):
          return horizontal * x + vertical * y + translation
        case .grid(let coordinates):
          let column = x / 16
          let row = y / 16
          let x0 = min(mapSize - 2, Int(column))
          let y0 = min(mapSize - 2, Int(row))
          let tx = column - Float(x0)
          let ty = row - Float(y0)
          let index = y0 * mapSize + x0
          let topLeft = coordinates[index]
          let bottomLeft = coordinates[index + mapSize]
          let top = topLeft + (coordinates[index + 1] - topLeft) * tx
          let bottom = bottomLeft + (coordinates[index + mapSize + 1] - bottomLeft) * tx
          return top + (bottom - top) * ty
        }
      }
    }

    private final class Texture {
      let pixels: [UInt32]
      let width: Int
      let height: Int
      let columns: Range<Int>
      let rows: Range<Int>
      let wool: [UInt32]
      let patch: WoolPatch

      init(
        pixels: [UInt32], width: Int, height: Int, columns: Range<Int>, rows: Range<Int>,
        wool: [UInt32], patch: WoolPatch
      ) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.wool = wool
        self.patch = patch
      }

      var byteCount: Int { (pixels.count + wool.count) * MemoryLayout<UInt32>.stride }

      @inline(__always)
      func pixel(x: Int, y: Int) -> UInt32 {
        if columns.contains(x), rows.contains(y) {
          return pixels[(y - rows.lowerBound) * columns.count + x - columns.lowerBound]
        }
        return wool[patch.sampleIndex(atX: x, y: y)]
      }
    }

    private final class Frame {
      let image: CGImage
      init(_ image: CGImage) { self.image = image }
    }

    /// NSCache protects entries. A separate lock per rig key coalesces misses
    /// while allowing unrelated frames and textures to render concurrently.
    private final class Cache<Value: AnyObject>: @unchecked Sendable {
      private let entries = NSCache<NSString, Value>()
      private let registryLock = NSLock()
      private var keyLocks: [String: NSLock] = [:]

      init(megabytes: Int) {
        entries.totalCostLimit = megabytes * 1024 * 1024
      }

      func value(for name: String, make: () -> (Value, Int)?) -> Value? {
        let key = name as NSString
        if let value = entries.object(forKey: key) { return value }

        let keyLock = registryLock.withLock {
          if let lock = keyLocks[name] { return lock }
          let lock = NSLock()
          keyLocks[name] = lock
          return lock
        }
        return keyLock.withLock {
          if let value = entries.object(forKey: key) { return value }
          guard let (value, cost) = make() else { return nil }
          entries.setObject(value, forKey: key, cost: cost)
          return value
        }
      }
    }

    private static let textures = Cache<Texture>(megabytes: 32)
    private static let renderedFrames = Cache<Frame>(megabytes: 20)
    private static let sourceURLs: [String: URL] = Dictionary(uniqueKeysWithValues:
      Set(CharacterFullBodyCatArtwork.assets.map(\.name)).compactMap { name in
        guard let url = try? CharacterPackageResource.url(named: name, fileExtension: "png") else { return nil }
        return (name, url)
      })
    private static let rig: [String: [[Layer]]] = {
      guard let data = try? CharacterPackageResource.data(
        named: "full-body-cat-motion-rig", fileExtension: "json")
      else { return [:] }
      return (try? JSONDecoder().decode([String: [[Layer]]].self, from: data)) ?? [:]
    }()

    static func isGenerated(_ name: String) -> Bool { request(named: name) != nil }

    static func hasSource(named name: String) -> Bool {
      guard let layers = layers(named: name), !layers.isEmpty else { return false }
      return layers.allSatisfy { layer in
        layer.paths.contains { $0.count >= 6 && $0.count.isMultiple(of: 2) }
          && hasSource(for: layer.a) && (layer.b.map { hasSource(for: $0) } ?? true)
      }
    }

    private static func hasSource(for mapping: Mapping) -> Bool {
      let parts = TextureParts(stem: mapping.asset)
      return mapping.hasCoordinates && sourceURL(stem: parts.body) != nil
        && (parts.behind.map { sourceURL(stem: $0) != nil } ?? true)
        && (parts.inFront.map { sourceURL(stem: $0) != nil } ?? true)
    }

    static func prepareForInteractivePlayback() {
      guard !Task.isCancelled else { return }
      let layers = rig.values.joined().joined()
      let sources = Set(layers.flatMap { [$0.a.asset, $0.b?.asset].compactMap { $0 } })
      // The standing materials are visible in the first frames of most routes.
      let standing = ["stand-combined", "stand-tail", "stand"]
      let preparation = standing.filter { sources.contains($0) } + sources.subtracting(standing).sorted()
      for asset in preparation {
        if Task.isCancelled { return }
        _ = texture(stem: asset)
      }

      // Render only the entry frame of each route to prime the mask sampler
      // off the main thread. The rest are still generated on demand.
      for route in rig.keys.sorted() {
        if Task.isCancelled { return }
        _ = image(named: "\(namePrefix)\(route)-1")
      }
    }

    private static func request(named name: String) -> (route: String, frame: Int)? {
      guard name.hasPrefix(namePrefix) else { return nil }
      let suffix = name.dropFirst(namePrefix.count)
      guard let separator = suffix.lastIndex(of: "-"),
        let frame = Int(suffix[suffix.index(after: separator)...]),
        (1...11).contains(frame),
        suffix[suffix.index(after: separator)...] == String(frame)
      else { return nil }
      let route = suffix[..<separator]
      guard !route.isEmpty, route.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
      return (String(route), frame)
    }

    private static func layers(named name: String) -> [Layer]? {
      guard let (route, index) = request(named: name),
        let frames = rig[route], frames.indices.contains(index - 1)
      else { return nil }
      return frames[index - 1]
    }

    static func image(named name: String) -> CGImage? {
      guard let layers = layers(named: name) else { return nil }
      return renderedFrames.value(for: name) {
        guard let image = render(layers: layers) else { return nil }
        return (Frame(image), pixelSize * pixelSize * 4)
      }?.image
    }

    private static func render(layers: [Layer]) -> CGImage? {
      guard !layers.isEmpty else { return nil }
      var pixels = [UInt32](repeating: 0, count: pixelSize * pixelSize)
      for layer in layers {
        guard let mask = mask(paths: layer.paths), let a = layer.a.sampler,
          let aTexture = texture(stem: layer.a.asset)
        else { return nil }
        if let second = layer.b {
          guard let b = second.sampler, let bTexture = texture(stem: second.asset) else { return nil }
          paint(mask, using: a, aTexture, blending: b, bTexture, mix: layer.mix ?? 0, into: &pixels)
        } else {
          paint(mask, using: a, aTexture, blending: nil, nil, mix: 0, into: &pixels)
        }
      }

      let bytes = pixels.withUnsafeBytes { Data($0) }
      guard let provider = CGDataProvider(data: bytes as CFData),
        let image = CGImage(
          width: pixelSize, height: pixelSize, bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: pixelSize * 4, space: colorSpace, bitmapInfo: bitmapInfo,
          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
      else { return nil }
      return image
    }

    static func png(named name: String) throws -> Data {
      guard let image = image(named: name) else {
        throw CharacterImageResolutionError.unavailable(name: name, source: .package)
      }
      let data = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
      else { throw CharacterImageResolutionError.invalidPNG(name: name) }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else {
        throw CharacterImageResolutionError.invalidPNG(name: name)
      }
      return data as Data
    }

    private struct Mask {
      let coverage: [UInt8]
      let x: Int
      let y: Int
      let width: Int
      let height: Int
    }

    private static func mask(paths: [[Int]]) -> Mask? {
      let outlines = CGMutablePath()
      for points in paths where points.count >= 6 && points.count.isMultiple(of: 2) {
        outlines.move(to: CGPoint(x: CGFloat(points[0]) / 16, y: CGFloat(points[1]) / 16))
        for index in stride(from: 2, to: points.count, by: 2) {
          outlines.addLine(to: CGPoint(
            x: CGFloat(points[index]) / 16, y: CGFloat(points[index + 1]) / 16))
        }
        outlines.closeSubpath()
      }
      guard !outlines.isEmpty else { return nil }
      let density = CGFloat(Float(pixelSize) / stageSize)
      let bounds = outlines.boundingBoxOfPath
      let x = max(0, Int(floor(bounds.minX * density)) - 1)
      let y = max(0, Int(floor(bounds.minY * density)) - 1)
      let width = min(pixelSize, Int(ceil(bounds.maxX * density)) + 1) - x
      let height = min(pixelSize, Int(ceil(bounds.maxY * density)) + 1) - y
      guard width > 0, height > 0 else { return nil }
      let rowBytes = (width + 15) & ~15
      var coverage = [UInt8](repeating: 0, count: rowBytes * height)
      let success = coverage.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(
          data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return false }
        context.translateBy(x: -CGFloat(x), y: CGFloat(y + height))
        context.scaleBy(x: density, y: -density)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(outlines)
        context.drawPath(using: .eoFill)
        return true
      }
      guard success else { return nil }
      return .init(coverage: coverage, x: x, y: y, width: width, height: height)
    }

    private static func texture(stem: String) -> Texture? {
      textures.value(for: stem) {
        guard let texture = makeTexture(stem: stem) else { return nil }
        return (texture, texture.byteCount)
      }
    }

    private struct TextureParts {
      let body: String
      let behind: String?
      let inFront: String?

      init(stem: String) {
        switch stem {
        case "stand-combined": (body, behind, inFront) = ("stand", "stand-tail", nil)
        case "wave-combined": (body, behind, inFront) = ("wave", nil, "wave-paw")
        default: (body, behind, inFront) = (stem, nil, nil)
        }
      }
    }

    private static func makeTexture(stem: String) -> Texture? {
      let parts = TextureParts(stem: stem)
      guard let base = source(stem: parts.body) else { return nil }
      let width = base.width
      let height = base.height
      let area = CGRect(x: 0, y: 0, width: width, height: height)
      var pixels = [UInt32](repeating: 0, count: width * height)
      let success = pixels.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(
          data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        else { return false }
        if let behind = parts.behind {
          guard let image = source(stem: behind) else { return false }
          context.draw(image, in: area)
        }
        context.draw(base, in: area)
        if let inFront = parts.inFront {
          guard let image = source(stem: inFront) else { return false }
          context.draw(image, in: area)
        }
        return true
      }
      guard success else { return nil }
      return extendOpaqueWool(in: pixels, width: width, height: height)
    }

    private static func sourceURL(stem: String) -> URL? {
      sourceURLs["full-body-cat-\(stem)"]
    }

    private static func source(stem: String) -> CGImage? {
      guard let url = sourceURL(stem: stem),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
      else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private struct WoolPatch {
      let x: Int
      let y: Int
      let size: Int

      private func mirrored(_ position: Int) -> Int {
        let period = max(1, 2 * size - 2)
        let remainder = (position % period + period) % period
        return min(remainder, period - remainder)
      }

      func sampleIndex(atX x: Int, y: Int) -> Int {
        mirrored(y - x / 5) * size + mirrored(x + y / 3)
      }
    }

    /// Reflects fibres just beyond the opaque edge. Farther outside, a nearby
    /// sample of the original wool prevents a repeated edge pixel from streaking.
    private static func extendOpaqueWool(in pixels: [UInt32], width: Int, height: Int) -> Texture? {
      var nearest = [Int32](repeating: -1, count: pixels.count)
      var square = [Int](repeating: 0, count: width + 1)
      let patchLimit = min(48, min(width, height))
      var patch = WoolPatch(x: 0, y: 0, size: 0)
      var patchDistance = Int.max
      var minOpaqueX = width
      var maxOpaqueX = -1
      var minOpaqueY = height
      var maxOpaqueY = -1
      for row in 0..<height {
        var columnOnWool = -1
        var upperLeft = 0
        for x in 0..<width {
          let p = row * width + x
          let previousWidth = square[x + 1]
          if pixels[p] >> 24 == 255 {
            if columnOnWool == -1 {
              minOpaqueX = min(minOpaqueX, x)
              minOpaqueY = min(minOpaqueY, row)
              maxOpaqueY = row
            }
            columnOnWool = x
            let span = min(patchLimit, min(upperLeft, min(square[x], previousWidth)) + 1)
            square[x + 1] = span
            let dx = x - span / 2 - width / 2
            let dy = row - span / 2 - height * 2 / 3
            let distance = dx * dx + dy * dy
            if span > patch.size || (span == patch.size && distance < patchDistance) {
              patch = WoolPatch(x: x - span + 1, y: row - span + 1, size: span)
              patchDistance = distance
            }
          } else {
            square[x + 1] = 0
          }
          upperLeft = previousWidth
          if columnOnWool >= 0 { nearest[p] = Int32(columnOnWool) }
        }
        guard columnOnWool >= 0 else { continue }
        maxOpaqueX = max(maxOpaqueX, columnOnWool)
        columnOnWool = -1
        for x in stride(from: width - 1, through: 0, by: -1) {
          let p = row * width + x
          if pixels[p] >> 24 == 255 { columnOnWool = x }
          if columnOnWool >= 0 && (nearest[p] < 0 || columnOnWool - x < x - Int(nearest[p])) {
            nearest[p] = Int32(columnOnWool)
          }
        }
      }
      guard patch.size > 0 else { return nil }

      // Pixels outside the reflection halo use the wool patch regardless of
      // which edge sample is nearest. Keep them virtual so all prepared poses
      // can share the bounded material cache.
      let radius = 24
      let reflectX = max(0, minOpaqueX - radius + 1)..<min(width, maxOpaqueX + radius)
      let reflectY = max(0, minOpaqueY - radius + 1)..<min(height, maxOpaqueY + radius)
      var cropped = [UInt32](repeating: 0, count: reflectX.count * reflectY.count)
      var wool = [UInt32]()
      wool.reserveCapacity(patch.size * patch.size)
      for y in patch.y..<(patch.y + patch.size) {
        let first = y * width + patch.x
        wool.append(contentsOf: pixels[first..<(first + patch.size)])
      }

      // A per-column distance transform chooses among the nearest solid samples
      // on each row. Its lower envelope avoids a search for every transparent pixel.
      var rows = [Int](repeating: 0, count: height)
      var intersections = [Float](repeating: 0, count: height + 1)
      for x in reflectX {
        var top = -1
        intersections[0] = -.infinity
        for y in minOpaqueY...maxOpaqueY {
          let sampleX = Int(nearest[y * width + x])
          if sampleX < 0 || abs(sampleX - x) >= radius { continue }
          let dx = sampleX - x
          var crossing: Float = -.infinity
          while top >= 0 {
            let previousY = rows[top]
            let previousX = Int(nearest[previousY * width + x])
            let oldDX = previousX - x
            crossing = Float(dx * dx + y * y - oldDX * oldDX - previousY * previousY)
              / Float(2 * (y - previousY))
            if crossing > intersections[top] { break }
            top -= 1
          }
          top += 1
          rows[top] = y
          intersections[top] = top == 0 ? -.infinity : crossing
          intersections[top + 1] = .infinity
        }
        var candidate = 0
        for y in reflectY {
          let p = y * width + x
          let offset = (y - reflectY.lowerBound) * reflectX.count + x - reflectX.lowerBound
          if pixels[p] >> 24 == 255 {
            cropped[offset] = pixels[p]
            continue
          }
          let patchPixel = wool[patch.sampleIndex(atX: x, y: y)]
          guard top >= 0 else {
            cropped[offset] = patchPixel
            continue
          }
          while intersections[candidate + 1] < Float(y) { candidate += 1 }
          let sourceY = rows[candidate]
          let sourceX = Int(nearest[sourceY * width + x])
          let dx = x - sourceX
          let dy = y - sourceY
          let distanceSquared = dx * dx + dy * dy
          if distanceSquared >= radius * radius {
            cropped[offset] = patchPixel
            continue
          }

          let reflectedX = sourceX - dx
          let reflectedY = sourceY - dy
          let reflectedIsOpaque = (0..<width).contains(reflectedX) && (0..<height).contains(reflectedY)
            && nearest[reflectedY * width + reflectedX] == Int32(reflectedX)
          let edgePixel = reflectedIsOpaque
            ? pixels[reflectedY * width + reflectedX] : pixels[sourceY * width + sourceX]
          let patchWeight = max(0, (sqrt(Float(distanceSquared)) - 4) / 20)
          let edge = rgb(edgePixel)
          cropped[offset] = composite(edge + (rgb(patchPixel) - edge) * patchWeight, coverage: 255, over: 0)
        }
      }
      return Texture(
        pixels: cropped, width: width, height: height, columns: reflectX, rows: reflectY,
        wool: wool, patch: patch)
    }

    private static func paint(
      _ mask: Mask, using a: Sampler, _ aTexture: Texture,
      blending b: Sampler?, _ bTexture: Texture?, mix: Float, into pixels: inout [UInt32]
    ) {
      let weight = min(1, max(0, mix))
      let pointPerPixel = stageSize / Float(pixelSize)
      let rowBytes = (mask.width + 15) & ~15
      for y in 0..<mask.height {
        let screenY = (Float(mask.y + y) + 0.5) * pointPerPixel
        for x in 0..<mask.width {
          let coverage = UInt32(mask.coverage[y * rowBytes + x])
          if coverage == 0 { continue }
          let screenX = (Float(mask.x + x) + 0.5) * pointPerPixel
          var color = sample(aTexture, at: a.source(x: screenX, y: screenY))
          if weight > 0, let b, let bTexture {
            let second = sample(bTexture, at: b.source(x: screenX, y: screenY))
            color += (second - color) * weight
          }
          let index = (mask.y + y) * pixelSize + mask.x + x
          pixels[index] = composite(color, coverage: coverage, over: pixels[index])
        }
      }
    }

    @inline(__always)
    private static func sample(_ texture: Texture, at point: SIMD2<Float>) -> SIMD3<Float> {
      let x = min(Float(texture.width - 1), max(0, point.x * Float(texture.width) / stageSize - 0.5))
      let y = min(Float(texture.height - 1), max(0, point.y * Float(texture.height) / stageSize - 0.5))
      let x0 = Int(x)
      let y0 = Int(y)
      let x1 = min(x0 + 1, texture.width - 1)
      let y1 = min(y0 + 1, texture.height - 1)
      let tx = x - Float(x0)
      let ty = y - Float(y0)
      let topLeft = rgb(texture.pixel(x: x0, y: y0))
      let bottomLeft = rgb(texture.pixel(x: x0, y: y1))
      let top = topLeft + (rgb(texture.pixel(x: x1, y: y0)) - topLeft) * tx
      let bottom = bottomLeft + (rgb(texture.pixel(x: x1, y: y1)) - bottomLeft) * tx
      return top + (bottom - top) * ty
    }

    // Byte-order-32-big Core Graphics pixels are RGBA in memory on Apple hosts.
    @inline(__always)
    private static func rgb(_ pixel: UInt32) -> SIMD3<Float> {
      .init(Float(pixel & 255), Float((pixel >> 8) & 255), Float((pixel >> 16) & 255))
    }

    @inline(__always)
    private static func composite(_ color: SIMD3<Float>, coverage: UInt32, over old: UInt32) -> UInt32 {
      let red = UInt32(color.x + 0.5)
      let green = UInt32(color.y + 0.5)
      let blue = UInt32(color.z + 0.5)
      if coverage == 255 { return red | (green << 8) | (blue << 16) | (255 << 24) }
      let reverse = 255 - coverage
      let outR = (red * coverage + (old & 255) * reverse + 127) / 255
      let outG = (green * coverage + ((old >> 8) & 255) * reverse + 127) / 255
      let outB = (blue * coverage + ((old >> 16) & 255) * reverse + 127) / 255
      let outA = coverage + ((old >> 24) * reverse + 127) / 255
      return outR | (outG << 8) | (outB << 16) | (outA << 24)
    }
  }
#endif

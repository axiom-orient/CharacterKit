#if os(iOS) || os(macOS)
  import Foundation
  import ImageIO
  import UniformTypeIdentifiers

  enum CharacterGIFSetError: Error, Sendable, Equatable {
    case missingEmotion(CharacterEmotion)
    case invalidNeutral
    case invalidGIF(CharacterEmotion)
    case frameUnavailable(CharacterEmotion, Int)
    case budgetExceeded
  }

  /// Immutable compressed sources and a shared neutral image. View-owned caches
  /// retain decoded frames; this resource boundary never owns semantic state.
  @MainActor
  final class CharacterGIFSet {
    static let norwegianForest: Result<CharacterGIFSet, Error> = Result {
      func data(_ name: String, _ extensionName: String) throws -> Data {
        try CharacterPackageResource.data(named: name, fileExtension: extensionName)
      }
      let neutral = try data("norwegian-neutral", "png")
      let clips = try Dictionary(uniqueKeysWithValues: CharacterEmotion.allCases.map {
        ($0, try data("norwegian-\($0.rawValue)", "gif"))
      })
      return try CharacterGIFSet(neutralData: neutral, emotionGIFs: clips)
    }

    struct Clip {
      let source: CGImageSource
      let durations: [Double]
      let duration: Double
    }

    let neutral: CGImage
    private let clips: [CharacterEmotion: Clip]

    init(neutralData: Data, emotionGIFs: [CharacterEmotion: Data]) throws {
      guard neutralData.count <= 8_388_608,
        let source = CGImageSourceCreateWithData(neutralData as CFData, nil),
        let neutral = CGImageSourceCreateImageAtIndex(source, 0, nil),
        neutral.width > 0, neutral.height > 0,
        neutral.width <= 4096, neutral.height <= 4096
      else { throw CharacterGIFSetError.invalidNeutral }

      var clips: [CharacterEmotion: Clip] = [:]
      var totalBytes = neutralData.count
      for emotion in CharacterEmotion.allCases {
        guard let data = emotionGIFs[emotion] else {
          throw CharacterGIFSetError.missingEmotion(emotion)
        }
        totalBytes += data.count
        guard data.count <= 4_194_304, totalBytes <= 16_777_216 else {
          throw CharacterGIFSetError.budgetExceeded
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetType(source) as String? == UTType.gif.identifier
        else { throw CharacterGIFSetError.invalidGIF(emotion) }
        let count = CGImageSourceGetCount(source)
        guard (2...64).contains(count),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 4096, height <= 4096,
          width == neutral.width, height == neutral.height,
          width * height <= 16_777_216 / count
        else { throw CharacterGIFSetError.invalidGIF(emotion) }
        var durations: [Double] = []
        for index in 0..<count {
          guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let frameWidth = props[kCGImagePropertyPixelWidth] as? Int,
            let frameHeight = props[kCGImagePropertyPixelHeight] as? Int,
            frameWidth == width, frameHeight == height
          else { throw CharacterGIFSetError.invalidGIF(emotion) }
          let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
          let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
          guard delay.isFinite, delay > 0, delay <= 2 else {
            throw CharacterGIFSetError.invalidGIF(emotion)
          }
          durations.append(delay)
        }
        let duration = durations.reduce(0, +)
        guard duration <= 30 else { throw CharacterGIFSetError.invalidGIF(emotion) }
        clips[emotion] = Clip(source: source, durations: durations, duration: duration)
      }
      self.neutral = neutral
      self.clips = clips
    }

    func duration(for emotion: CharacterEmotion) -> Double { clips[emotion]?.duration ?? 0 }

    /// Resolves only the current clip, keeping decoded-frame memory bounded.
    func image(for emotion: CharacterEmotion, elapsed: Double, reduceMotion: Bool,
      cache: CharacterGIFFrameCache? = nil) throws -> CGImage? {
      guard let clip = clips[emotion], elapsed >= 0, elapsed < clip.duration else { return nil }
      let index: Int
      if reduceMotion {
        index = clip.durations.count / 2
      } else {
        var cursor = 0.0
        var selected = clip.durations.count - 1
        for (i, duration) in clip.durations.enumerated() {
          cursor += duration
          if elapsed < cursor { selected = i; break }
        }
        index = selected
      }
      if let cached = cache?.image(emotion: emotion, index: index) { return cached }
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let frame = CGImageSourceCreateImageAtIndex(clip.source, index, options) else {
        throw CharacterGIFSetError.frameUnavailable(emotion, index)
      }
      cache?.insert(frame, emotion: emotion, index: index)
      return frame
    }
  }

  /// A view-owned decode cache: independent characters never evict each other's frames.
  @MainActor
  final class CharacterGIFFrameCache {
    private var emotion: CharacterEmotion?
    private var frames: [Int: CGImage] = [:]

    func image(emotion: CharacterEmotion, index: Int) -> CGImage? {
      self.emotion == emotion ? frames[index] : nil
    }

    func insert(_ image: CGImage, emotion: CharacterEmotion, index: Int) {
      if self.emotion != emotion {
        frames.removeAll(keepingCapacity: true)
        self.emotion = emotion
      }
      frames[index] = image
    }
  }
#endif

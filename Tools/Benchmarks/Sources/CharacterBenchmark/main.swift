import Foundation
import ReactiveCharacterKit

/// Measures SDK CPU work and offline export, not display FPS or animation hitches.
@main @MainActor
struct CharacterBenchmark {
  struct Statistics: Codable {
    let samples: Int
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let p99Milliseconds: Double
    let checksum: Int
  }
  struct Report: Codable {
    let operatingSystem: String
    let processorCount: Int
    let scenario: String
    let oneCharacterPipeline: Statistics
    let tenCharacterPipeline: Statistics
    let svgExport: Statistics
    let nativePNGExport: Statistics?
  }
  enum BenchmarkError: Error { case invalidArguments }

  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      let iterations: Int
      if arguments.isEmpty {
        iterations = 500
      } else if arguments.count == 2, arguments[0] == "--iterations",
        let count = Int(arguments[1]), (50...5_000).contains(count) {
        iterations = count
      } else {
        throw BenchmarkError.invalidArguments
      }
      let direction = CharacterArtDirection.semiDocumentCat
      let states = CharacterEmotion.allCases.map {
        ReactiveCharacter.act(state: .idle, event: .emotionChanged($0)).stateAfter
      }
      func frame(_ index: Int) throws -> CharacterScene {
        let pose = ReactiveCharacter.pose(
          state: states[index % states.count], elapsed: Double(index) / 60,
          artDirection: direction)
        return try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction,
          width: 200, height: 200, includeBackground: false)
      }
      // Warm lazy geometry/resource initialization outside the timed samples.
      for index in 0..<20 { _ = try frame(index) }
      let one = try measure(iterations: iterations) { index in try frame(index).nodes.count }
      let ten = try measure(iterations: iterations) { index in
        var count = 0
        for character in 0..<10 { count += try frame(index + character).nodes.count }
        return count
      }
      let scene = try frame(47)
      _ = try CharacterSVGRenderer.render(scene)
      let svg = try measure(iterations: min(iterations, 100)) { _ in
        try CharacterSVGRenderer.render(scene).utf8.count
      }
      let native: Statistics?
      #if os(macOS)
      _ = try CharacterScenePNGRenderer.render(scene)
      native = try measure(iterations: 30) { _ in
        try autoreleasepool { try CharacterScenePNGRenderer.render(scene).count }
      }
      #else
      native = nil
      #endif
      let report = Report(
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        processorCount: ProcessInfo.processInfo.activeProcessorCount,
        scenario: "Warm release build, 200pt SEMI, 12 emotions; pose + scene validation. Batch of ten excludes UI/GPU work.",
        oneCharacterPipeline: one, tenCharacterPipeline: ten,
        svgExport: svg, nativePNGExport: native)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      FileHandle.standardOutput.write(try encoder.encode(report))
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("CharacterBenchmark: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func measure(
    iterations: Int, operation: (Int) throws -> Int
  ) rethrows -> Statistics {
    let clock = ContinuousClock()
    var milliseconds: [Double] = []
    var checksum = 0
    for index in 0..<iterations {
      let start = clock.now
      checksum += try operation(index)
      let elapsed = start.duration(to: clock.now).components
      milliseconds.append(Double(elapsed.seconds) * 1_000
        + Double(elapsed.attoseconds) / 1_000_000_000_000_000)
    }
    milliseconds.sort()
    func percentile(_ fraction: Double) -> Double {
      milliseconds[min(iterations - 1, Int(ceil(Double(iterations) * fraction)) - 1)]
    }
    return Statistics(
      samples: iterations, p50Milliseconds: percentile(0.50),
      p95Milliseconds: percentile(0.95), p99Milliseconds: percentile(0.99), checksum: checksum)
  }
}

import Foundation
import ReactiveCharacterKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A local consumer of the real public SDK. It exports frames, never reimplements a renderer.
@main @MainActor
struct CharacterPreview {
  struct Frame: Codable {
    let path: String
    let time: Double
    let label: String
  }
  struct Group: Codable {
    let id: String
    let label: String
    let kind: String
    let frames: [Frame]
  }
  enum PreviewError: LocalizedError {
    case invalidArguments
    case nativeRendererUnavailable
    case outputParentUnavailable(String)
    case outputPathNotDirectory(String)
    case outputDirectoryNotEmpty(String)

    var errorDescription: String? {
      switch self {
      case .invalidArguments:
        "Invalid arguments. Use --output <directory> [--native-png]."
      case .nativeRendererUnavailable:
        "Native PNG rendering is available only on Apple platforms."
      case .outputParentUnavailable(let path):
        "Output directory parent does not exist or is not a directory: \(path)"
      case .outputPathNotDirectory(let path):
        "Output path exists and is not a directory: \(path)"
      case .outputDirectoryNotEmpty(let path):
        "Output directory must be empty: \(path)"
      }
    }
  }

  static func main() {
    do { try export() }
    catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      FileHandle.standardError.write(Data("CharacterPreview: \(message)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  /// Accept only a new directory or an existing empty one. Returning true means this
  /// invocation created the directory and may remove it later if export fails.
  private static func prepareOutputDirectory(at output: URL) throws -> Bool {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else {
        throw PreviewError.outputPathNotDirectory(output.path)
      }
      guard try fileManager.contentsOfDirectory(atPath: output.path).isEmpty else {
        throw PreviewError.outputDirectoryNotEmpty(output.path)
      }
      return false
    }

    let parent = output.deletingLastPathComponent()
    var parentIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
          parentIsDirectory.boolValue
    else {
      throw PreviewError.outputParentUnavailable(parent.path)
    }
    try fileManager.createDirectory(at: output, withIntermediateDirectories: false)
    return true
  }

  private static func export() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let native = arguments.last == "--native-png"
    if native { arguments.removeLast() }
    guard arguments.count == 2, arguments[0] == "--output" else {
      FileHandle.standardError.write(Data(
        "Usage: swift run --package-path Tools/Preview CharacterPreview --output <directory> [--native-png]\n".utf8))
      throw PreviewError.invalidArguments
    }
    #if !(os(iOS) || os(macOS))
    guard !native else { throw PreviewError.nativeRendererUnavailable }
    #endif
    let output = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let createdOutputDirectory = try prepareOutputDirectory(at: output)
    var generatedFiles: [URL] = []
    var exportSucceeded = false
    defer {
      if !exportSucceeded {
        let fileManager = FileManager.default
        for file in generatedFiles.reversed() {
          var isDirectory: ObjCBool = false
          guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory) else { continue }
          guard !isDirectory.boolValue else {
            FileHandle.standardError.write(Data(
              "CharacterPreview: Preserving unexpected directory at generated file path \(file.path)\n".utf8))
            continue
          }
          do {
            try fileManager.removeItem(at: file)
          } catch {
            FileHandle.standardError.write(Data(
              "CharacterPreview: Could not remove generated file \(file.path): \(error.localizedDescription)\n".utf8))
          }
        }
        if createdOutputDirectory {
          let result = output.path.withCString { rmdir($0) }
          if result != 0 && errno != ENOENT {
            FileHandle.standardError.write(Data(
              "CharacterPreview: Could not remove empty output directory \(output.path): \(String(cString: strerror(errno)))\n".utf8))
          }
        }
      }
    }
    let directions: [(String, CharacterArtDirection)] = [
      ("semi", .semiDocumentCat), ("black", .black), ("white", .white), ("arcade", .arcade), ("cat", .cat),
      ("cat-simple", .catSimple2D),
      ("portrait", .portrait), ("girl", CharacterPortraitStyle.bobGirl.artDirection),
      ("flower-girl", CharacterPortraitStyle.flowerGirl.artDirection),
      ("boy", CharacterPortraitStyle.shortHairBoy.artDirection),
      ("capped-boy", CharacterPortraitStyle.cappedBoy.artDirection),
      ("boy-three-quarter", CharacterPortraitStyle.boy(viewpoint: .threeQuarterRight).artDirection),
    ]
    func save(_ pose: CharacterPose, direction: CharacterArtDirection, filename: String,
      title: String, prefix: String, time: Double) throws -> Frame {
      let scene = try CharacterSceneBuilder.scene(pose: pose, artDirection: direction,
        width: 320, height: 320, includeBackground: false)
      let path = filename + (native ? ".png" : ".svg")
      let destination = output.appendingPathComponent(path)
      generatedFiles.append(destination)
      if native {
        #if os(iOS) || os(macOS)
        try CharacterScenePNGRenderer.render(scene, scale: 2).write(
          to: destination, options: .atomic)
        #endif
      } else {
        let svg = try CharacterSVGRenderer.render(scene, title: title, idPrefix: prefix)
        try svg.write(to: destination, atomically: true, encoding: .utf8)
      }
      return Frame(path: path, time: time, label: title)
    }
    let task = try CharacterTaskID(validating: "preview-task")
    var started = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: task)).stateAfter
    started = ReactiveCharacter.act(state: started, event: .agentProgress(taskID: task, progress: 0.42)).stateAfter
    var states: [(String, CharacterState)] = [("idle", .idle), ("writing", started)]
    states += CharacterEmotion.allCases.map { emotion in
      (emotion.rawValue, ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter)
    }
    var groups: [Group] = []
    for (name, direction) in directions {
      var frames: [Frame] = []
      for (label, state) in states {
        let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8,
          artDirection: direction)
        frames.append(try save(pose, direction: direction, filename: "\(name)-\(label)",
          title: "\(name) · \(label)", prefix: "\(name)-\(label)", time: 0.8))
      }
      groups.append(Group(id: name, label: name, kind: "emotions", frames: frames))
    }
    let direction = CharacterArtDirection.semiDocumentCat
    var idleFrames: [Frame] = []
    for index in 0...144 {
      let time = Double(index) / 24
      idleFrames.append(try save(
        ReactiveCharacter.pose(state: .idle, elapsed: time, artDirection: direction),
        direction: direction, filename: "idle-\(index)", title: "SEMI idle · \(time)",
        prefix: "idle-\(index)", time: time))
    }
    groups.append(Group(id: "idle-motion", label: "SEMI · relaxed extended whiskers",
      kind: "motion", frames: idleFrames))
    // SEMI-focused acting review. These are consumers of the existing state/pose path, not
    // separate animation state. They make expression holds and communication cadence visible.
    for emotion in [CharacterEmotion.joy, .gratitude, .interest, .calmTrust,
      .sadness, .anxietyFear, .surprise, .fatigueBurden] {
      let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
      var frames: [Frame] = []
      for index in 0...72 {
        let time = Double(index) / 24
        let pose = ReactiveCharacter.pose(state: state, elapsed: time,
          artDirection: direction)
        frames.append(try save(pose, direction: direction,
          filename: "acting-\(emotion.rawValue)-\(index)", title: "\(emotion.rawValue) · \(time)",
          prefix: "acting-\(emotion.rawValue)-\(index)", time: time))
      }
      groups.append(Group(id: "acting-\(emotion.rawValue)", label: "SEMI · \(emotion.rawValue)",
        kind: "motion", frames: frames))
    }

    let speaking = ReactiveCharacter.act(state: .idle, event: .chatStarted).stateAfter
    var speakingFrames: [Frame] = []
    for index in 0...96 {
      let time = Double(index) / 24
      let pose = ReactiveCharacter.pose(state: speaking, elapsed: time,
        artDirection: direction)
      speakingFrames.append(try save(pose, direction: direction,
        filename: "speaking-\(index)", title: "SEMI speaking · \(time)",
        prefix: "speaking-\(index)", time: time))
    }
    groups.append(Group(id: "speaking", label: "SEMI · natural speaking loop",
      kind: "motion", frames: speakingFrames))

    let speakingBlinkID = try CharacterAnimationID(validating: "preview-speaking-blink")
    let speakingWithBlink = ReactiveCharacter.act(state: speaking,
      event: .animationStarted(id: speakingBlinkID, animation: .blink)).stateAfter
    var speakingBlinkFrames: [Frame] = []
    for index in 0...18 {
      let time = Double(index) / 60
      let pose = ReactiveCharacter.pose(state: speakingWithBlink, elapsed: time,
        artDirection: direction)
      speakingBlinkFrames.append(try save(pose, direction: direction,
        filename: "speaking-blink-\(index)", title: "SEMI speaking + blink · \(time)",
        prefix: "speaking-blink-\(index)", time: time))
    }
    groups.append(Group(id: "speaking-blink", label: "SEMI · speaking + blink independence",
      kind: "motion", frames: speakingBlinkFrames))

    for animation in CharacterAnimation.allCases {
      let id = try CharacterAnimationID(validating: "preview-\(animation.rawValue)")
      let state = ReactiveCharacter.act(state: .idle, event: .animationStarted(id: id, animation: animation)).stateAfter
      var frames: [Frame] = []
      let count = Int(ceil((animation.duration + 0.15) * 24))
      var samples = (0...count).map { Double($0) / 24 }
      // Include the blink curve peak so the review shows its actual closed frame.
      if animation == .blink { samples.append(0.025 + 0.18 * 0.40); samples.sort() }
      for (index, time) in samples.enumerated() {
        let pose = ReactiveCharacter.pose(state: state, elapsed: time,
          artDirection: direction)
        frames.append(try save(pose, direction: direction,
          filename: "motion-\(animation.rawValue)-\(index)", title: animation.rawValue,
          prefix: "motion-\(animation.rawValue)-\(index)", time: time))
      }
      groups.append(Group(id: "motion-\(animation.rawValue)", label: animation.rawValue,
        kind: "motion", frames: frames))
    }
    // A real reducer/session trace: late task progress cannot resurrect a cancelled task.
    let events: [(Double, CharacterEvent)] = [
      (0, .agentStarted(taskID: task)), (0.5, .agentProgress(taskID: task, progress: 0.12)),
      (1.1, .agentProgress(taskID: task, progress: 0.72)), (1.5, .emotionChanged(.joy)),
      (2, .voiceStarted), (2.2, .voiceLevelChanged(0.85)), (2.8, .communicationEnded),
      (3.1, .agentCancellationRequested(taskID: task)), (3.4, .agentCancelled(taskID: task)),
      (3.8, .agentProgress(taskID: task, progress: 0.95)), (4.2, .reset),
    ]
    var state = CharacterState.idle
    var session = CharacterPresentationSession()
    var eventIndex = 0
    var caption = "idle"
    var lifecycle: [Frame] = []
    for index in 0...120 {
      let time = Double(index) / 24
      while eventIndex < events.count, events[eventIndex].0 <= time {
        let (eventTime, event) = events[eventIndex]
        let receipt = ReactiveCharacter.act(state: state, event: event,
          transitionProfile: direction.transitionProfile)
        state = receipt.stateAfter
        caption = "\(event) → \(receipt.disposition)"
        session.update(state: state, at: eventTime, projection: direction.projection,
          motionProfile: direction.motionProfile, transitionProfile: direction.transitionProfile)
        eventIndex += 1
      }
      let pose = session.pose(at: time, projection: direction.projection, motionProfile: direction.motionProfile)
      lifecycle.append(try save(pose, direction: direction, filename: "lifecycle-\(index)",
        title: caption, prefix: "lifecycle-\(index)", time: time))
    }
    groups.append(Group(id: "lifecycle", label: "Task → emotion → speech → cancellation → stale result",
      kind: "motion", frames: lifecycle))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifest = output.appendingPathComponent("index.json")
    generatedFiles.append(manifest)
    try encoder.encode(groups).write(to: manifest, options: .atomic)
    exportSucceeded = true
    print("Exported \(groups.reduce(0) { $0 + $1.frames.count }) \(native ? "native PNG" : "SVG") frames to \(output.path)")
  }
}

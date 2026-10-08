import Foundation
import ReactiveCharacterKit

@main
struct CharacterPreview {
  static func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 2, args[0] == "--output" else {
      throw PreviewError.usage
    }
    let output = URL(fileURLWithPath: args[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    var states: [(String, CharacterState)] = [("idle", .idle)]
    states += CharacterEmotion.allCases.map { emotion in
      (emotion.rawValue, ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state)
    }
    let voice = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state
    states.append(("voice", voice))

    for (name, state) in states {
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8)
      let scene = try CharacterSceneBuilder.scene(pose: pose, width: 320, height: 320)
      let svg = try CharacterSVGRenderer.render(scene, title: "SEMI · \(name)", idPrefix: name)
      try svg.write(
        to: output.appendingPathComponent("semi-\(name).svg"),
        atomically: true,
        encoding: .utf8
      )
    }
  }

  enum PreviewError: Error { case usage }
}

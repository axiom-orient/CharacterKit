import Foundation
import XCTest
@testable import ReactiveCharacterKit

final class CharacterSEMITests: XCTestCase {
  private let direction = CharacterArtDirection.semiDocumentCat
  private func state(_ events: [CharacterEvent]) -> CharacterState {
    events.reduce(.idle) { ReactiveCharacter.act(state: $0, event: $1).stateAfter }
  }
  private func pose(_ state: CharacterState = .idle, time: Double = 0.8,
    reduced: Bool = false) -> CharacterPose {
    ReactiveCharacter.pose(state: state, elapsed: time, reduceMotion: reduced,
      projection: direction.projection, motionProfile: direction.motionProfile)
  }
  private func scene(_ pose: CharacterPose, direction: CharacterArtDirection? = nil,
    width: Double = 320, height: Double = 320) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(pose: pose, artDirection: direction ?? self.direction,
      width: width, height: height, includeBackground: false)
  }
  private func node(_ id: String, in scene: CharacterScene) throws -> CharacterSceneNode {
    try XCTUnwrap(scene.nodes.first { $0.id == id }, id)
  }

  private func mouthNodes(_ scene: CharacterScene) -> [CharacterSceneNode] {
    scene.nodes.filter { $0.id.hasPrefix("mouth") }
  }

  private func assertSEMIMouthPresent(_ scene: CharacterScene,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let mouth = mouthNodes(scene)
    XCTAssertFalse(mouth.isEmpty, file: file, line: line)
    for id in ["mouth.lips", "mouth.philtrum", "mouth.whiskers"] {
      XCTAssertNotNil(scene.nodes.first { $0.id == id }, id, file: file, line: line)
    }
    let head = try XCTUnwrap(scene.nodes.first { $0.id == "semi.head" }, file: file, line: line)
    for feature in mouth {
      XCTAssertNil(feature.fill, "\(feature.id) must remain an unfilled line", file: file, line: line)
      XCTAssertNotNil(feature.stroke, "\(feature.id) must use a stroke", file: file, line: line)
      XCTAssertFalse(feature.path.commands.isEmpty, "\(feature.id) must have geometry", file: file, line: line)
      if let first = feature.path.commands.first {
        if case .move = first {} else {
          XCTFail("\(feature.id) must start with a move", file: file, line: line)
        }
      }
      XCTAssertFalse(feature.path.commands.contains(.close), "\(feature.id) must remain open", file: file, line: line)
      XCTAssertTrue(feature.clips.isEmpty, "\(feature.id) cannot clip a cavity", file: file, line: line)
      XCTAssertEqual(feature.transform, head.transform, "\(feature.id) must share the head transform", file: file, line: line)
    }
    for retiredID in ["mouth.opening", "mouth.tongue", "mouth.lowerLip"] {
      XCTAssertFalse(scene.nodes.contains { $0.id == retiredID }, "\(retiredID) is not part of the stroke-only mouth", file: file, line: line)
    }
  }

  private func pathBounds(_ node: CharacterSceneNode) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var xs: [Double] = []
    var ys: [Double] = []
    let t = node.transform
    func collect(_ p: CharacterVectorPoint) {
      xs.append(t.a * p.x + t.c * p.y + t.tx)
      ys.append(t.b * p.x + t.d * p.y + t.ty)
    }
    for command in node.path.commands {
      switch command {
      case .move(let p), .line(let p):
        collect(p)
      case .quad(let c, let p):
        collect(c); collect(p)
      case .cubic(let c1, let c2, let p):
        collect(c1); collect(c2); collect(p)
      case .close:
        break
      }
    }
    return (xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
  }

  func testPublicSelectionUsesExistingThemeAndAnatomyPipeline() {
    XCTAssertEqual(CharacterTheme.semi.artDirection, direction)
    XCTAssertEqual(CharacterTheme(rawValue: "semi"), .semi)
    XCTAssertEqual(direction.anatomy, .semiDocumentCat)
    XCTAssertEqual(direction.components, .default.union([.nose, .writing]))
    XCTAssertEqual(direction.motionProfile, .cartoon)
    XCTAssertEqual(direction.transitionProfile, .cartoon)
    XCTAssertEqual(direction.contentInset, CharacterArtDirection.canonicalContentInset)
  }

  func testSingleCharacterSceneEntryPointRetainsSEMICompatibility() throws {
    let sample = ReactiveCharacter.pose(state: .idle, elapsed: 0.8, artDirection: direction)
    let compatibility = try CharacterSceneBuilder.scene(pose: sample, width: 320, height: 320)
    let explicit = try CharacterSceneBuilder.scene(
      pose: sample, artDirection: direction, width: 320, height: 320,
      includeBackground: false)
    XCTAssertEqual(compatibility, explicit)
  }

  func testResourceCatalogIsExactAndRegistrationIs512Pixels() throws {
    let actual = try scene(pose())
    XCTAssertEqual(Set(actual.nodes.compactMap { $0.image?.asset }), Set(direction.requiredImageAssets))
    XCTAssertEqual(direction.requiredImageAssets.count, 6)
    for asset in direction.requiredImageAssets {
      let bytes = Array(try CharacterImageResources.png(asset))
      XCTAssertGreaterThan(bytes.count, 1024)
      XCTAssertEqual(Array(bytes.prefix(8)), [137,80,78,71,13,10,26,10])
      XCTAssertEqual(Array(bytes[16..<24]), [0,0,2,0,0,0,2,0], asset.name)
    }
  }

  func testTwelveEmotionsHaveDistinctLiveFacesAndNoExpressionBitmaps() throws {
    var faces: [[CharacterSceneNode]] = []
    let assets = Set(direction.requiredImageAssets)
    for emotion in CharacterEmotion.allCases {
      let actual = try scene(pose(state([.emotionChanged(emotion)])))
      let face = actual.nodes.filter { $0.id.hasPrefix("eye.") || $0.id.hasPrefix("mouth") }
      XCTAssertFalse(face.isEmpty)
      try assertSEMIMouthPresent(actual)
      XCTAssertFalse(faces.contains(face), "Emotion must remain distinguishable: \(emotion)")
      faces.append(face)
      XCTAssertEqual(Set(actual.nodes.compactMap { $0.image?.asset }), assets)
    }
    XCTAssertEqual(faces.count, 12)
  }

  func testEveryOneShotSamplesActualMotionWithoutNewSemanticState() throws {
    for animation in CharacterAnimation.allCases {
      let id = try CharacterAnimationID(validating: "semi-\(animation.rawValue)")
      let input = state([.animationStarted(id: id, animation: animation)])
      let before = ReactiveCharacter.inspect(state: input)
      let frames = try [0.0,0.06,0.12,0.24,0.4,0.7,1.2,2.0].map { try scene(pose(input, time: $0)) }
      XCTAssertTrue(frames.dropFirst().contains { $0 != frames[0] }, animation.rawValue)
      XCTAssertEqual(ReactiveCharacter.inspect(state: input), before)
      XCTAssertEqual(input.animation?.id, id)
      for frame in frames {
        try assertSEMIMouthPresent(frame)
        try CharacterSceneValidation.validate(frame)
      }
    }
  }

  func testBuiltInMotionKeepsSEMIVisibleVectorPartsInsideViewport() throws {
    for animation in CharacterAnimation.allCases {
      let id = try CharacterAnimationID(validating: "bounds-\(animation.rawValue)")
      let input = state([.animationStarted(id: id, animation: animation)])
      for index in 0...120 {
        let time = (animation.duration + 0.15) * Double(index) / 120
        let frame = try scene(pose(input, time: time))
        try assertSEMIMouthPresent(frame)
        for node in frame.nodes where node.id.hasPrefix("semi.") && node.image == nil {
          for command in node.path.commands {
            let points: [CharacterVectorPoint]
            switch command {
            case .move(let p), .line(let p): points = [p]
            case .quad(let c, let p): points = [c, p]
            case .cubic(let c1, let c2, let p): points = [c1, c2, p]
            case .close: points = []
            }
            let t = node.transform
            for p in points {
              let x = t.a * p.x + t.c * p.y + t.tx
              let y = t.b * p.x + t.d * p.y + t.ty
              XCTAssertTrue((0...frame.width).contains(x) && (0...frame.height).contains(y),
                "\(animation) at \(time): \(node.id) overflows (\(x), \(y))")
            }
          }
        }
      }
    }
  }

  func testEveryPupilAndHighlightUseTheLiveApertureClip() throws {
    for emotion in CharacterEmotion.allCases {
      let actual = try scene(pose(state([.emotionChanged(emotion)])))
      for side in ["left", "right"] {
        let id = "eye.\(side)"
        if let pupil = actual.nodes.first(where: { $0.id == id + ".pupil" }) {
          let aperture = try node(id, in: actual)
          XCTAssertEqual(pupil.clips, [aperture.path])
          XCTAssertEqual(pupil.transform, aperture.transform)
          let highlight = try node(id + ".highlight", in: actual)
          XCTAssertEqual(highlight.clips, [aperture.path, pupil.path])
        }
      }
    }
  }

  func testBlinkActuallyClosesBothEyesAndHidesPupils() throws {
    let id = try CharacterAnimationID(validating: "blink")
    let input = state([.animationStarted(id: id, animation: .blink)])
    var closed = false
    // Include the actual shared curve peak, not merely samples bracketing it.
    let times = (0...48).map { Double($0) * 0.005 } + [0.025 + 0.18 * 0.40]
    for time in times {
      let p = pose(input, time: time)
      let frame = try scene(p)
      if p.eyes.left.blink > 0.999, p.eyes.right.blink > 0.999 {
        closed = true
        XCTAssertFalse(frame.nodes.contains { $0.id.hasSuffix(".pupil") })
        XCTAssertEqual(try node("eye.left", in: frame).stroke, direction.style.partColors.eyes)
        XCTAssertEqual(try node("eye.right", in: frame).stroke, direction.style.partColors.eyes)
      }
    }
    XCTAssertTrue(closed, "The shared blink must reach closed geometry")
  }

  func testSilentRestAndListeningKeepReadableMouthFamily() throws {
    for input in [CharacterState.idle, state([.listeningStarted, .listeningLevelChanged(1)])] {
      let frame = try scene(pose(input))

      try assertSEMIMouthPresent(frame)
      XCTAssertFalse(frame.nodes.contains { $0.id.hasPrefix("semi.writing.") })
      XCTAssertNotNil(frame.nodes.first { $0.id == "semi.document" })
    }
  }

  func testVoiceLevelChangesOnlyClosedMouthLinesAndPreservesDocument() throws {
    let silentLevel = state([.voiceStarted, .voiceLevelChanged(0)])
    let loudLevel = state([.voiceStarted, .voiceLevelChanged(1)])
    let a = try scene(pose(silentLevel)), b = try scene(pose(loudLevel))

    try assertSEMIMouthPresent(a)
    try assertSEMIMouthPresent(b)
    XCTAssertNotEqual(try node("mouth.lips", in: a).path, try node("mouth.lips", in: b).path)
    XCTAssertEqual(try node("semi.document", in: a).path, try node("semi.document", in: b).path)
  }

  func testVoiceStagesProgressThroughClosedMouthFamily() throws {
    let levels: [Double] = [0.30, 0.60, 1.0]
    for frame in try levels.map({ try scene(pose(state([.voiceStarted, .voiceLevelChanged($0)]))) }) {
      try assertSEMIMouthPresent(frame)
    }
  }

  func testReducedCalmTrustKeepsSoftSmileWithMouthAnchors() throws {
    let frame = try scene(pose(state([.emotionChanged(.calmTrust)]), reduced: true))

    try assertSEMIMouthPresent(frame)
    XCTAssertNotNil(frame.nodes.first { $0.id == "eye.left.closed" || $0.id == "eye.left" })
  }

  func testSpeechAndSurpriseKeepStrokeOnlyMouthWithoutChangingDocumentArtwork() throws {
    let surprise = try scene(pose(state([.emotionChanged(.surprise)])))
    let speech = try scene(pose(state([.voiceStarted, .voiceLevelChanged(0.8)])))

    try assertSEMIMouthPresent(surprise)
    try assertSEMIMouthPresent(speech)
    XCTAssertEqual(try node("semi.document", in: surprise).image, try node("semi.document", in: speech).image)
  }


  func testSurpriseAndLoudSpeechUseClosedMouthLineFamily() throws {
    for frame in [try scene(pose(state([.emotionChanged(.surprise)]))),
                  try scene(pose(state([.voiceStarted, .voiceLevelChanged(1)])))] {

      try assertSEMIMouthPresent(frame)
    }
  }

  func testJoyAndGratitudeKeepDistinctClosedLipContours() throws {
    let joy = try scene(pose(state([.emotionChanged(.joy)])))
    let gratitude = try scene(pose(state([.emotionChanged(.gratitude)])))
    try assertSEMIMouthPresent(joy)
    try assertSEMIMouthPresent(gratitude)
    let joyLips = try node("mouth.lips", in: joy)
    let gratitudeLips = try node("mouth.lips", in: gratitude)
    XCTAssertEqual(joyLips.path.commands.count, 3)
    XCTAssertEqual(gratitudeLips.path.commands.count, 3)
    XCTAssertNotEqual(joyLips.path, gratitudeLips.path)
  }

  func testJoyAndGratitudeKeepSoftMouthAcrossHold() throws {
    for emotion in [CharacterEmotion.joy, .gratitude] {
      let input = state([.emotionChanged(emotion)])
      for index in 0...48 {
        let frame = try scene(pose(input, time: Double(index) / 24))
        try assertSEMIMouthPresent(frame, file: #filePath, line: UInt(index + 1))
      }
    }
  }

  func testSpeakingBlinkKeepsOneMouthFamily() throws {
    let speaking = state([.chatStarted])
    let blinkID = try CharacterAnimationID(validating: "speaking-blink")
    let speakingBlink = state([.chatStarted, .animationStarted(id: blinkID, animation: .blink)])
    for time in [0.05, 0.08, 0.10, 0.13, 0.17] {
      let plain = try scene(pose(speaking, time: time))
      let blinking = try scene(pose(speakingBlink, time: time))
      try assertSEMIMouthPresent(plain)
      try assertSEMIMouthPresent(blinking)
    }
  }

  func testSpeakingLoopKeepsOneCleanMouthFamily() throws {
    let speaking = state([.chatStarted])
    for index in 0...96 {
      let frame = try scene(pose(speaking, time: Double(index) / 24))

      try assertSEMIMouthPresent(frame)
    }
  }

  func testWritingProgressIsNotAnAnimationPhaseOrDuplicateGenericPen() throws {
    let task = try CharacterTaskID(validating: "writing")
    let input = state([.agentStarted(taskID: task), .agentProgress(taskID: task, progress: 0.42)])
    let a = try scene(pose(input, time: 0.1)), b = try scene(pose(input, time: 0.8))
    try assertSEMIMouthPresent(a)
    try assertSEMIMouthPresent(b)
    XCTAssertEqual(try node("semi.writing.progress", in: a).path, try node("semi.writing.progress", in: b).path)
    XCTAssertNotEqual(try node("semi.writing.pencil", in: a).path, try node("semi.writing.pencil", in: b).path)
    XCTAssertNotEqual(try node("semi.paw.right", in: a).transform, try node("semi.paw.right", in: b).transform)
    XCTAssertFalse(a.nodes.contains { $0.id == "writing" || $0.id == "writing.progress" })
    XCTAssertEqual(input.communication, .silent)
    let result = ReactiveCharacter.act(state: input, event: .agentSucceeded(taskID: task)).stateAfter
    let complete = try scene(pose(result))
    XCTAssertFalse(complete.nodes.contains { $0.id.hasPrefix("semi.writing.") })
    XCTAssertNotNil(complete.nodes.first { $0.id == "semi.document" })
  }

  func testPartColorsChangeLiveFeaturesNotAuthoredFurOrSemanticState() throws {
    let input = state([.emotionChanged(.angerIrritation)])
    let pink = try CharacterColor(red: 0.9, green: 0.3, blue: 0.4)
    let colors = direction.style.partColors.replacing(eyes: pink, nose: pink, mouth: pink,
      writing: pink, accessory: pink, accessoryDetail: pink, outline: pink)
    let custom = direction.replacingPartColors(colors)
    let a = try scene(pose(input)), b = try scene(pose(input), direction: custom)
    XCTAssertEqual(a.nodes.map(\.path), b.nodes.map(\.path))
    XCTAssertEqual(a.nodes.compactMap(\.image), b.nodes.compactMap(\.image))
    XCTAssertEqual(try node("nose", in: b).fill, .solid(pink))
    XCTAssertEqual(try node("eye.left.pupil", in: b).fill, .solid(pink))
    XCTAssertEqual(input.emotion, .angerIrritation)
  }

  func testSurfaceAndComponentsDoNotLeaveHiddenResourcesOrParts() throws {
    let hidden = try CharacterArtDirection(name: "SEMI face only", components: [.eyes],
      style: .semiDocumentCat, surface: .transparent, anatomy: .semiDocumentCat)
    let frame = try scene(pose(), direction: hidden)
    XCTAssertTrue(hidden.requiredImageAssets.isEmpty)
    XCTAssertTrue(frame.nodes.allSatisfy { $0.id.hasPrefix("eye.") && $0.image == nil })
    let empty = try CharacterArtDirection(name: "SEMI none", components: [],
      style: .semiDocumentCat, surface: .transparent, anatomy: .semiDocumentCat)
    XCTAssertTrue(try scene(pose(), direction: empty).nodes.isEmpty)
  }

  func testEyesRespectTreatmentWithoutChangingEmotionsOrAssets() throws {
    let input = state([.emotionChanged(.surprise)])
    let p = pose(input)
    let vertical = try scene(p)
    let horizontal = try scene(p, direction: direction.replacingFaceTreatment(eyes: .horizontal))
    XCTAssertNotEqual(try node("eye.left", in: vertical).path, try node("eye.left", in: horizontal).path)
    XCTAssertEqual(vertical.nodes.compactMap(\.image), horizontal.nodes.compactMap(\.image))
    XCTAssertEqual(input.emotion, .surprise)
  }

  func testGazeMovesPupilsAndNoseThroughOnePose() throws {
    let left = state([.attentionFocused(try .init(validatingX: 0, y: 0.5))])
    let right = state([.attentionFocused(try .init(validatingX: 1, y: 0.5))])
    let a = try scene(pose(left)), b = try scene(pose(right))
    XCTAssertNotEqual(try node("eye.left.pupil", in: a).path, try node("eye.left.pupil", in: b).path)
    XCTAssertNotEqual(try node("nose", in: a).path, try node("nose", in: b).path)
  }

  func testAllEmotionsRemainStaticWithReduceMotionAtOrdinaryTimes() throws {
    for emotion in CharacterEmotion.allCases {
      let input = state([.emotionChanged(emotion)])
      let early = try scene(pose(input, time: 3, reduced: true))
      let late = try scene(pose(input, time: 18, reduced: true))
      try assertSEMIMouthPresent(early)
      try assertSEMIMouthPresent(late)
      XCTAssertEqual(early, late, emotion.rawValue)
    }
  }

  func testExtremeFiniteTimesAndAspectRatiosProduceValidDeterministicScenes() throws {
    for emotion in CharacterEmotion.allCases {
      let input = state([.emotionChanged(emotion)])
      for time in [0.0, 0.8, Double.greatestFiniteMagnitude] {
        for size in [(1.0,1.0),(48,64),(160,320),(512,128),(16_384,16_384)] {
          let p = pose(input, time: time)
          let frame = try scene(p, width: size.0, height: size.1)
          try assertSEMIMouthPresent(frame)
          try CharacterSceneValidation.validate(frame)
          XCTAssertEqual(frame, try scene(p, width: size.0, height: size.1))
        }
      }
    }
  }

  func testInterruptedSessionPreservesCurrentStateAndSharedOwnership() throws {
    let task = try CharacterTaskID(validating: "task")
    var input = state([.agentStarted(taskID: task)])
    for reduceMotion in [false, true] {
      input = state([.agentStarted(taskID: task)])
      var session = CharacterPresentationSession(state: input, at: 0)
      for (index, event) in [CharacterEvent.emotionChanged(.joy), .voiceStarted,
        .voiceLevelChanged(0.6), .communicationEnded, .agentCancellationRequested(taskID: task),
        .agentCancelled(taskID: task)].enumerated() {
        input = ReactiveCharacter.act(state: input, event: event).stateAfter
        let time = Double(index) * 0.11 + 0.1
        session.update(state: input, at: time, reduceMotion: reduceMotion,
          projection: direction.projection, motionProfile: direction.motionProfile,
          transitionProfile: direction.transitionProfile)
        for offset in [0.0,0.02,0.05] {
          let p = session.pose(at: time + offset, reduceMotion: reduceMotion,
            projection: direction.projection, motionProfile: direction.motionProfile)
          let frame = try scene(p)
          try assertSEMIMouthPresent(frame)
          try CharacterSceneValidation.validate(frame)
        }
        XCTAssertEqual(session.inspect(at: time).state, input)
      }
    }
  }

  func testSVGIncludesActualTexturesWithoutRemoteOrScriptContent() throws {
    let frame = try scene(pose(state([.emotionChanged(.joy)])))
    let svg = try CharacterSVGRenderer.render(frame, title: "SEMI <preview>", idPrefix: "semi")
    XCTAssertTrue(svg.contains("data:image/png;base64,"))
    XCTAssertFalse(svg.contains("<script"))
    XCTAssertFalse(svg.contains("<image href=\"https:"))
    XCTAssertTrue(svg.contains("SEMI &lt;preview&gt;"))
    XCTAssertEqual(svg, try CharacterSVGRenderer.render(frame, title: "SEMI <preview>", idPrefix: "semi"))
  }


  func testExpressionProjectionMovesHeadEarsTailAcrossEmotions() throws {
    let neutral = try scene(pose())
    let joy = try scene(pose(state([.emotionChanged(.joy)])))
    let surprise = try scene(pose(state([.emotionChanged(.surprise)])))
    let fatigue = try scene(pose(state([.emotionChanged(.fatigueBurden)])))

    XCTAssertNotEqual(try node("semi.head", in: neutral).transform,
      try node("semi.head", in: joy).transform)
    XCTAssertNotEqual(try node("semi.head", in: joy).transform,
      try node("semi.head", in: surprise).transform)
    XCTAssertNotEqual(try node("semi.ear.left", in: neutral).transform,
      try node("semi.ear.left", in: fatigue).transform)
    XCTAssertNotEqual(try node("semi.tail", in: neutral).transform,
      try node("semi.tail", in: surprise).transform)
  }

  func testVoiceLoopAlsoDrivesBodyActingWithMouth() throws {
    let input = state([.chatStarted])
    let early = try scene(pose(input, time: 0.04))
    let late = try scene(pose(input, time: 0.38))
    try assertSEMIMouthPresent(early)
    try assertSEMIMouthPresent(late)
    XCTAssertNotEqual(try node("semi.head", in: early).transform,
      try node("semi.head", in: late).transform)
    XCTAssertNotEqual(try node("semi.tail", in: early).transform,
      try node("semi.tail", in: late).transform)
  }

  func testGratitudeSadnessAndFatigueHaveDistinctBodyActing() throws {
    let gratitude = try scene(pose(state([.emotionChanged(.gratitude)]), time: 0.8))
    let sadness = try scene(pose(state([.emotionChanged(.sadness)]), time: 0.8))
    let fatigue = try scene(pose(state([.emotionChanged(.fatigueBurden)]), time: 0.8))
    XCTAssertNotEqual(try node("semi.head", in: gratitude).transform,
      try node("semi.head", in: sadness).transform)
    XCTAssertNotEqual(try node("semi.ear.left", in: sadness).transform,
      try node("semi.ear.left", in: fatigue).transform)
    XCTAssertNotEqual(try node("semi.tail", in: sadness).transform,
      try node("semi.tail", in: fatigue).transform)
  }

  func testSpeakingAndListeningUseDistinctMouthLoops() throws {
    let speaking = state([.chatStarted])
    let listening = state([.listeningStarted, .listeningLevelChanged(0.8)])
    for time in [0.3, 1.34, 2.55] {
      let speak = try scene(pose(speaking, time: time))
      let listen = try scene(pose(listening, time: time))
      try assertSEMIMouthPresent(speak)
      try assertSEMIMouthPresent(listen)
      XCTAssertNotEqual(try node("semi.head", in: speak).transform,
        try node("semi.head", in: listen).transform)
      XCTAssertNotEqual(try node("eye.left", in: speak).transform,
        try node("eye.left", in: listen).transform)
    }
  }

  func testPainterOrderKeepsEarRootsBehindHeadAndPawsOverDocument() throws {
    let frame = try scene(pose())
    let ids = frame.nodes.map(\.id)
    for side in ["left", "right"] {
      XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "semi.ear.\(side).root")),
        try XCTUnwrap(ids.firstIndex(of: "semi.head")))
      XCTAssertGreaterThan(try XCTUnwrap(ids.firstIndex(of: "semi.paw.\(side)")),
        try XCTUnwrap(ids.firstIndex(of: "semi.document")))
    }
    XCTAssertEqual(frame.nodes.map { $0.layer.rawValue }, frame.nodes.map { $0.layer.rawValue }.sorted())
  }

  func testSceneRejectsNoncanonicalPainterOrderInsteadOfBackendDisagreement() throws {
    let valid = try scene(pose())
    let invalid = CharacterScene(width: valid.width, height: valid.height, faceBounds: valid.faceBounds,
      surfaceTransform: valid.surfaceTransform, nodes: valid.nodes.reversed(),
      effectiveMode: valid.effectiveMode, isCompact: valid.isCompact)
    XCTAssertThrowsError(try CharacterSceneValidation.validate(invalid))
    XCTAssertThrowsError(try CharacterSVGRenderer.render(invalid))
  }
}

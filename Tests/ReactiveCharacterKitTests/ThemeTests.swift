import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class ThemeTests: XCTestCase {
  func testBuiltInCatalogIsDeliberatelySmall() {
    XCTAssertEqual(
      CharacterTheme.allCases.map(\.rawValue),
      ["black", "white", "arcade", "cat"])
    XCTAssertNil(CharacterTheme(rawValue: "saffron"))
    XCTAssertEqual(CharacterTheme.black.artDirection, .black)
  }

  func testBlackIsAProceduralMonochromeSurfaceWithRimFitHeadset() {
    let direction = CharacterTheme.black.artDirection
    XCTAssertNil(direction.assets.background)
    XCTAssertNil(direction.assets.face)
    XCTAssertEqual(
      direction.assets.accessories.map(\.image.name), ["headset-black"])
    XCTAssertEqual(direction.layout, .standard)
    XCTAssertEqual(direction.featureGlow, 0)
    XCTAssertEqual(direction.ornamentGlow, 0)
  }

  func testBuiltInThemesShareOneCanonicalFaceFrame() throws {
    let directions = CharacterTheme.allCases.map(\.artDirection)
    XCTAssertEqual(
      Set(directions.map(\.contentInset)),
      Set([CharacterArtDirection.canonicalContentInset]),
      "Theme color/artwork may change, but the canonical face board may not resize"
    )

    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    let expectedSide = 320 * (1 - 2 * CharacterArtDirection.canonicalContentInset)
    for direction in directions {
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 320, height: 320)
      XCTAssertEqual(scene.faceBounds.width, expectedSide, accuracy: 0.000_001)
      XCTAssertEqual(scene.faceBounds.height, expectedSide, accuracy: 0.000_001)
      XCTAssertEqual(
        scene.faceBounds.x, 320 * CharacterArtDirection.canonicalContentInset,
        accuracy: 0.000_001)
      XCTAssertEqual(
        scene.faceBounds.y, 320 * CharacterArtDirection.canonicalContentInset,
        accuracy: 0.000_001)
    }
  }

  func testBlackKeepsHeadsetOnTheFaceRimAndFeaturesCrisp() throws {
    let direction = CharacterTheme.black.artDirection
    XCTAssertEqual(
      direction.assets.accessories.map(\.layer), [.behindFeatures])

    let state = ReactiveCharacter.act(
      state: .idle, event: .emotionChanged(.joy)
    ).stateAfter
    let pose = ReactiveCharacter.pose(
      state: state, elapsed: 0.8, motionProfile: direction.motionProfile)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 320, height: 320)

    XCTAssertFalse(
      scene.nodes.contains { node in
        node.id.hasPrefix("eye.near") || node.id.hasPrefix("eye.far")
      })
    XCTAssertTrue(scene.nodes.contains { $0.id == "eye.left" })
    XCTAssertTrue(scene.nodes.contains { $0.id == "eye.right" })
    XCTAssertTrue(scene.nodes.contains { $0.id == "mouth" })

    let idle = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: direction, width: 320, height: 320)
    let headsetNode = try XCTUnwrap(idle.nodes.first { $0.id == "art.accessory.0" })
    XCTAssertEqual(headsetNode.image?.asset, .blackHeadset)
    let headsetBounds = try XCTUnwrap(headsetNode.image?.bounds)
    let attachmentScale = CharacterBuiltInAccessoryCatalog.headsetAttachmentScale
    XCTAssertEqual(
      headsetBounds.width, idle.faceBounds.width * attachmentScale, accuracy: 0.000_001)
    XCTAssertEqual(
      headsetBounds.height, idle.faceBounds.height * attachmentScale, accuracy: 0.000_001)
    XCTAssertGreaterThan(
      headsetBounds.width, idle.faceBounds.width,
      "The worn headset outer envelope must exceed the face diameter")
    XCTAssertGreaterThanOrEqual(
      headsetBounds.x, 0,
      "Headset envelope must remain inside the scene viewport")
    XCTAssertLessThanOrEqual(
      headsetBounds.x + headsetBounds.width, idle.width,
      "Headset envelope must remain inside the scene viewport")
    XCTAssertLessThanOrEqual(
      headsetBounds.x,
      idle.faceBounds.x - idle.faceBounds.width * (attachmentScale - 1) / 2 + 0.000_001,
      "Earcups must wrap outside the left face contour")
    XCTAssertGreaterThanOrEqual(
      headsetBounds.x + headsetBounds.width,
      idle.faceBounds.x + idle.faceBounds.width
        + idle.faceBounds.width * (attachmentScale - 1) / 2 - 0.000_001,
      "Earcups must wrap outside the right face contour")
    XCTAssertFalse(
      idle.nodes.contains { $0.id.hasPrefix("mouth") },
      "neutral silent face must not render a rest mouth")
  }

  func testBlackAgentWritingCreatesAndThenHidesOutputMouthWave() throws {
    let direction = CharacterTheme.black.artDirection
    let task = try CharacterTaskID(validating: "black-output")
    let started = ReactiveCharacter.reduce(
      state: .idle, event: .agentStarted(taskID: task)
    ).state
    let writing = ReactiveCharacter.reduce(
      state: started, event: .agentProgress(taskID: task, progress: 0.4)
    ).state
    let writingPose = ReactiveCharacter.pose(
      state: writing, elapsed: 0.4, reduceMotion: true,
      projection: direction.projection, motionProfile: direction.motionProfile)
    XCTAssertEqual(
      writing.communication, .silent,
      "output mouth must not fake a host chat/voice state")
    XCTAssertTrue(writingPose.mouth.visible)
    XCTAssertEqual(writingPose.mouth.glyph, .speechWave)
    let writingScene = try CharacterSceneBuilder.scene(
      pose: writingPose, artDirection: direction, width: 320, height: 320)
    XCTAssertTrue(writingScene.nodes.contains { $0.id == "mouth" })
    XCTAssertTrue(writingScene.nodes.contains { $0.id == "mouth.wave" })

    let finished = ReactiveCharacter.reduce(
      state: writing, event: .agentSucceeded(taskID: task)
    ).state
    let finishedPose = ReactiveCharacter.pose(
      state: finished, elapsed: 0.4, reduceMotion: true,
      projection: direction.projection, motionProfile: direction.motionProfile)
    XCTAssertFalse(finishedPose.mouth.visible)
    let finishedScene = try CharacterSceneBuilder.scene(
      pose: finishedPose, artDirection: direction, width: 320, height: 320)
    XCTAssertFalse(finishedScene.nodes.contains { $0.id.hasPrefix("mouth") })
  }

  func testMinimalThemesKeepTheRoundedFaceContract() {
    let directions = [CharacterTheme.black, .white, .arcade].map(\.artDirection)
    XCTAssertTrue(directions.allSatisfy { $0.assets.face == nil && $0.assets.background == nil })
    XCTAssertEqual(
      Set(directions.flatMap { $0.assets.accessories.map(\.image.name) }),
      ["headset-black", "headset-white", "headset-arcade"])
    for direction in directions {
      XCTAssertEqual(direction.layout, .standard)
      XCTAssertEqual(direction.projection, .softSphere)
      XCTAssertTrue(direction.components.contains(.eyes))
      XCTAssertTrue(direction.components.contains(.mouth))
      XCTAssertTrue(direction.components.contains(.writing))
      XCTAssertFalse(direction.components.contains(.nose))
      XCTAssertFalse(direction.components.contains(.ornaments))
    }
    XCTAssertEqual(
      Set(directions.map(\.contentInset)), [CharacterArtDirection.canonicalContentInset])
    XCTAssertEqual(directions.map(\.assets), [.black, .white, .arcade])
    XCTAssertNotEqual(directions[0].style, directions[1].style)
    XCTAssertNotEqual(directions[1].style, directions[2].style)
  }

  func testEveryThemeResourceExistsAndSVGExportUsesOnlySelectedPack() throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0)
    for theme in CharacterTheme.allCases {
      let direction = theme.artDirection
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 160, height: 160)
      let actual = Set(scene.nodes.compactMap { $0.image?.asset.name })
      let expected = Set(direction.requiredImageAssets.map(\.name))
      XCTAssertEqual(actual, expected)
      XCTAssertTrue(try CharacterSVGRenderer.render(scene).contains("data:image/png;base64,"))
      for node in scene.nodes {
        if let image = node.image {
          XCTAssertGreaterThan(try CharacterImageResources.png(image.asset).count, 24)
        }
      }
    }
  }

  func testThemeChangeDuringTaskAndSpeechPreservesAllSemanticState() throws {
    let id = try CharacterTaskID(validating: "preserve")
    var state = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: id)).stateAfter
    for event in [
      CharacterEvent.agentProgress(taskID: id, progress: 0.4), .emotionChanged(.joy), .voiceStarted,
      .voiceLevelChanged(0.7),
    ] {
      state = ReactiveCharacter.act(state: state, event: event).stateAfter
    }
    var session = CharacterPresentationSession(state: state, at: 0)
    let expected = ReactiveCharacter.inspect(state: state)
    for theme in CharacterTheme.allCases + CharacterTheme.allCases.reversed() {
      session.reconcilePresentationConfigurationChange(at: 1)
      let direction = theme.artDirection
      let pose = session.pose(
        at: 1, projection: direction.projection, motionProfile: direction.motionProfile)
      _ = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 160, height: 160)
      XCTAssertEqual(session.inspect(at: 1).state, state)
      XCTAssertEqual(ReactiveCharacter.inspect(state: state), expected)
    }
  }

  func testThemeReplacementDuringHandoffDropsOnlyCapturedBridge() {
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(.joy)).stateAfter
    var session = CharacterPresentationSession(at: 0)
    session.update(state: state, at: 1)
    XCTAssertGreaterThan(session.inspect(at: 1).remainingHandoffDuration, 0)
    session.reconcilePresentationConfigurationChange(at: 1.05)
    XCTAssertEqual(session.inspect(at: 1.05).phase, .performing)
    XCTAssertEqual(session.inspect(at: 1.05).state, state)
  }

  func testEveryThemeEveryEmotionAtMultipleSizesAndAccessibilityModes() throws {
    for theme in CharacterTheme.allCases {
      let direction = theme.artDirection
      for emotion in CharacterEmotion.allCases {
        let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
        for time in [0.0, 0.15, 0.8, 4.0] {
          for reduced in [false, true] {
            let pose = ReactiveCharacter.pose(
              state: state, elapsed: time, reduceMotion: reduced, projection: direction.projection,
              motionProfile: direction.motionProfile)
            for size in [1.0, 96.0, 160.0, 320.0, 16_384.0] {
              for simplified in [false, true] {
                let scene = try CharacterSceneBuilder.scene(
                  pose: pose, artDirection: direction, width: size, height: size,
                  environment: .init(increasedContrast: simplified, reduceTransparency: simplified))
                try CharacterSceneValidation.validate(scene)
                XCTAssertTrue(scene.nodes.contains { $0.id == "eye.left" })
                XCTAssertTrue(scene.nodes.contains { $0.id == "eye.right" })
                XCTAssertFalse(scene.nodes.contains { $0.id.lowercased().contains("eyebrow") })
              }
            }
          }
        }
      }
    }
  }

  func testEveryAnimationAndCommunicationRetainAValidThemedScene() throws {
    let id = try CharacterAnimationID(validating: "theme-animation")
    for theme in CharacterTheme.allCases {
      let direction = theme.artDirection
      for event in CharacterAnimation.allCases.map({
        CharacterEvent.animationStarted(id: id, animation: $0)
      }) + [.chatStarted, .voiceStarted, .voiceLevelChanged(0.9)] {
        let initial =
          event == .voiceLevelChanged(0.9)
          ? ReactiveCharacter.act(state: .idle, event: .voiceStarted).stateAfter : .idle
        let state = ReactiveCharacter.act(state: initial, event: event).stateAfter
        for time in [0.0, 0.12, 0.4, 0.9, 2.0, 10.0] {
          let pose = ReactiveCharacter.pose(
            state: state, elapsed: time, projection: direction.projection,
            motionProfile: direction.motionProfile)
          let scene = try CharacterSceneBuilder.scene(
            pose: pose, artDirection: direction, width: 160, height: 200)
          try CharacterSceneValidation.validate(scene)
        }
      }
    }
  }

  func testCustomThemeUsesExistingArtDirectionWithoutRegistration() throws {
    let custom = try CharacterArtDirection(name: "Custom", assets: .empty)
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0), artDirection: custom, width: 160,
      height: 160)
    XCTAssertFalse(scene.nodes.contains { $0.image != nil })
    XCTAssertFalse(try CharacterSVGRenderer.render(scene).contains("data:image"))
  }

  func testMotionReplacementPreservesAllOtherThemeFields() {
    for theme in CharacterTheme.allCases {
      let direction = theme.artDirection
      let changed = direction.replacingMotionProfile(.minimal)
      XCTAssertEqual(changed.assets, direction.assets)
      XCTAssertEqual(changed.style, direction.style)
      XCTAssertEqual(changed.layout, direction.layout)
      XCTAssertEqual(changed.contentInset, direction.contentInset)
      XCTAssertEqual(changed.motionProfile, .minimal)
    }
  }
}

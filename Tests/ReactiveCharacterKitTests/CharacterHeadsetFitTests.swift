import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterHeadsetFitTests: XCTestCase {
  private func direction(headset: Bool) throws -> CharacterArtDirection {
    let base = CharacterArtDirection.black
    return try CharacterArtDirection(
      name: base.name, components: base.components, layout: base.layout, style: base.style,
      surface: base.surface, projection: base.projection, motionProfile: base.motionProfile,
      transitionProfile: base.transitionProfile,
      assets: .init(accessories: headset ? base.assets.accessories : []),
      featureGlow: base.featureGlow, ornamentGlow: base.ornamentGlow,
      contentInset: base.contentInset)
  }

  func testRimFittedHeadsetUsesCanonicalFaceEnvelope() throws {
    let spec = CharacterBuiltInAccessoryCatalog.headset(image: .blackHeadset)
    XCTAssertEqual(spec.centerX, 0.5)
    XCTAssertEqual(spec.centerY, 0.5)
    XCTAssertEqual(spec.width, CharacterBuiltInAccessoryCatalog.headsetAttachmentScale)
    XCTAssertEqual(spec.height, CharacterBuiltInAccessoryCatalog.headsetAttachmentScale)
    XCTAssertEqual(spec.followLag, 0)
    XCTAssertEqual(spec.squashRigidity, 0)

    let frame = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0), artDirection: .black,
      width: 320, height: 320, includeBackground: false)
    let headset = try XCTUnwrap(frame.nodes.first { $0.id == "art.accessory.0" })
    let bounds = try XCTUnwrap(headset.image?.bounds)
    XCTAssertEqual(bounds.width, frame.faceBounds.width * spec.width, accuracy: 0.000_001)
    XCTAssertEqual(bounds.height, frame.faceBounds.height * spec.height, accuracy: 0.000_001)
    XCTAssertEqual(
      bounds.x + bounds.width / 2, frame.faceBounds.x + frame.faceBounds.width / 2,
      accuracy: 0.000_001)
    XCTAssertEqual(
      bounds.y + bounds.height / 2, frame.faceBounds.y + frame.faceBounds.height / 2,
      accuracy: 0.000_001)
    XCTAssertEqual(headset.transform, frame.surfaceTransform)
    XCTAssertTrue(headset.clips.isEmpty)
  }

  func testHeadsetAndFaceRemainInTheSameAffineSpaceAtMotionExtremes() throws {
    let base = ReactiveCharacter.pose(state: .idle, elapsed: 0)
    for surface in [
      CharacterSurfacePose.identity,
      .init(offsetX: 0.12, offsetY: -0.10, scaleX: 1.20, scaleY: 0.80, angle: 0.30),
      .init(offsetX: -0.12, offsetY: 0.10, scaleX: 0.80, scaleY: 1.20, angle: -0.30),
      .init(scaleX: 1.40, scaleY: 0.70, angle: Double.pi * 4.25),
    ] {
      let frame = try CharacterSceneBuilder.scene(
        pose: base.replacingSurface(surface), artDirection: .black,
        width: 320, height: 320, includeBackground: false)
      let headset = try XCTUnwrap(frame.nodes.first { $0.id == "art.accessory.0" })
      XCTAssertEqual(headset.transform, frame.surfaceTransform)
    }
  }

  func testHeadsetSelectionDoesNotChangeFaceEyesMouthBlushOrWriting() throws {
    let withHeadset = try direction(headset: true)
    let withoutHeadset = try direction(headset: false)
    let task = try CharacterTaskID(validating: "headset-writing-regression")
    let animationID = try CharacterAnimationID(validating: "headset-motion-regression")
    var states = [CharacterState.idle]
    states += CharacterEmotion.allCases.map {
      ReactiveCharacter.reduce(state: .idle, event: .emotionChanged($0)).state
    }
    states.append(
      ReactiveCharacter.reduce(state: .idle, event: .userWritingBegan(focus: .center)).state)
    states.append(ReactiveCharacter.reduce(state: .idle, event: .chatStarted).state)
    let thinking = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: task)).state
    states.append(thinking)
    states.append(
      ReactiveCharacter.reduce(state: thinking, event: .agentProgress(taskID: task, progress: 0.5))
        .state)
    let voice = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state
    states.append(ReactiveCharacter.reduce(state: voice, event: .voiceLevelChanged(1)).state)
    states += CharacterAnimation.allCases.map {
      ReactiveCharacter.reduce(
        state: .idle, event: .animationStarted(id: animationID, animation: $0)
      ).state
    }
    func protected(_ frame: CharacterScene) -> [CharacterSceneNode] {
      frame.nodes.filter {
        $0.id == "surface.body" || $0.id.hasPrefix("eye") || $0.id.hasPrefix("mouth")
          || $0.id.hasPrefix("blush") || $0.id.hasPrefix("writing")
      }
    }
    for state in states {
      for reduced in [false, true] {
        for time in [0.0, 0.08, 0.22, 0.44, 0.70, 1.20] {
          let pose = ReactiveCharacter.pose(
            state: state, elapsed: time, reduceMotion: reduced, motionProfile: .cartoon)
          for size in [96.0, 160.0, 320.0] {
            let on = try CharacterSceneBuilder.scene(
              pose: pose, artDirection: withHeadset,
              width: size, height: size, includeBackground: false)
            let off = try CharacterSceneBuilder.scene(
              pose: pose, artDirection: withoutHeadset,
              width: size, height: size, includeBackground: false)
            XCTAssertEqual(on.faceBounds, off.faceBounds)
            XCTAssertEqual(on.surfaceTransform, off.surfaceTransform)
            XCTAssertFalse(protected(on).isEmpty)
            XCTAssertEqual(protected(on), protected(off))
            XCTAssertEqual(
              try XCTUnwrap(on.nodes.first { $0.id == "art.accessory.0" }).transform,
              on.surfaceTransform)
          }
        }
      }
    }
  }
}

import XCTest
@testable import ReactiveCharacterKit

final class CharacterReferenceCatEyeTests: XCTestCase {
  func testReferenceCatUsesSubtleMotionWithoutChangingMascotDefaults() {
    for variant in CharacterNorwegianVariant.allCases {
      let direction = CharacterArtDirection.reference(.norwegianForest(variant))
      XCTAssertEqual(direction.motionProfile, .companion)
      XCTAssertEqual(direction.transitionProfile, .soft)
    }
    let mascot = CharacterArtDirection.reference(.mascot(variant: .hero))
    XCTAssertEqual(mascot.motionProfile, .cartoon)
    XCTAssertEqual(mascot.transitionProfile, .cartoon)
  }

  func testAllReferenceCoatsKeepTheirAuthoredEyeSocketsDuringExpressionsAndBlink() throws {
    let blink = try CharacterAnimationID(validating: "reference-cat-blink")
    let states = [CharacterState.idle]
      + CharacterEmotion.allCases.map {
        ReactiveCharacter.reduce(state: .idle, event: .emotionChanged($0)).state
      }
      + [ReactiveCharacter.reduce(
        state: .idle, event: .animationStarted(id: blink, animation: .blink)).state]

    for variant in CharacterNorwegianVariant.allCases {
      let direction = CharacterArtDirection.reference(.norwegianForest(variant))
      let rig = CharacterReferenceAppearance.norwegianForest(variant).rig
      for state in states {
        let pose = ReactiveCharacter.pose(state: state, elapsed: 0.1, artDirection: direction)
        let scene = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: direction, width: 320, height: 320)
        for part in [CharacterReferenceRig.Part.eyeLeft, .eyeRight, .irisLeft, .irisRight] {
          let layer = try XCTUnwrap(rig.layers.first { $0.part == part })
          let node = try XCTUnwrap(scene.nodes.first { $0.id == "reference.\(part.rawValue)" })
          XCTAssertNotNil(node.image)
          XCTAssertEqual(node.opacity, 1)
          XCTAssertEqual(node.clips, [.rectangle(layer.frame)])
        }
        XCTAssertFalse(scene.nodes.contains { $0.id.hasPrefix("reference.eyeLeft.upper")
          || $0.id.hasPrefix("reference.eyeRight.upper") })
      }
    }
  }

  func testReferenceIrisStillRespondsToAttention() throws {
    let direction = CharacterArtDirection.catNorwegianForest
    let focus = try CharacterPoint(validatingX: 0.95, y: 0.5)
    let state = ReactiveCharacter.reduce(state: .idle, event: .attentionFocused(focus)).state
    func iris(_ state: CharacterState) throws -> CharacterSceneNode {
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8, artDirection: direction)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 320, height: 320)
      return try XCTUnwrap(scene.nodes.first { $0.id == "reference.irisLeft" })
    }
    XCTAssertNotEqual(try iris(.idle).image?.bounds, try iris(state).image?.bounds)
  }

  func testEyeTreatmentsChangeIrisWithoutChangingSocket() throws {
    let neutral = CharacterArtDirection.catNorwegianForest
    let rounded = neutral.replacingFaceTreatment(eyes: .round)
    func scene(_ direction: CharacterArtDirection) throws -> CharacterScene {
      let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0.8, artDirection: direction)
      return try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 320, height: 320)
    }
    let a = try scene(neutral)
    let b = try scene(rounded)
    XCTAssertEqual(a.nodes.first { $0.id == "reference.eyeLeft" },
      b.nodes.first { $0.id == "reference.eyeLeft" })
    XCTAssertNotEqual(a.nodes.first { $0.id == "reference.irisLeft" }?.transform,
      b.nodes.first { $0.id == "reference.irisLeft" }?.transform)
  }
}

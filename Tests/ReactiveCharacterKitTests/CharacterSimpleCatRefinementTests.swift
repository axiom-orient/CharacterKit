import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterSimpleCatRefinementTests: XCTestCase {
  private func points(_ path: CharacterVectorPath) -> [CharacterVectorPoint] {
    path.commands.flatMap { command -> [CharacterVectorPoint] in
      switch command {
      case .move(let p), .line(let p): [p]
      case .quad(let c, let p): [c, p]
      case .cubic(let a, let b, let p): [a, b, p]
      case .close: []
      }
    }
  }

  func testEarRootsStayInsideHeadAcrossEntireMotionEnvelope() throws {
    let head = CharacterSimpleCatGeometry.headBounds
    for left in [true, false] {
      let rest = points(CharacterSimpleCatGeometry.ear(left: left, inner: false, angle: 0))
      for angle in stride(from: -0.24, through: 0.24, by: 0.004) {
        let deformed = points(
          CharacterSimpleCatGeometry.ear(left: left, inner: false, angle: angle))
        XCTAssertEqual(deformed.first, rest.first)
        XCTAssertEqual(deformed.last, rest.last)
        for root in [try XCTUnwrap(deformed.first), try XCTUnwrap(deformed.last)] {
          let x = (root.x - head.midX) / (head.width / 2)
          let y = (root.y - head.midY) / (head.height / 2)
          XCTAssertLessThan(x * x + y * y, 0.9, "Root must have overlap, not merely touch the edge")
        }
        let next = points(
          CharacterSimpleCatGeometry.ear(left: left, inner: false, angle: angle + 0.0001))
        for (a, b) in zip(deformed, next) {
          XCTAssertLessThan(hypot(a.x - b.x, a.y - b.y), 0.025)
        }
      }
      XCTAssertNotEqual(
        rest, points(CharacterSimpleCatGeometry.ear(left: left, inner: false, angle: 0.24)))
    }
  }

  func testInnerEarUsesItsDeformedOuterMask() throws {
    for emotion in CharacterEmotion.allCases {
      let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0.52, motionProfile: .cartoon)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: .catSimple2D, width: 320, height: 320)
      for side in ["left", "right"] {
        let outer = try XCTUnwrap(scene.nodes.first { $0.id == "cat.ear.\(side)" })
        let inner = try XCTUnwrap(scene.nodes.first { $0.id == "cat.ear.\(side).inner" })
        XCTAssertEqual(inner.clips, [outer.path])
        XCTAssertEqual(inner.transform, outer.transform)
        XCTAssertEqual(inner.layer, .behindSurface)
      }
    }
  }

  func testCompactEyeUsesUnblinkedSizeAndExplicitClosure() {
    func path(height: Double, blink: Double) -> CharacterVectorPath {
      CharacterCompactEyeGeometry.path(
        eye: .init(
          centerX: 0.3, centerY: 0.5, width: 0.19, height: height,
          angle: 0, unblinkedWidth: 0.19, unblinkedHeight: 0.43, blink: blink),
        contour: .neutral, left: true, center: .init(x: 194, y: 337),
        width: 17, height: 43, treatment: .vertical, thickness: 4.5)
    }
    // Rendered source height may already contain blink; do not apply it twice.
    XCTAssertEqual(path(height: 0.43, blink: 0.5), path(height: 0.01, blink: 0.5))
    XCTAssertNotEqual(path(height: 0.43, blink: 0), path(height: 0.43, blink: 1))
    let closed = points(path(height: 0.43, blink: 1))
    XCTAssertEqual(closed.map(\.y).max()! - closed.map(\.y).min()!, 4.5, accuracy: 1e-8)
  }

  func testSimpleCatReducedMotionRemainsStatic() throws {
    for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
      let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
      let frames = try [0.0, 10.0, 100.0].map { time in
        try CharacterSceneBuilder.scene(
          pose: ReactiveCharacter.pose(
            state: state, elapsed: time, reduceMotion: true, motionProfile: .cartoon),
          artDirection: .catSimple2D, width: 320, height: 320)
      }
      XCTAssertEqual(frames[0], frames[1])
      XCTAssertEqual(frames[1], frames[2])
    }
  }

  func testSimpleEarArticulationDoesNotFollowGaze() throws {
    let base = ReactiveCharacter.act(
      state: .idle, event: .emotionChanged(.interest)
    ).stateAfter
    var reference: [String: CharacterVectorPath] = [:]
    for x in [0.0, 0.5, 1.0] {
      for y in [0.0, 0.5, 1.0] {
        let focused = ReactiveCharacter.act(
          state: base, event: .attentionFocused(try .init(validatingX: x, y: y))
        ).stateAfter
        let pose = ReactiveCharacter.pose(
          state: focused, elapsed: 0.52, reduceMotion: true, motionProfile: .cartoon)
        let scene = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: .catSimple2D, width: 320, height: 320)
        for id in ["cat.ear.left", "cat.ear.right"] {
          let path = try XCTUnwrap(scene.nodes.first { $0.id == id }?.path)
          if let existing = reference[id] {
            XCTAssertEqual(path, existing, "Gaze alone must not twitch a simple-cat ear")
          } else {
            reference[id] = path
          }
        }
      }
    }
  }

  func testSimpleEarsUseFixedRootDeformationNotWholeTriangleRotation() throws {
    for emotion in [CharacterEmotion.interest, .angerIrritation, .surprise] {
      let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0.35, motionProfile: .cartoon)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: .catSimple2D, width: 320, height: 320)
      let head = try XCTUnwrap(scene.nodes.first { $0.id == "cat.head" })
      for id in ["cat.ear.left", "cat.ear.right"] {
        let ear = try XCTUnwrap(scene.nodes.first { $0.id == id })
        XCTAssertEqual(ear.transform, head.transform, "The root must share the head's transform")
        XCTAssertTrue(
          ear.path.commands.contains { command in
            if case .cubic = command { return true }
            return false
          }, "A rounded, root-fixed pinna replaces the rigid triangle")
      }
    }
  }

  func testSimpleClosedEyesAndRestMouthRemainLegibleOnLightFacePatch() throws {
    for emotion: CharacterEmotion? in [nil, .joy, .gratitude] {
      let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
      let scene = try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true),
        artDirection: .catSimple2D, width: 320, height: 320)
      let patch = try XCTUnwrap(scene.nodes.first { $0.id == "cat.face.patch" })
      guard case .solid(let faceColor) = patch.fill else {
        return XCTFail("Simple face requires a flat patch")
      }
      XCTAssertGreaterThan(faceColor.relativeLuminance, 0.85)
      for id in ["eye.left", "eye.right", "mouth.lip"] {
        let node = try XCTUnwrap(scene.nodes.first { $0.id == id })
        let color: CharacterColor
        if case .solid(let fill) = node.fill {
          color = fill
        } else {
          color = try XCTUnwrap(node.stroke)
        }
        XCTAssertLessThan(color.relativeLuminance, 0.05, "\(id) disappeared on light face")
      }
    }
  }
}

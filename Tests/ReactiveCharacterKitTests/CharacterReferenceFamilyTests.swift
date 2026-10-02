import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterReferenceFamilyTests: XCTestCase {
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

  private func pose(_ emotion: CharacterEmotion?) -> CharacterPose {
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
    return ReactiveCharacter.pose(state: state, elapsed: 0.52, reduceMotion: true)
  }

  private func scene(_ pose: CharacterPose, _ direction: CharacterArtDirection) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(pose: pose, artDirection: direction, width: 512, height: 560)
  }

  func testPortraitPresetsExposeTheirActualAccessory() {
    XCTAssertEqual(CharacterPortraitStyle.HairAccessory.allCases.map(\.rawValue),
                   ["none", "bar", "cross", "flower", "backward-cap"])
    XCTAssertEqual(CharacterPortraitStyle.standard.hairAccessory, .bar)
    XCTAssertEqual(CharacterPortraitStyle.bobGirl.hairAccessory, .cross)
    XCTAssertEqual(CharacterPortraitStyle.shortHairBoy.hairAccessory, .none)
    XCTAssertEqual(CharacterPortraitStyle.flowerGirl.hairAccessory, .flower)
    XCTAssertEqual(CharacterPortraitStyle.cappedBoy.hairAccessory, .backwardCap)
  }

  func testReferencePresetsShareExpressionChannelsAndKeepTheirOwnAccessories() throws {
    for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
      for treatment in CharacterEyeTreatment.allCases {
        let p = pose(emotion)
        let a = try scene(p, CharacterPortraitStyle.flowerGirl.artDirection.replacingFaceTreatment(eyes: treatment))
        let b = try scene(p, CharacterPortraitStyle.cappedBoy.artDirection.replacingFaceTreatment(eyes: treatment))
        for id in ["eye.left", "eye.right", "mouth"] {
          XCTAssertEqual(a.nodes.first { $0.id == id }?.path.commands.count,
                         b.nodes.first { $0.id == id }?.path.commands.count)
        }
        XCTAssertNotEqual(a.nodes.first { $0.id == "portrait.face" }?.path,
                          b.nodes.first { $0.id == "portrait.face" }?.path)
        XCTAssertEqual(a.nodes.filter { $0.id.hasPrefix("portrait.hair.flower.petal.") }.count, 5)
        for part in ["crown", "strap", "buckle", "rearBrim", "seams", "opening", "button"] {
          XCTAssertTrue(b.nodes.contains { $0.id == "portrait.hair.cap." + part })
        }
        XCTAssertFalse(a.nodes.contains { $0.image != nil || $0.id == "nose" })
        XCTAssertFalse(b.nodes.contains { $0.image != nil || $0.id == "nose" })
      }
    }
  }

  func testNeutralPortraitMeasurementsMatchApprovedReferenceHierarchy() throws {
    let frame = try scene(pose(nil), CharacterPortraitStyle.flowerGirl.artDirection)
    let eye = points(try XCTUnwrap(frame.nodes.first { $0.id == "eye.left" }).path)
    let width = eye.map(\.x).max()! - eye.map(\.x).min()!
    let height = eye.map(\.y).max()! - eye.map(\.y).min()!
    XCTAssertTrue((29...35).contains(width), "Reference oval width: \(width)")
    XCTAssertTrue((55...62).contains(height), "Reference oval height: \(height)")
    let brow = points(try XCTUnwrap(frame.nodes.first { $0.id == "eyebrow.left" }).path)
    XCTAssertTrue((40...44).contains(brow.map(\.x).max()! - brow.map(\.x).min()!))
    let fringe = points(try XCTUnwrap(frame.nodes.first { $0.id == "portrait.hair.fringe" }).path)
    let face = points(try XCTUnwrap(frame.nodes.first { $0.id == "portrait.face" }).path)
    XCTAssertLessThan(fringe.map(\.y).min()!, face.map(\.y).min()!, "No forehead sliver above the bangs")
  }

  func testCatHasDarkExternalWhiskersTailAndLargerPillEyes() throws {
    let frame = try scene(pose(nil), .catSimple2D)
    XCTAssertEqual(frame.nodes.first { $0.id == "cat.tail" }?.layer, .behindSurface)
    for side in ["left", "right"] {
      let whiskers = try XCTUnwrap(frame.nodes.first { $0.id == "cat.whiskers." + side })
      XCTAssertLessThan(try XCTUnwrap(whiskers.stroke).relativeLuminance, 0.05)
      let xs = points(whiskers.path).map(\.x)
      if side == "left" { XCTAssertLessThan(xs.min()!, 30) }
      else { XCTAssertGreaterThan(xs.max()!, 482) }
      let eye = points(try XCTUnwrap(frame.nodes.first { $0.id == "eye." + side }).path)
      XCTAssertGreaterThan(eye.map(\.y).max()! - eye.map(\.y).min()!, 72)
    }
  }

  func testChevronIsReachableThroughPublicAppearanceWithoutChangingPoseOrIdle() throws {
    for direction in [CharacterArtDirection.catSimple2D, CharacterPortraitStyle.flowerGirl.artDirection] {
      let changed = direction.replacingSmileEyeShape(.chevron)
      XCTAssertEqual(try scene(pose(nil), direction), try scene(pose(nil), changed))
      let joyful = pose(.joy)
      XCTAssertEqual(joyful.eyeContours.left.chevron, 0, "The semantic pose is not rewritten")
      let a = try scene(joyful, direction)
      let b = try scene(joyful, changed)
      XCTAssertNotEqual(a.nodes.first { $0.id == "eye.left" }?.path,
        b.nodes.first { $0.id == "eye.left" }?.path)
      XCTAssertEqual(changed.replacingPartColors(.default).replacingFaceTreatment(eyes: .round)
        .replacingMotionProfile(.expressive).style.smileEyeShape, .chevron)
      XCTAssertEqual(a.nodes.filter { !$0.id.hasPrefix("eye.") },
        b.nodes.filter { !$0.id.hasPrefix("eye.") })
    }
  }

  func testChevronHasRoundCapsConstantTopologyAndMirroredGeometry() {
    let rect = CharacterRect(x: 20, y: 30, width: 50, height: 45)
    let left = CharacterInkGeometry.chevron(in: rect, thickness: 6, pointsRight: true)
    let right = CharacterInkGeometry.chevron(in: rect, thickness: 6, pointsRight: false)
    XCTAssertEqual(left.points.count, 37)
    XCTAssertEqual(left.path.commands.count, 14)
    let mirrored = left.points.reversed().map { CharacterVectorPoint(x: 90 - $0.x, y: $0.y) }
    XCTAssertEqual(right.points, mirrored)
    for amount in stride(from: 0.0, through: 1, by: 0.02) {
      for blink in stride(from: 0.0, through: 1, by: 0.1) {
        for side in [true, false] {
          let path = CharacterCompactEyeGeometry.path(
            eye: .init(centerX: 0.3, centerY: 0.5, width: 0.19, height: 0.43,
              angle: 0, unblinkedWidth: 0.19, unblinkedHeight: 0.43, blink: blink),
            contour: .init(chevron: amount), left: side,
            center: .init(x: 100, y: 100), width: 23, height: 78,
            treatment: .vertical, thickness: 6, expressionWidth: 55)
          XCTAssertEqual(path.commands.count, 14)
          XCTAssertTrue(points(path).allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
      }
    }
  }
}
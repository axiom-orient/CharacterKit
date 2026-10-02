import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterBoyTests: XCTestCase {
  private let viewpoints = CharacterPortraitStyle.BoyViewpoint.allCases

  private func pose(_ emotion: CharacterEmotion? = nil) -> CharacterPose {
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
    return ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
  }

  private func scene(
    _ viewpoint: CharacterPortraitStyle.BoyViewpoint, pose: CharacterPose? = nil,
    accessory: CharacterPortraitStyle.HairAccessory = .none,
    components: CharacterComponents = .default
  ) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: pose ?? self.pose(), artDirection: .portrait(
        .boy(viewpoint: viewpoint, hairAccessory: accessory), components: components),
      width: 1116, height: 1116)
  }

  private func node(_ id: String, in scene: CharacterScene) throws -> CharacterSceneNode {
    try XCTUnwrap(scene.nodes.first { $0.id == id })
  }

  /// Exact extrema of the rendered curves, not their (larger) control-point hull.
  private func bounds(_ path: CharacterVectorPath) throws -> CharacterRect {
    var points: [CharacterVectorPoint] = []
    var current = CharacterVectorPoint(x: 0, y: 0)
    var start = current
    func roots(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> [Double] {
      let a = -p0 + 3 * p1 - 3 * p2 + p3
      let b = 2 * (p0 - 2 * p1 + p2)
      let c = p1 - p0
      if abs(a) < 1e-12 { return abs(b) < 1e-12 ? [] : [-c / b] }
      let d = b * b - 4 * a * c
      guard d >= 0 else { return [] }
      return [(-b + sqrt(d)) / (2 * a), (-b - sqrt(d)) / (2 * a)]
    }
    for command in path.commands {
      switch command {
      case .move(let p): current = p; start = p; points.append(p)
      case .line(let p): current = p; points.append(p)
      case .quad(let c, let end):
        let p = current
        for (a, b, d) in [(p.x, c.x, end.x), (p.y, c.y, end.y)] {
          let denominator = a - 2 * b + d
          if abs(denominator) > 1e-12 {
            let t = (a - b) / denominator
            if t > 0 && t < 1 {
              let u = 1 - t
              points.append(.init(x: u*u*p.x + 2*u*t*c.x + t*t*end.x,
                                  y: u*u*p.y + 2*u*t*c.y + t*t*end.y))
            }
          }
        }
        current = end; points.append(end)
      case .cubic(let c1, let c2, let end):
        let p = current
        for t in roots(p.x, c1.x, c2.x, end.x) + roots(p.y, c1.y, c2.y, end.y)
          where t > 0 && t < 1 {
          let u = 1 - t
          points.append(.init(x: u*u*u*p.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                              y: u*u*u*p.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y))
        }
        current = end; points.append(end)
      case .close: current = start; points.append(start)
      }
    }
    let minX = try XCTUnwrap(points.map(\.x).min())
    let maxX = try XCTUnwrap(points.map(\.x).max())
    let minY = try XCTUnwrap(points.map(\.y).min())
    let maxY = try XCTUnwrap(points.map(\.y).max())
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  func testExistingPresetsAndRawValuesRemainSourceCompatible() {
    XCTAssertEqual(CharacterPortraitStyle.Hairstyle.allCases.map(\.rawValue),
                   ["bob", "side-part", "crop"])
    XCTAssertEqual(CharacterPortraitStyle.shortHairBoy.hairstyle, .crop)
    XCTAssertEqual(CharacterPortraitStyle.shortHairBoy.boyViewpoint, .front)
    XCTAssertEqual(CharacterPortraitStyle.shortHairBoy.hairAccessory, .none)
    XCTAssertEqual(CharacterPortraitStyle.cappedBoy, .boy(viewpoint: .front))
    XCTAssertEqual(CharacterPortraitStyle(hairstyle: .crop).boyViewpoint, .front)
    XCTAssertEqual(CharacterPortraitStyle(hairstyle: .crop).hairColor,
                   CharacterPortraitStyle.defaultHairColor)
    XCTAssertNil(CharacterPortraitStyle.bobGirl.boyViewpoint)
    XCTAssertEqual(CharacterPortraitStyle.boy(viewpoint: .threeQuarterRight).hairAccessory,
                   .backwardCap)
  }

  func testReferenceEyeAndMouthAnchorsAreIndependentOfLegacyGirlProportions() throws {
    // Independently measured in the uploaded 724 × 1086 reference halves, not board percentages.
    for (view, lx, ly, rx, ry, mx, my) in [
      (CharacterPortraitStyle.BoyViewpoint.front, 282.6, 563.4, 479.7, 564.2, 378.5, 646.0),
      (.threeQuarterRight, 384.4, 566.2, 535.8, 567.0, 462.7, 647.5),
    ] {
      let value = try scene(view)
      for (id, x, y) in [("eye.left", lx, ly), ("eye.right", rx, ry), ("mouth", mx, my)] {
        let box = try bounds(node(id, in: value).path)
        XCTAssertEqual(box.midX, x, accuracy: 0.01, id)
        XCTAssertEqual(box.midY, y, accuracy: 0.01, id)
      }
      let left = try bounds(node("eye.left", in: value).path)
      let right = try bounds(node("eye.right", in: value).path)
      XCTAssertTrue((38...50).contains(left.width))
      XCTAssertTrue((75...86).contains(left.height))
      if view == .threeQuarterRight { XCTAssertLessThan(right.width, left.width) }
    }
  }

  func testBothAuthoredSilhouettesHaveCowlickAndUniformAtReferenceLandmarks() throws {
    for view in viewpoints {
      let value = try scene(view)
      let outline = try bounds(node("portrait.outline", in: value).path)
      XCTAssertTrue((100...111).contains(outline.minY))
      XCTAssertTrue((904...910).contains(outline.maxY), "\(view): \(outline.maxY)")
      XCTAssertGreaterThan(outline.width, 640)
      XCTAssertLessThan(outline.width, 680)
      XCTAssertTrue(value.nodes.allSatisfy { $0.image == nil })
      XCTAssertFalse(try CharacterSVGRenderer.render(value).contains("<image"))
      XCTAssertEqual(value.nodes.map(\.id).count, Set(value.nodes.map(\.id)).count)
    }
  }

  func testAuthoredAnatomyIsStaticWhileSharedSurfaceAndFeaturesExpressEmotion() throws {
    for view in viewpoints {
      let baseline = try scene(view, pose: pose().replacingSurface(.identity))
      let anatomy: (CharacterSceneNode) -> Bool = { $0.id.hasPrefix("portrait.") }
      var signatures: [[CharacterVectorPath]] = []
      for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
        // The shared surface may squash even a static expression. Neutralize that
        // independent channel before comparing authored anatomy; do not disable it in production.
        let value = try scene(view, pose: pose(emotion).replacingSurface(.identity))
        XCTAssertTrue(value.nodes.filter(anatomy) == baseline.nodes.filter(anatomy),
                      "Authored anatomy changed for \(view), \(String(describing: emotion))")
        let paths = try ["eye.left", "eye.right", "eyebrow.left", "eyebrow.right", "mouth"]
          .map { try node($0, in: value).path }
        XCTAssertFalse(signatures.contains(paths))
        signatures.append(paths)
      }
      XCTAssertEqual(signatures.count, 13)
    }
  }

  func testNineGazesDoNotChangeViewpointHairBrowsOrMouth() throws {
    for view in viewpoints {
      let base = try scene(view)
      for x in [0.0, 0.5, 1.0] {
        for y in [0.0, 0.5, 1.0] {
          let state = ReactiveCharacter.act(state: .idle,
            event: .attentionFocused(try .init(validatingX: x, y: y))).stateAfter
          let p = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
          let value = try scene(view, pose: p)
          XCTAssertEqual(value.nodes.filter { !$0.id.hasPrefix("eye.") },
                         base.nodes.filter { !$0.id.hasPrefix("eye.") })
          let left = try bounds(node("eye.left", in: value).path)
          let right = try bounds(node("eye.right", in: value).path)
          XCTAssertLessThan(left.maxX + 30, right.minX)
        }
      }
    }
  }

  func testHairOcclusionBoundaryDoesNotRotateWithAngryBrows() throws {
    for view in viewpoints {
      let normal = try scene(view)
      let angry = try scene(view, pose: pose(.angerIrritation))
      let face = try node("portrait.face", in: normal)
      for id in ["eye.left", "eye.right", "eyebrow.left", "eyebrow.right", "mouth"] {
        let value = try node(id, in: angry)
        XCTAssertEqual(value.clips, [face.path])
        XCTAssertEqual(value.transform, face.transform)
      }
      XCTAssertNotEqual(try node("eyebrow.left", in: normal).path,
                        try node("eyebrow.left", in: angry).path)
    }
  }

  func testExplicitBlinkChangesOnlyLiveFeaturesAndNeverShowsBakedEyes() throws {
    let blink = ReactiveCharacter.act(state: .idle, event: .animationStarted(
      id: try .init(validating: "boy-blink"), animation: .blink)).stateAfter
    for view in viewpoints {
      var smallest = Double.infinity
      var largest = 0.0
      for time in stride(from: 0.0, through: 0.30, by: 0.01) {
        let p = ReactiveCharacter.pose(state: blink, elapsed: time).replacingSurface(.identity)
        let value = try scene(view, pose: p)
        let eye = try node("eye.left", in: value)
        let height = try bounds(eye.path).height
        smallest = min(smallest, height)
        largest = max(largest, height)
        XCTAssertEqual(eye.path.commands.count, 14)
        XCTAssertGreaterThan(height, 0)
        XCTAssertTrue(value.nodes.allSatisfy { $0.image == nil })
      }
      XCTAssertLessThan(smallest, 10)
      XCTAssertGreaterThan(largest, 75)
    }
  }

  func testColorReplacementChangesPaintWithoutChangingReferenceGeometry() throws {
    let hair = try CharacterColor(red: 0.4, green: 0.2, blue: 0.1)
    let skin = try CharacterColor(red: 1, green: 0.8, blue: 0.6)
    let eyes = try CharacterColor(red: 0.1, green: 0.4, blue: 0.7)
    let shirt = try CharacterColor(red: 0.2, green: 0.5, blue: 0.4)
    for view in viewpoints {
      let base = try scene(view)
      let style = CharacterPortraitStyle.boy(viewpoint: view, hairAccessory: .none, hairColor: hair)
      let direction = style.artDirection.replacingPartColors(
        style.artDirection.style.partColors.replacing(surface: skin, eyes: eyes, accent: shirt))
      let result = try CharacterSceneBuilder.scene(pose: pose(), artDirection: direction,
                                                 width: 1116, height: 1116)
      XCTAssertEqual(result.nodes.map(\.path), base.nodes.map(\.path))
      XCTAssertEqual(try node("portrait.face", in: result).fill, .solid(skin))
      XCTAssertEqual(try node("portrait.hair.fringe", in: result).fill, .solid(hair))
      XCTAssertEqual(try node("eye.left", in: result).fill, .solid(eyes))
      XCTAssertEqual(try node("portrait.shoulders", in: result).fill, .solid(shirt))
      XCTAssertEqual(try node("mouth", in: result).stroke, try node("mouth", in: base).stroke)
    }
  }

  func testCapOccludesCowlickOnlyWhenAccessoriesAreEnabled() throws {
    for view in viewpoints {
      let capped = try scene(view, accessory: .backwardCap)
      let hidden = try scene(view, accessory: .backwardCap, components: [.eyes, .mouth])
      let bare = try scene(view, components: [.eyes, .mouth])
      XCTAssertEqual(hidden, bare)
      XCTAssertNotNil(capped.nodes.first { $0.id == "portrait.hair.cap.crown" })
      for id in ["portrait.outline", "portrait.hair.back", "portrait.hair.fringe"] {
        XCTAssertFalse(try node(id, in: capped).clips.isEmpty)
        XCTAssertTrue(try node(id, in: bare).clips.isEmpty)
      }
    }
  }

  func testFeatureVisibilityNeverLeavesAuthoredFacialFeaturesBehind() throws {
    for view in viewpoints {
      let value = try scene(view, components: [])
      XCTAssertFalse(value.nodes.contains { ["eye.", "eyebrow.", "mouth", "nose"].contains(where: $0.id.hasPrefix) })
      XCTAssertTrue(value.nodes.allSatisfy { $0.image == nil && $0.id.hasPrefix("portrait.") })
      let active = try scene(view)
      XCTAssertEqual(value.nodes, active.nodes.filter { $0.id.hasPrefix("portrait.") })
    }
  }

  func testReducedMotionIsStaticForBothViewsAndEveryEmotion() throws {
    for view in viewpoints {
      for emotion in CharacterEmotion.allCases {
        let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
        let a = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
        let b = ReactiveCharacter.pose(state: state, elapsed: 100, reduceMotion: true)
        XCTAssertEqual(try scene(view, pose: a), try scene(view, pose: b))
      }
    }
  }

  func testQuarterViewAndBothEyeTreatmentsRemainFiniteAcrossEveryEmotion() throws {
    for view in viewpoints {
      for treatment in CharacterEyeTreatment.allCases {
        for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
          let direction = CharacterPortraitStyle.boy(viewpoint: view, hairAccessory: .none)
            .artDirection.replacingFaceTreatment(eyes: treatment)
          let value = try CharacterSceneBuilder.scene(pose: pose(emotion), artDirection: direction,
                                                     width: 320, height: 320)
          try CharacterSceneValidation.validate(value)
          let left = try bounds(node("eye.left", in: value).path)
          let right = try bounds(node("eye.right", in: value).path)
          XCTAssertLessThan(left.maxX + 10, right.minX)
        }
      }
    }
  }

  func testBoyUsesExistingWritingOwnerAndRejectsInvalidViewport() throws {
    let state = ReactiveCharacter.act(state: .idle, event: .userWritingBegan(focus: .center)).stateAfter
    for view in viewpoints {
      let direction = CharacterPortraitStyle.boy(viewpoint: view, hairAccessory: .none).artDirection
      let p = ReactiveCharacter.pose(state: state, elapsed: 0.3, reduceMotion: true)
      let value = try CharacterSceneBuilder.scene(pose: p, artDirection: direction, width: 512, height: 512)
      XCTAssertEqual(value.nodes.filter { $0.id == "writing" }.count, 1)
      for width in [Double.nan, -Double.infinity, -1, 0] {
        XCTAssertThrowsError(try CharacterSceneBuilder.scene(
          pose: p, artDirection: direction, width: width, height: 512))
      }
    }
  }
}

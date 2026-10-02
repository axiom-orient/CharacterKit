import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterMinimalFaceTests: XCTestCase {
  private func state(_ emotion: CharacterEmotion?) -> CharacterState {
    ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
  }

  private func cubic(_ p: [CharacterVectorPoint], _ segment: Int, _ t: Double)
    -> CharacterVectorPoint
  {
    let i = segment * 3
    let u = 1 - t
    let a = u * u * u
    let b = 3 * u * u * t
    let c = 3 * u * t * t
    let d = t * t * t
    return .init(
      x: p[i].x * a + p[i + 1].x * b + p[i + 2].x * c + p[i + 3].x * d,
      y: p[i].y * a + p[i + 1].y * b + p[i + 2].y * c + p[i + 3].y * d)
  }

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

  private func sampled(_ path: CharacterVectorPath) -> [CharacterVectorPoint] {
    let p = points(path)
    precondition(p.count == 37)
    return (0..<12).flatMap { segment in
      (0..<12).map { cubic(p, segment, Double($0) / 12) }
    }
  }

  private func signedArea(_ points: [CharacterVectorPoint]) -> Double {
    zip(points, Array(points.dropFirst()) + [points[0]])
      .reduce(0.0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) } / 2
  }

  private func hasCrossing(_ p: [CharacterVectorPoint]) -> Bool {
    func cross(_ a: CharacterVectorPoint, _ b: CharacterVectorPoint, _ c: CharacterVectorPoint)
      -> Double
    {
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    for i in 0..<(p.count - 2) {
      let a = p[i]
      let b = p[(i + 1) % p.count]
      for j in (i + 2)..<p.count where !(i == 0 && j == p.count - 1) {
        let c = p[j]
        let d = p[(j + 1) % p.count]
        if cross(a, b, c) * cross(a, b, d) < -1e-8,
          cross(c, d, a) * cross(c, d, b) < -1e-8
        {
          return true
        }
      }
    }
    return false
  }

  func testMouthFillPreservesConfiguredAlphaThroughoutOpening() throws {
    let light = try CharacterColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.2)
    let dark = try CharacterColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.7)
    for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let paths = CharacterMouthPaths(
        outer: .init(), teeth: .init(), tongue: .init(),
        detailOpacity: 0, tongueOpacity: 0, cavityAmount: amount)
      let color = paths.fill(light: light, dark: dark)
      XCTAssertEqual(
        color.alpha, light.alpha + (dark.alpha - light.alpha) * amount, accuracy: 1e-12)
      XCTAssertEqual(color.red, light.red + (dark.red - light.red) * amount, accuracy: 1e-12)
    }
  }

  func testOpenSmileHasRoundedLowerBowlAndTongueAttachedToLowerLip() {
    let pose = ReactiveCharacter.pose(
      state: state(.joy), elapsed: 0.52,
      reduceMotion: true, motionProfile: .cartoon)
    let paths = CharacterMouthGeometry.paths(
      for: pose.mouth,
      in: .init(x: 0, y: 0, width: 400, height: 400))
    let outer = points(paths.outer)
    let cornerY = (outer[9].y + outer[27].y) / 2
    let upperSag = outer[0].y - cornerY
    let lowerDepth = outer[18].y - cornerY
    XCTAssertGreaterThan(upperSag, 0)
    XCTAssertGreaterThan(lowerDepth, upperSag * 2)
    let tongueY = sampled(paths.tongue).map(\.y)
    XCTAssertLessThan(tongueY.min()!, outer[18].y)
    XCTAssertGreaterThan(tongueY.max()!, outer[18].y)
    XCTAssertGreaterThan(paths.tongueOpacity, 0)
  }

  func testEmotionOnlyNeverDrawsAnOutputWaveFromGlyphMetadata() throws {
    for direction in [CharacterArtDirection.black, .white, .arcade] {
      for emotion in CharacterEmotion.allCases {
        for time in stride(from: 0.0, through: 4.0, by: 0.20) {
          let pose = ReactiveCharacter.pose(
            state: state(emotion), elapsed: time,
            motionProfile: .cartoon)
          XCTAssertFalse(pose.writingVisible)
          let scene = try CharacterSceneBuilder.scene(
            pose: pose, artDirection: direction,
            width: 320, height: 320)
          XCTAssertFalse(
            scene.nodes.contains { $0.id == "mouth.wave" },
            "Emotion is not output: \(emotion) at \(time)")
        }
      }
    }
  }

  func testSmileRibbonHasEqualThicknessAcrossBothArcsAndRoundedEnds() {
    for width in [12.0, 40, 90, 180] {
      let thickness = width * 0.16
      let ribbon = CharacterInkGeometry.ribbon(
        in: .init(x: 17, y: 23, width: width, height: width * 0.65),
        thickness: thickness, rise: width * 0.27)
      for step in 0...40 {
        let t = Double(step) / 40
        for (outer, inner) in [(0, 5), (1, 4), (10, 7), (11, 6)] {
          let a = cubic(ribbon.points, outer, t)
          let b = cubic(ribbon.points, inner, 1 - t)
          XCTAssertEqual(
            hypot(a.x - b.x, a.y - b.y), thickness,
            accuracy: thickness * 0.0005)
        }
      }
      XCTAssertGreaterThan(signedArea(sampled(ribbon.path)), 0)
      XCTAssertFalse(hasCrossing(sampled(ribbon.path)))
    }
  }

  func testCapsuleAspectChangeKeepsTopologyAndControlPointsContinuous() {
    let a = CharacterInkGeometry.capsule(in: .init(x: 0, y: 0, width: 60, height: 60 - 1e-7))
    let b = CharacterInkGeometry.capsule(in: .init(x: 0, y: 0, width: 60, height: 60 + 1e-7))
    for (p, q) in zip(a.points, b.points) {
      XCTAssertLessThan(hypot(p.x - q.x, p.y - q.y), 1e-6)
    }
    XCTAssertEqual(a.path.commands.count, 14)
    XCTAssertEqual(b.path.commands.count, 14)
  }

  func testAllEyeMorphsStayClosedFiniteAndDoNotCrossThemselves() {
    let shapes = [
      CharacterEyeContour.neutral, .init(crescent: 1), .init(ellipse: 1),
      .init(heart: 1), .init(lidCompression: 0.48, innerPinch: 0.94),
    ]
    for from in shapes {
      for to in shapes {
        for step in 0...12 {
          for aspect in [0.15, 0.60, 2.4] {
            let path = CharacterEyeGeometry.path(
              from.blended(to: to, amount: Double(step) / 12),
              in: .init(x: 0, y: 0, width: 60, height: 60 * aspect), left: true)
            XCTAssertEqual(path.commands.count, 14)
            XCTAssertTrue(points(path).allSatisfy { $0.x.isFinite && $0.y.isFinite })
            let outline = sampled(path)
            XCTAssertGreaterThan(signedArea(outline), 1, "\(from) → \(to) / \(step) / \(aspect)")
            XCTAssertFalse(hasCrossing(outline), "\(from) → \(to) / \(step) / \(aspect)")
          }
        }
      }
    }
  }

  func testHeartBecomesOneFlatCapsuleAtFullBlinkWithoutChangingEmotionChannels() throws {
    let pose = ReactiveCharacter.pose(
      state: state(.affection), elapsed: 3.54, motionProfile: .cartoon)
    XCTAssertEqual(pose.eyeContours.left.heart, 1)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: .black, width: 480, height: 480)
    let node = try XCTUnwrap(scene.nodes.first { $0.id == "eye.left" })
    let points = points(node.path)
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    let box = CharacterRect(
      x: xs.min()!, y: ys.min()!,
      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    XCTAssertGreaterThan(box.width / box.height, 6)
    let expected = CharacterInkGeometry.capsule(in: box).points
    for (a, b) in zip(points, expected) {
      XCTAssertEqual(a.x, b.x, accuracy: 1e-8)
      XCTAssertEqual(a.y, b.y, accuracy: 1e-8)
    }
  }

  func testEyeSilhouetteVocabularyIsIndependentOfMotionTempo() {
    for emotion in CharacterEmotion.allCases {
      let expected = CharacterExpression.sample(
        emotion: emotion, elapsed: 0.52,
        reduceMotion: false, profile: .focusedEmotion(.authored)
      ).eyeContours
      for mode in CharacterEmotionMotion.allCases {
        for time in [0.0, 0.20, 3.54, 20.0] {
          XCTAssertEqual(
            CharacterExpression.sample(
              emotion: emotion, elapsed: time,
              reduceMotion: false, profile: .focusedEmotion(mode)
            ).eyeContours, expected)
        }
      }
    }
  }

  func testWideAndSurprisedEyesHaveSeparatePaintedHalfSpaces() throws {
    for direction in [CharacterArtDirection.black, .white, .arcade] {
      for emotion in [CharacterEmotion?.none, .surprise, .joy, .affection, .angerIrritation] {
        for time in stride(from: 0.0, through: 6.0, by: 0.05) {
          let pose = ReactiveCharacter.pose(
            state: state(emotion), elapsed: time, motionProfile: .cartoon)
          let scene = try CharacterSceneBuilder.scene(
            pose: pose, artDirection: direction, width: 320, height: 480)
          func facePoints(_ name: String) throws -> [CharacterVectorPoint] {
            let node = try XCTUnwrap(scene.nodes.first { $0.id == name })
            let transform = node.transform
            let base = scene.surfaceTransform
            let determinant = base.a * base.d - base.b * base.c
            return sampled(node.path).map { point in
              let x = transform.a * point.x + transform.c * point.y + transform.tx - base.tx
              let y = transform.b * point.x + transform.d * point.y + transform.ty - base.ty
              return .init(
                x: (base.d * x - base.c * y) / determinant,
                y: (-base.b * x + base.a * y) / determinant)
            }
          }
          let left = try facePoints("eye.left")
          let right = try facePoints("eye.right")
          XCTAssertLessThan(
            left.map(\.x).max()!, right.map(\.x).min()!, "\(emotion as Any) / \(time)")
        }
      }
    }
  }

  func testMouthCrossingZeroCurvatureDoesNotJumpOrTurnInsideOut() {
    let base = ReactiveCharacter.pose(state: state(.joy), elapsed: 0.52, reduceMotion: true).mouth
    func mouth(_ curve: Double, _ openness: Double) -> CharacterMouthPose {
      .init(
        visible: true, opacity: 1, curvature: curve, openness: openness, width: 0.70,
        skew: 0, intrinsicAspect: base.intrinsicAspect, detailOpacity: base.detailOpacity,
        referenceGlyphOpacity: base.referenceGlyphOpacity, glyph: base.glyph,
        interior: base.interior, contour: base.contour, details: base.details)
    }
    let face = CharacterRect(x: 0, y: 0, width: 392, height: 414)
    for open in [0.0, 0.10, 0.32, 0.80] {
      let a = CharacterMouthGeometry.paths(for: mouth(-1e-7, open), in: face).outer
      let b = CharacterMouthGeometry.paths(for: mouth(1e-7, open), in: face).outer
      for (p, q) in zip(points(a), points(b)) {
        XCTAssertLessThan(hypot(p.x - q.x, p.y - q.y), 0.001)
      }
      for curve in stride(from: -1.0, through: 1.0, by: 0.10) {
        let shape = CharacterMouthGeometry.paths(for: mouth(curve, open), in: face).outer
        XCTAssertEqual(shape.commands.count, 14)
        XCTAssertGreaterThan(signedArea(sampled(shape)), 0)
        XCTAssertFalse(hasCrossing(sampled(shape)), "\(curve) / \(open)")
      }
    }
  }

  func testNeutralHoldsStillAndJoyHasRestBetweenUnequalLaughBeats() {
    let neutral = ReactiveCharacter.pose(state: .idle, elapsed: 0.1, motionProfile: .cartoon)
    for time in [0.4, 0.7, 1.0, 1.5] {
      XCTAssertEqual(
        ReactiveCharacter.pose(state: .idle, elapsed: time, motionProfile: .cartoon), neutral)
    }
    func joy(_ time: Double) -> CharacterExpressionSample {
      CharacterExpression.sample(
        emotion: .joy, elapsed: time, reduceMotion: false, profile: .cartoon)
    }
    XCTAssertLessThan(joy(0.23).surface.offsetY, joy(0.73).surface.offsetY)
    for time in [1.10, 1.65, 2.20, 2.80] { XCTAssertEqual(joy(time).surface, .identity) }
    XCTAssertGreaterThan(joy(0.23).mouthOpenness, joy(1.65).mouthOpenness)
  }

  func testDefaultComponentsKeepNoseAndDecorationsOptIn() throws {
    XCTAssertFalse(CharacterComponents.default.contains(.nose))
    XCTAssertFalse(CharacterComponents.default.contains(.ornaments))
    XCTAssertTrue(CharacterComponents.all.contains(.nose))
    let pose = ReactiveCharacter.pose(state: state(.joy), elapsed: 0.2, motionProfile: .cartoon)
    for direction in [CharacterArtDirection.black, .white, .arcade] {
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 240, height: 240)
      XCTAssertFalse(
        scene.nodes.contains {
          $0.id == "nose" || $0.id.hasPrefix("blush")
            || $0.id.hasPrefix("art.accent") || $0.id.contains(".scan")
        })
      XCTAssertEqual(scene.nodes.filter { $0.id == "eye.left" || $0.id == "eye.right" }.count, 2)
      XCTAssertNotNil(scene.nodes.first { $0.id == "mouth" })
    }
  }
}

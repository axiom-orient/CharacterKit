import XCTest

@testable import ReactiveCharacterKit

final class CharacterCustomizationTests: XCTestCase {
  func testEyeTreatmentVocabularyHasOneCanonicalBaseAndTwoExplicitVariants() {
    XCTAssertEqual(CharacterEyeTreatment.allCases, [.vertical, .horizontal, .round])
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

  private func sampled(_ path: CharacterVectorPath) -> [CharacterVectorPoint] {
    let p = points(path)
    precondition(p.count == 37)
    return (0..<12).flatMap { segment in
      (0..<12).map { cubic(p, segment, Double($0) / 12) }
    }
  }

  private func bounds(of path: CharacterVectorPath) throws -> CharacterRect {
    var points: [CharacterVectorPoint] = []
    for command in path.commands {
      switch command {
      case .move(let p), .line(let p):
        points.append(p)
      case .quad(let control, let end):
        points += [control, end]
      case .cubic(let control1, let control2, let end):
        points += [control1, control2, end]
      case .close:
        break
      }
    }
    let first = try XCTUnwrap(points.first)
    let minX = points.reduce(first.x) { min($0, $1.x) }
    let maxX = points.reduce(first.x) { max($0, $1.x) }
    let minY = points.reduce(first.y) { min($0, $1.y) }
    let maxY = points.reduce(first.y) { max($0, $1.y) }
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private func idleScene(_ treatment: CharacterEyeTreatment) throws -> CharacterScene {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    return try CharacterSceneBuilder.scene(
      pose: pose,
      artDirection: CharacterTheme.black.configured(eyes: treatment),
      width: 320,
      height: 320,
      environment: .init(reduceTransparency: true))
  }

  func testEyeTreatmentsChangeOnlyBaseEyeProportion() throws {
    let vertical = try bounds(
      of: XCTUnwrap(try idleScene(.vertical).nodes.first { $0.id == "eye.left" }).path)
    let horizontal = try bounds(
      of: XCTUnwrap(try idleScene(.horizontal).nodes.first { $0.id == "eye.left" }).path)
    let round = try bounds(
      of: XCTUnwrap(try idleScene(.round).nodes.first { $0.id == "eye.left" }).path)

    XCTAssertGreaterThan(vertical.height / vertical.width, horizontal.height / horizontal.width)
    XCTAssertGreaterThan(vertical.height, vertical.width)
    XCTAssertGreaterThan(horizontal.width, horizontal.height)
    XCTAssertEqual(round.width, round.height, accuracy: max(round.width, round.height) * 0.02)
  }

  func testDefaultAndEveryBuiltInThemeUseCanonicalVerticalEye() throws {
    let defaultStyle = try CharacterStyle()
    XCTAssertEqual(defaultStyle.eyeTreatment, .vertical)
    for theme in CharacterTheme.allCases {
      XCTAssertEqual(theme.artDirection.style.eyeTreatment, .vertical)
    }
  }

  func testHorizontalEyeIsDerivedFromTheCanonicalVerticalEye() throws {
    let vertical = try bounds(
      of: XCTUnwrap(try idleScene(.vertical).nodes.first { $0.id == "eye.left" }).path)
    let horizontal = try bounds(
      of: XCTUnwrap(try idleScene(.horizontal).nodes.first { $0.id == "eye.left" }).path)

    XCTAssertGreaterThan(horizontal.width, vertical.height * 0.68)
    XCTAssertLessThan(horizontal.width, vertical.height * 0.82)
    XCTAssertLessThan(horizontal.height, vertical.height * 0.35)
    XCTAssertGreaterThan(
      horizontal.width / horizontal.height, vertical.height / vertical.width * 0.60)
  }

  func testHorizontalEyesStaySeparatedAndInsideTheFaceOutline() throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose,
      artDirection: CharacterTheme.black.configured(eyes: .horizontal),
      width: 320,
      height: 320,
      environment: .init(reduceTransparency: true))

    func transformedPoints(_ id: String) throws -> [CharacterVectorPoint] {
      let node = try XCTUnwrap(scene.nodes.first { $0.id == id })
      return sampled(node.path).map { point in
        .init(
          x: node.transform.a * point.x + node.transform.c * point.y + node.transform.tx,
          y: node.transform.b * point.x + node.transform.d * point.y + node.transform.ty)
      }
    }

    let left = try transformedPoints("eye.left")
    let right = try transformedPoints("eye.right")
    XCTAssertLessThan(left.map(\.x).max()!, right.map(\.x).min()!)

    let face = scene.faceBounds.rect
    let cx = face.midX
    let cy = face.midY
    let rx = face.width / 2
    let ry = face.height / 2
    for point in left + right {
      let nx = (point.x - cx) / rx
      let ny = (point.y - cy) / ry
      XCTAssertLessThanOrEqual(nx * nx + ny * ny, 1.0 + 0.001)
    }
  }

  func testHeartExpressionStaysEmotionOwnedAcrossBaseTreatments() throws {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.affection)).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.52, reduceMotion: true)
    var paths: [CharacterVectorPath] = []
    for treatment in CharacterEyeTreatment.allCases {
      let scene = try CharacterSceneBuilder.scene(
        pose: pose,
        artDirection: CharacterTheme.black.configured(eyes: treatment),
        width: 320,
        height: 320)
      paths.append(try XCTUnwrap(scene.nodes.first { $0.id == "eye.left" }).path)
    }
    XCTAssertTrue(paths.dropFirst().allSatisfy { $0 == paths[0] })
  }

  func testMouthTreatmentChangesPaintNotExpressionGeometry() throws {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.52, reduceMotion: true)
    let outline = try CharacterSceneBuilder.scene(
      pose: pose,
      artDirection: CharacterTheme.black.configured(mouth: .outline),
      width: 320,
      height: 320)
    let filled = try CharacterSceneBuilder.scene(
      pose: pose,
      artDirection: CharacterTheme.black.configured(mouth: .filled),
      width: 320,
      height: 320)
    let outlineMouth = try XCTUnwrap(outline.nodes.first { $0.id == "mouth" })
    let filledMouth = try XCTUnwrap(filled.nodes.first { $0.id == "mouth" })

    XCTAssertEqual(outlineMouth.path, filledMouth.path)
    XCTAssertEqual(outlineMouth.stroke, filledMouth.stroke)
    XCTAssertNil(outlineMouth.fill)
    XCTAssertNotNil(filledMouth.fill)
  }

  func testCustomPartColorsPreserveGeometryAndSemanticState() throws {
    let originalState = ReactiveCharacter.reduce(
      state: .idle, event: .emotionChanged(.gratitude)
    ).state
    let pose = ReactiveCharacter.pose(state: originalState, elapsed: 0.52, reduceMotion: true)
    let base = CharacterTheme.arcade.artDirection
    let colors = base.style.partColors.replacing(
      surface: try CharacterColor(red: 0.05, green: 0.07, blue: 0.10),
      eyes: try CharacterColor(red: 1, green: 0.3, blue: 0.1),
      mouth: try CharacterColor(red: 0.2, green: 1, blue: 0.5))
    let custom = CharacterTheme.arcade.configured(partColors: colors)
    let a = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: base, width: 320, height: 320,
      environment: .init(reduceTransparency: true))
    let b = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: custom, width: 320, height: 320,
      environment: .init(reduceTransparency: true))

    XCTAssertEqual(a.faceBounds, b.faceBounds)
    XCTAssertEqual(a.nodes.map(\.id), b.nodes.map(\.id))
    XCTAssertEqual(a.nodes.map(\.path), b.nodes.map(\.path))
    XCTAssertEqual(originalState.emotion, .gratitude)
    XCTAssertEqual(b.nodes.first { $0.id == "eye.left" }?.fill, .solid(colors.eyes))
    XCTAssertEqual(b.nodes.first { $0.id == "mouth" }?.stroke, colors.mouth)
  }

  func testBuiltInsKeepMinimalNosesHiddenAndNeverEnableFaceStickers() throws {
    for theme in CharacterTheme.allCases {
      XCTAssertEqual(theme.artDirection.components.contains(.nose), theme == .cat)
      XCTAssertFalse(theme.artDirection.components.contains(.ornaments))
      for emotion in CharacterEmotion.allCases {
        let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
        let pose = ReactiveCharacter.pose(state: state, elapsed: 0.52, reduceMotion: true)
        XCTAssertTrue(pose.accents.isEmpty)
        let scene = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: theme.artDirection, width: 160, height: 160)
        XCTAssertEqual(scene.nodes.contains { $0.id == "nose" }, theme == .cat)
        XCTAssertFalse(scene.nodes.contains { $0.id.hasPrefix("art.accent") })
      }
    }
  }
}

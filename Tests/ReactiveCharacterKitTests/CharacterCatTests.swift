import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterCatTests: XCTestCase {
  private let catDirections: [CharacterArtDirection] = [.cat, .catSimple2D, .catNorwegianForest]
  private let expectedAssets: Set<String> = [
    "cat-head", "cat-neck", "cat-ear-left", "cat-ear-right", "cat-nose",
    "cat-whiskers-left", "cat-whiskers-right",
  ]

  private func pose(
    _ emotion: CharacterEmotion? = nil, time: Double = 0.52,
    reduced: Bool = true
  ) -> CharacterPose {
    let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
    return ReactiveCharacter.pose(
      state: state, elapsed: time, reduceMotion: reduced,
      motionProfile: .cartoon)
  }

  private func scene(_ pose: CharacterPose, direction: CharacterArtDirection = .cat) throws
    -> CharacterScene
  {
    try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 512, height: 512,
      includeBackground: false)
  }

  private func node(_ id: String, _ scene: CharacterScene) throws -> CharacterSceneNode {
    try XCTUnwrap(scene.nodes.first { $0.id == id }, id)
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

  func testCatCatalogIsAnatomyNotReplacementForTheDefault() throws {
    XCTAssertEqual(CharacterArtDirection.black.anatomy, .minimal)
    XCTAssertEqual(CharacterTheme.cat.artDirection.anatomy, .cat(.animated))
    XCTAssertEqual(CharacterTheme.cat.artDirection.assets, .empty)
    XCTAssertEqual(
      Set(CharacterTheme.cat.artDirection.requiredImageAssets.map(\.name)), expectedAssets)
    let rendered = try scene(pose())
    XCTAssertEqual(Set(rendered.nodes.compactMap { $0.image?.asset.name }), expectedAssets)
    XCTAssertNil(rendered.nodes.first { $0.id == "art.face" })
    XCTAssertEqual(try node("cat.ear.left", rendered).layer, .behindSurface)
    XCTAssertEqual(try node("cat.head", rendered).layer, .surface)
    XCTAssertFalse(
      rendered.nodes.contains { $0.id.contains("eyebrow") || $0.id.hasPrefix("art.accent") })
  }

  func testStaticFaceAndGeometryAnatomyCannotHaveDuplicateOwnership() throws {
    let face = try CharacterImageAsset(name: "custom-face")
    let assets = CharacterAssetPack(face: face)
    for anatomy in [
      CharacterAnatomy.cat(.animated), .cat(.simple2D),
      .reference(.norwegianForest(.hero)), .reference(.mascot(variant: .hero)), .portrait(.standard),
    ] {
      XCTAssertThrowsError(
        try CharacterArtDirection(name: "conflict", assets: assets, anatomy: anatomy)
      ) {
        XCTAssertEqual($0 as? CharacterArtDirectionError, .conflictingFaceAsset)
      }
    }
    XCTAssertNoThrow(try CharacterArtDirection(name: "static-face", assets: assets))
  }

  func testUnsupportedAnatomyGeometryAndGlowFailExplicitlyInsteadOfBeingIgnored() {
    for anatomy in [
      CharacterAnatomy.cat(.animated), .cat(.simple2D),
      .reference(.norwegianForest(.hero)), .reference(.mascot(variant: .hero)), .portrait(.standard),
    ] {
      XCTAssertThrowsError(
        try CharacterArtDirection(name: "Invalid rig", layout: .hero, anatomy: anatomy)
      ) {
        XCTAssertEqual(
          $0 as? CharacterArtDirectionError, .unsupportedAnatomyConfiguration(field: "layout"))
      }
      XCTAssertThrowsError(
        try CharacterArtDirection(name: "Invalid glow", featureGlow: 0.4, anatomy: anatomy)
      ) {
        XCTAssertEqual(
          $0 as? CharacterArtDirectionError, .unsupportedAnatomyConfiguration(field: "featureGlow"))
      }
    }
    XCTAssertNoThrow(
      try CharacterArtDirection(
        name: "Minimal remains customizable", layout: .hero, featureGlow: 0.4))
  }

  func testAppearanceReplacementPreservesAnatomyAndResourceContract() throws {
    let colors = CharacterStyle.cat.partColors.replacing(
      eyes: try CharacterColor(red: 0.98, green: 0.61, blue: 0.13))
    let directions = [
      CharacterTheme.cat.configured(eyes: .horizontal, mouth: .outline, partColors: colors),
      CharacterArtDirection.cat.replacingMotionProfile(.companion),
      CharacterArtDirection.cat.replacingPartColors(colors),
    ]
    for direction in directions {
      XCTAssertEqual(direction.anatomy, .cat(.animated))
      XCTAssertEqual(Set(direction.requiredImageAssets.map(\.name)), expectedAssets)
      XCTAssertNotNil(try scene(pose(), direction: direction).nodes.first { $0.id == "cat.head" })
    }
  }

  func testAllCatImagesDecodeTheirDeclaredPNGHeaderAndSharedArtboard() throws {
    for asset in CharacterCatAssets.all {
      let data = try CharacterImageResources.png(asset)
      XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
      XCTAssertEqual(data[25], 6, "RGBA rather than an opaque matte")
      func dimension(_ offset: Int) -> Int {
        data[offset..<offset + 4].reduce(0) { $0 * 256 + Int($1) }
      }
      if CharacterCatAssets.body.contains(asset) {
        XCTAssertEqual(dimension(16), 512)
        XCTAssertEqual(dimension(20), 560)
      }
      XCTAssertGreaterThan(dimension(16), 0)
      XCTAssertGreaterThan(dimension(20), 0)
    }
  }

  func testSVGActuallyEmbedsEveryCatResourceWithoutHostInstallation() throws {
    let rendered = try scene(pose())
    let text = try CharacterSVGRenderer.render(rendered)
    XCTAssertEqual(
      text.components(separatedBy: "data:image/png;base64,").count - 1,
      rendered.nodes.compactMap(\.image).count,
      "Every image node, including fixed ear-root overlap layers, must be embedded")
    XCTAssertFalse(text.contains("source-parts.png"))
    XCTAssertFalse(text.contains("file://"))
    XCTAssertFalse(text.contains("/mnt/"))
    XCTAssertTrue(text.contains("clipPath"))
    let missing = try CharacterImageAsset(name: "missing-cat-artwork", source: .package)
    XCTAssertThrowsError(try CharacterImageResources.png(missing)) {
      XCTAssertEqual(
        $0 as? CharacterImageResolutionError, .unavailable(name: missing.name, source: .package))
    }
  }

  func testEveryEyeContentsSharesExactApertureAndTransform() throws {
    for emotion in CharacterEmotion.allCases {
      let rendered = try scene(pose(emotion))
      for side in ["left", "right"] {
        let sclera = try node("eye.\(side)", rendered)
        for suffix in [
          "iris", "iris.fibers", "iris.caustic", "pupil", "highlight", "highlight.small",
        ] {
          let part = try node("eye.\(side).\(suffix)", rendered)
          XCTAssertEqual(part.clips.first, sclera.path, "\(emotion)/\(side)/\(suffix)")
          XCTAssertEqual(part.transform, sclera.transform)
          XCTAssertEqual(part.opacity > 0, sclera.opacity > 0)
        }
      }
    }
  }

  func testCompactEyesExposeSeparateUpperAndLowerLidContours() throws {
    for emotion in [CharacterEmotion.affection, .calmTrust, .fatigueBurden] {
      let rendered = try scene(pose(emotion))
      for side in ["left", "right"] {
        let upper = try node("eye.\(side).lid", rendered)
        let lower = try node("eye.\(side).lid.lower", rendered)
        XCTAssertFalse(upper.path.commands.isEmpty, "\(emotion)/\(side)/upper")
        XCTAssertFalse(lower.path.commands.isEmpty, "\(emotion)/\(side)/lower")
        XCTAssertNotEqual(upper.path, lower.path, "\(emotion)/\(side)")
        XCTAssertEqual(upper.transform, lower.transform, "\(emotion)/\(side)")
        XCTAssertGreaterThan(lower.opacity, 0, "\(emotion)/\(side)")
      }
    }

    let closed = try scene(pose(.joy))
    XCTAssertEqual(try node("eye.left.lid.lower", closed).opacity, 0)
    XCTAssertEqual(try node("eye.right.lid.lower", closed).opacity, 0)
  }

  func testBlinkChangesApertureButNeverFlattensIrisArtwork() throws {
    let id = try CharacterAnimationID(validating: "cat-blink")
    let state = ReactiveCharacter.act(
      state: .idle, event: .animationStarted(id: id, animation: .blink)
    ).stateAfter
    var irisShapes: [CharacterVectorPath] = []
    var apertures: [CharacterVectorPath] = []
    var opacities: [Double] = []
    for frame in 0...48 {
      let p = ReactiveCharacter.pose(
        state: state, elapsed: Double(frame) / 200,
        motionProfile: .companion)
      let rendered = try scene(p)
      irisShapes.append(try node("eye.left.iris", rendered).path)
      apertures.append(try node("eye.left", rendered).path)
      opacities.append(try node("eye.left", rendered).opacity)
    }
    XCTAssertTrue(irisShapes.allSatisfy { $0 == irisShapes[0] })
    XCTAssertTrue(apertures.contains { $0 != apertures[0] })
    XCTAssertEqual(opacities.min(), 0)
    XCTAssertEqual(opacities.first, 1)
    XCTAssertEqual(opacities.last, 1)
  }

  func testClosedAngryOrHappyApertureHasCoincidentLids() {
    let closed = CharacterEyePose(
      centerX: 0.34, centerY: 0.5, width: 0.19, height: 0.04, angle: 0,
      unblinkedWidth: 0.19, unblinkedHeight: 0.43, blink: 1)
    for contour in [CharacterEyeContour.neutral, .init(crescent: 1), .init(innerPinch: 1)] {
      let eye = CharacterCatEye(
        eye: closed, contour: contour, left: true,
        treatment: .vertical, gazeX: 0, gazeY: 0)
      XCTAssertEqual(eye.closure, 1)
      let p = points(eye.aperture(left: true))
      XCTAssertEqual(p[0].y, p[3].y)
      XCTAssertEqual(p[1], p[5])
      XCTAssertEqual(p[2], p[4])
    }
  }

  func testPupilMorphIsContinuousAcrossFormerHalfwayThreshold() throws {
    var a = pose()
    a.eyeContours = .init(left: .init(heart: 0.4999), right: .neutral)
    var b = a
    b.eyeContours = .init(left: .init(heart: 0.5001), right: .neutral)
    let lhs = points(try node("eye.left.pupil", scene(a)).path)
    let rhs = points(try node("eye.left.pupil", scene(b)).path)
    XCTAssertEqual(lhs.count, rhs.count)
    for (l, r) in zip(lhs, rhs) {
      XCTAssertLessThan(abs(l.x - r.x) + abs(l.y - r.y), 0.02)
    }
  }

  func testSurpriseDilatesFelinePupilAndHasReadableOpenMouth() throws {
    let neutral = try scene(pose())
    let surprised = try scene(pose(.surprise))
    func bounds(_ path: CharacterVectorPath) -> (width: Double, height: Double) {
      let p = points(path)
      return (
        p.map(\.x).max()! - p.map(\.x).min()!,
        p.map(\.y).max()! - p.map(\.y).min()!
      )
    }
    let neutralPupil = bounds(try node("eye.left.pupil", neutral).path)
    let surprisePupil = bounds(try node("eye.left.pupil", surprised).path)
    XCTAssertGreaterThan(surprisePupil.width, neutralPupil.width * 1.8)
    XCTAssertGreaterThan(
      surprisePupil.height / surprisePupil.width, 1.8,
      "Even a dilated surprise pupil must remain recognizably feline and vertically oriented")
    XCTAssertGreaterThan(
      bounds(try node("eye.left.iris", surprised).path).width,
      bounds(try node("eye.left.iris", neutral).path).width * 0.75,
      "Surprise opens lids and dilates the pupil instead of collapsing the iris")
    let mouth = points(try node("mouth", surprised).path)
    let w = mouth.map(\.x).max()! - mouth.map(\.x).min()!
    let h = mouth.map(\.y).max()! - mouth.map(\.y).min()!
    XCTAssertGreaterThan(w / h, 0.5, "Open O must not collapse into a tongue-like slit")
  }

  func testEarAndWhiskerResponsesAreDerivedNotFrozenOnHead() throws {
    let neutral = try scene(pose())
    let sad = try scene(pose(.angerIrritation))
    for id in ["cat.ear.left", "cat.ear.right", "cat.whiskers.left", "cat.whiskers.right"] {
      XCTAssertNotEqual(try node(id, neutral).transform, try node(id, sad).transform)
      XCTAssertEqual(try node(id, neutral).image?.asset, try node(id, sad).image?.asset)
    }
  }

  func testEyesCannotOverlapAtExtremeAttentionAndEveryTreatment() throws {
    for treatment in CharacterEyeTreatment.allCases {
      for x in [0.0, 0.5, 1.0] {
        for y in [0.0, 0.5, 1.0] {
          let focus = try CharacterPoint(validatingX: x, y: y)
          let state = ReactiveCharacter.act(state: .idle, event: .attentionFocused(focus))
            .stateAfter
          let p = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
          let rendered = try scene(p, direction: CharacterTheme.cat.configured(eyes: treatment))
          let left = points(try node("eye.left", rendered).path)
          let right = points(try node("eye.right", rendered).path)
          XCTAssertLessThan(left.map(\.x).max()!, right.map(\.x).min()!)
          XCTAssertGreaterThan(left.map(\.x).min()!, 65)
          XCTAssertLessThan(right.map(\.x).max()!, 465)
        }
      }
    }
  }

  func testAmberIrisCustomizationChangesPaintNotAnatomy() throws {
    let colors = CharacterStyle.cat.partColors.replacing(
      eyes: try CharacterColor(red: 1, green: 0.64, blue: 0.10))
    let a = try scene(pose(.angerIrritation))
    let b = try scene(pose(.angerIrritation), direction: .cat.replacingPartColors(colors))
    XCTAssertEqual(a.nodes.map(\.path), b.nodes.map(\.path))
    XCTAssertEqual(a.nodes.compactMap(\.image), b.nodes.compactMap(\.image))
    XCTAssertNotEqual(try node("eye.left.iris", a).fill, try node("eye.left.iris", b).fill)
  }

  func testTransparentComponentsRequireOnlyRequestedResources() throws {
    let direction = try CharacterArtDirection(
      name: "Eyes only", components: .eyes,
      style: .cat, surface: .transparent, anatomy: .cat(.animated))
    let rendered = try scene(pose(), direction: direction)
    XCTAssertTrue(direction.requiredImageAssets.isEmpty)
    XCTAssertTrue(rendered.nodes.allSatisfy { $0.image == nil && $0.id.hasPrefix("eye.") })
    let svg = try CharacterSVGRenderer.render(rendered)
    XCTAssertFalse(svg.contains("data:image/png"))
  }

  func testAllAnimationsAndInterruptedEmotionHandoffsProduceValidRealScenes() throws {
    for animation in CharacterAnimation.allCases {
      let id = try CharacterAnimationID(validating: animation.rawValue)
      let state = ReactiveCharacter.act(
        state: .idle, event: .animationStarted(id: id, animation: animation)
      ).stateAfter
      for frame in 0...24 {
        let p = ReactiveCharacter.pose(
          state: state, elapsed: Double(frame) * animation.duration / 24,
          motionProfile: .cartoon)
        try CharacterSceneValidation.validate(scene(p))
      }
    }
    var session = CharacterPresentationSession(at: 0)
    for (index, emotion) in CharacterEmotion.allCases.enumerated() {
      let time = Double(index) * 0.09
      let state = ReactiveCharacter.act(
        state: session.inspect(at: time).state,
        event: .emotionChanged(emotion)
      ).stateAfter
      session.update(state: state, at: time, motionProfile: .cartoon, transitionProfile: .cartoon)
      for dt in [0.0, 0.03, 0.06] {
        let p = session.pose(at: time + dt, motionProfile: .cartoon)
        XCTAssertEqual(try scene(p), try scene(p))
        XCTAssertEqual(session.inspect(at: time + dt).state, state)
      }
    }
  }

  func testAnatomicalRestMouthNeverFabricatesCommunication() throws {
    let state = CharacterState.idle
    let p = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
    XCTAssertFalse(p.mouth.visible)
    XCTAssertNotNil(try scene(p).nodes.first { $0.id == "mouth" })
    XCTAssertEqual(state.communication, .silent)
    XCTAssertFalse(ReactiveCharacter.inspect(state: state).mouthRequested)
  }

  func testTaskAndCancellationRemainHostOwnedAcrossThemeSwitches() throws {
    let task = try CharacterTaskID(validating: "real-operation")
    var state = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: task)).stateAfter
    state =
      ReactiveCharacter.act(state: state, event: .agentProgress(taskID: task, progress: 0.4))
      .stateAfter
    let receipt = ReactiveCharacter.act(
      state: state, event: .agentCancellationRequested(taskID: task))
    XCTAssertEqual(receipt.effects, [.cancelAgent(taskID: task)])
    let committed = receipt.stateAfter
    for theme in CharacterTheme.allCases {
      let p = ReactiveCharacter.pose(state: committed, elapsed: 0.4, reduceMotion: true)
      _ = try scene(p, direction: theme.artDirection)
      XCTAssertEqual(ReactiveCharacter.inspect(state: committed).activeTaskID, task)
    }
    let ended = ReactiveCharacter.act(state: committed, event: .agentCancelled(taskID: task))
    XCTAssertNil(ReactiveCharacter.inspect(state: ended.stateAfter).activeTaskID)
    let duplicate = ReactiveCharacter.act(
      state: ended.stateAfter, event: .agentProgress(taskID: task, progress: 0.8))
    XCTAssertEqual(duplicate.stateAfter, ended.stateAfter)
    XCTAssertTrue(duplicate.effects.isEmpty)
  }

  func testCatSelectionHasOneExplicitAnatomyOwner() throws {
    XCTAssertEqual(CharacterTheme.cat.artDirection.anatomy, .cat(.animated))
    XCTAssertEqual(CharacterArtDirection.catSimple2D.anatomy, .cat(.simple2D))
    XCTAssertEqual(CharacterArtDirection.catNorwegianForest.anatomy,
                   .reference(.norwegianForest(.hero)))
    XCTAssertEqual(CharacterProceduralCatTheme.allCases, [.animated, .simple2D])
    XCTAssertEqual(
      CharacterArtDirection.catSimple2D.replacingFaceTreatment(eyes: .horizontal).anatomy,
      .cat(.simple2D))

    for direction in catDirections {
      XCTAssertEqual(direction.style.eyeTreatment, .vertical)
      let rendered = try scene(pose(), direction: direction)
      switch direction.anatomy {
      case .cat(.animated):
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.head" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.ear.left" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.ear.right" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "eye.left.pupil" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "eye.right.pupil" })
        XCTAssertEqual(Set(direction.requiredImageAssets.map(\.name)), expectedAssets)
        XCTAssertTrue(rendered.nodes.contains { $0.image != nil })
      case .cat(.simple2D):
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.head" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.ear.left" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.ear.right" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "cat.face.patch" })
        XCTAssertNil(rendered.nodes.first { $0.id == "eye.left.pupil" })
        XCTAssertTrue(direction.requiredImageAssets.isEmpty)
        XCTAssertTrue(rendered.nodes.allSatisfy { $0.image == nil })
      case .reference:
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.body" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.earLeft" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.earRight" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.mane" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.eyeLeft" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.eyeRight" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.irisLeft" })
        XCTAssertNotNil(rendered.nodes.first { $0.id == "reference.irisRight" })
        XCTAssertFalse(direction.requiredImageAssets.isEmpty)
        XCTAssertTrue(direction.requiredImageAssets.allSatisfy { $0.name.hasPrefix("reference-norwegian-") })
        XCTAssertTrue(rendered.nodes.contains { $0.image != nil })
      default:
        XCTFail("Unexpected cat anatomy: \(direction.anatomy)")
      }
    }
  }

  func testAuthoredCatEarRootIsStationaryOverlapUnderMovingEar() throws {
    for direction in [CharacterArtDirection.cat, .catNorwegianForest] {
      let neutral = try scene(pose(), direction: direction)
      let angry = try scene(pose(.angerIrritation), direction: direction)
      for side in ["left", "right"] {
        let movingID: String
        let baseID: String
        switch direction.anatomy {
        case .cat(.animated):
          movingID = "cat.ear.\(side)"
          baseID = "cat.ear.\(side).base"
        case .reference:
          movingID = "reference.ear\(side.capitalized)"
          baseID = "reference.ear\(side.capitalized).root"
        default:
          return XCTFail("This test requires authored ear images")
        }
        let movingNeutral = try node(movingID, neutral)
        let movingAngry = try node(movingID, angry)
        let baseNeutral = try node(baseID, neutral)
        let baseAngry = try node(baseID, angry)
        XCTAssertNotEqual(movingNeutral.transform, movingAngry.transform)
        XCTAssertEqual(baseNeutral.transform, baseAngry.transform)
        XCTAssertEqual(baseNeutral.image?.asset, movingNeutral.image?.asset)
        XCTAssertEqual(baseNeutral.clips.count, 1)
        XCTAssertFalse(baseNeutral.clips[0].commands.isEmpty)
        XCTAssertEqual(baseNeutral.layer, .behindSurface)
      }
    }
  }

  func testCatEyeConsumesContourScaleAndSeparatesBlinkFromProjection() {
    let source = CharacterEyePose(
      centerX: 0.34, centerY: 0.5, width: 0.19, height: 0.43, angle: 0,
      unblinkedWidth: 0.19, unblinkedHeight: 0.43, blink: 0.25)
    let neutral = CharacterCatEye(
      eye: source, contour: .neutral, left: true,
      treatment: .vertical, gazeX: 0, gazeY: 0)
    let scaled = CharacterCatEye(
      eye: source, contour: .init(widthScale: 1.24, heightScale: 0.76), left: true,
      treatment: .vertical, gazeX: 0, gazeY: 0)
    let elliptical = CharacterCatEye(
      eye: source, contour: .init(ellipse: 1), left: true,
      treatment: .vertical, gazeX: 0, gazeY: 0)
    XCTAssertGreaterThan(scaled.width, neutral.width)
    XCTAssertLessThan(scaled.height, neutral.height)
    XCTAssertNotEqual(elliptical.aperture(left: true), neutral.aperture(left: true))
    XCTAssertEqual(neutral.closure, 0.25, accuracy: 1e-12)

    let foreshortened = CharacterEyePose(
      centerX: 0.34, centerY: 0.5, width: 0.13, height: 0.31, angle: 0,
      unblinkedWidth: 0.13, unblinkedHeight: 0.31, blink: 0.25)
    let projected = CharacterCatEye(
      eye: foreshortened, contour: .neutral, left: true,
      treatment: .vertical, gazeX: 1, gazeY: 0)
    XCTAssertEqual(projected.closure, neutral.closure, accuracy: 1e-12)
  }

  func testNeutralCatPupilIsLongNarrowVerticalSlitAcrossProceduralThemes() throws {
    func bounds(_ path: CharacterVectorPath) -> (Double, Double) {
      let p = points(path)
      return (p.map(\.x).max()! - p.map(\.x).min()!, p.map(\.y).max()! - p.map(\.y).min()!)
    }
    for direction in [CharacterArtDirection.cat, .catSimple2D] {
      let rendered = try scene(pose(), direction: direction)
      for side in ["left", "right"] {
        let id = direction.anatomy == .cat(.simple2D) ? "eye.\(side)" : "eye.\(side).pupil"
        let (width, height) = bounds(try node(id, rendered).path)
        XCTAssertGreaterThan(
          height / width, direction.anatomy == .cat(.simple2D) ? 2.2 : 4.0, "\(direction.anatomy)/\(side)")
      }
    }

    let norwegian = try scene(pose(), direction: CharacterArtDirection.catNorwegianForest)
    XCTAssertNotNil(norwegian.nodes.first { $0.id == "reference.eyeLeft" })
    XCTAssertNotNil(norwegian.nodes.first { $0.id == "reference.irisLeft" })
    XCTAssertTrue(norwegian.nodes.contains { $0.id.hasPrefix("reference.eye") || $0.id.hasPrefix("reference.iris") })
  }

  func testThreeCatThemesCoverEveryExpressionNineGazescapesAndReduceMotion() throws {
    let emotions: [CharacterEmotion?] = [nil] + CharacterEmotion.allCases.map(Optional.some)
    for direction in catDirections {
      for emotion in emotions {
        for x in [0.0, 0.5, 1.0] {
          for y in [0.0, 0.5, 1.0] {
            var state = ReactiveCharacter.act(
              state: .idle, event: .emotionChanged(emotion)
            ).stateAfter
            state =
              ReactiveCharacter.act(
                state: state,
                event: .attentionFocused(try CharacterPoint(validatingX: x, y: y))
              ).stateAfter
            for reduceMotion in [false, true] {
              let p = ReactiveCharacter.pose(
                state: state, elapsed: 0.52, reduceMotion: reduceMotion,
                projection: direction.projection, motionProfile: direction.motionProfile)
              let rendered = try scene(p, direction: direction)
              try CharacterSceneValidation.validate(rendered)
              switch direction.anatomy {
              case .cat(.animated):
                XCTAssertTrue(rendered.nodes.contains { $0.id == "eye.left" })
                XCTAssertTrue(rendered.nodes.contains { $0.id == "eye.right" })
                XCTAssertTrue(rendered.nodes.contains { $0.id == "eye.left.pupil" })
              case .cat(.simple2D):
                XCTAssertTrue(rendered.nodes.contains { $0.id == "eye.left" })
                XCTAssertTrue(rendered.nodes.contains { $0.id == "eye.right" })
                XCTAssertFalse(rendered.nodes.contains { $0.id == "eye.left.pupil" })
              case .reference:
                XCTAssertTrue(rendered.nodes.contains { $0.id.hasPrefix("reference.eyeLeft") })
                XCTAssertTrue(rendered.nodes.contains { $0.id.hasPrefix("reference.eyeRight") })
                let leftHasImage = rendered.nodes.contains { $0.id == "reference.irisLeft" }
                let rightHasImage = rendered.nodes.contains { $0.id == "reference.irisRight" }
                let leftClosed = rendered.nodes.contains { $0.id == "reference.eyeLeft.upper" }
                let rightClosed = rendered.nodes.contains { $0.id == "reference.eyeRight.upper" }
                XCTAssertTrue(leftHasImage || leftClosed)
                XCTAssertTrue(rightHasImage || rightClosed)
              default:
                XCTFail("Unexpected cat anatomy: \(direction.anatomy)")
              }
              XCTAssertFalse(rendered.nodes.contains { $0.id.lowercased().contains("eyebrow") })
            }
          }
        }
      }
    }
  }

  func testThreeCatThemesRemainValidDuringBlinkAndInterruptedExpressionHandoffs() throws {
    let animationID = try CharacterAnimationID(validating: "cat-theme-blink")
    let blinkState = ReactiveCharacter.act(
      state: .idle, event: .animationStarted(id: animationID, animation: .blink)
    ).stateAfter
    for direction in catDirections {
      for time in [0.0, 0.04, 0.08, 0.12, 0.20, 0.28] {
        let p = ReactiveCharacter.pose(
          state: blinkState, elapsed: time,
          projection: direction.projection,
          motionProfile: direction.motionProfile)
        try CharacterSceneValidation.validate(try scene(p, direction: direction))
      }

      var session = CharacterPresentationSession(at: 0)
      for (index, emotion) in CharacterEmotion.allCases.enumerated() {
        let time = Double(index) * 0.045
        let next = ReactiveCharacter.act(
          state: session.inspect(at: time).state,
          event: .emotionChanged(emotion)
        ).stateAfter
        session.update(
          state: next, at: time,
          motionProfile: direction.motionProfile,
          transitionProfile: direction.transitionProfile)
        for dt in [0.0, 0.015, 0.03] {
          let p = session.pose(at: time + dt, motionProfile: direction.motionProfile)
          try CharacterSceneValidation.validate(try scene(p, direction: direction))
          XCTAssertEqual(session.inspect(at: time + dt).state, next)
        }
      }
    }
  }

  func testPresentationGazeBridgePreservesBlinkDecomposition() throws {
    let animationID = try CharacterAnimationID(validating: "cat-gaze-during-blink")
    let blinkState = ReactiveCharacter.act(
      state: .idle, event: .animationStarted(id: animationID, animation: .blink)
    ).stateAfter
    var session = CharacterPresentationSession(state: blinkState, at: 0)
    let transitionTime = 0.08
    let before = session.pose(at: transitionTime)
    XCTAssertGreaterThan(before.eyes.left.blink, 0)
    XCTAssertGreaterThan(before.eyes.left.unblinkedHeight, before.eyes.left.height)

    let focused = ReactiveCharacter.act(
      state: blinkState,
      event: .attentionFocused(try CharacterPoint(validatingX: 0.92, y: 0.28))
    ).stateAfter
    session.update(state: focused, at: transitionTime)
    let bridged = session.pose(at: transitionTime + 0.01)
    XCTAssertGreaterThan(bridged.eyes.left.blink, 0)
    XCTAssertGreaterThan(bridged.eyes.left.unblinkedHeight, bridged.eyes.left.height)
  }

}

import Foundation
import XCTest

@testable import ReactiveCharacterKit

#if canImport(FoundationXML)
  import FoundationXML
#endif

final class CharacterSceneTests: XCTestCase {

  func testSVGRejectsNonFiniteSceneBeforeSerialization() throws {
    let bad = CharacterScene(
      width: 100, height: 100,
      faceBounds: .init(.init(x: 0, y: 0, width: 100, height: 100)),
      surfaceTransform: .init(a: 1, b: 0, c: 0, d: 1, tx: .infinity, ty: 0),
      nodes: [], effectiveMode: .flat, isCompact: false)
    XCTAssertThrowsError(try CharacterSVGRenderer.render(bad))
  }

  func testNarrowMouthUsesReadableAspectWithoutChangingPose() throws {
    let original = try CharacterDesign.load(.white)
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.3, reduceMotion: true)
    XCTAssertEqual(pose.mouth.glyph, .puckerO)
    for minimumAspect in [0.35, 0.7] {
      var profile = original.profile
      profile.rendering.minimumMouthAspect = minimumAspect
      let design = try profile.compile()
      let frame = try CharacterSceneBuilder.scene(
        pose: pose, design: design, width: 384, height: 384)
      let node = try XCTUnwrap(frame.nodes.first { $0.id == "mouth" })
      let points: [CharacterVectorPoint] = node.path.commands.flatMap {
        command -> [CharacterVectorPoint] in
        switch command {
        case .move(let p), .line(let p): [p]
        case .quad(let c, let p): [c, p]
        case .cubic(let c1, let c2, let p): [c1, c2, p]
        case .close: []
        }
      }
      let width = try XCTUnwrap(points.map(\.x).max()) - XCTUnwrap(points.map(\.x).min())
      let height = try XCTUnwrap(points.map(\.y).max()) - XCTUnwrap(points.map(\.y).min())
      XCTAssertGreaterThanOrEqual(width / height, minimumAspect - 1e-12)
      let numericAspect = 0.27 * pose.mouth.width / (0.009 + 0.16 * pose.mouth.openness)
      XCTAssertEqual(width / height, max(numericAspect, minimumAspect), accuracy: 1e-12)
      XCTAssertEqual(pose, ReactiveCharacter.pose(state: state, elapsed: 0.3, reduceMotion: true))
    }
  }

  private func pose(
    _ emotion: CharacterEmotion? = .joy, design: CharacterDesign, time: Double = 1.2
  ) -> CharacterPose {
    ReactiveCharacter.pose(
      state: ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state,
      elapsed: time, projection: design.projection, motionProfile: design.motionProfile)
  }

  private func scene(
    _ d: CharacterDesign, size: Double = 384,
    environment: CharacterDesignEnvironment = .init()
  ) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: pose(design: d), design: d, width: size, height: size,
      environment: environment, includeBackground: true)
  }

  private func assertScene(
    _ scene: CharacterScene, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(Set(scene.nodes.map(\.id)).count, scene.nodes.count, file: file, line: line)
    XCTAssertEqual(
      scene.nodes.map(\.layer.rawValue), scene.nodes.map(\.layer.rawValue).sorted(), file: file,
      line: line)
    for node in scene.nodes {
      XCTAssertTrue(node.lineWidth.isFinite && node.lineWidth > 0, node.id, file: file, line: line)
      XCTAssertTrue((0...1).contains(node.opacity), node.id, file: file, line: line)
      let t = node.transform
      XCTAssertTrue(
        [t.a, t.b, t.c, t.d, t.tx, t.ty].allSatisfy(\.isFinite), node.id, file: file, line: line)
      for path in [node.path] + node.clips {
        for command in path.commands {
          let points: [CharacterVectorPoint]
          switch command {
          case .move(let p), .line(let p): points = [p]
          case .quad(let c, let p): points = [c, p]
          case .cubic(let c1, let c2, let p): points = [c1, c2, p]
          case .close: points = []
          }
          XCTAssertTrue(
            points.allSatisfy { $0.x.isFinite && $0.y.isFinite }, node.id, file: file, line: line)
        }
      }
    }
  }

  func testFullExpressionMatrixIsDeterministicFiniteAndXMLValid() throws {
    // 4 × 13 × 2 × 3 sizes × 3 times = 936 production-generated scenes.
    for preset in CharacterDesignPreset.allCases {
      let design = try CharacterDesign.load(preset)
      for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
        for appearance in CharacterDesignAppearance.allCases {
          for size in [32.0, 144, 512] {
            for time in [0.0, 0.27, 1.2] {
              let p = pose(emotion, design: design, time: time)
              let a = try CharacterSceneBuilder.scene(
                pose: p, design: design, width: size, height: size,
                environment: .init(appearance: appearance))
              XCTAssertEqual(
                a,
                try CharacterSceneBuilder.scene(
                  pose: p, design: design, width: size, height: size,
                  environment: .init(appearance: appearance)))
              assertScene(a)
              if time == 1.2, size == 144 {
                let svg = try CharacterSVGRenderer.render(a)
                XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
              }
            }
          }
        }
      }
    }
  }

  func testEachAnimationAndWritingPathProducesValidScenes() throws {
    for preset in CharacterDesignPreset.allCases {
      let d = try CharacterDesign.load(preset)
      for animation in CharacterAnimation.allCases {
        var state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.interest)).state
        state =
          ReactiveCharacter.reduce(
            state: state,
            event: .animationStarted(id: CharacterAnimationID(UUID()), animation: animation)
          ).state
        for time in [0.0, 0.05, 0.2, 0.7, 2.0] {
          let p = ReactiveCharacter.pose(
            state: state, elapsed: time, projection: d.projection, motionProfile: d.motionProfile)
          assertScene(try CharacterSceneBuilder.scene(pose: p, design: d, width: 320, height: 280))
        }
      }
      let id = CharacterTaskID(UUID())
      var state = ReactiveCharacter.reduce(state: .idle, event: .agentStarted(taskID: id)).state
      state =
        ReactiveCharacter.reduce(state: state, event: .agentProgress(taskID: id, progress: 0.65))
        .state
      let p = ReactiveCharacter.pose(
        state: state, elapsed: 3.7, projection: d.projection, motionProfile: d.motionProfile)
      let s = try CharacterSceneBuilder.scene(pose: p, design: d, width: 320, height: 320)
      XCTAssertTrue(s.nodes.contains { $0.id == "writing.pen" })
      XCTAssertTrue(s.nodes.contains { $0.id == "writing.progress" })
      assertScene(s)
    }
  }

  func testRendererModesAndSilhouettesActuallyChangeOutput() throws {
    var p = try CharacterDesign.load(.black).profile
    var modes: [CharacterScene] = []
    for mode in CharacterRenderMode.allCases {
      p.rendering.mode = mode
      let s = try scene(p.compile())
      assertScene(s)
      modes.append(s)
      XCTAssertEqual(s.effectiveMode, mode)
    }
    XCTAssertNotEqual(modes[0].nodes, modes[1].nodes)
    XCTAssertNotEqual(modes[1].nodes, modes[2].nodes)
    var bodies: [CharacterVectorPath] = []
    for silhouette in CharacterSilhouette.allCases {
      p.rendering.silhouette = silhouette
      bodies.append(try XCTUnwrap(scene(p.compile()).nodes.first { $0.id == "surface.body" }).path)
    }
    XCTAssertNotEqual(bodies[0], bodies[1])
    XCTAssertNotEqual(bodies[1], bodies[2])
  }

  func testSurfaceLightingSelectsRealLinearOrRadialPaint() throws {
    var p = try CharacterDesign.load(.black).profile
    p.rendering.lighting = .linear
    let linear = try scene(p.compile())
    let body = try XCTUnwrap(linear.nodes.first { $0.id == "surface.body" })
    guard case .linear = body.fill else { return XCTFail("Expected linear body paint") }
    XCTAssertTrue(try CharacterSVGRenderer.render(linear).contains("<linearGradient"))
    p.rendering.lighting = .radial
    let radialBody = try XCTUnwrap(scene(p.compile()).nodes.first { $0.id == "surface.body" })
    guard case .radial = radialBody.fill else { return XCTFail("Expected radial body paint") }
  }

  func testLayoutFitAlignmentAndAspectAreConsumed() throws {
    var p = try CharacterDesign.load(.black).profile
    var bounds: [CharacterRenderBounds] = []
    for fit in CharacterDesignFit.allCases {
      p.layout.fit = fit
      let d = try p.compile()
      bounds.append(
        try CharacterSceneBuilder.scene(pose: pose(design: d), design: d, width: 600, height: 300)
          .faceBounds)
    }
    XCTAssertNotEqual(bounds[0], bounds[1])
    XCTAssertNotEqual(bounds[1], bounds[2])
    p.layout.fit = .contain
    p.layout.alignmentX = 0
    let d0 = try p.compile()
    let s0 = try CharacterSceneBuilder.scene(
      pose: pose(design: d0), design: d0, width: 600, height: 300)
    p.layout.alignmentX = 1
    let d1 = try p.compile()
    let s1 = try CharacterSceneBuilder.scene(
      pose: pose(design: d1), design: d1, width: 600, height: 300)
    XCTAssertGreaterThan(s1.faceBounds.x, s0.faceBounds.x)
    XCTAssertEqual(s0.faceBounds.width, s1.faceBounds.width)
  }

  func testDisabledComponentsAndSurfaceProduceNoCorrespondingNodes() throws {
    var p = try CharacterDesign.load(.black).profile
    p.components = [.eyes]
    p.rendering.surfaceVisible = false
    p.accessories = [.recommended(.crown)]
    let s = try scene(p.compile())
    XCTAssertTrue(s.nodes.contains { $0.id == "eye.left" })
    for prefix in ["surface.", "mouth", "writing.", "accent.", "accessory."] {
      XCTAssertFalse(s.nodes.contains { $0.id.hasPrefix(prefix) })
    }
  }

  func testEachAccessoryHasActualGeometryAndSimultaneousAccessoriesRetainOrder() throws {
    for preset in CharacterDesignPreset.allCases {
      var p = try CharacterDesign.load(preset).profile
      for glyph in CharacterDesignAccessoryGlyph.allCases {
        p.accessories = [.recommended(glyph)]
        let a = p.accessories[0]
        let s = try scene(p.compile())
        XCTAssertTrue(s.nodes.contains { $0.id.hasPrefix("accessory.\(a.id).") })
        assertScene(s)
      }
      p.accessories = CharacterDesignAccessoryGlyph.allCases.map { .recommended($0) }
      p.accessories[0].layer = .behindSurface
      p.accessories[1].layer = .behindFeatures
      let s = try scene(p.compile())
      for a in p.accessories {
        XCTAssertTrue(s.nodes.contains { $0.id.hasPrefix("accessory.\(a.id).") })
      }
      assertScene(s)
      p.accessories[0].opacity = 0
      let hidden = try scene(p.compile())
      XCTAssertFalse(hidden.nodes.contains { $0.id.hasPrefix("accessory.\(p.accessories[0].id).") })
    }
  }

  func testAppearanceChangesPaintNotGeometryAndDoesNotResetPresentation() throws {
    let d = try CharacterDesign.load(.black)
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let session = CharacterPresentationSession(state: state, at: 10)
    let before = session.pose(at: 10.4, projection: d.projection, motionProfile: d.motionProfile)
    var p = d.profile
    p.palettes.light.feature = "#E8CCFF"
    p.layout.face.x = 0.09
    let changed = try p.compile()
    _ = try CharacterSceneBuilder.scene(pose: before, design: changed, width: 200, height: 200)
    XCTAssertEqual(
      before, session.pose(at: 10.4, projection: d.projection, motionProfile: d.motionProfile))
    let light = try scene(d)
    let dark = try scene(d, environment: .init(appearance: .dark))
    XCTAssertEqual(
      light.nodes, dark.nodes, "built-in palettes are explicit and system-appearance invariant")
    XCTAssertEqual(light.nodes.map(\.path), dark.nodes.map(\.path))
    XCTAssertEqual(light.surfaceTransform, dark.surfaceTransform)
  }

  func testAccessibilityOverridesArePresentationOnlyAndSuppressTranslucentDecorations() throws {
    var p = try CharacterDesign.load(.black).profile
    p.accessories = [.recommended(.roundGlasses)]
    let d = try p.compile()
    for environment in [
      CharacterDesignEnvironment(increasedContrast: true), .init(reduceTransparency: true),
    ] {
      let s = try scene(d, environment: environment)
      XCTAssertEqual(s.effectiveMode, .flat)
      XCTAssertFalse(
        s.nodes.contains { ["surface.shadow", "surface.light", "surface.rim"].contains($0.id) })
      XCTAssertFalse(s.nodes.contains { $0.id.hasPrefix("eye.near") || $0.id.hasPrefix("eye.far") })
      assertScene(s)
    }
    XCTAssertEqual(d.profile.rendering.mode, .sculpted)
    let s = try scene(d, environment: .init(increasedContrast: true))
    let body = try XCTUnwrap(s.nodes.first { $0.id == "surface.body" })
    let eye = try XCTUnwrap(s.nodes.first { $0.id == "eye.left" })
    if case .solid(let background) = body.fill, case .solid(let foreground) = eye.fill {
      XCTAssertEqual(background.contrastRatio(with: foreground), 21, accuracy: 0.001)
    } else {
      XCTFail("Expected opaque high-contrast solid paints")
    }
  }

  func testCompactModeRemovesOnlyOptionalOrnamentsAndSurfaceEffects() throws {
    let d = try CharacterDesign.load(.black)
    let small = try scene(d, size: 48)
    let large = try scene(d)
    XCTAssertTrue(small.isCompact)
    XCTAssertFalse(large.isCompact)
    XCTAssertTrue(small.nodes.contains { $0.id == "eye.left" })
    XCTAssertTrue(small.nodes.contains { $0.id == "mouth" })
    XCTAssertFalse(small.nodes.contains { $0.id.hasPrefix("accent.") || $0.id == "surface.light" })
    XCTAssertGreaterThan(large.nodes.count, small.nodes.count)
  }

  func testInvalidViewportAndOverlayPayloadFailInsteadOfRenderingSuccess() throws {
    let d = try CharacterDesign.load(.black)
    let p = pose(design: try CharacterDesign.load(.black))
    for size in [0.0, 0.5, -1, .nan, .infinity, 16_385] {
      XCTAssertThrowsError(
        try CharacterSceneBuilder.scene(pose: p, design: d, width: size, height: 100))
    }
    let bad = CharacterAccentPose(
      kind: .ring, centerX: .nan, centerY: 0.5, width: 0.1,
      height: 0.1, angle: 0, opacity: 1)
    XCTAssertThrowsError(
      try CharacterSceneBuilder.scene(
        pose: p, design: d, width: 100, height: 100, overlayAccents: [bad]))
    let a = CharacterAccentPose(
      kind: .ring, centerX: 0.5, centerY: 0.5, width: 0.1,
      height: 0.1, angle: 0, opacity: 1)
    XCTAssertThrowsError(
      try CharacterSceneBuilder.scene(
        pose: p, design: d, width: 100, height: 100, overlayAccents: Array(repeating: a, count: 33))
    )
  }

  func testExtremeValidMotionCommunicationAndLongClocksRemainFinite() throws {
    for preset in CharacterDesignPreset.allCases {
      var profile = try CharacterDesign.load(preset).profile
      profile.motion = .init(
        projection: .softSphere, expressiveness: 1.5,
        trailStrength: 1.5, accentStrength: 1.5, idleStrength: 1.5)
      let d = try profile.compile()
      for emotion in CharacterEmotion.allCases {
        for event in [CharacterEvent.chatStarted, .voiceStarted, .voiceLevelChanged(1)] {
          var state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
          state = ReactiveCharacter.reduce(state: state, event: .voiceStarted).state
          state = ReactiveCharacter.reduce(state: state, event: event).state
          for time in [0.1, 0.9, 1e20] {
            let p = ReactiveCharacter.pose(
              state: state, elapsed: time, projection: d.projection,
              motionProfile: d.motionProfile)
            assertScene(
              try CharacterSceneBuilder.scene(pose: p, design: d, width: 16_384, height: 1024))
          }
        }
      }
    }
  }

  func testReducedMotionDesignFramesAreTimeIndependent() throws {
    for preset in CharacterDesignPreset.allCases {
      let d = try CharacterDesign.load(preset)
      let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
      let p1 = ReactiveCharacter.pose(
        state: state, elapsed: 0, reduceMotion: true,
        projection: d.projection, motionProfile: d.motionProfile)
      let p2 = ReactiveCharacter.pose(
        state: state, elapsed: 400, reduceMotion: true,
        projection: d.projection, motionProfile: d.motionProfile)
      XCTAssertEqual(
        try CharacterSceneBuilder.scene(pose: p1, design: d, width: 200, height: 200),
        try CharacterSceneBuilder.scene(pose: p2, design: d, width: 200, height: 200))
    }
  }

  func testSVGIsDeterministicEscapedScopedAndContainsNoExternalResources() throws {
    let d = try CharacterDesign.load(.white)
    let s = try scene(d)
    let svg = try CharacterSVGRenderer.render(s, title: "<test> & \"quote\"", idPrefix: "preview-1")
    XCTAssertEqual(
      svg, try CharacterSVGRenderer.render(s, title: "<test> & \"quote\"", idPrefix: "preview-1"))
    XCTAssertTrue(svg.contains("&lt;test&gt; &amp; &quot;quote&quot;"))
    XCTAssertTrue(svg.contains("aria-labelledby=\"ck-preview-1-title\""))
    XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    for forbidden in ["<script", "<image", "<foreignObject", "href=", "NaN", "nan", "infinity"] {
      XCTAssertFalse(svg.contains(forbidden))
    }
    XCTAssertNoThrow(try CharacterSVGRenderer.render(s, idPrefix: "custom.theme-v1"))
    XCTAssertThrowsError(try CharacterSVGRenderer.render(s, idPrefix: "bad id"))
    XCTAssertThrowsError(try CharacterSVGRenderer.render(s, title: "bad\nlabel"))
    XCTAssertThrowsError(
      try CharacterSVGRenderer.render(s, title: String(repeating: "a", count: 513)))
  }

  func testSVGAllClipAndPaintReferencesResolveToUniqueLocalIDs() throws {
    let svg = try CharacterSVGRenderer.render(scene(CharacterDesign.load(.black)))
    let ids = try NSRegularExpression(pattern: "id=\"([^\"]+)\"")
      .matches(in: svg, range: NSRange(svg.startIndex..., in: svg))
      .map { String(svg[Range($0.range(at: 1), in: svg)!]) }
    let references = try NSRegularExpression(pattern: "url\\(#([^\\)]+)\\)")
      .matches(in: svg, range: NSRange(svg.startIndex..., in: svg))
      .map { String(svg[Range($0.range(at: 1), in: svg)!]) }
    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertFalse(references.isEmpty)
    XCTAssertTrue(Set(references).isSubset(of: Set(ids)))
  }
}

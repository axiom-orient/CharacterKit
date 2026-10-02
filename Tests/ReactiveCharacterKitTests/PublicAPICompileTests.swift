import Foundation
import ReactiveCharacterKit
import XCTest

final class PublicAPICompileTests: XCTestCase {
  func testPublicReducerExpressionCommunicationAndPoseAPI() throws {
    let taskID = CharacterTaskID(UUID())
    var state = ReactiveCharacter.initialState

    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .emotionChanged(.joy)
      ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .chatStarted
      ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentStarted(taskID: taskID)
      ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: taskID, progress: 0.42)
      ).state

    XCTAssertEqual(state.emotion, .joy)
    XCTAssertEqual(state.communication, .chat)

    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.25,
      projection: .softSphere,
      motionProfile: .expressive
    )
    XCTAssertTrue(pose.mouth.visible)
    XCTAssertGreaterThan(pose.eyes.left.width, 0)
  }

  func testPublicCustomizationContractsCompile() throws {
    let surface = try CharacterColor(red: 0.04, green: 0.04, blue: 0.06)
    let eyes = try CharacterColor(red: 0.9, green: 0.8, blue: 1)
    let mouth = try CharacterColor(red: 1, green: 0.7, blue: 0.8)
    let writing = try CharacterColor(red: 0.7, green: 0.9, blue: 1)

    let accessory = try CharacterColor(red: 0.45, green: 0.55, blue: 0.95)
    let detail = try CharacterColor(red: 0.95, green: 0.85, blue: 1)
    let colors = CharacterPartColors(
      surface: surface,
      eyes: eyes,
      mouth: mouth,
      writing: writing,
      accessory: accessory,
      accessoryDetail: detail
    )
    let style = try CharacterStyle(
      partColors: colors,
      lineWidth: 0.02
    )
    XCTAssertEqual(style.partColors.accessory, accessory)
    XCTAssertEqual(try CharacterStyle(), .default)
    XCTAssertEqual(try CharacterStyle(partColors: colors).partColors.surface, surface)
    XCTAssertTrue(CharacterComponents.default.contains(.accessories))
    _ = CharacterLayout.default
    _ = CharacterComponents.default
    _ = CharacterComponents.accessories
    _ = CharacterAccentPose(
      kind: .sparkle,
      centerX: 0.9,
      centerY: 0.1,
      width: 0.05,
      height: 0.05,
      angle: 0,
      opacity: 0.8
    )
    _ = CharacterProjection.flat
    _ = CharacterProjection.softSphere
    _ = CharacterEmotion.allCases
    _ = CharacterAttention.automatic
    _ = ReactiveCharacter.inspect(state: ReactiveCharacter.initialState).attention
    _ = CharacterMotionProfile.expressive
    _ = CharacterMotionProfile.cartoon
    _ = CharacterMotionProfile.soft
    _ = CharacterMotionProfile.minimal
    _ = CharacterSurfacePose.identity
    _ = CharacterTransitionProfile.expressive
    _ = CharacterTransitionProfile.cartoon
    _ = CharacterTransitionProfile.soft
    _ = CharacterTransitionProfile.reducedMotion
    _ = CharacterAnimation.allCases

    let animationID = CharacterAnimationID(UUID())
    let receipt = ReactiveCharacter.act(
      state: ReactiveCharacter.initialState,
      event: .animationStarted(id: animationID, animation: .celebrate)
    )
    _ = ReactiveCharacter.inspect(state: receipt.stateAfter)

    var presentation = CharacterPresentationSession(state: receipt.stateAfter, at: 0)
    _ = presentation.pose(at: 0.2)
    _ = presentation.inspect(at: 0.2)
    _ = presentation.update(state: ReactiveCharacter.initialState, at: 0.3)
  }
}

extension PublicAPICompileTests {
  func testPublicAccessoryPlacementIsRendererIndependent() throws {
    let placement = try CharacterAccessoryPlacement(
      anchor: .eyes, layer: .foreground, width: 0.9, height: 0.7, angle: 0.1, opacity: 0.8
    )
    XCTAssertEqual(placement.anchor, .eyes)
    XCTAssertEqual(placement.opacity, 0.8)
  }
}

#if os(iOS)
  import SwiftUI

  extension PublicAPICompileTests {
    @MainActor
    func testOriginalAndOverlayRendererInitializersCompile() {
      let state = ReactiveCharacter.initialState
      _ = ReactiveCharacterView(state: state)
      _ = ReactiveCharacterView(
        state: state,
        accessoryOverlays: [
          CharacterAccessoryOverlay(image: Image(systemName: "eyeglasses"), placement: .glasses),
          CharacterAccessoryOverlay(image: Image(systemName: "crown.fill"), placement: .crown),
        ]
      )
    }
  }
#endif

extension PublicAPICompileTests {
  func testPublicProfileToSVGPathWithoutInternalAccess() throws {
    var profile = try CharacterDesign.load(.white).profile
    profile.id = "my.ceramic"
    profile.rendering.lighting = .linear
    profile.layout.aspectRatio = 1.1
    profile.accessories = [.recommended(.roundGlasses), .recommended(.badge)]
    let design = try profile.compile()
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let pose = ReactiveCharacter.pose(
      state: state, elapsed: 1.2,
      projection: design.projection, motionProfile: design.motionProfile)
    let scene = try CharacterSceneBuilder.scene(pose: pose, design: design, width: 400, height: 320)
    XCTAssertFalse(scene.nodes.isEmpty)
    XCTAssertTrue(
      try CharacterSVGRenderer.render(scene, idPrefix: design.profile.id).contains("<svg"))
    XCTAssertEqual(design, try CharacterDesign.decode(design.encodedProfile()))
  }

  #if os(iOS)
    @MainActor
    func testPublicDesignViewAndSceneCanvasCompile() throws {
      let design = try CharacterDesign.load(.black)
      let state = ReactiveCharacter.initialState
      _ = ReactiveCharacterView(state: state, design: design)
      _ = ReactiveCharacterView(
        state: state, design: design,
        accessoryOverlays: [
          CharacterAccessoryOverlay(image: Image(systemName: "star"), placement: .badge)
        ])
      let scene = try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(state: state, elapsed: 0),
        design: design, width: 200, height: 200)
      _ = CharacterSceneCanvas(scene: scene)
    }
  #endif
}

#if os(iOS)
  extension PublicAPICompileTests {
    @MainActor
    func testSceneViewContractsCompileWithoutAmbiguity() throws {
      let state = ReactiveCharacter.initialState
      _ = ReactiveCharacterView(state: state)
      _ = ReactiveCharacterView(state: state, overlayAccents: [])
      _ = ReactiveCharacterView(state: state, accessibilityLabel: "Character")
      _ = ReactiveCharacterView(state: state, artDirection: .black)
      _ = ReactiveCharacterView(
        state: state, theme: .arcade, eyeTreatment: .vertical, mouthTreatment: .filled)
      _ = ReactiveCharacterView(state: state, design: try .load(.black))
    }
  }
#endif

extension PublicAPICompileTests {
  func testCanonicalConstructorsAcceptDefaultsAndCustomization() throws {
    let style = try CharacterStyle(eyeTreatment: .horizontal)
    XCTAssertEqual(style.eyeTreatment, .horizontal)
    let direction = try CharacterArtDirection(name: "Current", style: style, contentInset: 0.2)
    XCTAssertEqual(direction.style, style)
    XCTAssertEqual(direction.contentInset, 0.2)
    XCTAssertEqual(direction.anatomy, .minimal)
    for anatomy in [
      CharacterAnatomy.cat(.animated), .cat(.simple2D),
      .reference(.norwegianForest(.hero)), .reference(.mascot(variant: .hero)), .portrait(.cappedBoy),
    ] {
      let selected = try CharacterArtDirection(name: "Selected", anatomy: anatomy)
      XCTAssertEqual(selected.anatomy, anatomy)
    }
  }
}

extension PublicAPICompileTests {
  func testPublicPortraitComponentsAndSurfacePreserveAnatomy() throws {
    let style = CharacterPortraitStyle.boy(viewpoint: .threeQuarterRight, hairAccessory: .none)
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    let features = try CharacterSceneBuilder.scene(pose: pose,
      artDirection: style.artDirection(components: [.eyes, .nose], surface: .transparent), width: 256, height: 256)
    XCTAssertNotNil(features.nodes.first { $0.id == "eye.left" })
    XCTAssertNotNil(features.nodes.first { $0.id == "nose" })
    XCTAssertNil(features.nodes.first { $0.id == "mouth" })
    XCTAssertTrue(features.nodes.allSatisfy { !$0.id.hasPrefix("portrait.") })
    let body = try CharacterSceneBuilder.scene(pose: pose,
      artDirection: style.artDirection(components: []), width: 256, height: 256)
    XCTAssertNotNil(body.nodes.first { $0.id == "portrait.face" })
    XCTAssertFalse(body.nodes.contains { $0.id.hasPrefix("eye") || $0.id == "mouth" || $0.id == "nose" })
  }
}

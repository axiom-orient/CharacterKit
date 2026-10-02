import XCTest

@testable import ReactiveCharacterKit

final class CharacterFaceCompositionTests: XCTestCase {
  private func renderedCenterX(_ scene: CharacterScene, id: String) throws -> Double {
    let node = try XCTUnwrap(scene.nodes.first { $0.id == id })
    let points = node.path.commands.flatMap { command -> [CharacterVectorPoint] in
      switch command {
      case .move(let p), .line(let p): [p]
      case .quad(let c, let p): [c, p]
      case .cubic(let c1, let c2, let p): [c1, c2, p]
      case .close: []
      }
    }
    let transformed = points.map { point in
      node.transform.a * point.x + node.transform.c * point.y + node.transform.tx
    }
    return (try XCTUnwrap(transformed.min()) + XCTUnwrap(transformed.max())) * 0.5
  }

  private func state(
    x: Double,
    y: Double = 0.5,
    emotion: CharacterEmotion? = .joy
  ) throws -> CharacterState {
    var state = ReactiveCharacter.act(
      state: .idle,
      event: .emotionChanged(emotion)
    ).stateAfter
    state =
      ReactiveCharacter.act(
        state: state,
        event: .attentionFocused(try .init(validatingX: x, y: y))
      ).stateAfter
    return state
  }

  func testEveryEmotionKeepsMouthPlacementAlignedWithResolvedFaceDirection() throws {
    for emotion in CharacterEmotion.allCases {
      let left = ReactiveCharacter.pose(
        state: try state(x: 0, emotion: emotion), elapsed: 0.5, reduceMotion: true)
      let right = ReactiveCharacter.pose(
        state: try state(x: 1, emotion: emotion), elapsed: 0.5, reduceMotion: true)
      XCTAssertLessThan(left.face.gazeX, 0, "\(emotion)")
      XCTAssertGreaterThan(right.face.gazeX, 0, "\(emotion)")
      XCTAssertLessThan(left.face.mouth.offsetX, 0, "\(emotion)")
      XCTAssertGreaterThan(right.face.mouth.offsetX, 0, "\(emotion)")
      XCTAssertLessThan(left.face.mouth.offsetX, right.face.mouth.offsetX, "\(emotion)")
      // Gaze direction belongs to face composition. Emotion still owns mouth articulation,
      // but moving the gaze alone must not distort the mouth shape a second time.
      XCTAssertEqual(left.mouth.width, right.mouth.width, accuracy: 1e-12, "\(emotion)")
      XCTAssertEqual(left.mouth.skew, right.mouth.skew, accuracy: 1e-12, "\(emotion)")
    }

    let flat = ReactiveCharacter.pose(
      state: try state(x: 1), elapsed: 0.5, reduceMotion: true, projection: .flat)
    XCTAssertEqual(flat.face.mouth.scaleX, 1, accuracy: 1e-12)
  }

  func testEveryEmotionMovesRenderedMouthWithGazeAtSameMotionTime() throws {
    for emotion in CharacterEmotion.allCases {
      let leftPose = ReactiveCharacter.pose(
        state: try state(x: 0, emotion: emotion), elapsed: 0.52, reduceMotion: true,
        projection: CharacterArtDirection.black.projection,
        motionProfile: CharacterArtDirection.black.motionProfile)
      let rightPose = ReactiveCharacter.pose(
        state: try state(x: 1, emotion: emotion), elapsed: 0.52, reduceMotion: true,
        projection: CharacterArtDirection.black.projection,
        motionProfile: CharacterArtDirection.black.motionProfile)
      let leftScene = try CharacterSceneBuilder.scene(
        pose: leftPose, artDirection: .black, width: 320, height: 320)
      let rightScene = try CharacterSceneBuilder.scene(
        pose: rightPose, artDirection: .black, width: 320, height: 320)

      XCTAssertLessThan(
        try renderedCenterX(leftScene, id: "mouth"),
        try renderedCenterX(rightScene, id: "mouth"),
        "\(emotion): rendered mouth must follow the displayed gaze direction")
    }
  }

  func testInterruptedGazeBridgeDoesNotSnapMouthToNewTarget() throws {
    var session = CharacterPresentationSession(state: try state(x: 0), at: 0)
    let before = session.pose(at: 1, motionProfile: .focusedEmotion())

    XCTAssertFalse(
      session.update(
        state: try state(x: 1),
        at: 1,
        motionProfile: .focusedEmotion()
      )
    )
    let initial = session.pose(at: 1, motionProfile: .focusedEmotion())
    XCTAssertEqual(initial.eyes, before.eyes)
    XCTAssertEqual(initial.noseOffsetX, before.noseOffsetX)
    XCTAssertEqual(initial.face.mouth, before.face.mouth)

    let midway = session.pose(at: 1.04, motionProfile: .focusedEmotion())
    XCTAssertFalse(
      session.update(
        state: try state(x: 0, y: 0.8),
        at: 1.04,
        motionProfile: .focusedEmotion()
      )
    )
    let interrupted = session.pose(at: 1.04, motionProfile: .focusedEmotion())
    XCTAssertEqual(interrupted.eyes, midway.eyes)
    XCTAssertEqual(interrupted.noseOffsetX, midway.noseOffsetX)
    XCTAssertEqual(interrupted.face.mouth, midway.face.mouth)
  }

  func testAuthoredDesignKeepsItsLayoutWhileMouthTracksFinalFacePlacement() throws {
    let design = try CharacterDesign.load(.white)
    let leftPose = ReactiveCharacter.pose(
      state: try state(x: 0), elapsed: 0.5, reduceMotion: true,
      projection: design.projection, motionProfile: design.motionProfile)
    let rightPose = ReactiveCharacter.pose(
      state: try state(x: 1), elapsed: 0.5, reduceMotion: true,
      projection: design.projection, motionProfile: design.motionProfile)

    let left = try CharacterSceneBuilder.scene(
      pose: leftPose, design: design, width: 320, height: 320)
    let right = try CharacterSceneBuilder.scene(
      pose: rightPose, design: design, width: 320, height: 320)
    XCTAssertEqual(left.faceBounds, right.faceBounds)

    func centerX(_ scene: CharacterScene) throws -> Double {
      let node = try XCTUnwrap(scene.nodes.first { $0.id == "mouth" })
      let points = node.path.commands.flatMap { command -> [CharacterVectorPoint] in
        switch command {
        case .move(let p), .line(let p): [p]
        case .quad(let c, let p): [c, p]
        case .cubic(let c1, let c2, let p): [c1, c2, p]
        case .close: []
        }
      }
      return (try XCTUnwrap(points.map(\.x).min()) + XCTUnwrap(points.map(\.x).max())) * 0.5
    }

    XCTAssertLessThan(try centerX(left), try centerX(right))
  }

}

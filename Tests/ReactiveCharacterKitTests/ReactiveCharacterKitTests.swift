import Foundation
import XCTest

@testable import ReactiveCharacterKit

#if os(iOS)
  import UIKit
#endif

final class ReactiveCharacterKitTests: XCTestCase {
  private let taskA = CharacterTaskID(UUID())
  private let taskB = CharacterTaskID(UUID())

  private func point(_ x: Double = 0.5, _ y: Double = 0.5) -> CharacterPoint {
    try! CharacterPoint(validatingX: x, y: y)
  }

  func testInitialStateIsNeutralSilentIdle() {
    let state = ReactiveCharacter.initialState
    XCTAssertEqual(state.activity, .idle)
    XCTAssertEqual(state.attention, .automatic)
    XCTAssertNil(state.emotion)
    XCTAssertEqual(state.communication, .silent)
    XCTAssertNil(state.animation)
    XCTAssertEqual(state.visualChannel, .neutral)
  }

  func testAgentFlowPreservesOrthogonalEmotionAndCommunication() {
    var state = ReactiveCharacter.initialState
    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.interest)).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    state = ReactiveCharacter.reduce(state: state, event: .agentStarted(taskID: taskA)).state
    state =
      ReactiveCharacter.reduce(state: state, event: .agentProgress(taskID: taskA, progress: 0.4))
      .state

    XCTAssertEqual(
      state.activity,
      .agentWriting(taskID: taskA, progress: try! CharacterProgress(validating: 0.4)))
    XCTAssertEqual(state.emotion, .interest)
    XCTAssertEqual(state.communication, .chat)
  }

  func testNewTaskCancelsCurrentTaskAsEffect() {
    let current = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: taskA)
    ).state
    let next = ReactiveCharacter.reduce(
      state: current,
      event: .agentStarted(taskID: taskB)
    )

    XCTAssertEqual(next.state.activity, .agentThinking(taskID: taskB))
    XCTAssertEqual(next.effects, [.cancelAgent(taskID: taskA)])
  }

  func testStaleProgressCannotMutateCurrentTask() {
    let current = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: taskB)
    ).state
    let result = ReactiveCharacter.reduce(
      state: current,
      event: .agentProgress(taskID: taskA, progress: 0.5)
    )

    XCTAssertEqual(result.state, current)
    XCTAssertEqual(
      result.disposition,
      .ignored(.staleTask(expected: taskB, received: taskA))
    )
  }

  func testProgressRegressionIsRejectedWithoutMutation() throws {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: taskA)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: taskA, progress: 0.7)
      ).state

    let result = ReactiveCharacter.reduce(
      state: state,
      event: .agentProgress(taskID: taskA, progress: 0.4)
    )
    XCTAssertEqual(result.state, state)
    XCTAssertEqual(
      result.disposition,
      .rejected(.progressRegressed(previous: 0.7, received: 0.4))
    )
  }

  func testCancellationRequestProducesEffectThenExplicitResult() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: taskA)
    ).state

    let request = ReactiveCharacter.reduce(
      state: state,
      event: .agentCancellationRequested(taskID: taskA)
    )
    XCTAssertEqual(request.state.activity, .agentCancelling(taskID: taskA))
    XCTAssertEqual(request.effects, [.cancelAgent(taskID: taskA)])

    state = request.state
    let result = ReactiveCharacter.reduce(
      state: state,
      event: .agentCancelled(taskID: taskA)
    )
    XCTAssertEqual(result.state.activity, .cancelled(taskID: taskA))
    XCTAssertEqual(result.effects, [])
  }

  func testEmotionChangeIsExplicitAndIdempotent() {
    let first = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.gratitude)
    )
    XCTAssertEqual(first.state.emotion, .gratitude)
    XCTAssertEqual(first.disposition, .accepted)

    let duplicate = ReactiveCharacter.reduce(
      state: first.state,
      event: .emotionChanged(.gratitude)
    )
    XCTAssertEqual(duplicate.disposition, .ignored(.duplicate))

    let cleared = ReactiveCharacter.reduce(
      state: first.state,
      event: .emotionChanged(nil)
    )
    XCTAssertNil(cleared.state.emotion)
  }

  func testAllRequiredEmotionLabelsAreStable() {
    XCTAssertEqual(
      CharacterEmotion.allCases.map(\.rawValue),
      [
        "joy",
        "affection",
        "gratitude",
        "interest",
        "surprise",
        "calm_trust",
        "sadness",
        "anxiety_fear",
        "anger_irritation",
        "disgust_contempt",
        "shame_guilt",
        "fatigue_burden",
      ]
    )
  }

  func testVoiceLifecycleAndValidation() {
    let started = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .voiceStarted
    )
    XCTAssertEqual(started.state.communication, .voice(level: .zero))

    let leveled = ReactiveCharacter.reduce(
      state: started.state,
      event: .voiceLevelChanged(0.72)
    )
    XCTAssertEqual(
      leveled.state.communication,
      .voice(level: try! CharacterVoiceLevel(validating: 0.72))
    )

    let invalid = ReactiveCharacter.reduce(
      state: leveled.state,
      event: .voiceLevelChanged(1.2)
    )
    XCTAssertEqual(invalid.state, leveled.state)
    XCTAssertEqual(invalid.disposition, .rejected(.outOfRange(field: "voiceLevel", value: 1.2)))

    let ended = ReactiveCharacter.reduce(
      state: leveled.state,
      event: .communicationEnded
    )
    XCTAssertEqual(ended.state.communication, .silent)
  }

  func testResetClearsExpressionCommunicationAndCancelsActiveTask() {
    var state = ReactiveCharacter.initialState
    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.joy)).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    state = ReactiveCharacter.reduce(state: state, event: .agentStarted(taskID: taskA)).state

    let reset = ReactiveCharacter.reduce(state: state, event: .reset)
    XCTAssertEqual(reset.state, ReactiveCharacter.initialState)
    XCTAssertEqual(reset.effects, [.cancelAgent(taskID: taskA)])
  }

  func testNeutralSilentDefaultPoseHidesMouth() {
    let pose = ReactiveCharacter.pose(
      state: ReactiveCharacter.initialState,
      elapsed: 0,
      reduceMotion: true
    )
    XCTAssertFalse(pose.mouth.visible)
  }

  func testEveryEmotionMakesMouthAvailable() {
    for emotion in CharacterEmotion.allCases {
      let state = ReactiveCharacter.reduce(
        state: ReactiveCharacter.initialState,
        event: .emotionChanged(emotion)
      ).state
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
      XCTAssertTrue(pose.mouth.visible, emotion.rawValue)
    }
  }

  func testMouthAtlasUsesSixteenFiniteSameTopologyGlyphs() {
    XCTAssertEqual(CharacterMouthGlyph.allCases.count, 16)
    let expectedInterior: [CharacterMouthGlyph: CharacterMouthInterior] = [
      .slantedOpen: .none,
      .baseFlat: .none,
      .toothyOpen: .teethAndTongue,
      .tongueDrop: .tongue,
      .zigzag: .none,
      .clenchedWave: .none,
      .speechWave: .none,
      .puckerO: .none,
      .halfMoonTeeth: .teeth,
      .uneasyOpen: .none,
      .downturnedArc: .none,
      .asymmetricSmirk: .none,
      .openGrill: .teethAndTongue,
      .smallYawn: .none,
      .wideToothyGrin: .teethAndTongue,
      .caretFrown: .none,
    ]
    var definitions: [MouthGlyphDefinition] = []
    for glyph in CharacterMouthGlyph.allCases {
      let definition = MouthGlyphLibrary.definition(
        for: glyph,
        openness: 0.62,
        width: 0.84,
        curvature: -0.14,
        skew: 0.12
      )
      definitions.append(definition)
      XCTAssertEqual(definition.segments.count, MouthGlyphLibrary.segmentCount, glyph.rawValue)
      let expected = expectedInterior[glyph] ?? CharacterMouthInterior.none
      XCTAssertEqual(definition.interior, expected, glyph.rawValue)
      XCTAssertFalse(
        definition.details.isEmpty && expected != CharacterMouthInterior.none, glyph.rawValue)
      for detail in definition.details {
        XCTAssertFalse(detail.segments.isEmpty, glyph.rawValue)
        for segment in detail.segments {
          let values = [
            segment.start.x, segment.start.y,
            segment.control1.x, segment.control1.y,
            segment.control2.x, segment.control2.y,
            segment.end.x, segment.end.y,
          ]
          XCTAssertTrue(values.allSatisfy(\.isFinite), glyph.rawValue)
        }
      }
      for segment in definition.segments {
        let values = [
          segment.start.x, segment.start.y,
          segment.control1.x, segment.control1.y,
          segment.control2.x, segment.control2.y,
          segment.end.x, segment.end.y,
        ]
        XCTAssertTrue(values.allSatisfy(\.isFinite), glyph.rawValue)
      }
    }
    for lhs in definitions.indices {
      for rhs in definitions.indices where rhs > lhs {
        XCTAssertNotEqual(
          definitions[lhs].segments,
          definitions[rhs].segments,
          "distinct authored silhouettes required"
        )
      }
    }
  }

  func testRuntimeMouthFitPreservesTallAndWideReferenceAspects() {
    let regionAspect = CharacterLayout.default.mouth.width / CharacterLayout.default.mouth.height
    let pucker = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.surprise)
    ).state
    let flat = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.calmTrust)
    ).state
    let puckerPose = ReactiveCharacter.pose(state: pucker, elapsed: 0, reduceMotion: true).mouth
    let flatPose = ReactiveCharacter.pose(state: flat, elapsed: 0, reduceMotion: true).mouth
    let puckerScale = MouthGlyphLibrary.aspectFitScale(
      intrinsicAspect: puckerPose.intrinsicAspect,
      regionAspect: regionAspect
    )
    let flatScale = MouthGlyphLibrary.aspectFitScale(
      intrinsicAspect: flatPose.intrinsicAspect,
      regionAspect: regionAspect
    )

    XCTAssertLessThan(puckerScale.x, puckerScale.y)
    XCTAssertGreaterThan(flatScale.x, flatScale.y)
  }

  func testReferenceRasterAtlasContainsAllGlyphs() {
    for glyph in CharacterMouthGlyph.allCases {
      XCTAssertNotNil(MouthReferenceRasterLibrary.resourceURL(for: glyph), glyph.rawValue)
    }
  }

  func testPoseRemainsContinuousAcrossFormerOneDayBoundary() {
    let before = ReactiveCharacter.pose(state: .idle, elapsed: 86_399.999, projection: .flat)
    let after = ReactiveCharacter.pose(state: .idle, elapsed: 86_400.001, projection: .flat)

    XCTAssertLessThan(abs(after.eyes.left.centerX - before.eyes.left.centerX), 0.01)
    XCTAssertLessThan(abs(after.eyes.left.centerY - before.eyes.left.centerY), 0.01)
    XCTAssertLessThan(abs(after.eyes.right.centerX - before.eyes.right.centerX), 0.01)
    XCTAssertLessThan(abs(after.eyes.right.centerY - before.eyes.right.centerY), 0.01)
  }

  func testStableTargetEnablesReferenceGlyphRendering() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.25, reduceMotion: true)

    XCTAssertGreaterThan(pose.mouth.referenceGlyphOpacity, 0.99)
  }

  func testEmotionSubphasesReachAllMouthGlyphFamilies() {
    let sampleTimes = stride(from: 0.0, through: 2.4, by: 0.08).map { Double($0) }
    var reached = Set<CharacterMouthGlyph>()
    for emotion in CharacterEmotion.allCases {
      let state = ReactiveCharacter.reduce(
        state: ReactiveCharacter.initialState,
        event: .emotionChanged(emotion)
      ).state
      for time in sampleTimes {
        reached.insert(
          ReactiveCharacter.pose(
            state: state,
            elapsed: time,
            expressionElapsed: time,
            reduceMotion: false
          ).mouth.glyph
        )
      }
    }
    let communication = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .chatStarted
    ).state
    for time in sampleTimes {
      reached.insert(
        ReactiveCharacter.pose(
          state: communication,
          elapsed: time,
          communicationElapsed: time,
          reduceMotion: false
        ).mouth.glyph
      )
    }
    XCTAssertEqual(reached, Set(CharacterMouthGlyph.allCases))
  }

  func testVoiceZeroIsVisibleAndVoiceCycleUsesMoreThanOneFamily() {
    let started = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .voiceStarted
    ).state
    let zero = ReactiveCharacter.pose(state: started, elapsed: 0, reduceMotion: true)
    XCTAssertTrue(zero.mouth.visible)
    XCTAssertEqual(zero.mouth.glyph, .speechWave)
    XCTAssertEqual(zero.mouth.contour.count, MouthGlyphLibrary.segmentCount)

    let first = ReactiveCharacter.pose(state: started, elapsed: 0.18, reduceMotion: false).mouth
      .glyph
    let second = ReactiveCharacter.pose(state: started, elapsed: 0.72, reduceMotion: false).mouth
      .glyph
    XCTAssertNotEqual(first, second)
  }

  func testRepeatingMouthCycleReturnsThroughBaseAndFadesDetails() {
    let chat = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .chatStarted
    ).state
    let held = ReactiveCharacter.pose(
      state: chat,
      elapsed: 0.20,
      communicationElapsed: 0.20,
      reduceMotion: false
    ).mouth
    let returned = ReactiveCharacter.pose(
      state: chat,
      elapsed: 0.30,
      communicationElapsed: 0.30,
      reduceMotion: false
    ).mouth
    let base = ReactiveCharacter.pose(
      state: chat,
      elapsed: 0.33,
      communicationElapsed: 0.33,
      reduceMotion: false
    ).mouth
    let next = ReactiveCharacter.pose(
      state: chat,
      elapsed: 0.361,
      communicationElapsed: 0.361,
      reduceMotion: false
    ).mouth

    XCTAssertEqual(held.glyph, .speechWave)
    XCTAssertGreaterThan(held.detailOpacity, 0.99)
    XCTAssertEqual(returned.glyph, .speechWave)
    XCTAssertLessThan(returned.detailOpacity, 0.001)
    XCTAssertEqual(base.glyph, .baseFlat)
    XCTAssertEqual(base.detailOpacity, 0, accuracy: 1e-12)
    let baseContour = MouthGlyphLibrary.contour(
      for: .baseFlat,
      openness: 0,
      width: base.width,
      curvature: 0,
      skew: 0
    )
    var baseDifference = 0.0
    for (lhs, rhs) in zip(base.contour, baseContour) {
      baseDifference = max(baseDifference, abs(lhs.start.x - rhs.start.x))
      baseDifference = max(baseDifference, abs(lhs.start.y - rhs.start.y))
      baseDifference = max(baseDifference, abs(lhs.control1.x - rhs.control1.x))
      baseDifference = max(baseDifference, abs(lhs.control1.y - rhs.control1.y))
      baseDifference = max(baseDifference, abs(lhs.control2.x - rhs.control2.x))
      baseDifference = max(baseDifference, abs(lhs.control2.y - rhs.control2.y))
      baseDifference = max(baseDifference, abs(lhs.end.x - rhs.end.x))
      baseDifference = max(baseDifference, abs(lhs.end.y - rhs.end.y))
    }
    XCTAssertLessThanOrEqual(baseDifference, 1e-12)
    XCTAssertEqual(next.glyph, .slantedOpen)
    XCTAssertEqual(next.detailOpacity, 0, accuracy: 1e-12)
    let nextBaseContour = MouthGlyphLibrary.contour(
      for: .baseFlat,
      openness: 0,
      width: next.width,
      curvature: 0,
      skew: 0
    )
    let nextTargetContour = MouthGlyphLibrary.contour(
      for: .slantedOpen,
      openness: 1,
      width: next.width,
      curvature: next.curvature,
      skew: next.skew
    )
    var nextBaseDifference = 0.0
    var nextTargetDifference = 0.0
    for (lhs, rhs) in zip(next.contour, nextBaseContour) {
      nextBaseDifference = max(nextBaseDifference, abs(lhs.start.x - rhs.start.x))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.start.y - rhs.start.y))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.control1.x - rhs.control1.x))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.control1.y - rhs.control1.y))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.control2.x - rhs.control2.x))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.control2.y - rhs.control2.y))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.end.x - rhs.end.x))
      nextBaseDifference = max(nextBaseDifference, abs(lhs.end.y - rhs.end.y))
    }
    for (lhs, rhs) in zip(next.contour, nextTargetContour) {
      nextTargetDifference = max(nextTargetDifference, abs(lhs.start.x - rhs.start.x))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.start.y - rhs.start.y))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.control1.x - rhs.control1.x))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.control1.y - rhs.control1.y))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.control2.x - rhs.control2.x))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.control2.y - rhs.control2.y))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.end.x - rhs.end.x))
      nextTargetDifference = max(nextTargetDifference, abs(lhs.end.y - rhs.end.y))
    }
    XCTAssertGreaterThan(nextBaseDifference, 0.000_001)
    XCTAssertLessThan(nextBaseDifference, nextTargetDifference)
  }

  func testPresentationBridgeUsesExactSpritesNearEndpointsOnly() {
    let first = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let next = ReactiveCharacter.reduce(
      state: first,
      event: .emotionChanged(.surprise)
    ).state
    var session = CharacterPresentationSession(state: first, at: 0)

    XCTAssertTrue(session.update(state: next, at: 0.60))

    let handoff = session.inspect(at: 0.60).remainingHandoffDuration
    let middlePose = session.pose(at: 0.60 + handoff * 0.5).mouth
    XCTAssertLessThan(middlePose.referenceGlyphOpacity, 0.05)

    let settledPose = session.pose(at: 0.60 + handoff + 0.18).mouth
    XCTAssertGreaterThan(settledPose.referenceGlyphOpacity, 0.99)
  }

  func testMouthReturnsToBaseBeforeBuildingNextGlyph() {
    let first = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let next = ReactiveCharacter.reduce(
      state: first,
      event: .emotionChanged(.surprise)
    ).state
    var session = CharacterPresentationSession(state: first, at: 0)
    let source = session.pose(at: 0.18)
    XCTAssertTrue(session.update(state: next, at: 0.18))
    XCTAssertEqual(session.pose(at: 0.18).mouth.contour, source.mouth.contour)

    let neutral = ReactiveCharacter.pose(
      state: ReactiveCharacter.initialState,
      elapsed: 0,
      reduceMotion: true
    ).mouth
    let returned = session.pose(at: 0.18 + 0.063)
    XCTAssertEqual(returned.mouth.contour.count, neutral.contour.count)
    var maximumContourDifference = 0.0
    for (lhs, rhs) in zip(returned.mouth.contour, neutral.contour) {
      maximumContourDifference = max(maximumContourDifference, abs(lhs.start.x - rhs.start.x))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.start.y - rhs.start.y))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.control1.x - rhs.control1.x))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.control1.y - rhs.control1.y))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.control2.x - rhs.control2.x))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.control2.y - rhs.control2.y))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.end.x - rhs.end.x))
      maximumContourDifference = max(maximumContourDifference, abs(lhs.end.y - rhs.end.y))
    }
    XCTAssertLessThanOrEqual(maximumContourDifference, 1e-12)
    XCTAssertFalse(returned.mouth.visible)

    let handoffEnd = 0.18 + session.inspect(at: 0.18).remainingHandoffDuration
    let hold = session.pose(at: handoffEnd - 0.01)
    XCTAssertEqual(hold.mouth.contour.count, neutral.contour.count)
    XCTAssertFalse(hold.mouth.visible)

    // The rest of the character may use a longer return budget; the mouth is
    // guaranteed to build only after that bridge and its neutral hold finish.
    let built = session.pose(at: handoffEnd + 0.18)
    XCTAssertEqual(built.mouth.glyph, .puckerO)
    XCTAssertNotEqual(built.mouth.contour, neutral.contour)
  }

  func testReducedMotionPresentationSnapsToStableTargetWithoutBridge() {
    let first = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let next = ReactiveCharacter.reduce(
      state: first,
      event: .emotionChanged(.surprise)
    ).state
    var session = CharacterPresentationSession(state: first, at: 0)

    XCTAssertFalse(session.update(state: next, at: 0.4, reduceMotion: true))
    let snapped = session.pose(at: 0.4, reduceMotion: true)
    let expected = ReactiveCharacter.pose(
      state: next,
      elapsed: 0,
      expressionElapsed: 0,
      communicationElapsed: 0,
      animationElapsed: 0,
      reduceMotion: true
    )
    XCTAssertEqual(snapped, expected)
    XCTAssertEqual(session.inspect(at: 0.4).phase, .performing)
    XCTAssertEqual(session.inspect(at: 0.4).remainingHandoffDuration, 0, accuracy: 1e-12)
  }

  func testReducedMotionMouthTargetDoesNotCycleWithTime() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let early = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
    let late = ReactiveCharacter.pose(state: state, elapsed: 900, reduceMotion: true)
    XCTAssertEqual(early.mouth.glyph, .wideToothyGrin)
    XCTAssertEqual(early.mouth, late.mouth)
  }

  func testNeutralAndExpressiveStatesNeverCreateAutomaticOrnaments() {
    let neutral = ReactiveCharacter.pose(
      state: ReactiveCharacter.initialState,
      elapsed: 0.4,
      reduceMotion: true
    )
    XCTAssertTrue(neutral.accents.isEmpty)

    let anxiety = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.anxietyFear)
    ).state
    let expressive = ReactiveCharacter.pose(state: anxiety, elapsed: 0.4, reduceMotion: false)
    XCTAssertTrue(expressive.accents.isEmpty)
    XCTAssertTrue(expressive.mouth.visible)
    XCTAssertNotEqual(expressive.eyes, neutral.eyes)
  }

  func testChatAndVoiceMakeMouthAvailableWithoutEmotion() {
    let chat = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .chatStarted
    ).state
    XCTAssertTrue(
      ReactiveCharacter.pose(state: chat, elapsed: 0.2, reduceMotion: false).mouth.visible
    )

    var voice = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .voiceStarted
    ).state
    voice =
      ReactiveCharacter.reduce(
        state: voice,
        event: .voiceLevelChanged(0.8)
      ).state
    let pose = ReactiveCharacter.pose(state: voice, elapsed: 0, reduceMotion: true)
    XCTAssertTrue(pose.mouth.visible)
    XCTAssertGreaterThan(pose.mouth.openness, 0.6)
  }

  func testCommunicationUsesMouthWithoutAutomaticStickersOrSemanticMutation() {
    let chat = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .chatStarted
    ).state
    let chatPose = ReactiveCharacter.pose(state: chat, elapsed: 0.4, reduceMotion: false)
    XCTAssertTrue(chatPose.mouth.visible)
    XCTAssertTrue(chatPose.accents.isEmpty)
    XCTAssertEqual(chat.communication, .chat)

    var voice = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .voiceStarted
    ).state
    voice =
      ReactiveCharacter.reduce(
        state: voice,
        event: .voiceLevelChanged(0.45)
      ).state
    let voicePose = ReactiveCharacter.pose(state: voice, elapsed: 0.4, reduceMotion: false)
    XCTAssertTrue(voicePose.mouth.visible)
    XCTAssertTrue(voicePose.accents.isEmpty)
    XCTAssertEqual(voice.communication, .voice(level: try! CharacterVoiceLevel(validating: 0.45)))
  }

  func testAgentWritingKeepsProgressAuthoritySeparateFromMotionPhase() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: taskA)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: taskA, progress: 0.42)
      ).state

    let early = ReactiveCharacter.pose(state: state, elapsed: 0.10, reduceMotion: false)
    let later = ReactiveCharacter.pose(state: state, elapsed: 0.42, reduceMotion: false)

    XCTAssertEqual(early.writingPhase, 0.42, accuracy: 1e-12)
    XCTAssertEqual(later.writingPhase, 0.42, accuracy: 1e-12)
    XCTAssertEqual(early.writingProgress ?? -1, 0.42, accuracy: 1e-12)
    XCTAssertEqual(later.writingProgress ?? -1, 0.42, accuracy: 1e-12)
    XCTAssertNotEqual(early.writingMotionPhase, later.writingMotionPhase)
  }

  func testAllEmotionCyclesStayStickerFreeWithoutSuppressingTheFace() throws {
    for reduced in [true, false] {
      for time in [0.0, 0.11, 0.37, 0.73, 1.18, 1.91, 2.63, 3.47, 4.82, 6.15] {
        for emotion in CharacterEmotion.allCases {
          let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
          let pose = ReactiveCharacter.pose(state: state, elapsed: time, reduceMotion: reduced)
          XCTAssertTrue(pose.accents.isEmpty, "\(emotion) at \(time)")
          XCTAssertTrue(pose.mouth.visible)
          let scene = try CharacterSceneBuilder.scene(
            pose: pose, artDirection: .black,
            width: 240, height: 240)
          XCTAssertEqual(
            scene.nodes.filter { $0.id == "eye.left" || $0.id == "eye.right" }.count, 2)
          XCTAssertFalse(scene.nodes.contains { $0.id == "nose" || $0.id.hasPrefix("art.accent") })
        }
      }
    }
  }

  func testFaceLayoutsKeepEyeMouthAndWritingBandsSeparated() {
    for layout in [CharacterLayout.default, .strict] {
      let eyeMaxY = layout.eyes.y + layout.eyes.height
      let mouthMaxY = layout.mouth.y + layout.mouth.height
      XCTAssertGreaterThan(layout.mouth.y - eyeMaxY, 0.001)
      XCTAssertGreaterThan(layout.writing.y - mouthMaxY, 0.001)
      XCTAssertGreaterThan(layout.writing.x - (layout.mouth.x + layout.mouth.width), 0.001)
    }

    // eyesOnly remains a full-band eye composition. The renderer contract
    // suppresses a separately requested mouth instead of overlapping it.
    XCTAssertGreaterThan(CharacterLayout.eyesOnly.eyes.height, 0.80)
    XCTAssertGreaterThan(
      CharacterLayout.eyesOnly.writing.y
        - (CharacterLayout.eyesOnly.mouth.y + CharacterLayout.eyesOnly.mouth.height),
      0.001
    )
  }

  func testFaceWritingLayoutsUseCompactOuterCornerAndWritingOnlyStaysBroad() {
    for layout in [CharacterLayout.default, .strict, .eyesOnly] {
      XCTAssertGreaterThanOrEqual(layout.writing.x, 0.75)
      XCTAssertGreaterThanOrEqual(layout.writing.y, 0.78)
      XCTAssertLessThanOrEqual(layout.writing.width, 0.22)
      XCTAssertLessThanOrEqual(layout.writing.height, 0.18)
    }
    XCTAssertLessThanOrEqual(CharacterLayout.writingOnly.writing.x, 0.05)
    XCTAssertLessThanOrEqual(CharacterLayout.writingOnly.writing.y, 0.10)
    XCTAssertGreaterThanOrEqual(CharacterLayout.writingOnly.writing.width, 0.90)
    XCTAssertGreaterThanOrEqual(CharacterLayout.writingOnly.writing.height, 0.80)
  }

  func testSoftSphereIsSymmetricAtCenteredGaze() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .userWritingBegan(focus: point(0.5, 0.5))
    ).state
    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0,
      reduceMotion: true,
      projection: .softSphere
    )
    XCTAssertEqual(pose.eyes.left.width, pose.eyes.right.width, accuracy: 1e-12)
    XCTAssertEqual(pose.eyes.left.height, pose.eyes.right.height, accuracy: 1e-12)
  }

  func testSoftSphereShrinksEyeCloserToLeftRim() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .userWritingBegan(focus: point(0, 0.5))
    ).state
    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0,
      reduceMotion: true,
      projection: .softSphere
    )
    XCTAssertLessThan(pose.eyes.left.width, pose.eyes.right.width)
    XCTAssertLessThan(pose.eyes.left.height, pose.eyes.right.height)
  }

  func testSoftSphereShrinksEyeCloserToRightRim() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .userWritingBegan(focus: point(1, 0.5))
    ).state
    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0,
      reduceMotion: true,
      projection: .softSphere
    )
    XCTAssertLessThan(pose.eyes.right.width, pose.eyes.left.width)
    XCTAssertLessThan(pose.eyes.right.height, pose.eyes.left.height)
  }

  func testFlatProjectionKeepsEqualEyeDimensionsDuringHorizontalGaze() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .userWritingBegan(focus: point(0, 0.5))
    ).state
    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0,
      reduceMotion: true,
      projection: .flat
    )
    XCTAssertEqual(pose.eyes.left.width, pose.eyes.right.width, accuracy: 1e-12)
    XCTAssertEqual(pose.eyes.left.height, pose.eyes.right.height, accuracy: 1e-12)
  }

  func testArousalMappingMakesSurpriseMoreOpenThanCalmTrust() {
    let surprise = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.surprise)
    ).state
    let calm = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.calmTrust)
    ).state

    let surprisePose = ReactiveCharacter.pose(state: surprise, elapsed: 0, reduceMotion: true)
    let calmPose = ReactiveCharacter.pose(state: calm, elapsed: 0, reduceMotion: true)
    XCTAssertGreaterThan(surprisePose.eyes.left.height, calmPose.eyes.left.height)
    XCTAssertGreaterThan(surprisePose.mouth.openness, calmPose.mouth.openness)
  }

  func testAngerNarrowsEyesRelativeToInterest() {
    let anger = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.angerIrritation)
    ).state
    let interest = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.interest)
    ).state

    let angerPose = ReactiveCharacter.pose(state: anger, elapsed: 0, reduceMotion: true)
    let interestPose = ReactiveCharacter.pose(state: interest, elapsed: 0, reduceMotion: true)
    XCTAssertLessThan(angerPose.eyes.left.height, interestPose.eyes.left.height)
  }

  func testDisgustContemptUsesIntentionalAsymmetry() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.disgustContempt)
    ).state
    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0,
      reduceMotion: true,
      projection: .flat
    )
    XCTAssertNotEqual(pose.eyes.left.height, pose.eyes.right.height)
    XCTAssertNotEqual(pose.mouth.skew, 0)
  }

  func testCartoonValenceAndArousalSignaturesStaySeparated() {
    let joy = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let sadness = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.sadness)
    ).state
    let fear = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.anxietyFear)
    ).state
    let anger = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.angerIrritation)
    ).state

    let joyPose = ReactiveCharacter.pose(state: joy, elapsed: 0, reduceMotion: true)
    let sadnessPose = ReactiveCharacter.pose(state: sadness, elapsed: 0, reduceMotion: true)
    let fearPose = ReactiveCharacter.pose(state: fear, elapsed: 0, reduceMotion: true)
    let angerPose = ReactiveCharacter.pose(state: anger, elapsed: 0, reduceMotion: true)

    XCTAssertGreaterThan(joyPose.mouth.curvature, 0)
    XCTAssertLessThan(sadnessPose.mouth.curvature, 0)
    XCTAssertGreaterThan(joyPose.mouth.curvature, sadnessPose.mouth.curvature)
    XCTAssertGreaterThan(fearPose.eyes.left.height, angerPose.eyes.left.height)
    XCTAssertGreaterThan(fearPose.mouth.openness, angerPose.mouth.openness)
  }

  func testSubtleEmotionMouthCyclesAnimateWithoutBreakingReducedMotion() {
    let gratitude = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.gratitude)
    ).state
    let calm = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.calmTrust)
    ).state
    let fatigue = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.fatigueBurden)
    ).state

    XCTAssertNotEqual(
      ReactiveCharacter.pose(state: gratitude, elapsed: 0.18, reduceMotion: false).mouth.glyph,
      ReactiveCharacter.pose(state: gratitude, elapsed: 0.82, reduceMotion: false).mouth.glyph
    )
    XCTAssertNotEqual(
      ReactiveCharacter.pose(state: calm, elapsed: 0.22, reduceMotion: false).mouth.glyph,
      ReactiveCharacter.pose(state: calm, elapsed: 0.90, reduceMotion: false).mouth.glyph
    )
    XCTAssertNotEqual(
      ReactiveCharacter.pose(state: fatigue, elapsed: 0.34, reduceMotion: false).mouth.glyph,
      ReactiveCharacter.pose(state: fatigue, elapsed: 1.12, reduceMotion: false).mouth.glyph
    )

    XCTAssertEqual(
      ReactiveCharacter.pose(state: gratitude, elapsed: 0.18, reduceMotion: true).mouth,
      ReactiveCharacter.pose(state: gratitude, elapsed: 10.18, reduceMotion: true).mouth
    )
  }

  func testEveryEmotionHasTimeVaryingPresentation() {
    for emotion in CharacterEmotion.allCases {
      let state = ReactiveCharacter.reduce(
        state: ReactiveCharacter.initialState,
        event: .emotionChanged(emotion)
      ).state
      let early = ReactiveCharacter.pose(state: state, elapsed: 0.12, reduceMotion: false)
      let later = ReactiveCharacter.pose(state: state, elapsed: 0.86, reduceMotion: false)
      XCTAssertNotEqual(early, later, emotion.rawValue)
    }
  }

  func testAmbientBlinkClosesNeutralAndEveryEmotionDuringDeterministicWindow() {
    let fixedExpressionElapsed = 0.52
    let outsideWindowElapsed = 3.12
    let insideWindowElapsed = 3.23
    let neutralAndEmotionalStates: [(String, CharacterState)] =
      [("neutral", ReactiveCharacter.initialState)]
      + CharacterEmotion.allCases.map { emotion in
        (
          emotion.rawValue,
          ReactiveCharacter.reduce(
            state: ReactiveCharacter.initialState,
            event: .emotionChanged(emotion)
          ).state
        )
      }

    for (label, state) in neutralAndEmotionalStates {
      let outsideWindow = ReactiveCharacter.pose(
        state: state,
        elapsed: outsideWindowElapsed,
        expressionElapsed: fixedExpressionElapsed,
        communicationElapsed: fixedExpressionElapsed,
        animationElapsed: fixedExpressionElapsed,
        reduceMotion: false,
        projection: .flat
      )
      let insideWindow = ReactiveCharacter.pose(
        state: state,
        elapsed: insideWindowElapsed,
        expressionElapsed: fixedExpressionElapsed,
        communicationElapsed: fixedExpressionElapsed,
        animationElapsed: fixedExpressionElapsed,
        reduceMotion: false,
        projection: .flat
      )

      XCTAssertLessThan(
        insideWindow.eyes.left.height,
        outsideWindow.eyes.left.height * 0.65,
        label
      )
      XCTAssertLessThan(
        insideWindow.eyes.right.height,
        outsideWindow.eyes.right.height * 0.65,
        label
      )
    }
  }

  func testSeparateExpressionClockDoesNotResetActivityMotion() {
    let task = CharacterTaskID(UUID())
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: task)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: task, progress: 0.5)
      ).state

    let before = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.62,
      expressionElapsed: 0.62
    )
    let withFreshExpressionClock = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.62,
      expressionElapsed: 0
    )
    XCTAssertEqual(before.writingPhase, withFreshExpressionClock.writingPhase)
  }

  func testMotionProfileControlsTrailsAndAccentsWithoutChangingSemanticState() throws {
    let profile = try CharacterMotionProfile(
      expressiveness: 0.5,
      trailStrength: 0,
      accentStrength: 0,
      idleStrength: 0.5
    )
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.surprise)
    ).state
    let pose = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.12,
      reduceMotion: false,
      motionProfile: profile
    )
    XCTAssertNil(pose.nearTrail)
    XCTAssertNil(pose.farTrail)
    XCTAssertTrue(pose.accents.isEmpty)
    XCTAssertEqual(state.emotion, .surprise)
  }

  func testExpressiveEntryUsesWholeCharacterAnticipation() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let anticipation = ReactiveCharacter.pose(state: state, elapsed: 0.055)
    let snap = ReactiveCharacter.pose(state: state, elapsed: 0.12)
    XCTAssertNotEqual(anticipation.surface, .identity)
    XCTAssertNotEqual(snap.surface, anticipation.surface)
  }

  func testMotionSamplerIsDeterministic() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentStarted(taskID: taskA)
      ).state

    let a = ReactiveCharacter.pose(state: state, elapsed: 1.234, reduceMotion: false)
    let b = ReactiveCharacter.pose(state: state, elapsed: 1.234, reduceMotion: false)
    XCTAssertEqual(a, b)
  }

  func testReducedMotionIsTimeIndependent() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.fatigueBurden)
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state

    let a = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true)
    let b = ReactiveCharacter.pose(state: state, elapsed: 500, reduceMotion: true)
    XCTAssertEqual(a, b)
  }

  func testVisibleSurfaceUsesInscribedSquareAndTransparentUsesFullRect() {
    let size = CharacterSize(width: 320, height: 200)
    XCTAssertEqual(
      CharacterGeometry.coordinateSpace(in: size, surface: .visible),
      CharacterRect(x: 60, y: 0, width: 200, height: 200)
    )
    XCTAssertEqual(
      CharacterGeometry.coordinateSpace(in: size, surface: .transparent),
      CharacterRect(x: 0, y: 0, width: 320, height: 200)
    )
  }

  func testRotatedEyeCapsuleRemainsInsideRegion() {
    let region = CharacterRect(x: 10, y: 20, width: 120, height: 80)
    let capsule = CharacterGeometry.fitCapsule(
      preferredCenterX: 10,
      preferredCenterY: 20,
      preferredWidth: 100,
      preferredHeight: 60,
      angle: 0.4,
      inside: region
    )
    XCTAssertTrue(
      CharacterGeometry.contains(region, CharacterGeometry.capsuleBounds(capsule))
    )
  }

  func testExplicitAnimationLifecycleUsesStableIdentity() {
    let firstID = CharacterAnimationID(UUID())
    let secondID = CharacterAnimationID(UUID())

    let started = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .animationStarted(id: firstID, animation: .bounce)
    )
    XCTAssertEqual(
      started.state.animation,
      CharacterAnimationState(id: firstID, animation: .bounce)
    )

    let duplicate = ReactiveCharacter.reduce(
      state: started.state,
      event: .animationStarted(id: firstID, animation: .bounce)
    )
    XCTAssertEqual(duplicate.disposition, .ignored(.duplicate))

    let conflict = ReactiveCharacter.reduce(
      state: started.state,
      event: .animationStarted(id: firstID, animation: .shake)
    )
    XCTAssertEqual(conflict.disposition, .rejected(.animationIdentityConflict(id: firstID)))

    let staleEnd = ReactiveCharacter.reduce(
      state: started.state,
      event: .animationEnded(id: secondID)
    )
    XCTAssertEqual(
      staleEnd.disposition,
      .ignored(.staleAnimation(expected: firstID, received: secondID))
    )

    let ended = ReactiveCharacter.reduce(
      state: started.state,
      event: .animationEnded(id: firstID)
    )
    XCTAssertNil(ended.state.animation)
  }

  func testEmotionPreemptsExplicitAnimationSemantically() {
    let animationID = CharacterAnimationID(UUID())
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .animationStarted(id: animationID, animation: .shake)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .emotionChanged(.joy)
      ).state

    XCTAssertEqual(state.emotion, .joy)
    XCTAssertNil(state.animation)
  }

  func testEveryExplicitAnimationHasTimeVaryingPresentation() {
    for animation in CharacterAnimation.allCases {
      let id = CharacterAnimationID(UUID())
      let state = ReactiveCharacter.reduce(
        state: ReactiveCharacter.initialState,
        event: .animationStarted(id: id, animation: animation)
      ).state
      let early = ReactiveCharacter.pose(state: state, elapsed: 0.12, expressionElapsed: 0.12)
      let later = ReactiveCharacter.pose(state: state, elapsed: 0.48, expressionElapsed: 0.48)
      XCTAssertNotEqual(early, later, animation.rawValue)
    }
  }

  func testPresentationSessionReturnsThroughNeutralWithinOneSecond() {
    let joy = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let surprise = ReactiveCharacter.reduce(
      state: joy,
      event: .emotionChanged(.surprise)
    ).state

    var session = CharacterPresentationSession(state: joy, at: 0)
    let source = session.pose(at: 0.34)
    XCTAssertTrue(session.update(state: surprise, at: 0.34))
    XCTAssertEqual(session.pose(at: 0.34), source)

    let initialStatus = session.inspect(at: 0.34)
    XCTAssertLessThanOrEqual(initialStatus.remainingHandoffDuration, 1.0)
    guard case .returningToNeutral = initialStatus.phase else {
      return XCTFail("expected returningToNeutral")
    }

    let handoffEnd = 0.34 + initialStatus.remainingHandoffDuration
    let neutral = ReactiveCharacter.pose(
      state: .idle,
      elapsed: 0,
      reduceMotion: true
    )
    XCTAssertEqual(session.pose(at: handoffEnd - 0.01), neutral)
    XCTAssertEqual(session.inspect(at: handoffEnd - 0.01).phase, .neutralHold)

    let target = session.pose(at: handoffEnd + 0.02)
    XCTAssertNotEqual(target, neutral)
    XCTAssertEqual(session.inspect(at: handoffEnd + 0.02).phase, .performing)
  }

  func testInterruptingAnInterruptionCapturesCurrentPoseWithoutWarp() {
    let joy = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    let surprise = ReactiveCharacter.reduce(
      state: joy,
      event: .emotionChanged(.surprise)
    ).state
    let anger = ReactiveCharacter.reduce(
      state: surprise,
      event: .emotionChanged(.angerIrritation)
    ).state

    var session = CharacterPresentationSession(state: joy, at: 0)
    XCTAssertTrue(session.update(state: surprise, at: 0.30))
    let interruptedPose = session.pose(at: 0.44)
    XCTAssertTrue(session.update(state: anger, at: 0.44))
    XCTAssertEqual(session.pose(at: 0.44), interruptedPose)
    XCTAssertLessThanOrEqual(session.inspect(at: 0.44).remainingHandoffDuration, 1.0)
  }

  func testParameterOnlyUpdatesDoNotRestartPresentationHandoff() {
    let task = CharacterTaskID(UUID())
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: task)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: task, progress: 0.2)
      ).state

    var session = CharacterPresentationSession(state: state, at: 0)
    let progressed = ReactiveCharacter.reduce(
      state: state,
      event: .agentProgress(taskID: task, progress: 0.6)
    ).state
    XCTAssertFalse(session.update(state: progressed, at: 0.4))
    XCTAssertEqual(session.inspect(at: 0.4).phase, .performing)
  }

  func testInspectionDoesNotOfferDuplicateCancellationWhileCancellationIsPending() {
    let taskID = CharacterTaskID(UUID())
    let started = ReactiveCharacter.reduce(
      state: .idle,
      event: .agentStarted(taskID: taskID)
    ).state
    let cancelling = ReactiveCharacter.reduce(
      state: started,
      event: .agentCancellationRequested(taskID: taskID)
    ).state

    let inspection = ReactiveCharacter.inspect(state: cancelling)
    XCTAssertEqual(inspection.activeTaskID, taskID)
    XCTAssertFalse(inspection.canCancelTask)
  }

  func testAgentNativeInspectAndActReturnStructuredEvidence() {
    let before = ReactiveCharacter.initialState
    let inspection = ReactiveCharacter.inspect(state: before)
    XCTAssertEqual(inspection.visualAuthority, .neutral)
    XCTAssertFalse(inspection.canCancelTask)

    let receipt = ReactiveCharacter.act(
      state: before,
      event: .emotionChanged(.affection)
    )
    XCTAssertEqual(receipt.stateBefore, before)
    XCTAssertEqual(receipt.stateAfter.emotion, .affection)
    XCTAssertEqual(receipt.disposition, .accepted)
    guard case .handoffThroughNeutral(let maximumDuration) = receipt.presentation else {
      return XCTFail("expected handoff directive")
    }
    XCTAssertLessThanOrEqual(maximumDuration, 1.0)
  }

  func testNewestMeaningfulSemanticActionOwnsLargePresentationMotion() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.joy)
    ).state
    XCTAssertEqual(state.visualChannel, .emotion)

    let task = CharacterTaskID(UUID())
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentStarted(taskID: task)
      ).state
    XCTAssertEqual(state.visualChannel, .activity)
    XCTAssertEqual(
      state.emotion, .joy, "emotion remains semantic styling while activity owns motion")

    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .emotionChanged(.joy)
      ).state
    XCTAssertEqual(
      state.visualChannel, .emotion, "same emotion can explicitly reclaim visual authority")
  }

  func testParameterUpdatesDoNotStealVisualAuthority() {
    let task = CharacterTaskID(UUID())
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: task)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: task, progress: 0.2)
      ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .emotionChanged(.interest)
      ).state
    XCTAssertEqual(state.visualChannel, .emotion)

    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentProgress(taskID: task, progress: 0.6)
      ).state
    XCTAssertEqual(state.visualChannel, .emotion)
  }

  func testEndingVisualOwnerFallsBackToRemainingSemanticState() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.calmTrust)
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    XCTAssertEqual(state.visualChannel, .communication)

    state = ReactiveCharacter.reduce(state: state, event: .communicationEnded).state
    XCTAssertEqual(state.visualChannel, .emotion)

    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(nil)).state
    XCTAssertEqual(state.visualChannel, .neutral)
  }

  func testActivityCanPreemptEmotionWithoutVisualWarp() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .emotionChanged(.surprise)
    ).state
    var session = CharacterPresentationSession(state: state, at: 0)
    let before = session.pose(at: 0.31)

    let task = CharacterTaskID(UUID())
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .agentStarted(taskID: task)
      ).state
    XCTAssertEqual(state.visualChannel, .activity)
    XCTAssertTrue(session.update(state: state, at: 0.31))
    XCTAssertEqual(session.pose(at: 0.31), before)
    XCTAssertLessThanOrEqual(session.inspect(at: 0.31).remainingHandoffDuration, 1)
  }

  func testAttentionIsIndependentSemanticGazeControl() {
    let left = point(0.10, 0.50)
    let focused = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .attentionFocused(left)
    )
    XCTAssertEqual(focused.state.attention, .focus(left))
    XCTAssertEqual(focused.state.visualChannel, .neutral)

    let receipt = ReactiveCharacter.act(
      state: ReactiveCharacter.initialState,
      event: .attentionFocused(left)
    )
    guard case .gazeTransition(let maximumDuration) = receipt.presentation else {
      return XCTFail("expected gaze transition")
    }
    XCTAssertLessThanOrEqual(maximumDuration, 0.135)
  }

  func testAttentionTransitionUsesSaccadeWithoutNeutralHandoff() {
    var session = CharacterPresentationSession(state: .idle, at: 0)
    let before = session.pose(at: 0.40)
    let focus = point(0.92, 0.50)
    let focused = ReactiveCharacter.reduce(
      state: .idle,
      event: .attentionFocused(focus)
    ).state

    XCTAssertFalse(session.update(state: focused, at: 0.40))
    XCTAssertEqual(session.pose(at: 0.40), before)
    guard case .gazeTransition = session.inspect(at: 0.40).phase else {
      return XCTFail("expected gazeTransition")
    }
    XCTAssertLessThanOrEqual(session.inspect(at: 0.40).remainingHandoffDuration, 0.135)
    XCTAssertEqual(session.inspect(at: 0.55).phase, .performing)
  }

  func testEmotionAndActivityGazeComposeInsteadOfSerializing() {
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .userWritingBegan(focus: point(0.05, 0.50))
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.joy)).state
    XCTAssertEqual(state.visualChannel, .emotion)

    let left = ReactiveCharacter.pose(state: state, elapsed: 0.52, expressionElapsed: 0.52)
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .userWritingChanged(focus: point(0.95, 0.50))
      ).state
    let right = ReactiveCharacter.pose(state: state, elapsed: 0.52, expressionElapsed: 0.52)

    XCTAssertLessThan(left.eyes.left.centerX, right.eyes.left.centerX)
    XCTAssertGreaterThan(left.mouth.curvature, 0.5)
    XCTAssertGreaterThan(right.mouth.curvature, 0.5)
    XCTAssertTrue(right.writingVisible)
    XCTAssertGreaterThan(right.writingOpacity, 0)
  }

  func testConversationKeepsPurposefulGazeAlive() {
    let state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .chatStarted
    ).state
    let front = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.60,
      communicationElapsed: 0.60
    )
    let averted = ReactiveCharacter.pose(
      state: state,
      elapsed: 1.55,
      communicationElapsed: 1.55
    )
    XCTAssertNotEqual(front.eyes.left.centerX, averted.eyes.left.centerX)
    XCTAssertTrue(averted.mouth.visible)
  }

  func testExplicitAnimationsAreOneShotAndScheduleTheirResultEvent() {
    let id = CharacterAnimationID(UUID())
    let started = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .animationStarted(id: id, animation: .celebrate)
    )
    XCTAssertEqual(
      started.effects,
      [
        .scheduleAnimationEnd(
          id: id,
          after: CharacterAnimation.celebrate.duration
            + CharacterTransitionProfile.maximumAllowedHandoffDuration
        )
      ]
    )

    let early = ReactiveCharacter.pose(
      state: started.state,
      elapsed: 0.25,
      animationElapsed: 0.25
    )
    let afterDuration = ReactiveCharacter.pose(
      state: started.state,
      elapsed: 2.0,
      animationElapsed: 2.0
    )
    XCTAssertNotEqual(early.surface, afterDuration.surface)
    XCTAssertEqual(afterDuration.surface, .identity)
  }

  func testFullHandoffPreservesUnchangedActivityClock() {
    let task = CharacterTaskID(UUID())
    var state = ReactiveCharacter.reduce(
      state: ReactiveCharacter.initialState,
      event: .agentStarted(taskID: task)
    ).state
    var session = CharacterPresentationSession(state: state, at: 0)

    let beforeEmotion = 0.72
    _ = session.pose(at: beforeEmotion)
    state = ReactiveCharacter.reduce(state: state, event: .emotionChanged(.interest)).state
    XCTAssertTrue(session.update(state: state, at: beforeEmotion))
    let handoff = session.inspect(at: beforeEmotion).remainingHandoffDuration
    let resumedAt = beforeEmotion + handoff
    // Sample after the shared 170 ms face-entry envelope, not during interpolation.
    let observed = session.pose(at: resumedAt + 0.20)
    let expected = ReactiveCharacter.pose(
      state: state,
      elapsed: beforeEmotion + 0.20,
      expressionElapsed: 0.20,
      communicationElapsed: beforeEmotion + 0.20,
      animationElapsed: beforeEmotion + 0.20
    )
    XCTAssertEqual(observed.eyes.left.centerX, expected.eyes.left.centerX, accuracy: 1e-9)
    XCTAssertEqual(observed.eyes.right.centerX, expected.eyes.right.centerX, accuracy: 1e-9)
  }

  func testAnimationEndEffectCannotFireBeforeWorstCasePresentationStart() {
    let id = CharacterAnimationID(UUID())
    let transition = ReactiveCharacter.reduce(
      state: .idle,
      event: .animationStarted(id: id, animation: .blink)
    )
    XCTAssertEqual(
      transition.effects,
      [
        .scheduleAnimationEnd(
          id: id,
          after: CharacterAnimation.blink.duration
            + CharacterTransitionProfile.maximumAllowedHandoffDuration
        )
      ]
    )
  }

  func testExpiredAnimationVisuallyFallsBackBeforeSemanticCleanup() {
    let id = CharacterAnimationID(UUID())
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationStarted(id: id, animation: .blink)
      ).state

    let expired = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.9,
      expressionElapsed: 0.9,
      animationElapsed: CharacterAnimation.blink.duration + 0.01
    )
    let fallbackState = ReactiveCharacter.reduce(
      state: state,
      event: .animationEnded(id: id)
    ).state
    let fallback = ReactiveCharacter.pose(
      state: fallbackState,
      elapsed: 0.9,
      expressionElapsed: 0.9,
      animationElapsed: 0
    )

    XCTAssertEqual(expired.eyes, fallback.eyes)
    XCTAssertEqual(expired.mouth, fallback.mouth)
    XCTAssertEqual(expired.surface, fallback.surface)
  }

  func testExpiredAnimationStaysFallbackAfterOneDayBoundary() {
    let id = CharacterAnimationID(UUID())
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationStarted(id: id, animation: .celebrate)
      ).state

    // A one-shot remains expired even at very large elapsed values; periodic
    // presentation math must not turn semantic expiry back into an active animation.
    let elapsed = 86_400 + CharacterAnimation.celebrate.duration / 2
    let expired = ReactiveCharacter.pose(
      state: state,
      elapsed: elapsed,
      expressionElapsed: elapsed,
      communicationElapsed: elapsed,
      animationElapsed: elapsed
    )
    let fallbackState = ReactiveCharacter.reduce(
      state: state,
      event: .animationEnded(id: id)
    ).state
    let fallback = ReactiveCharacter.pose(
      state: fallbackState,
      elapsed: elapsed,
      expressionElapsed: elapsed,
      communicationElapsed: elapsed,
      animationElapsed: 0
    )

    XCTAssertEqual(expired, fallback)
  }

  func testExpiredAnimationCleanupDoesNotCreateSecondNeutralHandoff() {
    let id = CharacterAnimationID(UUID())
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationStarted(id: id, animation: .blink)
      ).state

    var session = CharacterPresentationSession(state: state, at: 0)
    let cleanupTime = CharacterAnimation.blink.duration + 0.05
    let before = session.pose(at: cleanupTime)
    let cleaned = ReactiveCharacter.reduce(state: state, event: .animationEnded(id: id)).state

    XCTAssertFalse(session.update(state: cleaned, at: cleanupTime))
    XCTAssertEqual(session.pose(at: cleanupTime), before)
    XCTAssertEqual(session.inspect(at: cleanupTime).phase, .performing)
  }

  func testReduceMotionReconciliationClearsActiveHandoffWithoutSemanticChange() {
    let joy = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    let surprise = ReactiveCharacter.reduce(
      state: joy,
      event: .emotionChanged(.surprise)
    ).state

    var session = CharacterPresentationSession(state: joy, at: 0)
    XCTAssertTrue(session.update(state: surprise, at: 0.30))
    guard case .returningToNeutral = session.inspect(at: 0.34).phase else {
      return XCTFail("expected active neutral handoff")
    }

    XCTAssertFalse(
      session.update(
        state: surprise,
        at: 0.34,
        reduceMotion: true
      )
    )
    XCTAssertEqual(session.inspect(at: 0.34).phase, .performing)
    XCTAssertEqual(
      session.pose(at: 0.34, reduceMotion: true),
      ReactiveCharacter.pose(state: surprise, elapsed: 0, reduceMotion: true)
    )
  }

  func testAnimationTemporarilyOverridesAndRestoresLatestSemanticVisualOwner() {
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    XCTAssertEqual(state.visualChannel, .communication)

    let animationID = CharacterAnimationID(UUID())
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationStarted(id: animationID, animation: .bounce)
      ).state
    XCTAssertEqual(state.visualChannel, .animation)

    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationEnded(id: animationID)
      ).state
    XCTAssertEqual(state.visualChannel, .communication)
  }

  func testAnimationRestorationSkipsSemanticOwnerThatEndedDuringOverride() {
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.calmTrust)
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .chatStarted).state
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .userWritingBegan(focus: point(0.6, 0.4))
      ).state
    XCTAssertEqual(state.visualChannel, .activity)

    let animationID = CharacterAnimationID(UUID())
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationStarted(id: animationID, animation: .nod)
      ).state
    state = ReactiveCharacter.reduce(state: state, event: .userWritingEnded).state
    XCTAssertEqual(state.visualChannel, .animation)

    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .animationEnded(id: animationID)
      ).state
    XCTAssertEqual(state.visualChannel, .communication)

    state = ReactiveCharacter.reduce(state: state, event: .communicationEnded).state
    XCTAssertEqual(state.visualChannel, .emotion)
  }

  func testUserWritingChangedRequiresActiveWritingPhase() {
    let fromIdle = ReactiveCharacter.reduce(
      state: .idle,
      event: .userWritingChanged(focus: point(0.7, 0.5))
    )
    XCTAssertEqual(fromIdle.state, .idle)
    XCTAssertEqual(fromIdle.disposition, .ignored(.eventNotApplicable))
    XCTAssertTrue(fromIdle.effects.isEmpty)

    let taskID = CharacterTaskID(UUID())
    let agent = ReactiveCharacter.reduce(
      state: .idle,
      event: .agentStarted(taskID: taskID)
    ).state
    let whileAgentRuns = ReactiveCharacter.reduce(
      state: agent,
      event: .userWritingChanged(focus: point(0.3, 0.5))
    )
    XCTAssertEqual(whileAgentRuns.state, agent)
    XCTAssertEqual(whileAgentRuns.disposition, .ignored(.eventNotApplicable))
    XCTAssertTrue(whileAgentRuns.effects.isEmpty)
  }

  func testDefaultStyleInitializerMatchesCanonicalDefault() throws {
    XCTAssertEqual(try CharacterStyle(), .default)

    let customEyes = try CharacterColor(red: 0.95, green: 0.86, blue: 0.72)
    let customized = try CharacterStyle(partColors: CharacterPartColors(eyes: customEyes))
    XCTAssertEqual(customized.partColors.eyes, customEyes)
    XCTAssertEqual(customized.partColors.accent, .accentDefault)
    XCTAssertEqual(customized.partColors.accessoryDetail, customEyes)
  }

  func testValidationRejectsInvalidInputsWithoutFallback() throws {
    XCTAssertThrowsError(try CharacterPoint(validatingX: -0.1, y: 0.5))
    XCTAssertThrowsError(try CharacterProgress(validating: .nan))
    XCTAssertThrowsError(try CharacterVoiceLevel(validating: 2))
    XCTAssertThrowsError(try CharacterTaskID(validating: "  "))
    XCTAssertThrowsError(try CharacterAnimationID(validating: "  "))
    XCTAssertThrowsError(try CharacterFailure(operation: "", cause: "timeout"))
  }

  func testAccessoryResourcesAreBundledAsPNG() throws {
    for accessory in CharacterBuiltInAccessoryID.allCases {
      let asset = CharacterBuiltInAccessoryCatalog.spec(for: accessory).image
      let data = try CharacterImageResources.png(asset)
      XCTAssertGreaterThan(data.count, 8)
      XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }
  }

  #if os(iOS)
    func testReferenceResourcesDecodeForCanvasRendering() throws {
      for accessory: CharacterBuiltInAccessoryID in [.hood, .baseballCap, .bunnyEars] {
        let asset = CharacterBuiltInAccessoryCatalog.spec(for: accessory).image
        let image = try XCTUnwrap(CharacterPlatformImageLoader.named(asset))
        XCTAssertEqual(image.size, CGSize(width: 1024, height: 1024))
        XCTAssertNotNil(image.cgImage)
      }
      for glyph in CharacterMouthGlyph.allCases {
        let image = try MouthReferenceRasterLibrary.platformImage(for: glyph)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertNotNil(image.cgImage)
      }
      XCTAssertTrue(MouthReferenceRasterLibrary.unavailableGlyphs.isEmpty)
    }

    func testNativeImageLoaderReportsMissingAndInvalidFiles() throws {
      XCTAssertThrowsError(
        try CharacterPlatformImageLoader.load(url: nil, name: "missing.png"))

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try Data("not a png".utf8).write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }
      XCTAssertThrowsError(
        try CharacterPlatformImageLoader.load(url: url, name: "invalid.png"))
    }
  #endif

  func testMotionPresetsProduceDistinctRenderedPoseWithoutMutatingState() {
    let state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state

    let expressive = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.42,
      motionProfile: .expressive
    )
    let soft = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.42,
      motionProfile: .soft
    )
    let minimal = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.42,
      motionProfile: .minimal
    )

    XCTAssertNotEqual(expressive, soft)
    XCTAssertNotEqual(soft, minimal)
    XCTAssertNotEqual(expressive, minimal)
    XCTAssertEqual(state.emotion, .joy)
  }

  func testEmotionAttentionAndMotionComposeWithoutOverwritingEachOther() {
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    let joyAutomatic = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.37,
      motionProfile: .expressive
    )

    let left = point(0.12, 0.50)
    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .attentionFocused(left)
      ).state
    XCTAssertEqual(state.emotion, .joy)
    XCTAssertEqual(state.attention, .focus(left))
    let joyLeft = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.37,
      motionProfile: .expressive
    )
    XCTAssertNotEqual(joyAutomatic.eyes, joyLeft.eyes)

    let softJoyLeft = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.37,
      motionProfile: .soft
    )
    XCTAssertNotEqual(joyLeft, softJoyLeft)
    XCTAssertEqual(state.emotion, .joy)
    XCTAssertEqual(state.attention, .focus(left))

    state =
      ReactiveCharacter.reduce(
        state: state,
        event: .emotionChanged(.sadness)
      ).state
    XCTAssertEqual(state.emotion, .sadness)
    XCTAssertEqual(state.attention, .focus(left))
    let sadnessLeft = ReactiveCharacter.pose(
      state: state,
      elapsed: 0.37,
      motionProfile: .soft
    )
    XCTAssertNotEqual(softJoyLeft, sadnessLeft)
  }

  func testPresentationConfigurationChangeDropsStaleBridgeAndPreservesClockProgress() {
    let joy = ReactiveCharacter.reduce(
      state: .idle,
      event: .emotionChanged(.joy)
    ).state
    let surprise = ReactiveCharacter.reduce(
      state: joy,
      event: .emotionChanged(.surprise)
    ).state

    var stable = CharacterPresentationSession(state: joy, at: 0)
    let before = stable.pose(at: 0.42, motionProfile: .expressive)
    stable.reconcilePresentationConfigurationChange(at: 0.42)
    XCTAssertEqual(before, stable.pose(at: 0.42, motionProfile: .expressive))

    var interrupted = CharacterPresentationSession(state: joy, at: 0)
    XCTAssertTrue(interrupted.update(state: surprise, at: 0.30))
    guard case .returningToNeutral = interrupted.inspect(at: 0.34).phase else {
      return XCTFail("expected active handoff")
    }

    interrupted.reconcilePresentationConfigurationChange(at: 0.34)
    XCTAssertEqual(interrupted.inspect(at: 0.34).phase, .performing)
    let configured = interrupted.pose(
      at: 0.34,
      projection: .flat,
      motionProfile: .minimal
    )
    XCTAssertEqual(
      configured,
      ReactiveCharacter.pose(
        state: surprise,
        elapsed: 0,
        expressionElapsed: 0,
        communicationElapsed: 0,
        animationElapsed: 0,
        projection: .flat,
        motionProfile: .minimal
      )
    )
  }

  func testAnimationCompletionAfterResetCannotRestoreStaleAnimation() {
    let id = CharacterAnimationID(UUID())
    var state = ReactiveCharacter.reduce(
      state: .idle,
      event: .animationStarted(id: id, animation: .celebrate)
    ).state
    state = ReactiveCharacter.reduce(state: state, event: .reset).state

    let stale = ReactiveCharacter.reduce(
      state: state,
      event: .animationEnded(id: id)
    )
    XCTAssertEqual(stale.state, .idle)
    XCTAssertEqual(stale.disposition, .ignored(.noActiveAnimation(received: id)))
    XCTAssertTrue(stale.effects.isEmpty)
  }
}

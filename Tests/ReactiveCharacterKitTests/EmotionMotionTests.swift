import XCTest

@testable import ReactiveCharacterKit

final class EmotionMotionTests: XCTestCase {
  private func state(_ emotion: CharacterEmotion) -> CharacterState {
    ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
  }

  private func scene(
    _ state: CharacterState, at time: Double = 0, reduced: Bool = false,
    motion: CharacterEmotionMotion = .adaptive,
    components: CharacterComponents = [.eyes, .mouth]
  ) throws -> CharacterScene {
    let direction = try CharacterArtDirection(
      name: "Expression", components: components, projection: .flat,
      motionProfile: .focusedEmotion(motion))
    let pose = ReactiveCharacter.pose(
      state: state, elapsed: time, reduceMotion: reduced,
      projection: direction.projection, motionProfile: direction.motionProfile)
    return try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 400, height: 400)
  }

  func testEyeSilhouettesAloneDistinguishAllTwelveEmotions() throws {
    var silhouettes: [[CharacterSceneNode]] = []
    for emotion in CharacterEmotion.allCases {
      let frame = try scene(state(emotion), reduced: true, components: [.eyes])
      let eyes = frame.nodes.filter { $0.id == "eye.left" || $0.id == "eye.right" }
      XCTAssertEqual(eyes.count, 2)
      for previous in silhouettes { XCTAssertNotEqual(eyes, previous, emotion.rawValue) }
      silhouettes.append(eyes)
    }
    for emotion in [CharacterEmotion.affection, .gratitude] {
      let pose = ReactiveCharacter.pose(
        state: state(emotion), elapsed: 2, reduceMotion: true,
        projection: .flat, motionProfile: .focusedEmotion())
      XCTAssertEqual(pose.eyeContours.left, pose.eyeContours.right)
      XCTAssertTrue([0.0, 1.0].contains(pose.eyeContours.left.crescent))
    }
  }

  func testAnxietyActsOnceThenHoldsAcrossEveryMotionPolicy() {
    for mode in CharacterEmotionMotion.allCases {
      let profile = CharacterMotionProfile.focusedEmotion(mode)
      let entry = CharacterExpression.sample(
        emotion: .anxietyFear, elapsed: 0.16,
        reduceMotion: false, profile: profile)
      XCTAssertNotEqual(entry.surface, .identity)
      let settled = CharacterExpression.sample(
        emotion: .anxietyFear, elapsed: 2,
        reduceMotion: false, profile: profile)
      for time in [2.4, 3.0, 4.0, 8.2] {
        let later = CharacterExpression.sample(
          emotion: .anxietyFear, elapsed: time,
          reduceMotion: false, profile: profile)
        XCTAssertEqual(later.surface, settled.surface)
        XCTAssertEqual(later.gazeX, settled.gazeX)
        XCTAssertEqual(later.gazeY, settled.gazeY)
      }
      XCTAssertEqual(
        CharacterExpression.sample(
          emotion: .anxietyFear, elapsed: 0.16, reduceMotion: true, profile: profile),
        CharacterExpression.sample(
          emotion: .anxietyFear, elapsed: 20, reduceMotion: true, profile: profile))
    }
  }

  func testTwelveLabelsMatchEmotionCoreNativeOntology() {
    XCTAssertEqual(
      CharacterEmotion.allCases.map(\.rawValue),
      [
        "joy", "affection", "gratitude", "interest", "surprise", "calm_trust", "sadness",
        "anxiety_fear", "anger_irritation", "disgust_contempt", "shame_guilt", "fatigue_burden",
      ])
  }

  func testAllTwelveRemainDistinctAndReduceMotionRemovesChoreography() throws {
    var scenes: [CharacterScene] = []
    for emotion in CharacterEmotion.allCases {
      let first = try scene(state(emotion), reduced: true)
      for previous in scenes { XCTAssertNotEqual(first, previous, emotion.rawValue) }
      scenes.append(first)
      for mode in [CharacterEmotionMotion.adaptive, .restrained, .exaggerated] {
        XCTAssertEqual(first, try scene(state(emotion), at: 7, reduced: true, motion: mode), emotion.rawValue)
      }
    }
  }

  func testQuietEmotionsHaveSlowerSurfaceMovementThanReactiveEmotions() {
    func peakSpeed(_ emotion: CharacterEmotion) -> Double {
      var previous: CharacterSurfacePose?
      var peak = 0.0
      for frame in 0...480 {
        let pose = ReactiveCharacter.pose(
          state: state(emotion), elapsed: Double(frame) / 60,
          projection: .flat, motionProfile: .focusedEmotion())
        if let previous {
          peak = max(peak, hypot(
            pose.surface.offsetX - previous.offsetX,
            pose.surface.offsetY - previous.offsetY) * 60)
        }
        previous = pose.surface
      }
      return peak
    }
    let joy = peakSpeed(.joy)
    let surprise = peakSpeed(.surprise)
    let anger = peakSpeed(.angerIrritation)
    for emotion in [
      CharacterEmotion.affection, .gratitude, .calmTrust, .sadness, .shameGuilt, .fatigueBurden,
    ] {
      XCTAssertLessThan(peakSpeed(emotion), min(joy, surprise, anger) * 0.6, emotion.rawValue)
    }
  }

  func testSceneConsumesSurfaceWithoutChangingViewportOrFaceBounds() throws {
    let pose = ReactiveCharacter.pose(
      state: state(.joy), elapsed: 0.18, projection: .flat,
      motionProfile: .focusedEmotion())
    let direction = try CharacterArtDirection(name: "Surface", projection: .flat)
    let animated = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 400, height: 400)
    let fixed = try CharacterSceneBuilder.scene(
      pose: pose.replacingSurface(.identity), artDirection: direction, width: 400, height: 400)
    XCTAssertNotEqual(animated.surfaceTransform, fixed.surfaceTransform)
    XCTAssertNotEqual(
      animated.nodes.first { $0.id == "eye.left" }?.transform,
      fixed.nodes.first { $0.id == "eye.left" }?.transform)
    XCTAssertEqual(animated.faceBounds, fixed.faceBounds)
    XCTAssertEqual(animated.width, fixed.width)
    XCTAssertEqual(animated.height, fixed.height)
  }

  func testMotionModesDoNotChangeTaskOrSpeechClocks() throws {
    let id = try CharacterTaskID(validating: "independent-clocks")
    var s = ReactiveCharacter.act(state: state(.fatigueBurden), event: .agentStarted(taskID: id))
      .stateAfter
    s = ReactiveCharacter.act(state: s, event: .agentProgress(taskID: id, progress: 0.6)).stateAfter
    s = ReactiveCharacter.act(state: s, event: .voiceStarted).stateAfter
    s = ReactiveCharacter.act(state: s, event: .voiceLevelChanged(0.7)).stateAfter
    let reference = ReactiveCharacter.pose(
      state: s, elapsed: 1, projection: .flat, motionProfile: .focusedEmotion())
    for mode in CharacterEmotionMotion.allCases {
      let pose = ReactiveCharacter.pose(
        state: s, elapsed: 1, projection: .flat, motionProfile: .focusedEmotion(mode))
      XCTAssertEqual(pose.writingProgress, reference.writingProgress)
      XCTAssertEqual(pose.writingMotionPhase, reference.writingMotionPhase)
      XCTAssertEqual(pose.mouth.openness, reference.mouth.openness)
    }
  }

  func testHostOverrideChangesReactionWithoutChangingWritingActivity() throws {
    let joyful = state(.joy)
    let restrained = try scene(joyful, at: 0.16, motion: .restrained)
    let exaggerated = try scene(joyful, at: 0.16, motion: .exaggerated)
    XCTAssertNotEqual(restrained.surfaceTransform, exaggerated.surfaceTransform)
    let id = try CharacterTaskID(validating: "mode-independent-writing")
    let started = ReactiveCharacter.act(state: joyful, event: .agentStarted(taskID: id)).stateAfter
    let working = ReactiveCharacter.act(state: started, event: .agentProgress(taskID: id, progress: 0.6)).stateAfter
    let scenes = try [CharacterEmotionMotion.adaptive, .restrained, .exaggerated].map { mode in
      try scene(working, at: 1.2, motion: mode, components: [.eyes, .mouth, .writing])
    }
    let expected = scenes[0].nodes.filter { $0.id.hasPrefix("writing") }
    XCTAssertFalse(expected.isEmpty)
    for frame in scenes {
      XCTAssertEqual(frame.nodes.filter { $0.id.hasPrefix("writing") }, expected)
    }
  }

  func testExistingProfilesKeepAuthoredBehavior() {
    for profile in [CharacterMotionProfile.expressive, .cartoon, .soft, .companion, .minimal] {
      XCTAssertEqual(profile.emotionMotion, .authored)
    }
  }
}

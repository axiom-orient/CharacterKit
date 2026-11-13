import Testing
@testable import ReactiveCharacterKit

struct CharacterDetailMotionTests {
  private func state(_ events: [CharacterEvent]) -> CharacterState {
    events.reduce(.idle) { ReactiveCharacter.act(state: $0, event: $1).stateAfter }
  }

  private func pose(
    _ state: CharacterState = .idle,
    time: Double,
    reduced: Bool = false,
    profile: CharacterMotionProfile = .expressive
  ) -> CharacterPose {
    ReactiveCharacter.pose(
      state: state, elapsed: time, reduceMotion: reduced, motionProfile: profile)
  }

  private func components(_ motion: CharacterDetailMotion) -> [Double] {
    [motion.sway, motion.swayQuadrature, motion.quiver, motion.quiverQuadrature,
      motion.impulse, motion.amount]
  }

  private func distance(_ lhs: CharacterDetailMotion, _ rhs: CharacterDetailMotion) -> Double {
    zip(components(lhs), components(rhs)).map { abs($0 - $1) }.max() ?? 0
  }

  @Test
  func swayAndElectricQuiverUseBoundedQuadratureAtTheirOwnRates() {
    let speaking = state([.chatStarted])
    let origin = pose(speaking, time: 0).detailMotion
    #expect(origin.sway == 0)
    #expect(abs(origin.swayQuadrature - 1) < 1e-12)
    #expect(origin.quiver == 0)
    #expect(abs(origin.quiverQuadrature - 1) < 1e-12)

    let slowQuarterCycle = pose(speaking, time: 1 / (4 * 0.7)).detailMotion
    let fastQuarterCycle = pose(speaking, time: 1 / (4 * 7.0)).detailMotion
    let slowIsFinite = components(slowQuarterCycle).allSatisfy { $0.isFinite }
    let fastIsFinite = components(fastQuarterCycle).allSatisfy { $0.isFinite }
    #expect(abs(slowQuarterCycle.sway - 1) < 1e-12)
    #expect(abs(fastQuarterCycle.quiver - 1) < 1e-12)
    #expect(slowIsFinite)
    #expect(fastIsFinite)
    #expect((-1...1).contains(slowQuarterCycle.swayQuadrature))
    #expect((-1...1).contains(fastQuarterCycle.quiverQuadrature))
  }

  @Test
  func neutralMinimalPoseKeepsItsExistingTimeInvariant() {
    let neutral = pose(.idle, time: 0.1, profile: .cartoon)
    for time in [0.4, 0.7, 1.0, 1.5] {
      let sample = pose(.idle, time: time, profile: .cartoon)
      #expect(sample.detailMotion == .still)
      #expect(sample == neutral)
    }
  }

  @Test
  func typedSEMIIdleStyleAddsOnlyGentleClockDrivenSway() throws {
    let direction = CharacterArtDirection.semiDocumentCat
    let standardSession = CharacterPresentationSession(state: .idle, at: 0)
    let semiSession = CharacterPresentationSession(
      state: .idle, at: 0, artDirection: direction)

    let standardStart = standardSession.pose(at: 0)
    let standardLater = standardSession.pose(at: 0.25)
    let semiStart = semiSession.pose(at: 0)
    let semiLater = semiSession.pose(at: 0.25)

    #expect(standardStart.detailMotion == .still)
    #expect(standardLater.detailMotion == .still)
    #expect(semiStart.detailMotion.amount > 0)
    #expect(semiStart.detailMotion.impulse == 0)
    #expect(semiLater.detailMotion != semiStart.detailMotion)
    #expect(semiSession.pose(at: 0.25, reduceMotion: true).detailMotion == .still)

    let publicSEMIStart = ReactiveCharacter.pose(
      state: .idle, elapsed: 0, artDirection: direction)
    let publicSEMILater = ReactiveCharacter.pose(
      state: .idle, elapsed: 0.25, artDirection: direction)
    let legacyProfilePose = ReactiveCharacter.pose(
      state: .idle, elapsed: 0.25,
      projection: direction.projection, motionProfile: direction.motionProfile)
    #expect(publicSEMIStart.detailMotion.amount > 0)
    #expect(publicSEMILater.detailMotion != publicSEMIStart.detailMotion)
    #expect(legacyProfilePose.detailMotion == .still)

    let stillProfile = try CharacterMotionProfile(
      expressiveness: 0, trailStrength: 0, accentStrength: 0, idleStrength: 0)
    #expect(semiSession.pose(at: 0.25, motionProfile: stillProfile).detailMotion == .still)
  }

  @Test
  func publicSessionInitializerKeepsSEMIStyleAcrossHandoffAndConfigurationChange() {
    let direction = CharacterArtDirection.semiDocumentCat
    let joy = state([.emotionChanged(.joy)])
    let handoffTime = 0.357
    var semiSession = CharacterPresentationSession(state: joy, at: 0, artDirection: direction)
    var legacySession = CharacterPresentationSession(state: joy, at: 0)
    let detailBefore = semiSession.pose(
      at: handoffTime, projection: direction.projection, motionProfile: direction.motionProfile
    ).detailMotion

    semiSession.update(state: .idle, at: handoffTime,
      projection: direction.projection, motionProfile: direction.motionProfile,
      transitionProfile: direction.transitionProfile)
    legacySession.update(state: .idle, at: handoffTime,
      projection: direction.projection, motionProfile: direction.motionProfile,
      transitionProfile: direction.transitionProfile)
    #expect(semiSession.pose(
      at: handoffTime, projection: direction.projection, motionProfile: direction.motionProfile
    ).detailMotion == detailBefore)

    let remaining = semiSession.inspect(at: handoffTime).remainingHandoffDuration
    let resumedTime = handoffTime + remaining + 0.01
    let resumedSEMI = semiSession.pose(
      at: resumedTime, projection: direction.projection, motionProfile: direction.motionProfile
    )
    let resumedLegacy = legacySession.pose(
      at: resumedTime, projection: direction.projection, motionProfile: direction.motionProfile
    )
    #expect(resumedSEMI.detailMotion.amount > 0)
    #expect(resumedLegacy.detailMotion == .still)

    var reconfigured = CharacterPresentationSession(state: .idle, at: 0)
    let configureAt = 0.25
    reconfigured.reconcilePresentationConfigurationChange(at: configureAt, artDirection: direction)
    let configured = reconfigured.pose(
      at: configureAt, projection: direction.projection, motionProfile: direction.motionProfile
    )
    let configuredFromInit = CharacterPresentationSession(
      state: .idle, at: 0, artDirection: direction).pose(
        at: configureAt, projection: direction.projection, motionProfile: direction.motionProfile)
    #expect(configured.detailMotion == configuredFromInit.detailMotion)
  }

  @Test
  func extremeFiniteSamplesStayBoundedAndUseNumericAnimationImpulse() throws {
    let animationID = try CharacterAnimationID(validating: "detail-motion-bounce")
    let bouncing = state([.animationStarted(id: animationID, animation: .bounce)])
    let rest = pose(time: 0.22).detailMotion
    let impact = pose(bouncing, time: 0.22).detailMotion
    #expect(impact.impulse > rest.impulse)
    #expect(impact.amount > 0)

    for time in [0.0, 0.22, 10_000.0, Double.greatestFiniteMagnitude] {
      for sample in [pose(time: time), pose(bouncing, time: time)] {
        let motion = sample.detailMotion
        let isFinite = components(motion).allSatisfy { $0.isFinite }
        #expect(isFinite)
        #expect((-1...1).contains(motion.sway))
        #expect((-1...1).contains(motion.swayQuadrature))
        #expect((-1...1).contains(motion.quiver))
        #expect((-1...1).contains(motion.quiverQuadrature))
        #expect((0...1).contains(motion.impulse))
        #expect((0...1).contains(motion.amount))
      }
    }
  }

  @Test
  func ordinaryEmotionAndBlinkEnergyDoNotMasqueradeAsImpact() throws {
    let joy = state([.emotionChanged(.joy)])
    let laugh = pose(joy, time: 0.23)
    #expect(laugh.surface != .identity)
    #expect(laugh.motionEnergy > 0)
    #expect(laugh.detailMotion.impulse == 0)

    let blinkID = try CharacterAnimationID(validating: "detail-motion-blink")
    let blink = state([.animationStarted(id: blinkID, animation: .blink)])
    #expect(pose(blink, time: 0.08).detailMotion.impulse == 0)

    let recoilID = try CharacterAnimationID(validating: "detail-motion-impact")
    let recoil = state([.animationStarted(id: recoilID, animation: .recoil)])
    #expect(pose(recoil, time: 0.13).detailMotion.impulse > 0)
  }

  @Test
  func reducedMotionAndZeroExpressivenessSuppressEveryDetailChannel() throws {
    let animationID = try CharacterAnimationID(validating: "detail-motion-shake")
    let active = state([
      .voiceStarted, .voiceLevelChanged(1),
      .animationStarted(id: animationID, animation: .shake),
    ])
    let stillProfile = try CharacterMotionProfile(
      expressiveness: 0, trailStrength: 0, accentStrength: 0, idleStrength: 0)

    for time in [0.0, 0.17, 0.42, 1.0] {
      #expect(pose(active, time: time, reduced: true).detailMotion == .still)
      #expect(pose(active, time: time, profile: stillProfile).detailMotion == .still)
    }
  }

  @Test
  func voiceAndProgressRetargetsPreserveTheirClockAndPresentedDetail() throws {
    let quietVoice = state([.voiceStarted, .voiceLevelChanged(0.1)])
    var voiceSession = CharacterPresentationSession(state: quietVoice, at: 0)
    let voiceTime = 0.53
    let voiceBefore = voiceSession.pose(at: voiceTime).detailMotion
    let loudVoice = ReactiveCharacter.act(
      state: quietVoice, event: .voiceLevelChanged(0.9)).stateAfter
    voiceSession.update(state: loudVoice, at: voiceTime)
    #expect(voiceSession.pose(at: voiceTime).detailMotion == voiceBefore)
    let voiceMidpoint = voiceSession.pose(at: voiceTime + 0.05).detailMotion
    let voiceSettled = voiceSession.pose(at: voiceTime + 0.10).detailMotion
    #expect(voiceMidpoint.amount > voiceBefore.amount)
    #expect(voiceSettled == pose(loudVoice, time: voiceTime + 0.10).detailMotion)

    let taskID = try CharacterTaskID(validating: "detail-progress")
    let earlyProgress = state([
      .agentStarted(taskID: taskID), .agentProgress(taskID: taskID, progress: 0.2),
    ])
    var progressSession = CharacterPresentationSession(state: earlyProgress, at: 0)
    let progressTime = 0.31
    let progressBefore = progressSession.pose(at: progressTime).detailMotion
    let lateProgress = ReactiveCharacter.act(
      state: earlyProgress, event: .agentProgress(taskID: taskID, progress: 0.8)).stateAfter
    progressSession.update(state: lateProgress, at: progressTime)
    #expect(progressSession.inspect(at: progressTime).phase == .gazeTransition(progress: 0))
    #expect(progressSession.pose(at: progressTime).detailMotion == progressBefore)
    let shortlyAfter = progressSession.pose(at: progressTime + 0.0001).detailMotion
    #expect(distance(progressBefore, shortlyAfter) < 0.05)
    #expect(distance(shortlyAfter,
      pose(lateProgress, time: progressTime + 0.0001).detailMotion) < 0.01)
  }

  @Test
  func fullHandoffBlendsSampledVectorsWithoutPhaseWrapAndPoseCopiesPreserveThem() throws {
    let joy = state([.emotionChanged(.joy)])
    var session = CharacterPresentationSession(state: joy, at: 0)
    let handoffTime = 0.357
    let before = session.pose(at: handoffTime)
    let sadness = ReactiveCharacter.act(state: joy, event: .emotionChanged(.sadness)).stateAfter
    session.update(state: sadness, at: handoffTime)
    let atHandoff = session.pose(at: handoffTime)
    #expect(atHandoff.detailMotion == before.detailMotion)
    #expect(distance(before.detailMotion, session.pose(at: handoffTime + 0.0001).detailMotion) < 0.05)

    let remaining = session.inspect(at: handoffTime).remainingHandoffDuration
    let neutral = session.pose(at: handoffTime + remaining)
    #expect(neutral.detailMotion == .still)
    let reentering = session.pose(at: handoffTime + remaining + 0.001)
    let reenteringIsFinite = components(reentering.detailMotion).allSatisfy { $0.isFinite }
    #expect(reenteringIsFinite)
    #expect(distance(neutral.detailMotion, reentering.detailMotion) < 0.05)

    let sourcePose = pose(.idle, time: handoffTime)
    #expect(sourcePose.replacingSurface(.identity).detailMotion == sourcePose.detailMotion)
  }
}

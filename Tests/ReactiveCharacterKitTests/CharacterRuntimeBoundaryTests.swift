import Foundation
@testable import ReactiveCharacterKit
import Testing

struct CharacterRuntimeBoundaryTests {
  private func state(_ events: [CharacterEvent]) -> CharacterState {
    events.reduce(.idle) { ReactiveCharacter.reduce(state: $0, event: $1).state }
  }

  @Test
  func voiceLevelRetargetsFromPresentedValueAndKeepsCommunicationClock() {
    let quiet = state([.voiceStarted])
    var session = CharacterPresentationSession(state: quiet, at: 0)
    let quietPose = session.pose(at: 0.52)
    let loud = ReactiveCharacter.reduce(
      state: quiet, event: .voiceLevelChanged(1)
    ).state

    let startedHandoff = session.update(state: loud, at: 0.52)
    #expect(!startedHandoff)
    let transitionStart = session.pose(at: 0.52)
    #expect(transitionStart.mouth == quietPose.mouth)
    #expect(session.inspect(at: 0.52).state == loud)

    let loudRawPose = ReactiveCharacter.pose(state: loud, elapsed: 0.57)
    let middle = session.pose(at: 0.57)
    #expect(middle.mouth.openness > transitionStart.mouth.openness)
    #expect(middle.mouth.openness < loudRawPose.mouth.openness)

    let medium = ReactiveCharacter.reduce(
      state: loud, event: .voiceLevelChanged(0.4)
    ).state
    let retargetedHandoff = session.update(state: medium, at: 0.57)
    #expect(!retargetedHandoff)
    #expect(session.pose(at: 0.57).mouth == middle.mouth)
    #expect(session.inspect(at: 0.57).state == medium)

    let settled = session.pose(at: 0.72)
    let expected = ReactiveCharacter.pose(state: medium, elapsed: 0.72)
    #expect(settled.mouth == expected.mouth)
  }

  @Test
  func progressRetargetsEyesFromPresentedValueAndLeavesWritingClockAlone() throws {
    let taskID = try CharacterTaskID(validating: "runtime-progress")
    let thinking = state([.agentStarted(taskID: taskID)])
    let early = ReactiveCharacter.reduce(
      state: thinking, event: .agentProgress(taskID: taskID, progress: 0.1)
    ).state
    var session = CharacterPresentationSession(state: early, at: 0)
    let before = session.pose(at: 0.1)

    let progressReceipt = ReactiveCharacter.act(
      state: early, event: .agentProgress(taskID: taskID, progress: 0.9)
    )
    let late = progressReceipt.stateAfter
    guard case .gazeTransition(let maximumDuration) = progressReceipt.presentation else {
      Issue.record("Agent progress must expose its gaze retarget to receipt-based hosts")
      return
    }
    #expect(maximumDuration > 0)
    let startedHandoff = session.update(state: late, at: 0.1)
    #expect(!startedHandoff)
    #expect(session.pose(at: 0.1).eyes == before.eyes)
    #expect(session.inspect(at: 0.1).state == late)

    let lateRawPose = ReactiveCharacter.pose(state: late, elapsed: 0.15)
    let middle = session.pose(at: 0.15)
    #expect(middle.eyes.left.centerX > before.eyes.left.centerX)
    #expect(middle.eyes.left.centerX < lateRawPose.eyes.left.centerX)
    #expect(middle.eyes.left.blink == lateRawPose.eyes.left.blink)
    #expect(middle.surface == lateRawPose.surface)
    #expect(middle.writingMotionPhase == lateRawPose.writingMotionPhase)
    #expect(middle.writingProgress == 0.9)

    let almostComplete = ReactiveCharacter.reduce(
      state: late, event: .agentProgress(taskID: taskID, progress: 0.95)
    ).state
    let retargetedHandoff = session.update(state: almostComplete, at: 0.15)
    #expect(!retargetedHandoff)
    #expect(session.pose(at: 0.15).eyes == middle.eyes)
    #expect(session.inspect(at: 0.15).state == almostComplete)

    let settled = session.pose(at: 0.35)
    let expected = ReactiveCharacter.pose(state: almostComplete, elapsed: 0.35)
    #expect(settled.eyes == expected.eyes)
    #expect(settled.writingMotionPhase == expected.writingMotionPhase)
  }

  @Test
  func explicitFocusOwnsGazeDuringProgressUpdates() throws {
    let taskID = try CharacterTaskID(validating: "focused-progress")
    let point = try CharacterPoint(validatingX: 0.05, y: 0.5)
    let writing = state([
      .agentStarted(taskID: taskID),
      .agentProgress(taskID: taskID, progress: 0.1),
    ])
    let focused = ReactiveCharacter.reduce(
      state: writing, event: .attentionFocused(point)
    ).state
    var session = CharacterPresentationSession(state: writing, at: 0)
    let startedFocus = session.update(state: focused, at: 0.1)
    #expect(!startedFocus)
    let before = session.inspect(at: 0.12)

    let progressReceipt = ReactiveCharacter.act(
      state: focused, event: .agentProgress(taskID: taskID, progress: 0.9)
    )
    #expect(progressReceipt.presentation == .unchanged)
    let progressHandoff = session.update(state: progressReceipt.stateAfter, at: 0.12)
    #expect(!progressHandoff)
    let after = session.inspect(at: 0.12)

    #expect(after.state == progressReceipt.stateAfter)
    #expect(after.phase == before.phase)
    #expect(after.remainingHandoffDuration == before.remainingHandoffDuration)
  }

  @Test
  func reduceMotionAppliesVoiceAndProgressTargetsImmediately() throws {
    let quiet = state([.voiceStarted])
    let loud = ReactiveCharacter.reduce(
      state: quiet, event: .voiceLevelChanged(1)
    ).state
    var voiceSession = CharacterPresentationSession(state: quiet, at: 0)
    let voiceHandoff = voiceSession.update(state: loud, at: 0.1, reduceMotion: true)
    #expect(!voiceHandoff)
    let voicePose = voiceSession.pose(at: 0.1, reduceMotion: true)
    let expectedVoice = ReactiveCharacter.pose(state: loud, elapsed: 0.1, reduceMotion: true)
    #expect(voicePose.mouth == expectedVoice.mouth)

    let taskID = try CharacterTaskID(validating: "reduced-progress")
    let writing = state([
      .agentStarted(taskID: taskID),
      .agentProgress(taskID: taskID, progress: 0.1),
    ])
    let complete = ReactiveCharacter.reduce(
      state: writing, event: .agentProgress(taskID: taskID, progress: 0.9)
    ).state
    var progressSession = CharacterPresentationSession(state: writing, at: 0)
    let progressHandoff = progressSession.update(state: complete, at: 0.1, reduceMotion: true)
    #expect(!progressHandoff)
    let progressPose = progressSession.pose(at: 0.1, reduceMotion: true)
    let expectedProgress = ReactiveCharacter.pose(
      state: complete, elapsed: 0.1, reduceMotion: true)
    #expect(progressPose.eyes == expectedProgress.eyes)
  }

  @Test
  func performanceHandoffCapturesCurrentVoiceLevelThenUsesLatestState() {
    let quiet = state([.voiceStarted])
    var session = CharacterPresentationSession(state: quiet, at: 0)
    let loud = ReactiveCharacter.reduce(
      state: quiet, event: .voiceLevelChanged(1)
    ).state
    let voiceHandoff = session.update(state: loud, at: 0)
    #expect(!voiceHandoff)

    let currentlyPresented = session.pose(at: 0.05)
    let medium = ReactiveCharacter.reduce(
      state: loud, event: .voiceLevelChanged(0.4)
    ).state
    let taskID = CharacterTaskID(UUID())
    let newPerformance = ReactiveCharacter.reduce(
      state: medium, event: .agentStarted(taskID: taskID)
    ).state

    let performanceHandoff = session.update(state: newPerformance, at: 0.05)
    #expect(performanceHandoff)
    #expect(session.pose(at: 0.05).mouth == currentlyPresented.mouth)
    #expect(session.inspect(at: 0.05).state == newPerformance)

    let settled = session.pose(at: 1.0)
    #expect(abs(settled.mouth.openness - (0.10 + 0.4 * 0.78)) < 1e-12)
  }

  @Test
  func listeningLevelDoesNotMoveTheFaceInTheCurrentPresentationContract() {
    let listening = state([.listeningStarted])
    var session = CharacterPresentationSession(state: listening, at: 0)
    let before = session.pose(at: 0.42)
    let louder = ReactiveCharacter.reduce(
      state: listening, event: .listeningLevelChanged(1)
    ).state

    let handoff = session.update(state: louder, at: 0.42)
    #expect(!handoff)
    #expect(session.inspect(at: 0.42).state == louder)
    #expect(session.pose(at: 0.42) == before)
  }
}

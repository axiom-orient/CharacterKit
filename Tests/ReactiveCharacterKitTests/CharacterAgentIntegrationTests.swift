import Foundation
import ReactiveCharacterKit
import XCTest

final class CharacterAgentIntegrationTests: XCTestCase {
  func testEffectPlanReplacementResetAndStaleCallbacks() throws {
    let a = try CharacterAnimationID(validating: "a")
    let b = try CharacterAnimationID(validating: "b")
    let first = ReactiveCharacter.act(
      state: .idle, event: .animationStarted(id: a, animation: .nod))
    let next = ReactiveCharacter.act(
      state: first.stateAfter, event: .animationStarted(id: b, animation: .blink))
    let plan = next.effectPlan(scheduledAnimationIDs: [b, a, a])
    XCTAssertEqual(plan.animationIDsToCancel, [a])
    XCTAssertEqual(plan.effects, next.effects)
    let stale = ReactiveCharacter.act(state: next.stateAfter, event: .animationEnded(id: a))
    XCTAssertEqual(stale.effectPlan(scheduledAnimationIDs: [b, a]).animationIDsToCancel, [a])
    XCTAssertTrue(stale.effects.isEmpty)
    let reset = ReactiveCharacter.act(state: next.stateAfter, event: .reset)
    XCTAssertEqual(
      reset.effectPlan(scheduledAnimationIDs: [b, a, b]).animationIDsToCancel, [a, b])
    XCTAssertTrue(reset.effectPlan(scheduledAnimationIDs: [CharacterAnimationID]()).effects.isEmpty)
    let idle = ReactiveCharacter.act(state: .idle, event: .reset).effectPlan(
      scheduledAnimationIDs: [CharacterAnimationID]())
    XCTAssertTrue(idle.animationIDsToCancel.isEmpty)
    let task = try CharacterTaskID(validating: "task")
    let running = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: task))
    let cancelled = ReactiveCharacter.act(state: running.stateAfter, event: .reset)
    XCTAssertEqual(
      cancelled.effectPlan(scheduledAnimationIDs: [a]).effects, [.cancelAgent(taskID: task)])
  }

  func testDiagnosticCodesAndNonfiniteEncoding() throws {
    let task = try CharacterTaskID(validating: "task")
    let other = try CharacterTaskID(validating: "other")
    let a = try CharacterAnimationID(validating: "a")
    let b = try CharacterAnimationID(validating: "b")
    let cases: [(CharacterDisposition, String)] = [
      (.accepted, "accepted"), (.ignored(.duplicate), "duplicate"),
      (.ignored(.staleTask(expected: task, received: other)), "stale_task"),
      (.ignored(.noActiveTask(received: task)), "no_active_task"),
      (.ignored(.staleAnimation(expected: a, received: b)), "stale_animation"),
      (.ignored(.noActiveAnimation(received: a)), "no_active_animation"),
      (.ignored(.eventNotApplicable), "event_not_applicable"),
      (.rejected(.emptyTaskID), "empty_task_id"),
      (.rejected(.emptyAnimationID), "empty_animation_id"),
      (.rejected(.animationIdentityConflict(id: a)), "animation_identity_conflict"),
      (.rejected(.emptyFailureField(field: "cause")), "empty_failure_field"),
      (.rejected(.nonFiniteValue(field: "voiceLevel", value: .infinity)), "non_finite_value"),
      (.rejected(.outOfRange(field: "progress", value: 2)), "out_of_range"),
      (.rejected(.progressRegressed(previous: 0.8, received: 0.2)), "progress_regressed"),
    ]
    for (disposition, code) in cases {
      let observation = disposition.diagnostic
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any])
      XCTAssertEqual(json["schema"] as? String, "characterkit.action-diagnostic/1")
      XCTAssertEqual(json["code"] as? String, code)
      XCTAssertFalse(observation.message.isEmpty)
    }
    XCTAssertEqual(
      CharacterDisposition.ignored(.staleTask(expected: task, received: other)).diagnostic.details,
      ["expected": "task", "received": "other"])
  }

  func testMotionReplacementPreservesCompleteArtDirection() throws {
    let original = try CharacterArtDirection(
      name: "Custom", components: .all, layout: .standard,
      style: .black, surface: .transparent, projection: .flat, motionProfile: .soft,
      transitionProfile: .cartoon, assets: .arcade, featureGlow: 0.7,
      ornamentGlow: 0.3, contentInset: 0.12)
    let replaced = original.replacingMotionProfile(.companion)
    XCTAssertEqual(replaced.motionProfile, .companion)
    XCTAssertEqual(replaced.replacingMotionProfile(.soft), original)
    XCTAssertEqual(original.motionProfile, .soft)
  }
}

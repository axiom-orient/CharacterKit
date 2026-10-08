import Foundation
import ReactiveCharacterKit
import XCTest

final class CharacterAgentIntegrationTests: XCTestCase {
  func testEffectPlanReplacementResetAndStaleCallbacks() throws {
    let a = try CharacterAnimationID(validating: "a")
    let b = try CharacterAnimationID(validating: "b")
    let first = ReactiveCharacter.act(state: .idle, event: .animationStarted(id: a, animation: .nod))
    let next = ReactiveCharacter.act(
      state: first.stateAfter, event: .animationStarted(id: b, animation: .blink)
    )
    let plan = next.effectPlan(scheduledAnimationIDs: [b, a, a])
    XCTAssertEqual(plan.animationIDsToCancel, [a])
    XCTAssertEqual(plan.effects, next.effects)

    let stale = ReactiveCharacter.act(state: next.stateAfter, event: .animationEnded(id: a))
    XCTAssertEqual(stale.stateAfter, next.stateAfter)
    XCTAssertEqual(stale.disposition, .ignored(.staleAnimation(expected: b, received: a)))
    XCTAssertEqual(stale.effectPlan(scheduledAnimationIDs: [b, a]).animationIDsToCancel, [a])
    XCTAssertTrue(stale.effects.isEmpty)

    let reset = ReactiveCharacter.act(state: next.stateAfter, event: .reset)
    XCTAssertEqual(reset.effectPlan(scheduledAnimationIDs: [b, a, b]).animationIDsToCancel, [a, b])
    let afterReset = ReactiveCharacter.act(state: reset.stateAfter, event: .animationEnded(id: b))
    XCTAssertEqual(afterReset.stateAfter, .idle)
    XCTAssertEqual(afterReset.disposition, .ignored(.noActiveAnimation(received: b)))
    XCTAssertTrue(afterReset.effects.isEmpty)
    let idlePlan = ReactiveCharacter.act(state: .idle, event: .reset).effectPlan(
      scheduledAnimationIDs: [CharacterAnimationID]()
    )
    XCTAssertTrue(idlePlan.animationIDsToCancel.isEmpty)
    XCTAssertTrue(idlePlan.effects.isEmpty)
  }

  func testTaskReplacementCancelsPriorTaskAndRejectsItsCompletion() throws {
    let a = try CharacterTaskID(validating: "task-a")
    let b = try CharacterTaskID(validating: "task-b")
    let first = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: a))
    let replacement = ReactiveCharacter.act(state: first.stateAfter, event: .agentStarted(taskID: b))
    XCTAssertEqual(replacement.effects, [.cancelAgent(taskID: a)])
    for staleEvent in [CharacterEvent.agentSucceeded(taskID: a), .agentCancelled(taskID: a)] {
      let stale = ReactiveCharacter.act(state: replacement.stateAfter, event: staleEvent)
      XCTAssertEqual(stale.stateAfter, replacement.stateAfter)
      XCTAssertEqual(stale.disposition, .ignored(.staleTask(expected: b, received: a)))
      XCTAssertTrue(stale.effects.isEmpty)
    }
    let reset = ReactiveCharacter.act(state: replacement.stateAfter, event: .reset)
    XCTAssertEqual(reset.stateAfter, .idle)
    XCTAssertEqual(reset.effects, [.cancelAgent(taskID: b)])
  }

  func testCancellationRemainsPendingUntilExplicitResult() throws {
    let task = try CharacterTaskID(validating: "cancel-task")
    let running = ReactiveCharacter.act(state: .idle, event: .agentStarted(taskID: task))
    let pending = ReactiveCharacter.act(
      state: running.stateAfter, event: .agentCancellationRequested(taskID: task)
    )
    XCTAssertEqual(pending.stateAfter.activity, .agentCancelling(taskID: task))
    XCTAssertEqual(pending.effects, [.cancelAgent(taskID: task)])
    XCTAssertFalse(ReactiveCharacter.inspect(state: pending.stateAfter).canCancelTask)
    let duplicate = ReactiveCharacter.act(
      state: pending.stateAfter, event: .agentCancellationRequested(taskID: task)
    )
    XCTAssertEqual(duplicate.disposition, .ignored(.duplicate))
    XCTAssertEqual(duplicate.stateAfter, pending.stateAfter)
    XCTAssertTrue(duplicate.effects.isEmpty)
    let completed = ReactiveCharacter.act(state: pending.stateAfter, event: .agentCancelled(taskID: task))
    XCTAssertEqual(completed.stateAfter.activity, .cancelled(taskID: task))
    XCTAssertTrue(completed.effects.isEmpty)
  }

  func testAnimationIdentityConflictDoesNotReplacePerformanceOrScheduleWork() throws {
    let id = try CharacterAnimationID(validating: "one-performance")
    let initial = ReactiveCharacter.act(state: .idle, event: .animationStarted(id: id, animation: .nod))
    let conflict = ReactiveCharacter.act(
      state: initial.stateAfter, event: .animationStarted(id: id, animation: .bounce)
    )
    XCTAssertEqual(conflict.disposition, .rejected(.animationIdentityConflict(id: id)))
    XCTAssertEqual(conflict.stateAfter, initial.stateAfter)
    XCTAssertTrue(conflict.effects.isEmpty)
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
      (.rejected(.nonFiniteValue(field: "voiceLevel", value: .nan)), "non_finite_value"),
      (.rejected(.outOfRange(field: "progress", value: 2)), "out_of_range"),
      (.rejected(.progressRegressed(previous: 0.8, received: 0.2)), "progress_regressed"),
    ]
    for (disposition, code) in cases {
      let diagnostic = disposition.diagnostic
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(diagnostic)) as? [String: Any]
      )
      XCTAssertEqual(json["schema"] as? String, "characterkit.action-diagnostic/1")
      XCTAssertEqual(json["code"] as? String, code)
      XCTAssertFalse(diagnostic.message.isEmpty)
    }
    XCTAssertEqual(
      CharacterDisposition.ignored(.staleTask(expected: task, received: other)).diagnostic.details,
      ["expected": "task", "received": "other"]
    )
  }
}

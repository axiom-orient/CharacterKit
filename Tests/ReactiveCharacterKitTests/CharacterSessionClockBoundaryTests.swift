import ReactiveCharacterKit
import Testing

struct CharacterSessionClockBoundaryTests {
  @Test(arguments: [false, true])
  func finiteReanchorsStayFiniteForCommunicationAndAnimation(
    reduceMotion: Bool
  ) throws {
    let communicationState = ReactiveCharacter.reduce(
      state: .idle, event: .voiceStarted
    ).state
    let animationID = try CharacterAnimationID(validating: "clock-boundary-animation")
    let animationState = ReactiveCharacter.reduce(
      state: communicationState,
      event: .animationStarted(id: animationID, animation: .nod)
    ).state

    #expect(communicationState.visualChannel == .communication)
    #expect(animationState.visualChannel == .animation)

    let latestFiniteTime = Double.greatestFiniteMagnitude
    for state in [communicationState, animationState] {
      var session = CharacterPresentationSession(state: state)
      session.update(state: state, at: latestFiniteTime, reduceMotion: reduceMotion)

      // Re-anchor forward, backward, then forward again. Every supplied sample remains finite;
      // accumulated elapsed time must saturate before it reaches the pose sampler.
      session.reconcilePresentationConfigurationChange(at: 0)
      session.reconcilePresentationConfigurationChange(at: latestFiniteTime)
      session.reconcilePresentationConfigurationChange(at: 0)

      for time in [0.0, latestFiniteTime, latestFiniteTime] {
        let pose = session.pose(at: time, reduceMotion: reduceMotion)
        let finiteValues = [
          pose.surface.offsetX, pose.surface.offsetY, pose.surface.scaleX,
          pose.surface.scaleY, pose.surface.angle,
          pose.eyes.left.centerX, pose.eyes.left.centerY,
          pose.eyes.left.width, pose.eyes.left.height,
          pose.eyes.right.centerX, pose.eyes.right.centerY,
          pose.eyes.right.width, pose.eyes.right.height,
          pose.mouth.opacity, pose.mouth.curvature, pose.mouth.openness,
        ]
        #expect(finiteValues.allSatisfy { $0.isFinite })

        let scene = try CharacterSceneBuilder.scene(
          pose: pose, artDirection: .black, width: 160, height: 160)
        #expect(!scene.nodes.isEmpty)
        #expect(session.inspect(at: time).state == state)
      }
    }
  }

  @Test
  func ordinaryElapsedArithmeticMatchesDirectSamplingAfterReanchors() {
    let state = ReactiveCharacter.reduce(
      state: .idle, event: .voiceStarted
    ).state
    var session = CharacterPresentationSession(state: state, at: 0)

    session.reconcilePresentationConfigurationChange(at: 0.25)
    session.reconcilePresentationConfigurationChange(at: 0.75)
    session.reconcilePresentationConfigurationChange(at: 1.10)

    let actual = session.pose(at: 2.77)
    let expected = ReactiveCharacter.pose(state: state, elapsed: 2.77)
    #expect(abs(actual.eyes.left.centerX - expected.eyes.left.centerX) < 1e-12)
    #expect(abs(actual.eyes.left.centerY - expected.eyes.left.centerY) < 1e-12)
    #expect(abs(actual.eyes.right.centerX - expected.eyes.right.centerX) < 1e-12)
    #expect(abs(actual.eyes.right.centerY - expected.eyes.right.centerY) < 1e-12)
    #expect(abs(actual.mouth.openness - expected.mouth.openness) < 1e-12)
  }
}

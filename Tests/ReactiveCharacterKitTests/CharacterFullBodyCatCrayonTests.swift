import Testing
@testable import ReactiveCharacterKit

struct CharacterFullBodyCatCrayonTests {
  @Test
  func expressionSeparatesBrowsAndClosedLipsFromSpeechArticulation() throws {
    let cat = CharacterFullBodyCatAppearance(style: .crayon)
    let neutral = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let surprisedState = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    let surprised = ReactiveCharacter.pose(state: surprisedState, elapsed: 0, reduceMotion: true, projection: .flat)
    func features(_ face: CharacterPose) throws -> [String: CharacterSceneNode] {
      let scene = try CharacterSceneBuilder.scene(
        pose: face, fullBodyCat: cat, width: 256, height: 256, reduceMotion: true)
      return Dictionary(uniqueKeysWithValues: scene.nodes.filter { $0.layer == .features }.map { ($0.id, $0) })
    }
    let rest = try features(neutral)
    let emotion = try features(surprised)
    let speech = try features(surprised.applyingSpeechArticulation(.init(openness: 0.72, width: 0.92)))
    #expect(rest["full-body-cat.mouth"]?.fill == nil)
    #expect(emotion["full-body-cat.mouth"]?.fill != nil)
    #expect(speech["full-body-cat.mouth"]?.path != emotion["full-body-cat.mouth"]?.path)
    for side in ["left", "right"] {
      let eye = "full-body-cat.eye.\(side)"
      let brow = "full-body-cat.brow.\(side)"
      #expect(rest[brow] == nil && emotion[brow] != nil)
      #expect(speech[eye] == emotion[eye] && speech[brow] == emotion[brow])
    }
  }

  @Test(arguments: CharacterFullBodyCatAction.allCases)
  func sharedGesturesLeaveAndReturnToTheDrawnRest(_ action: CharacterFullBodyCatAction) throws {
    let appearance = CharacterFullBodyCatAppearance(
      pose: .loaf, action: action, style: .crayon, walkDirection: .right, puffDirection: .right)
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0.32, reduceMotion: false, projection: .flat)
    func motion(_ phase: Double) -> CharacterFullBodyCatMotion {
      .sample(appearance: appearance, elapsed: 0.32, actionElapsed: action.duration * phase, reduceMotion: false)
    }
    func scene(_ phase: Double) throws -> CharacterScene {
      try CharacterSceneBuilder.scene(pose: pose, fullBodyCat: appearance, motion: motion(phase),
        width: 256, height: 256, environment: .init())
    }
    let start = try scene(0)
    #expect(start == (try scene(1)))
    for phase in [0.05, 0.12, 0.24, 0.45, 0.69, 0.87, 0.95] {
      let frame = try scene(phase)
      #expect(frame.nodes.allSatisfy { $0.image == nil })
      #expect(frame.nodes.contains { $0.id == "full-body-cat.nose" })
      let torso = try #require(frame.nodes.first { $0.id == "full-body-cat.body" })
      let grain = try #require(frame.nodes.first { $0.id == "full-body-cat.wax.body" })
      #expect(grain.clips == [torso.path])
      #expect(grain.transform == torso.transform)
      let head = try #require(frame.nodes.first { $0.id == "full-body-cat.head" })
      let headGrain = try #require(frame.nodes.first { $0.id == "full-body-cat.wax.head" })
      #expect(headGrain.clips == [head.path])
      #expect(headGrain.transform == head.transform)
    }
    #expect(motion(0.12).crayonStances.count == 2)
    #expect(motion(0.87).crayonStances.count == 2)
    #expect(motion(0.12).transition == nil)
  }

  @Test
  func crayonGesturesSeparateGroundedAnticipationFromTheAction() {
    func sample(_ action: CharacterFullBodyCatAction, at phase: Double) -> CharacterFullBodyCatMotion {
      .sample(appearance: .init(action: action, style: .crayon), elapsed: 0,
        actionElapsed: action.duration * phase, reduceMotion: false)
    }

    let crouch = sample(.hop, at: 0.15)
    let airborne = sample(.hop, at: 0.49)
    let landing = sample(.hop, at: 0.80)
    #expect(crouch.breath < -0.10 && crouch.bodyOffsetY == 0)
    #expect(airborne.bodyOffsetY < -0.14 && airborne.pawTuck > 1)
    #expect(landing.breath < -0.08 && landing.bodyOffsetY == 0 && landing.pawTuck == 0)

    let brace = sample(.stretch, at: 0.10)
    let reach = sample(.stretch, at: 0.42)
    #expect(brace.bodyOffsetX > 0 && brace.bodyWidth < 0)
    #expect(reach.bodyOffsetX < -0.025 && reach.bodyWidth > 0.07 && reach.bodyOffsetY == 0)

    let tip = sample(.showBelly, at: 0.24)
    let settle = sample(.showBelly, at: 0.38)
    let rock = sample(.showBelly, at: 0.44)
    #expect(tip.bodyAngle < -0.12 && tip.bodyOffsetY == 0)
    #expect(settle.breath < -0.05 && settle.bodyOffsetY == 0)
    #expect(rock.bodyAngle > 0.065 && rock.bodyOffsetY == 0)
  }

  @Test(arguments: [CharacterFullBodyCatWalkDirection.left, .right])
  func turningToWalkOccludesTheFarEyeBeforeTheEyesMeet(_ direction: CharacterFullBodyCatWalkDirection) throws {
    let cat = CharacterFullBodyCatAppearance(action: .walk, style: .crayon, walkDirection: direction)
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    func eye(_ side: String, at time: Double) throws -> Double? {
      let frame = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: cat,
        width: 256, height: 256, elapsed: 0, actionElapsed: time)
      return frame.nodes.first { $0.id == "full-body-cat.eye." + side }?.opacity
    }
    let (near, far) = direction == .left ? ("right", "left") : ("left", "right")
    #expect(try eye(far, at: 0) == 1)
    #expect(try eye(far, at: 0.24) == 0)
    #expect(try eye(near, at: 0.24) == 1)
    #expect(try eye(far, at: 0.50) == nil)
  }

  @Test
  func replacingTheRestingPoseDoesNotReenterARepeatedWalkCue() throws {
    let walking = CharacterFullBodyCatAppearance(
      pose: .standing, action: .walk, actionTrigger: 31, style: .crayon, walkDirection: .right)
    let resting = CharacterFullBodyCatAppearance(
      pose: .loaf, action: .walk, actionTrigger: 31, style: .crayon, walkDirection: .right)
    var playback = CharacterFullBodyCatPlayback(appearance: walking, at: 0)
    let visible = playback.sample(appearance: walking, at: 0.50, reduceMotion: false)
    #expect(visible.walkStrength > 0.75)

    playback.update(appearance: resting, at: 0.50)
    #expect(playback.sample(appearance: resting, at: 0.50, reduceMotion: false) == visible)
    let settling = playback.sample(appearance: resting, at: 0.79, reduceMotion: false)
    #expect(settling.crayonStances.contains { $0.stance.pose == .loaf && $0.weight > 0.99 })
    let settled = playback.sample(appearance: resting, at: 0.81, reduceMotion: false)
    #expect(settled.pose == .loaf)
    #expect(settled.walkPhase == nil)
    #expect(playback.sample(appearance: resting, at: 0.81, reduceMotion: true).pose == .loaf)
  }

  @Test(arguments: [CharacterFullBodyCatFacing.left, .right])
  func groundedCrayonStartleShiversAndReleasesFromTheVisibleFrame(_ facing: CharacterFullBodyCatFacing) {
    let cue = CharacterFullBodyCatAppearance(pose: .puffed, action: .startle, style: .crayon, puffDirection: facing)
    let rest = CharacterFullBodyCatAppearance(pose: .puffed, style: .crayon, puffDirection: facing)
    var playback = CharacterFullBodyCatPlayback(appearance: cue, at: 0)
    let samples = (0...72).map {
      playback.sample(appearance: cue, at: Double($0) / 60, reduceMotion: false)
    }
    #expect(samples.allSatisfy { $0.bodyOffsetY == 0 && $0.bodyAngle == 0 })
    #expect(samples.contains { $0.bristleSway > 0.025 })
    #expect(samples.contains { $0.bristleSway < -0.025 })
    #expect(samples.last?.bristleSway == 0)

    let visible = playback.sample(appearance: cue, at: 0.25, reduceMotion: false)
    #expect((facing == .left ? 1 : -1) * visible.bristleSway > 0.03)
    playback.update(appearance: rest, at: 0.25)
    #expect(playback.sample(appearance: rest, at: 0.25, reduceMotion: false) == visible)
    let settling = playback.sample(appearance: rest, at: 0.40, reduceMotion: false)
    #expect(abs(settling.bristleSway) < abs(visible.bristleSway))
    #expect(playback.sample(appearance: rest, at: 0.56, reduceMotion: false).bristleSway == 0)
  }

  @Test
  func replacingAPoseAndAnInFlightGestureContinuesFromTheVisibleDrawing() throws {
    let loaf = CharacterFullBodyCatAppearance(pose: .loaf, action: .hop, style: .crayon)
    let belly = CharacterFullBodyCatAppearance(pose: .bellyUp, style: .crayon)
    let wave = CharacterFullBodyCatAppearance(pose: .standing, action: .wave, style: .crayon)
    var playback = CharacterFullBodyCatPlayback(appearance: loaf, at: 0)
    let inFlight = playback.sample(appearance: loaf, at: 0.46, reduceMotion: false)
    #expect(inFlight.bodyOffsetY < 0)
    playback.update(appearance: belly, at: 0.46)
    #expect(playback.sample(appearance: belly, at: 0.46, reduceMotion: false) == inFlight)
    let rolling = playback.sample(appearance: belly, at: 0.58, reduceMotion: false)
    #expect(rolling.crayonStances.count == 2)
    playback.update(appearance: wave, at: 0.58)
    #expect(playback.sample(appearance: wave, at: 0.58, reduceMotion: false) == rolling)
    let waveEntry = playback.sample(appearance: wave, at: 1.01, reduceMotion: false)
    #expect(waveEntry.crayonStances.map(\.stance.pose) == [.standing, .waving])
    #expect(playback.sample(appearance: wave, at: 1.02, reduceMotion: true).crayonStances.isEmpty)
  }
}

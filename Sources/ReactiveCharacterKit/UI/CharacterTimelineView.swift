#if os(iOS) || os(macOS)
  import SwiftUI

  @available(iOS 16.0, macOS 13.0, *)
  private enum CharacterPresentationTime {
    private static let clock = ContinuousClock()
    private static let origin = clock.now

    static var now: Double {
      let components = origin.duration(to: clock.now).components
      return Double(components.seconds)
        + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  struct CharacterTimelineView: View {
    private struct SessionInput: Equatable {
      let state: CharacterState
      let reduceMotion: Bool
    }

    let state: CharacterState

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.characterReducedMotion) private var hostReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: CharacterPresentationSession

    private var reduceMotion: Bool { systemReduceMotion || hostReduceMotion }
    private var sessionInput: SessionInput { .init(state: state, reduceMotion: reduceMotion) }

    init(state: CharacterState) {
      self.state = state
      _presentation = State(
        initialValue: CharacterPresentationSession(state: state, at: CharacterPresentationTime.now)
      )
    }

    var body: some View {
      Group {
        if reduceMotion {
          frame(reduceMotion: true)
        } else {
          TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { _ in
            frame(reduceMotion: false)
          }
        }
      }
      .onChange(of: sessionInput) { input in
        presentation.update(
          state: input.state,
          at: CharacterPresentationTime.now,
          reduceMotion: input.reduceMotion
        )
      }
    }

    @ViewBuilder
    private func frame(reduceMotion: Bool) -> some View {
      let pose = presentation.pose(at: CharacterPresentationTime.now, reduceMotion: reduceMotion)
      GeometryReader { geometry in
        if geometry.size.width >= 1, geometry.size.height >= 1 {
          let result = Result {
            try CharacterSceneBuilder.scene(
              pose: pose,
              width: geometry.size.width,
              height: geometry.size.height
            )
          }
          switch result {
          case .success(let scene):
            CharacterSceneCanvas(scene: scene)
              .accessibilityValue(
                Text(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene))
              )
          case .failure(let error):
            Text("Character rendering failed: \(String(describing: error))")
              .font(.caption)
              .accessibilityIdentifier("character.render.error")
          }
        }
      }
    }
  }
#endif

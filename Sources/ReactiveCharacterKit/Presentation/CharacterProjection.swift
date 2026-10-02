/// Eye projection policy.
/// `softSphere` keeps the renderer two-dimensional but applies deterministic edge
/// foreshortening: the eye closer to the circular rim becomes narrower and slightly
/// smaller, while centered gaze remains symmetric.
public enum CharacterProjection: Sendable, Equatable {
  case flat
  case softSphere
}

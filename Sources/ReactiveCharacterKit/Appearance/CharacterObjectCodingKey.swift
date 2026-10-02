import Foundation

/// Captures every string member name; callers retain their distinct allowed/exact-key policies.
struct CharacterObjectCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

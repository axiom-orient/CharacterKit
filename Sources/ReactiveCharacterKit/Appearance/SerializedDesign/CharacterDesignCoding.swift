import Foundation

extension Decoder {
  /// Unknown keys are errors, including nested profile objects. A typo must not
  /// silently leave a previous/default appearance in effect.
  func characterDesignContainer<Key: CodingKey & CaseIterable>(
    keyedBy type: Key.Type
  ) throws -> KeyedDecodingContainer<Key> {
    let raw = try container(keyedBy: CharacterObjectCodingKey.self)
    let allowed = Set(Key.allCases.map(\.stringValue))
    if let unknown = raw.allKeys.sorted(by: { $0.stringValue < $1.stringValue })
      .first(where: { !allowed.contains($0.stringValue) })
    {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [unknown],
          debugDescription: "Unknown design field: \(unknown.stringValue)"
        ))
    }
    return try container(keyedBy: type)
  }
}

extension CharacterAccessoryAnchor: Codable {}
extension CharacterAccessoryLayer: Codable {}

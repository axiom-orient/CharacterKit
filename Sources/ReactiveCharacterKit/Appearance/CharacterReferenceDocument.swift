import Foundation

public enum CharacterReferenceDocumentError: Error, Sendable, Equatable {
  case unsupportedSchema(String)
  case inputTooLarge(bytes: Int, maximum: Int)
}

/// Portable appearance input/output. The host owns storage and file permissions.
public struct CharacterReferenceDocument: Sendable, Equatable, Codable {
  public static let schema = "character-reference/1"
  public static let maximumInputBytes = 16_384
  public let appearance: CharacterReferenceAppearance

  public init(appearance: CharacterReferenceAppearance) { self.appearance = appearance }

  public init(data: Data) throws {
    guard data.count <= Self.maximumInputBytes else {
      throw CharacterReferenceDocumentError.inputTooLarge(
        bytes: data.count, maximum: Self.maximumInputBytes)
    }
    do {
      try CharacterJSONStructure.check(data)
    } catch let violation as CharacterJSONStructure.Violation {
      throw DecodingError.dataCorrupted(.init(
        codingPath: [], debugDescription: "\(violation.path): \(violation.reason)"))
    }
    self = try JSONDecoder().decode(Self.self, from: data)
  }

  public func data() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return try encoder.encode(self)
  }

  private enum Key: String, CodingKey { case schema, appearance }

  public init(from decoder: any Decoder) throws {
    try Self.requireKeys(["schema", "appearance"], decoder: decoder)
    let container = try decoder.container(keyedBy: Key.self)
    let schema = try container.decode(String.self, forKey: .schema)
    guard schema == Self.schema else {
      throw CharacterReferenceDocumentError.unsupportedSchema(schema)
    }
    appearance = try container.decode(CharacterReferenceAppearance.self, forKey: .appearance)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(Self.schema, forKey: .schema)
    try container.encode(appearance, forKey: .appearance)
  }

  static func requireKeys(_ keys: Set<String>, decoder: any Decoder) throws {
    let actual = Set(try decoder.container(keyedBy: CharacterObjectCodingKey.self).allKeys.map(\.stringValue))
    guard actual == keys else {
      throw DecodingError.dataCorrupted(.init(
        codingPath: decoder.codingPath,
        debugDescription: "Expected fields \(keys.sorted()); received \(actual.sorted())"))
    }
  }
}

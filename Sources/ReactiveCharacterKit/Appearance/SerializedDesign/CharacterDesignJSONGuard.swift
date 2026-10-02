import Foundation

/// Design owns its error contract; shared raw structure checking owns no schema or state.
enum CharacterDesignJSONGuard {
  static func check(_ data: Data) throws {
    do {
      try CharacterJSONStructure.check(data)
    } catch let violation as CharacterJSONStructure.Violation {
      throw CharacterDesignError.invalid(path: violation.path, reason: violation.reason)
    }
  }
}

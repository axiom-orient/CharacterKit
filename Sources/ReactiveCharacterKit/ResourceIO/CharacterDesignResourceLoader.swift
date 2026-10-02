import Foundation

/// Package-resource adapter for built-in designs. Decoding and validation remain pure in
/// `CharacterDesign`; missing resources retain the design-specific error contract.
enum CharacterDesignResourceLoader {
  static func data(for preset: CharacterDesignPreset) throws -> Data {
    let url: URL
    do {
      url = try CharacterPackageResource.url(named: "design-\(preset.rawValue)", fileExtension: "json")
    } catch {
      throw CharacterDesignError.resourceNotFound(preset.rawValue)
    }
    // Keep read errors distinct from a resource lookup failure.
    return try Data(contentsOf: url)
  }
}

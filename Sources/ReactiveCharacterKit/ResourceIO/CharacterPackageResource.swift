import Foundation

public enum CharacterPackageResourceError: Error, Sendable, Equatable {
  case unavailable(name: String, fileExtension: String)
  case invalidTextEncoding(name: String, fileExtension: String)
}

/// Single confined resolver for CharacterKit-owned package resources.
enum CharacterPackageResource {
  // The black, white and graphite variants use byte-identical eye and mouth masks.
  private static let referenceFeaturePNGAliases = Dictionary(uniqueKeysWithValues:
    ["hero", "bare", "white", "black", "arcade"].flatMap { variant in
      ["eye-left", "eye-right", "mouth"].flatMap { feature in
        let stem = "reference-mascot-\(variant)-\(feature)"
        return ["white", "graphite"].map { ("\(stem)-\($0)", "\(stem)-black") }
      }
    })

  static func pngName(_ name: String) -> String {
    referenceFeaturePNGAliases[name] ?? name
  }

  static func url(named name: String, fileExtension: String) throws -> URL {
    let storedName = fileExtension == "png" ? pngName(name) : name
    guard
      let url = Bundle.module.url(forResource: storedName, withExtension: fileExtension),
      let resourceRoot = Bundle.module.resourceURL,
      url.standardizedFileURL.path.hasPrefix(resourceRoot.standardizedFileURL.path + "/")
    else {
      throw CharacterPackageResourceError.unavailable(name: name, fileExtension: fileExtension)
    }
    return url
  }

  static func data(named name: String, fileExtension: String) throws -> Data {
    try Data(contentsOf: url(named: name, fileExtension: fileExtension))
  }

  static func string(named name: String, fileExtension: String) throws -> String {
    let bytes = try data(named: name, fileExtension: fileExtension)
    guard let text = String(data: bytes, encoding: .utf8) else {
      throw CharacterPackageResourceError.invalidTextEncoding(name: name, fileExtension: fileExtension)
    }
    return text
  }

}

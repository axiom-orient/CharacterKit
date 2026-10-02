import Foundation

public enum CharacterPackageResourceError: Error, Sendable, Equatable {
  case unavailable(name: String, fileExtension: String)
  case invalidTextEncoding(name: String, fileExtension: String)
}

/// Single confined resolver for CharacterKit-owned package resources.
enum CharacterPackageResource {
  static func url(named name: String, fileExtension: String) throws -> URL {
    guard
      let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
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

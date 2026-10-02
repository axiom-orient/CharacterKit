import Foundation

extension CharacterCatSupplementalAsset {
  public func packageURL(for representation: Representation) throws -> URL {
    try CharacterPackageResource.url(
      named: rawValue, fileExtension: representation.rawValue)
  }

  public func data(for representation: Representation) throws -> Data {
    try CharacterPackageResource.data(
      named: rawValue, fileExtension: representation.rawValue)
  }

  public func svgString() throws -> String {
    try CharacterPackageResource.string(named: rawValue, fileExtension: Representation.svg.rawValue)
  }
}

extension CharacterPawVariant {
  public func packageURL(for representation: Representation) throws -> URL {
    try CharacterPackageResource.url(named: resourceName, fileExtension: representation.rawValue)
  }

  public func data(for representation: Representation) throws -> Data {
    try CharacterPackageResource.data(named: resourceName, fileExtension: representation.rawValue)
  }

  public func svgString() throws -> String {
    try CharacterPackageResource.string(named: resourceName, fileExtension: "svg")
  }
}

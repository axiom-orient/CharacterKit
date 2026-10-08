import Foundation

public enum CharacterImageResolutionError: Error, Sendable, Equatable {
  case unavailable(name: String)
  case invalidPNG(name: String)
}

enum CharacterImageResources {
  private static let bundled: [String: Result<Data, CharacterImageResolutionError>] = Dictionary(
    uniqueKeysWithValues: CharacterSEMIStyle.assets.map { asset in
      (asset.name, readPackage(asset))
    })

  static func png(_ asset: CharacterImageAsset) throws -> Data {
    try (bundled[asset.name] ?? readPackage(asset)).get()
  }

  private static func readPackage(_ asset: CharacterImageAsset) -> Result<Data, CharacterImageResolutionError> {
    do {
      let data = try CharacterPackageResource.data(named: asset.name, fileExtension: "png")
      guard data.count >= 24, Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
        return .failure(.invalidPNG(name: asset.name))
      }
      return .success(data)
    } catch {
      return .failure(.unavailable(name: asset.name))
    }
  }
}

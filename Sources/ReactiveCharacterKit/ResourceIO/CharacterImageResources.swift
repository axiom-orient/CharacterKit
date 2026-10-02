import Foundation

public enum CharacterImageResolutionError: Error, Sendable, Equatable {
  case unavailable(name: String, source: CharacterAssetSource)
  case invalidPNG(name: String)
}

/// The local resource boundary. Scene construction does not call this type.
enum CharacterImageResources {
  private static let bundled: [String: Result<Data, CharacterImageResolutionError>] = {
    let themeAssets = CharacterTheme.allCases.flatMap { theme in
      theme.artDirection.requiredImageAssets
    }
    let optionalAssets = CharacterBuiltInAccessoryID.allCases.map {
      CharacterBuiltInAccessoryCatalog.spec(for: $0).image
    }
    let supplementalAssets = CharacterCatSupplementalAsset.allCases.map(\.pngImageAsset)
    let assets = Set(themeAssets + optionalAssets + supplementalAssets)
    return Dictionary(
      uniqueKeysWithValues: assets.map { asset in
        (asset.name, readPackage(asset))
      })
  }()

  static func png(_ asset: CharacterImageAsset) throws -> Data {
    guard asset.source == .package else {
      // An app's compiled asset catalog cannot be exported as a package PNG.
      // Native Canvas supports it; SVG must not invent a substitute.
      throw CharacterImageResolutionError.unavailable(name: asset.name, source: asset.source)
    }
    return try (bundled[asset.name] ?? readPackage(asset)).get()
  }

  private static func readPackage(_ asset: CharacterImageAsset)
    -> Result<Data, CharacterImageResolutionError>
  {
    let data: Data
    do {
      data = try CharacterPackageResource.data(named: asset.name, fileExtension: "png")
    } catch {
      return .failure(.unavailable(name: asset.name, source: asset.source))
    }
    guard data.count >= 24, Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
      return .failure(.invalidPNG(name: asset.name))
    }
    return .success(data)
  }
}

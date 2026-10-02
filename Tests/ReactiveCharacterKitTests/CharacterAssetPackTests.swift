import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterAssetPackTests: XCTestCase {
  func testImageAssetRejectsEmptyName() {
    XCTAssertThrowsError(try CharacterImageAsset(name: "  "))
  }

  func testAccessoryRejectsInvalidGeometry() throws {
    let image = try CharacterImageAsset(name: "custom")
    XCTAssertThrowsError(try CharacterAccessoryAsset(image: image, width: 0, height: 1))
    XCTAssertThrowsError(try CharacterAccessoryAsset(image: image, width: 1, height: 0))
    XCTAssertThrowsError(
      try CharacterAccessoryAsset(image: image, width: 1, height: 1, opacity: 1.01)
    )
    XCTAssertThrowsError(
      try CharacterAccessoryAsset(image: image, width: 1, height: 1, angle: .infinity)
    )
  }

  func testPalettePacksShareGeometryButUsePaletteMatchedHeadsetArtwork() {
    let pack = CharacterAssetPack.arcade
    XCTAssertNil(pack.background)
    XCTAssertNil(pack.face)
    XCTAssertEqual(pack.accessories, [.arcadeHeadset])
    XCTAssertEqual(pack.accessories.map(\.layer), [.behindFeatures])
    XCTAssertEqual(CharacterAssetLayer.allCases, [.behindFeatures, .foreground])
    XCTAssertEqual(CharacterAssetAnchor.allCases, [.face, .eyes, .nose, .mouth, .writing])

    XCTAssertEqual(CharacterTheme.black.artDirection.assets, .black)
    XCTAssertEqual(CharacterTheme.white.artDirection.assets, .white)
    XCTAssertEqual(CharacterTheme.arcade.artDirection.assets, .arcade)
    XCTAssertEqual(CharacterAssetPack.black.accessories.map(\.image), [.blackHeadset])
    XCTAssertEqual(CharacterAssetPack.white.accessories.map(\.image), [.whiteHeadset])
    XCTAssertEqual(CharacterAssetPack.arcade.accessories.map(\.image), [.arcadeHeadset])
    for theme in [CharacterTheme.black, .white, .arcade] {
      XCTAssertEqual(theme.artDirection.assets.accessories.map(\.layer), [.behindFeatures])
      XCTAssertEqual(theme.artDirection.assets.accessories.map(\.width), [1.30])
      XCTAssertEqual(theme.artDirection.assets.accessories.map(\.height), [1.30])
    }
  }

  func testPackageResourcesExistAndArePNG() throws {
    let names = [
      CharacterImageAsset.blackHeadset.name,
      CharacterImageAsset.whiteHeadset.name,
      CharacterImageAsset.arcadeHeadset.name,
      CharacterImageAsset.hood.name,
      CharacterImageAsset.baseballCap.name,
      CharacterImageAsset.bunnyEars.name,
    ]
    for name in names {
      let url = try CharacterPackageResource.url(named: name, fileExtension: "png")
      let data = try Data(contentsOf: url)
      XCTAssertGreaterThan(data.count, 8)
      XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }
  }

  func testBlackHeadsetIsEnabledInDefaultArtDirection() {
    let direction = CharacterArtDirection.black
    XCTAssertEqual(direction.assets, .black)
    XCTAssertTrue(direction.assets.accessories.contains(.blackHeadset))
    XCTAssertEqual(CharacterAccessoryAsset.blackHeadset.anchor, .face)
    XCTAssertEqual(CharacterAccessoryAsset.blackHeadset.layer, .behindFeatures)
  }
}

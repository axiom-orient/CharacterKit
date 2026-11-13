import ReactiveCharacterKit
import Testing

struct CharacterConfigurationBudgetTests {
  @Test(arguments: [0, 16])
  func supportedAccessoryBudgetPublishesCompleteScene(count: Int) throws {
    let direction = try CharacterArtDirection(
      name: "Accessory budget", components: .default.union(.accessories),
      assets: CharacterAssetPack(accessories: Array(repeating: .blackHeadset, count: count)))
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: direction, width: 160, height: 160)
    #expect(scene.nodes.filter { $0.id.hasPrefix("art.accessory.") }.count == count)
    #expect(direction.replacingPartColors(.default).assets == direction.assets)
  }

  @Test(arguments: [17, 128])
  func excessiveAccessoriesFailAtConfigurationBeforeRendering(count: Int) {
    let assets = CharacterAssetPack(accessories: Array(repeating: .blackHeadset, count: count))
    #expect(throws: CharacterArtDirectionError.invalidValue(
      field: "assets.accessories.count", value: Double(count))) {
      try CharacterArtDirection(name: "Too many accessories", assets: assets)
    }
  }
}

import XCTest
@testable import ReactiveCharacterKit

final class CharacterSEMIRenderingTests: XCTestCase {
  func testSceneIsAlwaysSEMIAndContainsCanonicalParts() throws {
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0),
      width: 320,
      height: 320
    )
    let ids = Set(scene.nodes.map(\.id))
    for id in ["semi.head", "semi.tail", "semi.ear.left", "semi.ear.right", "semi.paw.left", "semi.paw.right", "semi.document", "mouth.lips", "mouth.philtrum"] {
      XCTAssertTrue(ids.contains(id), "missing SEMI part: \(id)")
    }
    XCTAssertFalse(ids.contains { $0.localizedCaseInsensitiveContains("portrait") })
    XCTAssertFalse(ids.contains { $0.localizedCaseInsensitiveContains("accessory.") })
  }

  func testSceneSupportsSmallAndRepresentativeOutputs() throws {
    for size in [48.0, 96.0, 320.0, 1024.0] {
      let scene = try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(state: .idle, elapsed: 0.7),
        width: size,
        height: size
      )
      XCTAssertEqual(scene.width, size)
      XCTAssertEqual(scene.height, size)
      XCTAssertFalse(scene.nodes.isEmpty)
    }
  }

  func testEveryEmotionBuildsAndRendersSVG() throws {
    for emotion in CharacterEmotion.allCases {
      let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
      let scene = try CharacterSceneBuilder.scene(
        pose: ReactiveCharacter.pose(state: state, elapsed: 0.8),
        width: 320,
        height: 320
      )
      let svg = try CharacterSVGRenderer.render(scene, title: emotion.rawValue, idPrefix: emotion.rawValue)
      XCTAssertTrue(svg.contains("<svg"))
      XCTAssertTrue(svg.contains("data:image/png;base64,"))
    }
  }

  func testMouthIsStrokeOnlyInScene() throws {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: state, elapsed: 0.3),
      width: 320,
      height: 320
    )
    let mouth = scene.nodes.filter { $0.id.hasPrefix("mouth.") && !$0.id.contains("whiskers") }
    XCTAssertFalse(mouth.isEmpty)
    XCTAssertTrue(mouth.allSatisfy { $0.fill == nil })
    XCTAssertTrue(mouth.contains { $0.id == "mouth.lips" })
    XCTAssertTrue(mouth.contains { $0.id == "mouth.philtrum" })
  }

  func testOnlySixPackageImageAssetsAreReferencedBySEMI() throws {
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0),
      width: 320,
      height: 320
    )
    let assets = Set(scene.nodes.compactMap { $0.image?.asset.name })
    XCTAssertEqual(assets, Set([
      "semi-head", "semi-ear-left", "semi-ear-right",
      "semi-paw-left", "semi-paw-right", "semi-tail",
    ]))
  }
}

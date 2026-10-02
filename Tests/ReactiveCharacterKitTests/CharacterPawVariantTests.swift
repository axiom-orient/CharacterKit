import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterPawVariantTests: XCTestCase {
  func testAllSeventeenVariantsHaveIndependentPackagedSVGAndPNG() throws {
    XCTAssertEqual(CharacterPawVariant.allCases.count, 17)
    XCTAssertEqual(Set(CharacterPawVariant.allCases.map(\.resourceName)).count, 17)
    for variant in CharacterPawVariant.allCases {
      let data = try variant.data(for: .png)
      XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
      let svg = try variant.svgString()
      XCTAssertEqual(svg.components(separatedBy: "id=\"toe-").count - 1, 4)
      XCTAssertEqual(svg.components(separatedBy: "id=\"bean\"").count - 1, 1)
      XCTAssertTrue(FileManager.default.fileExists(atPath: try variant.packageURL(for: .svg).path))
      XCTAssertEqual(variant.artDirection.requiredImageAssets, [variant.pngImageAsset])
    }
    XCTAssertEqual(CharacterCatSupplementalAsset.pawPad.rawValue, "cat-paw-pad")
    XCTAssertNotEqual(CharacterPawVariant.tiny.pngImageAsset, .catPawPad)
  }

  func testAllVariantsAreAssetOnlyAcrossEveryEmotionAndNineGazes() throws {
    for variant in CharacterPawVariant.allCases {
      for emotion in [nil] + CharacterEmotion.allCases.map(Optional.some) {
        let state = ReactiveCharacter.act(state: .idle, event: .emotionChanged(emotion)).stateAfter
        for x in [0.0, 0.5, 1.0] {
          for y in [0.0, 0.5, 1.0] {
            let focused = ReactiveCharacter.act(state: state,
              event: .attentionFocused(try .init(validatingX: x, y: y))).stateAfter
            let frame = try CharacterSceneBuilder.scene(
              pose: ReactiveCharacter.pose(state: focused, elapsed: 0.52, reduceMotion: true),
              artDirection: variant.artDirection, width: 64, height: 64)
            XCTAssertEqual(frame.nodes.count, 1)
            XCTAssertEqual(frame.nodes.first?.image?.asset, variant.pngImageAsset)
            XCTAssertFalse(frame.nodes.contains { $0.id.contains("eye") || $0.id.contains("mouth") })
          }
        }
      }
    }
  }

  func testVariantsEmbedRealResourcesAndUseExistingAnimationLifecycle() throws {
    let receipt = ReactiveCharacter.act(state: .idle,
      event: .animationStarted(id: try .init(validating: "variant-bounce"), animation: .bounce))
    for variant in CharacterPawVariant.allCases {
      func frame(_ time: Double, reduced: Bool) throws -> CharacterScene {
        try CharacterSceneBuilder.scene(
          pose: ReactiveCharacter.pose(state: receipt.stateAfter, elapsed: time,
            reduceMotion: reduced, motionProfile: .cartoon),
          artDirection: variant.artDirection, width: 320, height: 320)
      }
      XCTAssertNotEqual(try frame(0, reduced: false), try frame(0.18, reduced: false))
      XCTAssertEqual(try frame(0, reduced: true), try frame(3, reduced: true))
      XCTAssertTrue(try CharacterSVGRenderer.render(frame(0.18, reduced: false))
        .contains("data:image/png;base64,"))
    }
    XCTAssertEqual(receipt.effects.count, 1)
  }
}
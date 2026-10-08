import Foundation
import XCTest

import ReactiveCharacterKit

final class CharacterSVGInputTests: XCTestCase {
  func testSVGRejectsForbiddenXMLScalarsAndEscapesHostTitle() throws {
    let scene = try makeScene()
    for scalar: UInt32 in [0, 0x1F, 0xFFFE, 0xFFFF] {
      let title = "title" + String(try XCTUnwrap(UnicodeScalar(scalar)))
      XCTAssertThrowsError(try CharacterSVGRenderer.render(scene, title: title)) { error in
        guard case CharacterSceneError.invalidScene(let path, _) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(path, "title")
      }
    }
    let svg = try CharacterSVGRenderer.render(scene, title: "고양이 🐈 & <view> \"한글\"")
    XCTAssertTrue(svg.contains("고양이 🐈 &amp; &lt;view&gt; &quot;한글&quot;"))
    XCTAssertFalse(svg.contains("<view>"))
  }

  func testTitleLengthAndUnicodeBoundary() throws {
    let scene = try makeScene()
    XCTAssertNoThrow(try CharacterSVGRenderer.render(scene, title: String(repeating: "가", count: 512)))
    XCTAssertThrowsError(try CharacterSVGRenderer.render(scene, title: String(repeating: "가", count: 513)))
    XCTAssertNoThrow(try CharacterSVGRenderer.render(scene, title: "미리보기 🐈"))
  }

  func testIdentifierPrefixRejectsMarkupAndPreservesNamespacing() throws {
    let scene = try makeScene()
    for prefix in ["", "a b", "a\"/><script>", "세미", String(repeating: "a", count: 81)] {
      XCTAssertThrowsError(try CharacterSVGRenderer.render(scene, idPrefix: prefix)) { error in
        guard case CharacterSceneError.invalidScene(let path, _) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(path, "idPrefix")
      }
    }
    let first = try CharacterSVGRenderer.render(scene, idPrefix: "first")
    let second = try CharacterSVGRenderer.render(scene, idPrefix: "second")
    XCTAssertTrue(first.contains("aria-labelledby=\"ck-first-title\""))
    XCTAssertTrue(second.contains("aria-labelledby=\"ck-second-title\""))
    XCTAssertFalse(second.contains("ck-first-"))
  }

  func testInvalidViewportIsRejectedBeforeSceneConstruction() {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true)
    for value in [Double.nan, .infinity, -.infinity, -1, 0, 0.5, 16_385] {
      XCTAssertThrowsError(try CharacterSceneBuilder.scene(pose: pose, width: value, height: 64))
      XCTAssertThrowsError(try CharacterSceneBuilder.scene(pose: pose, width: 64, height: value))
    }
  }

  private func makeScene() throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      width: 64,
      height: 64
    )
  }
}

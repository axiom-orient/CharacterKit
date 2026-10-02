import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterSVGInputTests: XCTestCase {
  func testSVGRejectsForbiddenXMLScalarsBeforePublishing() throws {
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: CharacterPortraitStyle.shortHairBoy.artDirection,
      width: 64, height: 64, includeBackground: false)
    for scalar: UInt32 in [0, 0x1F, 0xFFFE, 0xFFFF] {
      let title = "title" + String(try XCTUnwrap(UnicodeScalar(scalar)))
      XCTAssertThrowsError(try CharacterSVGRenderer.render(scene, title: title)) { error in
        guard case CharacterDesignError.invalid(let path, _) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(path, "title")
      }
    }
    let svg = try CharacterSVGRenderer.render(scene, title: "고양이 🐈 & <view> \"한글\"")
    XCTAssertTrue(svg.contains("고양이 🐈 &amp; &lt;view&gt; &quot;한글&quot;"))
  }

  func testTitleLengthLimitAndSupplementaryCharactersRemainSupported() throws {
    let scene = try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: CharacterPortraitStyle.shortHairBoy.artDirection,
      width: 64, height: 64, includeBackground: false)
    XCTAssertNoThrow(try CharacterSVGRenderer.render(scene, title: String(repeating: "가", count: 512)))
    XCTAssertThrowsError(try CharacterSVGRenderer.render(scene, title: String(repeating: "가", count: 513)))
    XCTAssertNoThrow(try CharacterSVGRenderer.render(scene, title: "미리보기 🐈"))
  }
}

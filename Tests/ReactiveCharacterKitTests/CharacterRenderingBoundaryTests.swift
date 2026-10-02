import Foundation
import XCTest
@testable import ReactiveCharacterKit

final class CharacterRenderingBoundaryTests: XCTestCase {
  private func scene(_ direction: CharacterArtDirection) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: direction, width: 512, height: 512, includeBackground: false)
  }

  func testResolvedPaletteReplacesOnlyTheNamedRole() throws {
    let palette = CharacterStyle.portrait.partColors
    let red = try CharacterColor(red: 0.9, green: 0.2, blue: 0.1)
    let modified = palette.replacing(surface: red, eyes: red, mouth: red)
    XCTAssertEqual(modified.brows, palette.brows)
    XCTAssertEqual(modified.outline, palette.outline)
    XCTAssertEqual(modified.clothingDetail, palette.clothingDetail)
    XCTAssertEqual(modified.surfaceShade, palette.surfaceShade)
    XCTAssertEqual(modified.surfaceHighlight, palette.surfaceHighlight)
    XCTAssertEqual(modified.surfaceRim, palette.surfaceRim)
    XCTAssertEqual(modified.replacing(surface: palette.surface, eyes: palette.eyes, mouth: palette.mouth), palette)
  }

  func testIndependentBrowAndClothingDetailPaintReachBoyAndGirl() throws {
    let red = try CharacterColor(red: 0.9, green: 0.2, blue: 0.1)
    for style in [CharacterPortraitStyle.shortHairBoy, .bobGirl] {
      let direction = style.artDirection
      let changed = try scene(direction.replacingPartColors(
        direction.style.partColors.replacing(brows: red, clothingDetail: red)))
      let original = try scene(direction)
      XCTAssertEqual(changed.nodes.first { $0.id == "eye.left" }, original.nodes.first { $0.id == "eye.left" })
      let brow = try XCTUnwrap(changed.nodes.first { $0.id == "eyebrow.left" })
      XCTAssertTrue(brow.fill == .solid(red) || brow.stroke == red)
      for node in changed.nodes where node.id.hasPrefix("portrait.collar") {
        XCTAssertEqual(node.fill, .solid(red))
      }
    }
  }

  func testCapMaterialDoesNotRecolorHairOrOutline() throws {
    let style = CharacterPortraitStyle.cappedBoy.artDirection
    let red = try CharacterColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.5)
    let original = try scene(style)
    let changed = try scene(style.replacingPartColors(style.style.partColors.replacing(accessory: red, accessoryDetail: red)))
    for id in ["portrait.hair.fringe", "portrait.outline", "mouth"] {
      XCTAssertEqual(changed.nodes.first { $0.id == id }, original.nodes.first { $0.id == id })
    }
    XCTAssertEqual(changed.nodes.first { $0.id == "portrait.hair.cap.crown" }?.fill, .solid(red))
    XCTAssertEqual(changed.nodes.first { $0.id == "portrait.hair.cap.strap" }?.fill, .solid(red))
    XCTAssertEqual(changed.nodes.first { $0.id == "portrait.hair.cap.seams" }?.stroke?.alpha, 0.5)
  }

  func testSVGDefinesEachClipOnceWithoutFlatteningNodeTransforms() throws {
    for view in CharacterPortraitStyle.BoyViewpoint.allCases {
      let frame = try scene(CharacterPortraitStyle.boy(viewpoint: view).artDirection)
      var paths: [CharacterVectorPath] = []
      for path in frame.nodes.flatMap(\.clips) where !paths.contains(path) { paths.append(path) }
      let count = frame.nodes.reduce(0) { $0 + $1.clips.count }
      XCTAssertLessThan(paths.count, count)
      let svg = try CharacterSVGRenderer.render(frame)
      XCTAssertEqual(svg.components(separatedBy: "<clipPath ").count - 1, paths.count)
      XCTAssertEqual(svg.components(separatedBy: "clip-path=\"").count - 1, count)
      XCTAssertEqual(svg, try CharacterSVGRenderer.render(frame))
      XCTAssertTrue(svg.contains("clipPathUnits=\"userSpaceOnUse\""))
    }
  }

  func testCapAndHairUseSameLowerCurveInTheSameCoordinateSystem() throws {
    let localCurve = Array(CharacterPortraitCapGeometry.crown.commands.prefix(3).dropFirst())
    for style in [CharacterPortraitStyle.cappedBoy, .boy(viewpoint: .threeQuarterRight)] {
      let layout = CharacterPortraitFeatureLayout.resolve(style)
      let frame = try scene(style.artDirection)
      let hair = try XCTUnwrap(frame.nodes.first { $0.id == "portrait.hair.fringe" })
      let crown = try XCTUnwrap(frame.nodes.first { $0.id == "portrait.hair.cap.crown" })
      XCTAssertEqual(Array(crown.path.commands.prefix(3).dropFirst()), localCurve)
      let expected = CharacterPortraitCapGeometry.hairVisibility.mapped { p in
        let t = layout.capTransform
        return .init(x: t.a*p.x + t.c*p.y + t.tx, y: t.b*p.x + t.d*p.y + t.ty)
      }
      XCTAssertEqual(hair.clips, [expected])
      XCTAssertEqual(crown.transform, hair.transform.concatenating(layout.capTransform))
    }
  }

  func testUnknownComponentBitsFailBeforeScenePublication() throws {
    for style in [CharacterPortraitStyle.shortHairBoy, .bobGirl] {
      XCTAssertThrowsError(try scene(style.artDirection(components: .init(rawValue: 128)))) { error in
        guard case CharacterDesignError.invalid(let path, _) = error else { return XCTFail("\(error)") }
        XCTAssertEqual(path, "components")
      }
    }
  }
}

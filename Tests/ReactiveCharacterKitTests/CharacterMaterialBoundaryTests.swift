import XCTest
@testable import ReactiveCharacterKit

final class CharacterMaterialBoundaryTests: XCTestCase {
  private func scene(_ direction: CharacterArtDirection) throws -> CharacterScene {
    try CharacterSceneBuilder.scene(
      pose: ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true),
      artDirection: direction, width: 512, height: 512)
  }

  func testPortraitNoseUsesItsOwnColor() throws {
    let nose = try CharacterColor(red: 0.8, green: 0.1, blue: 0.2)
    for style in [CharacterPortraitStyle.shortHairBoy, .bobGirl] {
      let direction = CharacterArtDirection.portrait(style, components: .all)
        .replacingPartColors(style.artDirection.style.partColors.replacing(nose: nose))
      XCTAssertEqual(try scene(direction).nodes.first { $0.id == "nose" }?.stroke, nose)
    }
  }

  func testChangingMouthDoesNotRecolorBodyOutlineOrCap() throws {
    let base = CharacterPortraitStyle.cappedBoy.artDirection
    let custom = base.replacingPartColors(base.style.partColors.replacing(
      mouth: try CharacterColor(red: 0.9, green: 0.1, blue: 0.4)))
    let a = try scene(base), b = try scene(custom)
    for id in ["portrait.outline", "portrait.hair.cap.crown", "portrait.hair.cap.opening"] {
      XCTAssertEqual(a.nodes.first { $0.id == id }, b.nodes.first { $0.id == id }, id)
    }
    XCTAssertNotEqual(a.nodes.first { $0.id == "mouth" }?.stroke,
                      b.nodes.first { $0.id == "mouth" }?.stroke)
  }

  func testChangingSkinDoesNotRecolorCollarAndCuffs() throws {
    let base = CharacterPortraitStyle.shortHairBoy.artDirection
    let custom = base.replacingPartColors(base.style.partColors.replacing(
      surface: try CharacterColor(red: 0.9, green: 0.7, blue: 0.5)))
    let a = try scene(base), b = try scene(custom)
    for id in ["portrait.collar.left", "portrait.collar.right", "portrait.cuff.left", "portrait.cuff.right"] {
      XCTAssertEqual(a.nodes.first { $0.id == id }?.fill, b.nodes.first { $0.id == id }?.fill, id)
    }
    XCTAssertNotEqual(a.nodes.first { $0.id == "portrait.face" }?.fill,
                      b.nodes.first { $0.id == "portrait.face" }?.fill)
  }

  func testTransparentSurfaceHasNoOpaqueDerivedPaint() throws {
    let transparent = try CharacterColor(red: 0.15, green: 0.3, blue: 0.6, alpha: 0)
    let direction = try CharacterArtDirection(name: "Transparent material", components: [],
      style: CharacterStyle(partColors: .init(surface: transparent)))
    for node in try scene(direction).nodes where node.id.hasPrefix("art.face") {
      if let stroke = node.stroke { XCTAssertEqual(stroke.alpha, 0, node.id) }
      switch node.fill {
      case .solid(let color): XCTAssertEqual(color.alpha, 0, node.id)
      case .linear(_, _, let stops), .radial(_, _, let stops):
        XCTAssertTrue(stops.allSatisfy { $0.color.alpha == 0 }, node.id)
      case nil: break
      }
    }
  }
}

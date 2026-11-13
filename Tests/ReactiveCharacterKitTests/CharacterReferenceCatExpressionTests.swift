import XCTest
@testable import ReactiveCharacterKit

final class CharacterReferenceCatExpressionTests: XCTestCase {
  func testSadCatMouthCornersFallBelowJoyCorners() throws {
    let direction = CharacterArtDirection.catNorwegianForest
    func mouth(_ emotion: CharacterEmotion) throws -> CharacterVectorPath {
      let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8, artDirection: direction)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, artDirection: direction, width: 320, height: 320)
      return try XCTUnwrap(scene.nodes.first { $0.id == "reference.mouth.articulated" }?.path)
    }
    func cornersAndCenter(_ path: CharacterVectorPath) throws -> (Double, Double) {
      guard path.commands.count >= 5,
        case .move(let corner) = path.commands[2],
        case .quad(_, let center) = path.commands[3]
      else { throw NSError(domain: "Unexpected feline mouth path", code: 1) }
      return (corner.y, center.y)
    }
    let sad = try cornersAndCenter(mouth(.sadness))
    let happy = try cornersAndCenter(mouth(.joy))
    // Scene coordinates grow downward. Sad corners should sit below the center;
    // happy corners rise above it.
    XCTAssertGreaterThan(sad.0, sad.1)
    XCTAssertLessThan(happy.0, happy.1)
  }

  func testOpenMouthMeetsLipCenter() throws {
    let direction = CharacterArtDirection.catNorwegianForest
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8, artDirection: direction)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, artDirection: direction, width: 320, height: 320)
    let lip = try XCTUnwrap(scene.nodes.first { $0.id == "reference.mouth.articulated" })
    let opening = try XCTUnwrap(scene.nodes.first { $0.id == "reference.mouth.open" })
    guard case .line(let lipCenter) = lip.path.commands[1],
      case .move(let openingCorner) = opening.path.commands[0]
    else { return XCTFail("Unexpected feline mouth geometry") }
    XCTAssertEqual(openingCorner.y, lipCenter.y, accuracy: 1e-12)
    XCTAssertLessThan(try XCTUnwrap(scene.nodes.firstIndex(of: opening)),
      try XCTUnwrap(scene.nodes.firstIndex(of: lip)))
  }
}

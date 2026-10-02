import XCTest

@testable import ReactiveCharacterKit

final class CharacterCompanionTests: XCTestCase {
  func testQuietCompanionKeepsPositionAndBodyStillWhileBlinking() {
    let poses = stride(from: 0.0, through: 30.0, by: 0.025).map {
      ReactiveCharacter.pose(state: .idle, elapsed: $0, motionProfile: .companion)
    }
    let first = poses[0]
    for pose in poses {
      XCTAssertEqual(pose.surface, first.surface)
      XCTAssertEqual(pose.eyes.left.centerX, first.eyes.left.centerX)
      XCTAssertEqual(pose.eyes.left.centerY, first.eyes.left.centerY)
      XCTAssertEqual(pose.eyes.right.centerX, first.eyes.right.centerX)
      XCTAssertEqual(pose.eyes.right.centerY, first.eyes.right.centerY)
      XCTAssertEqual(pose.noseOffsetX, first.noseOffsetX)
      XCTAssertEqual(pose.motionEnergy, 0)
      XCTAssertTrue(pose.accents.isEmpty)
    }
    XCTAssertLessThan(poses.map(\.eyes.left.height).min()!, first.eyes.left.height * 0.5)
    XCTAssertEqual(CharacterMotionProfile.expressive.idleStrength, 1)
  }
}

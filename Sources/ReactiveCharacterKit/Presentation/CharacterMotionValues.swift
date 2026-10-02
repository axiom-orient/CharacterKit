import Foundation

struct CharacterEyeShape: Sendable, Equatable {
  let width: Double
  let height: Double

  static let tall = Self(width: 0.19, height: 0.43)
  static let circle = Self(width: 0.28, height: 0.28)
  static let tinyCircle = Self(width: 0.13, height: 0.13)
  static let large = Self(width: 0.25, height: 0.52)
  static let wide = Self(width: 0.42, height: 0.14)
}

struct CharacterGazeTarget: Sendable, Equatable {
  let x: Double
  let y: Double
  let angle: Double
  let shape: CharacterEyeShape

  static let front = Self(x: 0, y: 0, angle: 0, shape: .tall)
}

struct CharacterMotionFrame: Sendable, Equatable {
  let gazeX: Double
  let gazeY: Double
  let angle: Double
  let eyeWidth: Double
  let eyeHeight: Double
  let motionEnergy: Double
  let directionX: Double
  let directionY: Double
  let blink: Double
}

enum CharacterMotionReference {
  static let idleFrontHold = 1.90
  static let largeMove = 0.090
  static let largeSettle = 0.040
  static let largeHold = 0.30
  static let circleMove = 0.070
  static let circleSettle = 0.032
  static let circleHold = 0.22
  static let tinyMove = 0.060
  static let tinySettle = 0.030
  static let tinyHold = 0.17
  static let tallMove = 0.075
  static let tallSettle = 0.032
  static let tallHold = 0.25
  static let wideMove = 0.075
  static let wideSettle = 0.032
  static let wideHold = 0.28
  static let returnMove = 0.090
  static let returnSettle = 0.040
  static let idleFrontTail = 1.00

  static let blinkClose = 0.050
  static let blinkHold = 0.028
  static let blinkOpen = 0.090

  static let nearTrailDelay = 0.024
  static let farTrailDelay = 0.048

  static var blinkDuration: Double {
    blinkClose + blinkHold + blinkOpen
  }

  static var idleCycleDuration: Double {
    idleFrontHold
      + largeMove + largeSettle + largeHold
      + circleMove + circleSettle + circleHold
      + tinyMove + tinySettle + tinyHold
      + tallMove + tallSettle + tallHold
      + wideMove + wideSettle + wideHold
      + returnMove + returnSettle
      + idleFrontTail
  }
}

enum CharacterMotionIdentity: Sendable, Hashable {
  case idle
  case userWriting
  case agentThinking(CharacterTaskID)
  case agentWriting(CharacterTaskID)
  case agentCancelling(CharacterTaskID)
  case success(CharacterTaskID)
  case failure(CharacterTaskID)
  case cancelled(CharacterTaskID)
}

extension CharacterActivity {
  var motionIdentity: CharacterMotionIdentity {
    switch self {
    case .idle:
      .idle
    case .userWriting:
      .userWriting
    case .agentThinking(let taskID):
      .agentThinking(taskID)
    case .agentWriting(let taskID, _):
      .agentWriting(taskID)
    case .agentCancelling(let taskID):
      .agentCancelling(taskID)
    case .success(let taskID):
      .success(taskID)
    case .failure(let taskID, _):
      .failure(taskID)
    case .cancelled(let taskID):
      .cancelled(taskID)
    }
  }
}

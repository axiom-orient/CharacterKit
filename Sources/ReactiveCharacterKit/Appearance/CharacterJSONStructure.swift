import Foundation

/// Raw-data structural validation shared by document boundaries. Domain decoding
/// and error mapping remain with each document; this owns neither schema nor state.
// Adapted from the sibling CharacterKit; kept at the configuration input boundary.
enum CharacterJSONStructure {
  static let maximumDepth = 32

  struct Violation: Error {
    let path: String
    let reason: String
  }

  static func check(_ data: Data) throws {
    // JSONDecoder accepts UTF-8/16/32, with or without a BOM. Scan normalized UTF-8
    // so alternate encodings cannot bypass the duplicate-member/depth policy.
    // The original data is still decoded by Foundation: this is not a syntax parser.
    let bytes = normalizedBytes(data)
    var stack: [Set<String>?] = []
    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case 123: stack.append(Set<String>())  // object
      case 91: stack.append(nil)  // array
      case 125, 93:
        if !stack.isEmpty { stack.removeLast() }
      case 34:
        let start = index
        index += 1
        while index < bytes.count, bytes[index] != 34 {
          if bytes[index] == 92 { index += 1 }
          index += 1
        }
        guard index < bytes.count else { return }  // Foundation reports malformed JSON.
        var next = index + 1
        while next < bytes.count, isWhitespace(bytes[next]) { next += 1 }
        if next < bytes.count, bytes[next] == 58, !stack.isEmpty,
          var names = stack[stack.count - 1]
        {
          let key = try JSONDecoder().decode(String.self, from: Data(bytes[start...index]))
          guard names.insert(key).inserted else {
            throw Violation(path: "json.byte[\(start)]", reason: "duplicate object member: \(key)")
          }
          stack[stack.count - 1] = names
        }
      default: break
      }
      guard stack.count <= maximumDepth else {
        throw Violation(path: "json", reason: "maximum nesting depth is \(maximumDepth)")
      }
      index += 1
    }
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 9 || byte == 10 || byte == 13 || byte == 32
  }

  private static func normalizedBytes(_ data: Data) -> [UInt8] {
    let bytes = Array(data)
    let encoding: String.Encoding
    let bomLength: Int
    if bytes.starts(with: [0, 0, 0xFE, 0xFF]) {
      (encoding, bomLength) = (.utf32BigEndian, 4)
    } else if bytes.starts(with: [0xFF, 0xFE, 0, 0]) {
      (encoding, bomLength) = (.utf32LittleEndian, 4)
    } else if bytes.starts(with: [0xFE, 0xFF]) {
      (encoding, bomLength) = (.utf16BigEndian, 2)
    } else if bytes.starts(with: [0xFF, 0xFE]) {
      (encoding, bomLength) = (.utf16LittleEndian, 2)
    } else if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
      return Array(bytes.dropFirst(3))
    } else if bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0 {
      (encoding, bomLength) = (.utf32BigEndian, 0)
    } else if bytes.count >= 4, bytes[1] == 0, bytes[2] == 0, bytes[3] == 0 {
      (encoding, bomLength) = (.utf32LittleEndian, 0)
    } else if bytes.count >= 2, bytes[0] == 0 {
      (encoding, bomLength) = (.utf16BigEndian, 0)
    } else if bytes.count >= 2, bytes[1] == 0 {
      (encoding, bomLength) = (.utf16LittleEndian, 0)
    } else {
      return bytes
    }
    guard let string = String(data: Data(bytes.dropFirst(bomLength)), encoding: encoding) else {
      return []  // Invalid Unicode is rejected by the original-data JSONDecoder below.
    }
    return Array(string.utf8)
  }
}

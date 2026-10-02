import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterConfigurationInputTests: XCTestCase {
  private let encodings: [String.Encoding] = [
    .utf8, .utf16LittleEndian, .utf16BigEndian,
    .utf32LittleEndian, .utf32BigEndian,
  ]

  func testReferenceDocumentRejectsDuplicateAndEscapedEquivalentMembers() throws {
    let cases = [
      #"{"schema":"character-reference/1","schema":"character-reference/1","appearance":{"kind":"headsetFree","body":"white"}}"#,
      #"{"schema":"character-reference/1","appearance":{"kind":"headsetFree","body":"white","b\u006fdy":"white"}}"#,
    ]
    for json in cases {
      for encoding in encodings {
        XCTAssertThrowsError(
          try CharacterReferenceDocument(data: XCTUnwrap(json.data(using: encoding))),
          "Duplicate member accepted in \(encoding)")
      }
    }
  }

  func testBOMAndNestedScopeDoNotChangeStructuralPolicy() throws {
    let pairs: [(String.Encoding, [UInt8])] = [
      (.utf8, [0xEF, 0xBB, 0xBF]),
      (.utf16LittleEndian, [0xFF, 0xFE]), (.utf16BigEndian, [0xFE, 0xFF]),
      (.utf32LittleEndian, [0xFF, 0xFE, 0, 0]), (.utf32BigEndian, [0, 0, 0xFE, 0xFF]),
    ]
    for (encoding, bom) in pairs {
      let valid = #" {"a":{"id":1},"b":{"id":2},"label":"{ [ :"}"#
      let duplicate = #" {"a":{"id":1,"i\u0064":2}}"#
      XCTAssertNoThrow(
        try CharacterJSONStructure.check(Data(bom) + XCTUnwrap(valid.data(using: encoding))))
      XCTAssertThrowsError(
        try CharacterJSONStructure.check(Data(bom) + XCTUnwrap(duplicate.data(using: encoding))))
      let deep = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
      XCTAssertThrowsError(
        try CharacterJSONStructure.check(Data(bom) + XCTUnwrap(deep.data(using: encoding))))
    }
  }

  func testValidReferenceDocumentRetainsAllFoundationJSONEncodings() throws {
    let expected = CharacterReferenceDocument(appearance: .headsetFree(body: .white))
    let json = String(decoding: try expected.data(), as: UTF8.self)
    for encoding in encodings {
      XCTAssertEqual(
        try CharacterReferenceDocument(data: XCTUnwrap(json.data(using: encoding))), expected)
    }
  }

  func testDesignDuplicateGuardCannotBeBypassedByUnicodeEncoding() throws {
    let design = try CharacterDesign.load(.black)
    let json = String(decoding: try design.encodedProfile(), as: UTF8.self)
    let duplicate = "{\"id\":\"duplicate\"," + json.dropFirst()
    for encoding in encodings {
      XCTAssertEqual(try CharacterDesign.decode(XCTUnwrap(json.data(using: encoding))), design)
      XCTAssertThrowsError(
        try CharacterDesign.decode(XCTUnwrap(duplicate.data(using: encoding))),
        "Duplicate member accepted in \(encoding)")
    }
  }
}

import Foundation
import XCTest

@testable import ReactiveCharacterKit

final class CharacterDesignTests: XCTestCase {
  private func profile() throws -> CharacterDesignProfile {
    try CharacterDesign.load(.black).profile
  }

  private func object() throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: CharacterDesign.load(.black).encodedProfile())
        as? [String: Any])
  }

  private func decode(_ object: [String: Any]) throws -> CharacterDesign {
    try CharacterDesign.decode(JSONSerialization.data(withJSONObject: object))
  }

  func testAllBundledProfilesCompileRoundTripAndHaveDistinctDesigns() throws {
    var ids = Set<String>()
    for preset in CharacterDesignPreset.allCases {
      let design = try CharacterDesign.load(preset)
      XCTAssertTrue(ids.insert(design.profile.id).inserted)
      XCTAssertEqual(design, try CharacterDesign.decode(design.encodedProfile()))
      XCTAssertEqual(design.profile.schema, "characterkit.design/1")
      XCTAssertTrue(design.diagnostics.isEmpty, "\(preset): \(design.diagnostics)")
    }
    XCTAssertEqual(ids.count, 3)
  }

  func testUnknownRootAndNestedFieldsAreRejected() throws {
    var root = try object()
    root["renderer"] = "ignored-typo"
    XCTAssertThrowsError(try decode(root))
    root = try object()
    var rendering = try XCTUnwrap(root["rendering"] as? [String: Any])
    rendering["eyeScaelX"] = 1
    root["rendering"] = rendering
    XCTAssertThrowsError(try decode(root))
    root = try object()
    var palettes = try XCTUnwrap(root["palettes"] as? [String: Any])
    var light = try XCTUnwrap(palettes["light"] as? [String: Any])
    light["unknownColor"] = "#FFFFFF"
    palettes["light"] = light
    root["palettes"] = palettes
    XCTAssertThrowsError(try decode(root))
  }

  func testEveryRootFieldIsRequiredAndNullIsNotDefault() throws {
    let root = try object()
    for key in root.keys {
      var missing = root
      missing.removeValue(forKey: key)
      XCTAssertThrowsError(try decode(missing), key)
      var null = root
      null[key] = NSNull()
      XCTAssertThrowsError(try decode(null), key)
    }
  }

  func testWrongTypesUnknownEnumAndMalformedJSONAreRejected() throws {
    var root = try object()
    root["name"] = 42
    XCTAssertThrowsError(try decode(root))
    root = try object()
    var rendering = try XCTUnwrap(root["rendering"] as? [String: Any])
    rendering["mode"] = "photorealistic"
    root["rendering"] = rendering
    XCTAssertThrowsError(try decode(root))
    XCTAssertThrowsError(try CharacterDesign.decode(Data("{broken".utf8)))
    XCTAssertThrowsError(try CharacterDesign.decode(Data()))
    XCTAssertThrowsError(try CharacterDesign.decode(Data(repeating: 0x20, count: 131_073)))
  }

  func testDuplicateJSONMembersAndExcessiveNestingAreRejected() throws {
    let json = String(decoding: try CharacterDesign.load(.black).encodedProfile(), as: UTF8.self)
    let duplicate = json.replacingOccurrences(
      of: "{", with: "{\"id\":\"duplicate\",", options: [],
      range: json.startIndex..<json.index(after: json.startIndex))
    XCTAssertThrowsError(try CharacterDesign.decode(Data(duplicate.utf8)))
    let escaped = #"{"id":"first","i\u0064":"second"}"#
    XCTAssertThrowsError(try CharacterDesignJSONGuard.check(Data(escaped.utf8)))
    XCTAssertNoThrow(
      try CharacterDesignJSONGuard.check(
        Data(#"{"a":{"id":1},"b":{"id":2},"label":"[ { : \"}"}"#.utf8)))
    let deep = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
    XCTAssertThrowsError(try CharacterDesign.decode(Data(deep.utf8)))
  }

  func testUnsupportedSchemaAndInvalidIdentifiersFailExplicitly() throws {
    var p = try profile()
    p.schema = "characterkit.design/2"
    XCTAssertThrowsError(try p.compile()) {
      XCTAssertEqual($0 as? CharacterDesignError, .unsupportedSchema(p.schema))
    }
    for id in ["", "UPPER", "../file/", "new design", String(repeating: "a", count: 65)] {
      p = try profile()
      p.id = id
      XCTAssertThrowsError(try p.compile())
    }
    for name in ["", "  ", "bad\nlabel", String(repeating: "a", count: 81)] {
      p = try profile()
      p.name = name
      XCTAssertThrowsError(try p.compile())
    }
  }

  func testPaletteRejectsInvalidOrImplicitAlphaColors() throws {
    for color in ["red", "FFF", "#FFF", "#FFFFFF00", "#GG0000", " #FFFFFF"] {
      var p = try profile()
      p.palettes.light.feature = color
      XCTAssertThrowsError(try p.compile(), color)
    }
  }

  func testNumericConfigurationRejectsNaNInfinityAndOutOfRangeWithoutClamping() throws {
    let changes: [(inout CharacterDesignProfile) -> Void] = [
      { $0.layout.aspectRatio = .nan }, { $0.layout.aspectRatio = 0 },
      { $0.layout.inset = 0.26 }, { $0.layout.alignmentX = -0.01 },
      { $0.layout.face.width = 0 }, { $0.layout.face.width = Double.leastNonzeroMagnitude },
      { $0.layout.face.x = -0.1 },
      { $0.rendering.eyeScaleX = .infinity }, { $0.rendering.cornerRadius = 0.51 },
      { $0.rendering.eyeSpacing = 0.49 }, { $0.rendering.lineWidth = 0 },
      { $0.rendering.minimumMouthAspect = 0.01 }, { $0.rendering.minimumMouthAspect = 1.01 },
      { $0.rendering.minimumStrokeWidth = 0 }, { $0.rendering.highlight = -1 },
      { $0.rendering.shadow = 0.51 }, { $0.rendering.compactBelow = 257 },
      { $0.rendering.framesPerSecond = 24 }, { $0.motion.expressiveness = .infinity },
      { $0.transition.minimumReturnDuration = -1 },
    ]
    for change in changes {
      var p = try profile()
      change(&p)
      XCTAssertThrowsError(try p.compile())
    }
  }

  func testComponentsAreNonemptyUniqueAndOnlyActiveRegionsMayOverlap() throws {
    var p = try profile()
    p.components = []
    XCTAssertThrowsError(try p.compile())
    p = try profile()
    p.components.append(.eyes)
    XCTAssertThrowsError(try p.compile())
    p = try profile()
    p.layout.mouth = p.layout.eyes
    XCTAssertThrowsError(try p.compile())
    p.components.removeAll { $0 == .mouth }
    XCTAssertNoThrow(try p.compile())
  }

  func testAccessoriesValidateIdentityCountAndPlacement() throws {
    var p = try profile()
    p.accessories = [.recommended(.crown), .recommended(.crown)]
    XCTAssertThrowsError(try p.compile())
    p.accessories = (0..<17).map { n in
      var a = CharacterDesignAccessory.recommended(.badge)
      a.id = "badge-\(n)"
      return a
    }
    XCTAssertThrowsError(try p.compile())
    p.accessories = [.recommended(.halo)]
    p.accessories[0].width = 0
    XCTAssertThrowsError(try p.compile())
    p.accessories[0] = .recommended(.halo)
    p.accessories[0].opacity = 1.001
    XCTAssertThrowsError(try p.compile())
  }

  func testCompilationFreezesDraftAndInvalidDraftDoesNotMutateAppliedDesign() throws {
    var p = try profile()
    let applied = try p.compile()
    p.rendering.eyeScaleX = 1.4
    XCTAssertNotEqual(p, applied.profile)
    p.rendering.eyeScaleX = .nan
    XCTAssertThrowsError(try p.compile())
    XCTAssertEqual(applied, try CharacterDesign.load(.black))
  }

  func testContrastDiagnosticsAreWarningsNotAccessibilityCertification() throws {
    let white = try CharacterColor(red: 1, green: 1, blue: 1)
    let black = try CharacterColor(red: 0, green: 0, blue: 0)
    XCTAssertEqual(white.contrastRatio(with: black), 21, accuracy: 0.0001)
    XCTAssertEqual(white.contrastRatio(with: white), 1)
    var p = try profile()
    p.palettes.light.feature = p.palettes.light.surface
    let design = try p.compile()
    XCTAssertEqual(design.diagnostics.count, 1)
    XCTAssertEqual(design.diagnostics[0].path, "palettes.light.feature")
  }

  func testResolvedTokensUseDTCGColorObjectsAndNormalizedNumbers() throws {
    for appearance in CharacterDesignAppearance.allCases {
      let d = try CharacterDesign.load(.arcade)
      let tokens = try XCTUnwrap(
        JSONSerialization.jsonObject(with: d.encodedTokens(appearance: appearance))
          as? [String: Any])
      let colors = try XCTUnwrap(tokens["color"] as? [String: [String: Any]])
      XCTAssertEqual(colors.count, 8)
      XCTAssertEqual(colors["feature"]?["$type"] as? String, "color")
      let value = try XCTUnwrap(colors["feature"]?["$value"] as? [String: Any])
      XCTAssertEqual(value["colorSpace"] as? String, "srgb")
      let channels = try XCTUnwrap(value["components"] as? [Double])
      let feature = d.palette(for: appearance).feature
      XCTAssertEqual(channels.count, 3)
      // JSONSerialization bridges through decimal NSNumber text; compare numeric
      // meaning, not the final binary ULP of the decoded floating-point value.
      for (actual, expected) in zip(channels, [feature.red, feature.green, feature.blue]) {
        XCTAssertEqual(actual, expected, accuracy: 1e-14)
      }
      let geometry = try XCTUnwrap(tokens["geometry"] as? [String: [String: Any]])
      XCTAssertEqual(geometry["stroke"]?["$type"] as? String, "number")
      XCTAssertEqual(geometry["stroke"]?["$value"] as? Double, d.profile.rendering.lineWidth)
    }
  }
}

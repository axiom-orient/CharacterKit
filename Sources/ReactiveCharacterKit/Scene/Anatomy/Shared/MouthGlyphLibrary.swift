/// A deterministic vector atlas traced from the supplied 4×4 reference.
///
/// Each glyph uses a sixteen-point closed trace converted to sixteen cubic
/// segments. Immutable base geometry is cached once; sampling transforms only
/// the selected definition while preserving segment order for safe morphing.
enum MouthGlyphLibrary {
  static let segmentCount = 16

  private struct ReferenceAspectFrame {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
  }

  // Authored aspect calibration preserved from the original implementation.
  // These are NOT pixel bounds in the current master sheet. Runtime sprites
  // regenerate from that sheet; vector/raster perceptual alignment still needs
  // Apple-runtime visual qualification, especially for detached cheek marks.
  private static let referenceAspectFrames: [ReferenceAspectFrame] = [
    ReferenceAspectFrame(left: 41, top: 154, right: 181, bottom: 207),
    ReferenceAspectFrame(left: 281, top: 170, right: 379, bottom: 187),
    ReferenceAspectFrame(left: 459, top: 171, right: 572, bottom: 233),
    ReferenceAspectFrame(left: 652, top: 173, right: 780, bottom: 232),
    ReferenceAspectFrame(left: 46, top: 307, right: 175, bottom: 334),
    ReferenceAspectFrame(left: 250, top: 285, right: 396, bottom: 345),
    ReferenceAspectFrame(left: 468, top: 324, right: 581, bottom: 346),
    ReferenceAspectFrame(left: 706, top: 289, right: 735, bottom: 355),
    ReferenceAspectFrame(left: 43, top: 424, right: 174, bottom: 471),
    ReferenceAspectFrame(left: 271, top: 430, right: 357, bottom: 480),
    ReferenceAspectFrame(left: 471, top: 431, right: 554, bottom: 459),
    ReferenceAspectFrame(left: 679, top: 441, right: 761, bottom: 473),
    ReferenceAspectFrame(left: 60, top: 570, right: 148, bottom: 643),
    // The reference's r4c2 bbox also includes detached cheek marks.  The
    // vector intentionally places only the small U/oval mouth itself.
    ReferenceAspectFrame(left: 294, top: 585, right: 345, bottom: 637),
    ReferenceAspectFrame(left: 469, top: 576, right: 594, bottom: 645),
    ReferenceAspectFrame(left: 660, top: 576, right: 766, bottom: 633),
  ]

  private struct BaseDefinition: Sendable {
    let interior: CharacterMouthInterior
    let segments: [MouthCubicSegment]
    let details: [MouthDetailPath]
  }

  static func definition(
    for glyph: CharacterMouthGlyph,
    openness: Double = 1,
    width: Double = 1,
    curvature: Double = 0,
    skew: Double = 0
  ) -> MouthGlyphDefinition {
    let base = baseDefinition(for: glyph)
    let transform = pointTransform(
      for: glyph, openness: openness, width: width, curvature: curvature, skew: skew)
    return MouthGlyphDefinition(
      glyph: glyph,
      interior: base.interior,
      segments: base.segments.map { $0.mapped(transform) },
      details: base.details.map { detail in
        MouthDetailPath(
          kind: detail.kind,
          segments: detail.segments.map { $0.mapped(transform) },
          closed: detail.closed
        )
      }
    )
  }

  static func contour(
    for glyph: CharacterMouthGlyph,
    openness: Double,
    width: Double,
    curvature: Double,
    skew: Double
  ) -> [MouthCubicSegment] {
    let transform = pointTransform(
      for: glyph, openness: openness, width: width, curvature: curvature, skew: skew)
    return baseDefinition(for: glyph).segments.map { $0.mapped(transform) }
  }

  private static func pointTransform(
    for glyph: CharacterMouthGlyph, openness: Double, width: Double,
    curvature: Double, skew: Double
  ) -> (MouthVector) -> MouthVector {
    let open = bounded(openness)
    let xScale = min(max(finite(width), 0.18), 1.12)
    let heightScale = ribbon(glyph) ? 1 : 0.72 + open * 0.28
    return { point in
      var x = point.x * xScale
      var y = point.y * heightScale
      y += finite(curvature) * 0.018 * (1 - min(abs(point.x) * 1.8, 1))
      x += finite(skew) * 0.014 * (0.5 - abs(point.y))
      return MouthVector(x: x, y: y)
    }
  }

  /// The reference aspect is carried separately from the normalized contour.
  /// A normalized pucker and a normalized grin both span `[-0.5, 0.5]`, but
  /// their source bboxes are intentionally very different.  Keeping this
  /// metadata out of the path points preserves the authored vector proportions.
  /// Raster proportions use this same authored calibration, not decoded pixel bounds.
  static func intrinsicAspect(
    for glyph: CharacterMouthGlyph,
    openness: Double = 1,
    width: Double = 1
  ) -> Double {
    let frame = referenceAspectFrames[CharacterMouthGlyph.allCases.firstIndex(of: glyph)!]
    let referenceAspect = (frame.right - frame.left) / max(frame.bottom - frame.top, 0.000_001)
    let xScale = min(max(finite(width), 0.18), 1.12)
    let heightScale = ribbon(glyph) ? 1 : 0.72 + bounded(openness) * 0.28
    return max(referenceAspect * xScale / max(heightScale, 0.18), 0.05)
  }

  /// Returns centered scales that fit the intrinsic glyph aspect inside a
  /// renderer region.  One axis is letterboxed; neither axis is stretched.
  static func aspectFitScale(
    intrinsicAspect: Double,
    regionAspect: Double
  ) -> (x: Double, y: Double) {
    let glyphAspect = max(finite(intrinsicAspect), 0.05)
    let availableAspect = max(finite(regionAspect), 0.05)
    let ratio = glyphAspect / availableAspect
    if ratio < 1 {
      return (x: ratio, y: 1)
    }
    return (x: 1, y: 1 / ratio)
  }

  struct GlyphCycleSample: Sendable, Equatable {
    let glyph: CharacterMouthGlyph
    /// 0 is the shared base contour, 1 is the selected target contour.
    let targetAmount: Double
    /// Interior details fade independently so they cannot float in during a
    /// base crossing or read as a second mouth.
    let detailOpacity: Double
  }

  /// Selects a stable target plus an explicit base bridge for repeating
  /// expressive/communication cycles. Every target block contains a 170 ms
  /// build, a hold, a 62 ms return and a short neutral hold before the next
  /// target begins. This is deterministic from the layer clock and does not
  /// depend on an animation callback.
  static func cycleSample(
    emotion: CharacterEmotion?,
    expressionElapsed: Double,
    communication: CharacterCommunication,
    communicationElapsed: Double,
    reduceMotion: Bool
  ) -> GlyphCycleSample {
    if let emotion {
      switch emotion {
      case .joy:
        if reduceMotion { return stable(.wideToothyGrin) }
        return scheduled(
          [.toothyOpen, .openGrill, .wideToothyGrin],
          elapsed: expressionElapsed,
          durations: [0.20, 0.28, 0.38]
        )
      case .affection:
        if reduceMotion { return stable(.tongueDrop) }
        return scheduled(
          [.tongueDrop, .asymmetricSmirk],
          elapsed: expressionElapsed + 0.22,
          durations: [0.56, 0.74]
        )
      case .gratitude:
        if reduceMotion { return stable(.halfMoonTeeth) }
        return scheduled(
          [.halfMoonTeeth, .slantedOpen],
          elapsed: expressionElapsed + 0.08,
          durations: [0.58, 0.44]
        )
      case .interest:
        if reduceMotion { return stable(.slantedOpen) }
        return scheduled(
          [.slantedOpen, .speechWave],
          elapsed: expressionElapsed + 0.10,
          durations: [0.42, 0.36]
        )
      case .surprise:
        if reduceMotion { return stable(.puckerO) }
        return scheduled(
          [.puckerO, .smallYawn],
          elapsed: expressionElapsed,
          durations: [0.54, 0.42]
        )
      case .calmTrust:
        if reduceMotion { return stable(.baseFlat) }
        return scheduled(
          [.baseFlat, .halfMoonTeeth],
          elapsed: expressionElapsed + 0.18,
          durations: [0.78, 0.50]
        )
      case .sadness:
        if reduceMotion { return stable(.caretFrown) }
        return scheduled(
          [.downturnedArc, .caretFrown],
          elapsed: expressionElapsed,
          durations: [0.62, 1.18]
        )
      case .anxietyFear:
        if reduceMotion { return stable(.zigzag) }
        return scheduled(
          [.zigzag, .puckerO, .uneasyOpen],
          elapsed: expressionElapsed + 0.04,
          durations: [0.28, 0.30, 0.40]
        )
      case .angerIrritation:
        if reduceMotion { return stable(.clenchedWave) }
        return scheduled(
          [.clenchedWave, .openGrill],
          elapsed: expressionElapsed + 0.06,
          durations: [0.32, 0.28]
        )
      case .disgustContempt:
        if reduceMotion { return stable(.uneasyOpen) }
        return scheduled(
          [.uneasyOpen, .asymmetricSmirk],
          elapsed: expressionElapsed + 0.18,
          durations: [0.46, 0.62]
        )
      case .shameGuilt:
        if reduceMotion { return stable(.asymmetricSmirk) }
        return scheduled(
          [.downturnedArc, .asymmetricSmirk],
          elapsed: expressionElapsed + 0.12,
          durations: [0.72, 0.42]
        )
      case .fatigueBurden:
        if reduceMotion { return stable(.smallYawn) }
        return scheduled(
          [.baseFlat, .smallYawn],
          elapsed: expressionElapsed + 0.36,
          durations: [0.92, 0.76]
        )
      }
    }

    switch communication {
    case .silent, .listening: return stable(.baseFlat)
    case .chat, .voice:
      if reduceMotion { return stable(.speechWave) }
      return scheduled(
        [.speechWave, .slantedOpen, .puckerO],
        elapsed: communicationElapsed,
        durations: [0.36, 0.36, 0.36]
      )
    }
  }

  static func blend(
    from: [MouthCubicSegment],
    to: [MouthCubicSegment],
    amount: Double
  ) -> [MouthCubicSegment] {
    guard from.count == segmentCount, to.count == segmentCount else {
      return amount < 0.5 ? from : to
    }
    let t = min(max(amount, 0), 1)
    return zip(from, to).map { lhs, rhs in
      MouthCubicSegment(
        start: blend(lhs.start, rhs.start, amount: t),
        control1: blend(lhs.control1, rhs.control1, amount: t),
        control2: blend(lhs.control2, rhs.control2, amount: t),
        end: blend(lhs.end, rhs.end, amount: t)
      )
    }
  }

  private static func stable(_ glyph: CharacterMouthGlyph) -> GlyphCycleSample {
    GlyphCycleSample(glyph: glyph, targetAmount: 1, detailOpacity: 1)
  }

  private static func scheduled(
    _ targets: [CharacterMouthGlyph],
    elapsed: Double,
    durations: [Double]
  ) -> GlyphCycleSample {
    guard !targets.isEmpty, targets.count == durations.count else {
      return stable(.baseFlat)
    }
    let safeDurations = durations.map { max(finite($0), 0.22) }
    let total = safeDurations.reduce(0, +)
    let phase = positiveRemainder(elapsed, modulus: total)
    var offset = 0.0
    for index in targets.indices {
      let duration = safeDurations[index]
      let isLast = index == targets.index(before: targets.endIndex)
      guard phase < offset + duration || isLast else {
        offset += duration
        continue
      }

      let local = max(0, phase - offset)
      let buildDuration = min(0.17, duration - 0.045)
      let returnDuration = min(0.062, max(0.045, duration - buildDuration))
      let baseHoldDuration = min(0.04, max(0, duration - buildDuration - returnDuration))
      let returnStart = duration - returnDuration - baseHoldDuration

      if local < buildDuration {
        let progress = bounded(local / max(buildDuration, 0.000_001))
        let amount = easeOut(progress)
        return GlyphCycleSample(
          glyph: targets[index],
          targetAmount: amount,
          detailOpacity: smoothStep((amount - 0.58) / 0.42)
        )
      }
      if local < returnStart {
        return stable(targets[index])
      }
      if local < duration - baseHoldDuration {
        let progress = bounded((local - returnStart) / max(returnDuration, 0.000_001))
        return GlyphCycleSample(
          glyph: targets[index],
          targetAmount: 1 - smoothStep(progress),
          detailOpacity: 0
        )
      }
      return GlyphCycleSample(glyph: .baseFlat, targetAmount: 0, detailOpacity: 0)
    }
    return GlyphCycleSample(glyph: .baseFlat, targetAmount: 0, detailOpacity: 0)
  }

  private static func smoothStep(_ value: Double) -> Double {
    let t = bounded(value)
    return t * t * (3 - 2 * t)
  }

  private static func easeOut(_ value: Double) -> Double {
    let inverse = 1 - bounded(value)
    return 1 - inverse * inverse * inverse
  }

  // Immutable, finite vocabulary: build each trace and its details exactly once.
  private static let baseDefinitions: [CharacterMouthGlyph: BaseDefinition] = Dictionary(
    uniqueKeysWithValues: CharacterMouthGlyph.allCases.map { ($0, makeBaseDefinition(for: $0)) }
  )

  private static func baseDefinition(for glyph: CharacterMouthGlyph) -> BaseDefinition {
    // The table is exhaustively constructed from the same enum, not external data.
    baseDefinitions[glyph]!
  }

  private static func makeBaseDefinition(for glyph: CharacterMouthGlyph) -> BaseDefinition {
    switch glyph {
    case .slantedOpen:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph),
        details: [detail(.negativeOpening, oval: (-0.02, 0.04, 0.26, 0.07))])
    case .baseFlat:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph), details: [])
    case .toothyOpen:
      return BaseDefinition(
        interior: .teethAndTongue,
        segments: tracedSegments(for: glyph),
        details: toothRow(count: 4, y: (-0.22, 0.08), x: (-0.39, 0.39))
          + [detail(.tongue, ribbon: (-0.25, 0.25, 0.10, 0.28, 0.035))])
    case .tongueDrop:
      return BaseDefinition(
        interior: .tongue,
        segments: tracedSegments(for: glyph),
        details: [
          detail(.negativeOpening, oval: (0.00, 0.23, 0.23, 0.36)),
          detail(.tongue, oval: (0.00, 0.23, 0.08, 0.27)),
        ])
    case .zigzag:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph), details: [])
    case .clenchedWave:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph),
        details: [
          detail(.negativeOpening, band: (-0.44, 0.44, -0.20, -0.05, 0.022)),
          detail(.negativeOpening, band: (-0.44, 0.44, -0.08, 0.07, -0.018)),
          detail(.negativeOpening, band: (-0.44, 0.44, 0.04, 0.19, 0.020)),
        ])
    case .speechWave:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph), details: [])
    case .puckerO:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph),
        details: [detail(.negativeOpening, oval: (0.00, 0.00, 0.095, 0.22))])
    case .halfMoonTeeth:
      return BaseDefinition(
        interior: .teeth,
        segments: tracedSegments(for: glyph),
        details: [
          detail(.teeth, box: (-0.12, -0.08, -0.03, 0.04)),
          detail(.teeth, box: (0.03, -0.08, 0.12, 0.04)),
        ])
    case .uneasyOpen:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph),
        details: [
          detail(.negativeOpening, oval: (0.00, 0.03, 0.27, 0.13)),
          detail(.tongue, oval: (0.07, 0.16, 0.14, 0.12)),
          detail(.innerLine, curve: (-0.19, -0.02, -0.04, -0.08, 0.12, -0.04, 0.22, -0.07)),
        ])
    case .downturnedArc:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph), details: [])
    case .asymmetricSmirk:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph), details: [])
    case .openGrill:
      return BaseDefinition(
        interior: .teethAndTongue,
        segments: tracedSegments(for: glyph),
        details: toothRow(count: 5, y: (-0.28, 0.16), x: (-0.45, 0.45))
          + [detail(.tongue, ribbon: (-0.27, 0.27, 0.12, 0.30, 0.04))])
    case .smallYawn:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph),
        details: [detail(.negativeOpening, oval: (0.00, 0.08, 0.16, 0.27))])
    case .wideToothyGrin:
      return BaseDefinition(
        interior: .teethAndTongue,
        segments: tracedSegments(for: glyph),
        details: toothRow(count: 6, y: (-0.29, 0.18), x: (-0.47, 0.47))
          + [detail(.tongue, ribbon: (-0.30, 0.30, 0.14, 0.27, 0.035))])
    case .caretFrown:
      return BaseDefinition(
        interior: .none,
        segments: tracedSegments(for: glyph), details: [])
    }
  }

  /// Offline trace payload generated from the supplied raster during visual QA.
  /// The master sheet stays offline; extracted reference sprites are shipped separately. Catmull–Rom
  /// tangents are converted to cubic controls so every glyph remains a
  /// closed, 16-segment contour with the same point ordering contract.
  private static func tracedSegments(for glyph: CharacterMouthGlyph) -> [MouthCubicSegment] {
    let points: [MouthVector]
    switch glyph {
    case .slantedOpen:
      points = [
        MouthVector(x: -0.5000, y: -0.5000),
        MouthVector(x: -0.3346, y: -0.4608),
        MouthVector(x: -0.1764, y: -0.4020),
        MouthVector(x: -0.0110, y: -0.3627),
        MouthVector(x: 0.1618, y: -0.3431),
        MouthVector(x: 0.3346, y: -0.3235),
        MouthVector(x: 0.5000, y: -0.3235),
        MouthVector(x: 0.4260, y: -0.2059),
        MouthVector(x: 0.3263, y: 0.0098),
        MouthVector(x: 0.2267, y: 0.2255),
        MouthVector(x: 0.1124, y: 0.4020),
        MouthVector(x: -0.0311, y: 0.5000),
        MouthVector(x: -0.1965, y: 0.5000),
        MouthVector(x: -0.3254, y: 0.3627),
        MouthVector(x: -0.4122, y: 0.1127),
        MouthVector(x: -0.4488, y: -0.1544),
      ]
    case .baseFlat:
      points = [
        MouthVector(x: -0.5000, y: -0.5000),
        MouthVector(x: -0.3575, y: -0.4375),
        MouthVector(x: -0.2258, y: -0.3125),
        MouthVector(x: -0.0941, y: -0.1875),
        MouthVector(x: 0.0376, y: -0.0625),
        MouthVector(x: 0.1801, y: 0.0000),
        MouthVector(x: 0.3226, y: 0.0625),
        MouthVector(x: 0.4651, y: 0.1250),
        MouthVector(x: 0.5000, y: 0.4375),
        MouthVector(x: 0.3575, y: 0.5000),
        MouthVector(x: 0.2258, y: 0.3750),
        MouthVector(x: 0.0833, y: 0.3125),
        MouthVector(x: -0.0484, y: 0.1875),
        MouthVector(x: -0.1801, y: 0.0625),
        MouthVector(x: -0.3226, y: 0.0000),
        MouthVector(x: -0.4543, y: -0.1250),
      ]
    case .toothyOpen:
      points = [
        MouthVector(x: -0.4781, y: -0.5000),
        MouthVector(x: -0.3062, y: -0.4508),
        MouthVector(x: -0.1251, y: -0.4180),
        MouthVector(x: 0.0744, y: -0.4180),
        MouthVector(x: 0.2739, y: -0.4180),
        MouthVector(x: 0.4735, y: -0.4180),
        MouthVector(x: 0.5000, y: -0.2090),
        MouthVector(x: 0.4446, y: 0.0471),
        MouthVector(x: 0.3708, y: 0.2705),
        MouthVector(x: 0.2543, y: 0.4180),
        MouthVector(x: 0.1009, y: 0.5000),
        MouthVector(x: -0.0986, y: 0.5000),
        MouthVector(x: -0.2566, y: 0.4262),
        MouthVector(x: -0.3766, y: 0.2848),
        MouthVector(x: -0.4596, y: 0.0779),
        MouthVector(x: -0.5000, y: -0.2049),
      ]
    case .tongueDrop:
      points = [
        MouthVector(x: -0.5000, y: -0.5000),
        MouthVector(x: -0.3396, y: -0.4310),
        MouthVector(x: -0.1634, y: -0.3966),
        MouthVector(x: 0.0207, y: -0.4138),
        MouthVector(x: 0.2047, y: -0.4310),
        MouthVector(x: 0.3809, y: -0.4655),
        MouthVector(x: 0.5000, y: -0.4095),
        MouthVector(x: 0.3691, y: -0.3793),
        MouthVector(x: 0.2559, y: -0.2069),
        MouthVector(x: 0.2323, y: 0.1616),
        MouthVector(x: 0.1535, y: 0.4095),
        MouthVector(x: 0.0030, y: 0.5000),
        MouthVector(x: -0.1496, y: 0.4138),
        MouthVector(x: -0.2402, y: 0.1918),
        MouthVector(x: -0.3031, y: -0.0905),
        MouthVector(x: -0.3789, y: -0.3448),
      ]
    case .zigzag:
      points = [
        MouthVector(x: -0.4833, y: -0.5000),
        MouthVector(x: -0.3417, y: 0.0000),
        MouthVector(x: -0.1917, y: -0.3846),
        MouthVector(x: -0.0667, y: -0.0385),
        MouthVector(x: 0.0667, y: 0.0385),
        MouthVector(x: 0.2167, y: -0.1923),
        MouthVector(x: 0.3333, y: 0.1923),
        MouthVector(x: 0.4667, y: -0.1923),
        MouthVector(x: 0.5000, y: 0.5000),
        MouthVector(x: 0.3750, y: 0.3077),
        MouthVector(x: 0.2417, y: 0.0769),
        MouthVector(x: 0.0833, y: 0.3462),
        MouthVector(x: -0.0667, y: 0.2692),
        MouthVector(x: -0.2167, y: -0.0385),
        MouthVector(x: -0.3750, y: 0.2308),
        MouthVector(x: -0.5000, y: 0.1154),
      ]
    case .clenchedWave:
      points = [
        MouthVector(x: -0.3662, y: -0.5000),
        MouthVector(x: -0.2227, y: -0.3621),
        MouthVector(x: -0.0440, y: -0.3103),
        MouthVector(x: 0.0995, y: -0.4483),
        MouthVector(x: 0.2852, y: -0.4828),
        MouthVector(x: 0.4296, y: -0.3470),
        MouthVector(x: 0.5000, y: -0.0302),
        MouthVector(x: 0.4463, y: 0.3276),
        MouthVector(x: 0.3169, y: 0.5000),
        MouthVector(x: 0.1523, y: 0.4828),
        MouthVector(x: 0.0229, y: 0.3103),
        MouthVector(x: -0.1347, y: 0.2759),
        MouthVector(x: -0.2711, y: 0.4310),
        MouthVector(x: -0.4428, y: 0.3966),
        MouthVector(x: -0.5000, y: 0.1509),
        MouthVector(x: -0.4789, y: -0.2866),
      ]
    case .speechWave:
      points = [
        MouthVector(x: -0.4433, y: -0.5000),
        MouthVector(x: -0.3005, y: -0.1500),
        MouthVector(x: -0.1482, y: 0.0500),
        MouthVector(x: -0.0148, y: -0.3500),
        MouthVector(x: 0.1092, y: 0.1000),
        MouthVector(x: 0.2426, y: -0.1000),
        MouthVector(x: 0.3855, y: -0.2500),
        MouthVector(x: 0.5000, y: -0.3500),
        MouthVector(x: 0.4634, y: 0.2500),
        MouthVector(x: 0.3205, y: 0.0000),
        MouthVector(x: 0.2060, y: 0.5000),
        MouthVector(x: 0.0632, y: 0.2500),
        MouthVector(x: -0.0891, y: 0.1500),
        MouthVector(x: -0.2355, y: 0.4187),
        MouthVector(x: -0.3560, y: -0.0500),
        MouthVector(x: -0.5000, y: -0.0062),
      ]
    case .puckerO:
      points = [
        MouthVector(x: -0.2500, y: -0.5000),
        MouthVector(x: 0.2143, y: -0.4609),
        MouthVector(x: 0.1786, y: -0.3594),
        MouthVector(x: -0.1429, y: -0.3828),
        MouthVector(x: 0.1429, y: -0.2969),
        MouthVector(x: 0.1786, y: -0.1328),
        MouthVector(x: 0.4286, y: 0.0000),
        MouthVector(x: 0.5000, y: 0.2109),
        MouthVector(x: 0.3214, y: 0.3750),
        MouthVector(x: 0.0536, y: 0.5000),
        MouthVector(x: -0.3571, y: 0.4688),
        MouthVector(x: -0.5000, y: 0.2891),
        MouthVector(x: -0.4286, y: 0.0781),
        MouthVector(x: -0.2857, y: -0.1016),
        MouthVector(x: -0.1071, y: -0.2344),
        MouthVector(x: -0.4286, y: -0.3359),
      ]
    case .halfMoonTeeth:
      points = [
        MouthVector(x: -0.5000, y: -0.5000),
        MouthVector(x: -0.3548, y: -0.3910),
        MouthVector(x: -0.2157, y: -0.2660),
        MouthVector(x: -0.0373, y: -0.2447),
        MouthVector(x: 0.1331, y: -0.2872),
        MouthVector(x: 0.3115, y: -0.3085),
        MouthVector(x: 0.4597, y: -0.4096),
        MouthVector(x: 0.5000, y: -0.2048),
        MouthVector(x: 0.4194, y: 0.0745),
        MouthVector(x: 0.3135, y: 0.2872),
        MouthVector(x: 0.1835, y: 0.4362),
        MouthVector(x: 0.0212, y: 0.5000),
        MouthVector(x: -0.1371, y: 0.4255),
        MouthVector(x: -0.2631, y: 0.2660),
        MouthVector(x: -0.3528, y: 0.0106),
        MouthVector(x: -0.4345, y: -0.2660),
      ]
    case .uneasyOpen:
      points = [
        MouthVector(x: -0.3095, y: -0.5000),
        MouthVector(x: -0.1577, y: -0.4000),
        MouthVector(x: 0.0060, y: -0.4000),
        MouthVector(x: 0.1696, y: -0.4800),
        MouthVector(x: 0.3571, y: -0.4400),
        MouthVector(x: 0.4643, y: -0.2650),
        MouthVector(x: 0.5000, y: 0.0300),
        MouthVector(x: 0.4286, y: 0.2650),
        MouthVector(x: 0.3095, y: 0.4200),
        MouthVector(x: 0.1458, y: 0.5000),
        MouthVector(x: -0.0238, y: 0.4300),
        MouthVector(x: -0.1935, y: 0.3600),
        MouthVector(x: -0.3810, y: 0.4000),
        MouthVector(x: -0.4762, y: 0.2050),
        MouthVector(x: -0.5000, y: -0.1100),
        MouthVector(x: -0.4256, y: -0.3400),
      ]
    case .downturnedArc:
      points = [
        MouthVector(x: -0.0935, y: -0.5000),
        MouthVector(x: 0.1081, y: -0.4643),
        MouthVector(x: 0.2581, y: -0.2857),
        MouthVector(x: 0.3823, y: -0.0357),
        MouthVector(x: 0.5000, y: 0.2321),
        MouthVector(x: 0.4339, y: 0.4286),
        MouthVector(x: 0.3323, y: 0.1161),
        MouthVector(x: 0.2032, y: -0.1205),
        MouthVector(x: 0.0484, y: -0.2857),
        MouthVector(x: -0.1403, y: -0.2857),
        MouthVector(x: -0.2742, y: -0.0625),
        MouthVector(x: -0.3516, y: 0.3170),
        MouthVector(x: -0.5000, y: 0.5000),
        MouthVector(x: -0.4935, y: 0.1741),
        MouthVector(x: -0.3935, y: -0.1429),
        MouthVector(x: -0.2565, y: -0.3571),
      ]
    case .asymmetricSmirk:
      points = [
        MouthVector(x: -0.5000, y: -0.5000),
        MouthVector(x: -0.3984, y: -0.2097),
        MouthVector(x: -0.2969, y: 0.0806),
        MouthVector(x: -0.1578, y: 0.2742),
        MouthVector(x: 0.0312, y: 0.3387),
        MouthVector(x: 0.1828, y: 0.1774),
        MouthVector(x: 0.3094, y: -0.0484),
        MouthVector(x: 0.4250, y: -0.3024),
        MouthVector(x: 0.5000, y: -0.3387),
        MouthVector(x: 0.4234, y: 0.0161),
        MouthVector(x: 0.3094, y: 0.2742),
        MouthVector(x: 0.1578, y: 0.4355),
        MouthVector(x: -0.0312, y: 0.5000),
        MouthVector(x: -0.2078, y: 0.4032),
        MouthVector(x: -0.3500, y: 0.2177),
        MouthVector(x: -0.4625, y: -0.0444),
      ]
    case .openGrill:
      points = [
        MouthVector(x: 0.2816, y: -0.5000),
        MouthVector(x: 0.5000, y: -0.4877),
        MouthVector(x: 0.4885, y: -0.2218),
        MouthVector(x: 0.4885, y: 0.0581),
        MouthVector(x: 0.4253, y: 0.2606),
        MouthVector(x: 0.3161, y: 0.4067),
        MouthVector(x: 0.1638, y: 0.5000),
        MouthVector(x: -0.0532, y: 0.4859),
        MouthVector(x: -0.2126, y: 0.4014),
        MouthVector(x: -0.3391, y: 0.2764),
        MouthVector(x: -0.4310, y: 0.1092),
        MouthVector(x: -0.4770, y: -0.1144),
        MouthVector(x: -0.5000, y: -0.3662),
        MouthVector(x: -0.3807, y: -0.4718),
        MouthVector(x: -0.1523, y: -0.4718),
        MouthVector(x: 0.0761, y: -0.4718),
      ]
    case .smallYawn:
      points = [
        MouthVector(x: -0.2330, y: -0.5000),
        MouthVector(x: -0.0423, y: -0.4526),
        MouthVector(x: 0.0889, y: -0.3289),
        MouthVector(x: 0.1675, y: -0.1379),
        MouthVector(x: 0.2391, y: 0.0622),
        MouthVector(x: 0.2819, y: 0.2990),
        MouthVector(x: 0.3702, y: 0.4777),
        MouthVector(x: 0.5000, y: 0.4784),
        MouthVector(x: 0.2724, y: 0.4838),
        MouthVector(x: 0.0447, y: 0.4892),
        MouthVector(x: -0.1829, y: 0.4946),
        MouthVector(x: -0.4106, y: 0.5000),
        MouthVector(x: -0.5000, y: 0.3250),
        MouthVector(x: -0.5000, y: 0.0332),
        MouthVector(x: -0.4428, y: -0.1853),
        MouthVector(x: -0.3653, y: -0.3778),
      ]
    case .wideToothyGrin:
      points = [
        MouthVector(x: -0.5000, y: -0.5000),
        MouthVector(x: -0.3517, y: -0.3824),
        MouthVector(x: -0.2119, y: -0.2500),
        MouthVector(x: -0.0381, y: -0.1765),
        MouthVector(x: 0.1695, y: -0.1618),
        MouthVector(x: 0.3602, y: -0.2059),
        MouthVector(x: 0.5000, y: -0.3382),
        MouthVector(x: 0.4915, y: -0.1250),
        MouthVector(x: 0.4068, y: 0.1029),
        MouthVector(x: 0.3136, y: 0.3162),
        MouthVector(x: 0.1864, y: 0.4706),
        MouthVector(x: 0.0042, y: 0.5000),
        MouthVector(x: -0.1610, y: 0.4118),
        MouthVector(x: -0.2839, y: 0.2500),
        MouthVector(x: -0.3814, y: 0.0441),
        MouthVector(x: -0.4576, y: -0.1985),
      ]
    case .caretFrown:
      points = [
        MouthVector(x: 0.1211, y: -0.5000),
        MouthVector(x: 0.2632, y: -0.2876),
        MouthVector(x: 0.3842, y: -0.0398),
        MouthVector(x: 0.5000, y: 0.2168),
        MouthVector(x: 0.4789, y: 0.3850),
        MouthVector(x: 0.3789, y: 0.1018),
        MouthVector(x: 0.2579, y: -0.1460),
        MouthVector(x: 0.1000, y: -0.2788),
        MouthVector(x: -0.0579, y: -0.0929),
        MouthVector(x: -0.2000, y: 0.1195),
        MouthVector(x: -0.3421, y: 0.3319),
        MouthVector(x: -0.5000, y: 0.5000),
        MouthVector(x: -0.4684, y: 0.3142),
        MouthVector(x: -0.3211, y: 0.1106),
        MouthVector(x: -0.1737, y: -0.0929),
        MouthVector(x: -0.0263, y: -0.2965),
      ]
    }
    precondition(points.count == segmentCount, "Every built-in mouth trace must contain 16 points")
    let count = points.count
    return points.indices.map { index in
      let previous = points[(index + count - 1) % count]
      let start = points[index]
      let end = points[(index + 1) % count]
      let next = points[(index + 2) % count]
      let control1 = MouthVector(
        x: start.x + (end.x - previous.x) / 6,
        y: start.y + (end.y - previous.y) / 6
      )
      let control2 = MouthVector(
        x: end.x - (next.x - start.x) / 6,
        y: end.y - (next.y - start.y) / 6
      )
      return MouthCubicSegment(start: start, control1: control1, control2: control2, end: end)
    }
  }
  private static func edge(
    _ sx: Double, _ sy: Double,
    _ c1x: Double, _ c1y: Double,
    _ c2x: Double, _ c2y: Double,
    _ ex: Double, _ ey: Double
  ) -> MouthCubicSegment {
    MouthCubicSegment(
      start: MouthVector(x: sx, y: sy),
      control1: MouthVector(x: c1x, y: c1y),
      control2: MouthVector(x: c2x, y: c2y),
      end: MouthVector(x: ex, y: ey)
    )
  }

  private static func detail(
    _ kind: MouthDetailKind,
    box: (Double, Double, Double, Double)
  ) -> MouthDetailPath {
    let (left, top, right, bottom) = box
    let radius = min(min(right - left, bottom - top) * 0.24, 0.035)
    return MouthDetailPath(
      kind: kind,
      segments: [
        edge(
          left + radius, top, right - radius, top, right - radius * 0.45, top, right, top + radius),
        edge(
          right, top + radius, right, bottom - radius, right, bottom - radius * 0.45,
          right - radius, bottom),
        edge(
          right - radius, bottom, left + radius, bottom, left + radius * 0.45, bottom, left,
          bottom - radius),
        edge(
          left, bottom - radius, left, top + radius, left, top + radius * 0.45, left + radius, top),
      ],
      closed: true
    )
  }

  private static func detail(
    _ kind: MouthDetailKind,
    oval: (Double, Double, Double, Double)
  ) -> MouthDetailPath {
    let (cx, cy, rx, ry) = oval
    let k = 0.5522848
    return MouthDetailPath(
      kind: kind,
      segments: [
        edge(cx, cy - ry, cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy),
        edge(cx + rx, cy, cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry),
        edge(cx, cy + ry, cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy),
        edge(cx - rx, cy, cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry),
      ],
      closed: true
    )
  }

  private static func detail(
    _ kind: MouthDetailKind,
    ribbon: (Double, Double, Double, Double, Double)
  ) -> MouthDetailPath {
    let (left, right, top, bottom, arch) = ribbon
    let span = right - left
    return MouthDetailPath(
      kind: kind,
      segments: [
        edge(
          left, top, left + span * 0.28, top + arch, right - span * 0.28, top + arch, right, top),
        edge(
          right, top, right, bottom - arch, right - span * 0.18, bottom, right - span * 0.06, bottom
        ),
        edge(
          right - span * 0.06, bottom, left + span * 0.18, bottom + arch, left + span * 0.18,
          bottom + arch, left, top),
        edge(left, top, left, top, left, top, left, top),
      ],
      closed: true
    )
  }

  private static func detail(
    _ kind: MouthDetailKind,
    band: (Double, Double, Double, Double, Double)
  ) -> MouthDetailPath {
    let (left, right, top, bottom, wave) = band
    let span = right - left
    return MouthDetailPath(
      kind: kind,
      segments: [
        edge(
          left, top, left + span * 0.28, top + wave, right - span * 0.28, top + wave, right, top),
        edge(right, top, right, bottom, right, bottom, right - span * 0.06, bottom),
        edge(
          right - span * 0.06, bottom, left + span * 0.18, bottom - wave, left + span * 0.18,
          bottom - wave, left, bottom),
        edge(left, bottom, left, top, left, top, left, top),
      ],
      closed: true
    )
  }

  private static func detail(
    _ kind: MouthDetailKind,
    curve: (Double, Double, Double, Double, Double, Double, Double, Double)
  ) -> MouthDetailPath {
    let (sx, sy, c1x, c1y, c2x, c2y, ex, ey) = curve
    return MouthDetailPath(
      kind: kind,
      segments: [edge(sx, sy, c1x, c1y, c2x, c2y, ex, ey)],
      closed: false
    )
  }

  private static func toothRow(
    count: Int,
    y: (Double, Double),
    x: (Double, Double)
  ) -> [MouthDetailPath] {
    guard count > 0 else { return [] }
    let spacing = (x.1 - x.0) / Double(count)
    return (0..<count).map { index in
      let left = x.0 + Double(index) * spacing + spacing * 0.11
      let right = x.0 + Double(index + 1) * spacing - spacing * 0.11
      let edgeBias = abs(Double(index) - Double(count - 1) * 0.5) / max(Double(count), 1)
      let top = y.0 + edgeBias * 0.028
      let bottom = y.1 - (1 - edgeBias) * 0.012
      return detail(.teeth, box: (left, top, right, bottom))
    }
  }

  private static func ribbon(_ glyph: CharacterMouthGlyph) -> Bool {
    switch glyph {
    case .baseFlat, .zigzag, .clenchedWave, .speechWave, .downturnedArc,
      .asymmetricSmirk, .caretFrown:
      true
    default:
      false
    }
  }

  private static func blend(_ lhs: MouthVector, _ rhs: MouthVector, amount: Double) -> MouthVector {
    MouthVector(
      x: lhs.x + (rhs.x - lhs.x) * amount,
      y: lhs.y + (rhs.y - lhs.y) * amount
    )
  }

  private static func bounded(_ value: Double) -> Double {
    min(max(finite(value), 0), 1)
  }

  private static func finite(_ value: Double) -> Double {
    precondition(value.isFinite, "mouth geometry input must be finite")
    return value
  }

  private static func positiveRemainder(_ value: Double, modulus: Double) -> Double {
    precondition(value.isFinite && modulus.isFinite && modulus > 0)
    let result = value.truncatingRemainder(dividingBy: modulus)
    return result >= 0 ? result : result + modulus
  }

}

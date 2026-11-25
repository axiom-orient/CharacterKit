#if os(iOS) || os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ReactiveCharacterKit

@MainActor
struct CharacterFullBodyCatNativeTests {
  @Test(arguments: CharacterFullBodyCatArtwork.assets)
  func allRegisteredFeltLayersRetainHighResolutionAlpha(_ asset: CharacterImageAsset) throws {
    let png = try CharacterImageResources.png(asset)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 1024 && image.height == 1024, "\(asset.name) is \(image.width)×\(image.height)")
    #expect([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo))
  }

  @Test(arguments: CharacterFullBodyCatStyle.allCases, CharacterFullBodyCatPose.allCases)
  func nativeFrameHasAnOpaqueCharacterAndTransparentViewportEdges(
    _ style: CharacterFullBodyCatStyle, _ rest: CharacterFullBodyCatPose
  ) throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let scene = try CharacterSceneBuilder.scene(
      pose: pose, fullBodyCat: .init(pose: rest, style: style), width: 92, height: 92, reduceMotion: true)
    #expect(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene).isEmpty)

    let image = try nativeImage(for: scene)
    #expect(image.width == 184)
    #expect(image.height == 184)
    let pixels = try alphaSamples(image)
    #expect(pixels.filter { $0 == 255 }.count > 1_000)
    #expect(pixels.prefix(image.width).allSatisfy { $0 == 0 })
    #expect(pixels.suffix(image.width).allSatisfy { $0 == 0 })
    for row in 0..<image.height {
      #expect(pixels[row * image.width] == 0)
      #expect(pixels[row * image.width + image.width - 1] == 0)
    }

    let samples: [CharacterVectorPoint]
    switch style {
    case .felt:
      let face = CharacterFullBodyCatArtwork.resolve(rest).face
      samples = [face?.left?.center, face?.right?.center, face?.muzzle?.junction].compactMap { $0 }
    case .crayon:
      let face = CharacterCrayonCatGeometry.resolve(rest).face
      samples = [face?.left?.center, face?.right?.center, face?.muzzle?.junction].compactMap { $0 }
    }
    if !samples.isEmpty {
      let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
      for point in samples {
        let (x, y) = pixel(at: point, transform: body.transform)
        try #require((0..<image.width).contains(x) && (0..<image.height).contains(y))
        #expect(pixels[y * image.width + x] == 255, "\(rest) face at \(x), \(y)")
      }
    }
  }

  @Test
  func crayonWaveHasAConnectedOpaqueSilhouetteThroughThePawHandoff() throws {
    let cat = CharacterFullBodyCatAppearance(action: .wave, style: .crayon)
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    func alpha(at time: Double) throws -> [UInt8] {
      let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: cat,
        width: 128, height: 128, elapsed: 0, actionElapsed: time)
      return try alphaSamples(nativeImage(for: scene))
    }

    let standing = try alpha(at: 0)
    let halfway = try alpha(at: 0.20)
    let entering = try alpha(at: 0.400)
    let waving = try alpha(at: 0.410)
    #expect(silhouetteOverlap(standing, halfway) < 0.95)
    #expect(silhouetteOverlap(halfway, waving) > 0.70)
    #expect(silhouetteOverlap(entering, waving) > 0.93)
    #expect(halfway.filter { $0 == 255 }.count > 2_000)
    #expect(halfway.prefix(256).allSatisfy { $0 == 0 })
    #expect(halfway.suffix(256).allSatisfy { $0 == 0 })
  }

  @Test
  func crayonRaisedForepawStaysShortAndDrawsFromBehindTheShoulder() throws {
    let cat = CharacterFullBodyCatAppearance(action: .wave, style: .crayon)
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    for time in [0.15, 0.20, 0.45, 1.20] {
      let scene = try CharacterSceneBuilder.scene(
        pose: face, fullBodyCat: cat, width: 256, height: 256, elapsed: 0, actionElapsed: time)
      let pawIndex = try #require(scene.nodes.firstIndex { $0.id == "full-body-cat.paw.wave" })
      let torsoIndex = try #require(scene.nodes.firstIndex { $0.id == "full-body-cat.body" })
      #expect(pawIndex < torsoIndex)

      let paw = scene.nodes[pawIndex]
      let contour = paw.path.commands
      try #require(contour.count == 6)
      guard case .move(let shoulderEdge) = contour[0],
        case .cubic(_, _, let toeEdge) = contour[1],
        case .cubic(_, _, let otherToeEdge) = contour[2],
        case .cubic(_, _, let otherShoulderEdge) = contour[3]
      else {
        Issue.record("Unexpected raised forepaw contour at \(time)s")
        return
      }
      let reach = hypot((toeEdge.x + otherToeEdge.x - shoulderEdge.x - otherShoulderEdge.x) / 2,
                        (toeEdge.y + otherToeEdge.y - shoulderEdge.y - otherShoulderEdge.y) / 2)
      #expect(reach < 63, "forepaw stretched to \(reach) points at \(time)s")
      if time == 0.45 {
        let toes = try #require(scene.nodes.first { $0.id == "full-body-cat.paw.wave.toes" })
        #expect(toes.clips == [paw.path])
        #expect(toes.transform == paw.transform)
      }

      let path = CharacterSceneCanvasRenderer.path(paw.path).cgPath
      let bounds = path.boundingBoxOfPath.integral
      let fillArea = (Int(bounds.minY)..<Int(bounds.maxY)).reduce(0) { area, y in
        area + (Int(bounds.minX)..<Int(bounds.maxX)).count { x in
          path.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
        }
      }
      #expect(fillArea > 700, "forepaw pinched at \(time)s")
    }
  }

  @Test
  func crayonRearTurnRevealsTheFarForepawFromTheTorso() throws {
    let cat = CharacterFullBodyCatAppearance(pose: .rear, action: .startle, style: .crayon, puffDirection: .right)
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    for elapsed in [0.05, 0.10, 0.15, 0.20] {
      let scene = try CharacterSceneBuilder.scene(
        pose: face, fullBodyCat: cat, width: 84, height: 84, elapsed: elapsed, actionElapsed: elapsed)
      let frame = try nativeImage(for: scene)
      let regions = silhouetteRegions(try alphaSamples(frame), width: frame.width)
      #expect(regions.filter { $0 > 6 }.count == 1, "rear-to-right-puff at \(elapsed)s")
    }
  }

  @Test(arguments: [CharacterFullBodyCatFacing.left, .right])
  func crayonBristlesShiverWithThePawsStillOnTheFloor(_ facing: CharacterFullBodyCatFacing) throws {
    let cat = CharacterFullBodyCatAppearance(action: .startle, style: .crayon, puffDirection: facing)
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    var soles: [Int] = []
    for tick in 16...36 {
      let frameTime = Double(tick) / 60
      let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: cat,
        width: 84, height: 84, elapsed: frameTime, actionElapsed: frameTime)
      let frame = try nativeImage(for: scene)
      let alpha = try alphaSamples(frame)
      let pad = try #require(alpha.lastIndex(where: { $0 >= 128 }))
      soles.append(pad / frame.width)
      #expect(silhouetteRegions(alpha, width: frame.width).filter { $0 >= 8 }.count == 1)
    }
    let high = try #require(soles.min())
    let low = try #require(soles.max())
    #expect(low - high <= 1)
  }

  @Test
  func renderedFeltPuffSharesArtworkAcrossDirectionsAndKeepsGazeAndSpeechLive() throws {
    let left = CharacterFullBodyCatAppearance(pose: .puffed)
    let right = CharacterFullBodyCatAppearance(pose: .puffed, puffDirection: .right)
    func scene(_ look: CharacterPose, appearance: CharacterFullBodyCatAppearance) throws -> CharacterScene {
      try CharacterSceneBuilder.scene(
        pose: look, fullBodyCat: appearance, width: 128, height: 128, reduceMotion: true)
    }

    let neutral = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let leftScene = try scene(neutral, appearance: left)
    let rightScene = try scene(neutral, appearance: right)
    let leftImages = leftScene.nodes.compactMap(\.image)
    let rightImages = rightScene.nodes.compactMap(\.image)
    #expect(leftImages.count == 1 && leftImages == rightImages)
    #expect(leftImages.first?.asset.name == "full-body-cat-puff")
    #expect(leftScene.faceBounds.rect.midX < 64 && rightScene.faceBounds.rect.midX > 64)
    #expect(leftScene.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") }.map(\.id) == ["full-body-cat.eye.right"])
    #expect(rightScene.nodes.filter { $0.id.hasPrefix("full-body-cat.eye.") }.map(\.id) == ["full-body-cat.eye.left"])

    let leftImage = try nativeImage(for: leftScene)
    let leftAlpha = try alphaSamples(leftImage)
    let rightImage = try nativeImage(for: rightScene)
    let rightAlpha = try alphaSamples(rightImage)
    let width = rightImage.width
    let mirroredLeftAlpha = (0..<leftImage.height).flatMap { row in
      Array(leftAlpha[(row * width)..<((row + 1) * width)].reversed())
    }
    #expect(silhouetteOverlap(mirroredLeftAlpha, rightAlpha) > 0.99)
    #expect(rightAlpha.prefix(width).allSatisfy { $0 == 0 })
    #expect(rightAlpha.suffix(width).allSatisfy { $0 == 0 })
    for row in 0..<rightImage.height {
      #expect(rightAlpha[row * width] == 0 && rightAlpha[(row + 1) * width - 1] == 0)
    }

    func rightEyeX(focusX: Double) throws -> Int {
      let point = try CharacterPoint(validatingX: focusX, y: 0.5)
      let state = ReactiveCharacter.reduce(state: .idle, event: .attentionFocused(point)).state
      let look = ReactiveCharacter.pose(state: state, elapsed: 0, reduceMotion: true, projection: .flat)
      let focusedScene = try scene(look, appearance: right)
      let eye = try #require(focusedScene.nodes.first { $0.id == "full-body-cat.eye.left" })
      let bounds = CharacterSceneCanvasRenderer.path(eye.path).boundingRect
      let (x, _) = pixel(at: .init(x: bounds.midX, y: bounds.midY), transform: eye.transform)
      return x
    }
    let lookLeft = try rightEyeX(focusX: 0.05)
    let lookRight = try rightEyeX(focusX: 0.95)
    #expect(lookRight > lookLeft)

    let state = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state
    let speaking = ReactiveCharacter.pose(state: state, elapsed: 0.5, projection: .flat)
    let closed = try scene(speaking.applyingSpeechArticulation(.closed), appearance: right)
    let open = try scene(speaking.applyingSpeechArticulation(.open), appearance: right)
    let closedMouth = try #require(closed.nodes.first { $0.id == "full-body-cat.mouth" })
    let openMouth = try #require(open.nodes.first { $0.id == closedMouth.id })
    #expect(openMouth.path != closedMouth.path)
    let closedPixels = try rgbaSamples(nativeImage(for: closed))
    let openPixels = try rgbaSamples(nativeImage(for: open))
    #expect(stride(from: 3, to: closedPixels.count, by: 4).allSatisfy { closedPixels[$0] == openPixels[$0] })
    #expect(stride(from: 0, to: closedPixels.count, by: 4).filter {
      visiblyDifferentColor(closedPixels, openPixels, at: $0)
    }.count > 8)
  }

  @Test(arguments: [CharacterFullBodyCatAction?.none, .wave, .walk])
  func feltSilhouetteStaysConnectedThroughoutTheGesture(_ action: CharacterFullBodyCatAction?) throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let appearance = CharacterFullBodyCatAppearance(action: action, style: .felt)
    for fraction in [0.14, 0.26, 0.38, 0.5, 0.62, 0.74, 0.86] {
      let elapsed = fraction * (action?.duration ?? 3.4)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, fullBodyCat: appearance, width: 92, height: 92, elapsed: elapsed)
      let image = try nativeImage(for: scene)
      let regions = try silhouetteRegions(alphaSamples(image), width: image.width)
      // A few antialiased fibers may end separately. A paw or tail must stay attached.
      #expect(regions.filter { $0 > 6 }.count == 1, "\(String(describing: action)) at \(elapsed)s")
    }
  }

  @Test(arguments: [-0.35, -0.24, -0.12, 0.0, 0.12, 0.24, 0.35])
  func standingFeltTailKeepsItsRootHiddenAndConnected(_ angle: Double) throws {
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let motion = CharacterFullBodyCatMotion(pose: .standing, tailAngle: angle)
    let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: .init(), motion: motion,
      width: 160, height: 160, environment: .init())
    let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
    let tail = try #require(scene.nodes.first { $0.id == "full-body-cat.tail" })

    func coverage(_ node: CharacterSceneNode, at points: [CharacterVectorPoint]) throws -> [UInt8] {
      let part = CharacterScene(width: scene.width, height: scene.height, faceBounds: scene.faceBounds,
        surfaceTransform: scene.surfaceTransform, nodes: [node],
        effectiveMode: scene.effectiveMode, isCompact: scene.isCompact)
      let image = try nativeImage(for: part)
      let alpha = try alphaSamples(image)
      return points.map { point in
        let (x, y) = pixel(at: point, transform: node.transform)
        return alpha[y * image.width + x]
      }
    }

    // The fixed rump covers its rounded rim even when the tail is isolated or swung away.
    #expect(try coverage(body, at: [
      .init(x: 164, y: 140), .init(x: 155, y: 155), .init(x: 166, y: 150.75), .init(x: 170, y: 153.75),
    ]) == [0, 255, 255, 255])
    #expect(try coverage(tail, at: [
      .init(x: 184, y: 181), .init(x: 157.8, y: 147.2), .init(x: 167, y: 155), .init(x: 196, y: 108),
    ]) == [0, 0, 255, 255])
    let combined = try nativeImage(for: scene)
    let regions = try silhouetteRegions(alphaSamples(combined), width: combined.width)
    #expect(regions.filter { $0 > 6 }.count == 1)
  }

  @Test
  func standingTailRootUsesTailWoolInThePackagedArtwork() throws {
    let tail = try #require(CharacterFullBodyCatArtwork.resolve(.standing).tail)
    let png = try CharacterImageResources.png(tail.asset)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    try #require(image.width == 1024 && image.height == 1024)
    let rgba = try rgbaSamples(image)
    func lightness(x: Range<Int>, y: Range<Int>) throws -> Double {
      var total = 0.0
      var count = 0
      for row in (4 * y.lowerBound)..<(4 * y.upperBound) {
        for column in (4 * x.lowerBound)..<(4 * x.upperBound) {
          let i = (row * image.width + column) * 4
          guard rgba[i + 3] >= 250 else { continue }
          total += (2 * Double(rgba[i]) + 3 * Double(rgba[i + 1]) + Double(rgba[i + 2])) / 6
          count += 1
        }
      }
      try #require(count > 300)
      return total / Double(count)
    }
    let root = try lightness(x: 161..<167, y: 149..<154)
    let middle = try lightness(x: 174..<182, y: 125..<133)
    let tip = try lightness(x: 186..<201, y: 87..<94)
    #expect(abs(root - middle) < 9)
    #expect(tip > middle + 4)
  }

  @Test(arguments: [CharacterFullBodyCatPose.standing, .left, .right])
  func renderedFeltHopClearsTheFloorWithoutBreakingItsSilhouette(
    _ rest: CharacterFullBodyCatPose
  ) throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let hop = CharacterFullBodyCatAppearance(pose: rest, action: .hop, style: .felt)
    var soles: [Int] = []
    for phase in [0, 0.15, 0.35, 0.485, 0.65, 0.8, 1] {
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, fullBodyCat: hop, width: 128, height: 128, elapsed: 0,
        actionElapsed: phase * CharacterFullBodyCatAction.hop.duration)
      let frame = try nativeImage(for: scene)
      let alpha = try alphaSamples(frame)
      let top = try #require(alpha.firstIndex { $0 >= 128 })
      let sole = try #require(alpha.lastIndex { $0 >= 128 })
      #expect(top / frame.width > 3)
      #expect(sole / frame.width < frame.height - 3)
      #expect(silhouetteRegions(alpha, width: frame.width).filter { $0 > 6 }.count == 1)
      soles.append(sole / frame.width)
    }
    #expect(abs(soles[0] - soles[1]) <= 1)
    #expect(soles[0] - soles[3] >= 23)
    #expect(abs(soles[0] - soles[5]) <= 1)
    #expect(soles.first == soles.last)
  }

  @Test(arguments: CharacterFeltCatTransition.Route.allCases)
  func renderedFeltTransitionKeepsOneGroundedSilhouette(_ route: CharacterFeltCatTransition.Route) throws {
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let intervals = route.intervals
    var alphas: [[UInt8]] = []
    for index in 0...intervals {
      let transition = CharacterFeltCatTransition(route: route, progress: Double(index) / Double(intervals))
      let motion = CharacterFullBodyCatMotion(
        pose: transition.endpoint, usesGestureTransform: true, transition: transition)
      let scene = try CharacterSceneBuilder.scene(
        pose: face, fullBodyCat: route.testCue(), motion: motion, width: 92, height: 92, environment: .init())
      let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
      if let asset = transition.frameAsset {
        #expect(body.image?.asset == asset)
        #expect(scene.nodes.compactMap { $0.image }.count == 1)
        #expect((try? CharacterPackageResource.url(named: asset.name, fileExtension: "png")) == nil)
      }
      #expect(CharacterSceneCanvasRenderer.missingImageAccessibilityValue(in: scene).isEmpty)

      let frame = try nativeImage(for: scene)
      let alpha = try alphaSamples(frame)
      let sole = try #require(alpha.lastIndex { $0 >= 128 }) / frame.width
      let floor = pixel(at: .init(x: 128, y: 224), transform: body.transform).1
      #expect(abs(sole - floor) <= 5, "\(route) frame \(index) moves the floor contact")
      #expect(silhouetteRegions(alpha, width: frame.width).filter { $0 > 6 }.count == 1)
      #expect(alpha.prefix(frame.width).allSatisfy { $0 == 0 })
      #expect(alpha.suffix(frame.width).allSatisfy { $0 == 0 })
      for row in 0..<frame.height {
        #expect(alpha[row * frame.width] == 0)
        #expect(alpha[(row + 1) * frame.width - 1] == 0)
      }
      alphas.append(alpha)
    }
    let directCut = silhouetteOverlap(alphas[0], alphas[intervals])
    for (index, pair) in zip(alphas, alphas.dropFirst()).enumerated() {
      let overlap = silhouetteOverlap(pair.0, pair.1)
      #expect(overlap > directCut + 0.04, "\(route) jumps between frames \(index) and \(index + 1): \(overlap)")
    }
  }

  @Test(arguments: CharacterFeltCatTransition.Route.actionRoutes)
  func generatedFeltTransitionExportsPNGAndSVG(_ route: CharacterFeltCatTransition.Route) throws {
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let scene = try CharacterSceneBuilder.scene(
      pose: face, fullBodyCat: route.testCue(), width: 128, height: 128,
      elapsed: 0, actionElapsed: route.entryDuration / 2)
    let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
    let asset = try #require(body.image?.asset)
    #expect((try? CharacterPackageResource.url(named: asset.name, fileExtension: "png")) == nil)
    let png = try CharacterImageResources.png(asset)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == CharacterFeltCatRigRenderer.pixelSize)
    #expect(image.height == CharacterFeltCatRigRenderer.pixelSize)
    #expect([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo))
    let svg = try CharacterSVGRenderer.render(scene)
    #expect(svg.contains("data:image/png;base64," + png.base64EncodedString()))
  }

  @Test
  func wavingFeltKeepsBothPawContactsOpaqueThroughTheEighthKey() throws {
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let transition = CharacterFeltCatTransition(route: .waving, progress: 8.0 / 12.0)
    let motion = CharacterFullBodyCatMotion(pose: .waving, usesGestureTransform: true, transition: transition)
    let scene = try CharacterSceneBuilder.scene(
      pose: face, fullBodyCat: .init(action: .wave), motion: motion,
      width: 120, height: 120, environment: .init())
    let frame = try nativeImage(for: scene)
    let alpha = try alphaSamples(frame)
    #expect(frame.width == 240)
    for (x, y) in [(65, 151), (66, 151), (67, 152), (88, 178), (88, 179), (88, 180), (88, 181), (88, 182)] {
      #expect(alpha[y * frame.width + x] >= 235, "wave key 8 at \(x),\(y)")
    }
  }

  @Test
  func rightTurnHidesTheOldShoulderAndReturnsTheTailBehindTheBody() throws {
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    func coverage(at point: CharacterVectorPoint, frame: Int) throws -> UInt8 {
      let transition = CharacterFeltCatTransition(route: .right, progress: Double(frame) / 12)
      let motion = CharacterFullBodyCatMotion(pose: transition.endpoint, usesGestureTransform: true, transition: transition)
      let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: .init(pose: .right), motion: motion,
        width: 180, height: 180, environment: .init())
      let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
      let image = try nativeImage(for: scene)
      let (x, y) = pixel(at: point, transform: body.transform)
      return try alphaSamples(image)[y * image.width + x]
    }

    #expect(try coverage(at: .init(x: 170, y: 145), frame: 2) >= 240)
    #expect(try coverage(at: .init(x: 170, y: 145), frame: 3) == 0)
    #expect(try coverage(at: .init(x: 163, y: 141), frame: 5) == 0)
    #expect(try coverage(at: .init(x: 46, y: 170), frame: 4) == 0)
    #expect(try coverage(at: .init(x: 104, y: 173), frame: 4) >= 240)
    #expect(try coverage(at: .init(x: 67, y: 111), frame: 7) >= 240)
  }

  @Test(arguments: CharacterFeltCatTransition.Route.actionRoutes)
  func renderedFeltTransitionArticulatesWithoutChangingItsBodyAlpha(
    _ route: CharacterFeltCatTransition.Route
  ) throws {
    let talking = ReactiveCharacter.reduce(state: .idle, event: .voiceStarted).state
    let face = ReactiveCharacter.pose(state: talking, elapsed: 0.5, projection: .flat)
    for fraction in [0.20, 0.50, 0.80] {
      let elapsed = route.entryDuration * fraction
      let closed = try CharacterSceneBuilder.scene(
        pose: face.applyingSpeechArticulation(.closed), fullBodyCat: route.testCue(),
        width: 184, height: 184, elapsed: 0, actionElapsed: elapsed)
      let open = try CharacterSceneBuilder.scene(
        pose: face.applyingSpeechArticulation(.open), fullBodyCat: route.testCue(),
        width: 184, height: 184, elapsed: 0, actionElapsed: elapsed)
      let closedMouth = try #require(closed.nodes.first { $0.id == "full-body-cat.mouth" })
      let openMouth = try #require(open.nodes.first { $0.id == closedMouth.id })
      #expect(openMouth.path != closedMouth.path)
      #expect(closed.nodes.filter { $0.image != nil } == open.nodes.filter { $0.image != nil })

      let closedPixels = try rgbaSamples(nativeImage(for: closed))
      let openPixels = try rgbaSamples(nativeImage(for: open))
      let sameAlpha = stride(from: 3, to: closedPixels.count, by: 4).allSatisfy {
        closedPixels[$0] == openPixels[$0]
      }
      let changedColor = stride(from: 0, to: closedPixels.count, by: 4).filter {
        visiblyDifferentColor(closedPixels, openPixels, at: $0)
      }.count
      #expect(sameAlpha, "\(route) at \(fraction) draws speech outside the wool")
      #expect(changedColor > 8)
    }
  }

  @Test(arguments: [CharacterFeltCatTransition.Route.left, .right])
  func renderedFeltTransitionHandsOffToPlantedWalkWithoutAFootSnap(
    _ route: CharacterFeltCatTransition.Route
  ) throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let cue = route.testCue()
    let duration = try #require(cue.action).duration
    func frame(_ elapsed: Double) throws -> (scene: CharacterScene, alpha: [UInt8]) {
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, fullBodyCat: cue, width: 128, height: 128, elapsed: 0, actionElapsed: elapsed)
      return (scene, try alphaSamples(nativeImage(for: scene)))
    }
    let before = try frame(route.entryDuration - 1 / 120.0)
    let walking = try frame(route.entryDuration + 1 / 120.0)
    #expect(walking.scene.nodes.contains { $0.image?.feltWalk != nil })
    #expect(silhouetteOverlap(before.alpha, walking.alpha) > 0.98)
    let stopping = try frame(duration - route.returnDuration - 1 / 120.0)
    let returning = try frame(duration - route.returnDuration + 1 / 120.0)
    #expect(returning.scene.nodes.allSatisfy { $0.image?.feltWalk == nil })
    #expect(silhouetteOverlap(stopping.alpha, returning.alpha) > 0.98)
  }

  @Test(arguments: [CharacterFullBodyCatPose.left, .right])
  func renderedFeltGaitLiftsEachPawIndependently(_ direction: CharacterFullBodyCatPose) throws {
    let pose = ReactiveCharacter.pose(state: .idle, elapsed: 0, reduceMotion: true, projection: .flat)
    let cat = CharacterFullBodyCatAppearance(pose: direction, action: .walk, style: .felt)
    let footfalls: [(Double, CharacterFullBodyCatLeg)] = [
      (1.28, .farHind), (1.52, .farFront), (1.75, .nearHind), (1.99, .nearFront),
    ]
    let rig = try #require(CharacterFullBodyCatArtwork.resolve(direction).walk)

    for (time, lifted) in footfalls {
      let motion = CharacterFullBodyCatMotion.sample(
        appearance: cat, elapsed: 0, actionElapsed: time, reduceMotion: false)
      let scene = try CharacterSceneBuilder.scene(
        pose: pose, fullBodyCat: cat, width: 128, height: 128, actionElapsed: time)
      let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
      let surface = try #require(body.image?.feltWalk)
      let board = ResolvedCharacterAppearance.resolve(
        .fullBodyCat(cat, motion), width: 128, height: 128, environment: .init()).bounds
      let scale = board.width / CharacterFullBodyCatArtwork.size
      #expect(motion.step(for: lifted).lift >= 3)
      for leg in rig.legs {
        let bend = surfaceStep(surface, for: leg.id)
        let goal = leg.foot.y - motion.step(for: leg.id).lift
        let rendered = body.transform.d * (leg.foot.y + Double(bend.y)) + body.transform.ty
        let target = board.midY + scale * (goal - CharacterFullBodyCatArtwork.centerX)
        #expect(abs(rendered - target) <= 0.15 * scale, "\(direction) \(leg.id) at \(time)s")
      }

      let image = try nativeImage(for: scene)
      let regions = try silhouetteRegions(alphaSamples(image), width: image.width)
      #expect(regions.filter { $0 > 6 }.count == 1, "\(direction) at \(time)s")
    }
  }

  @Test
  func renderedFeltSpeechKeepsItsAlphaWhileTheRaisedPawMoves() throws {
    let surprised = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.surprise)).state
    let speaking = ReactiveCharacter.reduce(state: surprised, event: .voiceStarted).state
    let pose = ReactiveCharacter.pose(state: speaking, elapsed: 0.39, projection: .flat)
    let open = pose.applyingSpeechArticulation(.open)
    let closed = pose.applyingSpeechArticulation(.closed)
    let cat = CharacterFullBodyCatAppearance(action: .wave, style: .felt)

    let openScene = try CharacterSceneBuilder.scene(
      pose: open, fullBodyCat: cat, width: 200, height: 200, elapsed: 0.39)
    let closedScene = try CharacterSceneBuilder.scene(
      pose: closed, fullBodyCat: cat, width: 200, height: 200, elapsed: 0.39)
    let nextPawScene = try CharacterSceneBuilder.scene(
      pose: open, fullBodyCat: cat, width: 200, height: 200, elapsed: 0.50)
    let openPixels = try rgbaSamples(nativeImage(for: openScene))
    let closedPixels = try rgbaSamples(nativeImage(for: closedScene))
    let repeatPixels = try rgbaSamples(nativeImage(for: openScene))
    // Native gradient antialiasing can round a color channel by one unit on a repeat render.
    let repeatColorIsStable = zip(openPixels, repeatPixels).allSatisfy { pair in
      abs(Int(pair.0) - Int(pair.1)) <= 1
    }
    #expect(repeatColorIsStable)
    let speechChangedPixels = stride(from: 0, to: openPixels.count, by: 4).filter {
      visiblyDifferentColor(openPixels, closedPixels, at: $0)
    }.count
    #expect(speechChangedPixels > 8)
    let openAlpha = stride(from: 3, to: openPixels.count, by: 4).map { openPixels[$0] }
    let closedAlpha = stride(from: 3, to: closedPixels.count, by: 4).map { closedPixels[$0] }
    let repeatAlpha = stride(from: 3, to: repeatPixels.count, by: 4).map { repeatPixels[$0] }
    let repeatAlphaIsIdentical = openAlpha == repeatAlpha
    let speechPreservesSilhouette = openAlpha == closedAlpha
    let nextAlpha = try alphaSamples(nativeImage(for: nextPawScene))
    let waveChangedPixels = zip(openAlpha, nextAlpha).filter { pair in
      (pair.0 >= 128) != (pair.1 >= 128)
    }.count
    #expect(repeatAlphaIsIdentical)
    #expect(speechPreservesSilhouette)
    #expect(waveChangedPixels > 8)
  }

  @Test(arguments: [CharacterFullBodyCatPose.left, .right])
  func walkingEmotionChangesTheSwingAndKeepsThePlantedPaws(_ direction: CharacterFullBodyCatPose) throws {
    let cat = CharacterFullBodyCatAppearance(action: .walk, walkDirection: direction == .left ? .left : .right)
    func scene(_ emotion: CharacterEmotion, at time: Double, reduceMotion: Bool = false) throws -> CharacterScene {
      let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
      let pose = ReactiveCharacter.pose(state: state, elapsed: 0.62, reduceMotion: reduceMotion, projection: .flat)
      return try CharacterSceneBuilder.scene(pose: pose, fullBodyCat: cat,
        width: 200, height: 200, elapsed: time, reduceMotion: reduceMotion)
    }

    let cheerful = try scene(.joy, at: 1.05)
    let tired = try scene(.fatigueBurden, at: 1.05)
    let eager = try #require(cheerful.nodes.first { $0.id == "full-body-cat.body" }?.image?.feltWalk)
    let subdued = try #require(tired.nodes.first { $0.id == "full-body-cat.body" }?.image?.feltWalk)
    for leg in CharacterFullBodyCatLeg.allCases {
      let up = surfaceStep(eager, for: leg)
      let down = surfaceStep(subdued, for: leg)
      if leg == .nearHind {
        #expect(up.y + 1 < down.y)
      } else {
        #expect(up == down)
      }
    }
    for result in [cheerful, tired] {
      let image = try nativeImage(for: result)
      let regions = try silhouetteRegions(alphaSamples(image), width: image.width)
      #expect(regions.filter { $0 > 6 }.count == 1)
    }
    let brightTurn = try scene(.joy, at: 0.30).nodes.filter { $0.image != nil }
    let subduedTurn = try scene(.fatigueBurden, at: 0.30).nodes.filter { $0.image != nil }
    #expect(brightTurn == subduedTurn)
    let brightReduced = try scene(.joy, at: 1.05, reduceMotion: true).nodes.filter { $0.image != nil }
    let subduedReduced = try scene(.fatigueBurden, at: 1.05, reduceMotion: true).nodes.filter { $0.image != nil }
    #expect(brightReduced == subduedReduced)
  }

  @Test(arguments: [CharacterFullBodyCatWalkDirection.left, .right])
  func feltWalkKeepsItsSharedShoulderAndHipOpaque(_ direction: CharacterFullBodyCatWalkDirection) throws {
    let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let face = ReactiveCharacter.pose(state: state, elapsed: 0.62, projection: .flat)
    let elapsed = direction == .left ? 80.0 / 120 : 168.0 / 120
    let cue = CharacterFullBodyCatAppearance(action: .walk, walkDirection: direction)
    let motion = CharacterFullBodyCatMotion.sample(
      appearance: cue, elapsed: elapsed, actionElapsed: elapsed, reduceMotion: false)
    let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: cue, motion: motion,
      width: 256, height: 256, environment: .init())
    let body = try #require(scene.nodes.first { $0.id == "full-body-cat.body" })
    #expect(body.image?.feltWalk != nil)
    #expect(scene.nodes.allSatisfy { !$0.id.hasPrefix("full-body-cat.leg.") })
    let combined = try nativeImage(for: scene)
    let alpha = try alphaSamples(combined)
    let legs = try #require(CharacterFullBodyCatArtwork.resolve(motion.pose).walk).legs
    for leg in legs {
      let (x, y) = pixel(at: leg.art.pivot, transform: body.transform)
      #expect(alpha[y * combined.width + x] == 255)
    }
    let regions = silhouetteRegions(alpha, width: combined.width)
    #expect(regions.filter { $0 > 6 }.count == 1)
    let image = try #require(body.image)
    let surfacePNG = try CharacterImageResources.png(image)
    let svg = try CharacterSVGRenderer.render(scene)
    #expect(svg.contains(surfacePNG.base64EncodedString()))
  }

  @Test(arguments: [CharacterFullBodyCatWalkDirection.left, .right])
  func renderedFeltWalkKeepsVolumeAtTheForelegAndTailRoots(_ direction: CharacterFullBodyCatWalkDirection) throws {
    let mood = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.joy)).state
    let face = ReactiveCharacter.pose(state: mood, elapsed: 0.55, projection: .flat)
    let side: CharacterFullBodyCatPose = direction == .left ? .left : .right
    let cue = CharacterFullBodyCatAppearance(pose: side, action: .walk, walkDirection: direction)
    let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: cue, width: 300, height: 300,
      elapsed: 0.75, actionElapsed: 0.75)
    let image = try nativeImage(for: scene)
    let rgba = try rgbaSamples(image)
    func offset(x: Int, y: Int) -> Int { (2 * y * image.width + 2 * x) * 4 }

    if direction == .left {
      // A full-body flood fill missed this wedge because it was open between the paws.
      for (x, y) in [(74, 224), (72, 228), (72, 232)] {
        #expect(rgba[offset(x: x, y: y) + 3] == 255)
      }
      #expect(rgba[offset(x: 72, y: 241) + 3] == 0)
    }

    func averageWoolLight(x: Int, y: Int) -> Double {
      var total = 0.0
      for row in (y - 2)...(y + 2) {
        for column in (x - 1)...(x + 1) {
          let index = offset(x: column, y: row)
          #expect(rgba[index + 3] == 255)
          total += 0.2126 * Double(rgba[index]) + 0.7152 * Double(rgba[index + 1]) + 0.0722 * Double(rgba[index + 2])
        }
      }
      return total / 15
    }
    let points = direction == .left ? (212, 218, 175) : (87, 81, 176)
    let drop = averageWoolLight(x: points.0, y: points.2) - averageWoolLight(x: points.1, y: points.2)
    #expect((0...20).contains(drop), "The tail should retain round shading without a sharp cut.")
  }

  @Test(arguments: [CharacterFullBodyCatWalkDirection.left, .right])
  func feltTurnsAndWalksWithTheStandingCoatColor(_ direction: CharacterFullBodyCatWalkDirection) throws {
    let face = ReactiveCharacter.pose(state: .idle, elapsed: 0.52, projection: .flat)
    func meanWoolLight(_ cue: CharacterFullBodyCatAppearance, at time: Double) throws -> Double {
      let scene = try CharacterSceneBuilder.scene(pose: face, fullBodyCat: cue, width: 180, height: 180,
        elapsed: time, actionElapsed: time)
      let rgba = try rgbaSamples(nativeImage(for: scene))
      var sum = 0.0
      var count = 0
      for offset in stride(from: 0, to: rgba.count, by: 4)
      where rgba[offset + 3] == 255 && rgba[offset] < 95 {
        sum += 0.2126 * Double(rgba[offset]) + 0.7152 * Double(rgba[offset + 1]) + 0.0722 * Double(rgba[offset + 2])
        count += 1
      }
      try #require(count > 1_000)
      return sum / Double(count)
    }
    let reference = try meanWoolLight(.init(), at: 0)
    let walk = CharacterFullBodyCatAppearance(action: .walk, walkDirection: direction)
    for time in [0.25, 0.45, 1.2] {
      let sampled = try meanWoolLight(walk, at: time)
      #expect(abs(reference - sampled) <= 4, "Wool drifted from \(reference) to \(sampled) at \(time)s.")
    }
  }

  @Test
  func wavingEmotionChangesThePawWithoutInterruptingSpeech() throws {
    let cat = CharacterFullBodyCatAppearance(action: .wave)
    func speaking(_ emotion: CharacterEmotion) -> CharacterPose {
      let state = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(emotion)).state
      let speaking = ReactiveCharacter.reduce(state: state, event: .voiceStarted).state
      return ReactiveCharacter.pose(state: speaking, elapsed: 0.52, projection: .flat)
    }
    func scene(_ pose: CharacterPose) throws -> CharacterScene {
      try CharacterSceneBuilder.scene(pose: pose, fullBodyCat: cat,
        width: 200, height: 200, elapsed: 0.67)
    }

    let joy = speaking(.joy)
    let open = try scene(joy.applyingSpeechArticulation(.open))
    let closed = try scene(joy.applyingSpeechArticulation(.closed))
    let sad = try scene(speaking(.sadness).applyingSpeechArticulation(.open))
    let paw = "full-body-cat.paw.wave"
    let openPaw = try #require(open.nodes.first { $0.id == paw })
    #expect(openPaw == closed.nodes.first { $0.id == paw })
    #expect(openPaw.transform != sad.nodes.first { $0.id == paw }?.transform)
    #expect(open.nodes.first { $0.id == "full-body-cat.mouth" }?.path
      != closed.nodes.first { $0.id == "full-body-cat.mouth" }?.path)
  }

  @Test(arguments: [CharacterFullBodyCatPose.left, .right])
  func renderedFeltSpeechChangesTheWalkingMuzzle(_ direction: CharacterFullBodyCatPose) throws {
    let curious = ReactiveCharacter.reduce(state: .idle, event: .emotionChanged(.interest)).state
    let speaking = ReactiveCharacter.reduce(state: curious, event: .voiceStarted).state
    let pose = ReactiveCharacter.pose(state: speaking, elapsed: 0.50, projection: .flat)
    let cat = CharacterFullBodyCatAppearance(pose: direction, action: .walk, style: .felt)
    let rounded = try CharacterSceneBuilder.scene(
      pose: pose.applyingSpeechArticulation(.rounded), fullBodyCat: cat,
      width: 200, height: 200, elapsed: 0.50, actionElapsed: 1.52)
    let closed = try CharacterSceneBuilder.scene(
      pose: pose.applyingSpeechArticulation(.closed), fullBodyCat: cat,
      width: 200, height: 200, elapsed: 0.50, actionElapsed: 1.52)
    let skin = try #require(rounded.nodes.first { $0.id == "full-body-cat.body" })
    #expect(skin.image?.feltWalk != nil)
    #expect(skin == closed.nodes.first { $0.id == skin.id })
    let roundedMouth = try #require(rounded.nodes.first { $0.id == "full-body-cat.mouth" })
    let closedMouth = try #require(closed.nodes.first { $0.id == roundedMouth.id })
    #expect(roundedMouth.path != closedMouth.path)

    let muzzle = try #require(CharacterFullBodyCatArtwork.resolve(direction).face?.muzzle)
    let (x, y) = pixel(at: muzzle.junction, transform: roundedMouth.transform)
    let roundedImage = try nativeImage(for: rounded)
    let roundedPixels = try rgbaSamples(roundedImage)
    let closedPixels = try rgbaSamples(nativeImage(for: closed))
    try #require((0..<roundedImage.width).contains(x) && (0..<roundedImage.height).contains(y))
    let center = (y * roundedImage.width + x) * 4
    #expect(roundedPixels[center + 3] == 255 && closedPixels[center + 3] == 255)

    let xRange = max(0, x - 16)...min(roundedImage.width - 1, x + 16)
    let yRange = max(0, y - 16)...min(roundedImage.height - 1, y + 16)
    var changedMuzzlePixels = 0
    for row in yRange {
      for column in xRange {
        let pixel = (row * roundedImage.width + column) * 4
        if visiblyDifferentColor(roundedPixels, closedPixels, at: pixel) {
          changedMuzzlePixels += 1
        }
      }
    }
    #expect(changedMuzzlePixels > 8, "\(direction) muzzle only changed \(changedMuzzlePixels) pixels")
  }

  private func visiblyDifferentColor(_ first: [UInt8], _ second: [UInt8], at pixel: Int) -> Bool {
    (0..<3).contains { channel in
      abs(Int(first[pixel + channel]) - Int(second[pixel + channel])) >= 3
    }
  }

  private func silhouetteOverlap(_ first: [UInt8], _ second: [UInt8]) -> Double {
    var intersection = 0
    var union = 0
    for (before, after) in zip(first, second) {
      if max(before, after) >= 128 { union += 1 }
      if min(before, after) >= 128 { intersection += 1 }
    }
    return Double(intersection) / Double(max(union, 1))
  }

  private func pixel(at point: CharacterVectorPoint, transform: CharacterSceneTransform) -> (Int, Int) {
    let x = 2 * (transform.a * point.x + transform.c * point.y + transform.tx)
    let y = 2 * (transform.b * point.x + transform.d * point.y + transform.ty)
    return (Int(x.rounded()), Int(y.rounded()))
  }

  private func nativeImage(for scene: CharacterScene) throws -> CGImage {
    let png = try CharacterScenePNGRenderer.render(scene, scale: 2)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  private func surfaceStep(_ surface: CharacterFeltWalkSurface, for leg: CharacterFullBodyCatLeg)
    -> CharacterFeltWalkSurface.Step
  {
    switch leg {
    case .nearFront: surface.nearFront
    case .nearHind: surface.nearHind
    case .farFront: surface.farFront
    case .farHind: surface.farHind
    }
  }

  private func silhouetteRegions(_ pixels: [UInt8], width: Int) -> [Int] {
    var unvisited = pixels.map { $0 >= 128 }
    var regions: [Int] = []
    for start in unvisited.indices where unvisited[start] {
      var queue = [start]
      unvisited[start] = false
      var cursor = 0
      while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let column = index % width
        let rowStart = index - column
        for neighborRow in [rowStart - width, rowStart, rowStart + width]
          where neighborRow >= 0 && neighborRow < pixels.count {
          for neighborColumn in max(0, column - 1)...min(width - 1, column + 1) {
            let neighbor = neighborRow + neighborColumn
            if unvisited[neighbor] {
              queue.append(neighbor)
              unvisited[neighbor] = false
            }
          }
        }
      }
      regions.append(queue.count)
    }
    return regions
  }

  private func alphaSamples(_ image: CGImage) throws -> [UInt8] {
    let bytes = try rgbaSamples(image)
    return stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
  }

  private func rgbaSamples(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let drewImage = bytes.withUnsafeMutableBytes { storage -> Bool in
      guard let context = CGContext(
        data: storage.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    try #require(drewImage)
    return bytes
  }
}
#endif

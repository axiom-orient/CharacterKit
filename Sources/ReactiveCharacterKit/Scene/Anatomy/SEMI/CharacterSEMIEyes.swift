import Foundation

extension CharacterSEMIDrawing {
  private enum EyePolicy {
    static let centerY = 231.0
    static let minimumWidth = 48.0
    static let maximumWidth = 84.0
    static let minimumHeight = 10.0
    static let maximumHeight = 92.0
    static let smileStrokeWidth = 4.8
  }

  mutating func eye(left: Bool) {
    let source = left ? pose.eyes.left : pose.eyes.right
    let contour = left ? pose.eyeContours.left : pose.eyeContours.right
    // Reuse the feline expression projection; only the authored SEMI proportions differ.
    let eye = CharacterSEMIEyeGeometry(eye: source, contour: contour, left: left,
      gazeX: gazeX, gazeY: gazeY, sizeResponse: 0.25)
    let rig = expressionRig
    let id = left ? "eye.left" : "eye.right"
    let writingFocus = writingIntensity
    let affection = contour.heart
    let surpriseCue = rig.surprise
    let smile = min(1, max(0, eye.happiness * 1.02 + eye.closure * 0.32 + affection * 0.16))
    let joyCue = rig.joy
    let downwardMood = min(1, max(0, gazeY))
    let anxietyCue = rig.anxiety
    let calmTrustCue = rig.calmTrust
    let angerCue = min(1, max(0,
      contour.innerPinch * (1 - contour.lidCompression * 0.72)))
    let disgustCue = min(1, max(0,
      (contour.lidCompression - 0.48) / 0.45 * contour.innerPinch * 1.45))
    let shameCue = min(1, max(0, (0.84 - contour.widthScale) / 0.12))
      * (1 - contour.innerPinch * 0.80) * (1 - contour.circular * 0.80)
    let fearCue = min(1, max(0,
      contour.ellipse * (1 - contour.circular) * (0.82 + contour.innerPinch * 0.18)))
    let rawFatigueCue = min(1, max(0,
      contour.lidCompression * 1.08 + contour.innerPinch * 0.10 - contour.circular * 0.26))
    let fatigueWidthGate = min(1, max(0, (contour.widthScale - 0.72) / 0.56))
    let fatigueCue = rawFatigueCue * fatigueWidthGate
      * (1 - contour.innerPinch * 0.62) * (1 - calmTrustCue * 0.92)
    let tendernessCue = min(1, max(0, smile * downwardMood * 0.60 + affection * 0.18))
    let gratitudeCue = min(1, max(0,
      rig.gratitudeCourtesy * 0.72 + affection * 0.40 + tendernessCue * 0.42
        - eye.surprise * 0.12))
    let sadnessCue = min(1, max(0,
      max(rig.sadness,
        max(0, -mouthCurvature) * 0.68 + downwardMood * 0.42 - fatigueCue * 0.18)))
    // Sadness lifts the nasal corner and lets the upper lid settle over the eye. Fear and
    // a pinched inner canthus use nearby geometry, so attenuate the sad contour as either rises.
    let sadnessEyeCue = sadnessCue * (1 - anxietyCue * 0.72)
      * (1 - min(0.55, eye.pinch * 0.55))
    let anchor = faceAnchorRig
    let x = anchor.eyeX(left: left) + gazeX * 2.4 + (left ? 1.0 : -1.0) * writingFocus * 2.2
    let y = anchor.eyeY + gratitudeCue * 2.2 + sadnessCue * 1.8 + fatigueCue * 3.4
      + shameCue * 1.0 + disgustCue * 0.7 + calmTrustCue * 0.8
      - anxietyCue * 0.6 - joyCue * 1.0
    let w = min(EyePolicy.maximumWidth, max(EyePolicy.minimumWidth,
      eye.width * 68 / CharacterSEMIMetrics.eyeWidth
        * (1 - smile * 0.08 - gratitudeCue * 0.07 + joyCue * 0.10
          - calmTrustCue * 0.035 - angerCue * 0.035 - disgustCue * 0.045
          - shameCue * 0.045 + fearCue * 0.025)
        * (1 - surpriseCue * 0.14)))
    let h = min(EyePolicy.maximumHeight, max(EyePolicy.minimumHeight,
      eye.height * 84 / CharacterSEMIMetrics.eyeHeight
        * (1 - smile * 0.14 - sadnessEyeCue * 0.10 - fatigueCue * 0.68
          - angerCue * 0.06 - disgustCue * 0.06 - shameCue * 0.035
          + anxietyCue * 0.12 + fearCue * 0.06 + calmTrustCue * 0.06)
        * (1 - surpriseCue * 0.22)))
    let open = 1 - eye.closure
    let rx = w / 2
    let ry = h / 2
    let upperLift = smile * 3.8 + affection * 0.8 + gratitudeCue * 0.6
      + joyCue * 1.0 - fatigueCue * 0.45 - shameCue * 0.25
      - calmTrustCue * 0.4 - writingFocus * 0.4
    let bend = (-9.2 * smile + 1.6 * (1 - smile)) * eye.closure - smile * 0.8
      + gratitudeCue * 1.4 + anxietyCue * 0.8 - angerCue * 0.6
    let tilt = (left ? 1.0 : -1.0) * eye.pinch * 9.5 * (1 - smile * 0.30)
      + (left ? -1.0 : 1.0) * anxietyCue * 3.0
      + (left ? 1.0 : -1.0) * (shameCue * 2.2 + disgustCue * 2.4)
    let sadnessTilt = (left ? -1.0 : 1.0) * sadnessEyeCue * 8.0
    let cornerTilt = tilt + sadnessTilt
    let sadnessUpperDroop = ry * (0.22 * sadnessEyeCue + 0.10 * fatigueCue
      + 0.06 * disgustCue + 0.04 * shameCue)
    let lowerScale = max(0.42,
      1 - smile * 0.42 - fatigueCue * 0.18 - disgustCue * 0.10 - shameCue * 0.06
        + sadnessEyeCue * 0.04 + anxietyCue * 0.08 + fearCue * 0.04
        - calmTrustCue * 0.08)
    let local = CharacterSceneTransform.around(x: x, y: y, angle: eye.angle)
    var aperture = CharacterVectorPath()
    aperture.move(x - rx, y - cornerTilt)
    aperture.cubic(x - rx, y - ry * open * (0.54 - smile * 0.08) - cornerTilt - upperLift,
      x - rx * (0.57 - smile * 0.05),
      y - ry * open + bend - upperLift + sadnessUpperDroop * 0.78,
      x, y - ry * open + bend - upperLift + sadnessUpperDroop)
    aperture.cubic(x + rx * (0.57 - smile * 0.05),
      y - ry * open + bend - upperLift + sadnessUpperDroop,
      x + rx, y - ry * open * (0.54 - smile * 0.08) + cornerTilt - upperLift,
      x + rx, y + cornerTilt)
    aperture.cubic(x + rx, y + ry * sqrt(open) * 0.55 * lowerScale + cornerTilt,
      x + rx * (0.55 + smile * 0.03), y + ry * sqrt(open) * lowerScale + bend,
      x, y + ry * sqrt(open) * lowerScale + bend)
    aperture.cubic(x - rx * (0.55 + smile * 0.03), y + ry * sqrt(open) * lowerScale + bend,
      x - rx, y + ry * sqrt(open) * 0.55 * lowerScale - cornerTilt,
      x - rx, y - cornerTilt)
    aperture.close()

    let smileInkOpacity = min(1, max(min(1, max(0, (eye.closure - 0.76) / 0.24)),
      min(1, max(0, (smile - 0.34) / 0.26))))
    let eyeballOpacity = max(0, 1 - smileInkOpacity * 0.96)
    if open > CharacterSEMIMetrics.closedThreshold, eyeballOpacity > 0.02 {
      add(id, aperture,
        fill: material(colors.eyes, top: .init(x: x - 12, y: y - ry),
          bottom: .init(x: x + 10, y: y + ry)), opacity: eyeballOpacity,
        local: actingLocal(local))
      let pupilX = x + gazeX * 10 + (left ? 1.5 : -1.5)
      let pupilY = y + gazeY * 9 + smile * 0.8
      let pupilW = 24 + eye.surprise * 10 + eye.heart * 7 + anxietyCue * 5 - smile * 2.5
      let pupilH = 55 + eye.surprise * 3 + anxietyCue * 0.8 - smile * 4.5
      let pupil = semiPupil(x: pupilX, y: pupilY, width: pupilW,
        height: pupilH, heart: eye.heart)
      add(id + ".pupil", pupil, fill: .solid(colors.outline), opacity: eyeballOpacity,
        local: actingLocal(local), clips: [aperture])
      let glintOpacity = min(0.78, max(0.28,
        0.52 + joyCue * 0.12 + affection * 0.10 + fearCue * 0.08
          - sadnessEyeCue * 0.12 - fatigueCue * 0.14 - disgustCue * 0.12 - shameCue * 0.10))
      add(id + ".highlight", .ellipse(.init(x: pupilX - 7, y: pupilY - 20, width: 7, height: 10)),
        fill: .solid(colors.mouthDetail), opacity: glintOpacity * eyeballOpacity,
        local: actingLocal(local), clips: [aperture, pupil])
    }

    // A smile eye is the same face grammar compressed into one expressive ^^ arc, not a totally
    // different symbol. Strong happiness should read decisively even before a full blink.
    let lid = smileLid(centerX: x,
      centerY: y - smile * (2.0 + affection * 0.8) + gratitudeCue * 2.6
        + anxietyCue * 1.4 - joyCue * 1.0,
      width: w * (0.98 - smile * 0.02 + affection * 0.01 - gratitudeCue * 0.12
        + joyCue * 0.16 - calmTrustCue * 0.05),
      amplitude: 8.8 + smile * 5.4 + affection * 2.6 + gratitudeCue * 1.4
        + joyCue * 4.0 - calmTrustCue * 0.8,
      tilt: tilt, smile: smile)
    add(open > CharacterSEMIMetrics.closedThreshold ? id + ".closed" : id, lid,
      stroke: colors.eyes, width: readableStrokeWidth(EyePolicy.smileStrokeWidth),
      opacity: smileInkOpacity, local: actingLocal(local))
  }

  private func smileLid(centerX: Double, centerY: Double,
    width: Double, amplitude: Double, tilt: Double, smile: Double) -> CharacterVectorPath {
    let half = width / 2
    let leftY = centerY - tilt * 0.38
    let rightY = centerY + tilt * 0.38
    let crownY = centerY - amplitude * (0.62 + smile * 0.05)
    var lid = CharacterVectorPath()
    lid.move(centerX - half, leftY)
    lid.cubic(
      centerX - half * 0.56, crownY,
      centerX + half * 0.56, crownY,
      centerX + half, rightY)
    return lid
  }

  private func semiPupil(x: Double, y: Double, width: Double,
    height: Double, heart: Double) -> CharacterVectorPath {
    // A continuous ellipse → heart contour, not a glyph/state switch or sprite swap.
    let count = 32
    var points: [CharacterVectorPoint] = []
    for index in 0..<count {
      let t = Double(index) * 2 * .pi / Double(count)
      let sine = sin(t)
      let hx = sine * sine * sine
      let hy = -(13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)) / 17
      points.append(.init(x: x + width * 0.5 * (sine * (1-heart) + hx * heart * 1.4),
        y: y + height * 0.5 * (-cos(t) * (1-heart) + hy * heart)))
    }
    var p = CharacterVectorPath()
    p.move(points[0].x, points[0].y)
    for index in 0..<count {
      let previous = points[(index + count - 1) % count]
      let current = points[index]
      let next = points[(index + 1) % count]
      let after = points[(index + 2) % count]
      p.cubic(current.x + (next.x-previous.x)/6, current.y + (next.y-previous.y)/6,
        next.x - (after.x-current.x)/6, next.y - (after.y-current.y)/6, next.x, next.y)
    }
    p.close()
    return p
  }
}

# Full-body cat artwork

The supplied 1672 × 941 reference sheet is the source of the cat's silhouette, fur, and authored postures. Its SHA-256 and registration coordinates are in [manifest.json](manifest.json). Keep the reference sheet outside the SDK bundle.

## Rebuild the reference PNGs

Run on macOS 14 or later from the repository root. The original sheet provides the reference-resolution set, including the secondary poses and walking layers.

```sh
swift -O Artwork/FullBodyCat/prepare_assets.swift \
  /path/to/source-sheet.jpg \
  /tmp/felt-reference-pngs
```

The script finds the foreground in each crop using Vision and refines the edge against the source pixels. It keeps the opaque felt interior and replaces background-contaminated edge colours with a weighted sample of nearby opaque fur. Local texture retouching fills the eye and muzzle areas before the live face is drawn. For the stand and wave postures it isolates the tail and raised paw, keeps their roots opaque beneath the cut, and caps the shared edge coverage where layers overlap.

The finished PNGs share a 256 × 256 logical sRGB canvas with Y increasing down the stage. The registration maps each reference floor to Y = 224. Larger reference panels are scaled uniformly before placement. In the belly pose, the manifest reports eye and nose sizes before the face rotation. The profile postures use a visible eye and the rear posture has no face.

The standing tail draws behind the body and the raised paw draws over the torso. Both use the common canvas and their registered pivots. The standing master keeps the complete rounded rump in the body layer. The tail overlaps the rump at its root as it turns. The authored stretch, puff, and belly postures are individual drawings.

The sheet's walking rig separates the four visible legs of its left profile and reflects them for the right direction. Use this set as a registration reference. The high-resolution walking layers below use both independent profile masters.

For native walking, join the clipped torso and the two near paws in their registered neutral pose before deforming the texture. Each paw's displacement grows smoothly from the shoulder or hip toward the pad. The far paws bend on their own surfaces behind the joined coat. Contact loads flatten and widen the body, and each local foot target compensates for that change to keep its authored floor height. PNG and SVG export reuse the same generated surface as Canvas. [Runtime surface renderer](../../Sources/ReactiveCharacterKit/Rendering/Apple/CharacterFeltWalkRenderer.swift)

## Review a higher-resolution source

The ten shipped poses use the [high-resolution masters](HIGH_RESOLUTION.md) and the saved calibrations in [HighResolution](HighResolution). The bodies and appendages use the 4× raster.

The 256-point stage, joint anchors and live face registration also accept a square PNG at 3× or 4× density. Keep the generated master and calibration together outside the SDK bundle. Use source-image pixel coordinates with the origin at the top left. The import fits a uniform scale to the eye spacing, uses their midpoint for translation, and measures the remaining difference at the floor and joint. Set `alignGround` to `true` for a small vertical adjustment that pins the toes to the existing floor while keeping the eye midpoint fixed. The report includes the resulting vertical-to-horizontal scale ratio.

```sh
swift -O Artwork/FullBodyCat/prepare_assets.swift --hero \
  /path/to/felt-master.png /path/to/calibration.json \
  /tmp/felt-reference-pngs /tmp/felt-hero-review
```

The calibration accepts a `pose` from [manifest.json](manifest.json), `sourceSHA256`, `sourceCrop` (`[x,y,width,height]`), `groundY`, `pixelsPerPoint` (`3` or `4`) and an optional `joint` (`[x,y]` for the stand tail or wave paw). Two horizontal `eyes` (`[x,y]` points) establish default registration. A profile, rear, or belly-up view can provide `placement` with a source anchor, stage anchor and measured X/Y scales. A local `stageWarp` can bring a tail tip or foot back to the original extent by remapping ordered `[source,destination]` points on the 256-point stage.

Leave `removeBakedFace` enabled when the master contains facial ink. A master can provide exact source-image face patches. For the profiles that include a generated nose beyond the cheek edge, the saved face trim removes those few pixels after retouching. The waving master calibration records the paw seam so the raised paw and torso overlap around that specific joint. The standing `rumpContour` records the front edge of the tail join in registered stage coordinates. The importer rounds the overlapping tail root, replaces the rump imprint there with nearby tail wool, and finishes the tail's lighting and edge colour in its existing PNG. The same prepared tail serves the standing pose and transition renderer.

The review writes `comparison.png` (previous artwork on the left), `registered-source.png` (the new source positioned with its authored face), and `report.json` with the alpha-outline comparison. The default keeps the reference silhouette and transfers fine wool texture within the common opaque area. Set `preserveReferenceSilhouette` to `false` to review the registered source outline directly. Replace a body and its appendage together only after reviewing their position and overlap through motion. Each decoded 1024 × 1024 RGBA layer requires about 4 MiB of pixel data before renderer overhead.

## Rebuild the high-resolution walking layers

Regenerate the left and right face-cleared profile PNGs with their hero calibrations, then use the matching authored gait cut for each direction.

```sh
swift -O Artwork/FullBodyCat/prepare_gait.swift \
  /tmp/felt-left-review/full-body-cat-left.png \
  Artwork/FullBodyCat/HighResolution/left-gait.json /tmp/felt-left-gait
```

The right profile includes three visible feet. Its small, occluded far-front foot is filled from the same profile's felt art and kept beneath the near leg. Draw the far legs first, then the near legs, then the torso over their roots. Keep each direction's five parts and resting side profile together.

Collect the freshly aligned poses and gait layers in one preparation directory. Run `python3 Artwork/FullBodyCat/finish_gait.py PREPARED FINISHED_GAIT` with Pillow, NumPy, and SciPy. The finisher fits rounded wool to the left far foreleg's registered shoulder and toe, and softens the cut and lighting at each far hind paw. The profile tail blend preserves its alpha and fibre detail. Overlay those finished files on a copy of the complete set, then run `python3 Artwork/FullBodyCat/grade_felt.py PREPARED_WITH_FINISHED_GAIT GRADED` and install the graded PNGs. Each pose and its articulated layers share a grade calibrated against the standing felt. Use fresh sources for each run so each correction is applied once.

## Review after regeneration

- Check each pose at its actual display size against light, dark, and saturated backgrounds. Check the ears, tail, and paws for bright or dark rims, floor shadow fragments, and clipping.
- At the face anchors, check that the fur is opaque and that the original ivory features do not show through when the live features close or shift.
- Inspect the tail and paw at rest and at the full positive and negative angles of their clips. Compare each still pose to the supplied source after composing the live facial features.

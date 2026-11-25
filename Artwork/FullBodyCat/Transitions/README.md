# Felt cat transition artwork

The SDK draws transitions from its 22 approved felt PNGs and
`full-body-cat-motion-rig.lzfse`. The compressed JSON stores vector outlines and
inverse texture coordinates on the 256-point stage for ten routes. Each
intermediate body samples those textures into a transient 640 × 640 RGBA
image. The face stays live. The `*-face.json` files register the face in
authored intermediate poses. The rear turn uses the complete left approach
and right puff uses the complete right approach. A matching side pose joins
the latter part of either route at the original profile artwork.

## Left turn and stretch

The measured pairs in `left-stretch-geometry.json` put ears, cheek, paws,
shoulder, and tail at their corresponding positions. Each row contains
standing x and y followed by destination x and y. The generator registers
both images to the same intermediate contour with thin-plate-spline point
mapping. A signed-distance field provides one silhouette, and the aligned
opaque pixels provide the wool colour and fine detail.

## Right turn

The original right-turn outline uses a front-facing reference at frame six. The source is
`felt-hd-masters/front-turn.png` in the local task files, SHA-256
`d9030e1ec519a316930e2e7c2f1cc4ea7d6c39417116198be36b050603e4acc3`.
The 1254×1254 RGBA key was generated from the approved
[standing and right masters](../HIGH_RESOLUTION.md), with the face clear
for the live eyes and mouth. The preparation pins the feet to y=224,
normalizes interior coverage, shortens the tail as it passes behind the
head, and uses separate source-to-front and front-to-right landmark pairs.
The approved right pose supplies the final profile. During playback the
front outline is filled using geometry mapped to bundled wool textures.

The prompt for the front key used the standing and right masters in that order.

> Create exactly one transparent full-body 2D animation key pose of the same existing premium black needle-felt cat, from fixed camera height, warm subdued directional studio light. The attached first reference is the approved standing pose and object identity; the second is the approved endpoint of one body action. Preserve the exact tiny tight black wool fibers, hand-felt construction, cheek/ear/tail shapes, near-black brown sRGB and very short, softly rounded legs, matching the originals. Render the middle pose as a single coherent matte felt object with four anatomically placed paws, without duplicate dissolve silhouettes, ground shadows, props or text. Show the fine wool texture at native resolution, padding on all sides, real alpha transparency. Important for animation, leave the wool on the face plain and free of any eyes, nose, mouth, whiskers, or any markings so our live face is composited onto the blank head. Show the quarter-turn pose exactly halfway from the starting west-facing three-quarter stance to the ending east-facing (screen-right) side profile. At halfway, the toy is facing the camera with a very slight turn towards screen right. The head is large round and centered toward screen-center, the body is foreshortened behind it, the near and far front paws are both touching the ground under the head, hind paws are mostly occluded. Tail is compact and foreshortened behind the head, one small segment visible high or toward screen left; it should not form an arc across the face. A grounded front transition pose, not sitting and not jumping. Match low-slung cat mass and exact limb size; do not make it resemble a doll upright on two legs.

## Produce authoring references

From the repository root, prepare Python 3 with Pillow, NumPy, and SciPy.
The current assets were reviewed with Pillow 13.0.0, NumPy 2.5.5, and SciPy
1.18.1. Run both commands against the existing endpoint PNGs.

```sh
assets=Sources/ReactiveCharacterKit/Resources/FullBodyCat
python3 Artwork/FullBodyCat/prepare_transition_frames.py "$assets" /tmp/felt-transition
python3 Artwork/FullBodyCat/prepare_right_transition.py \
  "$assets" /path/to/front-turn.png /tmp/felt-transition
```

The generators write scratch references into destination-named
subdirectories. The numeric compiler uses their alpha contours and the
authored control points. Keep these reference PNGs outside the SDK.

## Rebuild the runtime geometry

Prepare the base geometry from the scratch references first. The next
generators give each planted or lifting paw its own motion, stage the
rear turn through the left profile, and round the belly roll. The right
turn then uses a rounded head, registered ears and cheek, and a separate tail.
The tail passes behind the head and returns on the other side. Right puff
continues from the exact right profile through four arch keys. The rear route
continues from the exact left profile through six rear keys. The rear crown
and its tail shadow share the sweep of the visible tail.

```sh
faces=Artwork/FullBodyCat/Transitions
python3 Artwork/FullBodyCat/prepare_runtime_motion_rig.py \
  "$assets" /tmp/felt-transition /tmp/felt-motion.json
python3 Artwork/FullBodyCat/prepare_turn_polish.py \
  "$assets" /tmp/felt-motion.json /tmp/felt-turn.json
python3 Artwork/FullBodyCat/prepare_right_turn_volume.py \
  "$assets" /tmp/felt-turn.json /tmp/felt-turn-volume.json
python3 Artwork/FullBodyCat/prepare_plant_polish.py "$assets" /tmp/felt-plant.json
python3 Artwork/FullBodyCat/prepare_rear_turn.py \
  "$assets" /tmp/felt-motion.json /tmp/felt-rear.json --face-output "$faces/rear-face.json"
python3 Artwork/FullBodyCat/prepare_runtime_belly_rig.py \
  "$assets" /tmp/felt-belly.json --face-json "$faces/belly-face.json"
python3 Artwork/FullBodyCat/prepare_right_puff_rig.py \
  "$assets" /tmp/felt-puffright.json "$faces/puffright-face.json"
jq -cs 'add | to_entries | sort_by(.key) | from_entries' /tmp/felt-motion.json \
  /tmp/felt-turn.json /tmp/felt-turn-volume.json /tmp/felt-plant.json /tmp/felt-rear.json \
  /tmp/felt-belly.json /tmp/felt-puffright.json > /tmp/felt-runtime-rig.json
compression_tool -encode -a lzfse -i /tmp/felt-runtime-rig.json -o "$assets/full-body-cat-motion-rig.lzfse"
python3 Artwork/FullBodyCat/emit_transition_faces.py > \
  Sources/ReactiveCharacterKit/Scene/Anatomy/FullBodyCat/CharacterFeltCatTransitionRegistration.swift
```

Use the corresponding checked-in face coordinates when evaluating a
regenerated sequence. Recheck the opaque eye and mouth areas, paw contact,
tail overlap, and viewport padding before promoting any updated frames.

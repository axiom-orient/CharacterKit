# High-resolution felt masters

The source is the supplied 1672 × 941 character sheet documented in
[manifest.json](manifest.json). Each of the ten poses uses a separate ImageGen
master based on its own crop of the sheet. The accepted standing master also
served as the wool and lighting reference for the last seven poses. The master
dimensions are 1254 × 1254 except for belly-up, which is 1774 × 887.

| Pose | Source crop, x / y / width / height in original pixels | Master SHA-256 |
| --- | --- | --- |
| Standing | 892 / 247 / 187 / 158 | `f7c34007acd21e43afaf22b1733748811af8b7a93f67be0d4575878052a10ec3` |
| Waving | 884 / 441 / 192 / 158 | `afe15cbedc8add86b0ae14e28a55401a33d866abb860b7f66554756521445b7c` |
| Loaf | 1159 / 279 / 182 / 124 | `2345765c4541ba6dcc2c86db90b1390640a0d8cd9c2245e82762cc6f2885a49c` |
| Left | 450 / 34 / 327 / 226 | `65e1e5690f16a0f3dc87b53390ffb0ddc8e0b9d97091c3c36437fa7a5a09efef` |
| Right | 455 / 308 / 332 / 225 | `32f02fd497c6b9390b611644593b5e5724d5adc6038eba69e2090a46fd0e13c2` |
| Rear | 125 / 299 / 187 / 237 | `4577802a21611c429633b407149e39cc9da43ddd3f9c60cc94e935eae37fe5e6` |
| Upright | 1459 / 245 / 146 / 161 | `ab8480027eb448725014bf9f70f9c67e834727d6b6b8e98113c49784a7d9cfe6` |
| Puffed | 1142 / 433 / 205 / 162 | `331cd5bfa632e4ee966fe28c993d4f45c016c680964409c181ac8c4926dfc373` |
| Belly-up | 1408 / 472 / 237 / 121 | `34c95f33a70131c14ba58c0d0facbe8b36f8914983d40661a7b3892a3c646b89` |
| Stretch | 245 / 667 / 277 / 216 | `ce6523f571a53b014b5bca8e36ef883a78f368c688abce0b53becb1da48c9328` |

The editable masters are preserved in the local task's `felt-hd-masters` directory.
The scene uses a 256-point coordinate space with the ground at y = 224.
Each of the 22 packaged body, tail and paw layers uses the same 1024 × 1024
RGBA PNG format. The runtime draws eyes, nose, and mouth on the registered
face anchors, with the rear view kept blank. Each side of the walk reuses the
artwork and facial placement of its standing profile. The profile mouth
opens inward along the cheek, so it can follow speech without extending
the side silhouette. The calibration files
are in [HighResolution](HighResolution), and the import steps are in the
[artwork guide](README.md).

## ImageGen prompts

Shared text for standing, waving, and loaf:

> Use case: identity-preserve. Asset type: isolated high-resolution 2D sprite art for an existing animated character. Input image is the exact pose and character to reproduce. Redraw only by restoring fine resolution, keep the reference's proportions and posture, original clean silhouette and composition, sRGB black/very dark charcoal, tiny warm cream oval eyes, small cream nose and fine double-curved mouth, no visible pupils, no whiskers, no eyebrows, no paws pads, no additional features. It must look like a premium real handcrafted needle-felt wool figure, dense short matte microfibers woven into the surface, delicate contact and form shading across the figure, round clean controlled ends, dimensional but no shiny plastic, no exaggerated fuzzy hairs. Preserve shape before adding texture, keep the original pose and orientation rather than redesigning. Use soft warm diffused studio light. Put the full character entirely within a square canvas with plenty of transparent padding and real alpha. No floor, cast shadow, background, checkerboard, text, letters, props, cut-off ears, or logos.

Standing:

> This is the standing four-legged three-quarter pose: face tilted slightly toward the left of the image, round large head with exactly two small triangular ears, exceptionally short thick bobbed legs, compact round body to right, very thick upright tail curling up right behind the body. Keep the exact apparent placement and size of both eyes and nose, and the number of visible legs. The tiny lettering at the top left is not part of the art.

Waving:

> This is the sitting three-quarter front pose: one rounded forepaw raises to the viewer's left of the head, the other forepaw plants at ground, squat round body, the thick curved tail on the viewer's right behind the body. Keep the two visible eye positions, cheek silhouette, and raised forepaw's joint position.

Loaf:

> This is a low compact loaf pose: wide round head on the viewer's left closest to camera, body huddled behind it to the right, short thick curled tail lies on viewer's right at floor level, no visible feet breaking the low silhouette. Keep the original blank small cream features and round shoulders.

Shared text for left, right, rear, upright, puffed, belly-up, and stretch:

> Use case: identity-preserve. Asset type: a single full-body 2D animation sprite. The first image is the exact silhouette, camera, proportions, expression and pose to reconstruct at high resolution. The second image is the already accepted master of the same black cat, used only to match the near-black warm charcoal needle-felt wool, density of its tiny compact visible fibers and soft neutral studio light. Use the pose and proportions of the first image, even if they differ from those in the second image. The finished piece should look like the same real premium hand-felted toy photographed from the first camera, with short dense tiny wool fibers and restrained soft form shading, almost black charcoal. Keep the original rounded head, small ear proportions, short thick rounded legs and exact tail placement. On angles where the source face is visible, keep the original tiny warm ivory felt eyes and visible nose and mouth, without pupils, whiskers, brows, or different proportions. Preserve a single coherent wool silhouette with no solid bright tracing lines. Render the entire isolated figure in a square canvas with true transparency, padding around every extremity, no ground contact shadow, floor, text, borders, logos, or props.

Left:

> True left-facing horizontal side profile; original small oval eye at the silhouette's front, cheek larger and lower than the ears, the visible near foreleg reaching diagonally to the left, far forefoot just under it, short near hind leg to the right and far hind foot peeking behind it. Match the exact torso length, contour of belly, round toe shapes, and rising tail at the far right. No second eye or turn to front.

Right:

> True right-facing side profile from this first image. Match its low long body, rounded outward-sloping near feet and existing faintly visible far-side feet, head and original small ivory eye and nose at the right edge, rising curved tail on the left. Preserve the exact amount of distant-leg occlusion. Keep the distinct right view instead of composing a frontal or 3/4 head.

Rear:

> True centered rear view only. The upward tail passes vertically in front of the center of the large round head from the viewer's perspective. Short rear legs on either side, small gap between them, small corner ears above the round cheeks. No visible face whatsoever, no eyes, nose or mouth. Do not enlarge the body or show a side of the face.

Upright:

> Exact front view balancing on two short back paws, two small curled forepaws held high together against its chest, high round head on a narrow body, neutral cream marks, thick curved tail to the viewer's right. Do not add a pose change, human limbs, wide stance, clothing or accessories.

Puffed:

> Same left-facing compact startled attitude, low front shoulder and head, back arched strongly higher than the hind legs with a restrained little raised wool ridge, tail almost straight up on the right and visibly puffed into rounded wool points. Tiny single eye. Preserve the original dark felt body, contact of fore/hind feet and recognizable outline.

Belly-up:

> Exact Russian-wheel-like belly-up horizontal resting pose in the first image: the face is rotated sideways at far left, its two cream eyes vertically aligned in the image, small original cream nose/mouth pointed inward to the right. Belly centered, four short rounded paws pointing up or curled over it, stout tail lies flat to the viewer's right. Do not twist the head toward frontal upright view or alter paw count.

Stretch:

> Exact extended running/stretch pose of first image: small round three-quarter head at the left, dark body diagonal and slightly lower toward front legs, two thick forelegs extended down-left, hind legs bent and extending right, raised thick tail diagonally up right. All original cream markings small. Hold the suspended/reaching action precisely while preserving the original reference back and face proportions.

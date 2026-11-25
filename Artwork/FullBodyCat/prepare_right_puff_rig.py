#!/usr/bin/env python3
"""Build right-facing puff contours and face registration from existing felt textures."""

import argparse
import json
from pathlib import Path

import numpy as np
from scipy import ndimage

from prepare_runtime_motion_rig import (
    GRID_POINTS, STAGE_SCALE, inverse_warp, positions, registered_image,
    sample_distance, signed_distance, source_grid, texture_layer,
)


# The SDK shares the preceding turn with rightward walking. Store only the arch.
ARCH_KEYS = (0.20, 0.40, 0.60, 0.80)

# Correspondences use the facing-right stage coordinates of both silhouettes.
# The final texture coordinates are reflected back into the approved left-facing PNG.
LANDMARKS = (
    # Tail tip, outer edge, stem and root.
    (27, 78, 52, 75), (37, 75, 58, 70), (52, 87, 77, 83),
    (54, 105, 82, 105), (60, 124, 80, 124), (73, 140, 76, 144),
    (66, 158, 67, 153), (52, 147, 56, 141), (39, 133, 44, 129),
    (29, 116, 39, 111), (22, 101, 38, 96), (38, 109, 61, 109),
    # Back, flank and belly fold.
    (79, 146, 85, 118), (101, 139, 103, 105), (124, 136, 125, 101),
    (144, 140, 140, 109), (153, 145, 152, 123), (154, 156, 152, 136),
    (148, 198, 140, 195), (130, 201, 128, 182), (120, 199, 116, 181),
    (103, 199, 107, 182), (86, 201, 98, 194), (76, 196, 89, 190),
    (68, 178, 80, 164), (115, 172, 117, 149), (132, 180, 137, 158),
    # Contact points and shoulder lift.
    (55, 191, 63, 187), (46, 207, 61, 205), (45, 218, 62, 217),
    (55, 222, 72, 222), (66, 216, 83, 220), (75, 204, 94, 205),
    (95, 214, 95, 215), (82, 216, 87, 215),
    (154, 199, 154, 188), (166, 213, 162, 208), (177, 223, 172, 222),
    (193, 221, 178, 222), (198, 211, 188, 211), (190, 194, 188, 195),
    # The face stays separate from the textures, with anchors pinned to the same warp.
    (153, 132, 143, 135), (159, 114, 155, 121), (173, 94, 171, 104),
    (194, 89, 181, 104), (202, 104, 194, 117), (220, 114, 209, 126),
    (232, 131, 217, 141), (237, 145, 220, 146), (233, 163, 218, 165),
    (211, 177, 205, 177), (188, 180, 189, 181), (166, 174, 169, 174),
    (224.6, 137.2, 212, 147), (233, 149, 216.7, 158), (231, 154, 214.9, 163),
)

SIDE_FACE = {
    "bounds": [151.1, 90.3, 84, 86.1],
    "left": [224.6, 137.2, 7, 12.6],
    "right": None,
    "muzzle": [233, 149, 3.8, 3, 231, 154],
    "eyeAngle": 0,
}
PUFF_FACE = {
    "bounds": [143, 101, 79, 83],
    "left": [212, 147, 7, 12],
    "right": None,
    "muzzle": [216.7, 158, 3.8, 3, 214.9, 163],
    "eyeAngle": 0,
}


def grounded(mask):
    regions, count = ndimage.label(mask)
    if count == 0:
        raise ValueError("The right-facing puff contour disappeared")
    if count > 1:
        sizes = np.bincount(regions.ravel())
        sizes[0] = 0
        mask = regions == sizes.argmax()
    shift = int(224 * STAGE_SCALE) - (np.nonzero(mask)[0].max() + 1)
    return ndimage.shift(mask, (shift, 0), order=0, cval=False), shift / STAGE_SCALE


def face_at(amount, lift):
    face = {}
    for key in ("bounds", "left", "muzzle"):
        face[key] = ((1 - amount) * np.array(SIDE_FACE[key]) + amount * np.array(PUFF_FACE[key])).tolist()
        face[key][1] += lift
    face["muzzle"][5] += lift
    face.update(right=None, eyeAngle=0)
    return face


def arch_frames(assets):
    right = np.asarray(registered_image(assets, "right").getchannel("A")) >= 128
    puff = np.asarray(registered_image(assets, "puff").getchannel("A"))[:, ::-1] >= 128
    fields = signed_distance(right), signed_distance(puff)
    first, last = positions(LANDMARKS)
    for amount in ARCH_KEYS:
        shape = (1 - amount) * first + amount * last
        source_a = inverse_warp(shape, first, smoothing=10)
        source_b = inverse_warp(shape, last, smoothing=10)
        contour = ((1 - amount) * sample_distance(fields[0], source_a(GRID_POINTS))
                   + amount * sample_distance(fields[1], source_b(GRID_POINTS)))
        solid, lift = grounded(contour >= 0)
        output_grid = GRID_POINTS - [0, lift]
        puff_grid = source_b(output_grid)
        puff_grid[:, 0] = 256 - puff_grid[:, 0]
        layer = texture_layer(solid, source_grid("right", source_a(output_grid)),
                              source_grid("puff", puff_grid), amount)
        yield [layer], face_at(amount, lift)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="directory containing the approved felt textures")
    parser.add_argument("output", type=Path, help="output numeric JSON")
    parser.add_argument("faces", type=Path, help="output face registrations")
    args = parser.parse_args()
    frames, faces = zip(*arch_frames(args.assets))
    args.output.write_text(json.dumps({"puffright": frames}, separators=(",", ":")) + "\n")
    args.faces.write_text(json.dumps(faces, indent=2) + "\n")


if __name__ == "__main__":
    main()

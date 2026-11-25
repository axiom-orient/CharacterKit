#!/usr/bin/env python3
"""Polish right/rear turns from the raw atlas produced by prepare_runtime_motion_rig.py."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from prepare_runtime_motion_rig import (
    CALIBRATION, FIXED_POINT, MASK_GRID, SIZE, STAGE_SCALE, affine_source,
    contours, mapped_mask, signed_distance,
)


X, Y = MASK_GRID / STAGE_SCALE
STANDING_FACE = (43, 97, 97, 82)
RIGHT_FACE = (153, 88, 85, 91)
HEADS = {
    "stand": ((38, 87), (131, 88), (141, 115), (144, 142),
              (138, 156), (126, 167), (111, 176), (91, 181), (38, 178)),
    "right": ((162, 82), (238, 82), (246, 137), (246, 184),
              (190, 184), (176, 175), (164, 163), (153, 150), (153, 128)),
}


def polygon(points, scale=STAGE_SCALE):
    canvas = Image.new("1", (SIZE, SIZE))
    ImageDraw.Draw(canvas).polygon([(x * scale, y * scale) for x, y in points], fill=1)
    return np.asarray(canvas).copy()


def coverage(layer):
    result = np.zeros((SIZE, SIZE), dtype=bool)
    for path in layer["paths"]:
        points = np.asarray(path).reshape(-1, 2) / FIXED_POINT
        result ^= polygon(points)
    return result


def image_alpha(assets, stem):
    with Image.open(assets / f"full-body-cat-{stem}.png") as image:
        return np.asarray(image.getchannel("A")) >= 128


def mapping(source, destination):
    """Map from the rig stage to a matching plane in a source cutout."""
    sx, sy, sw, sh = source
    x, y, width, height = destination
    matrix = np.diag([sw / width, sh / height])
    return matrix, np.array((sx, sy)) - matrix @ (x, y)


def texture_layer(mask, source, destination, source_box, second=None, mix=0):
    paths = contours(mask)
    layer = {"paths": paths, "a": affine_source(source, *mapping(source_box, destination))}
    if second and mix > 0:
        layer.update(b=affine_source(second[0], *mapping(second[1], destination)), mix=round(mix, 4))
    return layer


def small_holes(mask, maximum=19):
    holes = ndimage.binary_fill_holes(mask) & ~mask
    labels, _ = ndimage.label(holes)
    areas = np.bincount(labels.ravel())
    fill = (areas <= maximum * STAGE_SCALE ** 2)
    fill[0] = False
    return mask | fill[labels]


def clip_tail(layer, anchor, scale_x, scale_y):
    """Shorten the visible tail into its occlusion without moving its attachment."""
    old = np.asarray(layer["a"]["affine"])
    matrix, offset = old[:4].reshape(2, 2), old[4:]
    inverse = np.diag([1 / scale_x, 1 / scale_y])
    anchor = np.asarray(anchor)
    moved = mapped_mask(coverage(layer), inverse, anchor - inverse @ anchor)
    return {
        "paths": contours(moved),
        "a": affine_source(layer["a"]["asset"], matrix @ inverse, offset + matrix @ (anchor - inverse @ anchor)),
    }


def right_turn(frames, assets):
    faces = json.loads((CALIBRATION / "right-face.json").read_text())
    head = {name: image_alpha(assets, name) & polygon(shape) for name, shape in HEADS.items()}
    result = []
    for index, original in enumerate(frames, start=1):
        if not 2 <= index <= 9:
            result.append(original)
            continue
        x, y, width, height = face = np.asarray(faces[index - 1]["bounds"])
        base = coverage(original[0])
        old_tail = original[1] if len(original) > 1 else None
        tail = old_tail
        if old_tail and index == 3:
            tail = clip_tail(old_tail, (143, 132), 0.89, 0.65)
            old_visible = coverage(old_tail)
            base &= ~(old_visible & (Y < 130))
            base |= coverage(tail)

        profile = np.clip((index - 5) / 5, 0, 1)
        first_map = mapping(STANDING_FACE, face)
        second_map = mapping(RIGHT_FACE, face)
        from_stand = mapped_mask(head["stand"], *first_map)
        from_right = mapped_mask(head["right"], *second_map)
        head_mask = ((1 - profile) * signed_distance(from_stand) +
                     profile * signed_distance(from_right)) >= 0
        shoulder = y + height - 8
        # Round only the exposed shoulder near the turning cheek. Keep the tail
        # attachment and planted feet from the original connected matte.
        neck = (X > x - 13) & (X < x + width + 13) & (Y > y + 20) & (Y < shoulder)
        rounded = ndimage.gaussian_filter(base.astype(np.float32), sigma=5) >= 0.50
        base = small_holes(np.where(neck, rounded, base))
        head_mask &= base
        body = base & (Y >= shoulder - 7 - 0.08 * (X - (x + width / 2)))
        yy, xx = np.nonzero(body & (Y > 185))
        if len(xx) == 0:
            raise ValueError(f"No supporting feet in right frame {index}")
        x0, x1 = xx.min() / STAGE_SCALE, xx.max() / STAGE_SCALE
        body_bounds = (x0, shoulder, x1 - x0, 224 - shoulder)
        body_layer = texture_layer(body, "stand", body_bounds, (53, 166, 141, 58),
                                   ("right", (42, 165, 153, 59)), profile)
        head_layer = texture_layer(head_mask, "stand", face, STANDING_FACE, ("right", RIGHT_FACE), profile)
        backing = {**original[0], "paths": contours(base)}
        layers = [layer for layer in (backing, body_layer, tail, head_layer) if layer and layer["paths"]]
        result.append(layers)
    return result


def rear_turn(frames):
    result = []
    for index, original in enumerate(frames, start=1):
        if not 3 <= index <= 9:
            result.append(original)
            continue
        tail_layer, old_body = original
        main = small_holes(coverage(old_body))
        # Retain the established head/face registration. The planted lower half
        # borrows upright paws from the two source cutouts instead of dragging
        # their color bands across the chest as the body turns.
        chin = 166 - 16 * ((index - 3) / 6)
        paws = main & (Y >= chin + 4 * ((X - 126) / 59)**2)
        _, xx = np.nonzero(main & (Y >= 189))
        x0, x1 = xx.min() / STAGE_SCALE, xx.max() / STAGE_SCALE
        lower = (x0, chin, x1 - x0, 224 - chin)
        body_layer = texture_layer(paws, "stand", lower, (54, 170, 138, 54),
                                   ("rear", (73, 142, 111, 82)), min(1, (index - 2) / 7))
        old_body = {**old_body, "paths": contours(main)}
        result.append([tail_layer, old_body, body_layer])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path)
    parser.add_argument("base_rig", type=Path, help="unpolished numeric atlas")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rig = json.loads(args.base_rig.read_text())
    if any(len(frame) not in (1, 2) for frame in rig["right"]) or any(
        len(frame) != 2 for frame in rig["rear"]
    ):
        parser.error("Pass the unpolished atlas produced by prepare_runtime_motion_rig.py")
    result = {"right": right_turn(rig["right"], args.assets), "rear": rear_turn(rig["rear"])}
    args.output.write_text(json.dumps(result, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()

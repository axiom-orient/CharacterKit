from pathlib import Path
import argparse
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.interpolate import PchipInterpolator

from prepare_transition_frames import (
    BOUNDARIES,
    COLOR_PROFILE,
    FRAME_COUNT,
    SIZE,
    render,
    sampling_fields,
)

CALIBRATION = Path(__file__).parent / "Transitions" / "right-geometry.json"


def asset(root, name):
    return Image.open(root / f"full-body-cat-{name}.png").convert("RGBA")


def registered_front(path):
    im = Image.open(path).convert("RGBA")
    scale = 0.52 * 350 / max(im.size)
    offset_x = 24
    alpha = im.getchannel("A")
    offset_y = 224 - alpha.point(lambda p: 255 if p >= 128 else 0).getbbox()[3] * scale
    inv = 1 / (4 * scale)
    positioned = im.transform(
        (SIZE, SIZE),
        Image.Transform.AFFINE,
        (inv, 0, -offset_x / scale, 0, inv, -offset_y / scale),
        resample=Image.Resampling.BICUBIC,
    )
    rgba = np.asarray(positioned).copy()
    coverage = rgba[..., 3]
    # The generated master includes faint partial alpha in the centre of the
    # wool. Restore an opaque object, while keeping the perimeter anti-aliased.
    coverage[ndimage.binary_erosion(coverage >= 128, iterations=3)] = 255
    rgba[coverage < 9] = 0
    return Image.fromarray(rgba, "RGBA")


def separate(image, tail_area):
    region = Image.new("L", image.size)
    ImageDraw.Draw(region).polygon([(4 * x, 4 * y) for x, y in tail_area], fill=255)
    pixels = np.asarray(image).copy()
    a = pixels[..., 3].copy()
    cut = np.asarray(region) > 0
    pixels[..., 3] = np.where(cut, 0, a)
    body = Image.fromarray(pixels.copy(), "RGBA")
    pixels[..., 3] = np.where(cut, a, 0)
    tail = Image.fromarray(pixels, "RGBA")
    return body, tail


def relocate_tail(photo, source_root, source_tip, current_root, current_tip, thickness):
    p0 = np.asarray(source_root)
    p1 = np.asarray(source_tip)
    q0 = np.asarray(current_root)
    q1 = np.asarray(current_tip)
    source = p1 - p0
    target = q1 - q0
    cross = lambda v: np.array([-v[1], v[0]]) / np.linalg.norm(v)
    inverse = np.column_stack([source, cross(source)]) @ np.linalg.inv(
        np.column_stack([target, cross(target) * thickness])
    )
    origin = 4 * (p0 - inverse @ q0)
    return photo.transform(
        (SIZE, SIZE),
        Image.Transform.AFFINE,
        (*inverse[0], origin[0], *inverse[1], origin[1]),
        resample=Image.Resampling.BICUBIC,
    )


def shifted_front(front, index):
    # Keep the weight-bearing foot near its destination while the head-on key
    # completes the turn. The small shear closes the extreme shoulder mapping.
    head_offset = -14.8 if index == 4 else -7.4
    stretch = 1.115 if index == 4 else 1.055
    shear = -head_offset / 171
    tx = 4 * (126 - (126 + head_offset - 141 * shear) / stretch)
    return front.transform(
        (SIZE, SIZE),
        Image.Transform.AFFINE,
        (1 / stretch, -shear / stretch, tx, 0, 1, 0),
        resample=Image.Resampling.BICUBIC,
    )


def position(section):
    points = np.asarray(section, dtype=np.float64)
    return np.vstack([points[:, :2], BOUNDARIES]), np.vstack([points[:, 2:], BOUNDARIES])


def main():
    parser = argparse.ArgumentParser(
        description="Render the eleven body sprites for the felt cat's right turn."
    )
    parser.add_argument("assets", type=Path)
    parser.add_argument("front", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--samples", action="store_true")
    args = parser.parse_args()
    control = json.loads(CALIBRATION.read_text())
    stand = asset(args.assets, "stand")
    stand_tail = asset(args.assets, "stand-tail")
    trimmed_tail = stand_tail.copy()
    trimmed_tail.paste((0, 0, 0, 0), (0, 4 * 156, SIZE, SIZE))
    front = registered_front(args.front)
    front_body, front_tail = separate(
        front,
        [
            (0, 0),
            (88, 0),
            (88, 102),
            (87, 116),
            (85, 132),
            (82, 140),
            (76, 144),
            (70, 144),
            (0, 141),
        ],
    )
    right, right_tail = separate(
        asset(args.assets, "right"),
        [(0, 0), (103, 0), (103, 120), (88, 139), (82, 143), (73, 149), (65, 157), (0, 157)],
    )
    stage = [
        ((sampling_fields(stand), sampling_fields(front_body)), position(control["approach"])),
        ((sampling_fields(front_body), sampling_fields(right)), position(control["depart"])),
    ]
    # Pull the tail behind the head during the directional crossover, then
    # let the same wool texture emerge on the left as the hip opens out.
    track = np.array(
        [
            [0.0, 166, 148, 196, 94, 1.0],
            [0.16, 151, 150, 172, 98, 0.94],
            [0.28, 142, 151, 146, 113, 0.80],
            [0.36, 122, 151, 120, 132, 0.72],
            [0.43, 95, 148, 87, 113, 0.85],
            [0.5, 77, 143, 72, 105, 1.0],
            [0.66, 75, 145, 60, 99, 0.98],
            [0.82, 73, 146, 49, 92, 1.0],
            [1.0, 73, 146, 38, 89, 1.0],
        ]
    )
    motion = PchipInterpolator(track[:, 0], track[:, 1:], axis=0)
    args.output.mkdir(parents=True, exist_ok=True)
    dest = args.output / "right"
    dest.mkdir(parents=True, exist_ok=True)
    frames = [2, 4, 5, 6, 7, 8, 10] if args.samples else range(1, FRAME_COUNT + 1)
    for i in frames:
        t = i / (FRAME_COUNT + 1)
        if i == 6:
            layered = front
        else:
            segment, part = (0, 2 * t) if t < 0.5 else (1, 2 * t - 1)
            fields, points = stage[segment]
            body = (
                shifted_front(front_body, i)
                if i in (4, 5)
                else render(fields, points, part, smoothing=25)
            )
            x, y, tx, ty, width = motion(t)
            root, tip = (x, y), (tx, ty)
            if t < 0.34:
                tail = relocate_tail(
                    trimmed_tail if i == 3 else stand_tail, (166, 148), (196, 94), root, tip, width
                )
            elif t < 0.62:
                tail = relocate_tail(front_tail, (77, 143), (72, 105), root, tip, width)
            else:
                tail = relocate_tail(right_tail, (73, 146), (38, 89), root, tip, width)
            layered = Image.alpha_composite(tail, body)
        layered.save(dest / f"full-body-cat-transition-right-{i}.png", icc_profile=COLOR_PROFILE)


if __name__ == "__main__":
    main()

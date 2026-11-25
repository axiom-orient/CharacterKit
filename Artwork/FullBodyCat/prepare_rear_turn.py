#!/usr/bin/env python3
"""Continue the approved left turn into the rear pose with articulated wool plates."""

import argparse
import json
from pathlib import Path

import numpy as np
from scipy import ndimage
from scipy.interpolate import PchipInterpolator

from prepare_runtime_motion_rig import (
    CALIBRATION, GRID_POINTS, STAGE_SCALE, affine_source, contours, mapped_mask,
    signed_distance, source_grid, tail_transform,
)
from prepare_turn_polish import image_alpha, mapping, polygon, small_holes, X, Y


LEFT_KEYS = (1, 3, 5, 8)
TURN_WEIGHTS = (.11, .25, .41, .59, .77, .94)
HEAD_BOX = ((18.1, 90.3, 83.3, 89.6), (67, 78, 121, 84))
TORSO_BOX = ((41, 133, 171, 91), (73, 130, 111, 94))
TAIL_LEFT = ((189, 151), (222, 77))
TAIL_REAR = ((128, 162), (131, 67))
EAR_TIPS = ((0, .48, .60, 1), (0, .12, .89, 1))


def mix(first, last, fraction):
    return (1 - fraction) * np.asarray(first) + fraction * np.asarray(last)


def rear_head_box(fraction):
    box = mix(*HEAD_BOX, fraction)
    # The crown lifts slightly as the cat looks over its shoulder.
    lift = 4 * np.sin(np.pi * fraction)
    return box + (0, -lift, 0, lift)


def source_masks(assets):
    left = image_alpha(assets, "left")
    rear = image_alpha(assets, "rear")
    left_tail = left & polygon(((171, 142), (198, 105), (203, 82), (216, 55),
                               (243, 55), (248, 98), (233, 130), (211, 156), (192, 169)))
    rear_tail = rear & polygon(((102, 158), (111, 103), (111, 77), (119, 59), (139, 59),
                               (153, 75), (153, 105), (148, 137), (139, 164)))
    left_head = left & polygon(((8, 73), (105, 73), (112, 127), (103, 149),
                               (92, 163), (79, 181), (8, 182)))
    crown = 90 + .008 * (X - 129) ** 2
    rear_head = rear & (Y >= 74) & (Y < 164) & ~(rear_tail & (Y < crown))
    left_torso = left & ~left_tail & (Y >= 133) & ((X > 97) | (Y >= 168))
    rear_torso = rear & (Y >= 130 + .018 * (X - 129) ** 2)
    return (left, left_head, left_torso, left_tail), (rear_head, rear_torso, rear_tail)


def draw_plate(first, last, first_map, last_map, amount):
    a = mapped_mask(first, *first_map)
    b = mapped_mask(last, *last_map)
    solid = mix(signed_distance(a), signed_distance(b), amount) >= 0
    return solid, {
        "a": affine_source("left", *first_map),
        "b": affine_source("rear", *last_map),
        "mix": round(float(amount), 4),
    }


def turning_head(first, last, points, head, root, tip, fraction):
    ears = mix(*EAR_TIPS, fraction)
    x, y, width, height = head

    def mapping_from(source, source_ears):
        sx, sy, sw, sh = source
        crown = PchipInterpolator(ears, source_ears)

        def inverse(samples):
            u = (samples[..., 0] - x) / width
            v = (samples[..., 1] - y) / height
            fade = np.clip((v - .16) / .39, 0, 1)
            fade = fade * fade * (3 - 2 * fade)
            inside = np.clip(u, 0, 1)
            matched = u + (1 - fade) * (crown(inside) - inside)
            return np.stack((sx + sw * matched, sy + sh * v), axis=-1)

        return inverse

    left_map, rear_map = (mapping_from(box, source_ears)
                          for box, source_ears in zip(HEAD_BOX, EAR_TIPS))
    fields = []
    for distance, inverse in zip((first, last), (left_map, rear_map)):
        pixels = inverse(points) * STAGE_SCALE
        fields.append(ndimage.map_coordinates(distance, (pixels[..., 1], pixels[..., 0]),
                                               order=1, cval=-256))
    solid = ndimage.gaussian_filter(mix(*fields, fraction), sigma=6) >= 0
    rear_samples = rear_map(GRID_POINTS)
    # Align the baked rear tail shadow with the actual tail at each height.
    rows = GRID_POINTS[:, 1]
    moving_x = tip[0] + (root[0] - tip[0]) * ((rows - tip[1]) / (root[1] - tip[1]))
    sample_y = rear_samples[:, 1]
    rear_x = 131 - .065 * (sample_y - 108)
    positions = np.column_stack((moving_x, rows))
    rear_samples[:, 0] += rear_x - rear_map(positions)[:, 0]
    pigment = np.clip((fraction - .76) / .18, 0, 1)
    return solid, {
        "a": source_grid("left", left_map(GRID_POINTS)),
        "b": source_grid("rear", rear_samples),
        "mix": round(float(pigment), 4),
    }


def rear_turn(assets, left_frames):
    source, target = source_masks(assets)
    left, left_head, left_torso, left_tail = source
    rear_head, rear_torso, rear_tail = target
    identity = (np.eye(2), np.zeros(2))
    frames = [left_frames[index - 1] for index in LEFT_KEYS]
    frames.append([{"paths": contours(left), "a": affine_source("left", *identity)}])
    points = np.stack((X, Y), axis=-1)
    first, last = signed_distance(left_head), signed_distance(rear_head)
    for fraction in TURN_WEIGHTS:
        head = rear_head_box(fraction)
        # Ease the tail and rump through the middle without changing face timing.
        turn = fraction + .037 * np.sin(2 * np.pi * fraction)
        torso = mix(*TORSO_BOX, turn)
        root, tip = mix(TAIL_LEFT, TAIL_REAR, turn)
        tail_width = 1 - 0.12 * np.sin(np.pi * turn)
        head_solid, head_color = turning_head(first, last, points, head, root, tip, fraction)
        body_solid, body_color = draw_plate(
            left_torso, rear_torso, mapping(TORSO_BOX[0], torso), mapping(TORSO_BOX[1], torso),
            turn)
        tail_solid, tail_color = draw_plate(
            left_tail, rear_tail, tail_transform(*TAIL_LEFT, root, tip, tail_width),
            tail_transform(*TAIL_REAR, root, tip, tail_width), turn)
        # The neck and tail roots overlap behind solids. Fill enclosed one-part
        # pinholes without changing the open gap between planted paws.
        closed = small_holes(head_solid | body_solid | tail_solid, maximum=24)
        body_solid |= closed & ~(head_solid | body_solid | tail_solid)
        body_solid = ndimage.binary_closing(body_solid, iterations=2)
        tail = {"paths": contours(tail_solid), **tail_color}
        head_layer = {"paths": contours(head_solid), **head_color}
        body_layer = {"paths": contours(body_solid), **body_color}
        # Roll the rump up over the lower cheek as the near hip turns toward
        # the viewer. The curved edge preserves the head's round outline.
        hip_width = torso[2] * .5
        hip_center = torso[0] + hip_width
        roll = mix(181, 130, turn)
        hip_edge = roll + 28 * ((X - hip_center) / hip_width) ** 2
        foreground_hip = head_solid & body_solid & (Y >= hip_edge)
        # The tail sweeps across the back with its root tucked into the hip.
        tail_edge = mix(112, 158, turn) - .28 * np.abs(X - root[0])
        exposed_tail = tail_solid & (Y < tail_edge)
        frame = [tail, body_layer, head_layer,
                 {"paths": contours(foreground_hip), **body_color},
                 {"paths": contours(exposed_tail), **tail_color}]
        frames.append([layer for layer in frame if layer["paths"]])
    return frames


def face_registration():
    left = json.loads((CALIBRATION / "left-face.json").read_text())
    frames = [left[index - 1] for index in LEFT_KEYS]
    frames.append({"bounds": list(HEAD_BOX[0]), "left": None, "right": [27.2, 136.5, 7.7, 13.3],
                   "muzzle": [22.3, 147.8, 3.8, 3, 24.1, 153], "eyeAngle": 0})
    for fraction in TURN_WEIGHTS:
        bounds = rear_head_box(fraction)
        source, offset = mapping(bounds, HEAD_BOX[0])

        def transform(point):
            return (source @ point + offset).tolist()

        visibility = max(.18, 1 - 1.5 * fraction)
        frames.append({"bounds": bounds.tolist(), "left": None, "eyeAngle": 0,
                       "right": [*transform((27.2, 136.5)), 7.7 * visibility, 13.3 * visibility],
                       "muzzle": [*transform((22.3, 147.8)), 3.8 * visibility, 3 * visibility,
                                  *transform((24.1, 153))]})
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path)
    parser.add_argument("base_rig", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--face-output", type=Path)
    args = parser.parse_args()
    atlas = json.loads(args.base_rig.read_text())
    args.output.write_text(json.dumps({"rear": rear_turn(args.assets, atlas["left"])},
                                      separators=(",", ":")) + "\n")
    if args.face_output:
        args.face_output.write_text(json.dumps(face_registration(), indent=2) + "\n")


if __name__ == "__main__":
    main()

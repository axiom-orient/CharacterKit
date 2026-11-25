#!/usr/bin/env python3
"""Rebuild the right turn's visible torso and tail using the registered wool layers."""

import argparse
import json
from pathlib import Path

import numpy as np
from scipy import ndimage
from scipy.interpolate import PchipInterpolator

from prepare_turn_polish import (
    HEADS, RIGHT_FACE, STANDING_FACE, X, Y, coverage, image_alpha, mapping, polygon,
    small_holes,
)
from prepare_runtime_motion_rig import (
    CALIBRATION, GRID_POINTS, STAGE_SCALE, affine_source, contours, mapped_mask, signed_distance,
    source_grid, tail_transform,
)


# The ribcage foreshortens during the front view and then broadens to profile.
# The feet keep their existing contact key poses below the torso.
TORSO = {
    2: (116, 176, 57, 28),
    3: (113, 179, 49, 27),
    4: (109, 181, 39, 27),
    5: (114, 181, 39, 27),
    6: (117, 178, 44, 28),
    7: (115, 176, 52, 29),
    8: (116, 173, 59, 32),
    9: (117, 171, 65, 34),
}

# The tip disappears behind the head and returns on the other side as the
# body turns. Each root stays below the surface of the visible ribcage.
TAIL = {
    2: ((153, 160), (175, 101), 0.83),
    3: ((148, 165), (156, 111), 0.69),
    4: ((146, 164), (157, 123), 0.57),
    5: ((98, 167), (91, 134), 0.52),
    6: ((85, 164), (72, 105), 0.77),
    7: ((84, 163), (65, 101), 0.81),
    8: ((78, 161), (54, 93), 0.90),
    9: ((75, 157), (46, 86), 0.97),
}

# Crown anchors in normalized head coordinates. Near and far tips correspond
# through the turn, including when they overlap in profile.
CROWN = ((0, .21, .83, 1), (0, .34, .51, 1))


def ease(amount):
    amount = np.clip(amount, 0, 1)
    return amount * amount * (3 - 2 * amount)


def crown_mapping(face, source, target_crown, source_crown):
    x, y, width, height = face
    sx, sy, sw, sh = source
    curve = PchipInterpolator(target_crown, source_crown)

    def inverse(points):
        u = (points[..., 0] - x) / width
        v = (points[..., 1] - y) / height
        crown_weight = 1 - ease((v - .24) / .28)
        matched = curve(np.clip(u, 0, 1)) + u - np.clip(u, 0, 1)
        return np.stack((sx + sw * (u + crown_weight * (matched - u)), sy + sh * v), axis=-1)

    return inverse


def shoulder_mapping(source, bounds, wool):
    affine = np.asarray(source["affine"])
    matrix, offset = affine[:4].reshape(2, 2), affine[4:]
    upper_matrix, upper_offset = mapping(wool, bounds)

    def inverse(points):
        lower = points @ matrix.T + offset
        upper = points @ upper_matrix.T + upper_offset
        weight = 1 - ease((points[..., 1:2] - 168) / 28)
        return lower + (upper - lower) * weight

    return source_grid(source["asset"], inverse(GRID_POINTS))


def tail_layer(stem, source, first, end, root, tip, width, obscuring_parts):
    matrix, offset = tail_transform(*map(np.asarray, (first, end, root, tip)), width)
    matte = mapped_mask(source, matrix, offset)
    labels, _ = ndimage.label(matte)
    connected = np.bincount(labels[matte & obscuring_parts].ravel())
    if len(connected) < 2:
        return None
    connected[0] = 0
    result = contours(labels == connected.argmax())
    return {"a": affine_source(stem, matrix, offset), "paths": result} if result else None


def polish(frames, assets):
    faces = json.loads((CALIBRATION / "right-face.json").read_text())
    heads = [image_alpha(assets, name) & polygon(HEADS[name]) for name in ("stand", "right")]
    standing = image_alpha(assets, "stand-tail") & polygon(
        [(0, 0), (256, 0), (256, 148), (188, 148), (176, 158), (166, 163), (156, 157), (0, 157)]
    )
    profile = image_alpha(assets, "right") & polygon(
        [(0, 0), (103, 0), (103, 120), (88, 139), (82, 143), (73, 149), (65, 157), (0, 157)]
    )
    result = list(frames)
    image_points = np.stack((X, Y), axis=-1)
    for index, (cx, cy, rx, ry) in TORSO.items():
        # This can run from the prior volume pass or prepare_turn_polish.py.
        # Their torso plate is penultimate in the first case and second in
        # the second case, while the head is always last.
        layers = frames[index - 1]
        body = layers[1] if "grid" in layers[0]["a"] else layers[-2]
        projected = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 <= 1
        old_torso = coverage(body)
        foot_weight = ease((Y - 184) / 24)
        torso_distance = ((1 - foot_weight) * signed_distance(projected)
                          + foot_weight * signed_distance(old_torso))
        torso = np.where(Y >= 208, old_torso, ndimage.gaussian_filter(torso_distance, sigma=6) >= 0)
        body = {**body, "paths": contours(torso)}

        if index in (6, 7, 8, 9) and "affine" in body["a"]:
            shoulder = (cx - rx, cy - ry, 2 * rx, 2 * ry)
            body["a"] = shoulder_mapping(body["a"], shoulder, (134, 146, 56, 51))
            if "b" in body:
                body["b"] = shoulder_mapping(body["b"], shoulder, (65, 143, 103, 60))

        face = np.asarray(faces[index - 1]["bounds"])
        amount = np.clip((index - 5) / 5, 0, 1)
        target_crown = (1 - amount) * np.asarray(CROWN[0]) + amount * np.asarray(CROWN[1])
        stand_map = crown_mapping(face, STANDING_FACE, target_crown, CROWN[0])
        right_map = crown_mapping(face, RIGHT_FACE, target_crown, CROWN[1])
        first = stand_map(image_points) * STAGE_SCALE
        second = right_map(image_points) * STAGE_SCALE
        distances = [ndimage.map_coordinates(signed_distance(mask), (points[..., 1], points[..., 0]),
                                             order=1, cval=-256)
                     for mask, points in zip(heads, (first, second))]
        face_distance = (1 - amount) * distances[0] + amount * distances[1]
        x, y, width, height = face
        cheek = (((X - x - width * .49) / (width * .52)) ** 2
                 + ((Y - y - height * .55) / (height * .46)) ** 2 <= 1)
        # Remove the edge of the source shoulder from the rotating cheek.
        face_distance = np.where(Y >= y + height * .37,
                                 np.minimum(face_distance, signed_distance(cheek)), face_distance)
        head_matte = ndimage.gaussian_filter(face_distance, sigma=6) >= 0
        head = {
            "paths": contours(head_matte),
            "a": source_grid("stand", stand_map(GRID_POINTS)),
            "b": source_grid("right", right_map(GRID_POINTS)),
            "mix": round(float(amount), 4),
        }
        tail = None
        if index in TAIL:
            source = (
                ("stand-tail", standing, (165, 153), (198, 83)) if index < 5
                else ("right", profile, (72, 147), (38, 77))
            )
            tail = tail_layer(*source, *TAIL[index], torso | head_matte)
        if tail:
            solid = torso | head_matte | coverage(tail)
            filled = small_holes(solid, maximum=6)
            if np.any(filled & ~solid):
                body["paths"] = contours(torso | (filled & ~solid))

        result[index - 1] = [layer for layer in (tail, body, head) if layer]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="approved endpoint textures")
    parser.add_argument("atlas", type=Path, help="registered atlas after prepare_turn_polish.py")
    parser.add_argument("output", type=Path, help="right route override")
    args = parser.parse_args()
    right = json.loads(args.atlas.read_text())["right"]
    args.output.write_text(json.dumps({"right": polish(right, args.assets)}, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()

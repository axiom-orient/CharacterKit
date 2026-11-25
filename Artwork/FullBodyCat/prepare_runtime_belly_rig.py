#!/usr/bin/env python3
"""Export the felt belly-roll layers as geometry and inverse source transforms."""

import argparse
import json
from pathlib import Path

import numpy as np
from scipy.ndimage import affine_transform, binary_dilation, distance_transform_edt, gaussian_filter, gaussian_filter1d

from prepare_belly_transition import (
    DENSITY, GROUND, PIXELS, composite_part, ease, normalize, register_face, registered_layers,
    roll_layer_pose,
)
from prepare_runtime_motion_rig import affine_source, contours


# Even out the change in silhouette by sampling more closely while the
# shoulder takes the weight. Keep smaller steps near the resting endpoints.
ROLL_SAMPLES = (0.217, 0.290, 0.355, 0.412, 0.463, 0.508, 0.551, 0.600, 0.676, 0.753, 0.843)


def round_dorsal_edge(coverage, amount):
    # Restrict the adjustment to the exposed torso strip between the head
    # and the tail root. The legs, floor contact and face are separate layers.
    window = ease(amount, 0.12, 0.32) * (1 - ease(amount, 0.68, 0.86))
    if window == 0:
        return coverage
    filled = coverage >= 0.5
    valid_columns = np.flatnonzero(filled.any(axis=0))
    ridge = np.argmax(filled[:, valid_columns], axis=0)
    smooth = gaussian_filter1d(ridge.astype(float), sigma=4.5 * DENSITY)
    x = valid_columns / DENSITY
    weight = window * ease(x, 113, 128) * (1 - ease(x, 160, 176))
    change = np.clip(smooth - ridge, -2.5 * DENSITY, 2.5 * DENSITY) * weight
    active = np.abs(change) > 0.05
    if not np.any(active):
        return coverage
    columns = valid_columns[active]
    edge = ridge[active]
    new_edge = edge + change[active]
    y = np.arange(coverage.shape[0])[:, None]
    ramp = np.clip(y - new_edge + 0.5, 0, 1)
    coverage[:, columns] = np.where(
        y <= np.maximum(edge, new_edge) + 2, ramp, coverage[:, columns]
    )
    return coverage


def tuck_near_paw(coverage, pose, weight):
    # Foreshorten the turned paw on screen. Keep its contact edge in the same
    # place until the flank takes the weight, so head and face stay registered.
    occupied = np.flatnonzero(np.any(coverage >= 0.5, axis=1))
    if not occupied.size:
        return coverage
    scale = 1 - 0.18 * weight
    origin = pose.center[0] * DENSITY
    squeezed = affine_transform(coverage, (1, 1 / scale), (0, origin * (1 - 1 / scale)), order=1)
    smoothed = gaussian_filter(squeezed, 7)
    pad = squeezed + weight * (smoothed - squeezed)
    bottom = occupied[-1]
    free = 1 - ease(np.arange(PIXELS)[:, None], bottom - 4 * DENSITY, bottom - 2 * DENSITY)
    pose.matrix = np.diag((scale, 1)) @ pose.matrix
    pose.inverse = np.linalg.inv(pose.matrix)
    return coverage + free * (pad - coverage)


def soften_loaded_flank(coverage, amount):
    # During the roll the outer paws tuck over the flank. Round the short
    # seams between their pads without softening the face or the tail tip.
    window = ease(amount, 0.38, 0.50) * (1 - ease(amount, 0.64, 0.82))
    if window == 0:
        return coverage
    y, x = np.ogrid[:PIXELS, :PIXELS]
    x, y = x / DENSITY, y / DENSITY
    weight = window * ease(x, 89, 109) * (1 - ease(x, 168, 187)) * ease(y, 178, 206)
    smooth = gaussian_filter(coverage, (1.4 * DENSITY, 2.5 * DENSITY))
    return coverage + weight * (smooth - coverage)


def roll_frames(source_dir, face_coordinates=None):
    layers = registered_layers(source_dir)
    frames = []
    for amount in ROLL_SAMPLES:
        roll = ease(amount)
        tuck = ease(amount, 0.30, 0.46) * (1 - ease(amount, 0.69, 0.86))
        poses = []
        weights = []
        alpha = []
        matte = np.zeros((PIXELS, PIXELS, 4), dtype=np.float32)
        for index, (source, target) in enumerate(layers):
            pose, weight = roll_layer_pose(index, source, target, amount, roll)
            part = np.zeros_like(matte)
            composite_part(part, source, target, pose, weight, round_back=index == 3)
            poses.append(pose)
            weights.append(weight)
            coverage = part[:, :, 3]
            if index == 3:
                coverage = round_dorsal_edge(coverage, amount)
            if tuck > 0 and index in (4, 5):
                coverage = tuck_near_paw(coverage, pose, tuck)
            alpha.append(coverage.copy())
            matte[:, :, 3] = coverage + matte[:, :, 3] * (1 - coverage)

        matte[:, :, 3] = soften_loaded_flank(matte[:, :, 3], amount)
        png, max_y = normalize(matte, amount)
        floor_displacement = GROUND * DENSITY - max_y
        if face_coordinates is not None:
            head_start, head_end = layers[-1]
            face_coordinates.append(register_face(
                head_start.pose, head_end.pose, poses[-1], weights[-1], floor_displacement / DENSITY
            ))
        registered_solid = png[:, :, 3] >= 128
        # The paths overlap inside the toy, keeping small curve simplifications
        # from opening a seam between neighboring articulated parts.
        masks = [binary_dilation(coverage >= 0.5, iterations=2) & registered_solid for coverage in alpha]
        covered = np.any(masks, axis=0)
        missing = registered_solid & ~covered
        if np.any(missing):
            nearest = distance_transform_edt(~covered, return_distances=False, return_indices=True)
            for mask in masks:
                mask[missing] = mask[nearest[0][missing], nearest[1][missing]]

        frame = []
        for index, (source, target) in enumerate(layers):
            pose = poses[index]
            origin = pose.center + (0, floor_displacement / DENSITY)

            def texture(name, layer):
                matrix = layer.pose.matrix @ pose.inverse
                translation = layer.pose.center - matrix @ origin
                return affine_source(name, np.round(matrix, 6), np.round(translation, 5))

            paths = contours(np.roll(masks[index], floor_displacement, axis=0))
            if paths:
                frame.append({
                    "paths": paths,
                    "a": texture("stand-tail" if index == 0 else "stand", source),
                    "b": texture("belly", target),
                    "mix": round(float(weights[index]), 6),
                })
        frames.append(frame)
    return frames


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--face-json", type=Path)
    args = parser.parse_args()
    face_coordinates = [] if args.face_json else None
    with args.output_json.open("w", encoding="utf-8") as stream:
        json.dump({"belly": roll_frames(args.source_dir, face_coordinates)}, stream, separators=(",", ":"))
        stream.write("\n")
    if args.face_json:
        args.face_json.write_text(json.dumps(face_coordinates, indent=2) + "\n", encoding="utf-8")

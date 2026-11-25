#!/usr/bin/env python3
"""Finish the existing profile and gait layers from freshly prepared felt artwork."""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, PngImagePlugin
from scipy import ndimage


PIXELS_PER_POINT = 4
SIDE = 256 * PIXELS_PER_POINT
TAIL_ROOTS = {
    "left": ((174.75, 141.5), (190.75, 158.25)),
    "right": ((82, 141.75), (63.5, 158.5)),
}
HIND_FOLDS = {
    "left": ((154.25, 200), (177.75, 205.75)),
    "right": ((102.5, 201.75), (83.25, 205)),
}


def load(directory, name):
    with Image.open(directory / f"full-body-cat-{name}.png") as image:
        if image.size != (SIDE, SIDE):
            raise ValueError(f"Expected a {SIDE} × {SIDE} felt layer for {name}")
        return np.array(image.convert("RGBA"))


def save(directory, name, pixels):
    metadata = PngImagePlugin.PngInfo()
    metadata.add(b"sRGB", b"\x00")
    Image.fromarray(pixels).save(directory / f"full-body-cat-{name}.png", pnginfo=metadata, optimize=True)


def blend_wool_lighting(pixels, root, end, radius, sigma):
    """Blend local wool lighting while keeping the fibres and alpha coverage."""
    # Limit field processing to the root and enough opaque context for the broad filter.
    tile_radius = 35
    xmin, ymin = np.floor((np.minimum(root, end) - tile_radius) * PIXELS_PER_POINT).astype(int)
    xmax, ymax = np.ceil((np.maximum(root, end) + tile_radius) * PIXELS_PER_POINT).astype(int)
    tile = pixels[ymin:ymax, xmin:xmax]
    rows, columns = np.indices(tile.shape[:2], dtype=np.float32)
    x = (columns + xmin + 0.5) / PIXELS_PER_POINT
    y = (rows + ymin + 0.5) / PIXELS_PER_POINT
    dx, dy = np.subtract(end, root)
    progress = np.clip(((x - root[0]) * dx + (y - root[1]) * dy) / (dx * dx + dy * dy), 0, 1)
    distance = np.hypot(x - root[0] - progress * dx, y - root[1] - progress * dy)
    band = np.cos(0.5 * np.pi * np.minimum(1, distance / radius)) ** 2
    alpha = tile[:, :, 3].astype(np.float32) / 255
    rgb = tile[:, :, :3].astype(np.float32)
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

    def lighting(sigma):
        weighted = ndimage.gaussian_filter(luminance * alpha, sigma)
        return weighted / np.maximum(ndimage.gaussian_filter(alpha, sigma), 1e-7)

    delta = (lighting(sigma) - lighting(3.4)) * band * (alpha > 0)
    tile[:, :, :3] = np.rint(np.clip(rgb + delta[:, :, None], 0, 255)).astype(np.uint8)
    return pixels


def far_foreleg(near):
    """Fit the near paw's rounded wool to the farther shoulder and toe anchors."""
    near_hip, near_toe = np.array([73.5, 184.75]), np.array([64.5, 219])
    far_hip, far_toe = np.array([64.25, 181]), np.array([47.5, 212])
    near_axis, far_axis = near_toe - near_hip, far_toe - far_hip
    near_normal = np.array([near_axis[1], -near_axis[0]]) / np.linalg.norm(near_axis)
    far_normal = np.array([far_axis[1], -far_axis[0]]) / np.linalg.norm(far_axis)

    # Resample in premultiplied color so the wool outline acquires no matte fringe.
    rows, columns = (np.indices((SIDE, SIDE), dtype=np.float32) + 0.5) / PIXELS_PER_POINT
    centered_x, centered_y = columns - far_hip[0], rows - far_hip[1]
    reach = (centered_x * far_axis[0] + centered_y * far_axis[1]) / (far_axis @ far_axis)
    cross_axis = centered_x * far_normal[0] + centered_y * far_normal[1]
    # Inset the upper foreleg at crossover. Taper the shift away before the paw.
    rise = np.clip((reach + 0.28) / 0.53, 0, 1)
    fall = np.clip((0.78 - reach) / 0.34, 0, 1)
    envelope = rise**2 * (3 - 2 * rise) * fall**2 * (3 - 2 * fall)
    across = cross_axis / (0.57 + np.sign(cross_axis) * 0.34 * envelope)
    source_x = near_hip[0] + reach * near_axis[0] + across * near_normal[0]
    source_y = near_hip[1] + reach * near_axis[1] + across * near_normal[1]
    coordinates = np.stack((source_y, source_x)) * PIXELS_PER_POINT - 0.5
    alpha = near[:, :, 3].astype(np.float32) / 255
    sample = ndimage.map_coordinates(alpha, coordinates, order=1, prefilter=False)
    output = np.zeros_like(near)
    output[:, :, 3] = np.rint(sample * 255).astype(np.uint8)
    for channel in range(3):
        wool = ndimage.map_coordinates(near[:, :, channel] * alpha, coordinates, order=1, prefilter=False)
        color = 0.96 * wool / np.maximum(sample, 1e-7)
        output[:, :, channel] = np.rint(np.clip(color, 0, 255)).astype(np.uint8)
    output[output[:, :, 3] == 0] = 0
    return output


def smooth_hind_cut(pixels, side):
    """Round the far paw's exposed cut tip without changing its root or pad."""
    # The leading cut has a short flat ledge at this height. Round only
    # that turn; the far paw must still overlap the belly throughout gait.
    x_range = (147, 163) if side == "left" else (94, 109)
    x0, x1 = (coordinate * PIXELS_PER_POINT for coordinate in x_range)
    y0, y1 = 193 * PIXELS_PER_POINT, 209 * PIXELS_PER_POINT
    alpha = pixels[:, :, 3]
    # A small morphological opening softens the corner while retaining the
    # actual paw contour everywhere outside the calibrated slice.
    tile = alpha[(y0 - 16):(y1 + 16), (x0 - 16):(x1 + 16)]
    y, x = np.ogrid[-9:10, -9:10]
    smooth = ndimage.binary_opening(tile >= 128, structure=x * x + y * y <= 81)
    coverage = np.clip(ndimage.distance_transform_edt(smooth) - ndimage.distance_transform_edt(~smooth) + 0.5, 0, 1)
    coverage = ndimage.gaussian_filter(coverage, 0.7)[16:-16, 16:-16]
    target = alpha[y0:y1, x0:x1]
    target[:] = np.minimum(target, np.rint(coverage * 255).astype(np.uint8))
    pixels[alpha == 0] = 0
    return pixels


def clear_stray_fibres(pixels):
    alpha = pixels[:, :, 3]
    regions, _ = ndimage.label(alpha >= 96, structure=np.ones((3, 3)))
    areas = np.bincount(regions.ravel())
    areas[0] = 0
    wool = regions == areas.argmax()
    pixels[ndimage.distance_transform_edt(~wool) > PIXELS_PER_POINT] = 0
    return pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prepared", type=Path, help="fresh aligned profiles and gait split PNGs")
    parser.add_argument("output", type=Path, help="directory for the finished layers")
    args = parser.parse_args()
    if args.prepared.resolve() == args.output.resolve():
        parser.error("Use a separate output directory to keep the prepared artwork available.")
    args.output.mkdir(parents=True, exist_ok=True)
    for side, (root, end) in TAIL_ROOTS.items():
        for name in (side, f"{side}-walk-body"):
            save(args.output, name, blend_wool_lighting(load(args.prepared, name), root, end, 13.5, 20))
        name = f"{side}-walk-far-hind"
        pixels = smooth_hind_cut(load(args.prepared, name), side)
        save(args.output, name, blend_wool_lighting(pixels, *HIND_FOLDS[side], 8, 15))
    near_front = clear_stray_fibres(load(args.prepared, "left-walk-near-front"))
    save(args.output, "left-walk-near-front", near_front)
    save(args.output, "left-walk-far-front", clear_stray_fibres(far_foreleg(near_front)))


if __name__ == "__main__":
    main()

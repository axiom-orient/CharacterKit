from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image, ImageCms
from scipy import ndimage as ndi
from scipy.interpolate import RBFInterpolator

SIZE = 1024
SCALE = SIZE / 256
FRAME_COUNT = 11
COLOR_PROFILE = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
BOUNDARIES = np.array(
    [(x, y) for x in (0, 64, 128, 192, 256) for y in (0, 256)]
    + [(x, y) for x in (0, 256) for y in (48, 96, 144, 192, 240)]
)
SAMPLE_Y, SAMPLE_X = np.mgrid[0:257:2, 0:257:2]
SAMPLE_POINTS = np.stack([SAMPLE_X.ravel(), SAMPLE_Y.ravel()], axis=-1)


def display_image(asset_root, pose):
    asset = Image.open(asset_root / f"full-body-cat-{pose}.png").convert("RGBA")
    if pose == "stand":
        tail = Image.open(asset_root / "full-body-cat-stand-tail.png").convert("RGBA")
        asset = Image.alpha_composite(tail, asset)
    return asset


def sampling_fields(image):
    data = np.asarray(image, dtype=np.float32) / 255
    alpha = data[..., 3]
    foreground = alpha >= 0.5
    outside, nearest = ndi.distance_transform_edt(~foreground, return_indices=True)
    inside = ndi.distance_transform_edt(foreground)
    distance = np.where(foreground, inside - 0.5, 0.5 - outside)
    # Preserve the original anti-alias values in the immediate contour.
    edge = (alpha > 0) & (alpha < 1)
    distance[edge] = alpha[edge] - 0.5

    # Extend the opaque fibre colour past the contour so a moving edge cannot
    # pull the background into the wool.
    colour = data[nearest[0], nearest[1], :3]
    base = ndi.gaussian_filter(colour, sigma=(1.6, 1.6, 0))
    return distance.astype(np.float32), base, colour - base


def warped(fields, destination, source, smoothing):
    spline = RBFInterpolator(
        destination, source - destination, kernel="thin_plate_spline", smoothing=smoothing
    )
    offsets = spline(SAMPLE_POINTS).reshape(129, 129, 2)
    grid_y, grid_x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    coords = np.stack([grid_y / 8, grid_x / 8])
    y = grid_y + SCALE * ndi.map_coordinates(offsets[..., 1], coords, order=1)
    x = grid_x + SCALE * ndi.map_coordinates(offsets[..., 0], coords, order=1)
    source_coords = np.stack([y, x])
    out = []
    for field in fields:
        if field.ndim == 2:
            out.append(ndi.map_coordinates(field, source_coords, order=1, mode="nearest"))
        else:
            result = [
                ndi.map_coordinates(field[..., channel], source_coords, order=1, mode="nearest")
                for channel in range(3)
            ]
            out.append(np.stack(result, axis=-1))
    return out


def render(fields, positions, fraction, smoothing=9):
    first, last = positions
    middle = (1 - fraction) * first + fraction * last
    start_sdf, start_base, start_detail = warped(fields[0], middle, first, smoothing)
    end_sdf, end_base, end_detail = warped(fields[1], middle, last, smoothing)
    contour = (1 - fraction) * start_sdf + fraction * end_sdf
    alpha = np.clip(contour + 0.5, 0, 1)
    # The connected body is opaque. A handful of enclosed subpixel holes
    # can appear when blended landmarks meet at a fold in the same fleece.
    foreground = alpha >= 0.5
    regions, count = ndi.label(foreground)
    if count > 1:
        areas = np.bincount(regions.ravel())
        pieces = np.flatnonzero((areas > 0) & (areas < max(24, areas[1:].max() * 0.004)))
        alpha[np.isin(regions, pieces)] = 0
    inner = ndi.binary_fill_holes(alpha >= 0.5) & (alpha < 0.5)
    regions, count = ndi.label(inner)
    if count:
        areas = np.bincount(regions.ravel())
        fill = np.flatnonzero((areas > 0) & (areas < 140))
        alpha[np.isin(regions, fill)] = 1

    # Prefer colour from the material side supported by the solid shape.
    # Compensate the fine-band variance of the blend to preserve fibre grain.
    confidence = np.clip((end_sdf - start_sdf) / 38, -1, 1)
    amount = np.clip(fraction + 2 * fraction * (1 - fraction) * confidence, 0, 1)[..., None]
    mix = (1 - amount) * start_base + amount * end_base
    detail = ((1 - amount) * start_detail + amount * end_detail) / np.hypot(1 - amount, amount)
    colour = np.where(alpha[..., None] > 0, mix + detail, 0)
    rgba = np.concatenate([colour, alpha[..., None]], axis=-1)
    return Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def main():
    parser = argparse.ArgumentParser(
        description="Render the felt cat's registered 2D transition frames."
    )
    parser.add_argument("assets", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("poses", nargs="*")
    parser.add_argument("--samples", action="store_true")
    args = parser.parse_args()
    calibration = Path(__file__).parent / "Transitions" / "left-stretch-geometry.json"
    calibrations = json.loads(calibration.read_text())
    stand_fields = sampling_fields(display_image(args.assets, "stand"))
    for pose in args.poses or calibrations:
        key_points = np.array(calibrations[pose], dtype=np.float64)
        sources = np.vstack([key_points[:, :2], BOUNDARIES])
        targets = np.vstack([key_points[:, 2:], BOUNDARIES])
        fields = (stand_fields, sampling_fields(display_image(args.assets, pose)))
        output = args.output / pose
        output.mkdir(parents=True, exist_ok=True)
        indices = [2, 4, 6, 8, 10] if args.samples else range(1, FRAME_COUNT + 1)
        for index in indices:
            frame = render(fields, (sources, targets), index / (FRAME_COUNT + 1))
            frame.save(
                output / f"full-body-cat-transition-{pose}-{index}.png", icc_profile=COLOR_PROFILE
            )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Grade the prepared animation poses against the standing felt coat."""

import argparse
from pathlib import Path

from PIL import Image, PngImagePlugin


# All layers that belong to a pose share its gain, including both versions
# of each profile. Standing supplies the black level for the other poses.
GAIN = {
    "stand": 1.0,
    "left": 0.82,
    "right": 0.88,
    "rear": 0.82,
    "belly": 0.90,
    "loaf": 0.92,
    "puff": 0.89,
    "stretch": 0.85,
    "upright": 0.92,
    "wave": 0.91,
}
PARTS = {"stand": ("", "-tail"), "wave": ("", "-paw")}
WALK = ("", "-walk-body", "-walk-near-front", "-walk-far-front", "-walk-near-hind", "-walk-far-hind")


def grade(source, destination, gain):
    if gain == 1:
        destination.write_bytes(source.read_bytes())
        return
    with Image.open(source) as encoded:
        red, green, blue, alpha = encoded.convert("RGBA").split()
        table = [round(channel * gain) for channel in range(256)]
        result = Image.merge("RGBA", (red.point(table), green.point(table), blue.point(table), alpha))
        metadata = PngImagePlugin.PngInfo()
        if "srgb" in encoded.info:
            metadata.add(b"sRGB", bytes([encoded.info["srgb"]]))
        options = {key: encoded.info[key] for key in ("icc_profile", "dpi") if key in encoded.info}
        result.save(destination, pnginfo=metadata, optimize=True, **options)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prepared", type=Path, help="directory with ungraded prepared felt PNGs")
    parser.add_argument("output", type=Path, help="directory for the graded PNGs")
    args = parser.parse_args()
    if args.prepared.resolve() == args.output.resolve():
        parser.error("Use a separate output directory so the ungraded artwork stays available.")
    args.output.mkdir(parents=True, exist_ok=True)
    for pose, gain in GAIN.items():
        pieces = WALK if pose in ("left", "right") else PARTS.get(pose, ("",))
        for suffix in pieces:
            name = f"full-body-cat-{pose}{suffix}.png"
            grade(args.prepared / name, args.output / name, gain)


if __name__ == "__main__":
    main()

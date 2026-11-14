#!/usr/bin/env python3
"""Prepare SEMI rig textures from the supplied preview and registered ear sources.

Authoring dependencies: Pillow and NumPy. Runtime has no Python dependency.
No model/network calls. The source preview stays intact. The generated head has
its baked eyes/nose removed; the SDK supplies live features. Authored final ear
layers are validated and copied without re-encoding. All layers keep 512px canvases.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

SIZE = 512
SCALE = 4
ROOT = Path(__file__).resolve().parents[2]


def path_mask(start: tuple[float, float], curves: list[tuple[float, ...]]) -> Image.Image:
    points = [start]
    x0, y0 = start
    for x1, y1, x2, y2, x3, y3 in curves:
        for t in np.linspace(0, 1, 64)[1:]:
            u = 1 - t
            points.append((u**3*x0+3*u*u*t*x1+3*u*t*t*x2+t**3*x3,
                           u**3*y0+3*u*u*t*y1+3*u*t*t*y2+t**3*y3))
        x0, y0 = x3, y3
    mask = Image.new('L', (SIZE*SCALE, SIZE*SCALE))
    ImageDraw.Draw(mask).polygon([(round(x*SCALE), round(y*SCALE)) for x, y in points], fill=255)
    return mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def layer(image: Image.Image, mask: Image.Image) -> Image.Image:
    rgba = np.array(image).copy()
    rgba[:, :, 3] = (rgba[:, :, 3].astype(np.uint16) * np.asarray(mask) // 255).astype(np.uint8)
    rgba[rgba[:, :, 3] == 0, :3] = 0  # Transparent pixels must not carry baked features.
    return Image.fromarray(rgba)


def registered_png_bytes(path: Path, label: str) -> bytes:
    """Read an authored, registered 512px RGBA layer without re-encoding it."""
    try:
        with Image.open(path) as image:
            if image.format != 'PNG' or image.mode != 'RGBA' or image.size != (SIZE, SIZE):
                raise ValueError(f'Expected 512×512 RGBA PNG for {label}, got '
                                 f'{image.format} {image.mode} {image.size}')
            image.load()
    except OSError as error:
        raise ValueError(f'Cannot read registered {label} PNG at {path}: {error}') from error
    return path.read_bytes()


def blank_head(source: Image.Image) -> Image.Image:
    """Harmonic extension from actual neighboring fur, with fixed boundary pixels.

    This is deterministic texture preparation, not an expression-specific frame.
    Eye shadows are inside the removal mask to prevent ghost eyelids in a blink.
    """
    mask = Image.new('L', (SIZE, SIZE))
    draw = ImageDraw.Draw(mask)
    draw.ellipse((157, 184, 243, 280), fill=255)
    draw.ellipse((262, 181, 352, 278), fill=255)
    draw.ellipse((236, 248, 273, 279), fill=255)
    # Document corner is occluded by the articulated document in the rest pose.
    draw.rounded_rectangle((207, 282, 304, 326), radius=8, fill=255)
    rgba = np.array(source)
    rgb = rgba[:, :, :3].astype(np.float32)
    selected = np.asarray(mask) > 0
    # Ear interiors belong to the moving ears, never to the fixed skull.
    mint = (rgb[:, :, 1] > rgb[:, :, 0] + 14) & (rgb[:, :, 2] > rgb[:, :, 0] + 8)
    selected |= mint
    yy, xx = np.mgrid[:SIZE, :SIZE]
    fit = ((xx > 150) & (xx < 363) & (yy > 150) & (yy < 280)
           & ~selected & (rgba[:, :, 3] > 250) & (rgb.max(axis=2) < 85))
    def terms(x, y):
        x, y = (x-256)/128, (y-230)/128
        return np.stack([np.ones_like(x), x, y, x*x, x*y, y*y], axis=-1)
    coefficients = np.linalg.lstsq(terms(xx[fit], yy[fit]), rgb[fit], rcond=None)[0]
    rgb[selected] = np.clip(terms(xx[selected], yy[selected]) @ coefficients, 15, 62)
    # The head edge below the nose has no original fur because a document covers it.
    # Use the fitted local fur there; do not diffuse the document's ivory into it.
    solve = selected & (yy < 281)
    for _ in range(1100):
        average = (rgb[:-2, 1:-1]+rgb[2:, 1:-1]+rgb[1:-1, :-2]+rgb[1:-1, 2:]) * .25
        inner = rgb[1:-1, 1:-1]
        inner[solve[1:-1, 1:-1]] = average[solve[1:-1, 1:-1]]
    rgba[:, :, :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    return Image.fromarray(rgba)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT/'Artwork/SEMI/semi-document-cat-preview.png')
    parser.add_argument('--ear-left-source', type=Path,
                        default=ROOT/'Artwork/SEMI/registered-ear-left.png')
    parser.add_argument('--ear-right-source', type=Path,
                        default=ROOT/'Artwork/SEMI/registered-ear-right.png')
    parser.add_argument('--output', type=Path, default=ROOT/'Sources/ReactiveCharacterKit/Resources/SEMI')
    args = parser.parse_args()
    source = Image.open(args.source).convert('RGBA')
    if source.size != (SIZE, SIZE):
        raise ValueError(f'Expected registered 512×512 source, got {source.size}')
    registered_ears = {
        'semi-ear-left.png': registered_png_bytes(args.ear_left_source, 'left ear'),
        'semi-ear-right.png': registered_png_bytes(args.ear_right_source, 'right ear'),
    }
    masks = {
        'head': path_mask((254, 116), [
            (303, 113, 349, 137, 372, 181), (399, 226, 382, 273, 344, 297),
            (309, 320, 206, 322, 171, 301), (126, 276, 112, 243, 128, 200),
            (144, 155, 198, 113, 254, 116)]),
        'paw-left': path_mask((179, 319), [
            (194, 314, 220, 320, 227, 331), (239, 346, 230, 364, 215, 371),
            (192, 381, 166, 366, 164, 350), (160, 337, 166, 326, 179, 319)]),
        'paw-right': path_mask((303, 316), [
            (327, 312, 340, 328, 342, 346), (343, 363, 329, 377, 308, 375),
            (290, 374, 275, 364, 277, 345), (278, 329, 289, 319, 303, 316)]),
        'tail': path_mask((316, 404), [
            (348, 408, 380, 391, 388, 365), (397, 336, 382, 313, 365, 313),
            (347, 310, 336, 327, 340, 342), (350, 368, 333, 378, 313, 377),
            (308, 389, 308, 398, 316, 404)]),
    }
    args.output.mkdir(parents=True, exist_ok=True)
    head = blank_head(source)
    for name, mask in masks.items():
        result = layer(head if name == 'head' else source, mask)
        if name.startswith('paw'):
            # The source hand overlaps ivory paper: exclude paper, not a white matte halo.
            rgba = np.array(result)
            brightness = rgba[:, :, :3].max(axis=2).astype(float)
            keep = np.clip((85 - brightness) / 22, 0, 1)
            rgba[:, :, 3] = np.rint(rgba[:, :, 3] * keep).astype(np.uint8)
            rgba[:, :, :3] = np.minimum(rgba[:, :, :3], 65)
            rgba[rgba[:, :, 3] == 0, :3] = 0
            result = Image.fromarray(rgba)
        result.save(args.output/f'semi-{name}.png', optimize=True)
    for name, contents in registered_ears.items():
        (args.output/name).write_bytes(contents)
    print(f'Wrote {len(masks) + len(registered_ears)} registered layers to {args.output}')

if __name__ == '__main__':
    main()

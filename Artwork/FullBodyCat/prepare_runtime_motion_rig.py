#!/usr/bin/env python3
"""Compile felt scene contours and texture coordinates, without storing frame pixels."""

from pathlib import Path
import argparse
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.interpolate import PchipInterpolator, RBFInterpolator


SIZE = 1024
STAGE_SCALE = SIZE / 256
FIXED_POINT = 16
GRID = 17
POSITIONS = np.linspace(0, 256, GRID)
GRID_POINTS = np.stack(np.meshgrid(POSITIONS, POSITIONS), axis=-1).reshape(-1, 2)
MASK_GRID = np.stack(np.meshgrid(np.arange(SIZE), np.arange(SIZE)), axis=0)
MASK_GRID = MASK_GRID.astype(np.float32)
BOUNDARIES = np.array(
    [(x, y) for x in (0, 64, 128, 192, 256) for y in (0, 256)]
    + [(x, y) for x in (0, 256) for y in (48, 96, 144, 192, 240)]
)
ROUTES = ("left", "right", "stretch", "loaf", "wave", "rear", "upright", "puff")
CALIBRATION = Path(__file__).with_name("Transitions")


def simplify(points, epsilon):
    """Simplify an open polyline with a maximum contour error in source pixels."""
    keep = np.zeros(len(points), dtype=bool)
    keep[[0, -1]] = True
    work = [(0, len(points) - 1)]
    while work:
        begin, end = work.pop()
        if end <= begin + 1:
            continue
        delta = points[end] - points[begin]
        section = points[begin + 1:end] - points[begin]
        length = np.dot(delta, delta)
        if length:
            projection = np.clip((section @ delta) / length, 0, 1)
            section = section - projection[:, None] * delta
        squares = np.einsum("ij,ij->i", section, section)
        split = squares.argmax()
        if squares[split] > epsilon ** 2:
            split += begin + 1
            keep[split] = True
            work.extend(((begin, split), (split, end)))
    return points[keep]


def contours(alpha, epsilon=0.48, minimum_area=0.75):
    """Trace filled pixel edges with winding for holes and a logical-point tolerance."""
    solid = np.asarray(alpha)
    if solid.shape != (SIZE, SIZE):
        raise ValueError(f"Expected a {SIZE}×{SIZE} coverage mask, got {solid.shape}")
    if solid.dtype != np.bool_:
        solid = solid >= 128
    neighbors = np.pad(solid, 1, constant_values=False)
    edges = {}
    # Clockwise outer edges. At a diagonal touch, turn toward the foreground to
    # keep two contours distinct. Interior holes are traversed counterclockwise.
    for neighbor, start, end in (
        (neighbors[:-2, 1:-1], (0, 0), (1, 0)),
        (neighbors[1:-1, 2:], (1, 0), (1, 1)),
        (neighbors[2:, 1:-1], (1, 1), (0, 1)),
        (neighbors[1:-1, :-2], (0, 1), (0, 0)),
    ):
        ys, xs = np.nonzero(solid & ~neighbor)
        for x, y in zip(xs.tolist(), ys.tolist()):
            key = (x + start[0], y + start[1])
            edges.setdefault(key, []).append((x + end[0], y + end[1]))
    paths = []
    while edges:
        origin = next(iter(edges))
        at = origin
        loop = [origin]
        while True:
            outgoing = edges[at]
            if len(outgoing) > 1 and len(loop) > 1:
                dx, dy = at[0] - loop[-2][0], at[1] - loop[-2][1]
                index = max(
                    range(len(outgoing)),
                    key=lambda i: dx * (outgoing[i][1] - at[1]) - dy * (outgoing[i][0] - at[0]),
                )
                following = outgoing.pop(index)
            else:
                following = outgoing.pop()
            if not outgoing:
                del edges[at]
            if following == origin:
                break
            loop.append(following)
            at = following
        points = np.array(loop, dtype=float)
        x, y = points.T
        area = np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))
        if abs(area) / (2 * STAGE_SCALE ** 2) < minimum_area:
            continue
        opposite = np.square(points - points[0]).sum(axis=1).argmax()
        first = simplify(points[:opposite + 1], epsilon * STAGE_SCALE)
        last = simplify(np.concatenate((points[opposite:], points[:1])), epsilon * STAGE_SCALE)
        combined = np.concatenate((first[:-1], last[:-1]))
        if len(combined) >= 3:
            flat = np.rint(combined * FIXED_POINT / STAGE_SCALE).astype(int).ravel().tolist()
            paths.append((abs(area), flat))
    return [path for _, path in sorted(paths, reverse=True)]


def source_grid(asset, points):
    """A 17×17 inverse UV lattice defined on the whole 256pt scene."""
    grid = np.rint(np.asarray(points) * FIXED_POINT).astype(int).ravel().tolist()
    if len(grid) != GRID * GRID * 2:
        raise ValueError("Invalid texture grid")
    return {"asset": asset, "grid": grid}


def affine_source(asset, matrix, translation):
    """Return inverse texture coordinates in renderer row-major order."""
    return {"asset": asset, "affine": [*matrix.ravel().tolist(), *translation.tolist()]}


def positions(rows):
    points = np.asarray(rows, dtype=float)
    return (
        np.vstack((points[:, :2], BOUNDARIES)),
        np.vstack((points[:, 2:], BOUNDARIES)),
    )


def inverse_warp(destination, source, smoothing):
    offsets = RBFInterpolator(
        destination, source - destination, kernel="thin_plate_spline", smoothing=smoothing
    )
    return lambda sample: sample + offsets(sample)


def texture_layer(coverage, a, b=None, amount=0):
    layer = {"paths": contours(coverage), "a": a}
    if b is not None and amount:
        layer.update(b=b, mix=round(amount, 5))
    return layer


def authored_coverage(reference, route, index):
    name = f"full-body-cat-transition-{route}-{index}.png"
    path = reference / name
    if not path.is_file():
        path = reference / route / name
    with Image.open(path) as image:
        return np.asarray(image.getchannel("A")) >= 128


def compare_at(fraction, endpoints, smoothing=9):
    first, last = endpoints
    middle = (1 - fraction) * first + fraction * last
    return (
        inverse_warp(middle, first, smoothing)(GRID_POINTS),
        inverse_warp(middle, last, smoothing)(GRID_POINTS),
    )


def left_and_stretch(reference, route, rows):
    endpoints = positions(rows)
    frames = []
    for index in range(1, 12):
        progress = index / 12
        start, end = compare_at(progress, endpoints)
        mask = authored_coverage(reference, route, index)
        frames.append([texture_layer(
            mask, source_grid("stand-combined", start), source_grid(route, end), progress
        )])
    return frames


def right_turn(assets, reference, controls):
    approach, depart = (positions(controls[key]) for key in ("approach", "depart"))
    front_to_stand = inverse_warp(approach[1], approach[0], smoothing=25)
    with Image.open(assets / "full-body-cat-stand-tail.png") as image:
        standing_tail = np.asarray(image.getchannel("A")) >= 128
    with Image.open(assets / "full-body-cat-right.png") as image:
        right_tail = np.asarray(image.getchannel("A")) >= 128
    split = Image.new("1", (SIZE, SIZE))
    ImageDraw.Draw(split).polygon(
        [(x * 4, y * 4) for x, y in
         [(0, 0), (103, 0), (103, 120), (88, 139), (82, 143), (73, 149), (65, 157), (0, 157)]],
        fill=1,
    )
    right_tail &= np.asarray(split)
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
    tail_motion = PchipInterpolator(track[:, 0], track[:, 1:], axis=0)
    faces = json.loads((CALIBRATION / "right-face.json").read_text())
    px, py = MASK_GRID / STAGE_SCALE
    frames = []
    for index in range(1, 12):
        progress = index / 12
        if progress <= 0.5:
            fraction = 2 * progress
            start, front = compare_at(fraction, approach, smoothing=25)
            # Map the virtual front pose back to the original standing wool.
            first = source_grid("stand-combined", start)
            second = source_grid("stand-combined", front_to_stand(front))
        else:
            fraction = 2 * progress - 1
            front, right = compare_at(fraction, depart, smoothing=25)
            first = source_grid("stand-combined", front_to_stand(front))
            second = source_grid("right", right)
        mask = authored_coverage(reference, "right", index)
        frame = [texture_layer(mask, first, second, fraction)]
        if index in (4, 5):
            # The tail passes wholly behind the turning head here.
            frames.append(frame)
            continue
        x, y, tip_x, tip_y, width = tail_motion(progress)
        root, tip = np.array((x, y)), np.array((tip_x, tip_y))
        if progress < 0.42:
            name, matte = "stand-tail", standing_tail
            source_root, source_tip = (166, 148), (196, 94)
        else:
            name, matte = "right", right_tail
            source_root, source_tip = (73, 146), (38, 89)
        matrix, translation = tail_transform(source_root, source_tip, root, tip, width)
        region = mapped_mask(matte, matrix, translation)
        # Claim the complete original tail edge while leaving its root under the
        # shoulder. The slightly wider patch covers minor contour differences
        # as the tail turns edge-on and returns, without stretched body UVs.
        region = ndimage.maximum_filter(region, size=57)
        vector = tip - root
        along = ((px - x) * vector[0] + (py - y) * vector[1]) / np.linalg.norm(vector)
        visible = region & mask & (along > 8)
        if index == 3:
            # At the horizon of the turn, retain only the branch still visible
            # outside the cheek and near ear.
            bx, by, bw, bh = faces[index - 1]["bounds"]
            cheek = bx + bw * (0.89 + 0.08 * np.clip((py - by - 16) / (bh - 16), 0, 1))
            visible &= px > cheek
        if np.any(visible):
            tail = texture_layer(visible, affine_source(name, matrix, translation))
            if tail["paths"]:
                frame.append(tail)
        frames.append(frame)
    return frames


# Upright body silhouette and face positions on the registered common camera.
# Each row represents the same anatomical point in all poses.
STAND_POINTS = (
    # Ear tips and cheeks, eye anchors, nose.
    (62, 98), (50, 122), (43, 141), (52, 165), (78, 177), (113, 174), (135, 155),
    (133, 124), (120, 99), (91, 111), (63.5, 142), (96.5, 142.5), (77.5, 151),
    # Shoulder, back, haunch and lower torso.
    (130, 154), (149, 144), (170, 145), (185, 159), (188, 176),
    (159, 199), (126, 194), (103, 186),
    # Front, near front, far hind and near hind paw roots and contact points.
    (65, 193), (61, 213), (70, 218), (78, 204), (98, 204), (95, 219), (114, 223),
    (124, 205), (131, 215), (146, 213), (164, 213), (181, 220), (190, 213),
    # Tail root, lower half and tip.
    (177, 155), (174, 115), (181, 90), (193, 82), (207, 87), (210, 105), (199, 127),
)

TARGET_POINTS = {
    "loaf": (
        (66, 116), (56, 144), (44, 166), (51, 194), (77, 216), (126, 220), (149, 201),
        (159, 163), (139, 116), (100, 129), (77.5, 170.5), (117, 170.5), (96, 181),
        (145, 169), (153, 144), (176, 151), (194, 169), (198, 190),
        (170, 204), (145, 214), (126, 217),
        (68, 207), (74, 218), (81, 221), (93, 216), (113, 215), (112, 222), (133, 222),
        (145, 217), (157, 221), (168, 217), (171, 218), (190, 215), (199, 212),
        (158, 213), (161, 209), (172, 201), (187, 194), (202, 195), (208, 204), (196, 216),
    ),
    "wave": (
        (71, 80), (57, 110), (55, 130), (64, 148), (83, 159), (116, 159), (142, 147),
        (148, 116), (135, 79), (101, 92), (80.5, 125), (114.5, 125), (97, 133),
        (133, 155), (144, 158), (149, 166), (158, 178), (161, 194),
        (155, 218), (130, 219), (106, 188),
        (74, 174), (50, 158), (48, 159), (56, 171), (93, 201), (91, 219), (110, 223),
        (122, 209), (75, 216), (85, 219), (129, 221), (147, 220), (158, 212),
        (158, 185), (175, 169), (179, 127), (186, 116), (194, 119), (196, 134), (188, 153),
    ),
    "rear": (
        (83, 80), (72, 103), (68, 126), (73, 143), (87, 153), (126, 149), (165, 150),
        (182, 111), (173, 81), (119, 96), (96, 122), (144, 124), (119, 138),
        (109, 151), (125, 135), (143, 138), (163, 149), (172, 170),
        (150, 196), (138, 194), (116, 193),
        (104, 184), (88, 213), (94, 222), (103, 203), (99, 193), (76, 217), (88, 222),
        (109, 210), (111, 202), (144, 202), (152, 217), (167, 223), (178, 213),
        (127, 166), (130, 125), (130, 93), (135, 62), (145, 68), (150, 87), (146, 109),
    ),
    "upright": (
        (85, 74), (69, 101), (65, 118), (73, 134), (92, 146), (124, 146), (149, 135),
        (157, 103), (146, 74), (113, 86), (89.5, 110), (122.5, 110), (104.5, 117.5),
        (120, 149), (130, 154), (139, 161), (145, 176), (148, 193),
        (130, 205), (117, 200), (92, 193),
        (85, 154), (79, 161), (84, 174), (96, 169), (111, 153), (109, 172), (120, 174),
        (134, 164), (95, 212), (127, 210), (102, 222), (127, 222), (144, 215),
        (149, 191), (168, 177), (177, 151), (184, 144), (191, 146), (191, 158), (181, 182),
    ),
    "puff": (
        (81, 101), (52, 121), (36, 145), (40, 167), (61, 180), (87, 170), (103, 152),
        (99, 121), (80, 101), (69, 117), (43, 142), (44, 147), (39.3, 158),
        (106, 131), (137, 102), (159, 104), (179, 119), (192, 154),
        (166, 179), (131, 185), (104, 179),
        (76, 193), (63, 213), (69, 219), (82, 204), (87, 204), (77, 219), (88, 222),
        (106, 201), (159, 210), (171, 216), (169, 216), (182, 222), (193, 216),
        (187, 146), (183, 113), (180, 91), (190, 72), (206, 73), (216, 89), (207, 113),
    ),
}


def registered_image(root, pose):
    def load(name):
        with Image.open(root / f"full-body-cat-{name}.png") as image:
            return image.convert("RGBA")

    art = load(pose)
    if pose == "stand":
        return Image.alpha_composite(load("stand-tail"), art)
    if pose == "wave":
        return Image.alpha_composite(art, load("wave-paw"))
    return art


def signed_distance(solid):
    inside = ndimage.distance_transform_edt(solid)
    outside = ndimage.distance_transform_edt(~solid)
    return (inside - outside).astype(np.float32)


def sample_distance(field, source):
    x, y = source.reshape(GRID, GRID, 2).transpose(2, 0, 1)
    grid = MASK_GRID / ((GRID - 1) * STAGE_SCALE)
    x = ndimage.map_coordinates(x, grid[::-1], order=1, mode="nearest") * STAGE_SCALE
    y = ndimage.map_coordinates(y, grid[::-1], order=1, mode="nearest") * STAGE_SCALE
    return ndimage.map_coordinates(field, [y, x], order=1, mode="nearest")


def move_tail(route, amount, height_offset=0):
    """Pull the same standing tail around the torso as the camera angle changes."""
    root, tip = np.array((166, 148)), np.array((196, 94))
    if route == "rear":
        final_root, final_tip = np.array((128, 164)), np.array((136, 69))
        narrow = 1 - 0.24 * np.sin(np.pi * amount)
    else:
        final_root, final_tip = np.array((156, 208)), np.array((202, 204))
        narrow = 1 + 0.02 * np.sin(np.pi * amount)
    start = (1 - amount) * root + amount * final_root + (0, height_offset)
    end = (1 - amount) * tip + amount * final_tip + (0, height_offset)
    return tail_transform(root, tip, start, end, narrow)


def tail_transform(root, tip, start, end, width):
    root, tip = np.asarray(root), np.asarray(tip)
    baseline = tip - root
    target = end - start
    cross = lambda v: np.array([-v[1], v[0]]) / np.linalg.norm(v)
    matrix = np.column_stack([baseline, cross(baseline)]) @ np.linalg.inv(
        np.column_stack([target, cross(target) * width])
    )
    return matrix, root - matrix @ start


def mapped_mask(solid, matrix, translation):
    x, y = MASK_GRID
    tx, ty = translation * STAGE_SCALE
    source_x = matrix[0, 0] * x + matrix[0, 1] * y + tx
    source_y = matrix[1, 0] * x + matrix[1, 1] * y + ty
    return ndimage.map_coordinates(solid, [source_y, source_x], order=0, mode="constant", cval=0)


def generic_transition(assets, route):
    start_name = "stand-combined"
    start_image = registered_image(assets, "stand")
    split_tail = route in ("rear", "loaf")
    target_solid = np.asarray(registered_image(assets, route).getchannel("A")) >= 128
    controls = np.hstack((STAND_POINTS, TARGET_POINTS[route]))
    if split_tail:
        start_name = "stand"
        with Image.open(assets / "full-body-cat-stand.png") as image:
            start_image = image.convert("RGBA")
        with Image.open(assets / "full-body-cat-stand-tail.png") as image:
            tail_solid = np.asarray(image.getchannel("A")) >= 128
        # The root's irregular hidden cut must stay under the torso when it rolls
        # into a horizontal tail. Keeping that excess would expose a narrow spur.
        tail_solid[int(157 * STAGE_SCALE):] = False
        controls = controls[:-7]
        x, y = MASK_GRID / STAGE_SCALE
        if route == "rear":
            target_solid &= ~((x > 108) & (x < 154) & (y < 94))
        else:
            target_solid &= ~((x > 151) & (y > 208 - (x - 151) * 0.2))
    endpoints = positions(controls)
    stand = signed_distance(np.asarray(start_image.getchannel("A")) >= 128)
    target = signed_distance(target_solid)
    asset = "wave-combined" if route == "wave" else route
    frames = []
    for index in range(1, 12):
        amount = index / 12
        start, end = compare_at(amount, endpoints, smoothing=13)
        a = sample_distance(stand, start)
        b = sample_distance(target, end)
        contour = (1 - amount) * a + amount * b
        mask = contour >= 0
        regions, count = ndimage.label(mask)
        if count > 1:
            sizes = np.bincount(regions.ravel())
            sizes[0] = 0
            mask = regions == sizes.argmax()
        # Keep the contact point at the camera floor while paws tuck or lift.
        shift = 224 * STAGE_SCALE - (np.nonzero(mask)[0].max() + 1)
        mask = ndimage.shift(mask, (shift, 0), order=0, cval=False)
        if shift:
            samples = GRID_POINTS - [0, shift / STAGE_SCALE]
            first, last = endpoints
            middle = (1 - amount) * first + amount * last
            start = inverse_warp(middle, first, 13)(samples)
            end = inverse_warp(middle, last, 13)(samples)
        layers = []
        if split_tail:
            matrix, translation = move_tail(route, amount, shift / STAGE_SCALE)
            tail_mask = mapped_mask(tail_solid, matrix, translation)
            tail_mask[int(224 * STAGE_SCALE):] = False
            layers.append(texture_layer(tail_mask, affine_source("stand-tail", matrix, translation)))
        layers.append(texture_layer(mask, source_grid(start_name, start), source_grid(asset, end), amount))
        frames.append(layers)
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="directory of the approved felt textures")
    parser.add_argument("reference", type=Path, help="authoring-only intermediate alpha reference directory")
    parser.add_argument("output", type=Path, help="output numeric JSON, no raster images")
    parser.add_argument("--routes", nargs="+", choices=ROUTES, default=ROUTES)
    args = parser.parse_args()
    left_stretch = json.loads((CALIBRATION / "left-stretch-geometry.json").read_text())
    right_controls = json.loads((CALIBRATION / "right-geometry.json").read_text())
    routes = {}
    for route in args.routes:
        if route in left_stretch:
            routes[route] = left_and_stretch(args.reference, route, left_stretch[route])
        elif route == "right":
            routes[route] = right_turn(args.assets, args.reference, right_controls)
        else:
            routes[route] = generic_transition(args.assets, route)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(routes, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()

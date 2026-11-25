"""Author felt pose changes with separate planted and lifted paws.

The output contains contours and inverse mappings only. Run with the directory
of the approved SDK PNGs and a destination JSON path.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import prepare_runtime_motion_rig as rig


def alpha(assets, name):
    with Image.open(assets / f"full-body-cat-{name}.png") as image:
        return np.asarray(image.getchannel("A")) >= 128


def polygon(vertices):
    sheet = Image.new("1", (rig.SIZE, rig.SIZE))
    ImageDraw.Draw(sheet).polygon([(4 * x, 4 * y) for x, y in vertices], fill=1)
    return np.asarray(sheet)


def rounded(mask, sigma=3):
    return ndimage.gaussian_filter(mask.astype(np.float32), sigma) >= 0.5


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3 - 2 * value)


def points_on_arc(first, last, amount, root):
    first, last = np.asarray(first), np.asarray(last)
    a, b = np.arctan2(first[1], first[0]), np.arctan2(last[1], last[0])
    sweep = (b - a + np.pi) % (2 * np.pi) - np.pi
    angle = a + sweep * amount
    length = (1 - amount) * np.linalg.norm(first) + amount * np.linalg.norm(last)
    return root + length * np.array([np.cos(angle), np.sin(angle)])


def field_at(field, matrix, offset):
    x, y = rig.MASK_GRID / rig.STAGE_SCALE
    source_x = (matrix[0, 0] * x + matrix[0, 1] * y + offset[0]) * rig.STAGE_SCALE
    source_y = (matrix[1, 0] * x + matrix[1, 1] * y + offset[1]) * rig.STAGE_SCALE
    return ndimage.map_coordinates(field, (source_y, source_x), order=1, mode="constant", cval=-80)


def moving_part(start, end, amount, root, tip):
    start_name, start_mask, start_root, start_tip = start
    end_name, end_mask, end_root, end_tip = end
    first, first_offset = rig.tail_transform(start_root, start_tip, root, tip, 1)
    last, last_offset = rig.tail_transform(end_root, end_tip, root, tip, 1)
    weight = smooth(amount)
    mask = ((1 - weight) * field_at(start_mask, first, first_offset)
            + weight * field_at(end_mask, last, last_offset)) >= 0
    mask[int(224 * rig.STAGE_SCALE):] = False
    return (
        rounded(mask, 2.4), rig.affine_source(start_name, first, first_offset),
        rig.affine_source(end_name, last, last_offset), weight,
    )


def paw_layer(start, end, amount, root, tip):
    return rig.texture_layer(*moving_part(start, end, amount, root, tip))


def pose_shell(start, end, controls, amount, soften=2.8):
    positions = rig.positions(controls)
    uv_a, uv_b = rig.compare_at(amount, positions, smoothing=13)
    distance = ((1 - amount) * rig.sample_distance(start, uv_a)
                + amount * rig.sample_distance(end, uv_b))
    mask = rounded(distance >= 0, soften)
    mask = ndimage.binary_fill_holes(mask)
    floor = 224 * rig.STAGE_SCALE
    shift = floor - (np.nonzero(mask)[0].max() + 1)
    if shift:
        mask = ndimage.shift(mask, (shift, 0), order=0, cval=False)
        first, last = positions
        middle = (1 - amount) * first + amount * last
        samples = rig.GRID_POINTS - [0, shift / rig.STAGE_SCALE]
        uv_a = rig.inverse_warp(middle, first, 13)(samples)
        uv_b = rig.inverse_warp(middle, last, 13)(samples)
    return mask, uv_a, uv_b


STAND_OUTER_PAW = [
    (65, 174), (81, 178), (87, 192), (85, 206), (81, 224),
    (48, 224), (48, 199), (56, 183),
]
STAND_NEAR_PAW = [
    (96, 175), (115, 179), (126, 192), (128, 211), (121, 227),
    (91, 227), (88, 216), (92, 196),
]


def part(name, mask, root, tip):
    return name, rig.signed_distance(mask), np.array(root), np.array(tip)


def interpolate_paw(start, end, amount, swing):
    root = (1 - amount) * start[2] + amount * end[2]
    tip = points_on_arc(start[3] - start[2], end[3] - end[2], swing, root)
    return paw_layer(start, end, amount, root, tip)


def wave_seam_paths(body, support, lifted, frame_index):
    # Seal narrow slits left inside the overlap. Keep gaps that reach the
    # exterior so the raised paw remains distinct from the planted paw.
    joined = body | support | lifted
    interior = ndimage.binary_fill_holes(joined, structure=np.ones((3, 3))) & ~joined
    labels, _ = ndimage.label(interior)
    sizes = np.bincount(labels.ravel())
    fill = np.zeros_like(interior)
    for index, bounds in enumerate(ndimage.find_objects(labels), 1):
        y, x = bounds
        short_side = min(y.stop - y.start, x.stop - x.start) / rig.STAGE_SCALE
        area = sizes[index] / rig.STAGE_SCALE ** 2
        if short_side <= 3 and 0.75 <= area <= 18:
            fill[bounds] |= labels[bounds] == index
    bridge = ndimage.binary_dilation(fill, iterations=3) & (joined | fill)
    if frame_index == 8:
        # After contour simplification, two tangent contacts need underlap:
        # the raised paw against the cheek and the supporting paw at the chest.
        bridge |= polygon([(64, 164.4), (64.8, 163.8), (67, 164.2), (68.2, 165.1),
                           (69, 166.5), (66.7, 167.3), (64.4, 166.2)])
        bridge |= polygon([(90, 194), (92.5, 193.8), (93.5, 195.8), (93.1, 201.5),
                           (91.75, 201.5), (91, 200.9), (90.2, 199.6)])
    return rig.contours(bridge, epsilon=0.24)


def wave(assets):
    stand = alpha(assets, "stand")
    stand_full = stand | alpha(assets, "stand-tail")
    little_paw = stand & polygon(STAND_OUTER_PAW)
    near_paw = stand & polygon(STAND_NEAR_PAW)
    wave_body = alpha(assets, "wave")
    wave_near = wave_body & polygon([
        (94, 164), (117, 166), (125, 180), (122, 200), (119, 226),
        (93, 226), (87, 214), (91, 193),
    ])
    body = rig.signed_distance(stand_full & ~(little_paw | near_paw))
    seated = rig.signed_distance(wave_body & ~wave_near)
    start = part("stand", little_paw, (77, 179), (66, 211))
    end = part("wave-paw", alpha(assets, "wave-paw"), (85, 177), (61, 153))
    support_a = part("stand", near_paw, (108, 182), (106, 219))
    support_b = part("wave", wave_near, (108, 173), (102, 219))
    controls = np.hstack((rig.STAND_POINTS, rig.TARGET_POINTS["wave"]))
    controls = np.delete(controls, list(range(21, 29)), axis=0)
    frames = []
    for index in range(1, 12):
        amount = index / 12
        body_mask, uv_a, uv_b = pose_shell(body, seated, controls, amount)
        shell = rig.texture_layer(body_mask, rig.source_grid("stand-combined", uv_a),
                                 rig.source_grid("wave", uv_b), smooth(amount))
        support_root = (1 - amount) * support_a[2] + amount * support_b[2]
        support_tip = (1 - amount) * support_a[3] + amount * support_b[3]
        planted = moving_part(support_a, support_b, amount, support_root, support_tip)
        paw_root = (1 - amount) * start[2] + amount * end[2]
        paw_tip = points_on_arc(start[3] - start[2], end[3] - end[2], smooth(amount), paw_root)
        paw = moving_part(start, end, amount, paw_root, paw_tip)
        layers = [shell, rig.texture_layer(*planted), rig.texture_layer(*paw)]
        seam = wave_seam_paths(body_mask, planted[0], paw[0], index)
        if seam:
            # Draw underneath the existing layers so their paint still owns
            # each paw surface and the repair only shows through the gap.
            layers.insert(0, dict(shell, paths=seam))
        frames.append(layers)
    return frames


def upright(assets):
    stand = alpha(assets, "stand")
    far = stand & polygon(STAND_OUTER_PAW)
    near = stand & polygon(STAND_NEAR_PAW)
    torso = rig.signed_distance((stand | alpha(assets, "stand-tail")) & ~(far | near))
    seated = alpha(assets, "upright")
    far_end = seated & polygon([
        (80, 145), (99, 143), (107, 151), (105, 167), (100, 176), (84, 175), (75, 166), (74, 155),
    ])
    near_end = seated & polygon([
        (106, 144), (127, 143), (142, 151), (145, 162), (140, 172), (118, 177), (105, 173), (103, 161),
    ])
    # Leave the core behind both folded paws covered by the chest.
    outside = polygon([(68, 139), (83, 140), (86, 181), (74, 181), (64, 164)])
    torso_end = rig.signed_distance(seated & ~(far_end & outside))
    from_far = part("stand", far, (77, 179), (66, 211))
    from_near = part("stand", near, (108, 182), (106, 219))
    to_far = part("upright", far_end, (96, 147), (88, 163))
    to_near = part("upright", near_end, (122, 147), (124, 163))
    controls = np.hstack((rig.STAND_POINTS, rig.TARGET_POINTS["upright"]))
    controls = np.delete(controls, list(range(21, 29)), axis=0)
    frames = []
    for index in range(1, 12):
        amount = index / 12
        mask, uv_a, uv_b = pose_shell(torso, torso_end, controls, amount, soften=4.0)
        shell = rig.texture_layer(mask, rig.source_grid("stand-combined", uv_a),
                                 rig.source_grid("upright", uv_b), smooth((amount - 0.18) / 0.78))
        far_lift = interpolate_paw(from_far, to_far, amount, smooth(amount / 0.91))
        near_lift = interpolate_paw(from_near, to_near, amount, smooth((amount - 0.09) / 0.91))
        frames.append([shell, far_lift, near_lift])
    return frames


def loaf(assets):
    stand_tail = alpha(assets, "stand-tail")
    stand_tail[int(157 * rig.STAGE_SCALE):] = False
    rest = alpha(assets, "loaf")
    curled = rest & polygon([
        (145, 209), (152, 201), (165, 195), (183, 193), (198, 188),
        (212, 189), (222, 202), (220, 222), (205, 225), (146, 225),
    ])
    x, y = rig.MASK_GRID / rig.STAGE_SCALE
    # Resolve the standing split to the same rounded back as the live tail rig.
    back_t = np.clip((x - 156) / 10, 0, 1)
    standing_back = (x < 156) | (x >= 166) | (y >= 144.9 + back_t * (3 + 5.5 * back_t))
    standing = rig.signed_distance(alpha(assets, "stand") & standing_back)
    # The curl overlaps the rump. Retain the target shell under that overlap so
    # the fold stays rounded as the independent tail slides into it.
    huddled = rig.signed_distance(rest)
    controls = np.hstack((rig.STAND_POINTS[:-7], rig.TARGET_POINTS["loaf"][:-7]))
    tail_from = part("stand-tail", stand_tail, (165, 147), (196, 94))
    tail_to = part("loaf", curled, (154, 212), (204, 202))
    frames = []
    for index in range(1, 12):
        amount = index / 12
        mask, uv_a, uv_b = pose_shell(standing, huddled, controls, amount, soften=4)
        radius = 24 * np.sin(np.pi * amount) ** 2
        grown = ndimage.distance_transform_edt(~mask) <= radius
        tucked = ndimage.distance_transform_edt(grown) > radius
        mask |= tucked & (x > 113) & (y > 170) & (y < 224)
        shell = rig.texture_layer(mask, rig.source_grid("stand", uv_a),
                                 rig.source_grid("loaf", uv_b), smooth(amount))
        curl = smooth((amount - 0.14) / 0.86)
        root = (1 - amount) * tail_from[2] + amount * tail_to[2]
        tip = points_on_arc(tail_from[3] - tail_from[2], tail_to[3] - tail_to[2], curl, root)
        tail_mask, first, last, weight = moving_part(tail_from, tail_to, curl, root, tip)
        frames.append([rig.texture_layer(tail_mask, first, last, weight), shell])
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    routes = {"wave": wave(args.assets), "upright": upright(args.assets), "loaf": loaf(args.assets)}
    args.output.write_text(json.dumps(routes, separators=(",", ":"), sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

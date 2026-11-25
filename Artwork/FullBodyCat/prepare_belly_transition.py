#!/usr/bin/env python3
"""Build the 11 4× felt roll plates and their live facial anchors.

Requires Python 3.10+ with NumPy, Pillow, and SciPy. Run from CharacterKit:

python Artwork/FullBodyCat/prepare_belly_transition.py \
  Sources/ReactiveCharacterKit/Resources/FullBodyCat /tmp/felt-belly-roll

The inputs are the shipped stand, stand-tail, and belly PNGs. The walk, stretch,
and rest assets remain separate. Plates and anchor JSON use top-left 256-point
artwork registration, with the floor at y=224. No eye, nose, or mouth is painted
into a plate. The runtime composes the live facial channels on these anchors.
"""

import argparse
import json
import math
from pathlib import Path
from struct import pack

import numpy as np
from PIL import Image, ImageCms, ImageDraw
from scipy.interpolate import CubicSpline
from scipy.ndimage import distance_transform_edt, gaussian_filter, label, map_coordinates, median_filter

DENSITY = 4
STAGE = 256
PIXELS = DENSITY * STAGE
GROUND = 224
CANVAS = (PIXELS, PIXELS)
COORDINATES = np.mgrid[:PIXELS, :PIXELS].astype(np.float32) / DENSITY
PROFILE = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
# LittleCMS stamps newly created ICC profiles with the current UTC time.
# Preserve the shipped profile date so reruns produce the same PNG bytes.
PROFILE = PROFILE[:24] + pack(">6H", 2026, 11, 23, 11, 11, 11) + PROFILE[36:]


def lerp(left, right, amount):
    return (1 - amount) * np.asarray(left) + amount * np.asarray(right)


def ease(amount, begin=0, end=1):
    fraction = np.clip((amount - begin) / (end - begin), 0, 1)
    return fraction * fraction * (3 - 2 * fraction)


def radians(degrees):
    return degrees * math.pi / 180


def angle(root, tip):
    delta = np.asarray(tip) - root
    return math.atan2(delta[1], delta[0])


def rotation(orientation):
    cosine, sine = math.cos(orientation), math.sin(orientation)
    return np.array(((cosine, -sine), (sine, cosine)))


def smooth_polygon(vertices):
    vertices = np.asarray(vertices + vertices[:1])
    distance = np.concatenate(([0], np.cumsum(np.linalg.norm(np.diff(vertices, axis=0), axis=1))))
    curve = CubicSpline(distance, vertices, bc_type="periodic", axis=0)
    return [tuple(p * DENSITY) for p in curve(np.linspace(0, distance[-1], 210, endpoint=False))]


class Pose:
    def __init__(self, center, orientation=0, scale=(1, 1)):
        self.center = np.asarray(center)
        self.orientation = orientation
        self.scale = np.asarray(scale)
        self.matrix = rotation(orientation) @ np.diag(self.scale)
        self.inverse = np.linalg.inv(self.matrix)

    def place(self, points):
        return np.asarray(points) @ self.matrix.T + self.center

    def local(self, points):
        return (np.asarray(points) - self.center) @ self.inverse.T

    def interpolate(self, other, weight, center_shift=(0, 0), tilt=0, squash=(1, 1)):
        return Pose(lerp(self.center, other.center, weight) + center_shift,
                    (1 - weight) * self.orientation + weight * other.orientation + tilt,
                    lerp(self.scale, other.scale, weight) * squash)


class Layer:
    def __init__(self, rgba, vertices, pose, behind_joint=None):
        self.pose = pose
        if vertices is None:
            region = rgba[:, :, 3] > 127
        else:
            plate = Image.new("L", CANVAS)
            ImageDraw.Draw(plate).polygon(smooth_polygon(vertices), fill=255)
            region = (rgba[:, :, 3] > 127) & (np.asarray(plate) > 127)
        if behind_joint is not None:
            # Keep enough root under the torso and avoid carrying a piece of
            # shoulder into view on the other side of the turning leg.
            local = pose.local(COORDINATES[::-1].transpose(1, 2, 0))
            radius = behind_joint - 0.024 * local[:, :, 1] ** 2
            region &= local[:, :, 0] > -radius
        yy, xx = np.where(region)
        self.crop = (max(0, xx.min() - 12), max(0, yy.min() - 12),
                     min(PIXELS, xx.max() + 13), min(PIXELS, yy.max() + 13))
        x0, y0, x1, y1 = self.crop
        body = region[y0:y1, x0:x1]
        inside = distance_transform_edt(body)
        outside, lookup = distance_transform_edt(~body, return_indices=True)
        self.distance = (inside - outside).astype(np.float32)
        self.color = rgba[y0:y1, x0:x1, :3][lookup[0], lookup[1]].astype(np.float32)
        local_corners = np.array(((x0, y0), (x1, y0), (x0, y1), (x1, y1))) / DENSITY
        self.local_corners = self.pose.local(local_corners)

    def sample(self, local_points):
        world_points = self.pose.place(local_points) * DENSITY
        sample = (world_points[:, 1] - self.crop[1], world_points[:, 0] - self.crop[0])
        distance = map_coordinates(self.distance, sample, order=1, mode="constant", cval=-20)
        rgb = np.stack([map_coordinates(self.color[:, :, c], sample, order=1, mode="nearest")
                        for c in range(3)], axis=-1)
        return distance, rgb


def composite_part(result, start, end, pose, amount, round_back=False):
    x, y = pose.place(np.vstack((start.local_corners, end.local_corners))).T * DENSITY
    clip = np.s_[max(0, int(y.min()) - 1):min(PIXELS, int(y.max()) + 2),
                 max(0, int(x.min()) - 1):min(PIXELS, int(x.max()) + 2)]
    patch = result[clip]
    height, width = patch.shape[:2]
    coords = COORDINATES[:, clip[0], clip[1]][::-1].reshape(2, -1).T
    pos = pose.local(coords)
    start_distance, start_color = start.sample(pos)
    end_distance, end_color = end.sample(pos)
    plate_distance = lerp(start_distance, end_distance, amount)
    alpha = np.clip(0.5 + 0.51 * plate_distance, 0, 1).reshape(height, width)
    if round_back:
        # Hidden remnants of a paw can surface as a notch-sized ridge in the
        # warped torso. Remove only local peaks on the torso's dorsal outline.
        solid = alpha >= 0.5
        ridge = np.where(np.any(solid, axis=0), np.argmax(solid, axis=0), height)
        smooth_ridge = median_filter(ridge, size=31, mode="nearest")
        ramp = np.arange(height)[:, None] - smooth_ridge[None, :] + 0.7
        alpha = np.minimum(alpha, np.clip(ramp, 0, 1))
    start_weight = (1 - amount) * np.exp(np.clip(start_distance, -20, 0) * 0.34)
    end_weight = amount * np.exp(np.clip(end_distance, -20, 0) * 0.34)
    weight_sum = np.maximum(start_weight + end_weight, 1e-6)
    shaded = ((start_color * start_weight[:, None] + end_color * end_weight[:, None])
              / weight_sum[:, None]).reshape(height, width, 3)
    patch[:, :, :3] = shaded * alpha[:, :, None] + patch[:, :, :3] * (1 - alpha[:, :, None])
    patch[:, :, 3] = alpha + patch[:, :, 3] * (1 - alpha)


def normalize(rgba, amount):
    # Round the introduced cutout seams at exposed joints. Keep the registered
    # source contour nearly intact in frames close to either endpoint.
    sigma = 0.65 + 4.4 * math.sin(math.pi * amount) ** 2
    initial = rgba[:, :, 3].copy()
    smooth = gaussian_filter(initial, sigma)
    coverage = np.clip(0.5 + (smooth - 0.5) * (2.2 * sigma), 0, 1)
    solid = coverage >= 0.5
    ids, _ = label(solid, np.ones((3, 3), np.int32))
    counts = np.bincount(ids.ravel())
    counts[0] = 0
    largest = int(counts.argmax())
    coverage[(ids != 0) & (ids != largest)] = 0
    colored = initial > 0.05
    missing = ~colored & (coverage > 0)
    rgba[colored, :3] /= initial[colored, None]
    if np.any(missing):
        lookup = distance_transform_edt(~colored, return_distances=False, return_indices=True)
        rgba[missing, :3] = rgba[lookup[0][missing], lookup[1][missing], :3]
    rgba[coverage == 0, :3] = 0
    rgba[:, :, 3] = coverage * 255
    return np.round(np.clip(rgba, 0, 255)).astype(np.uint8), np.nonzero(ids == largest)[0].max()


def leg(source, target, start_polygon, final_polygon, root, toe, next_root, next_toe, length_gain):
    source = Layer(source, start_polygon, Pose(root, angle(root, toe)), behind_joint=13)
    final_angle = angle(next_root, next_toe)
    if final_angle > 0:
        final_angle -= 2 * math.pi
    target = Layer(target, final_polygon, Pose(next_root, final_angle, (length_gain, 1)), behind_joint=14)
    return source, target


def register_face(head_start, head_final, head, weight, vertical_shift):
    def landmark(source, target):
        local = lerp(head_start.local(source), head_final.local(target), weight)
        return head.place(local) + (0, vertical_shift)
    first = landmark((63.5, 142), (71, 197.8))
    second = landmark((96.5, 142.5), (71, 160.5))
    nose = landmark((77.5, 151), (82, 176.2))
    mouth = landmark((78, 157), (88.4, 178))
    widths = lerp((8, 13, 8, 14, 9, 6), (7.5, 12, 7.5, 12, 9, 6), weight)
    bounds = lerp((43, 97, 97, 82), (26.8, 141.2, 76.4, 81.9), weight)
    bounds[:2] += head.center - lerp(head_start.center, head_final.center, weight) + (0, vertical_shift)
    return {
        "bounds": list(bounds),
        "left": [*first, *widths[:2]],
        "right": [*second, *widths[2:4]],
        "muzzle": [*nose, *widths[4:], *mouth],
        "eyeAngle": head.orientation,
    }


def registered_layers(source_dir):
    def open_layer(name):
        return np.asarray(Image.open(source_dir / f"full-body-cat-{name}.png").convert("RGBA"))

    stand = open_layer("stand")
    belly = open_layer("belly")
    return [
        (Layer(open_layer("stand-tail"), None, Pose((153, 158), radians(-55))),
         Layer(belly, [(152, 198), (182, 186), (222, 182), (239, 191), (238, 220),
                       (213, 225), (179, 224), (151, 221)], Pose((155, 210), radians(-3)))),
        leg(stand, belly,
            [(62, 166), (82, 164), (100, 177), (88, 196), (80, 223), (64, 227),
             (47, 225), (44, 208), (51, 186)],
            [(75, 119), (110, 119), (114, 139), (108, 160), (95, 170), (83, 161), (74, 140)],
            (72, 175), (64, 213), (99, 159), (94, 132), 0.76),
        leg(stand, belly,
            [(128, 163), (145, 160), (154, 184), (151, 206), (149, 219),
             (130, 221), (122, 212), (122, 191)],
            [(128, 121), (155, 119), (161, 137), (158, 158), (151, 170), (133, 168), (128, 147)],
            (143, 172), (139, 209), (144, 162), (143, 133), 0.82),
        (Layer(stand, [(79, 139), (110, 135), (140, 139), (159, 141), (179, 151), (191, 172),
                       (188, 188), (176, 201), (158, 199), (146, 201), (121, 201), (96, 201),
                       (78, 194), (68, 181), (71, 158)], Pose((130, 176))),
         Layer(belly, [(83, 153), (103, 147), (122, 143), (135, 145), (151, 149), (163, 162),
                       (169, 179), (173, 199), (164, 215), (147, 223), (114, 226),
                       (94, 224), (83, 210), (78, 177)], Pose((125, 182), 0, (1.14, 1)))),
        leg(stand, belly,
            [(146, 148), (172, 146), (187, 159), (199, 183), (198, 221), (183, 226),
             (162, 225), (160, 208), (151, 197), (142, 190), (141, 167)],
            [(156, 151), (176, 143), (188, 155), (190, 174), (184, 193),
             (175, 207), (166, 213), (149, 208), (145, 194), (148, 174)],
            (162, 170), (179, 211), (150, 197), (172, 157), 0.96),
        leg(stand, belly,
            [(95, 161), (112, 155), (132, 165), (132, 184), (124, 204),
             (121, 221), (109, 229), (93, 228), (88, 215), (92, 192)],
            [(114, 169), (125, 158), (138, 159), (147, 172), (145, 186), (138, 200),
             (128, 210), (116, 213), (107, 203), (107, 187)],
            (109, 179), (108, 218), (117, 205), (130, 172), 0.92),
        (Layer(stand, [(39, 159), (39, 116), (47, 92), (76, 92), (87, 106), (107, 93),
                       (130, 92), (137, 118), (135, 143), (134, 157), (127, 172),
                       (113, 182), (91, 186), (71, 184), (53, 178), (41, 169)], Pose((87, 145))),
         Layer(belly, [(22, 157), (39, 145), (60, 138), (80, 141), (95, 146), (104, 156),
                       (106, 174), (105, 198), (102, 214), (95, 223), (78, 229),
                       (51, 228), (25, 228), (23, 207), (29, 187)], Pose((67, 184), -math.pi / 2))),
    ]


def roll_layer_pose(layer_number, source, target, amount, roll):
    movement = math.sin(roll * math.pi)
    if layer_number == 0:
        weight = ease(amount, 0.12, 0.99)
        return source.pose.interpolate(target.pose, weight, (0, 8 * movement)), weight
    if layer_number == 3:
        weight = ease(amount, 0.12, 0.93)
        return source.pose.interpolate(target.pose, weight, (-2 * movement, 6 * movement),
                                       radians(-9) * movement, (1, 1 - 0.12 * movement)), weight
    if layer_number == 6:
        weight = ease(amount, 0.045, 0.985)
        return source.pose.interpolate(target.pose, weight, (0, 5.8 * movement)), weight
    far = layer_number in (1, 2)
    weight = ease(amount, 0.15 if far else 0.22, 0.93 if far else 0.95)
    tuck = math.sin(weight * math.pi)
    return source.pose.interpolate(target.pose, weight, (-2 * tuck, 6 * movement),
                                   0, (1 - 0.19 * tuck, 1 + 0.035 * tuck)), weight


def render(source_dir, output_dir):
    layers = registered_layers(source_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    faces = []
    for index in range(1, 12):
        amount = index / 12
        roll = ease(amount)
        frame = np.zeros((PIXELS, PIXELS, 4), dtype=np.float32)
        for layer_number, (source, target) in enumerate(layers):
            pose, weight = roll_layer_pose(layer_number, source, target, amount, roll)
            if layer_number == 6:
                head = pose
            composite_part(frame, source, target, pose, weight, round_back=(layer_number == 3))
        pixels, max_y = normalize(frame, amount)
        delta = GROUND * DENSITY - max_y
        pixels = np.roll(pixels, delta, axis=0)
        # At the common camera floor the rolled cat can still blink and articulate.
        faces.append(register_face(layers[-1][0].pose, layers[-1][1].pose, head, weight, delta / DENSITY))
        file = output_dir / f"full-body-cat-transition-belly-{index}.png"
        Image.fromarray(pixels).save(file, icc_profile=PROFILE, optimize=True)
    (output_dir / "belly-face.json").write_text(json.dumps(faces, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    render(args.source_dir, args.output_dir)

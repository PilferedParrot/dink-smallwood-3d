#!/usr/bin/env python3
"""The well's materials at eye level (docs/DIRECTION.md, "P4d fix round"): what the built faces SHOW, measured from the engine's own
mesh and texture (tests/fps_well_dump.gd) against the sprite, not from the fit's numbers.

    python tools/well_materials.py <dump dir> [--label NAME] [--json out.json]

W1 posts. Every side face of the posts is sampled uniformly by its true area; each sample is the texel the face's UV lands on (the
engine samples nearest). The reference is the sprite's own WOOD pixels: the drawn posts' columns between the roof and the stone, the
roof's and the stone's pixels excluded, and the black outline excluded (OUTLINE_LUM: a drawing convention, not material; the first
version of this measure kept it, its darkest quartile was 0, and a build with flat pure-black faces passed for the wrong reason). Both are
summarised by the mean luminance and the mean luminance of the darkest quartile.
Pre-registered (2026-10-20, restated after the lead's view of 58866c4, before measuring): the mean luminance within 15 % of the sprite's
wood, the darkest quartile within 10 levels (of 255) of the sprite's either way, and NO face texel at or below the outline's luminance (no
void); and each post column the faces read is one colour down the post (one material along its full height).
W2 roof. Each face of the roof (a slope's top, its underside, its eave's edge, its two ends) is a plane that takes the sprite's picture
by UV. Its Jacobian (texels per true px, along the face's two in-plane axes) is the density of the straw drawn on it: sigma_down is
along the slope (the sprite's rows along it), sigma_ridge along the ridge. A UV error shows as a face whose densities differ from the
top slope's (stretched, a sigma near 0 is a smear). Pre-registered: every face of the roof keeps both densities within 35 % of the top
slope's (a plane of the same straw is cut from the same cloth; a thickness face cannot match exactly because the picture's rows come
from the slope it is cut from, hence 35 %), and no face has a density below 0.4 of the top slope's.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import landmark_fit as L  # noqa: E402
import prop_fit as P  # noqa: E402

LUM = np.array([0.299, 0.587, 0.114])


def lum(rgb: np.ndarray) -> np.ndarray:
    return np.asarray(rgb, float) @ LUM


def stats(rgb: np.ndarray) -> dict:
    y = np.sort(lum(rgb))
    q = y[:max(1, len(y) // 4)]
    return {'min_lum': float(y.min()), 'n': int(len(y)), 'mean_lum': float(y.mean()), 'dark_quartile_lum': float(q.mean()), 'mean_rgb': [float(v) for v in np.mean(rgb, axis=0)]}


OUTLINE_LUM = 24.0  # the drawn posts' luminance: the outline is below 20, the wood above 40 (prop_solids.gd OUTLINE_LUM)


def sprite_posts(wood_only: bool = True) -> np.ndarray:
    rgba = P.load('assets/graphics/struct/Landmark/landm-01.png')
    body, roof, base, posts, warm = L.segment(rgba)
    region = np.zeros_like(body)
    for p in posts:
        region[p['top']:p['foot'], p['x0']:p['x1']] = True
    region &= body & ~roof & ~base
    px = rgba[region][:, :3].astype(float)
    return px[lum(px) > OUTLINE_LUM] if wood_only else px


def triangles(part: dict, size):
    v = np.array(part['verts'], float)
    uv = np.array(part['uvs'], float) * np.array(size, float)
    idx = np.array(part['index']).reshape(-1, 3)
    return v, uv, idx


def sample_faces(part: dict, tex: np.ndarray, size, rng, per_area=4.0, vertical_only=True):
    """Texels under points drawn uniformly by true area over the part's (vertical) faces. Returns an (n, 3) array of RGB."""
    v, uv, idx = triangles(part, size)
    out = []
    for t in idx:
        a, b, c = v[t]
        n = np.cross(b - a, c - a)
        area = np.linalg.norm(n) / 2
        if area < 1e-9 or (vertical_only and abs(n[1]) / (2 * area) > 0.5):
            continue
        m = max(1, int(round(area * per_area)))
        r = rng.random((m, 2))
        f = r.sum(1) > 1
        r[f] = 1 - r[f]
        w = np.column_stack([1 - r.sum(1), r[:, 0], r[:, 1]])
        p = w @ uv[t]
        x = np.clip(np.floor(p[:, 0]).astype(int), 0, size[0] - 1)
        y = np.clip(np.floor(p[:, 1]).astype(int), 0, size[1] - 1)
        out.append(tex[y, x, :3].astype(float))
    return np.concatenate(out)


def face_jacobians(part: dict, size) -> list:
    """Per quad (four vertices): (sigma_ridge, sigma_down) texels per true px, from the quad's first triangle, in the quad's own plane:
    the in-plane axis along the face's top edge (horizontal: the ridge direction for a slope) and the one across it."""
    v, uv, idx = triangles(part, size)
    out = []
    for q in range(len(v) // 4):
        P4 = v[4 * q:4 * q + 4]
        U4 = uv[4 * q:4 * q + 4]
        e1 = P4[1] - P4[0]
        e2 = P4[3] - P4[0]
        # orthonormal in-plane basis from e1 (a), then the part of e2 orthogonal to it (b)
        a = e1 / np.linalg.norm(e1)
        b = e2 - a * (e2 @ a)
        b /= np.linalg.norm(b)
        M = np.array([[e1 @ a, e2 @ a], [e1 @ b, e2 @ b]])  # plane coordinates of the two edges (columns)
        D = np.column_stack([U4[1] - U4[0], U4[3] - U4[0]])  # their UV deltas
        J = D @ np.linalg.inv(M)  # UV per plane unit: 2x2
        s = np.linalg.svd(J, compute_uv=False)
        out.append({'quad': q, 'len_e1': float(np.linalg.norm(e1)), 'len_e2': float(np.linalg.norm(e2)), 'sigma_max': float(s[0]), 'sigma_min': float(s[1]),
                    'aspect': float(s[0] / max(s[1], 1e-9)), 'area_uv_per_true': float(abs(np.linalg.det(J)))})
    return out


NAMES = ['top', 'under', 'eave', 'end-', 'end+']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--label', default='')
    ap.add_argument('--json')
    a = ap.parse_args()
    d = Path(a.dir)
    dump = json.loads((d / 'surfaces.json').read_text())
    parts = dump['parts']
    rng = np.random.default_rng(1)
    rgba0 = P.load('assets/graphics/struct/Landmark/landm-01.png')
    size = (rgba0.shape[1], rgba0.shape[0])
    res = {'label': a.label}
    # W1
    tex = np.array(Image.open(d / parts[1]['texture']).convert('RGBA'))
    built = stats(sample_faces(parts[1], tex, size, rng))
    ref = stats(sprite_posts())
    res['W1_posts'] = {'sprite': ref, 'built': built,
                       'mean_rel_err': built['mean_lum'] / ref['mean_lum'] - 1,
                       'T_mean': abs(built['mean_lum'] / ref['mean_lum'] - 1) <= 0.15,
                       'dark_quartile_excess': built['dark_quartile_lum'] - ref['dark_quartile_lum'],
                       'T_dark': abs(built['dark_quartile_lum'] - ref['dark_quartile_lum']) <= 10.0,
                       'min_face_lum': built['min_lum'], 'T_no_void': built['min_lum'] > OUTLINE_LUM,
                       'sprite_with_outline': stats(sprite_posts(False))}
    # W2
    tsize = Image.open(d / parts[2]['texture']).size
    jac = face_jacobians(parts[2], tsize)
    for j in jac:
        j['name'] = ('s0-' if j['quad'] < 5 else 's1-') + NAMES[j['quad'] % 5]
    res['W2_roof'] = {'faces': jac}
    top = jac[0]
    fails = []
    for j in jac:
        j['rel_max'] = j['sigma_max'] / top['sigma_max']
        j['rel_min'] = j['sigma_min'] / top['sigma_min']
        j['ok'] = abs(j['rel_max'] - 1) <= 0.35 and abs(j['rel_min'] - 1) <= 0.35 and j['rel_min'] >= 0.4 and j['rel_max'] >= 0.4
        if not j['ok']:
            fails.append(j['name'])
    res['W2_roof']['reference_face'] = top['name']
    res['W2_roof']['failing_faces'] = fails
    print(json.dumps(res, indent=1))
    if a.json:
        Path(a.json).write_text(json.dumps(res, indent=1))


if __name__ == '__main__':
    main()


def thatch_projection(roof: dict, rgba: np.ndarray):
    """The roof's seen slope as the camera drew it, reconstructed independently of prop_solids.gd _thatch: the patch (across the ridge's
    length by down the slope, one texel a source pixel), each texel the sprite's pixel where the original camera drew that point of the
    slope (bilinear, from the roof's lit planks one pixel in from their edge). Returns (colour (th, tw, 3), drawn (th, tw))."""
    H, W = rgba.shape[:2]
    bits = np.unpackbits(np.frombuffer(__import__('base64').b64decode(roof['mask']), np.uint8))[:H * W].reshape(H, W).astype(bool)
    inner = bits.copy()
    inner[1:-1, 1:-1] = bits[1:-1, 1:-1] & bits[:-2, 1:-1] & bits[2:, 1:-1] & bits[1:-1, :-2] & bits[1:-1, 2:]
    inner[0, :] = inner[-1, :] = False
    inner[:, 0] = inner[:, -1] = False
    cx, cz, k = roof['cx'], roof['cz'], roof['k']
    hw, hd, ridge, rise, thick = roof['w'] / 2, roof['d'] / 2, roof['ridge'], roof['rise'], roof['h']
    slope = float(np.hypot(hw, rise))
    sa, ca = rise / slope, hw / slope
    tw, th = int(np.ceil(2 * hd)), int(np.ceil(slope + thick * sa))
    centre = np.array(roof['boxes'][0][:2], float)
    across = np.array([np.cos(roof['yaw']), np.sin(roof['yaw'])])
    along = np.array([-across[1], across[0]])
    seen = 1.0 if across[1] >= 0 else -1.0
    colour = np.zeros((th, tw, 3))
    drawn = np.zeros((th, tw), bool)
    for j in range(th):
        s = (j + 0.5) * (slope + thick * sa) / th
        if s > slope:
            continue
        for i in range(tw):
            v = -hd + (i + 0.5) * 2 * hd / tw
            q = centre + seen * s * ca * across + v * along
            fx, fy = cx + q[0] - 0.5, cz + k * q[1] - (ridge - s * sa) - 0.5
            x0, y0 = int(np.floor(fx)), int(np.floor(fy))
            if x0 < 0 or y0 < 0 or x0 + 1 >= W or y0 + 1 >= H or not inner[y0:y0 + 2, x0:x0 + 2].all():
                continue
            tx, ty = fx - x0, fy - y0
            c = np.zeros(3)
            for dy in (0, 1):
                for dx in (0, 1):
                    c += rgba[y0 + dy, x0 + dx, :3].astype(float) * ((tx if dx else 1 - tx) * (ty if dy else 1 - ty))
            colour[j, i] = c
            drawn[j, i] = True
    return colour, drawn

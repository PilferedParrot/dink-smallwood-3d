"""Provenance must discriminate nearest-edge extrusion from native patch reuse."""

import numpy as np
from tools.building_continuations import (
    authored_mask,
    nearest_provenance,
    plan_face,
    polygon_mask,
)


def test_native_patch_reuse_restores_two_dimensional_support_and_keeps_authored_texels():
    rgba = np.zeros((8, 12, 4), np.uint8)
    yy, xx = np.mgrid[:8, :8]
    rgba[:, :8, :3] = np.stack((20 + xx * 15, 30 + yy * 20, 80 + xx + yy), axis=2)
    rgba[:, :8, 3] = 255
    support = authored_mask(rgba)
    old = nearest_provenance(support)
    # Red control: padding repeats each last authored pixel across the strip.
    assert len(np.unique(old[:, 8:])) == 8
    assert np.all(old[:, 8] == old[:, 11])
    uv = [[0, 0], [12, 0], [12, 8], [0, 8]]
    pts = [[0, 0, 0], [12, 0, 0], [12, 8, 0], [0, 8, 0]]
    entry = plan_face("fixture", pts, uv, rgba)
    assert entry and not entry.get("unresolved")
    repaired = old.copy().ravel()
    for target, donor in entry["copies"]:
        assert not support.ravel()[target]
        assert support.ravel()[donor]
        repaired[target] = donor
    repaired = repaired.reshape(8, 12)
    assert len(np.unique(repaired[:, 8:])) == 32
    assert np.array_equal(repaired[:, :8], old[:, :8])
    assert np.all(np.diff(repaired[:, 8:] % 12, axis=1) == 1)
    assert np.all(np.diff(repaired[:, 8:] // 12, axis=0) == 1)


def test_empty_material_support_is_reported_and_not_silently_cleared():
    rgba = np.zeros((4, 4, 4), np.uint8)
    entry = plan_face(
        "empty",
        [[0, 0, 0], [4, 0, 0], [4, 4, 0], [0, 4, 0]],
        [[0, 0], [4, 0], [4, 4], [0, 4]],
        rgba,
    )
    assert entry["unresolved"] == "material group has no authored donor"
    assert entry["unsupported"] == 16


def test_face_mask_matches_the_emitted_triangle_fan_for_folded_uv_quads():
    uv = [[0, 0], [4, 4], [0, 4], [4, 0]]
    got = polygon_mask(uv, [0, 0, 4, 4])
    a = polygon_mask(uv[:3], [0, 0, 4, 4])
    b = polygon_mask([uv[0], uv[2], uv[3]], [0, 0, 4, 4])
    assert np.array_equal(got, a | b)


def test_singleton_padding_is_kept_because_it_has_no_repeated_internal_run():
    rgba = np.full((8, 8, 4), 128, np.uint8)
    rgba[:, :, 3] = 255
    rgba[4, 4] = 0
    uv = [[0, 0], [8, 0], [8, 8], [0, 8]]
    pts = [[0, 0, 0], [8, 0, 0], [8, 8, 0], [0, 8, 0]]
    assert plan_face("singleton", pts, uv, rgba) is None


def test_large_missing_region_keeps_native_jacobian_across_tile_joins():
    rgba = np.zeros((12, 12, 4), np.uint8)
    yy, xx = np.mgrid[:4, :4]
    rgba[:4, :4, :3] = np.stack((20 + xx * 30, 30 + yy * 30, 80 + xx + yy), axis=2)
    rgba[:4, :4, 3] = 255
    uv = [[0, 0], [12, 0], [12, 12], [0, 12]]
    pts = [[0, 0, 0], [12, 0, 0], [12, 12, 0], [0, 12, 0]]
    entry = plan_face("large", pts, uv, rgba)
    assert entry["patches"][0]["kind"] == "periodic_native_square"
    provenance = {
        divmod(dst, 12): np.array([donor % 12, donor // 12])
        for dst, donor in entry["copies"]
    }
    for (y, x), origin in provenance.items():
        if (y, x + 1) in provenance and (y + 1, x) in provenance:
            jac = np.stack(
                (provenance[y, x + 1] - origin, provenance[y + 1, x] - origin), axis=1
            )
            assert np.linalg.svd(jac, compute_uv=False)[-1] >= 1 - 1e-8
        local = [
            tuple(provenance[y + dy, x + dx])
            for dy in range(-1, 2)
            for dx in range(-1, 2)
            if (y + dy, x + dx) in provenance
        ]
        assert len(set(local)) == len(local)

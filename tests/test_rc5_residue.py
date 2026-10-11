import importlib.util
from pathlib import Path

import numpy as np

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "rc5_residue.py"
SPEC = importlib.util.spec_from_file_location("rc5_residue", MODULE_PATH)
residue = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(residue)


def test_membership_codes_preserve_high_bits_and_exact_union():
    domain = np.ones((1, 6), dtype=bool)
    default = np.array([[0, 1, 1, 0, 0, 0]], dtype=bool)
    custom = np.array([[0, 0, 1, 0, 0, 0]], dtype=bool)
    sprite = np.array([[0, 0, 0, 1, 1, 0]], dtype=bool)
    masks = {"tile_default": default, "tile_custom": custom, "sprite_hardbox": sprite}

    bits = residue.presence_bits(domain, masks)
    assert bits.tolist() == [[0, 1, 3, 4, 4, 0]]
    assert residue.presence_counts(domain, masks) == {
        "none": 2,
        "tile_default_only": 1,
        "tile_default_and_custom_invalid": 1,
        "sprite_hardbox_only": 2,
    }
    summary = residue.source_presence_summary(domain, masks)
    assert summary == {
        "source_covered_union_px": 4,
        "source_owner_incidences_px": 5,
        "source_only_px": 3,
        "source_overlap_px": 1,
        "no_identified_source_px": 2,
    }


def test_perimeter_cross_tab_is_location_union_and_keeps_membership_bits():
    domain = np.zeros((3, 6), dtype=bool)
    domain[0, 1:5] = True
    domain[1, 0] = True
    default = np.zeros_like(domain)
    custom = np.zeros_like(domain)
    sprite = np.zeros_like(domain)
    default[0, 1:3] = True
    custom[0, 2:4] = True
    sprite[1, 0] = True
    masks = {"tile_default": default, "tile_custom": custom, "sprite_hardbox": sprite}
    perimeter = np.zeros_like(domain)
    perimeter[0, :] = True
    perimeter[:, 0] = True
    perimeter[:, -1] = True
    perimeter[-1, :] = True
    edge_domain = domain & perimeter

    counts = residue.presence_counts(edge_domain, masks)
    assert sum(counts.values()) == 5
    assert counts == {
        "tile_default_only": 1,
        "tile_default_and_custom_invalid": 1,
        "tile_custom_only": 1,
        "sprite_hardbox_only": 1,
        "none": 1,
    }


def test_gzip_json_round_trip_is_deterministic(tmp_path):
    payload = {"counts": [1, 2, 3], "nested": {"ok": True}}
    first = tmp_path / "first.json.gz"
    second = tmp_path / "second.json.gz"
    residue.write_json(first, payload)
    residue.write_json(second, payload)
    assert residue.read_json(first) == payload
    assert first.read_bytes() == second.read_bytes()

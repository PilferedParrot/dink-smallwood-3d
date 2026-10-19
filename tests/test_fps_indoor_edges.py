"""Independent raw map links plus pinned indoor physical differences."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def _run(tmp_path, report, *extra):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    return subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                           "--script", str(ROOT / "tests/fps_indoor_edges_test.gd"), "--",
                           "--report=" + str(report), *extra], cwd=ROOT, env=env,
                          capture_output=True, text=True, timeout=600, check=False)


def _links(data):
    links = data["map_links"]
    raw = (ROOT / "tests/fixtures/indoor-map.dat").read_bytes()
    provenance = json.loads((ROOT / "tests/fixtures/indoor-map-provenance.json").read_text())
    assert hashlib.sha256(raw).hexdigest() == provenance["sha256"]
    loc = struct.unpack_from("<769i", raw, 20)
    pairs = {(e["source"], e["target"]) for e in links["cases"]}
    assert links["slots"] == 768 and links["grid_pairs"] == len(pairs) == 2960
    assert all((b, a) in pairs for a, b in pairs)
    assert all(e["original_loc"] == loc[e["target"]] and
               e["original_allowed"] == (loc[e["target"]] > 0) for e in links["cases"])
    assert any(e["original_allowed"] for e in links["cases"])
    assert any(not e["original_allowed"] for e in links["cases"])
    assert not links["world_equivalence_mismatches"]
    controls = links["discordance_controls"]
    assert len(controls) == 2 and all(e["mismatch_detected"] for e in controls)
    assert {e["world_entry"] for e in controls} == {False, True}
    return links


def test_indoor_edges_use_links_and_collision_instead_of_the_indoor_bit(tmp_path):
    report = Path(os.environ.get("INDOOR_EDGE_REPORT", str(tmp_path / "indoor-edges.json")))
    run = _run(tmp_path, report)
    assert report.is_file(), run.stdout + run.stderr
    data = json.loads(report.read_text())
    links = _links(data)
    assert not links["mismatches"] and not links["wrong_expectation_injected"]
    assert data["counts"]["indoor_indoor"] == 230 and data["counts"]["mixed"] == 16
    assert len({(e["source"], e["target"]) for e in data["edges"]}) == len(data["edges"])
    assert all(e["metadata_original_allowed"] == e["metadata_fps_allowed"] for e in data["edges"]), data["failures"]
    controls = data["negative_controls"]
    assert all(controls[k] for k in ("locked", "missing_link", "row_wrap", "hard_source_point"))
    assert controls["original_fully_hard_edges"] > 0
    expected = json.loads((ROOT / "tests/fixtures/indoor-physical-expected.json").read_text())
    for key in ("sealed", "differences", "fps_open_original_hard_points"):
        assert data["physical_expected"][key] == expected[key]
    assert not data["failures"] and run.returncode == 0 and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr


def test_original_map_link_oracle_rejects_one_deliberately_wrong_expectation(tmp_path):
    report = tmp_path / "wrong-map-link.json"
    run = _run(tmp_path, report, "--metadata-only", "--wrong-expectation")
    assert report.is_file(), run.stdout + run.stderr
    data = json.loads(report.read_text())
    links = _links(data)
    assert links["wrong_expectation_injected"] and len(links["mismatches"]) == 1
    assert len(data["failures"]) == 1 and "raw map.loc oracle" in data["failures"][0]
    assert run.returncode == 1 and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr

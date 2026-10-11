"""Census instrument checks: exact preservation and named old-code failures.

These certify the inventory, not rendering or exclusive visual ownership.
"""
import json
import sys
import os
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from rc5_hardness_census import components, runs, projection, census_screen


def test_component_runs_preserve_all_pixels_including_diagonal_and_singletons():
    mask = np.zeros((400, 640), bool)
    mask[1:4, 23:30] = True
    mask[4, 30] = True
    mask[399, 619] = True
    rebuilt = np.zeros_like(mask)
    parts = components(mask)
    for component in parts:
        assert sum(b-a for _, a, b in component["runs"]) == component["pixels"]
        for y, a, b in component["runs"]: rebuilt[y, a:b] = True
    assert len(parts) == 3
    assert np.array_equal(mask, rebuilt)
    assert sum(b-a for _, a, b in runs(mask)) == mask.sum()


def test_hidden_crop_contributes_no_projected_pixel():
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    e = {"seq":32,"frame":10,"x":392,"y":143,"size":100}
    assert projection(seqs, e).any()
    assert not projection(seqs, e, [[0,178,177,False],[200,378,377,False]]).any()


def test_known_base_cases_and_every_pixel_has_a_partition(tmp_path):
    inventory_path = tmp_path / "inventory.json"
    godot = os.environ.get("GODOT", str(Path.home()/".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
    result = subprocess.run(["nice","-n","10",godot,"--headless","--audio-driver","Dummy",
                             "--path",str(ROOT/"game"),"--script",str(ROOT/"tools/rc5_owner_inventory.gd"),
                             "--","--screens=712,375",f"--out={inventory_path}"],
                            env={**os.environ,"XDG_DATA_HOME":str(tmp_path/"profile"),"OMP_NUM_THREADS":"1",
                                 "OPENBLAS_NUM_THREADS":"1","MKL_NUM_THREADS":"1"},
                            capture_output=True,text=True,timeout=120)
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout+result.stderr
    native = json.loads(inventory_path.read_text())
    inventory = native["screens"]
    world = json.loads((ROOT / "game/data/world.json").read_text())
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    footprints = json.loads((ROOT / "game/data/footprints.json").read_text())["screens"]
    for n in (712,375):
        c = census_screen(world,seqs,footprints,inventory,n,0,native)
        assert c["native_collision_probe_count"] > 0
        assert not c["native_collision_mismatches"]
        assert sum(c["categories_px"].values()) == c["effective_hard_px"]
        assert sum(b-a for _,a,b,_ in c["classification_runs"]) == c["effective_hard_px"]
        assert sum(p["pixels"] for p in c["unowned_components"]) == c["categories_px"]["nothing"]
        if n == 712:
            assert len(c["wall_owners"]) == 9
            assert c["wall_hard_without_fitted_volume_px"] > 0
        else:
            assert c["forest_hard_without_standing_volume_px"] > 0
            assert c["unowned_components"]


def test_current_structure_masks_match_real_fps_queries(tmp_path):
    """Production hooks, source wall seams and fir bodies share one floor."""
    path = tmp_path / "current.json"
    godot = os.environ.get("GODOT",str(Path.home()/".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
    run = subprocess.run(["nice","-n","10",godot,"--headless","--audio-driver","Dummy",
                          "--path",str(ROOT/"game"),"--script",str(ROOT/"tools/rc5_owner_inventory.gd"),
                          "--","--current","--screens=712,375,449,768,420",f"--out={path}"],
                         env={**os.environ,"XDG_DATA_HOME":str(tmp_path/"profile"),"OMP_NUM_THREADS":"1",
                              "OPENBLAS_NUM_THREADS":"1","MKL_NUM_THREADS":"1"},
                         capture_output=True,text=True,timeout=120)
    assert run.returncode == 0 and "SCRIPT ERROR" not in run.stderr,run.stdout+run.stderr
    native = json.loads(path.read_text())
    world = json.loads((ROOT/"game/data/world.json").read_text())
    seqs = json.loads((ROOT/"game/data/sequences.json").read_text())["sequences"]
    footprints = json.loads((ROOT/"game/data/footprints.json").read_text())["screens"]
    structures = tuple(json.loads((ROOT/p).read_text()) for p in
                       ("game/prototype/rc5_walls.json","game/prototype/rc5_fir_collision.json"))
    for key in native["screens"]:
        c=census_screen(world,seqs,footprints,native["screens"],int(key),0,native,structures)
        assert c["native_collision_probe_count"] > 0
        assert not c["native_collision_mismatches"]
        assert sum(c["categories_px"].values()) == c["effective_hard_px"]

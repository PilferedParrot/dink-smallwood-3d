"""Source and native gates for posters mounted on fitted inn-wall fronts."""
import json
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
SCREENS = {33, 35, 195, 225, 226}


def test_source_poster_rectangles_share_one_fitted_wall_front():
    from sys import path
    path.insert(0, str(ROOT / "tools"))
    from collision_map import hardbox

    world_path = ROOT / "game/data/world.json"
    world = json.loads(world_path.read_text())
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    fits = json.loads((ROOT / "game/data/interior.json").read_text())
    before = world_path.read_bytes()
    posters = []
    for key, screen in world["screens"].items():
        for e in screen["sprites"]:
            f = sequences.get(str(e["seq"]), {}).get("frames", [])
            frame = f[e["frame"] - 1] if 0 < e["frame"] <= len(f) else {}
            if frame.get("path", "").startswith("assets/graphics/inner/poster"):
                posters.append((int(key), e, frame))
    assert len(posters) == 5 and {n for n, _, _ in posters} == SCREENS
    for screen_number, poster, frame in posters:
        assert (poster["type"], poster.get("vision", 0), poster.get("brain", 0), poster.get("size", 100)) == (1, 0, 0, 100)
        assert poster["script"] in {"poster", "s2-want"}
        image = Image.open(ROOT / "game" / frame["path"]).convert("RGBA")
        alpha = np.asarray(image)[..., 3] >= 128
        assert alpha.any()
        source_rect = (poster["x"] - frame["dx"], poster["y"] - frame["dy"],
                       poster["x"] - frame["dx"] + image.width,
                       poster["y"] - frame["dy"] + image.height)
        # Every source pixel in the rectangle, including transparent border,
        # has opaque original wall art beneath it on the same fitted front.
        possible = {}
        room_height = max((fits.get(sequences[str(wall["seq"])]["frames"][wall["frame"] - 1]["path"], {}).get("height", 0)
                           for wall in world["screens"][str(screen_number)]["sprites"]
                           if str(wall["seq"]) in sequences and 0 < wall["frame"] <= len(sequences[str(wall["seq"])]["frames"])),
                          default=0)
        for wall in world["screens"][str(screen_number)]["sprites"]:
            wf = sequences.get(str(wall["seq"]), {}).get("frames", [])
            wall_frame = wf[wall["frame"] - 1] if 0 < wall["frame"] <= len(wf) else {}
            fit = fits.get(wall_frame.get("path", ""), {})
            if fit.get("kind") != "wall" or fit.get("cap", 0) <= 0:
                continue
            hard = hardbox(sequences, wall)
            art_y = wall["y"] - wall_frame["dy"] + fit["base"]
            front = art_y if hard[1] + 2 < art_y < hard[3] else hard[3]
            if not (source_rect[1] >= front - room_height and source_rect[3] <= front):
                continue
            wall_alpha = np.asarray(Image.open(ROOT / "game" / wall_frame["path"]).convert("RGBA"))[..., 3] >= 128
            possible.setdefault(front, []).append((wall, wall_frame, hard, wall_alpha))
        supported = []
        for front, walls in possible.items():
            all_pixels = True
            for y in range(source_rect[1], source_rect[3]):
                for x in range(source_rect[0], source_rect[2]):
                    def wall_pixel(item):
                        wall, wall_frame, hard, wall_alpha = item
                        if not hard[0] <= x + 0.5 < hard[2]:
                            return False
                        xx = x - (wall["x"] - wall_frame["dx"])
                        yy = y - (wall["y"] - wall_frame["dy"])
                        return 0 <= xx < wall_alpha.shape[1] and 0 <= yy < wall_alpha.shape[0] and wall_alpha[yy, xx]
                    if not any(wall_pixel(item) for item in walls):
                        all_pixels = False
                        break
                if not all_pixels:
                    break
            if all_pixels:
                supported.append(front)
        assert supported == [100], (screen_number, supported)
    assert world_path.read_bytes() == before


def test_native_mounted_poster_class(tmp_path):
    env = {**os.environ, "XDG_DATA_HOME": str(tmp_path / "data"),
           "XDG_CONFIG_HOME": str(tmp_path / "config"), "OMP_NUM_THREADS": "1",
           "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "LP_NUM_THREADS": "1"}
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
         "--path", "game", "--script", str(ROOT / "tests/fps_mounted_posters_test.gd")],
        cwd=ROOT, env=env, text=True, capture_output=True, timeout=240, check=False,
    )
    assert result.returncode == 0 and "FPS MOUNTED POSTERS PASS" in result.stdout \
        and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr

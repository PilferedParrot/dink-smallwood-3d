"""Sprites against buildings in the game (docs/DIRECTION.md, "Trees against buildings in the game").

A sprite whose hotspot lies within its half-width of a fitted house's wall footprint takes a depth shift in
its own shader (fp_world.gd depth_shift): pulled toward the camera when the original draws it over the
house, pushed away when it draws it under. Actors are sprites like any: a pig against a wall is not cut by it.

Two tests, both through tests/fps_trees_test.gd:
  - classification: the game's flags, read from a loaded scene, equal an independent reading of the map
    data written here from the prototype's rule (sprite_world_proto.gd _flag_nudge): the sprites, the sign,
    the magnitude. Headless.
  - pixels: in rendered scenes the draw order holds (no tree cut by a wall, a tree under a house hidden by
    it), the push-at-0 control equals the plain sprites, and the plausible wrong rules go red. Rendered under
    xvfb with the Dummy audio driver and no Wayland: it never opens a window on the desktop.
"""
import json
import math
import os
import shutil
import struct
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")

# Screens with no flagged sprite, loaded too: the rule must flag nothing there (a rail).
QUIET = [407, 408, 470, 586]  # (505 left: its grass stands by the inn, a kit building, since the tenth pass)


def _png_size(path: Path) -> tuple:
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">I", head[16:20])[0], struct.unpack(">I", head[20:24])[0]


def _png_width(path: Path) -> int:
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">I", head[16:20])[0]


def _origin(n):
    return ((n - 1) % 32 * 600, (n - 1) // 32 * 400)


def _hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _inside(p, h):
    inside = False
    for i in range(len(h)):
        a, b = h[i], h[(i + 1) % len(h)]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]:
            inside = not inside
    return inside


def _segment_distance(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dy * dy
    t = 0.0 if length == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))


def _distance(p, h):
    if _inside(p, h):
        return 0.0
    return min(_segment_distance(p, h[i], h[(i + 1) % len(h)]) for i in range(len(h)))


def _expected_reading(include_castle=True, castle_shift=(0, 0)):
    """{(screen, x, y): shift in px (> 0 pushed away, < 0 pulled toward)} for every upright, non-struct,
    non-fence sprite of the map's default layer within its half-width of a fitted house or castle, as the
    game's rule says. Actors too (the tenth pass settles them like any sprite): the map has none
    within its half-width of a wall (see the actor case of tests/fps_trees_test.gd)."""
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    fits = json.loads((ROOT / "game/prototype/facades.json").read_text())
    screens = json.loads((ROOT / "game/data/world.json").read_text())["screens"]

    def frame(s):
        frames = seqs.get(str(s["seq"]), {}).get("frames", [])
        return frames[max(0, min(len(frames) - 1, int(s["frame"]) - 1))] if frames else None

    def fitted(path):
        return isinstance(fits.get(path), dict) and "faces" in fits[path]

    houses, seen = [], set()
    for number, screen in screens.items():
        n = int(number)
        if screen.get("indoor"):
            continue
        ox, oy = _origin(n)
        for s in screen["sprites"]:
            d = frame(s)
            if s.get("vision", 0) != 0 or s["type"] == 2 or not d or not fitted(d["path"]):
                continue
            rx, ry = ox + s["x"] - 20 - d["dx"], oy + s["y"] - d["dy"]
            key = (d["path"], int(rx), int(ry))
            if key in seen:
                continue
            seen.add(key)
            foot = [(rx + q[0], ry + q[2]) for f in fits[d["path"]]["faces"] if f.get("label") == 1
                    for q in f["pts"] if abs(q[1]) < 1e-3]
            hull = _hull(foot)
            if hull:
                houses.append({"hull": hull, "y": ry + d["dy"], "que": s.get("que", 0), "screen": n})
    # The kit buildings, after the houses: one footprint per block of wall faces; a sprite is over the kit unless one of
    # the kit's upright (type 1) sprites that its picture overlaps lies at or below it (y), as the original draws them.
    for b in fits.get("_kit_buildings", []):
        members = []
        for m in b["members"]:
            if m[1] != "s":
                continue
            s = screens[str(int(m[0]))]["sprites"][int(m[2])]
            d = frame(s)
            if s.get("type", 1) != 1 or not d:
                continue
            ox, oy = _origin(int(m[0]))
            f = max(0.01, s.get("size", 100) / 100)
            w, h = _png_size(ROOT / "game" / d["path"])
            x0, y0 = ox + s["x"] - 20 - d["dx"] * f, oy + s["y"] - d["dy"] * f
            members.append(((x0, y0, x0 + w * f, y0 + h * f), oy + s["y"]))
        rx, ry = b["rect"][0], b["rect"][1]
        blocks = {}
        for f in b["faces"]:
            if f.get("label") == 1:
                blocks.setdefault(int(f["block"]), []).extend((rx + q[0], ry + q[2]) for q in f["pts"] if abs(q[1]) < 1e-3)
        for pts in blocks.values():
            hull = _hull(pts)
            if hull:
                houses.append({"hull": hull, "kit": members})
    # Castle pieces take the same depth rule as fitted houses. Rebuild their plan footprints
    # from the map placements and _walls fit, independently of the game's house_plan().
    if include_castle:
        castle_seen = set()
        for number, screen in screens.items():
            n = int(number)
            if screen.get("indoor"):
                continue
            ox, oy = _origin(n)
            for s in screen["sprites"]:
                d = frame(s)
                if s.get("vision", 0) != 0 or s.get("type", 1) == 2 or not d:
                    continue
                path = d["path"]
                fit = fits.get("_walls", {}).get(path)
                if not isinstance(fit, dict) or not fit.get("parts"):
                    continue
                at = (ox + s["x"] - d["dx"] + castle_shift[0], oy + s["y"] - d["dy"] + castle_shift[1])
                key = (path, int(at[0]), int(at[1]))
                if key in castle_seen:
                    continue
                castle_seen.add(key)
                for part in fit["parts"]:
                    hull = []
                    if part["type"] == "wall":
                        slope, intercept = float(part["s"]), float(part["c"])
                        depth = float(part.get("depth", part["tv"]))
                        x0, x1 = float(part["x0"]), float(part["x1"])
                        hull = [(at[0] + x0, at[1] + slope*x0 + intercept),
                                (at[0] + x1, at[1] + slope*x1 + intercept),
                                (at[0] + x1, at[1] + slope*x1 + intercept - depth),
                                (at[0] + x0, at[1] + slope*x0 + intercept - depth)]
                    elif part["type"] == "block":
                        polygon = part.get("poly_ov") or part["poly"]
                        hull = [(at[0] + p[0], at[1] + p[1]) for p in polygon]
                    else:
                        for i in range(24):
                            angle = math.tau * i / 24.0
                            hull.append((at[0] + float(part["cx"]) + float(part["ar"]) * math.cos(angle),
                                         at[1] + float(part["cz"]) + float(part["k"]) * float(part["ar"]) * math.sin(angle)))
                    hull = _hull(hull)
                    if hull:
                        draw_y = oy + s["y"] - (100000 if s.get("type", 1) == 0 else 0)
                        houses.append({"hull": hull, "y": draw_y, "que": 0, "screen": n, "castle": True})
    out = {}
    for number, screen in screens.items():
        n = int(number)
        if screen.get("indoor"):
            continue
        ox, oy = _origin(n)
        for s in screen["sprites"]:
            d = frame(s)
            if s.get("vision", 0) != 0 or s["type"] in (0, 2) or not d:
                continue
            path = d["path"]
            if "/struct/" in path.lower() or "/fence/" in path.lower():
                continue
            file = ROOT / "game" / path
            assert file.is_file(), path
            half = _png_width(file) / 2 * max(0.01, s["size"] / 100)
            at = (ox + s["x"] - 20, oy + s["y"])
            for h in houses:
                # Castle depth_rule uses the entity hotspot as-is; the older house reading
                # retains the prototype's 20 px sprite-origin correction above.
                point = (ox + s["x"], oy + s["y"]) if h.get("castle") else at
                if _distance(point, h["hull"]) >= half:
                    continue
                if "kit" in h:
                    f = max(0.01, s["size"] / 100)
                    w, hh = _png_size(file)
                    x0, y0 = at[0] - d["dx"] * f, at[1] - d["dy"] * f
                    under = any(r[0] < x0 + w * f and r[2] > x0 and r[1] < y0 + hh * f and r[3] > y0 and my >= at[1] for r, my in h["kit"])
                    out[(n, s["x"], s["y"])] = half if under else -half
                    break
                order, house_order = point[1], h["y"]
                if not h.get("castle") and h["screen"] == n and (s["que"] != 0 or h["que"] != 0):
                    order = s["que"] if s["que"] != 0 else s["y"]
                    house_order = h["que"] if h["que"] != 0 else h["y"] - oy
                out[(n, s["x"], s["y"])] = -half if order > house_order else half
                break
    return out


@pytest.fixture(scope="module")
def expected():
    return _expected_reading()


def _castle_affected_screens():
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    fits = json.loads((ROOT / "game/prototype/facades.json").read_text())
    screens = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    out = set()
    for number, screen in screens.items():
        n = int(number)
        if screen.get("indoor"):
            continue
        for s in screen["sprites"]:
            frames = seqs.get(str(s["seq"]), {}).get("frames", [])
            d = frames[max(0, min(len(frames) - 1, int(s["frame"]) - 1))] if frames else None
            if (s.get("vision", 0) == 0 and s.get("type", 1) != 2 and d
                    and d["path"] in fits.get("_walls", {})):
                # fp_world.castle_pieces() reads this complete 5x5 neighborhood.
                col = (n - 1) % 32
                out.update(n + dx + dz * 32 for dz in range(-2, 3) for dx in range(-2, 3)
                           if 0 <= col + dx < 32 and str(n + dx + dz * 32) in screens
                           and not screens[str(n + dx + dz * 32)].get("indoor"))
    return out


def _run_godot(args, rendered, tmp_path, timeout):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    command = [GODOT, "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests/fps_trees_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + command[:1] + ["--resolution", "960x540"] + command[1:]
    else:
        command.insert(1, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def test_the_games_flags_equal_an_independent_reading_of_the_map(expected, tmp_path):
    screens = sorted({n for n, _, _ in expected} | set(QUIET) | _castle_affected_screens())
    result = _run_godot(["--dump=" + ",".join(str(n) for n in screens)], False, tmp_path, 600)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    nodes = []
    for line in result.stdout.splitlines():
        if line.startswith("NODE "):
            _, screen, x, y, key, shift = line.split()
            nodes.append((int(screen), int(x), int(y), key, float(shift)))
    assert nodes, result.stdout[-2000:]
    flagged = {(s, x, y): shift for s, x, y, _, shift in nodes if abs(shift) > 0.01}
    by_place = {}
    for s, x, y, key, _ in nodes:
        by_place.setdefault((s, x, y), set()).add(key)
    problems = []
    for place, shift in sorted(expected.items()):
        keys = by_place.get(place)
        if keys is None:
            continue  # not a billboard in the game: painted into the ground, or a building kept in 3D
        if place not in flagged:
            problems.append("not flagged: %s expected %.1f" % (place, shift))
        elif abs(flagged[place] - shift) > 0.01:
            problems.append("%s flagged %.2f, expected %.2f" % (place, flagged[place], shift))
    for place, shift in sorted(flagged.items()):
        if place not in expected:
            problems.append("flagged but not expected: %s %.2f" % (place, shift))
    assert not problems, "\n".join(problems)
    # The instrument could have seen something: the cases the sheet and the pixel test use.
    # The kit cases (tenth pass): a barrel over the inn's block on 504, grass under its pieces on 506.
    for place, sign in [((251, 153, 374), -1), ((496, 608, 235), 1), ((734, 249, 327), -1), ((504, 369, 115), -1), ((506, 103, 393), 1)]:
        assert place in flagged and flagged[place] * sign > 0, (place, flagged.get(place))
    # Both signs, and screens where nothing is flagged, are in the sample.
    assert any(v > 0 for v in flagged.values()) and any(v < 0 for v in flagged.values())
    assert not any(s in QUIET for s, _, _ in flagged)
    # Negative controls: deleting the fitted castle reading or shifting it 10 px must disagree
    # with the game's actual dump, proving this test can detect missing/misplaced castle geometry.
    def mismatches(wrong):
        problems = []
        for place, shift in wrong.items():
            if place not in by_place:
                continue
            if place not in flagged or abs(flagged[place] - shift) > 0.01:
                problems.append(place)
        problems.extend(place for place in flagged if place not in wrong)
        return problems

    for wrong in (_expected_reading(include_castle=False), _expected_reading(castle_shift=(0, -10))):
        assert wrong != expected
        assert mismatches(wrong), "castle control did not go red"


def test_the_draw_order_holds_in_rendered_scenes_and_the_controls_go_red(tmp_path):
    result = _run_godot(["--render"], True, tmp_path, 900)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and "FPS TREES PASS" in result.stdout, out[-6000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert not list(tmp_path.glob("*.png"))

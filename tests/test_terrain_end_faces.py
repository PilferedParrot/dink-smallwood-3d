"""Every vertical face of a cave-rock terrain box carries a non-degenerate picture, end faces included.

The cave rock shader (fp_world.gd wrapped_copy) once projected every vertical face of an x-running box on p.xy, and of a
z-running box on p.zy: on the box's two END faces (normal along the run axis) that coordinate is constant, so the face
sampled one texture column (rank 1: horizontal bands, and vertical stripes where thin steps neighbour). A flat wall
has no end faces, so the earlier synthetic control could not see it. Here a stepped wall (boxes with end faces) and a flat
wall are rendered face-on at the same distance, and the comb measure (tools/face_comb.py: horizontal over vertical gradient
energy; an isotropic picture reads about 1, a rank-1 face about 0.1-0.5) is taken on the stepped wall's end faces and on
the flat wall's long face, which is the control that the window can pass at all.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from tools.face_comb import metric

ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT = 1280, 800
WINDOW = (0.6, 1.5)  # a plain rock face reads about 1; face_comb.py's gate is < 1.5

# Source px rects (x, y, w, h). The walls are 40 px deep, so each end face is wide enough to measure.
STEP_X = [[120, 100, 80, 40], [200, 140, 80, 40], [280, 180, 80, 40]]
FLAT_X = [[120, 100, 240, 40]]
STEP_Z = [[100, 120, 40, 80], [140, 200, 40, 80], [180, 280, 40, 80]]
FLAT_Z = [[100, 120, 40, 240]]
D = 80  # px between the camera and the face in every view
VIEWS = [
    # x-running steps: the far end of the last box faces +x
    {"name": "step-x", "x": 360 + D, "y": 200, "yaw": 1.5708, "pitch": -0.05, "rects": STEP_X, "face": [[280, 180, 80, 40], [1, 0]]},
    {"name": "flat-x", "x": 240, "y": 100 - D, "yaw": 3.14159, "pitch": -0.05, "rects": FLAT_X, "face": [[120, 100, 240, 40], [0, -1]]},
    # z-running steps: the first box's near end faces -z
    {"name": "step-z", "x": 120, "y": 120 - D, "yaw": 3.14159, "pitch": -0.05, "rects": STEP_Z, "face": [[100, 120, 40, 80], [0, -1]]},
    {"name": "flat-z", "x": 100 - D, "y": 240, "yaw": -1.5708, "pitch": -0.05, "rects": FLAT_Z, "face": [[100, 120, 40, 240], [-1, 0]]},
]


def _godot():
    return (os.environ.get("GODOT") or shutil.which("godot")
            or str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


@pytest.fixture(scope="module")
def shots(tmp_path_factory):
    godot = _godot()
    if not Path(godot).is_file() or not shutil.which("xvfb-run"):
        pytest.skip("Godot and xvfb-run required")
    out = tmp_path_factory.mktemp("end-faces")
    bundle = out / "views.json"
    bundle.write_text(json.dumps(VIEWS))
    scratch = Path.home() / "pilferedparrot-tools/tools/godot-scratch/godot-scratch"
    env = os.environ.copy()
    env.update(LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="2")
    result = subprocess.run([
        str(scratch), "--", "xvfb-run", "-a", "-s", "-screen 0 1920x1080x24",
        godot, "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility",
        "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/terrain_end_faces_capture.gd"), "--",
        "--screen=100", f"--batch={bundle}", f"--out-dir={out}",
    ], cwd=ROOT, env=env, capture_output=True, text=True, timeout=900)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SCRIPT ERROR" not in output, output[-4000:]
    return out


def _face_box(shots, view):
    """The pixel box (inset 20%, inside the image) of the view's target face."""
    want_rect, want_normal = view["face"]
    for f in json.loads((shots / f"{view['name']}-faces.json").read_text()):
        if f["rect"] == want_rect and f["normal"] == [float(v) for v in want_normal]:
            x0, y0, x1, y1 = f["box"]
            x0, x1 = max(x0, 0.0), min(x1, float(WIDTH))
            y0, y1 = max(y0, 0.0), min(y1, float(HEIGHT))
            w, h = x1 - x0, y1 - y0
            assert w > 60 and h > 60, (view["name"], f["box"])
            return int(x0 + 0.2 * w), int(y0 + 0.2 * h), int(x1 - 0.2 * w), int(y1 - 0.2 * h)
    raise AssertionError(f"{view['name']}: target face not visible")


def _ratio(shots, name):
    view = next(v for v in VIEWS if v["name"] == name)
    return metric(str(shots / f"{name}.png"), _face_box(shots, view))[2]


@pytest.mark.parametrize("flat,step", [("flat-x", "step-x"), ("flat-z", "step-z")])
def test_stepped_end_faces_are_not_rank_one(shots, flat, step):
    control = _ratio(shots, flat)
    assert WINDOW[0] <= control <= WINDOW[1], f"the flat wall must pass the window ({control:.2f}), or the measure is invalid here"
    end = _ratio(shots, step)
    assert WINDOW[0] <= end <= WINDOW[1], f"end face comb ratio {end:.2f} (flat control {control:.2f})"

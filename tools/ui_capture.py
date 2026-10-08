#!/usr/bin/python3
# Copyright 2026 Pilfered Parrot Global Industries. SPDX-License-Identifier: Apache-2.0
"""Capture an exported Dink build through real keys in an isolated software-rendered display.

Verdict: repeatable presentation/input evidence, not a campaign certification.
OCR can falsely reject textured UI; disable page assertions and inspect frames.
Requires Xvfb, xdotool, ImageMagick, Tesseract and Pillow; no model or GPU calls.
"""
import argparse
import difflib
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import tempfile
import time


def observed_text(path, env, region=None):
    """Use block and sparse segmentation; scenery can hide text from either pass."""
    lines = []
    for mode in (3, 6):
        lines.append(subprocess.check_output(["tesseract", str(path), "stdout", "--psm", str(mode)], env=env, stderr=subprocess.DEVNULL, text=True))
    if region:
        from PIL import Image
        source = Image.open(path)
        width, height = source.size
        crop = source.crop(tuple(round(region[i] * (width if i % 2 == 0 else height)) for i in range(4)))
        crop = crop.convert("L").point(lambda pixel: 255 if pixel > 95 else 0)
        with tempfile.NamedTemporaryFile(suffix=".png") as stream:
            crop.save(stream.name)
            lines.append(subprocess.check_output(["tesseract", stream.name, "stdout", "--psm", "6"], env=env, stderr=subprocess.DEVNULL, text=True))
    return "\n".join(lines)


def text_matches(expected, actual):
    # OCR drops occasional characters against the original marble texture.
    # This is a page-identification aid; actual frames still need inspection.
    normalize = lambda value: re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()
    wanted, seen = normalize(expected), normalize(actual)
    if wanted in seen:
        return True
    words, count = seen.split(), len(wanted.split())
    return any(difflib.SequenceMatcher(None, wanted, " ".join(words[i:i + count])).ratio() >= 0.88
               for i in range(len(words) - count + 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--size", default="1280x800")
    parser.add_argument("--sequence", type=Path, help="JSON list of {name, keys, wait} steps")
    parser.add_argument("--save-source", type=Path, help="Explicit saved scenario fixture; skips campaign progression")
    parser.add_argument("--settings-source", type=Path, help="Copy specified settings into this isolated profile")
    parser.add_argument("--no-page-assertions", action="store_true", help="OCR is unreliable on original textures; manually confirm every captured page")
    parser.add_argument("--app-name", default="Dink Smallwood 3D", help="Godot app-data folder for explicitly supplied save/settings")
    parser.add_argument("--startup-wait", type=float, default=20, help="Boot wait with OCR disabled; every resulting frame needs inspection")
    args = parser.parse_args()
    if Path(args.app_name).name != args.app_name or args.app_name in [".", ".."]:
        parser.error("--app-name must be a directory name, without parent components")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    steps = json.loads(args.sequence.read_text()) if args.sequence else [
        {"name": "title", "wait": 1, "expect": "Begin adventure"},
        {"name": "dialogue", "keys": ["Return"], "wait": 2, "expect": "feed the pigs", "ocr_region": [0.145, 0.64, 0.86, 0.82]},
        {"name": "dialogue-dink", "keys": ["Return"], "wait": 1, "expect": "What now", "ocr_region": [0.145, 0.64, 0.86, 0.82]},
        {"name": "dialogue-mother", "keys": ["Return"], "wait": 1, "expect": "YES NOW", "ocr_region": [0.145, 0.64, 0.86, 0.82]},
        {"name": "adventure", "keys": ["Return"], "wait": 1, "expect": "Level"},
        {"name": "equipment", "keys": ["i"], "wait": 1, "expect": "Your equipment"},
        {"name": "equipment-back", "keys": ["Escape"], "wait": 1, "expect": "Level"},
        {"name": "pause", "keys": ["Escape"], "wait": 1, "expect": "Return to adventure"},
        {"name": "settings", "keys": ["Down"] * 6 + ["Return"], "wait": 1, "expect": "Master volume"},
        {"name": "settings-back", "keys": ["Escape"], "wait": 1, "expect": "Return to adventure"},
        {"name": "journal", "keys": ["Down"] * 4 + ["Return"], "wait": 1, "expect": "Adventure journal"},
        {"name": "journal-back", "keys": ["Escape"], "wait": 1, "expect": "Return to adventure"},
        {"name": "map-feedback", "keys": ["Down"] * 5 + ["Return"], "wait": 0.2, "expect": "own a map yet"},
    ]
    with tempfile.TemporaryDirectory(prefix="dink-ui-display-") as temp:
        display_file = Path(temp) / "display"
        with display_file.open("w") as stream:
            xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(stream.fileno()), "-screen", "0", args.size + "x24", "-nolisten", "tcp"], pass_fds=(stream.fileno(),), stderr=subprocess.DEVNULL)
        game = None
        try:
            deadline = time.monotonic() + 10
            while not display_file.read_text().strip():
                if xvfb.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("Xvfb failed to start")
                time.sleep(0.05)
            env = os.environ.copy()
            env.update(DISPLAY=":" + display_file.read_text().strip(), LIBGL_ALWAYS_SOFTWARE="1",
                       LP_NUM_THREADS="2", OMP_NUM_THREADS="1", OMP_THREAD_LIMIT="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1",
                       XDG_DATA_HOME=str(out / "profile/data"), XDG_CONFIG_HOME=str(out / "profile/config"), XDG_CACHE_HOME=str(out / "profile/cache"))
            if args.save_source:
                target = out / "profile/data/godot/app_userdata" / args.app_name / "adventure.json"
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(args.save_source, target)
            if args.settings_source:
                target = out / "profile/data/godot/app_userdata" / args.app_name / "settings.json"
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(args.settings_source, target)
            with (out / "game.log").open("w") as log:
                width, height = args.size.split("x")
                cores = ",".join(str(core) for core in sorted(os.sched_getaffinity(0))[:6])
                game = subprocess.Popen(["taskset", "-c", cores, "nice", "-n", "10", str(args.build.resolve()), "--audio-driver", "Dummy", "--max-fps", "30", "--resolution", f"{width}x{height}", "--position", "0,0"], env=env, stdout=log, stderr=subprocess.STDOUT)
            time.sleep(3)
            windows = subprocess.check_output(["xdotool", "search", "--pid", str(game.pid)], env=env, text=True).split()
            if not windows:
                raise RuntimeError("Exported game window not found")
            window = windows[-1]
            subprocess.run(["xdotool", "windowfocus", "--sync", window], env=env, check=True)
            # World setup precedes the first UI frame; never mistake the boot
            # splash for a title screenshot on a slow/software-rendered machine.
            ready_frame = Path(temp) / "ready.png"
            deadline = time.monotonic() + 120
            while True:
                if game.poll() is not None:
                    raise RuntimeError("Exported game exited during startup; inspect game.log")
                if args.no_page_assertions:
                    time.sleep(args.startup_wait)
                    break
                time.sleep(0.5)
                subprocess.run(["import", "-window", window, str(ready_frame)], env=env, check=True)
                ocr = observed_text(ready_frame, env)
                words = re.sub(r"[^a-z0-9]+", " ", ocr.lower())
                if "begin adventure" in words or "continue adventure" in words:
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError("No first UI frame within 120s; startup/capture inconclusive")
            for step in steps:
                if step.get("click"):
                    # Gameplay polls held attack state once per frame; a zero-
                    # duration synthetic click can vanish between frames.
                    button = str(step["click"])
                    subprocess.run(["xdotool", "mousedown", button], env=env, check=True)
                    time.sleep(step.get("click_hold", 0.2))
                    subprocess.run(["xdotool", "mouseup", button], env=env, check=True)
                if step.get("hold"):
                    held = step["hold"]
                    subprocess.run(["xdotool", "keydown", held["key"]], env=env, check=True)
                    time.sleep(held["seconds"])
                    subprocess.run(["xdotool", "keyup", held["key"]], env=env, check=True)
                for key in step.get("keys", []):
                    subprocess.run(["xdotool", "key", "--clearmodifiers", key], env=env, check=True)
                    time.sleep(0.6)
                delay = step.get("wait", 0.5)
                if args.no_page_assertions and not step.get("instant"):
                    delay = max(delay, 20 if step["name"] in ["dialogue", "feed-ready"] else 2)
                time.sleep(delay)
                picture_path = out / (step["name"] + ".png")
                deadline = time.monotonic() + 60
                while True:
                    subprocess.run(["import", "-window", window, str(picture_path)], env=env, check=True)
                    expected = None if args.no_page_assertions else step.get("expect")
                    if not expected:
                        break
                    ocr = observed_text(picture_path, env, step.get("ocr_region"))
                    if text_matches(expected, ocr):
                        step["observed_text"] = ocr.strip()
                        break
                    if game.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError(f"Page assertion failed for {step['name']}: expected {expected!r}; saw {ocr!r}")
                    time.sleep(0.5)
            setup = "Normal title/start and actual keyboard path, isolated profile; software rendering capped at 30 FPS, nice 10, six-core affinity, two llvmpipe threads."
            if args.save_source:
                setup = "Saved scenario fixture: skips campaign progression and script setup; actual export/input path, isolated profile."
            (out / "inputs.json").write_text(json.dumps({"build": str(args.build.resolve()), "size": args.size, "setup": setup, "page_assertions": not args.no_page_assertions, "save_source": str(args.save_source) if args.save_source else None, "steps": steps}, indent=2) + "\n")
        finally:
            for process in [game, xvfb]:
                if process and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    from PIL import Image, ImageDraw
    sheet = Image.new("RGB", (960, ((len(steps) + 1) // 2) * 340), "#151515")
    draw = ImageDraw.Draw(sheet)
    for index, step in enumerate(steps):
        picture = Image.open(out / (step["name"] + ".png")).convert("RGB")
        picture.thumbnail((470, 310))
        x, y = (index % 2) * 480, (index // 2) * 340
        draw.text((x + 5, y + 5), step["name"], fill="white")
        sheet.paste(picture, (x + 5, y + 25))
    sheet.save(out / "contact-sheet.jpg", quality=92)
    print(out / "contact-sheet.jpg")


if __name__ == "__main__":
    main()

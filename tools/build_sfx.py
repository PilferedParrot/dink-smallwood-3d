#!/usr/bin/env python3
"""Build the sound effects GNU FreeDink leaves silent, from free recordings and our own synthesis.

Usage:
    python3 tools/build_sfx.py --cache DIR               # fetch the sources into DIR, build every file
    python3 tools/build_sfx.py --cache DIR pig1.wav ...  # build some files
    python3 tools/build_sfx.py --synth                   # build only the synthesized files (offline)
    python3 tools/build_sfx.py --report [FILE ...]       # measure: length, peak, true peak, loudness

Why: the campaign's START.c registers 49 numbered sounds. GNU FreeDink ships a free replacement
for 22 of them and leaves 27 files (28 slots) silent, because RTsoft did not own the originals
(docs/AUDIO_FREEDINK_SWAP.md). This tool fills those 27 files. The original v1.08 sounds are not
used: only their sample rate, length and measured level were read, as targets.

Format. Mono 16-bit PCM WAV at the sample rate of the v1.08 file each one stands in for. All 20
of FreeDink's replacements whose original we could measure keep the original's rate too (8000,
11025, 12500 or 22050 Hz). DinkC's playsound speed is an absolute playback rate in Hz (GNU
FreeDink 109.6 sfx.cpp:637-653), so the scripts' speeds assume those rates; game.gd applies
pitch = speed / the file's rate. Each file's content is natural at its own rate.

Loudness. Each file's maximum momentary loudness (EBU R128 M, 400 ms window; files shorter than
0.4 s are padded with silence) is set to a target: the v1.08 file's measured value plus -0.35 dB,
the median offset between FreeDink's 20 replacements and the originals they replace (spread
-8.6 to +5.3 dB), clamped to the range the shipped FreeDink effects span, -29.0 to -10.2 LUFS.
Peaks above the -1 dBTP ceiling are limited (look-ahead 1.5 ms, release 20 ms), by at most
6 dB; where more would be needed, the file ends quieter than its target, and --report shows it.

Sources. Every downloaded source is pinned by SHA-256. Licenses and credits per shipped file are in
licenses/AUDIO-FILES.tsv, which tools/audio_provenance.py checks. Sourced files depend on ffmpeg's
decoder and SoX resampler, so a rebuild on another ffmpeg may differ in the last bit; the
synthesized files are pure numpy and tests/test_audio_provenance.py rebuilds them byte for byte.

Provenance: written 2026-09-30 by Claude Opus 5.5 for the silent-effects fill. Verdict: works;
builds all 27 files in FILLS. 24 of them reach their loudness target within 1 dB; knock, sel2 and
picker are percussive and end 3.1 to 6.9 dB under it (docs/AUDIO_FREEDINK_SWAP.md, "Filled").
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
import wave
import zipfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOUND = ROOT / "game" / "assets" / "sound"
USER_AGENT = "dink-sfx-build/1.0 (https://github.com/PilferedParrot)"
TRUE_PEAK_CEILING = -1.0
LOUDNESS_OFFSET = -0.35          # median(FreeDink replacement - v1.08 original), 20 pairs, dB
SHIPPED_RANGE = (-29.0, -10.2)   # min/max max-momentary loudness of the shipped FreeDink effects

KENNEY = "https://kenney.nl/media/pages/assets"
CC0 = "CC0-1.0"
CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/"

# Downloadable sources, pinned. "member" names a file inside a zip.
SOURCES: dict[str, dict] = {
    "kenney-interface": dict(
        url=f"{KENNEY}/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
        sha256="f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232",
        page="https://kenney.nl/assets/interface-sounds", license=CC0, license_url=CC0_URL,
        author="Kenney (kenney.nl)", title="Interface Sounds 1.0"),
    "kenney-rpg": dict(
        url=f"{KENNEY}/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
        sha256="6dbeaf8544da958d8f2adcb4a4a4b76c1ade34a05f8ab9edccd327da7375f38b",
        page="https://kenney.nl/assets/rpg-audio", license=CC0, license_url=CC0_URL,
        author="Kenney (kenney.nl)", title="RPG Audio"),
    "kenney-jingles": dict(
        url=f"{KENNEY}/music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
        sha256="b729ba57959bd58793d2c5cafa348aaf2655d354f3da35ec4729e03ec77197b8",
        page="https://kenney.nl/assets/music-jingles", license=CC0, license_url=CC0_URL,
        author="Kenney (kenney.nl)", title="Music Jingles"),
}
COMMONS = "https://upload.wikimedia.org/wikipedia/commons"
OGA = "https://opengameart.org/sites/default/files"
PD = "public domain"
BY3, BY3_URL = "CC-BY-3.0", "https://creativecommons.org/licenses/by/3.0/"


def _commons(path: str, sha: str, title: str, author: str, license: str, license_url: str) -> dict:
    name = path.rsplit("/", 1)[-1]
    return dict(url=f"{COMMONS}/{path}", sha256=sha, page=f"https://commons.wikimedia.org/wiki/File:{name}",
                license=license, license_url=license_url, author=author, title=title)


def _oga(file: str, sha: str, entry: str, title: str, author: str, license: str = CC0,
         license_url: str = CC0_URL) -> dict:
    return dict(url=f"{OGA}/{file}", sha256=sha, page=f"https://opengameart.org/content/{entry}",
                license=license, license_url=license_url, author=author, title=title)


PD_URL = "https://creativecommons.org/publicdomain/mark/1.0/"
SOURCES.update({
    "duck": _commons("f/f1/Ducks_snatching.ogg",
                     "24eefe8a596b6c8a4c99b7942b9a094510df240797278618f9534fca819539ec",
                     "Ducks snatching (Ravenhof park, Torhout)", "Bert76", CC0, CC0_URL),
    "pig-erdie": _commons("a/ac/Pig_grunt_-_Erdie.ogg",
                          "1c3d7b63b87e4d85c0db20e0649e72fe4ba2aa9fd8da11424b23e8deb9c6fa37",
                          "Pig grunt (a farm pig)", "erdie (freesound.org/people/Erdie)", BY3, BY3_URL),
    "pig-idle": _oga("pig_idle.mp3", "97ddd0b9ab41b093b74711c3ddaaf7f4c1bb273f56f40c9098294160333defbb",
                     "pig-sfx-pack", "Pig SFX Pack, pig_idle", "Vinrax", BY3, BY3_URL),
    "pig-idle3": _oga("pig_idle3.mp3", "9110b94126520b4840a7c852db02ecd35b29cc9d88f8ac15de7fddabb61ce2f9",
                      "pig-sfx-pack", "Pig SFX Pack, pig_idle3", "Vinrax", BY3, BY3_URL),
    "pig-idle4": _oga("pig_idle4.mp3", "04cd4f5f0f46d32328ad6819bc0ba2f6cd6ea5376a8c22fdff764124ce9ac96f",
                      "pig-sfx-pack", "Pig SFX Pack, pig_idle4", "Vinrax", BY3, BY3_URL),
    "cat-hiss": _commons("5/56/Cat_hissing_-_Zabuhailo.wav",
                         "ffbc639ecce3731c33f89da5b5fb6a829b7f8df916ce6ac7d628e79dd062d304",
                         "Cat hissing", "Zabuhailo (freesound.org/people/Zabuhailo)", CC0, CC0_URL),
    "dog-snarl": _oga("dog_0.7z", "fbd39c35b8743651f48e423d61ca3cee4e67f33ae3a28b5ef4eef0dd46bb043e",
                      "dog-snarl-grunt-grumble", "Dog snarl, grunt, grumble", "qubodup"),
    "bear": _oga("bear.zip", "7fbcc09b292019926e00a460831267fc55ae658e3265bb3c1d4e806920699723",
                 "bear-growls", "Bear growls (U.S. Fish & Wildlife Service recordings)", "AntumDeluge"),
    "monsters": _oga("michelbaradari-monsters.7z", "08a538200e43c2d0e148fc330b4d4325f42aa4359aba3c643b784341facdf8ed",
                     "15-monster-gruntpaindeath-sounds", "15 monster grunt/pain/death sounds", "Michel Baradari",
                     BY3, BY3_URL),
    "piglet": _commons("6/6f/618483_foleyhaven_piglet-squeal-01.flac",
                       "a2db47d1b40d75e545e20d04f137d03df526d21c6cbe652d7eabdbd21acc3494",
                       "Piglet squeal 01", "Foleyhaven (freesound.org/people/Foleyhaven)", CC0, CC0_URL),
    "troll": _oga("troll-roars_0.ogg", "7dc09cc3c3e424b66ac564ac83ac89ee91885c964780694d13f2c4957ac813c7",
                  "big-scary-troll-sounds", "Big scary troll sounds, troll-roars", "Darsycho"),
    "lion": _commons("7/7d/Lion_raring-sound1TamilNadu178.ogg",
                     "ab237d0f960e83412251d0c11f69959f3c2e8d3b14595f7181c3056f7fa18bf7",
                     "Lion roaring (a captive lion, Tamil Nadu)", "த*உழவன் (Wikimedia Commons)", PD, PD_URL),
    "alligator": _commons("b/bf/27alligator2bellow.ogg",
                          "a828496e183f2bfe1a7f139a0197d3e80533a16f67939caa82e429863eb16a0c",
                          "American alligator bellows", "U.S. Fish and Wildlife Service", PD, PD_URL),
    "monster-roar": _oga("monster_roar.wav", "040d2841619c732098c30a638731317d13d7647e5ce1a75a3246219ce4b162ff",
                         "cc0-deep-monster-roar", "CC0 deep monster roar", "trazzz123"),
    "squish": _oga("independent_nu_ljudbank-wet_squish_slurp_impacts.7z",
                   "81fba6009d1b3e48c258b122eef735ed27e86a2dcace9b6a2c93d05b80c83515",
                   "8-wet-squish-slurp-impacts", "8 wet squish, slurp impacts", "Independent.nu (Johannes Pinter)"),
    "splash": _oga("watersplash.flac", "f5fcdc9e8205a87547fe86e734543e1915bc65b9534f772bd491e3ebb8d6b29d",
                   "water-splash-yo-frankie", "Water Splash (Yo Frankie!)", "Blender Foundation", BY3, BY3_URL),
    "magic": _oga("magical_1_0.ogg", "119f9061a566c72c1c58444b03f8685b833079ef268dda02fe742eb34d3bc68f",
                  "magic-spell-sfx", "Magic spell SFX, magical_1", "JaggedStone"),
    "sword-clash": _oga("sword_clash_-_starninjas_0.zip",
                        "f363c80ea1627548d336370750651b0d2d092978148ecfb3642717c2efb54b6b",
                        "20-sword-sound-effects-attacks-and-clashes", "20 sword sound effects, clashes",
                        "StarNinjas"),
    "knock": _commons("1/1c/Knocking_on_wood_or_door.ogg",
                      "f65a210f76fd6e76757ac632585b1bbf9ffeaf35b9c3aa1466eb9dd6c7ca9590",
                      "Knocking on wood or door", "stephan (pdsounds.org)", PD, PD_URL),
})


# --------------------------------------------------------------------------- fetch and decode
def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(key: str, cache: Path) -> Path:
    src = SOURCES[key]
    name = re.sub(r"[^A-Za-z0-9._-]", "_", src["url"].rsplit("/", 1)[-1])
    path = cache / f"{key}--{name}"
    if not path.is_file() or sha256(path) != src["sha256"]:
        cache.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(src["url"], headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=120) as r:
            path.write_bytes(r.read())
    got = sha256(path)
    if got != src["sha256"]:
        raise SystemExit(f"{key}: {src['url']} has sha256 {got}, pinned {src['sha256']}")
    return path


def source_file(key: str, member: str | None, cache: Path) -> Path:
    path = fetch(key, cache)
    if member is None:
        return path
    out = cache / f"{key}--members" / member
    if not out.is_file():
        out.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".7z":
            out.write_bytes(subprocess.run(["7z", "e", "-so", str(path), member], capture_output=True,
                                           check=True).stdout)
        else:
            with zipfile.ZipFile(path) as z:
                out.write_bytes(z.read(member))
    return out


def decode(path: Path, rate: int, start: float = 0.0, dur: float | None = None, af: str = "") -> np.ndarray:
    """Mono float64 at `rate` (SoX resampler). `af` is an extra ffmpeg filter chain run first."""
    chain = ",".join(f for f in (af, f"aresample={rate}:resampler=soxr:precision=28") if f)
    cmd = ["ffmpeg", "-v", "error", "-ss", f"{start}", "-i", str(path)]
    if dur is not None:
        cmd += ["-t", f"{dur}"]
    cmd += ["-ac", "1", "-af", chain, "-f", "f64le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float64).copy()


class Ctx:
    """What a recipe needs: its cache, its rate, and the sources it used (for the record)."""

    def __init__(self, cache: Path | None, rate: int):
        self.cache, self.rate, self.used = cache, rate, []

    def load(self, key: str, member: str | None = None, start: float = 0.0, dur: float | None = None,
             speed: float = 1.0, af: str = "") -> np.ndarray:
        """Decode a source at this file's rate. speed != 1 resamples like tape: pitch and time together."""
        if self.cache is None:
            raise SystemExit("this file needs downloaded sources: pass --cache DIR")
        self.used.append((key, member))
        path = source_file(key, member, self.cache)
        return decode(path, int(round(self.rate / speed)), start, dur, af)


# --------------------------------------------------------------------------- editing primitives
def fade(x: np.ndarray, rate: int, fin: float = 0.0, fout: float = 0.0) -> np.ndarray:
    x = x.copy()
    for n, sl in ((int(fin * rate), slice(None)), (int(fout * rate), slice(None, None, -1))):
        if n > 0:
            ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))
            x[sl][:n] *= ramp
    return x


def trim(x: np.ndarray, rate: int, threshold_db: float = -50.0, pre: float = 0.005) -> np.ndarray:
    """Cut leading and trailing audio below threshold (relative to the peak)."""
    level = np.abs(x) / (np.max(np.abs(x)) + 1e-12)
    idx = np.nonzero(level > 10 ** (threshold_db / 20))[0]
    if idx.size == 0:
        return x
    a = max(0, idx[0] - int(pre * rate))
    return x[a:idx[-1] + 1]


def place(parts: list[tuple[float, np.ndarray, float]], rate: int, length: float | None = None) -> np.ndarray:
    """Mix (start_seconds, signal, gain_db) parts into one signal."""
    end = max(int(t * rate) + len(s) for t, s, _ in parts)
    n = max(end, int(round(length * rate)) if length else 0)
    out = np.zeros(n)
    for t, s, g in parts:
        i = int(t * rate)
        out[i:i + len(s)] += s[:n - i] * 10 ** (g / 20)
    return out[:n] if length is None else out[:int(round(length * rate))]


def fit(x: np.ndarray, rate: int, length: float, fout: float = 0.05) -> np.ndarray:
    """Pad with silence or cut (with a fade) to exactly `length` seconds."""
    n = int(round(length * rate))
    if len(x) >= n:
        return fade(x[:n], rate, 0.0, fout)
    return np.concatenate([x, np.zeros(n - len(x))])


def one_pole_lowpass(x: np.ndarray, rate: int, hz: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * hz / rate)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def convolve(x: np.ndarray, h: np.ndarray) -> np.ndarray:
    n = len(x) + len(h) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(h, size), size)[:n]


def room_ir(rate: int, rt60: float, seed: int, predelay: float = 0.012, reflections: int = 9,
            damping_hz: float = 2500.0) -> np.ndarray:
    """A diffuse room response: sparse early reflections, then decaying noise whose highs die first."""
    rng = np.random.default_rng(seed)
    n = int(rate * rt60 * 1.1)
    t = np.arange(n) / rate
    tail = rng.standard_normal(n) * 10 ** (-3 * t / rt60)
    # High frequencies decay faster in a real room: blend a low-passed copy in as time goes on.
    dark = one_pole_lowpass(tail, rate, damping_hz)
    mix = np.clip(t / (rt60 * 0.5), 0, 1)
    tail = (1 - mix) * tail + mix * dark * 2.0
    tail[: int(predelay * 2 * rate)] = 0.0
    for k in range(reflections):
        d = predelay + rng.uniform(0.0, 0.06)
        i = int(d * rate)
        tail[i] += rng.uniform(0.3, 0.8) * (-1) ** k
    h = np.zeros(n)
    h[0] = 1.0
    return h + tail * 0.08


# --------------------------------------------------------------------------- measurement
def write_wav(path: Path, x: np.ndarray, rate: int) -> None:
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def measure(path: Path) -> dict:
    """Duration, sample peak, true peak, max momentary and integrated loudness (ffmpeg ebur128)."""
    probe = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate,channels,duration,codec_name",
         "-of", "json", str(path)], capture_output=True, text=True, check=True).stdout)["streams"][0]
    r = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", str(path), "-af",
                        "apad=pad_dur=0.4,ebur128=peak=true+sample:framelog=info", "-f", "null", "-"],
                       capture_output=True, text=True)
    moments = [float(v) for v in re.findall(r"M:\s*(-?[\d.]+)", r.stderr)]
    summary = r.stderr[r.stderr.rfind("Summary:"):]

    def pick(pattern: str) -> float:
        m = re.search(pattern, summary, re.S)
        return float(m.group(1)) if m and m.group(1) != "-inf" else float("-inf")

    return {"rate": int(probe["sample_rate"]), "channels": int(probe["channels"]),
            "codec": probe["codec_name"], "seconds": float(probe.get("duration", 0.0)),
            "max_momentary": max(moments) if moments else float("-inf"),
            "integrated": pick(r"I:\s*(-?[\d.]+|-inf)"),
            "true_peak": pick(r"True peak:\s*Peak:\s*(-?[\d.]+|-inf)"),
            "sample_peak": pick(r"Sample peak:\s*Peak:\s*(-?[\d.]+|-inf)")}


def loudness_target(original_max_momentary: float) -> float:
    lo, hi = SHIPPED_RANGE
    return float(np.clip(original_max_momentary + LOUDNESS_OFFSET, lo, hi))


def limit(x: np.ndarray, rate: int, ceiling: float, attack: float = 0.0015, release: float = 0.02) -> np.ndarray:
    """Look-ahead peak limiter: gain never exceeds what keeps |x| under `ceiling` at any sample."""
    need = np.minimum(1.0, ceiling / np.maximum(np.abs(x), 1e-12))
    k = max(1, int(attack * rate))
    ahead = np.lib.stride_tricks.sliding_window_view(np.concatenate([need, np.ones(k - 1)]), k).min(axis=1)
    rel = 1.0 - np.exp(-1.0 / (release * rate))
    g = np.empty_like(ahead)
    last = 1.0
    for i, v in enumerate(ahead):
        last = min(v, last + (1.0 - last) * rel)
        g[i] = last
    smooth = np.convolve(np.concatenate([np.full(k - 1, g[0]), g]), np.ones(k) / k, mode="valid")
    return x * smooth


MAX_LIMIT_DB = 6.0   # at most this much peak reduction to reach a loudness target


def finish(x: np.ndarray, rate: int, target: float, out: Path) -> dict:
    """Scale to the loudness target, limit peaks by at most MAX_LIMIT_DB, hold the true-peak ceiling."""
    x = x - np.mean(x)
    base = x / (np.max(np.abs(x)) + 1e-12)
    ceiling = 10 ** ((TRUE_PEAK_CEILING - 0.5) / 20)      # sample-peak ceiling, room for inter-sample peaks
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / "probe.wav"

        def render(gain_db: float) -> np.ndarray:
            y = base * 10 ** (gain_db / 20)
            over = 20 * np.log10(np.max(np.abs(y)) / ceiling)
            if over > MAX_LIMIT_DB:
                y *= 10 ** ((MAX_LIMIT_DB - over) / 20)
            return limit(y, rate, ceiling) if over > 0 else y

        write_wav(probe, base, rate)
        gain = target - measure(probe)["max_momentary"]
        for _ in range(4):
            y = render(gain)
            write_wav(probe, y, rate)
            m = measure(probe)
            if abs(m["max_momentary"] - target) < 0.15:
                break
            gain += target - m["max_momentary"]
        for _ in range(3):  # inter-sample peaks after 16-bit rounding: trim to the ceiling
            if m["true_peak"] <= TRUE_PEAK_CEILING + 0.05:
                break
            y = y * 10 ** ((TRUE_PEAK_CEILING - 0.1 - m["true_peak"]) / 20)
            write_wav(probe, y, rate)
            m = measure(probe)
    write_wav(out, y, rate)
    return measure(out)


# --------------------------------------------------------------------------- synthesis (our own work)
SPEED_OF_SOUND = 343.0


def synth_flyby(rate: int, seed: int = 42, seconds: float = 0.60, speed: float = 26.0,
                miss: float = 1.1, closest_at: float = 0.30) -> np.ndarray:
    """A fireball passing the listener: its roar, heard through propagation.

    The source is combustion roar (low-passed noise) with sparse crackle. It flies in a straight
    line at `speed` m/s and passes `miss` m from the listener. What reaches the ear is the source
    at its emission time, delayed by distance / c (which is the Doppler shift), scaled by 1 / r,
    and darkened with distance (air and turbulence take the highs first). The swell and the
    pitch drop of the whoosh are outputs of that geometry, not drawn envelopes.
    """
    rng = np.random.default_rng(seed)
    n = int(seconds * rate)
    pad = int(0.1 * rate)
    m = n + 2 * pad
    white = rng.standard_normal(m)
    roar = one_pole_lowpass(white, rate, 2400.0) - one_pole_lowpass(white, rate, 180.0)
    crackle = np.zeros(m)
    hits = rng.random(m) < 90.0 / rate
    crackle[hits] = rng.uniform(-1, 1, hits.sum())
    crackle = np.convolve(crackle, np.exp(-np.arange(int(0.002 * rate)) / (0.0004 * rate)))[:m]
    source = roar / (np.std(roar) + 1e-12) + 0.25 * crackle / (np.std(crackle) + 1e-12)
    tau = (np.arange(m) - pad) / rate                              # emission time
    x = speed * (tau - closest_at)
    r = np.sqrt(x * x + miss * miss)
    arrival = tau + r / SPEED_OF_SOUND                             # monotonic: speed < c
    t = np.arange(n) / rate + miss / SPEED_OF_SOUND
    emitted = np.interp(t, arrival, tau)                           # invert arrival(tau)
    s = np.interp(emitted, tau, source)
    dist = np.interp(emitted, tau, r)
    bright = np.exp(-(dist - miss) / 2.5)                          # share of highs that survive
    dark = one_pole_lowpass(s, rate, 700.0)
    y = (bright * s + (1 - bright) * dark) / dist
    return fade(y, rate, 0.02, 0.06)


# --------------------------------------------------------------------------- the 27 files
class Fill:
    """One file: the v1.08 original's rate, length and level (targets only), and how we build ours."""

    def __init__(self, rate: int, seconds: float, original_max_momentary: float, role: str, build, edit: str):
        self.rate, self.seconds, self.original = rate, seconds, original_max_momentary
        self.role, self.build, self.edit = role, build, edit

    @property
    def target(self) -> float:
        return loudness_target(self.original)


def _interface(c: Ctx, name: str) -> np.ndarray:
    return trim(c.load("kenney-interface", f"Audio/{name}.ogg"), c.rate)


def _steps(c: Ctx) -> np.ndarray:
    steps = [trim(c.load("kenney-rpg", f"Audio/footstep0{i}.ogg"), c.rate) for i in (1, 3, 5, 7)]
    return place([(0.45 * k, s, -1.0 * (k % 2)) for k, s in enumerate(steps)], c.rate)


def _clip(c: Ctx, key: str, member: str | None, start: float, dur: float, speed: float = 1.0,
          af: str = "", fin: float = 0.005, fout: float = 0.04) -> np.ndarray:
    """One excerpt of a recording, trimmed, with short fades so it starts and stops cleanly."""
    return fade(trim(c.load(key, member, start, dur, speed, af), c.rate), c.rate, fin, fout)


def distant_in_cave(x: np.ndarray, rate: int, seconds: float, seed: int = 7, rt60: float = 2.6,
                    direct_db: float = -9.0) -> np.ndarray:
    """A sound far down a cave: highs lost on the way, heard mostly through the cave's reverb."""
    dry = one_pole_lowpass(one_pole_lowpass(x, rate, 1600.0), rate, 1600.0)
    wet = convolve(dry, room_ir(rate, rt60, seed, predelay=0.03, reflections=14, damping_hz=1200.0))
    wet /= np.max(np.abs(wet)) + 1e-12
    dry /= np.max(np.abs(dry)) + 1e-12
    y = wet + 10 ** (direct_db / 20) * np.concatenate([dry, np.zeros(max(0, len(wet) - len(dry)))])[:len(wet)]
    return fit(y, rate, seconds, fout=1.2)


FILLS: dict[str, Fill] = {
    "select.wav": Fill(22050, 0.582, -23.2, "menu cursor move (engine: inventory and choice menus)",
                       lambda c: _interface(c, "pluck_002"), "Kenney Interface Sounds pluck_002, trimmed"),
    "picker.wav": Fill(22050, 0.206, -30.6, "experience counter tick (engine), pig-feed item",
                       lambda c: _interface(c, "click_001"), "Kenney Interface Sounds click_001, trimmed"),
    "escape.wav": Fill(22050, 0.826, -14.9, "game menu and inventory open/close",
                       lambda c: trim(c.load("kenney-rpg", "Audio/clothBelt2.ogg"), c.rate),
                       "Kenney RPG Audio clothBelt2 (a pack or belt rustled open), trimmed"),
    "sel2.wav": Fill(22050, 0.432, -17.4, "title menu button hover",
                     lambda c: _interface(c, "pluck_001"), "Kenney Interface Sounds pluck_001, trimmed"),
    "sel3.wav": Fill(22050, 0.869, -14.9, "title menu choice; warp (at 8000 Hz)",
                     lambda c: _interface(c, "confirmation_002"),
                     "Kenney Interface Sounds confirmation_002, trimmed"),
    "level.wav": Fill(22050, 1.667, -12.4, "level up",
                      lambda c: trim(c.load("kenney-jingles", "Audio/Pizzicato jingles/jingles_PIZZI10.ogg"), c.rate),
                      "Kenney Music Jingles jingles_PIZZI10 (rising D E F# G, pizzicato), trimmed"),
    "sword1.wav": Fill(22050, 0.761, -13.5, "sword enemies' attack",
                       lambda c: _clip(c, "sword-clash", "sword_clash.2.ogg", 0.0, None),
                       "a sword clash (two blades), trimmed"),
    "knock.wav": Fill(12500, 0.676, -8.7, "knocking on a door (s2-mdoor)",
                      lambda c: _clip(c, "knock", None, 4.40, 0.75),
                      "one group of three knuckle raps on a wooden door, 4.40-5.15 s"),
    "quack.wav": Fill(22050, 1.130, -17.4, "duck hit (s7-duck); duck brain",
                      lambda c: _clip(c, "duck", None, 0.14, 1.0),
                      "three duck quacks, 0.14-1.14 s of the recording"),
    "pig1.wav": Fill(8000, 0.772, -19.6, "pig grunt (engine pig brain, at 13000 Hz for a size-100 pig)",
                     lambda c: _clip(c, "pig-idle", None, 0.0, None), "pig grunt, trimmed"),
    "pig2.wav": Fill(8000, 0.882, -22.5, "pig grunt (engine pig brain)",
                     lambda c: _clip(c, "pig-erdie", None, 0.0, None), "pig grunt, trimmed"),
    "pig3.wav": Fill(8000, 0.380, -27.8, "pig grunt (engine pig brain)",
                     lambda c: _clip(c, "pig-idle3", None, 0.0, None), "pig grunt, trimmed"),
    "pig4.wav": Fill(8000, 0.784, -19.4, "pig grunt (engine pig brain)",
                     lambda c: _clip(c, "pig-idle4", None, 0.0, None), "pig grunt, trimmed"),
    "snarl1.wav": Fill(22050, 1.644, -13.5, "monster snarl (no current caller)",
                       lambda c: _clip(c, "cat-hiss", None, 0.58, 1.64), "an angry cat's hiss, 0.58-2.22 s"),
    "snarl2.wav": Fill(22050, 0.782, -29.6, "monster attack snarl (goblins, slayers)",
                       lambda c: _clip(c, "dog-snarl", "dog/dog-snarl.flac", 0.0, None), "a dog's snarl, trimmed"),
    "snarl3.wav": Fill(22050, 1.969, -24.9, "monster attack snarl (goblins, slayers)",
                       lambda c: _clip(c, "bear", "ogg/bear_01.ogg", 0.0, None), "a bear's growl, trimmed"),
    "hurt1.wav": Fill(11025, 2.399, -16.5, "monster hit (boncas, slimes, cave monster; called at 1.5-2x)",
                      lambda c: _clip(c, "monsters", "monster/deathr.wav", 0.0, None, speed=0.56, fout=0.15),
                      "a monster's cry (deathr), slowed to 0.56 like tape so that its pitch and length sit "
                      "near the v1.08 file's at this rate (f0 about 260 vs 212 Hz; 2.2 vs 2.4 s)"),
    "hurt2.wav": Fill(22050, 1.290, -20.2, "pillbug hit",
                      lambda c: _clip(c, "piglet", None, 0.0, None, fout=0.1), "a piglet's squeal, trimmed"),
    "attack1.wav": Fill(11025, 1.302, -16.0, "monster attack (boncas, cave monster, dragon, boss)",
                        lambda c: _clip(c, "troll", None, 1.75, 1.30, fout=0.15),
                        "one troll roar, 1.75-3.05 s of the recording"),
    "drag1.wav": Fill(22050, 1.264, -13.7, "dragon hit; s5-fguy",
                      lambda c: _clip(c, "lion", None, 4.95, 1.30, fout=0.2),
                      "a lion's roar, 4.95-6.25 s of the recording"),
    "drag2.wav": Fill(22050, 3.102, -11.5, "dragon attack",
                      lambda c: _clip(c, "alligator", None, 0.10, 3.20, fin=0.02, fout=0.3),
                      "one alligator bellow, 0.10-3.30 s of the recording"),
    "caveent.wav": Fill(11025, 6.620, -12.2, "a monster roaring deep in the cave (s1-cave, s1-caves noise)",
                        lambda c: distant_in_cave(_clip(c, "monster-roar", None, 0.0, None, fout=0.3), c.rate, 6.62),
                        "a deep monster roar, heard far down a cave: low-passed, with a synthesized cave "
                        "reverb (RT60 2.6 s) and the direct sound 9 dB under it"),
    "squish.wav": Fill(22050, 0.419, -15.5, "slime touch and hit",
                       lambda c: _clip(c, "squish", "impsplat/impactsplat07.mp3.flac", 0.0, None),
                       "a wet squish and slurp impact, trimmed"),
    "splash.wav": Fill(22050, 2.665, -14.5, "fish splashing; boat launch",
                       lambda c: _clip(c, "splash", None, 0.0, None, fout=0.2), "a water splash, trimmed"),
    "spell1.wav": Fill(22050, 1.560, -7.4, "spell cast (wizards, magic items, bosses)",
                       lambda c: _clip(c, "magic", None, 0.0, None, fout=0.15), "a spell cast, trimmed"),
    "steps.wav": Fill(22050, 1.786, -21.2, "footsteps (s3-1st)",
                      _steps, "Kenney RPG Audio footstep01/03/05/07, 0.45 s apart"),
    "flyby.wav": Fill(22050, 0.604, -22.6, "fireball flying past (s4-h1p, s2-fgate, s8-da)",
                      lambda c: synth_flyby(c.rate),
                      "a fireball's roar moving past the listener: 1/r distance, propagation delay (Doppler) and air damping"),
}


# START.c's load_sound slots for each file (docs/AUDIO_FREEDINK_SWAP.md).
SLOTS = {"quack.wav": "1", "pig1.wav": "2", "pig2.wav": "3", "pig3.wav": "4", "pig4.wav": "5",
         "select.wav": "11", "picker.wav": "13", "escape.wav": "18", "sel2.wav": "20", "sel3.wav": "21",
         "spell1.wav": "24", "caveent.wav": "25 and 32", "snarl1.wav": "26", "snarl2.wav": "27",
         "snarl3.wav": "28", "hurt1.wav": "29", "hurt2.wav": "30", "attack1.wav": "31", "level.wav": "33",
         "splash.wav": "35", "sword1.wav": "36", "squish.wav": "38", "steps.wav": "40", "flyby.wav": "42",
         "knock.wav": "45", "drag1.wav": "46", "drag2.wav": "47"}


def record(name: str, sound_dir: Path = SOUND, cache: Path | None = None) -> str:
    """The licenses/AUDIO-FILES.tsv row for a built file. Sources come from a dry build's loads."""
    fill = FILLS[name]
    used = sources_of(name)
    keys = list(dict.fromkeys(k for k, _ in used))
    lic = " AND ".join(sorted({SOURCES[k]["license"] for k in keys})) if keys else "Apache-2.0"
    hashes = " ".join(SOURCES[k]["sha256"] for k in keys) if keys else "-"
    credit = fill.edit
    if keys:
        members = {k: [m for kk, m in used if kk == k and m] for k in keys}
        cited = []
        for k in keys:
            src = SOURCES[k]
            files = ", ".join(sorted({Path(m).name for m in members[k]}))
            cited.append(f"{src['title']} by {src['author']}" + (f" ({files})" if files else "")
                         + f", {src['page']}, {src['license']} {src['license_url']}")
        credit += ". Source: " + "; ".join(cited)
    else:
        credit += ". Synthesized by tools/build_sfx.py (this repository)"
    return "\t".join([name, f"sound slot {SLOTS[name]}: {fill.role}", "-", "tools/build_sfx.py",
                      sha256(sound_dir / name), hashes, lic, credit])


def sources_of(name: str) -> list[tuple[str, str | None]]:
    """Which sources a file's recipe loads, without downloading anything."""
    class Probe(Ctx):
        def load(self, key, member=None, start=0.0, dur=None, speed=1.0, af=""):
            self.used.append((key, member))
            return np.zeros(int(self.rate * (dur or 0.5)) + 64) + 1e-3
    probe = Probe(None, FILLS[name].rate)
    FILLS[name].build(probe)
    return probe.used


def build(name: str, cache: Path | None, out_dir: Path = SOUND) -> dict:
    fill = FILLS[name]
    ctx = Ctx(cache, fill.rate)
    x = fill.build(ctx)
    m = finish(x, fill.rate, fill.target, out_dir / name)
    m["sources"] = ctx.used
    return m


def synthesized(name: str) -> bool:
    return not sources_of(name)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--cache", type=Path)
    ap.add_argument("--out", type=Path, default=SOUND)
    ap.add_argument("--synth", action="store_true", help="build only the synthesized files")
    ap.add_argument("--report", action="store_true", help="measure files instead of building")
    ap.add_argument("--rows", action="store_true", help="print the licenses/AUDIO-FILES.tsv rows")
    a = ap.parse_args()
    if a.rows:
        for name in a.files or sorted(FILLS):
            print(record(name, a.out))
        return 0
    if a.report:
        paths = [Path(f) for f in a.files] or [a.out / n for n in sorted(FILLS)]
        print("file\trate\tseconds\ttarget\tmax_momentary\tintegrated\ttrue_peak\tsample_peak")
        for p in paths:
            m = measure(p)
            fill = FILLS.get(p.name)
            target = f"{fill.target:.1f}" if fill else ""
            print(f"{p.name}\t{m['rate']}\t{m['seconds']:.3f}\t{target}\t{m['max_momentary']:.1f}\t"
                  f"{m['integrated']:.1f}\t{m['true_peak']:.1f}\t{m['sample_peak']:.1f}")
        return 0
    names = a.files or [n for n in sorted(FILLS) if not a.synth or synthesized(n)]
    a.out.mkdir(parents=True, exist_ok=True)
    for name in names:
        m = build(name, a.cache, a.out)
        print(f"{name}: {m['seconds']:.3f} s, {m['rate']} Hz, max momentary {m['max_momentary']:.1f} "
              f"(target {FILLS[name].target:.1f}), true peak {m['true_peak']:.1f} dBTP")
    return 0


if __name__ == "__main__":
    sys.exit(main())

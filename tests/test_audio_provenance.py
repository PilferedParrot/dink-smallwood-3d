"""Shipped audio is the GNU FreeDink set, file for file (docs/AUDIO_FREEDINK_SWAP.md)."""
import shutil
import struct
from pathlib import Path

from tools.audio_provenance import ROOT, ogg_vorbis_seconds, read_table, verify
from tools.import_assets import midi_with_explicit_status

SOUND = ROOT / "game" / "assets" / "sound"
MIDI_SOURCES = sorted(p for p in (ROOT / "third_party" / "freedink-audio-source").rglob("*.mid") if p.is_file())


def test_every_shipped_sound_is_the_listed_freedink_file():
    assert verify() == []


def test_table_covers_music_and_effects_exactly_once():
    names = [row["file"] for row in read_table()]
    assert len(names) == len(set(names)) == 39


def test_verifier_rejects_an_unlisted_or_altered_sound(tmp_path):
    # Negative control: an original-only file (pig1.wav is not in FreeDink)
    # and an altered replacement must both fail.
    work = tmp_path / "sound"
    shutil.copytree(SOUND, work)
    (work / "pig1.wav").write_bytes((work / "punch.wav").read_bytes())
    altered = bytearray((work / "gold.wav").read_bytes()); altered[-1] ^= 0xFF
    (work / "gold.wav").write_bytes(bytes(altered))
    problems = verify(work, manifest=None)
    assert any(p.startswith("pig1.wav: shipped but not in") for p in problems), problems
    assert any(p.startswith("gold.wav: sha256 differs") for p in problems), problems


def _ogg_page(granule, payload):
    return b"OggS" + bytes([0, 0]) + struct.pack("<qIII", granule, 1, 0, 0) + bytes([1, len(payload)]) + payload


def test_empty_music_render_is_rejected():
    ident = b"\x01vorbis" + struct.pack("<IBI", 0, 2, 44100) + bytes(12)
    silent = _ogg_page(0, ident) + _ogg_page(64, b"")
    assert ogg_vorbis_seconds(silent) < 0.01  # the pre-fix 104.ogg was 0.0015 s


def _events(data):
    """Tolerant reader: running status survives meta events, as Rosegarden assumed."""
    events, pos = [], 14
    while pos < len(data):
        size = struct.unpack_from(">I", data, pos + 4)[0]; i, end, tick, status, track = pos + 8, pos + 8 + size, 0, None, []
        while i < end:
            delta = 0
            while True:
                b = data[i]; i += 1; delta = (delta << 7) | (b & 0x7F)
                if not b & 0x80: break
            tick += delta
            if data[i] in (0xFF, 0xF0, 0xF7):
                j = i + (2 if data[i] == 0xFF else 1); n = 0
                while True:
                    b = data[j]; j += 1; n = (n << 7) | (b & 0x7F)
                    if not b & 0x80: break
                track.append((tick, data[i:j + n])); i = j + n
            else:
                if data[i] & 0x80: status = data[i]; i += 1
                count = 1 if status & 0xF0 in (0xC0, 0xD0) else 2
                track.append((tick, bytes([status]) + data[i:i + count])); i += count
        events.append(track); pos = end
    return events


def test_running_status_after_a_meta_event_is_written_out():
    # Note on, an empty text meta, then a running-status note off: the shape
    # of FreeDink's 104.mid that made FluidSynth 2.3 render silence.
    track = bytes([0x00, 0x90, 0x3C, 0x64, 0x00, 0xFF, 0x01, 0x00, 0x0A, 0x3C, 0x00, 0x00, 0xFF, 0x2F, 0x00])
    smf = b"MThd" + struct.pack(">IHHH", 6, 0, 1, 96) + b"MTrk" + struct.pack(">I", len(track)) + track
    out = midi_with_explicit_status(smf)
    assert out.endswith(bytes([0x0A, 0x90, 0x3C, 0x00, 0x00, 0xFF, 0x2F, 0x00]))
    assert _events(out) == _events(smf)
    assert midi_with_explicit_status(out) == out


def test_explicit_status_is_lossless_on_every_freedink_midi():
    assert len(MIDI_SOURCES) >= 12
    for path in MIDI_SOURCES:
        data = path.read_bytes()
        assert _events(midi_with_explicit_status(data)) == _events(data), path.name

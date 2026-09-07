import json
import struct
from pathlib import Path
import pytest

from tools.import_assets import MAP_COUNT, SCREEN_SIZE, parse_dink_dat, parse_hard_dat, parse_map_screen
from tools.import_assets import build_sequences, parse_ini, parse_maps, png_size, sound_manifest


def test_map_screen_reads_96_tiles_before_sprite_table():
    data = bytearray(SCREEN_SIZE)
    # Tile records are 80 bytes; put recognizable values in the first and last.
    struct.pack_into("<i", data, 20, 123)
    struct.pack_into("<i", data, 20 + 95 * 80, 456)
    # The first sprite starts after 97 stored records plus the 240-byte block.
    sprite = 20 + 97 * 80 + 240
    struct.pack_into("<6i", data, sprite, 11, 22, 33, 1, 1, 100)
    data[sprite + 24] = 1
    result = parse_map_screen(bytes(data), 1)
    assert len(result["tiles"]) == 96
    assert result["tiles"][0]["tile"] == 123
    assert result["tiles"][-1]["tile"] == 456
    assert result["sprites"][0]["x"] == 11


def test_installed_freedink_screen_one_mother_layout():
    path = Path("/usr/share/games/dink/dink/Map.dat")
    if not path.exists():
        pytest.skip("FreeDink data package is not installed")
    result = parse_map_screen(path.read_bytes(), 1)
    mother = next(sprite for sprite in result["sprites"] if sprite["index"] == 26)
    assert (mother["x"], mother["y"], mother["script"]) == (202, 157, "s1-h1-m")


def test_hard_dat_preserves_all_800_tile_masks():
    tile_size = 51 * 51 + 1 + 2 + 4
    raw = bytes([0]) * (800 * tile_size)
    result = parse_hard_dat_from_bytes(raw)
    assert result["tile_count"] == 800
    assert len(result["masks_rle"]) == 800


def parse_hard_dat_from_bytes(data):
    """Exercise the public parser contract without requiring installed game data."""
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "Hard.dat"
        path.write_bytes(data)
        return parse_hard_dat(path)


def test_dink_dat_has_769_records(tmp_path):
    values = list(range(MAP_COUNT * 3))
    path = tmp_path / "Dink.dat"
    path.write_bytes(bytes(20) + struct.pack("<%di" % len(values), *values))
    result = parse_dink_dat(path)
    assert len(result["loc"]) == MAP_COUNT
    assert result["music"][3] == MAP_COUNT + 3


def test_sequences_match_freedink_metadata_aliases_and_repeat_sentinels():
    source = Path("/usr/share/games/dink/dink")
    assets = Path("game/assets")
    if not source.exists() or not assets.exists():
        pytest.skip("FreeDink data or imported assets unavailable")
    sequences = build_sequences(parse_ini(source / "Dink.ini"), source, assets)
    # Dink.ini's exact directory must win over same-name assets elsewhere.
    assert len(sequences["10"]["frames"]) == 11
    assert all(frame["path"].startswith("assets/tiles/") for frame in sequences["10"]["frames"])

    # SET_FRAME_FRAME aliases share the referenced bitmap, not the final
    # on-disk bitmap that happened to be cloned while growing the sequence.
    assert sequences["12"]["frames"][4]["frame_ref"] == [12, 3]
    assert sequences["12"]["frames"][4]["path"].endswith("ds-i2-03.png")
    assert sequences["12"]["frames"][5]["frame_ref"] == [12, 2]
    assert sequences["12"]["frames"][5]["path"].endswith("ds-i2-02.png")
    assert sequences["111"]["frames"][4]["frame_ref"] == [-1]

    # The home-exit artwork is positioned by the final SET_SPRITE_INFO line.
    home_exit = sequences["64"]["frames"][1]
    assert (home_exit["dx"], home_exit["dy"]) == (79, 70)
    assert home_exit["hardbox"] == [-88, -42, 88, 9]

    # Default hardboxes use C integer division followed by negation.  Python's
    # ``-width // 4`` would floor a negative result one pixel too far.
    default_frame = sequences["64"]["frames"][5]
    width, height = png_size(assets / default_frame["path"].removeprefix("assets/"))
    assert default_frame["hardbox"] == [-(width // 4), -(height // 10), width // 4, height // 10]


def test_home_exit_warp_uses_the_original_sequence_frame():
    source = Path("/usr/share/games/dink/dink")
    if not source.exists():
        pytest.skip("FreeDink data package is not installed")
    world = parse_maps(source / "Dink.dat", source / "Map.dat")
    exit_sprite = next(sprite for sprite in world["screens"]["1"]["sprites"] if sprite["index"] == 25)
    assert (exit_sprite["seq"], exit_sprite["frame"]) == (64, 2)
    assert exit_sprite["warp"] == {"map": 439, "x": 365, "y": 307}


def test_sound_manifest_records_midi_inputs_and_bundled_replacement_sources():
    source = Path("/usr/share/games/dink/dink/Sound")
    assets = Path("game/assets/sound")
    if not source.exists() or not assets.exists():
        pytest.skip("FreeDink data or imported sound assets unavailable")
    manifest = sound_manifest(source, Path("/usr/share/sounds/sf2/FluidR3_GM.sf2"))
    for track in ("7", "12", "18", "104", "105"):
        entry = manifest["music"][track]
        assert entry["source"] == f"Sound/{track}.mid"
        assert entry["generated_from"] == f"Sound/{track}.mid"
        assert Path(entry["source_directory"]).is_dir()
    assert manifest["music"]["5"]["source_directory"].endswith("src/5.mid")
    exported = json.loads(Path("game/data/sounds.json").read_text())
    assert exported["music"]["104"]["source"] == "Sound/104.mid"
    for section in ("music", "effects"):
        for entry in exported[section].values():
            if "source_directory" in entry:
                assert Path(entry["source_directory"]).is_dir()
    for filename in ("1003.mid", "2.mid", "dance.mid", "insper.mid", "lively.mid", "love.mid", "secret.wav"):
        assert (Path("third_party/freedink-audio-source/dink/Sound") / filename).is_file()

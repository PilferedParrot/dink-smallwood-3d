#!/usr/bin/env python3
"""Import the data files shipped with FreeDink into the Godot data model.

The binary readers deliberately use explicit little endian fields and bounds
checks.  They do not depend on FreeDink's GPL engine implementation.
"""
from __future__ import annotations
import argparse, json, re, shutil, struct, subprocess, tempfile, zlib
from pathlib import Path

SCREEN_SIZE = 31280
MAP_COUNT = 769

def u32(data, off):
    if off < 0 or off + 4 > len(data): raise ValueError(f"truncated u32 at {off}")
    return struct.unpack_from("<I", data, off)[0]
def i32(data, off):
    if off < 0 or off + 4 > len(data): raise ValueError(f"truncated i32 at {off}")
    return struct.unpack_from("<i", data, off)[0]

def parse_dink_dat(path):
    b = Path(path).read_bytes()
    need = 20 + MAP_COUNT * 12
    if len(b) < need: raise ValueError(f"Dink.dat is {len(b)} bytes, need at least {need}")
    vals = struct.unpack_from("<%di" % (MAP_COUNT * 3), b, 20)
    return {"loc": list(vals[:MAP_COUNT]), "music": list(vals[MAP_COUNT:2*MAP_COUNT]),
            "indoor": list(vals[2*MAP_COUNT:3*MAP_COUNT])}

def parse_hard_dat(path):
    b = Path(path).read_bytes(); tile_size = 51 * 51 + 1 + 2 + 4
    if len(b) < 800 * tile_size: raise ValueError("truncated Hard.dat")
    masks=[]; p=0
    for _ in range(800):
        raw=b[p:p+2601]; p += tile_size; runs=[]
        for value in raw:
            if runs and runs[-1][0] == value: runs[-1][1] += 1
            else: runs.append([value,1])
        masks.append(runs)
    defaults=list(struct.unpack_from("<%di" % ((len(b)-p)//4), b, p)) if len(b)-p >= 4 else []
    return {"tile_defaults": defaults, "masks_rle": masks, "tile_size": [51, 51], "tile_count": 800}

def _read_string(data, off, size):
    return data[off:off+size].split(b"\0", 1)[0].decode("latin1", "replace")

def png_size(path):
    b = path.read_bytes()
    if b[:8] != b'\x89PNG\r\n\x1a\n' or len(b) < 24:
        return (0, 0)
    return struct.unpack_from(">II", b, 16)

def parse_map_screen(data, number):
    if number < 1: raise ValueError("screen numbers are one based")
    off = (number - 1) * SCREEN_SIZE
    if off + SCREEN_SIZE > len(data): raise ValueError(f"screen {number} outside Map.dat")
    # The editor stores 97 tile records: 96 visible squares plus one extra
    # record retained for compatibility.  The following 240-byte block is
    # editor metadata, so skipping the extra record shifts every sprite.
    p = off + 20; tiles = []
    for _ in range(97):
        tiles.append({"tile": i32(data,p), "hard": i32(data,p+8)}); p += 80
    p += 240
    sprites=[]
    for index in range(101):
        vals = [i32(data,p + 4*j) for j in range(6)]
        active = data[p+24] != 0
        rotation, special, brain = (i32(data,p+28), i32(data,p+32), i32(data,p+36))
        script = _read_string(data,p+40,14)
        speed, base_walk, base_idle, base_attack, base_hit, timing, que, hard = [i32(data,p+92+4*j) for j in range(8)]
        # editor_sprite.alt trims the image; collision comes from Dink.ini.
        alt = [i32(data,p+124+4*j) for j in range(4)]
        warp = [i32(data,p+140+4*j) for j in range(4)]
        extra = [i32(data,p+156+4*j) for j in range(5)]
        # base_die is at 160; gold through touch_damage begin at 164.
        base_die = i32(data, p + 160)
        stats = [i32(data,p+164+4*j) for j in range(9)]
        if active:
            sprites.append({"index":index,"x":vals[0],"y":vals[1],"seq":vals[2],"frame":vals[3],
                "type":vals[4],"size":vals[5],"rotation":rotation,"special":special,"brain":brain,
                "script":script,"speed":speed,"base_walk":base_walk,"base_idle":base_idle,
                "base_attack":base_attack,"base_hit":base_hit,"base_die":base_die,"timing":timing,"que":que,"hard":hard,
                "clip_rect":alt,"warp": {"map":warp[1],"x":warp[2],"y":warp[3]} if warp[0] else None,
                "vision":stats[6],"nohit":stats[7],"touch_damage":stats[8],"gold":stats[0],"hitpoints":stats[1],"strength":stats[2],"defense":stats[3],"exp":stats[4],"sound":stats[5]})
        p += 220
    # The screen script follows the complete 101-entry sprite table and is a
    # fixed-width C string.  Residual bytes after a leading NUL are cleared
    # storage, not a second spelling of the script.
    script = _read_string(data, off + 30240, 21)
    return {"tiles":tiles[:96], "tiles_extra":tiles[96], "sprites":sprites, "script":script}

def parse_maps(dink_path, map_path, hard_path=None):
    idx=parse_dink_dat(dink_path); b=Path(map_path).read_bytes()
    screens={}
    for logical in range(1, MAP_COUNT):
        ref=idx["loc"][logical]
        if ref and ref * SCREEN_SIZE <= len(b):
            s=parse_map_screen(b, ref); s.update({"music":idx["music"][logical],"indoor":bool(idx["indoor"][logical])})
            screens[str(logical)] = s
    result={"screens":screens,"map_count":len(screens)}
    if hard_path: result["hardness"]=parse_hard_dat(hard_path)
    return result

def parse_ini(path):
    sequences={}; frame_overrides={}; sprite_info={}; warnings=[]
    for lineno, raw in enumerate(Path(path).read_text(errors="replace").splitlines(),1):
        line=raw.strip()
        if not line or line.startswith((";","//")): continue
        # tolerate inline comments used by hand-edited Dink.ini files
        line=re.split(r"\s+(?:;|//)",line,maxsplit=1)[0]; words=line.split(); cmd=words[0].lower()
        try:
            if cmd in ("load_sequence_now","load_sequence") and len(words)>=3:
                path0=words[1].replace("\\","/"); seq=int(words[2]); options=words[3:]
                delay=100; meta={"path":path0,"frames":[],"delay":delay}
                nums=[]
                for x in options:
                    try: nums.append(int(x))
                    except ValueError: meta[x.lower()]=True
                if nums: meta["delay"]=nums[0]
                if len(nums)>=3: meta["offset"]=[nums[1],nums[2]]
                if len(nums)>=7: meta["hardbox"]=[*nums[3:7]]
                sequences.setdefault(str(seq),[]).append(meta)
            elif cmd=="set_frame_delay" and len(words)>=4: frame_overrides.setdefault((int(words[1]),int(words[2])),{})["delay"]=int(words[3])
            elif cmd=="set_frame_special" and len(words)>=4: frame_overrides.setdefault((int(words[1]),int(words[2])),{})["special"]=int(words[3])
            elif cmd=="set_frame_frame" and len(words)>=4:
                frame_overrides.setdefault((int(words[1]),int(words[2])),{})["frame"] = list(map(int,words[3:]))
            elif cmd=="set_sprite_info" and len(words)>=3:
                # seq, frame, x/y offsets, then left/top/right/bottom.
                # FreeDink's tokenizer returns an empty string for missing
                # trailing fields, which atol reads as zero; mirror that for
                # the one malformed stock editor line.  Later lines
                # deliberately replace earlier editor adjustments.
                nums = list(map(int, words[1:9]))
                nums.extend([0] * (8 - len(nums)))
                seq, frame, *metadata = nums
                sprite_info[f"{seq}:{frame}"] = metadata
        except (ValueError, IndexError): warnings.append(f"line {lineno}: {raw}")
    return {"sequences":sequences,"frame_overrides":{f"{a}:{b}":v for (a,b),v in frame_overrides.items()},"sprite_info":sprite_info,"warnings":warnings}

def _casefold_child(parent, name):
    """Find one child without letting a prefix search escape its directory."""
    direct = parent / name
    if direct.exists():
        return direct
    matches = [child for child in parent.iterdir() if child.name.casefold() == name.casefold()]
    return matches[0] if len(matches) == 1 else None


def _casefold_dir(root, parts):
    current = root
    for part in parts:
        current = _casefold_child(current, part) if current.exists() else None
        if current is None or not current.is_dir():
            return None
    return current


def _numbered_frames(directory, prefix, suffix):
    """Return only this sequence's numbered frames in numerical order."""
    if directory is None or not directory.is_dir():
        return []
    expression = re.compile(rf"^{re.escape(prefix)}(\d+){suffix}$", re.I)
    frames = []
    for candidate in directory.iterdir():
        match = expression.match(candidate.name)
        if candidate.is_file() and match:
            frames.append((int(match.group(1)), candidate))
    return [candidate for _, candidate in sorted(frames, key=lambda item: (item[0], item[1].name.casefold()))]


def _asset_frames(load, source, asset_root):
    """Resolve a Dink.ini path within its declared directory, never by prefix rglob."""
    path = Path(load["path"].replace("\\", "/"))
    asset_dir = _casefold_dir(asset_root, path.parent.parts)
    pngs = _numbered_frames(asset_dir, path.name, r"\.png")
    if pngs:
        return pngs

    # This fallback supports callers that have loose BMPs but an already
    # converted asset tree.  It remains directory-scoped for the same reason.
    source_dir = _casefold_dir(source, path.parent.parts)
    bmps = _numbered_frames(source_dir, path.name, r"\.bmp")
    result = []
    for bmp in bmps:
        relative = bmp.relative_to(source).with_suffix(".png")
        target = asset_root.joinpath(*relative.parts)
        if target.exists():
            result.append(target)
    return result


def build_sequences(parsed, source, asset_root):
    """Resolve INI prefixes into stable frame records for the runtime."""
    out={}
    overrides=parsed["frame_overrides"]
    for seq, loads in parsed["sequences"].items():
        frames=[]; delay=100
        for load in loads[-1:]:
            candidates = _asset_frames(load, source, asset_root)
            first_offset = None
            notanim = bool(load.get("notanim") or load.get("leftalign"))
            for frame_no, file in enumerate(candidates,1):
                rel=(Path("assets")/file.relative_to(asset_root)).with_suffix(".png") if file.suffix.lower()==".bmp" else Path("assets")/file.relative_to(asset_root)
                rec={"path":str(rel).replace("\\","/"),"delay":load.get("delay",100),"special":0}
                if "offset" in load:
                    rec.update({"dx":load["offset"][0], "dy":load["offset"][1]})
                else:
                    w, h = png_size(file)
                    offset = [w - w // 2 + w // 6, h - h // 4 - h // 30]
                    if first_offset is None: first_offset = offset
                    if not notanim: offset = first_offset
                    rec.update({"dx":offset[0], "dy":offset[1]})
                if "hardbox" in load:
                    rec["hardbox"] = load["hardbox"]
                else:
                    w, h = png_size(file)
                    rec["hardbox"] = [-(w // 4), -(h // 10), w // 4, h // 10]
                rec.update(overrides.get(f"{seq}:{frame_no}",{}))
                sprite_override = parsed["sprite_info"].get(f"{seq}:{frame_no}")
                if sprite_override:
                    rec.update({"dx": sprite_override[0], "dy": sprite_override[1],
                                "hardbox": sprite_override[2:6]})
                frames.append(rec)
            # SET_FRAME_FRAME can add frames beyond the files on disk (the
            # stock idle sequences use frames 5/6 as aliases).
            for key, change in sorted(overrides.items(), key=lambda item: int(item[0].split(":")[1])):
                if not key.startswith(seq + ":") or "frame" not in change:
                    continue
                frame_no = int(key.split(":")[1]); target = change["frame"]
                if frame_no > len(frames):
                    while len(frames) < frame_no:
                        frames.append(dict(frames[-1]) if frames else {"delay": load.get("delay", 100), "special": 0})
                if frame_no <= len(frames):
                    # -1 is the original engine's repeat sentinel.  Keep it
                    # literal for the runtime; it is not an alias to the
                    # preceding bitmap.
                    frames[frame_no - 1]["frame_ref"] = [-1] if target == [-1] else target[:2]
            delay=load.get("delay",delay)
        out[seq]={"frames":frames,"delay":delay}
    # SET_FRAME_FRAME shares the target image and image metadata.  Delay and
    # special remain properties of the receiving sequence/frame.
    def resolve_alias(seq, frame, seen=()):
        record = out[seq]["frames"][frame - 1]
        target = record.get("frame_ref")
        if not target or target == [-1] or len(target) != 2:
            return record
        target_seq = str(target[0])
        target_frame = target[1]
        key = (seq, frame)
        if key in seen or target_seq not in out or not 1 <= target_frame <= len(out[target_seq]["frames"]):
            return record
        source_record = resolve_alias(target_seq, target_frame, seen + (key,))
        for field in ("path", "dx", "dy", "hardbox"):
            if field in source_record:
                record[field] = source_record[field]
        return record
    for seq, sequence in out.items():
        for frame in range(1, len(sequence["frames"]) + 1):
            resolve_alias(seq, frame)
    return out

def _png_from_bmp(blob, out, transparent=None):
    if blob[:2] != b"BM": raise ValueError("embedded frame is not BMP")
    pixel=u32(blob,10); dib=u32(blob,14); w=struct.unpack_from("<i",blob,18)[0]; h=struct.unpack_from("<i",blob,22)[0]; bits=struct.unpack_from("<H",blob,28)[0]
    if bits != 8 or w<=0 or h==0: raise ValueError("only 8-bit BMP frames are supported")
    top=h<0; h=abs(h); stride=(w+3)&~3; pal=[]
    for i in range(256):
        q=54+i*4; b,g,r=blob[q:q+3]; pal.append((r,g,b))
    rows=[]
    for y in range(h):
        sy=y if top else h-1-y; row=blob[pixel+sy*stride:pixel+sy*stride+w]
        if len(row)!=w: raise ValueError("truncated BMP pixels")
        rows.append(bytes(row))
    raw=b''.join(b'\0'+bytes(sum(([r,g,b,0 if transparent is not None and v==transparent else 255] for v in row for r,g,b in [pal[v]]),[])) for row in rows)
    def chunk(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack(">IIBBBBB",w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    Path(out).write_bytes(png)

def extract_ff(path, out_dir):
    b=Path(path).read_bytes(); n=u32(b,0); table=4 + n*17
    if n>100000 or table>len(b): raise ValueError("invalid dir.ff entry table")
    entries=[]
    for i in range(n):
        p=4+i*17; off=u32(b,p); name=_read_string(b,p+4,13); entries.append((off,name))
    out_dir.mkdir(parents=True,exist_ok=True); count=0
    for i,(off,name) in enumerate(entries):
        end=entries[i+1][0] if i+1<n else len(b)
        if off<table or end<=off or end>len(b): continue
        target=out_dir/(Path(name).stem.lower()+".png")
        try: _png_from_bmp(b[off:end],target,0); count+=1
        except ValueError: pass
    return count

def render_midi(source, output, soundfont):
    """Render a MIDI with a locally installed General MIDI soundfont."""
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="dink-midi-") as td:
        wav = Path(td) / "render.wav"
        subprocess.run(["fluidsynth", "-ni", str(soundfont), str(source), "-F", str(wav), "-r", "44100"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
                        "-c:a", "libvorbis", "-q:a", "5", str(output)], check=True)

_ORIGINAL_DINK_SOUNDS = {
    "1003", "2", "dance", "insper", "lively", "love", "secret",
}
_GPL_REPLACEMENT_MUSIC = {"5", "7", "12", "18", "104", "105"}
_AUDIO_SOURCE_ROOT = "third_party/freedink-audio-source"
_BUNDLED_REPLACEMENT_SOURCES = {
    "1.mid", "5.mid", "7.mid", "12.mid", "13.mid", "18.mid", "104.mid", "105.mid", "106.mid", "denube.mid", "lovin.mid",
    "axe.wav", "bird1.wav", "burn.wav", "fire.wav", "gold.wav", "intro.wav", "nono.wav", "open.wav", "save.wav", "sel1.wav", "stairs.wav", "wscream.wav",
}


def _sound_provenance(source_file):
    """Describe the input, rather than mislabelling a rendered Ogg as source."""
    stem = source_file.stem
    original = stem in _ORIGINAL_DINK_SOUNDS
    source_dir = None
    if not original:
        source_name = stem + ".mid" if source_file.suffix.lower() in (".mid", ".midi", ".ogg") else source_file.name
        if source_name in _BUNDLED_REPLACEMENT_SOURCES:
            source_dir = f"{_AUDIO_SOURCE_ROOT}/src/{source_name}"
    license_text = (
        "Original Dink data; see licenses/FREEDINK-DATA-COPYRIGHT.txt"
        if original else "FreeDink audio replacement; see licenses/AUDIO-REPLACEMENTS.txt"
    )
    if stem in _GPL_REPLACEMENT_MUSIC:
        license_text = "GPL-3.0-or-later FreeDink music replacement; see licenses/AUDIO-REPLACEMENTS.txt"
    result = {"source": f"Sound/{source_file.name}", "license": license_text}
    if source_file.suffix.lower() in (".mid", ".midi"):
        result["generated_from"] = f"Sound/{source_file.name}"
    if source_dir:
        result["source_directory"] = source_dir
    return result


def sound_manifest(source_sound_dir, soundfont):
    music = {}; effects = {}
    for f in sorted(source_sound_dir.iterdir(), key=lambda p: p.name.lower()):
        if not f.is_file(): continue
        stem = f.stem
        if f.suffix.lower() in (".mid", ".midi", ".ogg"):
            output_name = f"{stem}.ogg" if f.suffix.lower() in (".mid", ".midi") else f.name
            music[stem] = {"path": f"assets/sound/{output_name}", "format": "ogg",
                           **_sound_provenance(f)}
        elif f.suffix.lower() in (".wav", ".oga"):
            effects[stem] = {"path": f"assets/sound/{f.name}", "format": f.suffix.lower()[1:],
                             **_sound_provenance(f)}
    return {"music": music, "effects": effects, "soundfont": str(soundfont)}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("source",type=Path); ap.add_argument("--output",type=Path,default=Path("game")); ap.add_argument("--soundfont",type=Path, default=Path("/usr/share/sounds/sf2/FluidR3_GM.sf2")); a=ap.parse_args(); src=a.source; out=a.output
    out.mkdir(parents=True,exist_ok=True); (out/"assets").mkdir(exist_ok=True)
    ini=parse_ini(src/"Dink.ini"); (out/"data/sequences.json").parent.mkdir(parents=True,exist_ok=True)
    world=parse_maps(src/"Dink.dat",src/"Map.dat",src/"Hard.dat"); (out/"data/world.json").write_text(json.dumps(world,indent=2))
    copied=0
    for ff in src.rglob("dir.ff"): copied += extract_ff(ff,out/"assets"/ff.parent.relative_to(src))
    tile_dir = next((p for p in src.iterdir() if p.is_dir() and p.name.lower() == "tiles"), src/"Tiles")
    for tile in tile_dir.glob("*.bmp"):
        try:
            (out/"assets"/"tiles").mkdir(parents=True,exist_ok=True)
            _png_from_bmp(tile.read_bytes(),out/"assets"/"tiles"/(tile.stem.lower()+".png")); copied+=1
        except ValueError: pass
    sound_src = next((p for p in src.iterdir() if p.is_dir() and p.name.lower() == "sound"), src/"Sound")
    if sound_src.exists():
            sound_out = out/"assets"/"sound"; sound_out.mkdir(parents=True, exist_ok=True)
            for f in sound_src.rglob("*"):
                if f.is_file():
                    if f.suffix.lower() in (".mid", ".midi"):
                        render_midi(f, sound_out/(f.stem + ".ogg"), a.soundfont)
                    else:
                        target=sound_out/f.relative_to(sound_src); target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(f,target)
    if sound_src.exists():
        (out/"data/sounds.json").write_text(json.dumps(sound_manifest(sound_src, a.soundfont), indent=2))
    seq_data={"sequences":build_sequences(ini,src,out/"assets"),"frame_overrides":ini["frame_overrides"],"sprite_info":ini["sprite_info"],"warnings":ini["warnings"],
              "asset_frames":[{"path":str(Path("assets")/p.relative_to(out/"assets")).replace("\\","/")} for p in sorted((out/"assets").rglob("*.png"))]}
    (out/"data/sequences.json").write_text(json.dumps(seq_data,indent=2))
    print(json.dumps({"screens":world["map_count"],"sequences":len(ini["sequences"]),"frames":copied,"warnings":len(ini["warnings"])}))
if __name__ == "__main__": main()

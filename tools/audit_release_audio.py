#!/usr/bin/env python3
"""Audit which Dink audio set (GNU FreeDink or original v1.08) a Godot 4 export ships.

Question this answers: does a released build (exe/.x86_64 with an embedded PCK, or a
standalone .pck) contain the ORIGINAL Dink Smallwood v1.08 sounds, or only the GNU
FreeDink replacement set?  The classification is by CONTENT, never by file name.

USAGE
    python3 tools/audit_release_audio.py <pck-or-exe> \
        --freedink <dir> [<dir> ...] --original <dir> [<dir> ...] \
        [--json out.json] [--loose <extracted-release-dir> ...] [--windows 8] [-v]

    --freedink / --original   reference directories (non-recursive) holding .wav/.ogg/.mid/...
                              files of that set.  A file present in both sets with identical
                              bytes (e.g. secret.wav) makes a shipped copy BOTH.
    --loose                   also md5-compare every loose audio file under this directory
                              (e.g. the unzipped release folder) against the reference sets.

WHAT IT DOES
  1. Finds the PCK ('GDPC'): at offset 0, or via the Godot exe trailer (last 12 bytes are
     u64 pck_size + 'GDPC'), or by scanning.  Parses pack format v1/v2/v3 (v3 = Godot 4.4+:
     flags, file_base, dir_offset, 16 reserved u32, directory of {u32 padded path len, path,
     u64 ofs, u64 size, md5[16], u32 flags}).  Every entry's stored md5 is re-computed and
     checked; the offset base (file_base / pck_start) is chosen by that md5 check.
     An encrypted directory or encrypted entries are reported, not decoded.
  2. Lists every entry under res://assets/sound/ and every res://.godot/imported/ entry whose
     name is <audio-file>-<md5>.<ext> (or that a .import file names as a dest of an audio
     source), plus the exported .import files (importer, source_file, compress/mode).
  3. Parses the Godot binary resource (RSRC; RSCC deflate/zstd accepted) of each .sample /
     .oggvorbisstr and extracts format, mix_rate, stereo, frame count / granule length.
  4. Compares each shipped sample to every reference file by audio content:
       WAV/.sample : 8 windows of the reference PCM payload.  (a) PCM-formats: 64-byte windows
                     searched byte-for-byte in the resource blob (8-bit also tried XOR 0x80);
                     (b) all formats: the sample is decoded (PCM8/PCM16/QOA -- Godot's
                     compress/mode=2, decoded here with a from-spec QOA decoder) and 256-frame
                     windows at the same frame positions are compared to the reference by
                     SNR (exact PCM = inf; QOA is lossy, typically 15..40 dB; an unrelated
                     sound is <= ~0 dB).  A window matches at SNR >= 8 dB.
       .ogg        : the reference Ogg is demuxed into Vorbis packets; 64-byte windows from
                     inside 8 audio packets are searched byte-for-byte in the .oggvorbisstr
                     blob (Godot stores the raw Vorbis packets unchanged).
     A shipped sound "matches" a reference when >= 75% of the windows match (and >= 3 windows).
     The same-named references are tried first; if neither set matches by name, every
     reference is tried (catches renamed content).  IMA-ADPCM (compress/mode=1) is not decoded
     and is reported UNKNOWN(unsupported-format).
  5. Classifies each shipped sound: FREEDINK / ORIGINAL / BOTH / UNKNOWN.  A rendered OGG whose
     source MIDI is byte-identical in both sets is labelled BOTH ("shared-midi").

LIMITS
  * A render of an ORIGINAL .mid made with a different synth/soundfont than the reference
    renders in --original will not match and is reported UNKNOWN, not ORIGINAL.  Pass every
    plausible render directory as --original.
  * Silent/tiny references (no energetic window) are matched on whole-file content + length +
    rate and flagged "weak" (silence carries no timbre; only its length/rate can differ).
  * IMA-ADPCM samples, encrypted packs and MP3/FLAC imports are not decoded.

PROVENANCE / VERIFICATION
  Written 2026-09-30 (Claude Sonnet 5.5) for the audio-freedink-swap audit of the published
  PilferedParrot/dink-smallwood-3d releases v0.1.0 and v0.2.0.  Format knowledge: Godot 4.6
  core/io/file_access_pack.cpp, resource_format_binary.cpp, the wav/ogg importers, and the QOA
  spec (qoaformat.org).  Godot 4.6.1's default WAV import is compress/mode=2 (QOA), which is
  what the releases use, hence the from-spec QOA decoder.
  Checks run: (1) all 4 release PCKs (format v3, Godot 4.6.1): every stored entry md5 re-verifies;
  FreeDink files classify FREEDINK with the same-named ORIGINAL reference at 0/8 windows (SNR of
  matching windows 11..60 dB vs <= 1.4 dB for the wrong set).  (2) POSITIVE CONTROL for ORIGINAL:
  the original WAVs/OGGs were imported by Godot 4.6.1 --headless in a scratch project (QOA and
  PCM modes), wrapped in a synthetic v3 PCK: all classify ORIGINAL (secret.wav BOTH), through
  both the decoded-SNR path and the PCM byte-window path.  (3) NEGATIVE CONTROLS: destroying half
  of one sample's payload turns it UNKNOWN; removing the FreeDink references turns the FreeDink
  files UNKNOWN (never ORIGINAL); swapping the --freedink/--original roles flips the labels.

VERDICT (2026-09-30): v0.1.0 and v0.2.0 (Linux and Windows) ship ONLY the GNU FreeDink audio set
  plus the 7 files identical in both sets; 0 ORIGINAL-only sounds in any of the four builds.
"""
import argparse
import hashlib
import json
import math
import mmap
import os
import re
import struct
import sys
import zlib

AUDIO_EXTS = ('.wav', '.ogg', '.mp3', '.mid', '.midi', '.aif', '.aiff', '.flac', '.opus')
IMPORTED_RE = re.compile(r'^(?P<src>.+\.(?:wav|ogg|mp3|mid|midi|aif|aiff|flac|opus))-'
                         r'(?P<hash>[0-9a-f]{32})\.(?P<ext>[A-Za-z0-9_]+)$', re.I)

PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2
PACK_FILE_ENCRYPTED = 1
PACK_FILE_REMOVAL = 2

MATCH_FRACTION = 0.75
MIN_WINDOWS = 3
SNR_MATCH_DB = 8.0
BYTE_WIN = 64
FRAME_WIN = 256


# --------------------------------------------------------------------------- PCK

class PckError(Exception):
    pass


def _u32(m, o):
    return struct.unpack_from('<I', m, o)[0]


def _u64(m, o):
    return struct.unpack_from('<Q', m, o)[0]


def _parse_directory(m, dpos, count, version, limit):
    entries = []
    pos = dpos
    for _ in range(count):
        if pos + 4 > limit:
            raise PckError('directory runs past end of file')
        plen = _u32(m, pos)
        pos += 4
        if plen > 4096 or pos + plen + 8 + 8 + 16 + 4 > limit:
            raise PckError('implausible path length %d' % plen)
        raw = bytes(m[pos:pos + plen])
        pos += plen
        pck_path = raw.rstrip(b'\0').decode('utf-8', 'replace')
        # Godot 4 stores paths without the scheme; PackedData prepends res:// on load.
        path = pck_path if '://' in pck_path else 'res://' + pck_path
        ofs = _u64(m, pos)
        size = _u64(m, pos + 8)
        md5 = bytes(m[pos + 16:pos + 32]).hex()
        pos += 32
        flags = 0
        if version >= 2:
            flags = _u32(m, pos)
            pos += 4
        entries.append({'path': path, 'pck_path': pck_path, 'ofs': ofs, 'size': size, 'md5': md5, 'flags': flags})
    return entries


def parse_pck(m, start):
    """Parse the PCK beginning at absolute offset `start` of buffer m.  Returns dict."""
    n = len(m)
    if bytes(m[start:start + 4]) != b'GDPC':
        raise PckError('no GDPC magic at %d' % start)
    version, vmaj, vmin, vrev = struct.unpack_from('<IIII', m, start + 4)
    if not (1 <= version <= 3):
        raise PckError('unsupported pack format version %d' % version)
    pos = start + 20
    flags = 0
    file_base = 0
    dir_offset = None
    if version >= 2:
        flags = _u32(m, pos)
        file_base = _u64(m, pos + 4)
        pos += 12
    if version >= 3:
        dir_offset = _u64(m, pos)
        pos += 8
    pos += 64  # 16 reserved u32
    info = {'start': start, 'format_version': version, 'engine': '%d.%d.%d' % (vmaj, vmin, vrev),
            'flags': flags, 'file_base': file_base, 'dir_offset': dir_offset}
    if flags & PACK_DIR_ENCRYPTED:
        raise PckError('PCK directory is encrypted (flags=%d); cannot list' % flags)
    rel = bool(flags & PACK_REL_FILEBASE)
    # Directory location candidates.
    if version >= 3:
        cands = [start + dir_offset, dir_offset]
    else:
        cands = [pos]
    entries = None
    last_err = None
    for dpos in cands:
        try:
            if dpos + 4 > n:
                continue
            count = _u32(m, dpos)
            if count > 5_000_000:
                continue
            entries = _parse_directory(m, dpos + 4, count, version, n)
            info['dir_pos'] = dpos
            break
        except (PckError, struct.error) as e:
            last_err = e
    if entries is None:
        raise PckError('cannot parse directory: %s' % last_err)
    # Choose the offset base by md5 verification of the first few non-empty entries.
    bases = []
    if rel or version >= 3:
        bases.append(start + file_base)
    bases += [file_base, start + file_base, start]
    seen = set()
    bases = [b for b in bases if not (b in seen or seen.add(b))]
    probe = [e for e in entries if e['size'] > 0 and not e['flags'] & (PACK_FILE_ENCRYPTED | PACK_FILE_REMOVAL)][:5]
    chosen = None
    for b in bases:
        ok = True
        for e in probe:
            o = b + e['ofs']
            if o + e['size'] > n or hashlib.md5(m[o:o + e['size']]).hexdigest() != e['md5']:
                ok = False
                break
        if ok:
            chosen = b
            break
    if chosen is None and probe:
        raise PckError('no offset base reproduces the stored md5 of the first entries')
    info['offset_base'] = chosen if chosen is not None else bases[0]
    for e in entries:
        e['abs'] = info['offset_base'] + e['ofs']
    info['entries'] = entries
    return info


def find_pck(m):
    n = len(m)
    if bytes(m[:4]) == b'GDPC':
        return 0
    errs = []
    if n > 16 and bytes(m[n - 4:]) == b'GDPC':
        size = _u64(m, n - 12)
        st = n - 12 - size
        if 0 <= st < n and bytes(m[st:st + 4]) == b'GDPC':
            try:
                parse_pck(m, st)
                return st
            except PckError as e:
                errs.append('trailer candidate %d: %s' % (st, e))
    i = 0
    while True:
        i = m.find(b'GDPC', i)
        if i < 0:
            break
        try:
            parse_pck(m, i)
            return i
        except (PckError, struct.error) as e:
            errs.append('scan %d: %s' % (i, e))
        i += 1
    raise PckError('no parsable PCK found (%s)' % '; '.join(errs[:3]))


def read_entry(m, e):
    if e['flags'] & PACK_FILE_ENCRYPTED:
        return None
    return bytes(m[e['abs']:e['abs'] + e['size']])


# --------------------------------------------------------------------------- RSRC (Godot binary resource)

class _R:
    def __init__(self, b, pos=0):
        self.b = b
        self.p = pos

    def u32(self):
        v = struct.unpack_from('<I', self.b, self.p)[0]
        self.p += 4
        return v

    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]
        self.p += 4
        return v

    def u64(self):
        v = struct.unpack_from('<Q', self.b, self.p)[0]
        self.p += 8
        return v

    def i64(self):
        v = struct.unpack_from('<q', self.b, self.p)[0]
        self.p += 8
        return v

    def f32(self):
        v = struct.unpack_from('<f', self.b, self.p)[0]
        self.p += 4
        return v

    def f64(self):
        v = struct.unpack_from('<d', self.b, self.p)[0]
        self.p += 8
        return v

    def take(self, n):
        v = self.b[self.p:self.p + n]
        self.p += n
        return v

    def string(self):
        n = self.u32()
        if n > 1 << 24:
            raise ValueError('implausible string length')
        return self.take(n).rstrip(b'\0').decode('utf-8', 'replace')


def _decompress_rscc(b):
    """RSCC = Godot FileAccessCompressed: 'RSCC', u32 mode, u32 block_size, u32 total_size,
    then block_count u32 sizes and the blocks (mode 1 deflate, 2 zstd)."""
    mode, block, total = struct.unpack_from('<III', b, 4)
    nblocks = (total + block - 1) // block if block else 0
    sizes = struct.unpack_from('<%dI' % nblocks, b, 16)
    pos = 16 + 4 * nblocks
    out = bytearray()
    for sz in sizes:
        chunk = bytes(b[pos:pos + sz])
        pos += sz
        if mode == 1:
            out += zlib.decompress(chunk)
        elif mode == 2:
            try:
                from compression import zstd  # Python 3.14+
                out += zstd.decompress(chunk)
            except ImportError:
                raise ValueError('RSCC zstd needs Python 3.14 compression.zstd')
        else:
            raise ValueError('RSCC compression mode %d unsupported' % mode)
    return bytes(out[:total])


def _variant(r, strings, real64):
    t = r.u32()
    if t == 1:
        return None
    if t == 2:
        return bool(r.u32())
    if t == 3:
        return r.i32()
    if t == 4:
        return r.f64() if real64 else r.f32()
    if t in (5, 44):
        return r.string()
    if t == 24:  # object
        kind = r.u32()
        if kind == 0:
            return ('obj', None)
        if kind == 2:
            return ('int_res', r.u32())
        if kind == 3:
            return ('ext_res', r.u32())
        if kind == 1:
            r.string()
            return ('ext_res_old', r.string())
        raise ValueError('object kind %d' % kind)
    if t == 26:  # dictionary
        n = r.u32() & 0x7FFFFFFF
        return {repr(_variant(r, strings, real64)): _variant(r, strings, real64) for _ in range(n)}
    if t == 30:  # array
        n = r.u32() & 0x7FFFFFFF
        return [_variant(r, strings, real64) for _ in range(n)]
    if t == 31:  # packed byte array
        n = r.u32()
        v = r.take(n)
        r.p += (4 - n % 4) % 4
        return v
    if t == 32:
        n = r.u32()
        v = struct.unpack_from('<%di' % n, r.b, r.p)
        r.p += 4 * n
        return list(v)
    if t == 33:
        n = r.u32()
        v = struct.unpack_from('<%df' % n, r.b, r.p)
        r.p += 4 * n
        return list(v)
    if t == 34:
        n = r.u32()
        return [r.string() for _ in range(n)]
    if t == 40:
        return r.i64()
    if t == 41:
        return r.f64()
    if t == 48:
        n = r.u32()
        v = struct.unpack_from('<%dq' % n, r.b, r.p)
        r.p += 8 * n
        return list(v)
    if t == 49:
        n = r.u32()
        v = struct.unpack_from('<%dd' % n, r.b, r.p)
        r.p += 8 * n
        return list(v)
    raise ValueError('unhandled variant type %d at %d' % (t, r.p))


def parse_rsrc(b):
    """Parse a Godot 4 binary resource.  Returns {'type','resources':[{'type','path','props'}],
    'main': props of the last resource, 'partial': str|None}."""
    if b[:4] == b'RSCC':
        b = _decompress_rscc(b)
    if b[:4] != b'RSRC':
        raise ValueError('not an RSRC file (magic %r)' % b[:4])
    r = _R(b, 4)
    big = r.u32()
    real64 = bool(r.u32())
    if big:
        raise ValueError('big-endian resource unsupported')
    vmaj, vmin, fmt = r.u32(), r.u32(), r.u32()
    rtype = r.string()
    r.u64()  # importmd offset
    flags = r.u32()
    r.u64()  # uid
    if flags & 8:
        r.string()
    r.p += 44  # 11 reserved u32
    real64 = real64 or bool(flags & 4)
    strings = [r.string() for _ in range(r.u32())]
    for _ in range(r.u32()):  # external resources
        r.string()
        r.string()
        if flags & 2:
            r.u64()
    n_int = r.u32()
    table = []
    for _ in range(n_int):
        path = r.string()
        ofs = r.u64()
        table.append((path, ofs))
    resources = []
    partial = None
    for path, ofs in table:
        rr = _R(b, ofs)
        try:
            t = rr.string()
            props = {}
            for _ in range(rr.u32()):
                name = strings[rr.u32()]
                props[name] = _variant(rr, strings, real64)
            resources.append({'type': t, 'path': path, 'props': props})
        except (ValueError, struct.error, IndexError) as e:
            partial = str(e)
            resources.append({'type': '?', 'path': path, 'props': {}})
    return {'type': rtype, 'godot': '%d.%d fmt%d' % (vmaj, vmin, fmt), 'resources': resources,
            'main': resources[-1]['props'] if resources else {}, 'partial': partial}


# --------------------------------------------------------------------------- audio decoders

def parse_wav(b):
    if b[:4] != b'RIFF' or b[8:12] != b'WAVE':
        raise ValueError('not RIFF/WAVE')
    pos = 12
    fmt = data = None
    while pos + 8 <= len(b):
        cid = b[pos:pos + 4]
        sz = struct.unpack_from('<I', b, pos + 4)[0]
        body = pos + 8
        if cid == b'fmt ':
            tag, ch, rate, _br, _al, bits = struct.unpack_from('<HHIIHH', b, body)
            if tag == 0xFFFE and sz >= 26:
                tag = struct.unpack_from('<H', b, body + 24)[0]
            fmt = (tag, ch, rate, bits)
        elif cid == b'data':
            data = (body, min(sz, len(b) - body))
        pos = body + sz + (sz & 1)
    if fmt is None or data is None:
        raise ValueError('missing fmt/data chunk')
    tag, ch, rate, bits = fmt
    return {'tag': tag, 'channels': ch, 'rate': rate, 'bits': bits, 'ofs': data[0], 'len': data[1],
            'frames': data[1] // max(1, ch * (bits // 8))}


class WavRef:
    """A reference WAV: PCM payload access in int16 scale."""

    def __init__(self, b):
        self.b = b
        self.w = parse_wav(b)
        self.supported = self.w['tag'] in (1, 3) and self.w['bits'] in (8, 16, 24, 32)

    @property
    def frames(self):
        return self.w['frames']

    def payload(self):
        return self.b[self.w['ofs']:self.w['ofs'] + self.w['len']]

    def frames_i16(self, start, n):
        w = self.w
        ch, bits = w['channels'], w['bits']
        bps = bits // 8
        start = max(0, start)
        n = max(0, min(n, w['frames'] - start))
        off = w['ofs'] + start * ch * bps
        cnt = n * ch
        raw = self.b[off:off + cnt * bps]
        if w['tag'] == 3 and bits == 32:
            return [int(max(-1, min(1, x)) * 32767) for x in struct.unpack('<%df' % cnt, raw)]
        if bits == 8:
            return [(x - 128) << 8 for x in raw]
        if bits == 16:
            return list(struct.unpack('<%dh' % cnt, raw))
        if bits == 24:
            return [int.from_bytes(raw[i:i + 3], 'little', signed=True) >> 8 for i in range(0, len(raw), 3)]
        return [x >> 16 for x in struct.unpack('<%di' % cnt, raw)]


# QOA (qoaformat.org v1.0) -----------------------------------------------------------

def _qoa_table():
    base = (0.75, -0.75, 2.5, -2.5, 4.5, -4.5, 7.0, -7.0)
    tab = []
    for s in range(16):
        sf = int(math.floor(math.pow(s + 1, 2.75) + 0.5))
        row = []
        for q in base:
            v = sf * q
            row.append(int(math.floor(abs(v) + 0.5)) * (1 if v >= 0 else -1))
        tab.append(row)
    return tab


QOA_TAB = _qoa_table()
assert QOA_TAB[0] == [1, -1, 3, -3, 5, -5, 7, -7] and QOA_TAB[15][7] == -14336 and QOA_TAB[1][2] == 18


class QoaStream:
    """Random-access QOA decoder (frames are independent).  Only decodes frames on demand."""

    def __init__(self, data):
        self.d = data
        if data[:4] == b'qoaf':
            self.total = struct.unpack_from('>I', data, 4)[0]
            pos = 8
        else:
            self.total = None
            pos = 0
        self.frames = []  # (byte_off, first_sample, fsamples, fsize)
        first = 0
        self.channels = self.rate = None
        while pos + 8 <= len(data):
            ch = data[pos]
            rate = int.from_bytes(data[pos + 1:pos + 4], 'big')
            fs, fsize = struct.unpack_from('>HH', data, pos + 4)
            if ch == 0 or fsize < 8 or pos + fsize > len(data):
                break
            if self.channels is None:
                self.channels, self.rate = ch, rate
            self.frames.append((pos, first, fs, fsize))
            first += fs
            pos += fsize
        self.length = first
        if self.channels is None:
            raise ValueError('no QOA frames')
        self._cache = {}

    def _decode_frame(self, idx):
        if idx in self._cache:
            return self._cache[idx]
        pos, first, fs, fsize = self.frames[idx]
        d = self.d
        ch = d[pos]
        p = pos + 8
        hist = []
        wts = []
        for _ in range(ch):
            hist.append(list(struct.unpack_from('>4h', d, p)))
            wts.append(list(struct.unpack_from('>4h', d, p + 8)))
            p += 16
        out = [[0] * fs for _ in range(ch)]
        nslices = (fs + 19) // 20
        for sidx in range(nslices):
            for c in range(ch):
                sl = struct.unpack_from('>Q', d, p)[0]
                p += 8
                sf = (sl >> 60) & 15
                row = QOA_TAB[sf]
                h = hist[c]
                w = wts[c]
                o = out[c]
                base = sidx * 20
                cnt = min(20, fs - base)
                sl = (sl << 4) & 0xFFFFFFFFFFFFFFFF
                for k in range(cnt):
                    pred = (w[0] * h[0] + w[1] * h[1] + w[2] * h[2] + w[3] * h[3]) >> 13
                    q = (sl >> 61) & 7
                    deq = row[q]
                    rec = pred + deq
                    if rec > 32767:
                        rec = 32767
                    elif rec < -32768:
                        rec = -32768
                    o[base + k] = rec
                    delta = deq >> 4
                    w[0] += delta if h[0] >= 0 else -delta
                    w[1] += delta if h[1] >= 0 else -delta
                    w[2] += delta if h[2] >= 0 else -delta
                    w[3] += delta if h[3] >= 0 else -delta
                    h[0], h[1], h[2], h[3] = h[1], h[2], h[3], rec
                    sl = (sl << 3) & 0xFFFFFFFFFFFFFFFF
        self._cache[idx] = out
        return out

    def frames_i16(self, start, n):
        """Interleaved int16 samples for frames [start, start+n)."""
        n = max(0, min(n, self.length - start))
        res = [None] * (n * self.channels)
        got = 0
        for idx, (pos, first, fs, fsize) in enumerate(self.frames):
            if first + fs <= start or first >= start + n:
                continue
            dec = self._decode_frame(idx)
            lo = max(start, first)
            hi = min(start + n, first + fs)
            for s in range(lo, hi):
                for c in range(self.channels):
                    res[(s - start) * self.channels + c] = dec[c][s - first]
                got += 1
        return res


# Ogg demux ---------------------------------------------------------------------------

def ogg_packets(b):
    """Return (packets, last_granule, (channels, rate))."""
    pos = 0
    pkts = []
    cur = bytearray()
    last_gran = 0
    info = None
    while pos + 27 <= len(b):
        if b[pos:pos + 4] != b'OggS':
            nxt = b.find(b'OggS', pos + 1)
            if nxt < 0:
                break
            pos = nxt
            continue
        nseg = b[pos + 26]
        gran = struct.unpack_from('<q', b, pos + 6)[0]
        segs = b[pos + 27:pos + 27 + nseg]
        body = pos + 27 + nseg
        for s in segs:
            cur += b[body:body + s]
            body += s
            if s < 255:
                pkts.append(bytes(cur))
                cur = bytearray()
        if gran >= 0:
            last_gran = gran
        pos = body
    if pkts and pkts[0][:7] == b'\x01vorbis':
        ch = pkts[0][11]
        rate = struct.unpack_from('<I', pkts[0], 12)[0]
        info = (ch, rate)
    return pkts, last_gran, info


# --------------------------------------------------------------------------- windows & matching

def _distinct(bs):
    return len(set(bs))


def byte_windows(payload, k, w=BYTE_WIN):
    n = len(payload)
    out = []
    if n < w:
        return out
    used = set()
    for i in range(k):
        p = int((i + 0.5) * (n - w) / k)
        for tries in range(64):
            q = p + tries * w
            if q + w > n:
                break
            win = payload[q:q + w]
            if _distinct(win) >= 6 and q not in used:
                used.add(q)
                out.append((q, bytes(win)))
                break
    return out


def frame_windows(ref, k, w=FRAME_WIN):
    """Positions (frame index, n) of k energetic windows of the reference."""
    n = ref.frames
    if n < 32:
        return []
    w = min(w, max(16, n // 8))
    out = []
    used = set()
    for i in range(k):
        p = int((i + 0.5) * (n - w) / k)
        for tries in range(64):
            q = p + tries * (w // 2)
            if q + w > n:
                break
            if q in used:
                continue
            s = ref.frames_i16(q, w)
            if sum(x * x for x in s) / max(1, len(s)) > 100.0:  # rms > 10 LSB
                used.add(q)
                out.append((q, w))
                break
    return out


def snr_db(ref, got):
    if len(ref) != len(got) or not ref:
        return -99.0
    sig = sum(x * x for x in ref)
    err = sum((a - b) ** 2 for a, b in zip(ref, got))
    if err == 0:
        return float('inf')
    if sig == 0:
        return -99.0
    return 10 * math.log10(sig / err)


class OggRef:
    def __init__(self, b):
        self.pkts, self.granule, self.info = ogg_packets(b)

    def windows(self, k, w=BYTE_WIN):
        cand = [p for p in self.pkts[3:] if len(p) >= w + 16]
        out = []
        if not cand:
            return out
        for i in range(k):
            p = cand[min(len(cand) - 1, int((i + 0.5) * len(cand) / k))]
            q = (len(p) - w) // 2
            win = p[q:q + w]
            if _distinct(win) >= 6:
                out.append(bytes(win))
        return out


# --------------------------------------------------------------------------- references

def md5_of(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


class Ref:
    def __init__(self, setname, path):
        self.set = setname
        self.path = path
        self.name = os.path.basename(path).lower()
        self.ext = os.path.splitext(self.name)[1]
        self.md5 = md5_of(path)
        self._wav = self._ogg = None
        self._bw = self._fw = self._ow = None
        self.error = None

    def wav(self):
        if self._wav is None:
            try:
                self._wav = WavRef(open(self.path, 'rb').read())
            except Exception as e:  # noqa
                self.error = str(e)
                self._wav = False
        return self._wav or None

    def ogg(self):
        if self._ogg is None:
            try:
                self._ogg = OggRef(open(self.path, 'rb').read())
            except Exception as e:  # noqa
                self.error = str(e)
                self._ogg = False
        return self._ogg or None

    def bwins(self, k):
        if self._bw is None:
            w = self.wav()
            self._bw = byte_windows(w.payload(), k) if w and w.supported else []
        return self._bw

    def fwins(self, k):
        if self._fw is None:
            w = self.wav()
            self._fw = frame_windows(w, k) if w and w.supported else []
        return self._fw

    def owins(self, k):
        if self._ow is None:
            o = self.ogg()
            self._ow = o.windows(k) if o else []
        return self._ow


def load_refs(sets):
    refs = []
    for setname, dirs in sets.items():
        for d in dirs:
            for fn in sorted(os.listdir(d)):
                p = os.path.join(d, fn)
                if os.path.isfile(p) and os.path.splitext(fn)[1].lower() in AUDIO_EXTS:
                    refs.append(Ref(setname, p))
    return refs


# --------------------------------------------------------------------------- sample analysis

FMT_NAMES = {0: 'PCM8', 1: 'PCM16', 2: 'IMA_ADPCM', 3: 'QOA'}


def analyse_wav_resource(blob, K):
    """Return (stream, meta) for an imported AudioStreamWAV .sample blob."""
    res = parse_rsrc(blob)
    p = res['main']
    fmt = p.get('format', 0)
    data = p.get('data', b'')
    rate = int(p.get('mix_rate', 44100))
    stereo = bool(p.get('stereo', False))
    ch = 2 if stereo else 1
    meta = {'format': FMT_NAMES.get(fmt, str(fmt)), 'mix_rate': rate, 'stereo': stereo,
            'data_bytes': len(data), 'loop_mode': p.get('loop_mode', 0), 'rsrc_type': res['type']}
    if res['partial']:
        meta['rsrc_partial'] = res['partial']
    stream = None
    if fmt == 0:
        meta['frames'] = len(data) // ch
        stream = ('pcm8', data, ch)
    elif fmt == 1:
        meta['frames'] = len(data) // (2 * ch)
        stream = ('pcm16', data, ch)
    elif fmt == 3:
        q = QoaStream(data)
        meta['frames'] = q.length
        meta['qoa_channels'] = q.channels
        meta['qoa_rate'] = q.rate
        if q.total is not None and q.total != q.length:
            meta['qoa_header_samples'] = q.total
        stream = ('qoa', q, q.channels)
    else:
        meta['unsupported'] = 'IMA ADPCM not decoded'
    return stream, meta


def stream_frames(stream, start, n):
    kind, obj, ch = stream
    if kind == 'qoa':
        return obj.frames_i16(start, n)
    start = max(0, start)
    if kind == 'pcm8':
        raw = obj[start * ch:(start + n) * ch]
        return [(x if x < 128 else x - 256) << 8 for x in raw]
    raw = obj[start * ch * 2:(start + n) * ch * 2]
    return list(struct.unpack('<%dh' % (len(raw) // 2), raw))


def _mono(s, ch):
    if ch == 1:
        return s
    return [sum(s[i:i + ch]) // ch for i in range(0, len(s), ch)]


def match_wav(stream, blob, meta, ref, K, early_exit=False):
    """Score one imported WAV sample against one reference WAV.  Returns dict."""
    w = ref.wav()
    if not w or not w.supported:
        return {'ref': ref.path, 'set': ref.set, 'skip': ref.error or 'unsupported reference wav'}
    out = {'ref': ref.path, 'set': ref.set}
    # (a) byte windows over the resource blob (meaningful only for PCM formats).
    bws = ref.bwins(K)
    found = 0
    for _o, win in bws:
        if blob.find(win) >= 0:
            found += 1
        elif w.w['bits'] == 8:
            x = bytes(v ^ 0x80 for v in win)
            if blob.find(x) >= 0:
                found += 1
    out['byte_windows'] = '%d/%d' % (found, len(bws))
    out['_bw'] = (found, len(bws))
    # (b) decoded-domain SNR windows.
    fws = ref.fwins(K)
    if not fws and stream is not None:
        # Degenerate reference (silent / tiny): no energetic window exists.  Compare the whole
        # decoded signal plus length and rate.  Marked weak: silence carries no timbre.
        n = min(w.frames, 400000)
        a = w.frames_i16(0, n)
        g = stream_frames(stream, 0, n)
        if w.w['channels'] != stream[2]:
            a, g = _mono(a, w.w['channels']), _mono(g, stream[2])
        # QOA is lossy: a silent reference may decode to +-1 LSB, so also accept |diff| <= 64
        # (int16 scale, -54 dBFS) as identical silence.
        close = len(a) == len(g) and (snr_db(a, g) >= SNR_MATCH_DB
                                      or all(abs(x - y) <= 64 for x, y in zip(a, g)))
        same = (w.w['rate'] == meta.get('mix_rate') and w.frames == meta.get('frames') and close)
        out['degenerate'] = True
        out['snr_windows'] = '%d/1(whole-file)' % (1 if same else 0)
        out['_snr'] = (1 if same else 0, 1)
        out['snr_db'] = []
        out['ref_meta'] = {'rate': w.w['rate'], 'channels': w.w['channels'], 'bits': w.w['bits'],
                           'frames': w.frames}
        out['meta_ok'] = same
        return out
    snrs = []
    good = 0
    for i, (q, n) in enumerate(fws):
        a = w.frames_i16(q, n)
        g = stream_frames(stream, q, n) if stream else []
        if w.w['channels'] != stream[2]:
            a, g = _mono(a, w.w['channels']), _mono(g, stream[2])
        s = snr_db(a, g) if len(a) == len(g) else -99.0
        snrs.append(s)
        if s >= SNR_MATCH_DB:
            good += 1
        if early_exit and i == 2 and good == 0:
            break
    out['snr_windows'] = '%d/%d' % (good, len(fws))
    out['_snr'] = (good, len(fws))
    out['snr_db'] = [round(s, 1) if s != float('inf') else 'inf' for s in snrs]
    out['ref_meta'] = {'rate': w.w['rate'], 'channels': w.w['channels'], 'bits': w.w['bits'],
                       'frames': w.frames}
    out['meta_ok'] = (w.w['rate'] == meta.get('mix_rate') and abs(w.frames - meta.get('frames', -1)) <= 1
                      and (w.w['channels'] == 2) == meta.get('stereo'))
    return out


def score_of(m):
    """(matched, total) of the better of the two methods."""
    a = m.get('_snr', (0, 0))
    b = m.get('_bw', (0, 0))
    best = max((a, b), key=lambda t: (t[0] / t[1] if t[1] else 0, t[1]))
    return best


def is_match(m):
    got, tot = score_of(m)
    if m.get('degenerate'):
        return tot >= 1 and got >= tot
    return tot >= MIN_WINDOWS and got >= MATCH_FRACTION * tot


def match_ogg(blob, ref, K, meta=None):
    meta = meta or {}
    wins = ref.owins(K)
    o = ref.ogg()
    ref_meta = {'granule_length': o.granule if o else None,
                'rate': o.info[1] if o and o.info else None, 'packets': len(o.pkts) if o else 0}
    gl = meta.get('granule_length')
    meta_ok = (gl is not None and o is not None and abs(gl - o.granule) <= 2048)
    if not wins and o and o.pkts:
        # Degenerate reference (almost no audio packets): whole-file packet match + length.
        found = sum(1 for p in o.pkts if p and blob.find(p) >= 0)
        ok = found == len(o.pkts) and meta_ok
        return {'ref': ref.path, 'set': ref.set, 'degenerate': True,
                'packets_found': '%d/%d' % (found, len(o.pkts)), 'packet_windows': '%d/1(whole-file)' % (1 if ok else 0),
                'ref_meta': ref_meta, 'meta_ok': meta_ok, '_snr': (0, 0), '_bw': (1 if ok else 0, 1)}
    found = sum(1 for w in wins if blob.find(w) >= 0)
    return {'ref': ref.path, 'set': ref.set, 'packet_windows': '%d/%d' % (found, len(wins)),
            'ref_meta': ref_meta, 'meta_ok': meta_ok, '_snr': (0, 0), '_bw': (found, len(wins))}


def public(m):
    return {k: v for k, v in m.items() if not k.startswith('_')}


def classify_sound(kind, blob, meta, stream, stem, refs, shared_midi, K):
    """Match a shipped sound against refs; returns (label, evidence dict)."""
    kind_refs = [r for r in refs if r.ext == ('.ogg' if kind == 'ogg' else '.wav')]
    by_name = [r for r in kind_refs if r.name == stem.lower()]

    def run(cands, early):
        res = []
        seen = set()
        for r in cands:
            key = (r.set, r.md5)
            if key in seen:
                continue
            seen.add(key)
            m = match_ogg(blob, r, K, meta) if kind == 'ogg' else match_wav(stream, blob, meta, r, K, early)
            res.append(m)
        return res

    named = run(by_name, False)
    ev = {'name_hinted': [public(m) for m in named]}
    sets = {m['set'] for m in named if is_match(m)}
    hits = []
    path = 'name-hinted'
    if not sets:
        if kind == 'wav' and stream is None:
            return 'UNKNOWN', dict(ev, reason='unsupported format ' + meta.get('unsupported', '?'))
        others = [r for r in kind_refs if r not in by_name]
        wide = run(others, True)
        hits = [m for m in wide if is_match(m) and not m.get('degenerate')]
        ev['content_search_hits'] = [public(m) for m in hits[:6]]
        sets = {m['set'] for m in hits}
        path = 'content-search (renamed)'
    basis = path
    label = 'UNKNOWN'
    if sets == {'freedink', 'original'}:
        label = 'BOTH'
    elif sets == {'freedink'}:
        label = 'FREEDINK'
    elif sets == {'original'}:
        label = 'ORIGINAL'
    if kind == 'ogg' and label in ('FREEDINK', 'ORIGINAL') and stem.lower() in shared_midi:
        label, basis = 'BOTH', path + ' + shared-midi (same .mid bytes in both sets)'
    ev['basis'] = basis
    if label != 'UNKNOWN':
        matched = [m for m in (named if path == 'name-hinted' else hits) if is_match(m)]
        if matched and all(m.get('degenerate') for m in matched):
            ev['weak'] = True
            ev['weak_reason'] = ('reference has no energetic window/audio packets (silent or tiny); '
                                 'matched on whole-file content + length + rate only')
    return label, ev


# --------------------------------------------------------------------------- main audit

def parse_import(text):
    d = {}
    section = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('['):
            section = line.strip('[]')
        elif '=' in line and not line.startswith(';'):
            k, v = line.split('=', 1)
            d[(section, k.strip())] = v.strip().strip('"')
    return d


def audit(target, refs, K, loose_dirs, verbose):
    f = open(target, 'rb')
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    out = {'target': os.path.abspath(target), 'size': len(m),
           'sha256': hashlib.sha256(m).hexdigest()}
    start = find_pck(m)
    pck = parse_pck(m, start)
    entries = pck.pop('entries')
    out['pck'] = {k: v for k, v in pck.items()}
    out['pck']['entry_count'] = len(entries)
    md5_bad = []
    for e in entries:
        if e['flags'] & (PACK_FILE_ENCRYPTED | PACK_FILE_REMOVAL):
            continue
        if hashlib.md5(m[e['abs']:e['abs'] + e['size']]).hexdigest() != e['md5']:
            md5_bad.append(e['path'])
    out['pck']['md5_mismatches'] = md5_bad
    by_path = {e['path']: e for e in entries}

    # .import files and the imported destinations they name
    imports = {}
    dest_to_src = {}
    for e in entries:
        if e['path'].endswith('.import'):
            d = parse_import(read_entry(m, e).decode('utf-8', 'replace'))
            src = d.get(('deps', 'source_file'), '')
            imports[e['path']] = {'source_file': src, 'importer': d.get(('remap', 'importer')),
                                  'path': d.get(('remap', 'path')),
                                  'compress_mode': d.get(('params', 'compress/mode')),
                                  'params': {k[1]: v for k, v in d.items() if k[0] == 'params'}}
            if src.lower().endswith(AUDIO_EXTS):
                for dm in re.findall(r'"(res://[^"]+)"', d.get(('deps', 'dest_files'), '')):
                    dest_to_src[dm] = src

    sound_entries = []
    for e in entries:
        p = e['path']
        low = p.lower()
        in_sound = p.startswith('res://assets/sound/')
        im = IMPORTED_RE.match(os.path.basename(p)) if p.startswith('res://.godot/imported/') else None
        derived = p in dest_to_src or bool(im)
        raw_audio = low.endswith(AUDIO_EXTS)
        if in_sound or derived or raw_audio:
            sound_entries.append({'path': p, 'size': e['size'], 'md5': e['md5'],
                                  'kind': ('imported' if derived else 'raw' if raw_audio else 'import-meta'
                                           if low.endswith('.import') else 'other'),
                                  'source': dest_to_src.get(p) or (im.group('src') if im else None)})
    out['sound_entries'] = sound_entries

    # Shared MIDI stems
    mids = {}
    for r in refs:
        if r.ext in ('.mid', '.midi'):
            mids.setdefault(os.path.splitext(r.name)[0], {}).setdefault(r.set, set()).add(r.md5)
    shared_midi = set()
    for stem, d in mids.items():
        if 'freedink' in d and 'original' in d and d['freedink'] & d['original']:
            shared_midi.add(stem + '.ogg')
    md5_index = {}
    for r in refs:
        md5_index.setdefault(r.md5, set()).add(r.set)

    samples = []
    counts = {'FREEDINK': 0, 'ORIGINAL': 0, 'BOTH': 0, 'UNKNOWN': 0}
    for se in sound_entries:
        if se['kind'] == 'import-meta':
            continue
        e = by_path[se['path']]
        blob = read_entry(m, e)
        rec = {'entry': se['path'], 'source_file': se['source'], 'size': se['size'], 'md5': se['md5']}
        stem = os.path.basename(se['source'] or se['path'])
        rec['stem'] = stem
        imp = imports.get((se['source'] or '') + '.import')
        if imp:
            rec['importer'] = imp['importer']
            rec['compress_mode'] = imp['compress_mode']
        if blob is None:
            rec['classification'], rec['evidence'] = 'UNKNOWN', {'reason': 'entry encrypted'}
        elif se['kind'] == 'raw':
            sets = md5_index.get(se['md5'], set())
            lab = 'BOTH' if len(sets) == 2 else (sets and next(iter(sets)).upper()) or 'UNKNOWN'
            rec['classification'], rec['evidence'] = lab, {'basis': 'md5 of raw file vs reference files'}
        else:
            ext = os.path.splitext(se['path'])[1].lower()
            try:
                if ext == '.sample':
                    stream, meta = analyse_wav_resource(blob, K)
                    rec['resource'] = meta
                    lab, ev = classify_sound('wav', blob, meta, stream, stem, refs, shared_midi, K)
                elif ext == '.oggvorbisstr':
                    meta = {}
                    try:
                        res = parse_rsrc(blob)
                        for r_ in res['resources']:
                            pr = r_['props']
                            if 'packet_data' in pr or 'granule_positions' in pr or 'sampling_rate' in pr:
                                gp = pr.get('granule_positions') or [0]
                                meta = {'sampling_rate': pr.get('sampling_rate'), 'granule_length': max(gp),
                                        'pages': len(pr.get('packet_data', [])), 'rsrc_type': res['type']}
                        if res['partial']:
                            meta['rsrc_partial'] = res['partial']
                    except Exception as ex:  # noqa
                        meta = {'rsrc_error': str(ex)}
                    rec['resource'] = meta
                    lab, ev = classify_sound('ogg', blob, meta, None, stem, refs, shared_midi, K)
                else:
                    lab, ev = 'UNKNOWN', {'reason': 'unhandled imported extension ' + ext}
            except Exception as ex:  # noqa
                lab, ev = 'UNKNOWN', {'reason': 'analysis error: %r' % ex}
            rec['classification'], rec['evidence'] = lab, ev
        counts[rec['classification']] = counts.get(rec['classification'], 0) + 1
        samples.append(rec)
        if verbose:
            print('  %-58s %-9s' % (rec['entry'][-58:], rec['classification']), file=sys.stderr)
    out['samples'] = samples
    out['counts'] = counts

    # The game's own sound manifest (a CLAIM about provenance, recorded next to the content verdicts).
    man = by_path.get('res://data/sounds.json')
    if man:
        try:
            out['manifest_data_sounds_json'] = json.loads(read_entry(m, man))
        except Exception as ex:  # noqa
            out['manifest_data_sounds_json'] = {'error': str(ex)}

    if loose_dirs:
        loose = []
        for d in loose_dirs:
            for root, _dirs, files in os.walk(d):
                for fn in sorted(files):
                    if fn.lower().endswith(AUDIO_EXTS):
                        p = os.path.join(root, fn)
                        h = md5_of(p)
                        loose.append({'path': os.path.relpath(p, d), 'md5': h,
                                      'sets': sorted(md5_index.get(h, []))})
        out['loose_audio'] = loose
    return out


def print_summary(out):
    print('== %s' % out['target'])
    print('sha256 %s size %d' % (out['sha256'], out['size']))
    p = out['pck']
    print('PCK start=%d format v%d engine %s flags=%d file_base=%d entries=%d md5_mismatches=%d' % (
        p['start'], p['format_version'], p['engine'], p['flags'], p['file_base'], p['entry_count'],
        len(p['md5_mismatches'])))
    print('sound entries: %d (samples analysed: %d)' % (len(out['sound_entries']), len(out['samples'])))
    print('counts:', out['counts'])
    for s in out['samples']:
        ev = s.get('evidence', {})
        best = ''
        nh = ev.get('name_hinted') or []
        parts = []
        for m in nh:
            sc = m.get('snr_windows') or m.get('packet_windows')
            parts.append('%s:%s%s' % (m['set'][:2], sc, '/bw' + m['byte_windows'] if 'byte_windows' in m else ''))
        best = ' '.join(parts)
        print('  %-22s %-9s %-10s %s' % (s['stem'], s['classification'],
                                         (s.get('resource') or {}).get('format', 'ogg'), best))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('target', nargs='+', help='.pck or Godot export executable(s)')
    ap.add_argument('--freedink', nargs='+', required=True, metavar='DIR')
    ap.add_argument('--original', nargs='+', required=True, metavar='DIR')
    ap.add_argument('--json', help='write JSON here (with several targets: a directory or a '
                                   'path prefix; one file per target)')
    ap.add_argument('--loose', nargs='*', default=[], metavar='DIR')
    ap.add_argument('--windows', type=int, default=8)
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args(argv)
    refs = load_refs({'freedink': a.freedink, 'original': a.original})
    results = []
    for t in a.target:
        out = audit(t, refs, a.windows, a.loose, a.verbose)
        print_summary(out)
        results.append(out)
        if a.json:
            path = a.json
            if len(a.target) > 1:
                path = os.path.join(a.json, os.path.basename(t) + '.json') if os.path.isdir(a.json) \
                    else '%s.%s.json' % (a.json, os.path.basename(t))
            with open(path, 'w') as fh:
                json.dump(out, fh, indent=1, default=str)
    return 0


if __name__ == '__main__':
    sys.exit(main())

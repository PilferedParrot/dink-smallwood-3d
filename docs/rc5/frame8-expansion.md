# Expanded fir-trim class — 2026-10-11

The initial RC5 pack completed tree09/10 while tree08 remained a cropped generic card. The expanded class covers all confirmed fir trim frames8/9/10. Whole tree pictures, sparse natural border fronds and stumps are controls; border contact alone is not a missing-crown diagnosis.

The technical cause was importing a200×95px strip of upper foliage as one complete object at its generic hotspot. The development cause was an oversight: the earlier9/10 inventory became the assumed class definition instead of prompting an all-frame census. The fix completes each source crown with original seq32/frame1 art and one shadow twin, through `SourceFir.at_foot`.

## Source inference

Frame8 has no feet. Its source top-row apexes and periodic side-edge apex provide the following source owners. The original complete fir's measured apex-to-foot displacement is `(2.5,176)` source pixels; each owner keeps uniform scale1.0.

| Part | Source x ownership window | Apex | Inferred foot |
|---:|---|---|---|
| 0 | `[0,20)` | `(1,12)` | `(3.5,188)` |
| 1 | `[20,81)` | `(39.5,0)` | `(42,176)` |
| 2 | `[81,162)` | `(123,0)` | `(125.5,176)` |
| 3 | `[162,200)` | `(201,12)` | `(203.5,188)` |

The boundary feet differ by exactly200px. Adjacent source repeats therefore share one crown. Native ownership prefers an in-screen root, then source screen/editor/part order, using only the actual loaded5×5 block. A source copy regains ownership when its preferred competitor is outside that block. Rounded source-x midplanes partition overlapping foliage for visibility; they are not botanical segmentation.

The central canopy alpha comparison supports roughly full-tree scale: IoU about0.702/0.703 at1.0 versus0.588/0.560 at0.55, with a broad near tie around0.9–1.1. It does not establish exact hidden roots. The inferred feet extend81–93px below the cropped bitmap. Original-picture overlays on208,251 and768 show the sampled feet on painted forest tiles, despite those points often being walkable under original hardness. The lead approved original frame1 hardbox support there subject to topology and interaction gates. That deliberately changes movement inside painted forest; it does not enable a new forest layout or enlarge bodies to the crown proxy.

## Class evidence

There are40 frame8 source placements, including two ground-painted trims, with160 candidate crowns. Of these,139 are shown under full-world ownership and147 source part IDs show somewhere across570 real scene blocks. The fallback count is32 appearances; no scene displays coincident completed frame8 roots within3px. Source part IDs are not unique physical-root counts.

The collision inventory covers163 source placements and406 candidate parts. It authorizes227 unsupported valid roots,135 from frame8 and92 from9/10. Three invalid destinations remain listed: frame8 indoor289/absent737 and frame10 absent798. The92 ordered9/10 records retain SHA256 `967fd001265bc251c672497eee9176e113896d42da07093982bead4b5708652e`.

The all-frame native census finds zero shown partial fir owners. All706 source records outside frames8/9/10 exactly equal the archived initial native census, including visibility and sampled geometry. The live fixture finds four complete firs for768 editor2 and no old cropped card. Mounted against the frozen initial RC5 pack, the same fixture fails those two assertions.

The independent collision mask agrees with599,070 native queries. The expanded topology has652,057 newly occupied formerly reachable pixels relative to RC4 and577,863 disconnected surviving free pixels in21 per-screen components. `docs/DIRECTION.md` lists every component and the lead's acceptance of forest-only cutoffs. Source range, arrival, current native dispatch and packed real-input save evidence are retained separately; none certifies campaign progression or arbitrary saved state.

## Reproduce the all-frame census

Use isolated data/config/cache directories, Dummy audio, `nice -n10`, one rendered Godot at a time and software rendering. These commands are headless; the environment's existing Godot and Python paths may be substituted.

```sh
mkdir -p tmp/rc5-tree-reproduction
export XDG_DATA_HOME="$PWD/tmp/rc5-tree-reproduction/profile/data"
export XDG_CONFIG_HOME="$PWD/tmp/rc5-tree-reproduction/profile/config"
export XDG_CACHE_HOME="$PWD/tmp/rc5-tree-reproduction/profile/cache"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 LP_NUM_THREADS=1
nice -n 10 godot --headless --audio-driver Dummy --path game \
  --script res://../tools/rc5_tree_clip_census.gd -- \
  --out="$PWD/tmp/rc5-tree-reproduction/native.json"
/usr/bin/python3 - <<'PY'
import gzip
from pathlib import Path
Path('tmp/rc5-tree-reproduction/initial-native.json').write_bytes(
    gzip.decompress(Path('docs/rc5/tree-clip-native-8b70efa.json.gz').read_bytes()))
PY
nice -n 10 /usr/bin/python3 tools/rc5_tree_clip_summary.py \
  --native tmp/rc5-tree-reproduction/native.json \
  --out tmp/rc5-tree-reproduction/census.json \
  --summary tmp/rc5-tree-reproduction/summary.txt \
  --require-complete-firs \
  --controls-native tmp/rc5-tree-reproduction/initial-native.json
```

The summary's historical9/10 cross-check reads the tracked archived census by default; `--prior-census` can select another explicit JSON/gzip artifact. It no longer requires an untracked prior probe or native-support file. The retained expanded native/summary artifacts are `tree-native-expanded.json.gz` and `tree-census-expanded.json.gz` in this directory.

Run `tests/test_fps_whole_fir.py`, `tests/test_fps_seams.py` and `tests/test_fps_fir_collision.py` for native constructor, source-control, scene ownership, collision regeneration, invalid-root, escape and visibility checks. The broader suite supplies the exhaustive walker and rendering regressions. Native cleanup warnings are retained in logs; they are distinct from script errors and test assertions.

The forest layout proposal remains held outside the exported project at `tmp/rc5-forest-held/rc5_forest_preview.json`; its fitter and capture harness are uncommitted proposals. Natural crown-entry, ground relief, shores and retained unexplained hardness remain open in the earlier reports.

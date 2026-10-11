# RC5 dispatch and fir-eye audit reproduction

This page documents the retained audit tools and separates two different kinds of evidence: current FPS dispatch against before/after collision-topology masks, and the separately archived south savebot regression against the actual RC4 source code.

## Native current dispatch availability

`rc5_dispatch_candidates.py` creates exact integer-pixel range masks. It reads every input explicitly and no longer imports temporary pocket-audit modules. The formulas retained here are: talk range `<90` source pixels; default fist range as the four cardinal target rectangles from `game/scripts/fps_game.gd::_fps_melee_hit_rect`, including the 0-range 28px lateral extension. The candidate masks are prefilters only; actual facing, physics ray and target selection are evaluated by `rc5_dispatch_census.gd` in Godot.

Generate candidates from the preserved source candidate, integrated ray, broad interactions, and topology-mask artifacts:

```sh
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 LP_NUM_THREADS=4
mkdir -p "$REPO/tmp/rc5-audit-reproduction"
/usr/bin/python3 tools/rc5_dispatch_candidates.py \
  --source tmp/rc5-pocket-audit/ray-candidates.json \
  --rays tmp/rc5-pocket-audit/ray-census-integrated.json \
  --broad tmp/rc5-pocket-audit/interactions.json \
  --masks tmp/rc5-evidence/reach-masks.npz \
  --world game/data/world.json \
  --native tmp/rc5-native-inventory-v2.json \
  --footprints game/data/footprints.json \
  --out "$REPO/tmp/rc5-audit-reproduction/candidates"
```

For a clean rerun that preserves prior evidence, write generated files under a separate reproduction directory rather than over the saved audit. The checked reproduction below uses `tmp/rc5-audit-reproduction/` (create it before running). The prior candidate index and PNGs remain untouched. The preserved candidate census is 579 standing records, with 5,301,887 before and 5,288,453 after eligible pixels. Those are candidate-cell totals, not probe totals. `rc5_dispatch_census.gd` stops positive records at the first true native dispatch witness. A negative record is exhaustive only when `visited_cells == eligible_cells`; bounded runs may stop earlier. The prior native result records 576 witness/witness records and three exhaustive-negative/exhaustive-negative records, with no lost-all result. It visited all 16,023 eligible negative cells per topology state; positive records did not visit every white mask pixel.

The current-dispatch audit loads the current FPS game code in both runs and compares two topology states supplied by `reach-masks.npz`. “Before” and “after” refer to those static collision/reachability masks, not to old versus new game-code revisions. The following commands reproduce a bounded native census, an exhaustive-negative subset census, and the deterministic merge; the exhaustive subset index can be made from the three saved negative rows:

```sh
# Native, current code, before and after masks, first witness or at most 100 cells per record.
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 LP_NUM_THREADS=4
nice -n 10 godot --headless --audio-driver Dummy --path game \
  --script res://../tools/rc5_dispatch_census.gd -- \
  --index="$REPO/tmp/rc5-audit-reproduction/candidates/index.json" \
  --out="$REPO/tmp/rc5-audit-reproduction/postfix-100.json" --limit=100

# Build an exact 3-record index for the known exhaustive negatives.
/usr/bin/python3 - "$REPO" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
source = json.loads((root / "tmp/rc5-audit-reproduction/candidates/index.json").read_text())
negative = json.loads((root / "tmp/rc5-south-dispatch/final-status.json").read_text())
keys = {(r["screen"], r["list_index"], r["mode"])
        for r in negative["records"] if r["before"]["status"] == "EXHAUSTIVE_NO_DISPATCH"}
records = [r for r in source["records"] if (r["screen"], r["list_index"], r["mode"]) in keys]
assert len(records) == 3
out = {**source, "records": records,
       "counts": {"records": 3,
                  "before_cells": sum(r["images"]["before"]["eligible_cells"] for r in records),
                  "after_cells": sum(r["images"]["after"]["eligible_cells"] for r in records)}}
(root / "tmp/rc5-audit-reproduction/candidates/negative-index.json").write_text(json.dumps(out, separators=(",", ":")) + "\n")
PY

# No limit means exhaust each eligible cell for the three negatives.
nice -n 10 godot --headless --audio-driver Dummy --path game \
  --script res://../tools/rc5_dispatch_census.gd -- \
  --index="$REPO/tmp/rc5-audit-reproduction/candidates/negative-index.json" \
  --out="$REPO/tmp/rc5-audit-reproduction/postfix3-exhaustive.json"

/usr/bin/python3 tools/rc5_dispatch_merge.py \
  --bounded tmp/rc5-audit-reproduction/postfix-100.json \
  --exhaustive tmp/rc5-audit-reproduction/postfix3-exhaustive.json \
  --game-script game/scripts/fps_game.gd \
  --candidates tmp/rc5-audit-reproduction/candidates/index.json \
  --out tmp/rc5-audit-reproduction/final-status.json
```

The preserved `tmp/rc5-south-dispatch/final-status.json` retains its original four SHA-256 values. Re-running the corrected candidate tool produces pixel-identical PNG masks and identical counts, but its index JSON has corrected wording clarifying that positives stop at a witness; therefore a new merged report hashes the regenerated index rather than the preserved index. To verify the original merged report bit-for-bit, merge the saved source artifacts: bounded census `ec51975063c609ec028517c9bf3ca6d50154008a723c3beadf9aaee2f85d1de1`, exhaustive census `955795be0d388faedeb3ff799284c8df30130266d76e7a3b62b79abe5f55ba57`, `fps_game.gd` `049c943a839dc7d3797b2d0b9798028d819967cd2ac5a0115a58ddabe014077a`, and candidate index `7376cbfe936f6cb0c9f1689832ddfff0a5e920481ddf4400187bd810c32ca288`.

```sh
/usr/bin/python3 tools/rc5_dispatch_merge.py \
  --bounded tmp/rc5-south-dispatch/postfix-100.json \
  --exhaustive tmp/rc5-south-dispatch/postfix3-exhaustive.json \
  --game-script game/scripts/fps_game.gd \
  --candidates tmp/rc5-south-dispatch/candidates/index.json \
  --out /tmp/rc5-south-dispatch-final-status-recheck.json
```

This is distinct from the south savebot baseline exercise. That separate audit loaded an actual RC4 code archive and compared it with current code at the same scripted input point. It found an own-body ray failure in the RC4 code and successful talk/E dispatch in current code. Do not use that exact south baseline as proof of a worldwide code-version comparison; the worldwide 579-target report is a current-code check over before/after topology masks. Neither audit runs campaign startup scripts or establishes ordinary player progression.

## Fir eye-height source-art census

The native producers and Python analyzer now take explicit output and input paths. Reproduce the existing-tree seam inventory from the repository's Godot project:

```sh
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 LP_NUM_THREADS=4
nice -n 10 godot --headless --audio-driver Dummy --path game \
  --script res://../tools/rc5_existing_tree_inventory.gd -- \
  --out="$REPO/tmp/rc5-audit-reproduction/existing-native.json"
```

If the completed fir inventory needs to be regenerated, use the existing repository-native producer (this is a source/collision inventory, not a renderer):

```sh
nice -n 10 godot --headless --audio-driver Dummy --path game \
  --script res://../tools/rc5_fir_collision_inventory.gd -- \
  --out="$REPO/tmp/rc5-audit-reproduction/completed-firs.json"
```

Then run the deterministic 2D source-pixel eye-height census with explicit artifacts:

```sh
uv run --offline --with numpy --with scipy --with pillow python tools/rc5_fir_eye_census.py \
  --completed tmp/rc5-audit-reproduction/completed-firs.json \
  --existing tmp/rc5-audit-reproduction/existing-native.json \
  --fit game/prototype/rc5_firs.json \
  --world game/data/world.json \
  --masks tmp/rc5-evidence/reach-masks.npz \
  --art-root game/assets/graphics/lands/Trees \
  --out tmp/rc5-audit-reproduction/fir-eye-census.json \
  --baseline-existing tmp/rc5-fir-eye/existing-baseline-native.json
```

The analyzer checks native inventory counts: 570 outdoor scene centers; 165 shown completed fir owners, 79 shown source-tree-02 controls, and 199 shown source-tree-01 controls. The preserved report's totals include 100,397,252 before and 100,212,087 after reachable cells; the completed-fir disk proxy intersects 427,556 before and 262,755 after eye pixels. Its input SHA values are embedded in `tmp/rc5-fir-eye/census.json`; regenerated reports record the explicit paths supplied above.

The disk is a yaw-independent 2D proxy around measured nonblack source-art feet at 1.65m, not a 3D occlusion or eye-level visibility test. Native seam visibility supplies which parts enter the 5×5 scene inventory. Script-created actors, startup behavior, saved vision, camera gaze, rendered alpha and player experience are outside this census. The current audit already identifies crown entry as an open concern; this report does not propose a reconstruction change.

Both sets of audits are bounded data checks. They use headless Godot with Dummy audio, no renderer, and no gameplay save or account state. The report outputs are evidence artifacts, not updated automatically by these tools.

#!/usr/bin/env bash
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Run stages sequentially, after the lead's CPU courtesy hold is released.
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$TASK_ROOT"
STAGE=${1:?stage: fit, parse, export, gates, capture, sheet}
OUT="$TASK_ROOT/tmp/rc5-forest-preview"
PACK="$TASK_ROOT/tmp/rc5-forest-package/DinkSmallwood3D.x86_64"
GODOT=${GODOT:-/home/chris/.local/bin/Godot_v4.6.1-stable_linux.x86_64}
FOREST_PYTHON=${FOREST_PYTHON:-python3}
mkdir -p "$OUT"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 LP_NUM_THREADS=6
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
export XDG_DATA_HOME="$OUT/profile-$STAGE/data"
export XDG_CONFIG_HOME="$OUT/profile-$STAGE/config"
export XDG_CACHE_HOME="$OUT/profile-$STAGE/cache"
unset WAYLAND_DISPLAY
# One check at launch; no background monitoring or polling.
if awk '{exit !($1 > 24)}' /proc/loadavg; then
 echo 'Load1 exceeds 24; defer this stage.' >&2
 exit 75
fi
case "$STAGE" in
 fit)
  nice -n 10 "$FOREST_PYTHON" tools/rc5_forest_preview_fit.py > "$OUT/fit.log"
  nice -n 10 "$FOREST_PYTHON" tools/rc5_forest_preview_views.py \
   --masks tmp/rc5-d2-expanded/reach-masks.npz --out "$OUT/views" > "$OUT/views.log"
  ;;
 parse)
  for SCRIPT in prototype/rc5_forest_preview.gd ../tests/fps_forest_preview_capture.gd ../tests/fps_forest_preview_check.gd; do
   nice -n 10 "$GODOT" --headless --audio-driver Dummy --path game --check-only --script "res://$SCRIPT"
  done
  ;;
 export)
  mkdir -p "$(dirname "$PACK")"
  # Export isolation also relocates template lookup. Reuse installed binaries
  # by a link in our disposable profile; player app_userdata stays isolated.
  mkdir -p "$XDG_DATA_HOME/godot/export_templates"
  if [ ! -e "$XDG_DATA_HOME/godot/export_templates/4.6.1.stable" ]; then
   ln -s "${FOREST_EXPORT_TEMPLATES:-$HOME/.local/share/godot/export_templates}/4.6.1.stable" \
    "$XDG_DATA_HOME/godot/export_templates/4.6.1.stable"
  fi
  test -f "$XDG_DATA_HOME/godot/export_templates/4.6.1.stable/linux_release.x86_64"
  test -f "$XDG_DATA_HOME/godot/export_templates/4.6.1.stable/linux_debug.x86_64"
  nice -n 10 "$GODOT" --headless --audio-driver Dummy --path game --export-release Linux "$PACK"
  sha256sum "$PACK" > "$OUT/package.sha256"
  ;;
 gates)
  nice -n 10 "$GODOT" --headless --audio-driver Dummy --main-pack "$PACK" \
   --script "$TASK_ROOT/tests/fps_forest_preview_check.gd" -- \
   --out="$OUT/gates.json" --views="$OUT/views"
  /usr/bin/python3 - "$OUT/gates.json" <<'PY'
import json,sys
from pathlib import Path
report=json.loads(Path(sys.argv[1]).read_text())
assert not report['failures'],report['failures']
assert [r['screen'] for r in report['records']]==[144,375]
assert all(len(r['variants'])==2 for r in report['records'])
PY
  ;;
 capture)
  for PHASE in before fir floor; do
   SOURCE="$PACK"
   EXTRA=()
   if [ "$PHASE" = before ]; then
    SOURCE="$TASK_ROOT/tmp/rc5-package-2/DinkSmallwood3D.x86_64"
   else
    EXTRA+=(--rc5-forest-preview)
    if [ "$PHASE" = floor ]; then EXTRA+=(--rc5-forest-floor); fi
   fi
   for SCREEN in 144 375; do
    DEST="$OUT/$PHASE/$SCREEN"
    mkdir -p "$DEST"
    # Separate player profile for each packed scene/variant.
    export XDG_DATA_HOME="$DEST/profile/data" XDG_CONFIG_HOME="$DEST/profile/config" XDG_CACHE_HOME="$DEST/profile/cache"
    nice -n 10 timeout 900 xvfb-run -a -s '-screen 0 1280x720x24' \
     "$GODOT" --audio-driver Dummy --resolution 960x540 --main-pack "$SOURCE" \
     --script "$TASK_ROOT/tests/fps_forest_preview_capture.gd" -- --screen="$SCREEN" \
     --scripts=0 --neighbour-seed=20261011 --batch="$OUT/views/$SCREEN.json" --out-dir="$DEST" "${EXTRA[@]}" > "$DEST/run.log" 2>&1
    # Godot may exit 0 after a script parse error; require all named images.
    /usr/bin/python3 - "$OUT/views/$SCREEN.json" "$DEST" <<'PY'
import json,sys
from pathlib import Path
for view in json.loads(Path(sys.argv[1]).read_text()):
 assert (Path(sys.argv[2])/(view['name']+'.png')).is_file(),view['name']
PY
   done
  done
  ;;
 sheet) nice -n 10 "$FOREST_PYTHON" tools/rc5_forest_preview_sheet.py "$OUT" ;;
 *) echo "Unknown stage: $STAGE" >&2; exit 2 ;;
esac

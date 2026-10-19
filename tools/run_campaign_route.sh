#!/usr/bin/env bash
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Run the real-input campaign with silent, isolated software rendering.
# Optional: GODOT=/path/to/editor DINK_CAMPAIGN_PACK=/path/to/export.
# Put long runs in a named systemd user service; this script stays foreground.
set -euo pipefail
TASK_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${DINK_CAMPAIGN_ENGINE:-} == 1 ]]; then
    # PlaytestSession supplies a fresh XDG_DATA_HOME and XDG_CONFIG_HOME.
    # Keep the renderer's cache in that same disposable session profile.
    export XDG_CACHE_HOME="${XDG_DATA_HOME%/data}/cache"
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=4
    unset WAYLAND_DISPLAY
    args=("$@")
    if [[ -n ${DINK_CAMPAIGN_PACK:-} ]]; then
        test -f "$DINK_CAMPAIGN_PACK"
        for ((i = 0; i < ${#args[@]}; i++)); do
            if [[ ${args[i]} == --path ]]; then
                args[i]=--main-pack
                args[i+1]=$DINK_CAMPAIGN_PACK
                break
            fi
        done
    fi
    exec nice -n 10 timeout --kill-after=10s 5400 "$DINK_CAMPAIGN_GODOT" \
        --rendering-method gl_compatibility --resolution 960x540 "${args[@]}"
fi

export DINK_CAMPAIGN_GODOT=${GODOT:-$HOME/.local/bin/Godot_v4.6.1-stable_linux.x86_64}
command -v "$DINK_CAMPAIGN_GODOT" >/dev/null
export DINK_CAMPAIGN_ENGINE=1
export GODOT="$TASK_ROOT/tools/run_campaign_route.sh"
LOCK_DIR=${XDG_STATE_HOME:-$HOME/.local/state}
mkdir -p "$LOCK_DIR"
cd "$TASK_ROOT"
exec flock "$LOCK_DIR/dink-godot.lock" timeout --kill-after=15s 5400 \
    xvfb-run -a -s '-screen 0 1280x720x24' \
    "${PYTHON:-python3}" tools/playtest_campaign.py --rendered "$@"

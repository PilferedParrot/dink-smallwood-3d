#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
dink_godot="${GODOT:-}"
if [[ -z "$dink_godot" ]]; then
  for candidate in godot godot4 "$HOME/.local/bin/Godot_v4.6.1-stable_linux.x86_64"; do
    if command -v "$candidate" >/dev/null 2>&1; then dink_godot="$candidate"; break; fi
  done
fi
if [[ -z "$dink_godot" ]]; then
  echo 'Install Godot 4.6, or set GODOT to its executable path.' >&2
  exit 1
fi
"$dink_godot" --headless --path game --editor --import
exec "$dink_godot" --path game "$@"

# Local bug evidence

Press **F9** during play or in a menu/dialogue. A short notice gives the saved path. The game writes a PNG and paired JSON under its local `user://bug_reports/` folder; on Linux that is normally beneath the game's `~/.local/share/godot/app_userdata/` directory. Nothing is sent automatically. Settings & controls lists the key.

The JSON contains source screen, player coordinates/facing, camera orientation, story globals, current entity/editor/item state, settings, and hashes of the shipped FPS/renderer scripts. It retains up to ten seconds of gameplay keyboard, mouse and controller events in a bounded ring. Menu text, unrelated keys, Unicode text and F9 itself are omitted. A high-rate buffer overflow is reported rather than hidden.

For agent diagnosis, inspect `snapshot` and the paired image first. Restore that final snapshot, or rerun the recorded inputs **from that final state**, using an isolated profile:

```bash
mkdir -p tmp/report-replay/data tmp/report-replay/config
nice -n 10 env XDG_DATA_HOME="$PWD/tmp/report-replay/data" XDG_CONFIG_HOME="$PWD/tmp/report-replay/config" \
  ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 --headless --audio-driver Dummy \
  --path game --script "$PWD/tools/bug_report_replay.gd" -- \
  --report=/absolute/path/report.json --mode=snapshot
```

Use `--mode=inputs` to feed the bounded event sequence through the actual input path. For a rendered view, replace `--headless` with an isolated software-rendered Xvfb launch; retain Dummy audio. `--main-pack /absolute/path/export.x86_64` can replace `--path game` when diagnosing that exact release.

This is diagnostic restoration, not time travel. It does not rewind ten seconds, recover events/held keys before the window, resume pending DinkC tasks, or restore an in-progress modal conversation. Runtime physics, random choices and new screen scripts can diverge. A snapshot can place Dink directly at a reported stuck position without claiming normal progression reached that state.

Native mechanisms reused: [Godot Input](https://docs.godotengine.org/en/4.6/classes/class_input.html) (`parse_input_event` and explicit buffered-event flushing), the project's existing frame-post-draw viewport capture, and save entity restoration. Prior tools inspected: [GodotInputRecorder](https://github.com/bitwes/GodotInputRecorder) and [Testy](https://github.com/hpi-swa-lab/godot-interactive-testing). Their broader recording/test workflows do not supply this project's DinkC state and allowlisted local ten-second report, so no addon or external assets were installed. Historical determinism requires more state than this feature records.

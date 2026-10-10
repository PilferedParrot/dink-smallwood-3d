# Dink Smallwood 3D: playtesting

- Use deterministic local programs for repeatable runs and assertions. Agents may launch the game headless, drive
  inputs, collect telemetry and capture screenshots; pass compact observations and never call a model per
  simulation frame.
- Playtests isolate saves, settings and logs from the player's profile and exercise the real input path. Label any
  setup that skips normal progression or script execution.
- An obstructed direction alone is not a stuck-player bug. Classify each finding as a game failure, a harness
  failure or inconclusive exploration.
- Headless logic checks do not certify rendering or player experience.

# Development and playtesting delegation

For this project, the user's September 7, 2026 instruction overrides the earlier
OpenAI-only delegation policy:

- Astra owns planning, supervision, integration review, and visual judgments.
- Use deterministic local programs for repeatable execution and assertions.
- Use local Qwen for bounded text/state-based tasks when it is competent and
  economical. Use cheaper OpenAI agents for implementation and debugging;
  escalate only when evidence warrants it.
- Workers can launch headless games, drive inputs, collect telemetry, and capture
  rendered screenshots. Send screenshots to Astra for visual interpretation.
- Keep model requests bounded, pass compact observations, and record actual
  model usage. Do not call a model for every simulation frame.
- Verify delegated work in the shared checkout. Preserve existing uncommitted
  work and give concurrent workers separate write scopes.

Playtests must isolate saves/settings/logs from the player's profile. Exercise
the actual input path; label any scenario setup that skips normal progression
or script execution. An obstructed direction alone is not a stuck-player bug.
Distinguish game failures, harness failures, and inconclusive exploration.
Headless logic checks do not certify rendering or player experience.

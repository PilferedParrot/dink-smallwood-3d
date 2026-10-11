# RC5 authored interaction gating reproduction

These retained tools measure static authored interaction ranges and derive small point samples for native probing. They load every source artifact from explicit CLI paths; none imports a temporary audit module or reads source files at import time. `rc5_interactions.py` preserves the source actor eligibility and authored vision checks from the prior pocket audit. `rc5_fps_static.py` approximates line tests on static structure masks. `rc5_ray_candidates.py` creates representative points for later live FPS queries; it does not call Godot or certify a physics ray.

The first validation is against the preserved old topology masks. The expanded tree-trim masks are not yet available; root will rerun these tools against those later. The old-mask rerun reproduced the saved interaction records/statuses exactly and the ray-candidate records/keys exactly. Candidate output is written to a fresh directory so old evidence stays intact.

## Reproduce broad source ranges

From the repository root, run:

```sh
mkdir -p tmp/rc5-interaction-repro
nice -n 10 /usr/bin/python3 tools/rc5_interactions.py \
  --world game/data/world.json \
  --sequences game/data/sequences.json \
  --footprints game/data/footprints.json \
  --native tmp/rc5-native-inventory-v2.json \
  --masks tmp/rc5-evidence/reach-masks.npz \
  --story game/data/story.json \
  --route-audit tmp/rc5-pocket-audit/audit.json \
  --out tmp/rc5-interaction-repro/interactions.json
```

The preserved basis produced 1,522 records: 817 `PASS_RETAINED_REACHABLE_CELLS`, 179 `DYNAMIC_ACTIVATION_UNVERIFIED`, and 526 `PREEXISTING_NO_REACHABLE_CELLS_OR_UNMODELED`. By mode, it had 933 default-fist range records, 379 touch hardbox records, 120 nearest-talk records, and 90 static warp triggers. It retained 80 excluded authored-layer entries and 3 other-vision warp entries as unverified. New output records are semantically identical to the saved `tmp/rc5-pocket-audit/interactions.json` except the explicit mask path metadata.

The source eligibility logic keeps only vision-0, non-type-2 entries in the active actor inventory. Talk requires an authored TALK procedure on a standing type-1 source; hit eligibility comes from authored HIT, known NPC source keys, selected authored brains, or touch damage. Runtime-only touch activation stays `DYNAMIC_ACTIVATION_UNVERIFIED`. Other authored vision layers and their warps are preserved separately as unverified; they are not silently treated as active standing actors.

## Reproduce FPS static line candidates

This is the optional 5-pixel source-structure approximation. It does not use actual FPS physics rays or live nearest-target selection. A bounded screen smoke check for the savebot scene is:

```sh
nice -n 10 /usr/bin/python3 tools/rc5_fps_static.py \
  --broad tmp/rc5-interaction-repro/interactions.json \
  --masks tmp/rc5-evidence/reach-masks.npz \
  --world game/data/world.json \
  --native tmp/rc5-native-inventory-v2.json \
  --footprints game/data/footprints.json \
  --walls game/prototype/rc5_walls.json \
  --firs game/prototype/rc5_fir_collision.json \
  --out tmp/rc5-interaction-repro/fps-static-screen768.json \
  --screen 768
```

Omit `--screen 768` for the all-screen 1,053-record static approximation. For the preserved old inputs, screen 768's two savebot records exactly match the prior `fps-static.json`. The full previous static report had 120 talk and 933 melee candidate records, with zero loss-all static-cone/line failures.

## Reproduce native ray candidate points

The ray candidate step samples directions/distances from reachable talk/melee ranges after the approximate structure-line filter. The next stage is the separate bounded Godot dispatch census. Run:

```sh
nice -n 10 /usr/bin/python3 tools/rc5_ray_candidates.py \
  --broad tmp/rc5-interaction-repro/interactions.json \
  --masks tmp/rc5-evidence/reach-masks.npz \
  --world game/data/world.json \
  --native tmp/rc5-native-inventory-v2.json \
  --footprints game/data/footprints.json \
  --walls game/prototype/rc5_walls.json \
  --firs game/prototype/rc5_fir_collision.json \
  --out tmp/rc5-interaction-repro/ray-candidates.json
```

Old-mask validation reconciles exactly: **817** broad positive interaction records, **579** standing talk/hit targets, **129** positive type-0/nonstanding talk/hit records excluded from FPS targets, and **109** trigger-only positive records excluded from ray targets (73 warp + 36 touch). Candidate keys and all 579 records equal the preserved `tmp/rc5-pocket-audit/ray-candidates.json`; both before and after had a representative candidate for all 579 standing targets. This tool calculates source points only; it performs no live ray probes.

## Input provenance at this validation snapshot

The core game code is being changed separately, so these hashes document the exact source snapshot used for the old-mask validation. They are provenance, not an assertion that future code should retain them.

| Input | SHA-256 |
|---|---|
| `game/data/world.json` | `3e643839d6c287f757d9a65ccd773f1d4313de645ab944c54700e1a88a011be1` |
| `game/data/sequences.json` | `d2411618230e43d13edb1e9b58fa54211317486b862614127ca0d999a9ccc0de` |
| `game/data/footprints.json` | `dfe1548b35112dc67dc39ff8e5f679b30a7548e23e6046022ff4e4073eab33a1` |
| `game/data/story.json` | `08eec8d97ff5eb44a5a74e98650b655970c100fee1af302ce0c8038480a15a45` |
| `tmp/rc5-native-inventory-v2.json` | `8c1089c45043e35f5192d018e85de83bcabb2a6ca28a29d0a6aa85125920d329` |
| `tmp/rc5-evidence/reach-masks.npz` | `f8e59eb2b32ff522f8686dac6104fa7fbfdc8338ed0a7b220c2d023c19e85c61` |
| `tmp/rc5-pocket-audit/audit.json` | `b53c43047ef374d1c58ca74f1f9c0ed825d3bd9647180290a59c24fbded6c791` |
| `game/prototype/rc5_walls.json` | `1b670ffb3171e6a18e578f548284a1e1f4612a702b9ab79e8bcae65ff27779bf` |
| `game/prototype/rc5_fir_collision.json` | `0370a73be9d82e33d0bf23b32759c08e91e86da898b79812b2928430d81184d9` |
| `game/scripts/game.gd` at audit start | `5d1eeb7ff9673a6eb2476833f89ac8e380d7744be4516bec81f1c5af2854931e` |
| `game/scripts/fps_game.gd` at audit start | `049c943a839dc7d3797b2d0b9798028d819967cd2ac5a0115a58ddabe014077a` |
| Original temporary `interactions.py` | `ffb9c41ffc5f2a65f2c99ec6dbda54f165778080762d937048fa1f40352dd151` |
| Original temporary `fps_static.py` | `ee9a196fa61e3a2518a47f57f2dab2c900ec8658ee0004dccfab53b9d1f3535f` |
| Original temporary `ray_candidates.py` | `5b3d5b72884d274766aeaf5cdb4ef72b78da3e01f2f933d4bf6031569c7cabe3` |

These are static source-range instruments over the preserved old masks, not a campaign playthrough, an actual player gaze test, or proof of current live physics-ray reach. Use the separate `rc5_dispatch_census.gd` for native dispatch witnesses and exhaustive negative records.

# RC5 surviving-free cutoff audit

`tools/rc5_cutoff_audit.py` inventories every 4-connected outdoor component satisfying:

```text
before_reachable AND NOT after_reachable AND NOT after_hard
```

Each screen is analyzed in its own 400×600 logical playfield block. This keeps screen edges distinct and prevents row wrapping. The output records exact source-coordinate runs, source sprite origins and hardboxes, authored type/vision/touch/warp/script/item fields, art overlap, static and raw warp evidence, edge candidates, and paired literal story arrivals. Inputs and hashes are explicit; the tool does not import a temporary census module.

## Reproduction

```sh
mkdir -p tmp/rc5-cutoff-repro
nice -n 10 /usr/bin/python3 tools/rc5_cutoff_audit.py \
  --masks tmp/rc5-evidence/reach-masks.npz \
  --world game/data/world.json \
  --native tmp/rc5-native-inventory-v2.json \
  --sequences game/data/sequences.json \
  --story game/data/story.json \
  --routes tmp/rc5-story-routes/routes.json \
  --out tmp/rc5-cutoff-repro/report.json
```

The world file location determines the game asset root used for source-art checks. Exact source alpha overlap is reported only for unit scale and integer placement; otherwise the report marks image-bound intersections as candidates and leaves exact alpha counts null.

## Old-mask check

On the preserved `tmp/rc5-evidence/reach-masks.npz`, the tool found exactly two surviving-free components on screen 768:

| Component | Pixels | Source bbox `[x0,y0,x1,y1)` |
|---|---:|---|
| Left | 1,872 | `[220,102,259,150)` |
| Right | 1,564 | `[386,104,420,150)` |

The report found zero source-anchor, source-hardbox, actual touch/warp, native static warp trigger/destination, raw warp source/destination, playfield-edge, FPS transition-edge, or literal-story arrival hits for either component. Each component has one exact source-alpha overlap and one broad 90px talk-range candidate; neither is a gameplay or arrival hit. Each has one grown-four-pixel hardbox candidate, which is a geometric comparison only. Neither component touches the screen edge. The route inventory has 19 paired literal `player_map` routes and none arrives in these components. New-game `(screen 1, [334,161])` also hits none. Saved position/vision, screen startup scripts, dynamic map expressions, and gameplay input remain unverified.

This preserves the important distinction between visual overlap, source origins, hardbox candidates, actual authored touch/warp fields, script/item content, and arrival routes. An alpha-pixel overlap by itself is not evidence that the player can collide with or enter the object. The component findings have a separate `gameplay_or_arrival_candidate_total`; broad talk candidates and image alpha remain outside that total.

## Input hashes for the old-mask check

| Input | SHA-256 |
|---|---|
| `tmp/rc5-evidence/reach-masks.npz` | `f8e59eb2b32ff522f8686dac6104fa7fbfdc8338ed0a7b220c2d023c19e85c61` |
| `game/data/world.json` | `3e643839d6c287f757d9a65ccd773f1d4313de645ab944c54700e1a88a011be1` |
| `tmp/rc5-native-inventory-v2.json` | `8c1089c45043e35f5192d018e85de83bcabb2a6ca28a29d0a6aa85125920d329` |
| `game/data/sequences.json` | `d2411618230e43d13edb1e9b58fa54211317486b862614127ca0d999a9ccc0de` |
| `game/data/story.json` | `08eec8d97ff5eb44a5a74e98650b655970c100fee1af302ce0c8038480a15a45` |
| `tmp/rc5-story-routes/routes.json` | `7c948c486d4bde885253c292736cf3754cb7abe17eeff199d026f81294d4537d` |

The same command can consume the expanded-mask artifact when root generates it. This is a static arrival/content audit, not a gameplay test or a rendering test.

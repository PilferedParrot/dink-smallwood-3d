# Dink Smallwood 3D 0.3.2 candidate (work in progress)

This local release candidate corrects outdoor screen crossings, the house arrival,
original melee reach, script-created actors, and repeated equipment text. Dink now
casts a shadow from his original animated body. F9 saves a local screenshot and
state/input report for diagnosing a reported problem.

Dialogue frames the speaking actor above the measured card. Timed and blocking
speech share the same named card while retaining their original script timing.
Equipment shows one pair of HUD icons; the inventory distinguishes equipped items
from the selected slot. Reports identify this candidate as 0.3.2.

## Known issues

- Half trees and invisible forest/wall hardness remain unresolved. The crossing
  survey found no zero-motion traps in its startup fixtures; it does not prove
  that every campaign position is safe.
- Dink has a body shadow, but no visible torso or legs when looking down. The
  fist and bow still need visual work.
- The grief scene preserves the player's camera after a bounded automatic scene
  framing experiment failed its rendered check. The original death picture is
  painted on the floor, but is not guaranteed visible during dialogue. Original
  freezing and scripted movement remain, so the player cannot freely walk around
  during that beat.
- The interface panels, coarse textures, low ceiling and some prop surface
  mappings remain work in progress. Broken-barrel debris remains flat art.
- Reduced-motion dialogue keeps the eye position; some obstructed speakers may
  have no complete view above the card from that position.
- Timed speech leaves gameplay running, but its bottom card can cover the upper
  status bar until the line expires.
- F9 replay begins from the reported final state and does not reconstruct pending
  scripts or rewind the previous ten seconds.

No installation or publication is part of this candidate's local verification.

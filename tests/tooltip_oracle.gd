# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
## A pointer tooltip earns its place only if it adds meaning, hides nothing the player
## is reading, and stays inside the panel that owns the hovered control.
static func normal(text: String) -> String:
 var cleaned := text.to_lower().replace("selected:", "").replace(" ", " ").replace("·", " ")
 return " ".join(cleaned.split(" ", false)).strip_edges()

# Tooltip lines already said by a visible text.
static func duplicates(tooltip: String, visible_texts: Array[String]) -> Array[String]:
 var found: Array[String] = []
 for line in tooltip.split("\n", false):
  var wanted := normal(line)
  if wanted.is_empty(): continue
  for shown in visible_texts:
   if normal(shown).contains(wanted):
    found.append(line)
    break
 return found

# Rects of the underlying things the player is reading that the popup covers.
static func occluded(popup: Rect2, covered: Array[Rect2]) -> Array[Rect2]:
 var found: Array[Rect2] = []
 for rect in covered:
  if popup.grow(-1).intersects(rect.grow(-1)): found.append(rect)
 return found

static func outside(popup: Rect2, owner_panel: Rect2) -> bool:
 return not owner_panel.grow(1).encloses(popup)

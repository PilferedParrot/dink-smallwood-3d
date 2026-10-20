# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
## No partial text line or control at either edge of a scroll viewport. Atoms are the
## lines of every visible Label, and every other visible leaf control whole (a button,
## a slider, a chest slot). An atom taller than the viewport scrolls natively.
static func atoms(node: Node, found: Array[Dictionary]) -> void:
 var children: Array[Control] = []
 for child in node.get_children():
  if child is Control and child.visible: children.append(child)
 if node is Label and not node.text.is_empty():
  var pitch := float(node.get_line_height()) + float(node.get_theme_constant("line_spacing"))
  var rect: Rect2 = node.get_global_rect()
  var lines: int = maxi(1, node.get_line_count())
  for line in lines:
   found.append({"rect": Rect2(rect.position.x, rect.position.y + line * pitch, rect.size.x, minf(pitch, rect.size.y - line * pitch)), "what": "line %d of \"%s\"" % [line + 1, node.text.left(40)]})
 elif children.is_empty() and node is Control and node.get_global_rect().size.y > 0:
  found.append({"rect": node.get_global_rect(), "what": "%s %s" % [node.get_class(), str(node.get("text")) if node is Button else str(node.name)]})
 for child in children: atoms(child, found)

static func cuts(scroll: ScrollContainer) -> Array[String]:
 var found: Array[Dictionary] = []
 atoms(scroll.get_child(0), found)
 var area: Rect2 = scroll.get_global_rect()
 var report: Array[String] = []
 for atom in found:
  var rect: Rect2 = atom.rect
  if rect.size.y > area.size.y + 1 or rect.intersection(area).size.y <= 1: continue
  if not area.grow(1).encloses(rect): report.append(atom.what)
 return report

# Empty space left under the viewport that the next whole atom would have fitted in.
static func waste(scroll: ScrollContainer, free: float) -> float:
 var found: Array[Dictionary] = []
 atoms(scroll.get_child(0), found)
 var edge: float = scroll.get_global_rect().end.y
 var next: Variant = null
 for atom in found:
  var rect: Rect2 = atom.rect
  if rect.position.y >= edge - 1.0 and (next == null or rect.position.y < next.rect.position.y): next = atom
 if next == null: return 0.0
 return free if next.rect.end.y <= edge + free + 0.5 else 0.0

# Atoms visible at all: a collapsed viewport must not pass by showing nothing.
static func shown(scroll: ScrollContainer) -> int:
 var found: Array[Dictionary] = []
 atoms(scroll.get_child(0), found)
 var count := 0
 for atom in found:
  if scroll.get_global_rect().grow(1).encloses(atom.rect): count += 1
 return count

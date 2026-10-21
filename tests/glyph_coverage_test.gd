# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## Every authored non-ASCII character in the shipped scripts and data, every printable
## ASCII character, and every computed key/pad label must be drawn from a bundled font.
const ORACLE = preload("glyph_oracle.gd")
const BINDINGS = preload("res://scripts/input_bindings.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
 if not ok:
  failures.append(message)
  push_error(message)

func files(dir: String, extension: String, result: Array[String]) -> void:
 for name in DirAccess.get_directories_at(dir):
  if name != ".godot": files(dir.path_join(name), extension, result)
 for name in DirAccess.get_files_at(dir):
  if name.get_extension() == extension: result.append(dir.path_join(name))

func calibrate() -> void:
 var fonts := ORACLE.fonts()
 for name in fonts:
  check(ORACLE.missing(fonts[name], "Health é · • … – − × °").is_empty(), name + ": covered look-alike text is accepted")
  check(fonts[name].has_char(0xA0), name + ": the no-break space that binds key phrases has a glyph")
  check(ORACLE.missing(fonts[name], "go \u2197").size() == 1, name + ": a glyph no shipped font carries is rejected")
  check(ORACLE.missing(fonts[name], "▶◀").size() == 2, name + ": both pager triangles are rejected")

# A player's own layout can name a key in a script neither bundled font carries (Cyrillic
# here). That label may use the system fallback: it is the player's data, not authored text.
# Machine-dependent by nature, so it skips (and says so) when no installed font has it.
func fallback_row() -> void:
 var sample := "\u0416"
 var plain: FontFile = ORACLE.PLAIN
 check(not plain.has_char(0x416), "plain font itself lacks the Cyrillic sample (so only a fallback can draw it)")
 var strict := FontFile.new()
 strict.data = plain.data
 strict.allow_system_fallback = false
 var strict_line := TextLine.new()
 strict_line.add_string(sample, strict, 24)
 var open_line := TextLine.new()
 open_line.add_string(sample, plain, 24)
 var strict_missing := glyph_missing(strict_line)
 check(strict_missing, "look-alike: with system fallback off the sample has no glyph")
 if OS.get_system_fonts().is_empty():
  print("GLYPH FALLBACK ROW SKIPPED: no installed system fonts on this machine")
  return
 var drawn := not glyph_missing(open_line)
 print("GLYPH FALLBACK ROW ", "renders through the system fallback" if drawn else "no installed font carries it (tofu on this machine)")
 check(drawn, "a non-Latin key label renders through the system fallback, not as tofu")

func glyph_missing(line: TextLine) -> bool:
 for glyph in TextServerManager.get_primary_interface().shaped_text_get_glyphs(line.get_rid()):
  # A glyph the shaper cannot find is drawn as a hex box: no font owns it.
  if glyph.get("font_rid", RID()) == RID(): return true
 return false

func run() -> void:
 calibrate()
 fallback_row()
 var fonts := ORACLE.fonts()
 var printable := ""
 for code in range(33, 127): printable += char(code)
 var used := {}
 var sources: Array[String] = []
 files("res://", "gd", sources)
 files("res://data", "json", sources)
 for path in sources:
  var text := FileAccess.get_file_as_string(path)
  for i in text.length():
   if text.unicode_at(i) > 126 and not used.has(text[i]): used[text[i]] = path
 var computed := ""
 # Computed player-facing key names: ASCII keys and every special key (bit 22); other printable keys are the player's own layout, outside authored text.
 for code in range(32, 127): computed += BINDINGS.key_display_name(code)
 for code in range(0x400000, 0x400000 + 0x200):
  # Unassigned codes name U+FFFD; no keyboard produces them.
  if not OS.get_keycode_string(code).contains("\uFFFD"): computed += BINDINGS.key_display_name(code)
 for character in computed:
  if character.unicode_at(0) > 126 and not used.has(character): used[character] = "BINDINGS.key_display_name"
 for name in fonts:
  check(ORACLE.missing(fonts[name], printable).is_empty(), name + ": printable ASCII is covered")
  for character in used:
   var absent: PackedStringArray = ORACLE.missing(fonts[name], character)
   check(absent.is_empty(), ORACLE.describe(character, name, absent) + " (authored in " + str(used[character]) + ")")
 print("GLYPH SOURCES ", sources.size(), " authored non-ASCII ", used.size())
 print("GLYPH COVERAGE PASS" if failures.is_empty() else "GLYPH COVERAGE FAIL " + str(failures.size()))
 quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
 run.call_deferred()

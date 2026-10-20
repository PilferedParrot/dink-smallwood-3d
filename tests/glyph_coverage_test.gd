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

func run() -> void:
 calibrate()
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

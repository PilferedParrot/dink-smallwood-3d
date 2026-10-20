# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
## Machine-independent glyph coverage: FontFile.has_char reads only the font's own
## tables, never an installed system font, so a clean machine draws what this reports.
const PLAIN = preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")

static func missing(font: Font, text: String) -> PackedStringArray:
 var found := PackedStringArray()
 for i in text.length():
  var code := text.unicode_at(i)
  if code <= 32 or code == 0xA0: continue
  if not font.has_char(code) and not found.has(text[i]): found.append(text[i])
 return found

static func fonts() -> Dictionary:
 return {"default": ThemeDB.fallback_font, "plain": PLAIN}

static func describe(text: String, font_name: String, absent: PackedStringArray) -> String:
 var codes: PackedStringArray = []
 for c in absent: codes.append("U+%04X" % c.unicode_at(0))
 return "%s font lacks %s in \"%s\"" % [font_name, ", ".join(codes), text.left(60)]

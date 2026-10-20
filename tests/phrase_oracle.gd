# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
## Phrase-atomic wrapping: a key and its action ("Page Down  Read prompt") are one
## phrase. Phrases are separated by newlines, " · " or three or more spaces; a phrase
## may only be split when it is wider than the whole line on its own.
static func paragraph(label: Label) -> TextParagraph:
 var text := TextParagraph.new()
 text.width = label.size.x
 text.alignment = label.horizontal_alignment
 text.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE | TextServer.BREAK_TRIM_EDGE_SPACES
 text.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
 return text

static func line_of(text: TextParagraph, index: int) -> int:
 for line in text.get_line_count():
  var span := text.get_line_range(line)
  if index >= span.x and index < span.y: return line
 return -1

static func phrases(text: String) -> Array[String]:
 var expression := RegEx.create_from_string(" {3,}|\n| · ")
 var found: Array[String] = []
 var from := 0
 for hit in expression.search_all(text):
  found.append(text.substr(from, hit.get_start() - from))
  from = hit.get_end()
 found.append(text.substr(from))
 return found

static func split_phrases(label: Label) -> Array[String]:
 var found: Array[String] = []
 if label.text.is_empty() or label.size.x <= 0: return found
 var shaped := paragraph(label)
 var font := label.get_theme_font("font")
 var font_size := label.get_theme_font_size("font_size")
 var cursor := 0
 for phrase in phrases(label.text):
  if phrase.strip_edges().is_empty(): continue
  var start := label.text.find(phrase, cursor)
  cursor = start + phrase.length()
  var whole_width := font.get_string_size(phrase, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
  if whole_width > label.size.x: continue
  if line_of(shaped, start) != line_of(shaped, start + phrase.length() - 1): found.append(phrase)
 return found

# The reconstructed paragraph must agree with the label's own wrapping.
static func agrees(label: Label) -> bool:
 return paragraph(label).get_line_count() == label.get_line_count()

# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
## Independent geometry oracle: actual viewport/chrome, native full-line metrics.
## 35% remains the normal maximum; large text may require more pinned chrome. The card is sized to whole
## lines, to the NEAREST line edge (RULE.md, round 2), so it may pass the cap by up to half an atom per
## scroll area (`allowance`): half a prompt line, half a prose line or half the focused answer.
static func allowance(ui) -> float:
 var slack := 0.0
 if ui.choice_prompt_scroll.visible:
  slack += (float(ui.choice_prompt.get_line_height()) + ui.choice_prompt.get_theme_constant("line_spacing")) / 2.0
 if ui.column.get_child_count() > 0:
  if ui.dialogue_mode and not ui.dialogue_continue.visible:
   var focus: Control = ui.get_viewport().gui_get_focus_owner()
   if focus == null or not ui.column.is_ancestor_of(focus): focus = ui.column.get_child(0)
   slack += focus.get_combined_minimum_size().y / 2.0
  elif ui.column.get_child(0) is Label:
   var label: Label = ui.column.get_child(0)
   slack += (float(label.get_line_height()) + label.get_theme_constant("line_spacing")) / 2.0
 return slack
static func defects(ui) -> Array[String]:
 var errors: Array[String] = []
 # Chrome is what the card holds besides the SLOTS of its scroll areas: an empty strip under a fitted viewport
 # is not chrome, it is padding the card must not carry.
 var fixed: float = ui.panel.size.y - ui.menu_box.size.y
 var ideal := 0.0
 var floor_height := 0.0
 var viewport: float = ui.menu_scroll.size.y
 if ui.choice_prompt_scroll.visible:
  fixed -= ui.choice_prompt_box.size.y
  var focus: Control = ui.get_viewport().gui_get_focus_owner()
  if focus == null or not ui.column.is_ancestor_of(focus): focus = ui.column.get_child(0)
  var line := float(ui.choice_prompt.get_line_height())
  ideal = line + focus.get_combined_minimum_size().y
  floor_height = ideal
  viewport += ui.choice_prompt_scroll.size.y
  if ui.choice_prompt_scroll.size.y+1 < line: errors.append("Choice prompt has no whole readable line")
  if ui.menu_scroll.size.y+1 < focus.size.y: errors.append("Focused answer cannot be read whole")
 elif ui.dialogue_mode and not ui.dialogue_continue.visible and ui.column.get_child_count()>0:
  var focus: Control = ui.get_viewport().gui_get_focus_owner()
  if focus == null or not ui.column.is_ancestor_of(focus): focus = ui.column.get_child(0)
  floor_height = focus.get_combined_minimum_size().y
  ideal = floor_height
  if viewport+1 < focus.size.y: errors.append("Prompt-free focused answer cannot be read whole")
 elif ui.column.get_child_count()>0 and ui.column.get_child(0) is Label:
  var label: Label = ui.column.get_child(0)
  floor_height = label.get_line_height()
  ideal = minf(label.get_combined_minimum_size().y, label.get_line_height()*2+label.get_theme_constant("line_spacing"))
 if viewport+1 < floor_height: errors.append("Speech viewport cannot show one whole line")
 var bottom: float = ui.status_dock.readout_top()-ui.column.get_theme_constant("separation")
 var available: float = bottom-ui.column.get_theme_constant("separation")
 if available+1 >= fixed+ideal and viewport+1 < ideal: errors.append("Speech should show two body lines (or prompt plus answer) where space allows")
 if ui.panel.size.y > maxf(ui.root.size.y*0.35 + allowance(ui), fixed+ideal)+1: errors.append("Card exceeds35% without a native reading minimum requiring it")
 return errors

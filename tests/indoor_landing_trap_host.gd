# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends "res://../tests/collision_survey_host.gd"
# Labelled negative instrument fixture: source117's north boundary is cleared,
# incoming solidity is bypassed, then arrival on indoor85 blocks EVERY move.
# This proves the survey sees a trap after an admitted indoor crossing. It is
# not a physical-data finding or an earned campaign setup.
var injected_trap := false

func load_map(number: int, run_scripts: bool = true) -> void:
	super.load_map(number,run_scripts)
	injected_trap = bool(world.screens[str(number)].get("indoor",false))

func _blocked(pos: Vector2, mover: int, from: Vector2 = Vector2.INF) -> bool:
	if injected_trap: return true
	if current_screen == 117 and pos.y <= 1.0: return false
	return super._blocked(pos,mover,from)

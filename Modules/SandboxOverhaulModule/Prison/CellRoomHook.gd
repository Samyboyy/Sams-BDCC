extends Node

# The receiver of a cell room's onPreEnter signal. It is a node of the map so it lives and dies with it, and because Godot calls a signal's receivers in the order of their
# object IDs, a node created after the map runs after the map's own scripts: the vanilla cell rooms set their name and description first, and this overrides them.

var module = null

func onCellRoomPreEnter(room) -> void:
	if(module != null):
		module.onCellRoomPreEnter(room)

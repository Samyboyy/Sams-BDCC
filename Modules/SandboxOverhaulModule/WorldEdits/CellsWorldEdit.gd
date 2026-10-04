extends WorldEditBase

# Adds the cell directory to the cell block halls and "Cell info" to the player's own cell, using the existing RoomAction buttons,
# without editing the map scene. Safe to apply any number of times.

const ActionScript = preload("res://Modules/SandboxOverhaulModule/WorldEdits/CellDirectoryAction.gd")
const ACTION_NAME = "SandboxCellAction"

const HALLS = ["cellblock_orange_nearcell", "cellblock_red_nearcell", "cellblock_lilac_nearcell"]
const PLAYER_CELLS = ["cellblock_orange_playercell", "cellblock_red_playercell", "cellblock_pink_playercell"]

func _init():
	id = "SandboxCellsWorldEdit"

func apply(world: GameWorld):
	for roomID in HALLS:
		addAction(world, roomID, "Cell directory", "See who lives in each cell of this block", false)
	for roomID in PLAYER_CELLS:
		addAction(world, roomID, "Cell info", "Your cell and your cellmate", true)

func addAction(world, roomID:String, actionName:String, tooltip:String, onlyInPlayerCell:bool):
	var room = world.getRoomByID(roomID)
	if(room == null || room.get_node_or_null(ACTION_NAME) != null):
		return
	var action = ActionScript.new()
	action.name = ACTION_NAME
	action.ActionName = actionName
	action.ActionTooltip = tooltip
	action.ActionScene = "CellDirectoryScene"
	action.onlyInPlayerCell = onlyInPlayerCell
	room.add_child(action)

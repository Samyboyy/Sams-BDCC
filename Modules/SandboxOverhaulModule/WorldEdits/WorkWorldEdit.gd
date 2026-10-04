extends WorldEditBase

# Adds the job board (canteen), "Start shift" (the workplaces) and "Cell upgrades" (the player's cell) as RoomAction buttons,
# without editing the map scenes. Safe to apply any number of times.

const ActionScript = preload("res://Modules/SandboxOverhaulModule/WorldEdits/WorkAction.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

const BOARD_ROOM = "hall_canteen"
const PLAYER_CELLS = ["cellblock_orange_playercell", "cellblock_red_playercell", "cellblock_pink_playercell"]

func _init():
	id = "SandboxWorkWorldEdit"

func apply(world: GameWorld):
	applyAll(world)

# The edit itself, untyped so tests can pass a stand-in for the world.
func applyAll(world):
	addAction(world, BOARD_ROOM, "SandboxJobBoard", "board", "Job board", "See which prison jobs are open and manage yours", "JobBoardScene")
	for jobID in EmploymentScript.JOB_ORDER:
		addAction(world, EmploymentScript.JOBS[jobID]["room"], "SandboxStartShift", "shift", "Start shift", "Start your work shift here", "WorkShiftScene")
	for roomID in PLAYER_CELLS:
		addAction(world, roomID, "SandboxCellUpgrades", "upgrades", "Cell upgrades", "Storage, a hidden compartment and better bedding for your cell", "CellUpgradesScene")

func addAction(world, roomID:String, nodeName:String, kind:String, actionName:String, tooltip:String, scene:String):
	var room = world.getRoomByID(roomID)
	if(room == null || room.get_node_or_null(nodeName) != null):
		return
	var action = ActionScript.new()
	action.name = nodeName
	action.kind = kind
	action.ActionName = actionName
	action.ActionTooltip = tooltip
	action.ActionScene = scene
	room.add_child(action)

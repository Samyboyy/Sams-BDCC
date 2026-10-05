extends WorldEditBase

# Puts the physical cells on the Cellblock map (see Prison/CellRooms.gd): every cell is a real room with its own ID, a number and a colour. Runs at the start of
# every game and after every load; rooms that exist are skipped, so applying it again changes nothing. While the game runs the module adds rooms as the prison grows.

func _init():
	id = "SandboxCellsWorldEdit"

func apply(world: GameWorld):
	applyAll(world)

# The edit itself, untyped so tests can pass a stand-in for the world.
func applyAll(world):
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module != null):
		var _added:Array = module.ensureCellRooms(world, false)

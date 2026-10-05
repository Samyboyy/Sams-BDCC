extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/CellRoutesBootTest.tscn
# Every generated cell on the REAL World (the one the game plays on, after the world edit and the world's own transitions): it must have a real route in the navigation graph that
# players and NPCs use to its block's hall, to the cellblock entrance and to a shared prison room, a drawn connection that matches the real one, no overlapping rooms, and no
# room that is drawn but missing from the route graph. Tested for the start-up path (rooms built before the map's transitions) and for the growth path (rooms added to a running map).

const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const RoomsScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellRooms.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		if(failures < 40):
			print("FAIL: " + msg)

func newWorld():
	var ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	return GM.world

# Connection lines of a world: {"floor:x,y" + "e" or "s": true}. A line "e" joins the room at x,y with its east neighbour, "s" with its south neighbour.
func drawnLinks(world) -> Dictionary:
	var links = {}
	for floorID in world.cells:
		for pos in world.cells[floorID]:
			var room = world.cells[floorID][pos]
			for child in room.get_children():
				if(child.filename == "res://Game/World/RoomConnection.tscn"):
					var horizontal = int(round(child.rotation_degrees)) == 0
					var cell = Vector2(floor(child.global_position.x / world.gridsize), floor(child.global_position.y / world.gridsize))
					links[floorID + ":" + str(int(cell.x)) + "," + str(int(cell.y)) + ("e" if horizontal else "s")] = true
	return links

func countRooms(node) -> int:
	var total = 0
	for child in node.get_children():
		if(child.is_queued_for_deletion()):
			continue
		if(child.has_method("getCell") and child.get("roomID") != null):
			total += 1
		total += countRooms(child)
	return total

func judge(world, counts, label):
	var floorID = RoomsScript.floorOf(world)
	var entrance = "cellblock_nearcells"
	check(world.hasRoomID(entrance) and world.hasRoomID("hall_canteen"), label + ": the map has the entrance and a shared room")
	var rooms = world.cells[floorID]
	var nodes = countRooms(world.floorDict[floorID])
	check(nodes == rooms.size(), label + ": no room overlaps another (" + str(nodes) + " room nodes, " + str(rooms.size()) + " places)")
	var links = drawnLinks(world)
	var reachedAll = 0
	var cellRooms = 0
	var dirs = [GameWorld.Direction.WEST, GameWorld.Direction.NORTH, GameWorld.Direction.EAST, GameWorld.Direction.SOUTH]
	for block in LayoutScript.BLOCKS:
		var hall = LayoutScript.HALL_ROOMS[block]
		for cell in range(1, int(counts[block]) + 1):
			var id = LayoutScript.roomID(block, cell)
			check(world.hasRoomID(id), label + ": " + id + " exists on the real map")
			if(!world.hasRoomID(id)):
				continue
			cellRooms += 1
			var toHall = world.calculatePath(id, hall)
			var fromHall = world.calculatePath(hall, id)
			var toEntrance = world.calculatePath(id, entrance)
			var fromEntrance = world.calculatePath(entrance, id)
			var toShared = world.calculatePath(id, "hall_canteen")
			var okRoute = toHall.size() >= 2 and fromHall.size() >= 2 and toEntrance.size() >= 2 and fromEntrance.size() >= 2 and toShared.size() >= 2
			if(okRoute):
				okRoute = toHall[0] == id and fromHall[fromHall.size() - 1] == id and toEntrance[toEntrance.size() - 1] == entrance
			check(okRoute, label + ": " + id + " has a real route to its hall, the entrance and the canteen, and back")
			if(okRoute):
				reachedAll += 1
			var room = world.getRoomByID(id)
			var connected = 0
			for dir in dirs:
				if(!world.canGoID(id, dir)):
					continue
				connected += 1
				var other = world.getRoomByID(world.applyDirectionID(id, dir))
				check(world.astar.are_points_connected(room.astarID, other.astarID), label + ": " + id + " and its neighbour " + other.roomID + " are connected in the route graph")
				var origin = room if (dir == GameWorld.Direction.EAST || dir == GameWorld.Direction.SOUTH) else other
				var kind = "e" if (dir == GameWorld.Direction.EAST || dir == GameWorld.Direction.WEST) else "s"
				var key = floorID + ":" + str(int(origin.getCell().x)) + "," + str(int(origin.getCell().y)) + kind
				check(links.has(key), label + ": the connection " + id + " to " + other.roomID + " is drawn on the map")
			check(connected >= 1, label + ": " + id + " has at least one door")
	check(reachedAll == cellRooms and cellRooms >= 3, label + ": every cell is reachable: " + str(reachedAll) + " of " + str(cellRooms))
	# Nothing is drawn without being routable
	var stranded = []
	for pos in rooms:
		var room2 = rooms[pos]
		if(room2.roomID != entrance and world.calculatePath(entrance, room2.roomID).empty()):
			stranded.append(room2.roomID)
	check(stranded.empty() or stranded == ["solitary_cell"], label + ": no room is drawn but unreachable: " + str(stranded))
	# Every drawn line joins two rooms that really are connected
	for key in links:
		var parts = key.split(":")
		var tail = parts[1]
		var vertical = tail.ends_with("s")
		var xy = tail.substr(0, tail.length() - 1).split(",")
		var here = Vector2(float(xy[0]), float(xy[1]))
		var there = here + (Vector2(0, 1) if vertical else Vector2(1, 0))
		var floorCells = world.cells[parts[0]]
		check(floorCells.has(here) and floorCells.has(there) and world.astar.are_points_connected(floorCells[here].astarID, floorCells[there].astarID), label + ": the drawn line " + key + " matches a real connection")

func _ready():
	get_tree().create_timer(250.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")
	var main = MainScene.new()
	GM.main = main
	var thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")

	# ---- Growth path: the prison gets bigger while the map is in use ----
	var world = newWorld()
	world.addTransitions()
	var steps = [{"orange": 1, "red": 1, "lilac": 1}, {"orange": 3, "red": 2, "lilac": 2}, {"orange": 5, "red": 4, "lilac": 3}, {"orange": 8, "red": 8, "lilac": 8}]
	for population in [25, 45, 90, 120]:
		steps.append(LayoutScript.distribute({"orange": int(population * 0.45), "red": int(population * 0.3), "lilac": population - int(population * 0.45) - int(population * 0.3)}))
	steps.append({"orange": 60, "red": 60, "lilac": 60})
	var last = {"orange": 1, "red": 1, "lilac": 1}
	for step in steps:
		var counts = {}
		for block in LayoutScript.BLOCKS:
			counts[block] = int(max(step[block], last[block]))
		var _added = RoomsScript.ensureRooms(world, counts, module.getCellHook(world), true)
		last = counts
		judge(world, counts, "growing to " + str(counts))

	# ---- Start-up path: the rooms exist before the map's own transitions are built, as when a game starts or loads ----
	for counts in [{"orange": 8, "red": 8, "lilac": 8}, LayoutScript.distribute({"orange": 20, "red": 14, "lilac": 11}), {"orange": 60, "red": 60, "lilac": 60}]:
		var fresh = newWorld()
		var _added2 = RoomsScript.ensureRooms(fresh, counts, module.getCellHook(fresh), false)
		fresh.addTransitions()
		judge(fresh, counts, "start-up with " + str(counts))

	print("CellRoutesBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

extends Reference
class_name CellRooms

# Puts the cells on the map: real rooms on the Cellblock floor (see CellLayout for where), added through BDCC's own world API (GameWorld.addRoom), with a
# number on each, and a signal hook so entering one names its residents. No game state is kept here: how many cells exist is worked out from the inmates and
# the stored cell assignments every time, so an old save simply builds the rooms it needs. Static glue, so the world is passed in (untyped so tests can pass a stand-in).

const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")

const NUMBER_NODE = "SandboxCellNumber"
const FLOOR_ANCHOR = "cellblock_orange_nearcell" # any vanilla room of the Cellblock floor
const ENTER_SIGNAL = "onPreEnter"
const HANDLER = "onCellRoomPreEnter"

# Counts of inmates per block (entries: [[characterID, block], ...] as the module lists them) and the highest assigned cell per block.
static func countsOf(entries:Array) -> Dictionary:
	var counts:Dictionary = {"orange": 0, "red": 0, "lilac": 0}
	for entry in entries:
		if(entry is Array && entry.size() >= 2 && counts.has(entry[1])):
			counts[entry[1]] += 1
	return counts

static func highestAssigned(cells) -> Dictionary:
	var highest:Dictionary = {"orange": 0, "red": 0, "lilac": 0}
	for characterID in cells.getAssignedIDs():
		var entry:Dictionary = cells.getCell(characterID)
		if(!entry.empty() && highest.has(entry["block"])):
			highest[entry["block"]] = int(max(highest[entry["block"]], entry["cell"]))
	return highest

# How many cells each block has now: {"orange": n, ...}.
static func wantedCounts(entries:Array, cells) -> Dictionary:
	return LayoutScript.distribute(countsOf(entries), highestAssigned(cells))

# Whether the map's own transitions are already built (the Cellblock's rooms are connected). Rooms added after that need wiring themselves; rooms added before it are connected by addTransitions.
static func transitionsBuilt(world) -> bool:
	if(world == null):
		return false
	var anchor = world.getRoomByID(FLOOR_ANCHOR)
	if(anchor == null || anchor.get("astarConnections") == null):
		return false
	return !anchor.astarConnections.empty()

static func floorOf(world):
	var anchor = world.getRoomByID(FLOOR_ANCHOR)
	if(anchor == null):
		return ""
	return anchor.getFloorID()

# Builds every missing cell room and tags the vanilla cell 1 rooms. Returns the IDs of the rooms it added. wire: also connect the new rooms to the map graph
# (needed when rooms are added while the game runs; at start-up the world's own addTransitions does it afterwards).
static func ensureRooms(world, counts:Dictionary, handler = null, wire:bool = false) -> Array:
	var added:Array = []
	if(world == null):
		return added
	var floorID = floorOf(world)
	if(floorID == ""):
		return added
	for block in LayoutScript.BLOCKS:
		var vanilla = world.getRoomByID(LayoutScript.roomID(block, 1))
		if(vanilla != null):
			tagRoom(vanilla, block, 1, handler)
		var count:int = int(min(counts.get(block, 1), LayoutScript.maxCells()))
		for entry in LayoutScript.buildBlock(block, count):
			if(world.hasRoomID(entry["id"])):
				continue
			var open:Array = entry["open"]
			world.addRoom(floorID, entry["id"], Vector2(entry["x"], entry["y"]), {
				"name": LayoutScript.label(block, entry["cell"]),
				"desc": baseDescription(block, entry["cell"]),
				"icon": 10, # RoomStuff.RoomSprite.BED
				"color": LayoutScript.FLOOR_ROOM_COLORS[block],
				"canW": open[0], "canN": open[1], "canE": open[2], "canS": open[3],
			})
			var room = world.getRoomByID(entry["id"])
			if(room == null):
				continue
			tagRoom(room, block, entry["cell"], handler)
			added.append(entry["id"])
	if(wire && !added.empty()):
		wireRooms(world, added)
	return added

# What a visitor sees of a cell before knowing who lives there.
static func baseDescription(block, cell:int) -> String:
	return "A small cell with a stiff bed, a stool, an armored window and an automatic door. The number " + str(cell) + " is painted beside the door in " + LayoutScript.blockName(block).to_lower() + " paint."

# Number, zone group, enter hook. Safe to do twice.
static func tagRoom(room, block, cell:int, handler) -> void:
	var zone:String = "zone_" + LayoutScript.zoneOf(block, cell)
	if(!room.is_in_group(zone)):
		room.add_to_group(zone)
	if(!room.is_in_group("sbx_cell")):
		room.add_to_group("sbx_cell")
	if(room.get_node_or_null(NUMBER_NODE) == null):
		var number:Label = Label.new()
		number.name = NUMBER_NODE
		number.text = str(cell)
		number.rect_position = Vector2(-30, -31)
		number.add_color_override("font_color", Color(0.05, 0.05, 0.05))
		room.add_child(number)
	if(handler != null && room.has_signal(ENTER_SIGNAL) && !room.is_connected(ENTER_SIGNAL, handler, HANDLER)):
		var _err:int = room.connect(ENTER_SIGNAL, handler, HANDLER)

# Connects new rooms to their neighbours the way GameWorld.addTransitions does for the rooms that exist at start-up: A* links both ways, and the line drawn between
# two rooms (always from the room that is west or north of the other).
static func wireRooms(world, roomIDs:Array) -> void:
	var dirs:Array = [GameWorld.Direction.WEST, GameWorld.Direction.NORTH, GameWorld.Direction.EAST, GameWorld.Direction.SOUTH]
	for roomID in roomIDs:
		var room = world.getRoomByID(roomID)
		if(room == null):
			continue
		for dir in dirs:
			if(!world.canGoID(roomID, dir)):
				continue
			var otherID:String = world.applyDirectionID(roomID, dir)
			var other = world.getRoomByID(otherID)
			if(other == null):
				continue
			if(!world.astar.are_points_connected(room.astarID, other.astarID)):
				world.astar.connect_points(room.astarID, other.astarID)
				room.astarConnections.append(other.astarID)
				other.astarConnections.append(room.astarID)
				var owner = room if (dir == GameWorld.Direction.EAST || dir == GameWorld.Direction.SOUTH) else other
				var line = world.roomConnectionScene.instance()
				if(dir == GameWorld.Direction.SOUTH || dir == GameWorld.Direction.NORTH):
					line.rotation_degrees = 90
				owner.add_child(line)
				var cell:Vector2 = owner.getCell()
				line.global_position = (cell + (Vector2(0.5, 0) if (dir == GameWorld.Direction.EAST || dir == GameWorld.Direction.WEST) else Vector2(0, 0.5))) * GameWorld.gridsize

# The room title of a cell is always short and fixed ("Orange Cell 2"), so a long or odd character name can never overflow the sidebar. The residents are in the room description instead,
# where the text wraps: "Residents: Rowena and Brittney." (names: the occupants other than the player; "you" comes first when the player lives there).
static func residentsLine(names:Array, playerLives:bool) -> String:
	var all:Array = names.duplicate()
	if(playerLives):
		all.push_front("you")
	if(all.empty()):
		return "Nobody is assigned to this cell."
	return "Residents: " + LayoutScript.joinNames(all) + "."

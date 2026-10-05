extends Reference
class_name CellLayout

# Where the physical cells are. No game access, so it can be tested on its own.
#
# Cell 1 of each block is BDCC's own cell room (the three "player cell" rooms), so its ID, artwork and rest/stash scripts are reused. Every other cell is a new room with a stable ID
# "sbx_cell_<block>_<number>". The block's hall and its cell 1 are the anchors, and every new cell is added next to something already there, choosing the free spot closest to the middle of
# the block's part of the map, so each block grows into a compact blob (some rows left and right, some columns up and down) instead of one long line:
#   orange: the west and the north/south of the orange hall; red: the east; lilac: south of the lilac hall.
# The three original halls stay halls (they are the places inmates and quests start from, and BDCC's "Leave" goal and many scenes use them), so of the six original block rooms the three
# player cells are cells number 1 and the halls are the rooms the other cells open onto. The order is fixed: cell N is always at the same place, however many cells exist.
# Capacity is max(BASE_CELLS, ceil(inmates / 2), what the blocks need). Cells are only ever added: the number of rooms in a block is never lower than the highest cell number anyone is assigned to.

const BLOCKS = ["orange", "red", "lilac"]
const BLOCK_NAMES = {"orange": "Orange", "red": "Red", "lilac": "Lilac"}
const BASE_CELLS = 8
const PER_CELL = 2

# The vanilla room that is cell 1 of each block.
const FIRST_CELL_ROOMS = {"orange": "cellblock_orange_playercell", "red": "cellblock_red_playercell", "lilac": "cellblock_pink_playercell"}
const HALL_ROOMS = {"orange": "cellblock_orange_nearcell", "red": "cellblock_red_nearcell", "lilac": "cellblock_lilac_nearcell"}

# Grid positions of the block's hall and cell 1, the middle its cells gather around, and the part of the map it may use (min and max corner, inclusive).
const HALL_POS = {"orange": Vector2(-1, 2), "red": Vector2(1, 2), "lilac": Vector2(0, 3)}
const ORIGINS = {"orange": Vector2(-2, 2), "red": Vector2(2, 2), "lilac": Vector2(0, 4)}
const CENTER = {"orange": Vector2(-1.5, 2.0), "red": Vector2(1.5, 2.0), "lilac": Vector2(0.0, 4.6)}
const REGION_MIN = {"orange": Vector2(-12, -6), "red": Vector2(1, -6), "lilac": Vector2(-7, 4)}
const REGION_MAX = {"orange": Vector2(-1, 3), "red": Vector2(7, 3), "lilac": Vector2(7, 14)}
# Every room the Cellblock floor already has (grid positions), which no new cell may take: the stairs and corridors, the halls, the three player cells and the solitary cell.
const VANILLA_FLOOR = [Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 2), Vector2(-1, 2), Vector2(1, 2), Vector2(0, 3), Vector2(-2, 2), Vector2(2, 2), Vector2(0, 4), Vector2(8, 2)]
const MAX_CELLS = 60 # per block: far beyond any prison BDCC can generate

# The order cells are placed in for each block (index 0 is cell 2), worked out once from the rule above and kept: {block: [Vector2, ...]}.
const GROWTH = {}
const SLOTS = {} # the same spots as a lookup, worked out once per block

const FLOOR_ROOM_COLORS = {"orange": 5, "red": 2, "lilac": 4} # RoomStuff.RoomColor Orange, Red, Pink

static func isValidBlock(block) -> bool:
	return (block is String) && BLOCKS.has(block)

static func blockName(block) -> String:
	return BLOCK_NAMES.get(block, "?")

# ---- Capacity ----
# Cells needed for a population: ceil(inmates / 2), but never fewer than the base.
static func requiredCapacity(inmates:int) -> int:
	return int(max(BASE_CELLS, int(ceil(float(max(0, inmates)) / float(PER_CELL)))))

# Cells per block. typeCounts: how many inmates live in each block (the player counts); highest: the highest cell number already assigned in each block.
# Each block gets enough cells for its own inmates and for everyone already assigned; the remaining cells of the total capacity go to the blocks with the
# most inmates per cell. Deterministic, never fewer than 1 per block (cell 1 is a vanilla room).
static func distribute(typeCounts:Dictionary, highest:Dictionary = {}) -> Dictionary:
	var result:Dictionary = {}
	var total:int = 0
	var population:int = 0
	for block in BLOCKS:
		var count:int = int(max(0, typeCounts.get(block, 0)))
		population += count
		var needs:int = int(max(1, max(int(ceil(float(count) / float(PER_CELL))), int(highest.get(block, 0)))))
		result[block] = needs
		total += needs
	var target:int = int(max(requiredCapacity(population), total))
	while(total < target):
		var best:String = BLOCKS[0]
		var bestRatio:float = -1.0
		for block in BLOCKS:
			var ratio:float = float(int(typeCounts.get(block, 0)) + 1) / float(result[block])
			if(ratio > bestRatio):
				bestRatio = ratio
				best = block
		result[best] += 1
		total += 1
	return result

static func totalCells(counts:Dictionary) -> int:
	var total:int = 0
	for block in BLOCKS:
		total += int(counts.get(block, 0))
	return total

# ---- IDs ----
static func roomID(block, cell:int) -> String:
	if(!isValidBlock(block) || cell < 1):
		return ""
	if(cell == 1):
		return FIRST_CELL_ROOMS[block]
	return "sbx_cell_" + block + "_" + str(cell)

# {"block", "cell"} of a cell room ID (the vanilla cell 1 rooms included), or {}.
static func parse(id) -> Dictionary:
	if(!(id is String)):
		return {}
	for block in BLOCKS:
		if(FIRST_CELL_ROOMS[block] == id):
			return {"block": block, "cell": 1}
	var prefix:String = "sbx_cell_"
	if(!id.begins_with(prefix)):
		return {}
	var rest:String = id.substr(prefix.length())
	var parts:Array = rest.split("_")
	if(parts.size() != 2 || !isValidBlock(parts[0]) || !String(parts[1]).is_valid_integer()):
		return {}
	var cell:int = int(parts[1])
	if(cell < 2 || str(cell) != parts[1]):
		return {}
	return {"block": parts[0], "cell": cell}

static func isCellRoom(id) -> bool:
	return !parse(id).empty()

static func label(block, cell:int) -> String:
	return blockName(block) + " Cell " + str(cell)

# The zone group of one cell room: the zone name "sbxcell_<block>_<n>" is how a pawn is sent to exactly this room (BDCC's HangoutAt goal picks a room of a zone).
static func zoneOf(block, cell:int) -> String:
	return "sbxcell_" + str(block) + "_" + str(cell)

# ---- Layout ----
static func inRegion(block, point:Vector2) -> bool:
	return point.x >= REGION_MIN[block].x && point.x <= REGION_MAX[block].x && point.y >= REGION_MIN[block].y && point.y <= REGION_MAX[block].y

# The positions of cells 2, 3, 4... of a block: each is the free spot in the block's region, next to the hall, cell 1 or an earlier cell, closest to the block's middle (ties broken
# by position, so the result is always the same).
static func growth(block) -> Array:
	if(!isValidBlock(block)):
		return []
	if(GROWTH.has(block)):
		return GROWTH[block]
	var taken:Dictionary = {}
	for point in VANILLA_FLOOR:
		taken[point] = true
	var placed:Array = [HALL_POS[block], ORIGINS[block]]
	var order:Array = []
	var dirs:Array = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	while(order.size() < MAX_CELLS - 1):
		var best = null
		var bestDistance:float = 1000000.0
		for anchor in placed:
			for dir in dirs:
				var candidate:Vector2 = anchor + dir
				if(taken.has(candidate) || !inRegion(block, candidate)):
					continue
				var distance:float = candidate.distance_squared_to(CENTER[block])
				if(best == null || distance < bestDistance - 0.0001 || (abs(distance - bestDistance) < 0.0001 && (candidate.y < best.y || (candidate.y == best.y && candidate.x < best.x)))):
					best = candidate
					bestDistance = distance
		if(best == null):
			break
		taken[best] = true
		placed.append(best)
		order.append(best)
	GROWTH[block] = order
	return order

# Grid position (in map cells; the world multiplies by its grid size) of a cell. Cell 1 is the vanilla room.
static func position(block, cell:int) -> Vector2:
	if(!isValidBlock(block) || cell < 1):
		return Vector2.ZERO
	if(cell == 1):
		return ORIGINS[block]
	var order:Array = growth(block)
	return order[cell - 2] if cell - 2 < order.size() else Vector2.ZERO

# Highest cell number the layout can hold for a block.
static func maxCells() -> int:
	return MAX_CELLS

# Which of the four directions (GameWorld.Direction: WEST 0, NORTH 1, EAST 2, SOUTH 3) are open from a cell. A cell opens towards every spot that belongs to its own block (the block's hall, cell 1 and every
# place a later cell can take), never towards another block's rooms or the corridors. This does not depend on how many cells exist: a door is only a connection once the room on the other side exists
# too, so a cell built today and the cell built next month always agree. (Doors that depended on the current count left every later cell shut off from the cell it was built next to.)
# count is kept so callers do not change; it is not used.
static func openings(block, cell:int, _count:int = 0) -> Array:
	var open:Array = [false, false, false, false]
	if(!isValidBlock(block) || cell < 1):
		return open
	var here:Vector2 = position(block, cell)
	var dirs:Array = [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]
	var slots:Dictionary = slotsOf(block)
	for index in range(4):
		var there:Vector2 = here + dirs[index]
		if(there == HALL_POS[block] || (there == ORIGINS[block] && cell != 1) || slots.has(there)):
			open[index] = true
	return open

# Every spot a cell of the block can take, as {Vector2: true}.
static func slotsOf(block) -> Dictionary:
	if(SLOTS.has(block)):
		return SLOTS[block]
	var result:Dictionary = {}
	for point in growth(block):
		result[point] = true
	SLOTS[block] = result
	return result

# Every cell of a block laid out: [{"cell", "id", "x", "y", "open": [W, N, E, S]}], for cells 2..count (cell 1 is the vanilla room).
static func buildBlock(block, count:int) -> Array:
	var result:Array = []
	var capped:int = int(min(count, MAX_CELLS))
	for cell in range(2, capped + 1):
		var pos:Vector2 = position(block, cell)
		result.append({"cell": cell, "id": roomID(block, cell), "x": pos.x, "y": pos.y, "open": openings(block, cell, capped)})
	return result

# Short text for a list of resident names: "Alec", "Alec and Jeffery", "A, B and C".
static func joinNames(names:Array) -> String:
	if(names.empty()):
		return ""
	if(names.size() == 1):
		return str(names[0])
	var text:String = ""
	for index in range(names.size() - 2):
		text += str(names[index]) + ", "
	return text + str(names[names.size() - 2]) + " and " + str(names[names.size() - 1])

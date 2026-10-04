extends Reference
class_name Cells

# Inmate cells, cellmates and the nightly schedule. No game access here, so it can be tested on its own.
#
# BDCC's cell blocks are three colour-coded areas (orange, red, lilac) with one personal cell room each; there are no separate rooms for
# other inmates, so a cell is a logical home: block + number, two occupants at most. The player's cell is the block's existing player-cell room.
#
# SandboxState.cell_assignments[characterID] = {"block": "orange"|"red"|"lilac", "cell": int >= 1}
# SandboxState.known_cells[observerID][targetID] = true   (the observer has learned where the target lives)

const BLOCKS = ["orange", "red", "lilac"]
const BLOCK_NAMES = {"orange": "Orange", "red": "Red", "lilac": "Lilac"}
const CAPACITY = 2
const MAX_CELL_NUMBER = 9999
const PRESENCE_STATES = ["home", "away"]

# ---- Schedule (all numbers here) ----
const BEDTIME_HOUR = 21 # inmates settle into their cells around this time
const WAKE_HOUR = 7 # and leave around this time
const OFFSET_MINUTES = 30 # each inmate has a fixed offset of up to 30 minutes either way, so the prison settles gradually

const COLOR_CELL = "cyan"
const COLOR_NAME = "green"
const COLOR_AWAY = "#c8b560" # subdued yellow
const COLOR_ERROR = "red"

# Which night a time belongs to. The evening of day D and the early morning of day D+1 are the same night, numbered D. BDCC rolls the day number
# over at 06:00, so a time before the inmate's wake time counts as the night that began the previous day.
static func nightId(characterID, timeOfDay, day:int) -> int:
	var t:int = posmod(int(timeOfDay), 86400)
	return day if t >= bedtimeSeconds(characterID) else day - 1

var state

func _init(_state):
	state = _state

# ---- Pure helpers ----
static func isValidBlock(block) -> bool:
	return (block is String) && BLOCKS.has(block)

static func cellLabel(block, cell) -> String:
	return BLOCK_NAMES.get(block, "?") + " " + str(int(cell))

static func coloredCellLabel(block, cell) -> String:
	return "[color=" + COLOR_CELL + "]" + cellLabel(block, cell) + "[/color]"

# Stable per-character offset in seconds, -30 to +30 minutes. The salt gives bedtime and wake time different offsets.
static func offsetSeconds(characterID, salt:String) -> int:
	var span:int = OFFSET_MINUTES * 60 * 2 + 1
	return posmod((salt + str(characterID)).hash(), span) - OFFSET_MINUTES * 60

static func bedtimeSeconds(characterID) -> int:
	return BEDTIME_HOUR * 3600 + offsetSeconds(characterID, "bed")

static func wakeSeconds(characterID) -> int:
	return WAKE_HOUR * 3600 + offsetSeconds(characterID, "wake")

# True from the character's bedtime until their wake time. timeOfDay is seconds since midnight (BDCC's day starts at 06:00).
static func isNight(characterID, timeOfDay) -> bool:
	var t:int = posmod(int(timeOfDay), 86400)
	return t >= bedtimeSeconds(characterID) || t < wakeSeconds(characterID)

# ---- Assignments ----
func getCell(characterID) -> Dictionary:
	if(!(characterID is String) || !state.cell_assignments.has(characterID)):
		return {}
	var entry = state.cell_assignments[characterID]
	if(!(entry is Dictionary) || !isValidBlock(entry.get("block")) || !isNumberValue(entry.get("cell"))):
		return {}
	return {"block": entry["block"], "cell": int(entry["cell"])}

static func isNumberValue(value) -> bool:
	return (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) && !is_nan(float(value)) && !is_inf(float(value))

func isAssigned(characterID) -> bool:
	return !getCell(characterID).empty()

# Occupants of one cell, the player first, then by ID.
func getOccupants(block, cell) -> Array:
	var result:Array = []
	for characterID in state.cell_assignments:
		var entry:Dictionary = getCell(characterID)
		if(!entry.empty() && entry["block"] == block && entry["cell"] == int(cell)):
			result.append(characterID)
	result.sort()
	if(result.has("pc")):
		result.erase("pc")
		result.push_front("pc")
	return result

# The other occupant of the character's cell, or "" if they live alone or have no cell.
func getCellmate(characterID) -> String:
	var entry:Dictionary = getCell(characterID)
	if(entry.empty()):
		return ""
	for other in getOccupants(entry["block"], entry["cell"]):
		if(other != characterID):
			return other
	return ""

# Every cell with at least one occupant: [{"block", "cell", "occupants"}] ordered by block, then cell number.
func getOccupiedCells() -> Array:
	var byCell:Dictionary = {}
	for characterID in state.cell_assignments:
		var entry:Dictionary = getCell(characterID)
		if(entry.empty()):
			continue
		var key:String = entry["block"] + "|" + str(entry["cell"])
		if(!byCell.has(key)):
			byCell[key] = {"block": entry["block"], "cell": entry["cell"], "occupants": []}
		byCell[key]["occupants"].append(characterID)
	var result:Array = []
	for key in byCell:
		var cellEntry:Dictionary = byCell[key]
		cellEntry["occupants"].sort()
		if(cellEntry["occupants"].has("pc")):
			cellEntry["occupants"].erase("pc")
			cellEntry["occupants"].push_front("pc")
		result.append(cellEntry)
	result.sort_custom(self, "sortCells")
	return result

func sortCells(a, b) -> bool:
	var blockA:int = BLOCKS.find(a["block"])
	var blockB:int = BLOCKS.find(b["block"])
	if(blockA != blockB):
		return blockA < blockB
	return a["cell"] < b["cell"]

func getOccupiedCellsInBlock(block) -> Array:
	var result:Array = []
	for entry in getOccupiedCells():
		if(entry["block"] == block):
			result.append(entry)
	return result

# Occupancy counts keyed "block|cell".
func buildOccupancy() -> Dictionary:
	var counts:Dictionary = {}
	for characterID in state.cell_assignments:
		var entry:Dictionary = getCell(characterID)
		if(entry.empty()):
			continue
		var key:String = entry["block"] + "|" + str(entry["cell"])
		counts[key] = counts.get(key, 0) + 1
	return counts

# Puts the character in the first cell of the block with a free place. Never moves anyone else.
func assign(characterID, block) -> Dictionary:
	if(!(characterID is String) || characterID == "" || !isValidBlock(block)):
		return {}
	return assignWith(characterID, block, buildOccupancy())

func assignWith(characterID:String, block:String, occupancy:Dictionary) -> Dictionary:
	var cell:int = 1
	while(occupancy.get(block + "|" + str(cell), 0) >= CAPACITY && cell < MAX_CELL_NUMBER):
		cell += 1
	state.cell_assignments[characterID] = {"block": block, "cell": cell}
	occupancy[block + "|" + str(cell)] = occupancy.get(block + "|" + str(cell), 0) + 1
	return {"block": block, "cell": cell}

# entries: [[characterID, block], ...] for everyone who should have a cell. People who already have a valid cell keep it, so loading or
# adding inmates never reshuffles anyone. The player is placed first so they get cell 1 and the next inmate of their block becomes their cellmate.
# The player is the one exception to "keeps it": if their block no longer matches their inmate type they are moved. Returns how many were newly placed.
func ensureAssigned(entries:Array) -> int:
	var placed:int = 0
	var ordered:Array = []
	for entry in entries:
		if(entry is Array && entry.size() >= 2 && entry[0] is String && entry[0] != "" && isValidBlock(entry[1])):
			ordered.append(entry)
	ordered.sort_custom(self, "sortEntries")
	var occupancy:Dictionary = buildOccupancy()
	for entry in ordered:
		var current:Dictionary = getCell(entry[0])
		if(!current.empty() && (entry[0] != "pc" || current["block"] == entry[1])):
			continue
		if(!current.empty()):
			var oldKey:String = current["block"] + "|" + str(current["cell"])
			occupancy[oldKey] = max(0, occupancy.get(oldKey, 0) - 1)
			state.cell_assignments.erase(entry[0])
		var _cell:Dictionary = assignWith(entry[0], entry[1], occupancy)
		placed += 1
	return placed

func sortEntries(a, b) -> bool:
	if(a[0] == "pc" || b[0] == "pc"):
		return a[0] == "pc" && b[0] != "pc"
	return a[0] < b[0]

func getAssignedIDs() -> Array:
	var ids:Array = []
	for characterID in state.cell_assignments:
		if(isAssigned(characterID)):
			ids.append(characterID)
	ids.sort()
	return ids

# ---- Tonight's attendance ----
# The recorded state for the given night, or "" when nothing is recorded for that night.
func getPresence(characterID, night:int) -> String:
	if(!(characterID is String) || !state.cell_presence.has(characterID)):
		return ""
	var entry = state.cell_presence[characterID]
	if(!(entry is Dictionary) || !isNumberValue(entry.get("night")) || int(entry["night"]) != night || !PRESENCE_STATES.has(entry.get("state"))):
		return ""
	return entry["state"]

func setPresence(characterID, night:int, presence:String) -> bool:
	if(!(characterID is String) || characterID == "" || !PRESENCE_STATES.has(presence)):
		return false
	state.cell_presence[characterID] = {"night": night, "state": presence}
	return true

func clearPresence(characterID):
	state.cell_presence.erase(characterID)

# Removes a character's home and everything they or others learned about it.
func removeCharacter(characterID):
	if(!(characterID is String)):
		return
	state.cell_presence.erase(characterID)
	state.cell_assignments.erase(characterID)
	state.known_cells.erase(characterID)
	for observerID in state.known_cells.keys():
		if(state.known_cells[observerID] is Dictionary):
			state.known_cells[observerID].erase(characterID)
			if(state.known_cells[observerID].empty()):
				state.known_cells.erase(observerID)

# ---- Learned cells ----
# The observer learns where the target lives. Only possible when the target has a cell.
func learnCell(observerID, targetID) -> bool:
	if(!(observerID is String) || !(targetID is String) || observerID == "" || targetID == "" || observerID == targetID || !isAssigned(targetID)):
		return false
	if(!state.known_cells.has(observerID) || !(state.known_cells[observerID] is Dictionary)):
		state.known_cells[observerID] = {}
	state.known_cells[observerID][targetID] = true
	return true

func knowsCell(observerID, targetID) -> bool:
	if(!(observerID is String) || !(targetID is String) || !state.known_cells.has(observerID) || !(state.known_cells[observerID] is Dictionary)):
		return false
	return typeof(state.known_cells[observerID].get(targetID)) == TYPE_BOOL && state.known_cells[observerID][targetID]

func getKnownTargets(observerID) -> Array:
	var result:Array = []
	if(!(observerID is String) || !state.known_cells.has(observerID) || !(state.known_cells[observerID] is Dictionary)):
		return result
	for targetID in state.known_cells[observerID]:
		if(typeof(state.known_cells[observerID][targetID]) == TYPE_BOOL && state.known_cells[observerID][targetID]):
			result.append(targetID)
	result.sort()
	return result

func getCharacterIDs() -> Array:
	var ids:Dictionary = {}
	for characterID in state.cell_assignments:
		ids[characterID] = true
	for characterID in state.cell_presence:
		ids[characterID] = true
	for observerID in state.known_cells:
		ids[observerID] = true
		if(state.known_cells[observerID] is Dictionary):
			for targetID in state.known_cells[observerID]:
				ids[targetID] = true
	return ids.keys()

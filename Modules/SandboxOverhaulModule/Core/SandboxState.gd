extends Reference
class_name SandboxState

const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")

# 1 -> 2: injuries were added (version-1 saves have none).
# 2 -> 3: cell_assignments got its real structure and known_cells and cell_presence were added (older saves have none; cells are created on first use).
# 3 -> 4: work (jobs, shift and attendance), upgrades and hidden_storage were added (older saves are unemployed with no upgrades).
# 4 -> 5: security (Security Attention, warnings, search cooldowns) was added (older saves start at attention 0 with no cooldowns).
# 5 -> 6: gangs (membership, relations, captives, assignment) was added (older saves have no gangs; the established ones are created on first use).
# 6 -> 7: npc_jobs (the other inmates' jobs) and workplace (events, rivals) were added (older saves have none; jobs are handed out on first use).
# 7 -> 8: routines (today's plan of each inmate) and presence (where each inmate is and what they are doing) were added (older saves start from where the pawns stand).
# 8 -> 9: ownership (the player's owner, check-ins, demands, warnings, and the roles of the player's slaves) was added (older saves have none; BDCC's own owner and slaves stay as they are and are picked up on first use).
const CURRENT_SCHEMA_VERSION = 9
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const UpgradesScript = preload("res://Modules/SandboxOverhaulModule/Cells/CellUpgrades.gd")
const SecurityScript = preload("res://Modules/SandboxOverhaulModule/Security/Security.gd")
const GangsScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")
const NpcJobsScript = preload("res://Modules/SandboxOverhaulModule/Work/NpcJobs.gd")
const PresenceScript = preload("res://Modules/SandboxOverhaulModule/Prison/PresenceState.gd")
const WorkEventsScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEvents.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")

var schema_version: int = CURRENT_SCHEMA_VERSION
var npc_profiles: Dictionary = {}
var directed_relationships: Dictionary = {}
var major_memories: Dictionary = {}
var knowledge: Dictionary = {}
# characterID -> {"block": "orange"|"red"|"lilac", "cell": int}. See Cells.
var cell_assignments: Dictionary = {}
# observerID -> {targetID: true}: whose cell the observer has learned.
var known_cells: Dictionary = {}
# Tonight's attendance: characterID -> {"night": int, "state": "home"|"away"}. Only meaningful during that night; see Cells.
var cell_presence: Dictionary = {}
var gang_state: Dictionary = {}
var obligations: Array = []
var cooldowns: Dictionary = {}
# Prison-wide combat reputation, both -100..100 (see CombatConsequences).
var reputation: Dictionary = {"combat": 0.0, "defiance": 0.0}
# Lasting combat injuries: injuries[characterID][type] = {"severity": 1..3, "remainingHours": float}. See Injuries.
var injuries: Dictionary = {}
# The player's job, shift, warnings and work history. See Employment.
var work: Dictionary = EmploymentScript.defaults()
# Purchased cell upgrades and the hidden compartment's contents. See CellUpgrades. The ordinary storage is the vanilla pillow stash, which BDCC saves itself.
var upgrades: Dictionary = UpgradesScript.defaults()
var hidden_storage: Array = []
# Security Attention, warnings and every enforcement cooldown. See GuardSecurity.
var security: Dictionary = SecurityScript.defaults()
# Gangs, relations, personal gang relations, captives, the player's assignment. See GangService.
var gangs: Dictionary = GangsScript.defaults()
# Jobs of the other inmates and what the player has learned of them. See NpcJobs.
var npc_jobs: Dictionary = NpcJobsScript.defaults()
# Workplace events: cooldowns, rivals and the open event. See WorkEvents.
var workplace: Dictionary = WorkEventsScript.defaults()
# Today's plan of each inmate and where each inmate is. See PresenceState.
var routines: Dictionary = PresenceScript.defaultRoutines()
var presence: Dictionary = {}
# The player's owner and slaves, and the obligations between them. See Ownership.
var ownership: Dictionary = OwnershipScript.defaults()

const DICT_FIELDS = ["npc_profiles", "directed_relationships", "major_memories", "knowledge", "gang_state", "cooldowns"]

func clear():
	schema_version = CURRENT_SCHEMA_VERSION
	for field in DICT_FIELDS:
		set(field, {})
	obligations = []
	reputation = {"combat": 0.0, "defiance": 0.0}
	injuries = {}
	cell_assignments = {}
	known_cells = {}
	cell_presence = {}
	work = EmploymentScript.defaults()
	upgrades = UpgradesScript.defaults()
	hidden_storage = []
	security = SecurityScript.defaults()
	gangs = GangsScript.defaults()
	npc_jobs = NpcJobsScript.defaults()
	workplace = WorkEventsScript.defaults()
	routines = PresenceScript.defaultRoutines()
	presence = {}
	ownership = OwnershipScript.defaults()

# Safe getters: missing entries return defaults, never null.
func getNpcProfile(charID: String) -> Dictionary:
	return npc_profiles.get(charID, {})

func getDirectedRelationships(observerID: String) -> Dictionary:
	return directed_relationships.get(observerID, {})

func getMajorMemories(charID: String) -> Array:
	return major_memories.get(charID, [])

func getKnowledge(knowerID: String) -> Dictionary:
	return knowledge.get(knowerID, {})

func getCellAssignment(charID: String, default = {}):
	return cell_assignments.get(charID, default)

func getObligations() -> Array:
	return obligations

func getCooldown(key: String, default = 0):
	return cooldowns.get(key, default)

func saveData() -> Dictionary:
	var data = {"schema_version": schema_version, "obligations": obligations.duplicate(true), "reputation": reputation.duplicate(true), "injuries": injuries.duplicate(true), "cell_assignments": cell_assignments.duplicate(true), "known_cells": known_cells.duplicate(true), "cell_presence": cell_presence.duplicate(true),
		"work": work.duplicate(true), "upgrades": upgrades.duplicate(true), "hidden_storage": hidden_storage.duplicate(true), "security": security.duplicate(true), "gangs": gangs.duplicate(true), "npc_jobs": npc_jobs.duplicate(true), "workplace": workplace.duplicate(true), "routines": routines.duplicate(true), "presence": presence.duplicate(true), "ownership": ownership.duplicate(true)}
	for field in DICT_FIELDS:
		data[field] = get(field).duplicate(true)
	return data

func loadData(data) -> void:
	clear()
	if(!(data is Dictionary)):
		return
	
	# Saves store JSON numbers as floats, so cast.
	var version = data.get("schema_version", 1)
	schema_version = int(version) if (version is int || version is float) else 1
	
	for field in DICT_FIELDS:
		var value = data.get(field)
		if(value is Dictionary):
			set(field, value.duplicate(true))
	directed_relationships = sanitizeRelationships(data.get("directed_relationships"))
	reputation = sanitizeReputation(data.get("reputation"))
	if(schema_version >= 2):
		injuries = sanitizeInjuries(data.get("injuries"))
	if(schema_version >= 3):
		cell_assignments = sanitizeCellAssignments(data.get("cell_assignments"))
		known_cells = sanitizeKnownCells(data.get("known_cells"))
		cell_presence = sanitizeCellPresence(data.get("cell_presence"))
	if(schema_version >= 4):
		work = EmploymentScript.sanitize(data.get("work"))
		upgrades = UpgradesScript.sanitizeUpgrades(data.get("upgrades"))
		hidden_storage = UpgradesScript.sanitizeRecords(data.get("hidden_storage"), UpgradesScript.HIDDEN_SLOTS)
	if(schema_version >= 5):
		security = SecurityScript.sanitize(data.get("security"))
	if(schema_version >= 6):
		gangs = GangsScript.sanitize(data.get("gangs"))
	if(schema_version >= 7):
		npc_jobs = NpcJobsScript.sanitize(data.get("npc_jobs"))
		workplace = WorkEventsScript.sanitize(data.get("workplace"))
	if(schema_version >= 8):
		routines = PresenceScript.sanitizeRoutines(data.get("routines"))
		presence = PresenceScript.sanitizePresence(data.get("presence"))
	if(schema_version >= 9):
		ownership = OwnershipScript.sanitize(data.get("ownership"))
	var loadedObligations = data.get("obligations")
	if(loadedObligations is Array):
		obligations = loadedObligations.duplicate(true)
	
	migrate()

# Keeps only observer -> target -> dictionary entries. Recognised axes are clamped and default values dropped;
# unknown per-pair keys are kept for forward compatibility. Never aliases the input.
func sanitizeRelationships(raw) -> Dictionary:
	var result:Dictionary = {}
	if(!(raw is Dictionary)):
		return result
	for observerID in raw:
		if(!(observerID is String) || observerID == "" || !(raw[observerID] is Dictionary)):
			continue
		for targetID in raw[observerID]:
			if(!(targetID is String) || targetID == "" || targetID == observerID || !(raw[observerID][targetID] is Dictionary)):
				continue
			var pair:Dictionary = raw[observerID][targetID].duplicate(true)
			var allDefault:bool = true
			for axis in AxisScript.ALL:
				var key:String = AxisScript.getKey(axis)
				var value:float = AxisScript.getDefault(axis)
				if(pair.has(key) && AxisScript.isNumber(pair[key])):
					value = AxisScript.clampValue(axis, pair[key])
				pair[key] = value
				if(value != AxisScript.getDefault(axis)):
					allDefault = false
			if(allDefault):
				for axis in AxisScript.ALL:
					pair.erase(AxisScript.getKey(axis))
			if(pair.empty()):
				continue
			if(!result.has(observerID)):
				result[observerID] = {}
			result[observerID][targetID] = pair
	return result

# Keeps only characterID -> {block, cell} with a known block and a cell number from 1 to 9999. A cell holds two at most: when a cell has too many
# valid entries the player and then the lowest IDs keep it, so the repair is the same every time. Never aliases the input.
func sanitizeCellAssignments(raw) -> Dictionary:
	var result:Dictionary = {}
	if(!(raw is Dictionary)):
		return result
	var ids:Array = []
	for characterID in raw:
		if(characterID is String && characterID != "" && raw[characterID] is Dictionary):
			ids.append(characterID)
	ids.sort()
	if(ids.has("pc")):
		ids.erase("pc")
		ids.push_front("pc")
	var counts:Dictionary = {}
	for characterID in ids:
		var entry:Dictionary = raw[characterID]
		if(!CellsScript.isValidBlock(entry.get("block")) || !CellsScript.isNumberValue(entry.get("cell"))):
			continue
		var cell:int = int(round(float(entry["cell"])))
		if(cell < 1 || cell > CellsScript.MAX_CELL_NUMBER):
			continue
		var key:String = entry["block"] + "|" + str(cell)
		if(counts.get(key, 0) >= CellsScript.CAPACITY):
			continue
		counts[key] = counts.get(key, 0) + 1
		result[characterID] = {"block": entry["block"], "cell": cell}
	return result

# Keeps only characterID -> {night: number, state: "home"|"away"}. Saves without it (or with bad data) simply have no attendance recorded.
func sanitizeCellPresence(raw) -> Dictionary:
	var result:Dictionary = {}
	if(!(raw is Dictionary)):
		return result
	for characterID in raw:
		if(!(characterID is String) || characterID == "" || !(raw[characterID] is Dictionary)):
			continue
		var entry:Dictionary = raw[characterID]
		if(!CellsScript.isNumberValue(entry.get("night")) || !CellsScript.PRESENCE_STATES.has(entry.get("state"))):
			continue
		result[characterID] = {"night": int(round(float(entry["night"]))), "state": entry["state"]}
	return result

# Keeps only observerID -> {targetID: true} with non-empty string IDs, no self-knowledge and only true values.
func sanitizeKnownCells(raw) -> Dictionary:
	var result:Dictionary = {}
	if(!(raw is Dictionary)):
		return result
	for observerID in raw:
		if(!(observerID is String) || observerID == "" || !(raw[observerID] is Dictionary)):
			continue
		for targetID in raw[observerID]:
			if(!(targetID is String) || targetID == "" || targetID == observerID || !(typeof(raw[observerID][targetID]) == TYPE_BOOL && raw[observerID][targetID])):
				continue
			if(!result.has(observerID)):
				result[observerID] = {}
			result[observerID][targetID] = true
	return result

# Keeps only characterID -> known type -> {severity 1..3, remainingHours > 0}. Malformed entries are dropped; unknown extra keys on
# an entry are kept for forward compatibility. Never aliases the input.
func sanitizeInjuries(raw) -> Dictionary:
	var result:Dictionary = {}
	if(!(raw is Dictionary)):
		return result
	for characterID in raw:
		if(!(characterID is String) || characterID == "" || !(raw[characterID] is Dictionary)):
			continue
		for type in raw[characterID]:
			var entry = raw[characterID][type]
			if(!InjuriesScript.isValidType(type) || !(entry is Dictionary)):
				continue
			if(!AxisScript.isNumber(entry.get("severity")) || !AxisScript.isNumber(entry.get("remainingHours"))):
				continue
			var cleaned:Dictionary = entry.duplicate(true)
			cleaned["severity"] = int(clamp(round(float(entry["severity"])), InjuriesScript.MINOR, InjuriesScript.SEVERE))
			cleaned["remainingHours"] = float(entry["remainingHours"])
			if(cleaned["remainingHours"] <= 0.0):
				continue
			if(!result.has(characterID)):
				result[characterID] = {}
			result[characterID][type] = cleaned
	return result

# Both values default to 0; anything non-numeric is ignored and numbers are clamped to -100..100.
func sanitizeReputation(raw) -> Dictionary:
	var result:Dictionary = {"combat": 0.0, "defiance": 0.0}
	if(!(raw is Dictionary)):
		return result
	for key in result:
		if(raw.has(key) && AxisScript.isNumber(raw[key])):
			result[key] = clamp(float(raw[key]), -100.0, 100.0)
	return result

# Step upgrades one version at a time. Add `if(schema_version == N): ...; schema_version = N+1` blocks.
func migrate() -> void:
	if(schema_version > CURRENT_SCHEMA_VERSION):
		# Saved by a newer build: keep the data, do not downgrade the stamp.
		return
	if(schema_version < 1):
		schema_version = 1
	if(schema_version == 1):
		# 1 -> 2: injuries did not exist, so a version-1 save has none.
		injuries = {}
		schema_version = 2
	if(schema_version == 2):
		# 2 -> 3: cell_assignments had no structure and known_cells did not exist; cells are created on first use, so start empty.
		cell_assignments = {}
		known_cells = {}
		cell_presence = {}
		schema_version = 3
	if(schema_version == 3):
		# 3 -> 4: a version-3 save has no job, upgrades or storage: unemployed, nothing bought.
		work = EmploymentScript.defaults()
		upgrades = UpgradesScript.defaults()
		hidden_storage = []
		schema_version = 4
	if(schema_version == 4):
		# 4 -> 5: a version-4 save has no security state: attention 0 and no cooldowns.
		security = SecurityScript.defaults()
		schema_version = 5
	if(schema_version == 5):
		# 5 -> 6: a version-5 save has no gangs: the established ones are created on first use.
		gangs = GangsScript.defaults()
		schema_version = 6
	if(schema_version == 6):
		# 6 -> 7: a version-6 save has no NPC jobs or workplace events: jobs are handed out on first use.
		npc_jobs = NpcJobsScript.defaults()
		workplace = WorkEventsScript.defaults()
		schema_version = 7
	if(schema_version == 7):
		# 7 -> 8: a version-7 save has no routines or presence: today's plans are made from the characters when the game next runs the prison.
		routines = PresenceScript.defaultRoutines()
		presence = {}
		schema_version = 8
	if(schema_version == 8):
		# 8 -> 9: a version-8 save has no ownership record: the owner and the slaves BDCC already has are picked up the next time the game runs, with fresh schedules and no warnings.
		ownership = OwnershipScript.defaults()
		schema_version = 9

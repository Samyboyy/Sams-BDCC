extends Reference
class_name SandboxState

const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")

# 1 -> 2: injuries were added (version-1 saves have none).
const CURRENT_SCHEMA_VERSION = 2
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")

var schema_version: int = CURRENT_SCHEMA_VERSION
var npc_profiles: Dictionary = {}
var directed_relationships: Dictionary = {}
var major_memories: Dictionary = {}
var knowledge: Dictionary = {}
var cell_assignments: Dictionary = {}
var gang_state: Dictionary = {}
var obligations: Array = []
var cooldowns: Dictionary = {}
# Prison-wide combat reputation, both -100..100 (see CombatConsequences).
var reputation: Dictionary = {"combat": 0.0, "defiance": 0.0}
# Lasting combat injuries: injuries[characterID][type] = {"severity": 1..3, "remainingHours": float}. See Injuries.
var injuries: Dictionary = {}

const DICT_FIELDS = ["npc_profiles", "directed_relationships", "major_memories", "knowledge", "cell_assignments", "gang_state", "cooldowns"]

func clear():
	schema_version = CURRENT_SCHEMA_VERSION
	for field in DICT_FIELDS:
		set(field, {})
	obligations = []
	reputation = {"combat": 0.0, "defiance": 0.0}
	injuries = {}

# Safe getters: missing entries return defaults, never null.
func getNpcProfile(charID: String) -> Dictionary:
	return npc_profiles.get(charID, {})

func getDirectedRelationships(observerID: String) -> Dictionary:
	return directed_relationships.get(observerID, {})

func getMajorMemories(charID: String) -> Array:
	return major_memories.get(charID, [])

func getKnowledge(knowerID: String) -> Dictionary:
	return knowledge.get(knowerID, {})

func getCellAssignment(charID: String, default = ""):
	return cell_assignments.get(charID, default)

func getObligations() -> Array:
	return obligations

func getCooldown(key: String, default = 0):
	return cooldowns.get(key, default)

func saveData() -> Dictionary:
	var data = {"schema_version": schema_version, "obligations": obligations.duplicate(true), "reputation": reputation.duplicate(true), "injuries": injuries.duplicate(true)}
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

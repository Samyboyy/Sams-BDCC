extends Reference
class_name SandboxState

const CURRENT_SCHEMA_VERSION = 1

var schema_version: int = CURRENT_SCHEMA_VERSION
var npc_profiles: Dictionary = {}
var directed_relationships: Dictionary = {}
var major_memories: Dictionary = {}
var knowledge: Dictionary = {}
var cell_assignments: Dictionary = {}
var gang_state: Dictionary = {}
var obligations: Array = []
var cooldowns: Dictionary = {}

const DICT_FIELDS = ["npc_profiles", "directed_relationships", "major_memories", "knowledge", "cell_assignments", "gang_state", "cooldowns"]

func clear():
	schema_version = CURRENT_SCHEMA_VERSION
	for field in DICT_FIELDS:
		set(field, {})
	obligations = []

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
	var data = {"schema_version": schema_version, "obligations": obligations.duplicate(true)}
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
	var loadedObligations = data.get("obligations")
	if(loadedObligations is Array):
		obligations = loadedObligations.duplicate(true)
	
	migrate()

# Step upgrades one version at a time. Add `if(schema_version == N): ...; schema_version = N+1` blocks.
func migrate() -> void:
	if(schema_version > CURRENT_SCHEMA_VERSION):
		# Saved by a newer build: keep the data, do not downgrade the stamp.
		return
	schema_version = CURRENT_SCHEMA_VERSION

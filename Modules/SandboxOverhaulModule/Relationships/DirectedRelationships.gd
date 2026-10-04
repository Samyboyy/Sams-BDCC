extends Reference
class_name DirectedRelationships

const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")

# Reads SandboxState.directed_relationships on every call, so it follows the state when it clears or loads.
var state

func _init(_state):
	state = _state

func isValidPair(observerID, targetID) -> bool:
	return (observerID is String) && (targetID is String) && observerID != "" && targetID != "" && observerID != targetID

func getPair(observerID, targetID):
	var all:Dictionary = state.directed_relationships
	if(!all.has(observerID) || !(all[observerID] is Dictionary)):
		return null
	var pair = all[observerID].get(targetID)
	return pair if (pair is Dictionary) else null

func getFeeling(observerID, targetID, axis) -> float:
	if(!AxisScript.isValid(axis)):
		return 0.0
	if(!isValidPair(observerID, targetID)):
		return AxisScript.getDefault(axis)
	var pair = getPair(observerID, targetID)
	var key:String = AxisScript.getKey(axis)
	if(pair == null || !pair.has(key) || !AxisScript.isNumber(pair[key])):
		return AxisScript.getDefault(axis)
	return AxisScript.clampValue(axis, pair[key])

# Returns the stored value after clamping. Invalid input changes nothing and returns the current value.
func setFeeling(observerID, targetID, axis, value) -> float:
	if(!AxisScript.isValid(axis) || !isValidPair(observerID, targetID) || !AxisScript.isNumber(value)):
		return getFeeling(observerID, targetID, axis)
	var newValue:float = AxisScript.clampValue(axis, value)
	if(newValue == getFeeling(observerID, targetID, axis)):
		return newValue
	var all:Dictionary = state.directed_relationships
	if(!all.has(observerID) || !(all[observerID] is Dictionary)):
		all[observerID] = {}
	if(!all[observerID].has(targetID) || !(all[observerID][targetID] is Dictionary)):
		all[observerID][targetID] = {}
	all[observerID][targetID][AxisScript.getKey(axis)] = newValue
	normalizePair(observerID, targetID)
	return newValue

# Returns the change that was actually applied after clamping.
func adjustFeeling(observerID, targetID, axis, amount) -> float:
	if(!AxisScript.isValid(axis) || !isValidPair(observerID, targetID) || !AxisScript.isNumber(amount)):
		return 0.0
	var oldValue:float = getFeeling(observerID, targetID, axis)
	var newValue:float = AxisScript.clampValue(axis, oldValue + float(amount))
	if(newValue == oldValue):
		return 0.0
	var _stored:float = setFeeling(observerID, targetID, axis, newValue)
	return newValue - oldValue

# True when at least one recognised axis is not at its default.
func hasRelationship(observerID, targetID) -> bool:
	if(!isValidPair(observerID, targetID)):
		return false
	for axis in AxisScript.ALL:
		if(getFeeling(observerID, targetID, axis) != AxisScript.getDefault(axis)):
			return true
	return false

func removeRelationship(observerID, targetID):
	if(!isValidPair(observerID, targetID)):
		return
	var all:Dictionary = state.directed_relationships
	if(all.has(observerID) && all[observerID] is Dictionary):
		all[observerID].erase(targetID)
	cleanObserver(observerID)

func removeCharacter(characterID):
	if(!(characterID is String) || characterID == ""):
		return
	var all:Dictionary = state.directed_relationships
	all.erase(characterID)
	for observerID in all.keys():
		if(all[observerID] is Dictionary):
			all[observerID].erase(characterID)
		cleanObserver(observerID)

func getCharacterIDs() -> Array:
	var ids:Dictionary = {}
	var all:Dictionary = state.directed_relationships
	for observerID in all:
		ids[observerID] = true
		if(all[observerID] is Dictionary):
			for targetID in all[observerID]:
				ids[targetID] = true
	return ids.keys()

func describe(observerID, targetID) -> String:
	if(!isValidPair(observerID, targetID)):
		return "invalid relationship"
	var text:String = observerID + " -> " + targetID + ":"
	for axis in AxisScript.ALL:
		text += " " + axis + "=" + str(stepify(getFeeling(observerID, targetID, axis), 0.01))
	return text

# Writes all five keys while any axis is non-default; drops them (and empty parents) when all are default.
# Unknown keys in the pair are kept.
func normalizePair(observerID, targetID):
	var pair = getPair(observerID, targetID)
	if(pair == null):
		return
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
			state.directed_relationships[observerID].erase(targetID)
	cleanObserver(observerID)

func cleanObserver(observerID):
	var all:Dictionary = state.directed_relationships
	if(all.has(observerID) && all[observerID] is Dictionary && all[observerID].empty()):
		all.erase(observerID)

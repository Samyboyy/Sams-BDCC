extends Reference
class_name Injuries

# Lasting combat injuries. Three mechanical types, three severities, stored in SandboxState.injuries:
#   injuries[characterID][type] = {"severity": int 1..3, "remainingHours": float}
# All tuning lives in the constants below. The combat penalties themselves are applied by the injury status effects
# (StatusEffects/), through BDCC's existing buff and damage-modifier calculations, so each penalty is applied exactly once.

const ARM = "arm" # injured striking limb: physical damage dealt
const LEG = "leg" # impaired movement: maximum stamina and dodge chance
const TRAUMA = "trauma" # bruised ribs, torso or general damage: physical damage received
const TYPES = [ARM, LEG, TRAUMA]

const NONE = 0
const MINOR = 1
const MODERATE = 2
const SEVERE = 3

# In-game hours until a severity heals on its own. Reinjury resets to the new severity's duration.
const DURATION_HOURS = {1: 24.0, 2: 72.0, 3: 120.0}
# Penalty in percent for each severity (damage dealt, maximum stamina and dodge, damage received).
const PENALTY_PERCENT = {1: 10, 2: 20, 3: 30}

# Fraction of a fight's pain threshold the character ended with.
const MINOR_MIN_DAMAGE = 0.35
const MODERATE_MIN_DAMAGE = 0.60
const SEVERE_MIN_DAMAGE = 0.85

# Treatment price in credits at the medbay.
# BDCC's basic work pays 1 credit per 2-hour mine shift and a shift costs 40 of 100 stamina, so a normal day is about 3 credits.
# Minor is about half a day, Moderate a day, Severe two days. (A cryopod costs 10 and heals pain, not these injuries.)
const TREATMENT_COST = {1: 2, 2: 3, 3: 6}

# Extra interest opportunistic attackers take in an injured player, from the highest active severity only.
const ATTACK_INTEREST_MULT = {0: 1.0, 1: 1.1, 2: 1.25, 3: 1.4}

const TYPE_NAMES = {"arm": "Arm Injury", "leg": "Leg Injury", "trauma": "Body Trauma"}
const SEVERITY_NAMES = {1: "Minor", 2: "Moderate", 3: "Severe"}
const EFFECT_IDS = {"arm": "SandboxArmInjury", "leg": "SandboxLegInjury", "trauma": "SandboxBodyTrauma"}

var state

func _init(_state):
	state = _state

# ---- Pure rules ----
# 0 (none) to 3 (severe) from the fraction of the pain threshold the character ended a fight with.
static func severityFromDamage(fraction) -> int:
	if(!(typeof(fraction) == TYPE_INT || typeof(fraction) == TYPE_REAL)):
		return NONE
	if(fraction >= SEVERE_MIN_DAMAGE):
		return SEVERE
	if(fraction >= MODERATE_MIN_DAMAGE):
		return MODERATE
	if(fraction >= MINOR_MIN_DAMAGE):
		return MINOR
	return NONE

# regionDamage is accumulated damage per body region ({"arm": x, "leg": y, "torso": z}). BDCC does not record this today, so the
# argument is normally empty and the result is Body Trauma. Nothing is ever chosen at random.
static func pickType(regionDamage) -> String:
	if(!(regionDamage is Dictionary) || regionDamage.empty()):
		return TRAUMA
	var best:String = TRAUMA
	var bestValue:float = 0.0
	for region in regionDamage:
		var value = regionDamage[region]
		if(!(typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) || value <= bestValue):
			continue
		bestValue = float(value)
		best = ARM if (region == "arm") else (LEG if (region == "leg") else TRAUMA)
	return best

static func isValidType(type) -> bool:
	return (type is String) && TYPES.has(type)

static func typeName(type) -> String:
	return TYPE_NAMES.get(type, "Injury")

static func severityName(severity) -> String:
	return SEVERITY_NAMES.get(severity, "")

static func fullName(type, severity) -> String:
	return severityName(severity) + " " + typeName(type)

# The exact mechanical penalty.
static func penaltyText(type, severity) -> String:
	var pct = PENALTY_PERCENT.get(severity, 0)
	if(type == ARM):
		return "Physical damage -" + str(pct) + "%"
	if(type == LEG):
		return "Maximum stamina -" + str(pct) + "%, dodge chance -" + str(pct) + "%"
	if(type == TRAUMA):
		return "Physical damage received +" + str(pct) + "%"
	return ""

static func remainingText(hours) -> String:
	var h:float = float(hours)
	if(h < 1.0):
		return "less than an hour"
	if(h < 24.0):
		var whole:int = int(ceil(h))
		return str(whole) + (" hour" if whole == 1 else " hours")
	var days:int = int(round(h / 24.0))
	return str(days) + (" day" if days == 1 else " days")

static func attackInterestMultiplier(highestSeverity) -> float:
	return ATTACK_INTEREST_MULT.get(highestSeverity, 1.0)

# Highest active severity for a character in a raw injuries dictionary (SandboxState.injuries).
static func highestSeverityIn(injuries, characterID) -> int:
	var best:int = NONE
	if(!(injuries is Dictionary) || !(characterID is String) || !injuries.has(characterID) || !(injuries[characterID] is Dictionary)):
		return best
	for type in injuries[characterID]:
		var entry = injuries[characterID][type]
		if(entry is Dictionary && entry.has("severity") && int(entry["severity"]) > best):
			best = int(entry["severity"])
	return best

# ---- Stored injuries ----
func getAll(characterID) -> Dictionary:
	if(!(characterID is String) || !state.injuries.has(characterID) || !(state.injuries[characterID] is Dictionary)):
		return {}
	return state.injuries[characterID]

func has(characterID, type) -> bool:
	return getAll(characterID).has(type)

func getSeverity(characterID, type) -> int:
	var entry = getAll(characterID).get(type)
	return int(entry["severity"]) if (entry is Dictionary && entry.has("severity")) else NONE

func getRemainingHours(characterID, type) -> float:
	var entry = getAll(characterID).get(type)
	return float(entry["remainingHours"]) if (entry is Dictionary && entry.has("remainingHours")) else 0.0

func highestSeverity(characterID) -> int:
	return highestSeverityIn(state.injuries, characterID)

# Adds an injury, or worsens the same type if it is already active (Minor -> Moderate -> Severe, Severe stays Severe) and resets the
# remaining time. Returns {"result": "none"|"new"|"worsened"|"refreshed", "type", "from", "to"}.
func applyInjury(characterID, type, severity) -> Dictionary:
	var none:Dictionary = {"result": "none", "type": type, "from": NONE, "to": NONE}
	if(!(characterID is String) || characterID == "" || !isValidType(type) || !(severity is int) || severity < MINOR || severity > SEVERE):
		return none
	if(!state.injuries.has(characterID) || !(state.injuries[characterID] is Dictionary)):
		state.injuries[characterID] = {}
	var oldSeverity:int = getSeverity(characterID, type)
	var newSeverity:int = severity
	var result:String = "new"
	if(oldSeverity > NONE):
		newSeverity = int(min(SEVERE, oldSeverity + 1))
		result = "worsened" if newSeverity > oldSeverity else "refreshed"
	state.injuries[characterID][type] = {"severity": newSeverity, "remainingHours": DURATION_HOURS[newSeverity]}
	return {"result": result, "type": type, "from": oldSeverity, "to": newSeverity}

# One new injury at most per character per fight. The arena is supervised, so its severity drops one level.
func evaluateFight(characterID, damageFraction, arena:bool = false, regionDamage = null) -> Dictionary:
	var severity:int = severityFromDamage(damageFraction)
	if(arena):
		severity = int(max(NONE, severity - 1))
	if(severity == NONE):
		return {"result": "none", "type": "", "from": NONE, "to": NONE}
	return applyInjury(characterID, pickType(regionDamage), severity)

# Each active injury loses one hour per elapsed hour. Returns [{"characterID", "type"}] for the ones that healed.
func processHours(hours) -> Array:
	var recovered:Array = []
	if(!(typeof(hours) == TYPE_INT || typeof(hours) == TYPE_REAL) || hours <= 0):
		return recovered
	for characterID in state.injuries.keys():
		if(!(state.injuries[characterID] is Dictionary)):
			continue
		for type in state.injuries[characterID].keys():
			var entry = state.injuries[characterID][type]
			entry["remainingHours"] = float(entry["remainingHours"]) - float(hours)
			if(entry["remainingHours"] <= 0.0):
				state.injuries[characterID].erase(type)
				recovered.append({"characterID": characterID, "type": type})
		if(state.injuries[characterID].empty()):
			state.injuries.erase(characterID)
	return recovered

func remove(characterID, type):
	if(!has(characterID, type)):
		return
	state.injuries[characterID].erase(type)
	if(state.injuries[characterID].empty()):
		state.injuries.erase(characterID)

func removeCharacter(characterID):
	if(characterID is String):
		state.injuries.erase(characterID)

func getCharacterIDs() -> Array:
	return state.injuries.keys()

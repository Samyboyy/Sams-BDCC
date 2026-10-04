extends Object
class_name ConversationRelationships

# Relationship consequences of ordinary Talking outcomes, as the NPC's feelings towards the other character.
# No game access here, so it can be tested on its own. Fear is never changed by conversation.
# Respect is only touched by hostile responses.

const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")

const SHARED_INTEREST = "shared_interest" # chat: they agree and the topic really matters to them
const POSITIVE_CONVERSATION = "positive_conversation" # chat: they agree, weak interest
const NEUTRAL_EXCHANGE = "neutral_exchange" # chat: whatever / just learning something
const RESPECTFUL_DISAGREEMENT = "respectful_disagreement" # chat: they disagree
const HOSTILE_RESPONSE = "hostile_response" # no Talking outcome produces this yet
const FLIRT_ACCEPTED = "flirt_accepted"
const FLIRT_REJECTED = "flirt_rejected"
const SEX_REQUEST_ACCEPTED = "sex_request_accepted"
const SEX_REQUEST_REFUSED = "sex_request_refused" # no automatic change: refusal alone does not say they lack attraction

# A chat agreement counts as a shared interest when their interest in the topic is at least this strong (0..1).
const SHARED_INTEREST_MIN = 0.5

# ---- Tuning (all numbers live here). Axis points on the -100..100 scale. ----
const RULES = {
	"shared_interest": {"affection": 3.0, "trust": 1.0},
	"positive_conversation": {"affection": 2.0, "trust": 1.0},
	"neutral_exchange": {},
	"respectful_disagreement": {"affection": -1.0},
	"hostile_response": {"affection": -3.0, "trust": -2.0, "respect": -1.0},
	"flirt_accepted": {"affection": 2.0, "desire": 4.0},
	"flirt_rejected": {"desire": -2.0},
	"sex_request_accepted": {"desire": 2.0},
	"sex_request_refused": {},
}

# Fixed legacy (-1..1 scale) deltas, 100:1 with the axes above. The caller applies them through RelationshipSystem
# (so AffectionChange/LustChange events still fire) without the pawn reputation or personality multipliers.
# Temporary: Friend, Nemesis and AI still read the legacy values.
const LEGACY = {
	"shared_interest": {"affection": 0.03},
	"positive_conversation": {"affection": 0.02},
	"respectful_disagreement": {"affection": -0.01},
	"hostile_response": {"affection": -0.03},
	"flirt_accepted": {"affection": 0.02, "lust": 0.04},
	"flirt_rejected": {"lust": -0.02},
	"sex_request_accepted": {"lust": 0.02},
}

# Repeat protection: an outcome with any positive change is rewarded once per in-game day per NPC and target.
# Negative outcomes are never limited. Stored in SandboxState.cooldowns as key -> day number.
const COOLDOWN_PREFIX = "conv|"

static func getEffects(outcome) -> Dictionary:
	if(outcome is String && RULES.has(outcome)):
		return RULES[outcome]
	return {}

static func isPositive(outcome) -> bool:
	for axis in getEffects(outcome):
		if(RULES[outcome][axis] > 0.0):
			return true
	return false

static func getCooldownKey(outcome:String, observerID:String, targetID:String) -> String:
	return COOLDOWN_PREFIX + observerID + "|" + targetID + "|" + outcome

# Applies an outcome once. Returns {blocked, changes, legacyAffection, legacyLust}:
#  blocked: a positive reward already paid out today; nothing at all should be applied (directed or legacy).
#  changes: directed axis changes actually applied ({axis: amount}); the player's own feelings are never stored.
#  legacyAffection / legacyLust: fixed LEGACY deltas the caller applies to BDCC's RelationshipSystem.
# The cooldown is checked and consumed here, once. `cooldowns` is SandboxState.cooldowns, `day` the in-game day.
static func apply(relationships, cooldowns:Dictionary, outcome, observerID, targetID, day:int) -> Dictionary:
	var result:Dictionary = {"blocked": false, "changes": {}, "legacyAffection": 0.0, "legacyLust": 0.0}
	if(!(outcome is String) || !RULES.has(outcome) || !(observerID is String) || !(targetID is String) || observerID == "" || targetID == "" || observerID == targetID || observerID == "pc"):
		return result
	var positive:bool = isPositive(outcome)
	var key:String = getCooldownKey(outcome, observerID, targetID)
	if(positive && cooldowns.has(key) && cooldowns[key] == day):
		result["blocked"] = true
		return result
	var effects:Dictionary = RULES[outcome]
	for axis in AxisScript.ALL:
		if(!effects.has(axis)):
			continue
		var applied:float = relationships.adjustFeeling(observerID, targetID, axis, effects[axis])
		if(applied != 0.0):
			result["changes"][axis] = applied
	if(LEGACY.has(outcome)):
		result["legacyAffection"] = LEGACY[outcome].get("affection", 0.0)
		result["legacyLust"] = LEGACY[outcome].get("lust", 0.0)
	if(positive):
		cooldowns[key] = day
	return result

# Character IDs mentioned by conversation cooldown keys.
static func getCooldownCharacterIDs(cooldowns:Dictionary) -> Array:
	var ids:Dictionary = {}
	for key in cooldowns:
		if(key is String && key.begins_with(COOLDOWN_PREFIX)):
			var parts:PoolStringArray = key.split("|")
			if(parts.size() >= 4):
				ids[parts[1]] = true
				ids[parts[2]] = true
	return ids.keys()

static func removeCooldownsOf(cooldowns:Dictionary, characterID:String):
	for key in cooldowns.keys():
		if(key is String && key.begins_with(COOLDOWN_PREFIX)):
			var parts:PoolStringArray = key.split("|")
			if(parts.size() >= 4 && (parts[1] == characterID || parts[2] == characterID)):
				cooldowns.erase(key)

static func formatMessage(name:String, changes:Dictionary) -> String:
	return AftermathScript.formatMessage(name, changes)

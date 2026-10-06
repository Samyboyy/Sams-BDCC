extends Object
class_name SexAftermath

# Relationship consequences of one sex encounter. No game access here, so it can be tested on its own.
# Respect is deliberately not touched: combat outcomes will handle it later.

const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")

# ---- Tuning (all numbers live here). Axis points are on the -100..100 / 0..100 scale. ----

# Consensual and both participants at least this satisfied counts as a good experience.
const SATISFIED_MIN = 0.5

# Consensual, both satisfied. Scaled by 0.8..1.2 with the lower satisfaction.
const GOOD = {"affection": 5.0, "trust": 4.0, "desire": 8.0}
# Consensual, poor experience. Scaled by 1.0..1.5 the worse it was.
const POOR = {"affection": -3.0, "trust": -1.0, "desire": -5.0}
# Not scaled by satisfaction. The victim's Desire is never raised.
const COERCED_POINTS = {"affection": -10.0, "trust": -15.0, "fear": 8.0}
const FORCED_POINTS = {"affection": -25.0, "trust": -35.0, "fear": 20.0}

# The aggressor (the one who coerced or forced) successfully pursued what they wanted: their Desire for the victim rises a little. Never the victim's.
const AGGRESSOR_DESIRE = {ConsentScript.COERCED: 3.0, ConsentScript.FORCED: 5.0}

# Change to the legacy BDCC affection (-1..1 scale) of the victim towards the aggressor.
const LEGACY_AFFECTION = {ConsentScript.COERCED: -0.1, ConsentScript.FORCED: -0.25}
# After a non-consensual encounter the legacy affection is pushed to at most this, below the 0.5 Friend threshold,
# so the encounter can never start a Friend relationship.
const LEGACY_AFFECTION_CAP = 0.49

# ---- Message colours ----
const COLOR_POSITIVE = "green"
const COLOR_NEGATIVE = "red"
const COLOR_WARNING = "yellow" # fear increases

static func getLegacyAffectionChange(consent:int, currentAffection:float) -> float:
	if(!LEGACY_AFFECTION.has(consent)):
		return 0.0
	var target:float = min(currentAffection + LEGACY_AFFECTION[consent], LEGACY_AFFECTION_CAP)
	return target - currentAffection

# Axis deltas for the affected character's feelings. Empty when nothing applies.
static func getEffects(consent:int, domSatisfaction:float, subSatisfaction:float) -> Dictionary:
	if(consent == ConsentScript.CONSENSUAL):
		var lowest:float = clamp(min(domSatisfaction, subSatisfaction), 0.0, 1.0)
		var base:Dictionary = GOOD if lowest >= SATISFIED_MIN else POOR
		var scale:float = (0.8 + 0.4*lowest) if lowest >= SATISFIED_MIN else (1.0 + (SATISFIED_MIN - lowest))
		var result:Dictionary = {}
		for axis in base:
			result[axis] = base[axis] * scale
		return result
	if(consent == ConsentScript.COERCED || consent == ConsentScript.FORCED):
		var points:Dictionary = COERCED_POINTS if consent == ConsentScript.COERCED else FORCED_POINTS
		var result:Dictionary = {}
		for axis in points:
			# Satisfaction is ignored, and affection or trust can never go up here.
			result[axis] = min(points[axis], 0.0) if (axis == "affection" || axis == "trust") else points[axis]
		return result
	return {}

# The aggressor's own change after a non-consensual encounter: {"desire": +3 (coerced) or +5 (forced)}. Empty for consensual ones.
static func getAggressorEffects(consent:int) -> Dictionary:
	if(AGGRESSOR_DESIRE.has(consent)):
		return {"desire": AGGRESSOR_DESIRE[consent]}
	return {}

# Applies the encounter to the directed relationships. Returns [{observer, target, changes}] with the
# changes actually applied (after clamping), skipping zero changes.
# Consensual: each NPC participant towards their partner (Desire rises with a satisfying encounter, falls with a poor one, whoever is dom or sub, towards the player or another NPC).
# Non-consensual: the NPC victim (sub) towards the dom gets the negative points and never more Desire; the NPC aggressor (dom) towards the victim (the player or another NPC) gets a small Desire gain.
# The player's own feelings are never stored.
static func apply(relationships, consent:int, domID:String, subID:String, domSatisfaction:float, subSatisfaction:float) -> Array:
	var effects:Dictionary = getEffects(consent, domSatisfaction, subSatisfaction)
	var results:Array = []
	if(effects.empty() || domID == "" || subID == "" || domID == subID):
		return results
	var pairs:Array = []
	if(consent == ConsentScript.CONSENSUAL):
		pairs = [[domID, subID], [subID, domID]]
	else:
		pairs = [[subID, domID]]
	for pair in pairs:
		if(pair[0] == "pc"):
			continue
		var changes:Dictionary = {}
		for axis in AxisScript.ALL:
			if(!effects.has(axis)):
				continue
			var applied:float = relationships.adjustFeeling(pair[0], pair[1], axis, effects[axis])
			if(applied != 0.0):
				changes[axis] = applied
		results.append({observer = pair[0], target = pair[1], changes = changes})
	if(consent != ConsentScript.CONSENSUAL && domID != "pc"):
		var gain:Dictionary = getAggressorEffects(consent)
		var gained:Dictionary = {}
		for axis in gain:
			var applied:float = relationships.adjustFeeling(domID, subID, axis, gain[axis])
			if(applied != 0.0):
				gained[axis] = applied
		results.append({observer = domID, target = subID, changes = gained})
	return results

static func colorForChange(axis:String, amount:float) -> String:
	if(amount < 0.0):
		return COLOR_NEGATIVE
	return COLOR_WARNING if axis == "fear" else COLOR_POSITIVE

# One line, e.g. "Alex's feelings changed: Affection -25, Trust -35, Fear +20." Each value is coloured.
static func formatMessage(name:String, changes:Dictionary) -> String:
	var parts:Array = []
	for axis in AxisScript.ALL:
		if(!changes.has(axis)):
			continue
		var whole:int = int(round(changes[axis]))
		if(whole == 0):
			continue
		var text:String = axis.capitalize() + " " + ("+" if whole > 0 else "") + str(whole)
		parts.append("[color=" + colorForChange(axis, changes[axis]) + "]" + text + "[/color]")
	if(parts.empty()):
		return ""
	return name + "'s feelings changed: " + PoolStringArray(parts).join(", ") + "."

# Text for the NPC list: the NPC's feelings towards `targetID`, whole numbers.
static func formatFeelings(relationships, observerID:String, targetID:String) -> String:
	var values:Dictionary = {}
	for axis in AxisScript.ALL:
		var whole:int = int(round(relationships.getFeeling(observerID, targetID, axis)))
		values[axis] = ("+" if whole > 0 else "") + str(whole)
	return "Affection " + values["affection"] + "   Trust " + values["trust"] + "\nRespect " + values["respect"] + "   Fear " + values["fear"] + "\nDesire " + values["desire"]

# One line, e.g. "Affection -25, Trust -35, Respect 0, Fear +20, Desire 0".
static func formatSummary(relationships, observerID:String, targetID:String) -> String:
	var parts:Array = []
	for axis in AxisScript.ALL:
		var whole:int = int(round(relationships.getFeeling(observerID, targetID, axis)))
		parts.append(axis.capitalize() + " " + ("+" if whole > 0 else "") + str(whole))
	return PoolStringArray(parts).join(", ")

const FEELINGS_TOOLTIP = "Affection: emotional warmth or hostility\nTrust: belief that you are safe and reliable\nRespect: admiration or contempt\nFear: how threatening they consider you\nDesire: attraction or aversion"

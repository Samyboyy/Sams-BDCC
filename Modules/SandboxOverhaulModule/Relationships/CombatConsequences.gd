extends Reference
class_name CombatConsequences

# Social consequences of fights: prison-wide Combat Reputation and Defiance (SandboxState.reputation) plus one NPC's
# personal Fear, Respect (and, for unprovoked attacks, Affection and Trust) towards the player.
#
# Combat Reputation: perceived fighting ability (negative = easy target, positive = capable and dangerous).
# Defiance: perceived willingness to resist (negative = known to comply or surrender, positive = known to fight back).
# Both are -100..100 and start at 0. This is a lightweight rumour abstraction: no witnesses or propagation.

const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")

const REP_MIN = -100.0
const REP_MAX = 100.0

const WIN = "win" # the player won a fight
const LOSS = "loss" # the player fought and lost (pain or lust defeat)
const SURRENDER = "surrender" # the player gave up before being defeated
const UNPROVOKED = "unprovoked" # the player started a fight with no provocation
const CONSENSUAL_WIN = "consensual_win" # Fight Club or another agreed fight
const CONSENSUAL_LOSS = "consensual_loss"

# ---- Tuning (all numbers live here) ----
# combat / defiance: prison-wide points. npc: the NPC's feelings towards the player.
const RULES = {
	"win": {"combat": 6.0, "defiance": 2.0, "npc": {"fear": 10.0, "respect": 6.0}},
	"loss": {"combat": -4.0, "defiance": 2.0, "npc": {"fear": -4.0}}, # respect depends on LOSS_RESPECT
	"surrender": {"combat": -2.0, "defiance": -6.0, "npc": {"fear": -5.0, "respect": -3.0}},
	"unprovoked": {"npc": {"affection": -5.0, "trust": -8.0, "fear": 3.0}},
	"consensual_win": {"combat": 3.0, "npc": {"respect": 4.0}},
	"consensual_loss": {"combat": -2.0, "npc": {"respect": 1.0}},
}

# How badly the player lost, from the winner's damage taken (the larger of pain and lust as a fraction of
# their threshold, measured by FightScene when the fight ends). A close fight leaves the winner hurt.
const CLOSE_LOSS_MIN_DAMAGE = 0.6 # winner at 60% or more of a threshold: close loss
const CLEAR_LOSS_MIN_DAMAGE = 0.25 # 25% to 60%: clear loss. Below 25%: crushing loss.
const LOSS_RESPECT_CLOSE = 2.0
const LOSS_RESPECT_CLEAR = -2.0
const LOSS_RESPECT_CRUSHING = -5.0
const LOSS_RESPECT_UNKNOWN = -2.0 # no reliable measure: one fixed value

# Repeats against the same NPC on the same in-game day.
const REPEAT_PERSONAL_SCALE = 0.25
const REPEAT_DEFIANCE_SCALE = 0.25 # Defiance from repeated outcomes against the same NPC the same day
const COOLDOWN_PREFIX = "combat|"

# NPC attack interest: multiplied once, at the "attack" score type.
const ATTACK_COMBAT_MULT_AT_MIN = 1.5 # Combat Reputation -100
const ATTACK_COMBAT_MULT_AT_MAX = 0.5 # Combat Reputation +100
const ATTACK_FEAR_MULT_AT_MAX = 0.1 # personal Fear 100 (linear from 1.0 at Fear 0)
const ATTACK_MULT_FLOOR = 0.05 # nobody is ever fully immune
const ATTACK_MULT_CAP = 1.75 # injuries and a weak reputation together can raise interest only this far

# Post-fight punishment scoring after the player lost.
const DEFEAT_RESISTED = "resisted"
const DEFEAT_SURRENDERED = "surrendered"
const PUNISH_MULT_RESISTED = 1.25
const PUNISH_MULT_SURRENDERED = 0.65

const COLOR_DEFIANCE = "cyan" # a playstyle, not good or bad

var state
var relationships

func _init(_state, _relationships):
	state = _state
	relationships = _relationships

# ---- Prison-wide values ----
func getCombatReputation() -> float:
	return getRep("combat")

func getDefiance() -> float:
	return getRep("defiance")

func getRep(key:String) -> float:
	if(!(state.reputation is Dictionary) || !state.reputation.has(key) || !AxisScript.isNumber(state.reputation[key])):
		return 0.0
	return clamp(float(state.reputation[key]), REP_MIN, REP_MAX)

# Returns the change actually applied after clamping.
func addRep(key:String, amount:float) -> float:
	var old:float = getRep(key)
	var newValue:float = clamp(old + amount, REP_MIN, REP_MAX)
	if(!(state.reputation is Dictionary)):
		state.reputation = {}
	state.reputation[key] = newValue
	return newValue - old

static func getCombatBand(value:float) -> String:
	if(value <= -61.0):
		return "Easy target"
	if(value <= -21.0):
		return "Weak reputation"
	if(value <= 20.0):
		return "Unproven"
	if(value <= 60.0):
		return "Capable fighter"
	return "Formidable"

static func getDefianceBand(value:float) -> String:
	if(value <= -61.0):
		return "Highly compliant"
	if(value <= -21.0):
		return "Often compliant"
	if(value <= 20.0):
		return "Unpredictable"
	if(value <= 60.0):
		return "Defiant"
	return "Unbreakable"

static func signed(value:float) -> String:
	var whole:int = int(round(value))
	return ("+" if whole > 0 else "") + str(whole)

const DESCRIPTION_COMBAT = "How capable and dangerous the prison believes you are in a fight."
const DESCRIPTION_DEFIANCE = "How willing the prison believes you are to resist coercion."

# Visible text for the reputation screen: each value with its band and a one-line definition.
func describeReputation() -> String:
	var combat:float = getCombatReputation()
	var defiance:float = getDefiance()
	return "Combat Reputation: " + signed(combat) + " — " + getCombatBand(combat) + "\n" + DESCRIPTION_COMBAT + "\n\nDefiance: " + signed(defiance) + " — " + getDefianceBand(defiance) + "\n" + DESCRIPTION_DEFIANCE

# ---- Outcomes ----
static func classifyLoss(margin) -> float:
	if(!AxisScript.isNumber(margin) || margin < 0.0):
		return LOSS_RESPECT_UNKNOWN
	if(margin >= CLOSE_LOSS_MIN_DAMAGE):
		return LOSS_RESPECT_CLOSE
	if(margin >= CLEAR_LOSS_MIN_DAMAGE):
		return LOSS_RESPECT_CLEAR
	return LOSS_RESPECT_CRUSHING

# data: {npcID, outcome, day, margin (loss only; negative or missing when unknown)}
# Returns {npcID, outcome, reputation:{combat, defiance}, personal:{axis: amount}} with the amounts actually applied,
# or an empty dictionary for invalid input.
func applyCombatOutcome(data) -> Dictionary:
	if(!(data is Dictionary) || !data.has("outcome") || !(data["outcome"] is String) || !RULES.has(data["outcome"])):
		return {}
	var npcID = data.get("npcID")
	var day = data.get("day")
	if(!(npcID is String) || npcID == "" || npcID == "pc" || !AxisScript.isNumber(day)):
		return {}
	var outcome:String = data["outcome"]
	var rule:Dictionary = RULES[outcome]
	var result:Dictionary = {"npcID": npcID, "outcome": outcome, "reputation": {}, "personal": {}}

	var combatScale:float = 1.0
	var personalScale:float = 1.0
	var defianceScale:float = 1.0
	if(outcome != UNPROVOKED):
		var key:String = COOLDOWN_PREFIX + npcID
		var record = state.cooldowns.get(key)
		var outcomes:int = 0
		var surrenders:int = 0
		if(record is Array && record.size() >= 3 && AxisScript.isNumber(record[0]) && int(record[0]) == int(day)):
			outcomes = int(record[1])
			surrenders = int(record[2])
		if(outcomes > 0):
			combatScale = 0.0
			personalScale = REPEAT_PERSONAL_SCALE
			defianceScale = REPEAT_DEFIANCE_SCALE
		state.cooldowns[key] = [int(day), outcomes + 1, surrenders + (1 if outcome == SURRENDER else 0)]

	if(rule.has("combat")):
		var applied:float = addRep("combat", rule["combat"] * combatScale)
		if(applied != 0.0):
			result["reputation"]["combat"] = applied
	if(rule.has("defiance")):
		var applied:float = addRep("defiance", rule["defiance"] * defianceScale)
		if(applied != 0.0):
			result["reputation"]["defiance"] = applied

	var npcPoints:Dictionary = rule["npc"].duplicate()
	if(outcome == LOSS):
		npcPoints["respect"] = classifyLoss(data.get("margin"))
	for axis in AxisScript.ALL:
		if(!npcPoints.has(axis)):
			continue
		var applied:float = relationships.adjustFeeling(npcID, "pc", axis, npcPoints[axis] * personalScale)
		if(applied != 0.0):
			result["personal"][axis] = applied
	return result

# ---- Scoring ----
# Multiplier on an NPC's interest in attacking the player. Applied once, at the "attack" score type.
func attackMultiplier(npcID) -> float:
	var combatMult:float = lerp(ATTACK_COMBAT_MULT_AT_MIN, ATTACK_COMBAT_MULT_AT_MAX, (getCombatReputation() - REP_MIN) / (REP_MAX - REP_MIN))
	var fear:float = 0.0
	if(npcID is String && npcID != "" && npcID != "pc"):
		fear = clamp(relationships.getFeeling(npcID, "pc", "fear"), 0.0, 100.0)
	var fearMult:float = 1.0 - (1.0 - ATTACK_FEAR_MULT_AT_MAX) * (fear / 100.0)
	# The player's highest active injury makes them look like a better target (see Injuries.ATTACK_INTEREST_MULT).
	var injuryMult:float = InjuriesScript.attackInterestMultiplier(InjuriesScript.highestSeverityIn(state.injuries, "pc"))
	return clamp(combatMult * fearMult * injuryMult, ATTACK_MULT_FLOOR, ATTACK_MULT_CAP)

# Multiplier on harsher post-fight punishment scores after the player lost.
static func defeatPunishMultiplier(kind) -> float:
	if(kind == DEFEAT_RESISTED):
		return PUNISH_MULT_RESISTED
	if(kind == DEFEAT_SURRENDERED):
		return PUNISH_MULT_SURRENDERED
	return 1.0

# ---- Messages ----
static func colorFor(axis:String, amount:float) -> String:
	if(axis == "defiance"):
		return COLOR_DEFIANCE
	if(axis == "fear"):
		return "yellow"
	return "green" if amount > 0.0 else "red"

static func formatParts(order:Array, changes:Dictionary) -> Array:
	var parts:Array = []
	for axis in order:
		if(!changes.has(axis)):
			continue
		var whole:int = int(round(changes[axis]))
		if(whole == 0):
			continue
		parts.append("[color=" + colorFor(axis, changes[axis]) + "]" + axis.capitalize() + " " + signed(changes[axis]) + "[/color]")
	return parts

# "Your reputation changed: Combat +6, Defiance +2." (empty when nothing visible)
static func formatReputationMessage(changes:Dictionary) -> String:
	var parts:Array = formatParts(["combat", "defiance"], changes)
	if(parts.empty()):
		return ""
	return "Your reputation changed: " + PoolStringArray(parts).join(", ") + "."

# "Mae now sees you differently: Fear +10, Respect +6." (empty when nothing visible)
static func formatPersonalMessage(name:String, changes:Dictionary) -> String:
	var parts:Array = formatParts(["affection", "trust", "respect", "fear", "desire"], changes)
	if(parts.empty()):
		return ""
	return name + " now sees you differently: " + PoolStringArray(parts).join(", ") + "."

# ---- Cooldown helpers (see SandboxGameExtender pruning) ----
static func getCooldownCharacterIDs(cooldowns:Dictionary) -> Array:
	var ids:Array = []
	for key in cooldowns:
		if(key is String && key.begins_with(COOLDOWN_PREFIX)):
			ids.append(key.substr(COOLDOWN_PREFIX.length()))
	return ids

static func removeCooldownsOf(cooldowns:Dictionary, characterID:String):
	cooldowns.erase(COOLDOWN_PREFIX + characterID)

extends Module
class_name SandboxOverhaulModule

const ExtenderScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const ConversationScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")

func _init():
	id = "SandboxOverhaulModule"
	author = "Sam"
	
	gameExtenders = [
		"res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd",
	]

	statusEffects = [
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxArmInjury.gd",
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxLegInjury.gd",
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxBodyTrauma.gd",
	]

# Directed relationship service. Do not cache it across games; call this each time.
static func getRelationships():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getRelationships()

# Combat reputation service. Do not cache it across games; call this each time.
static func getCombat():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getCombat()

# Injury service. Do not cache it across games; call this each time.
static func getInjuries():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getInjuries()

# Active state. Resets itself when a different game (MainScene) is running.
static func getState():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getState()

# Called by PawnInteractionBase.doSexAftermath (see CORE_PATCHES.md). Applies the sandbox aftermath and returns whether
# the vanilla relationship aftermath (legacy affectAffection and affectLust from satisfaction) should still run.
# Fail closed: only an explicit CONSENSUAL classification returns true. COERCED, FORCED, UNKNOWN and any missing or
# malformed input (no interaction, result, roles, interaction ID or state) return false and change nothing.
func applySexAftermathAndShouldRunVanilla(interaction, sexData, sexResult) -> bool:
	if(interaction == null || sexResult == null || !(sexData is Array) || sexData.size() < 2):
		return false
	var domID:String = interaction.getRoleID(sexData[0])
	var subID:String = interaction.getRoleID(sexData[1])
	if(domID == "" || subID == "" || domID == subID):
		return false
	var consent:int = ConsentScript.classify(interaction.id, interaction.getState())
	if(consent == ConsentScript.UNKNOWN):
		return false

	var results:Array = AftermathScript.apply(getRelationships(), consent, domID, subID, sexResult.getAverageDomSatisfaction(), sexResult.getAverageSubSatisfaction())
	for entry in results:
		var npcID:String = entry["observer"] if entry["target"] == "pc" else ""
		if(npcID == ""):
			continue
		var npc = GlobalRegistry.getCharacter(npcID)
		var line:String = AftermathScript.formatMessage(npc.getName() if npc != null else "Someone", entry["changes"])
		if(line != ""):
			GM.main.addMessage(line)

	if(consent == ConsentScript.CONSENSUAL):
		return true

	# COERCED or FORCED. The legacy entry is shared by both characters, so this applies whoever the player is.
	var RS = GM.main.RS
	var legacyChange:float = AftermathScript.getLegacyAffectionChange(consent, RS.getAffection(subID, domID))
	if(legacyChange != 0.0):
		RS.addAffection(subID, domID, legacyChange, false, false)
	var npcOfPlayer:String = subID if domID == "pc" else (domID if subID == "pc" else "")
	if(npcOfPlayer != "" && RS.hasSpecialRelationshipID(npcOfPlayer, "Friend")):
		RS.stopSpecialRelationship(npcOfPlayer)
	return false

# Used by the NPC list (see CORE_PATCHES.md).
func getFeelingsText(observerID:String, targetID:String) -> String:
	return AftermathScript.formatFeelings(getRelationships(), observerID, targetID)

func getFeelingsTooltip() -> String:
	return AftermathScript.FEELINGS_TOOLTIP

func getFeelingsSummary(observerID:String, targetID:String) -> String:
	return AftermathScript.formatSummary(getRelationships(), observerID, targetID)

# Called by Talking.gd (see CORE_PATCHES.md). Applies one conversation outcome: the directed feelings, the fixed legacy
# deltas (events still fire, legacy messages suppressed) and one combined message when the player is the target.
# Returns {blocked, changes, legacyAffection, legacyLust}; when blocked nothing was applied and no message shown.
func applyConversationOutcome(outcome, observerID, targetID) -> Dictionary:
	if(GM.main == null || !is_instance_valid(GM.main)):
		return {"blocked": false, "changes": {}, "legacyAffection": 0.0, "legacyLust": 0.0}
	var result:Dictionary = ConversationScript.apply(getRelationships(), getState().cooldowns, outcome, observerID, targetID, GM.main.currentDay)
	if(result["blocked"]):
		return result
	var RS = GM.main.RS
	if(result["legacyAffection"] != 0.0):
		RS.addAffection(observerID, targetID, result["legacyAffection"], false, false)
	if(result["legacyLust"] != 0.0):
		RS.addLust(observerID, targetID, result["legacyLust"], false, false)
	if(!result["changes"].empty() && targetID == "pc"):
		var npc = GlobalRegistry.getCharacter(observerID)
		var line:String = ConversationScript.formatMessage(npc.getName() if npc != null else "Someone", result["changes"])
		if(line != ""):
			GM.main.addMessage(line)
	return result

# ---- Combat (see CORE_PATCHES.md) ----

# Applies one outcome against an NPC and shows the combined messages. Returns the service result.
func runCombatOutcome(npcID, outcome:String, margin = -1.0) -> Dictionary:
	if(GM.main == null || !is_instance_valid(GM.main)):
		return {}
	var result:Dictionary = getCombat().applyCombatOutcome({"npcID": npcID, "outcome": outcome, "day": GM.main.currentDay, "margin": margin})
	if(result.empty()):
		return result
	var repLine:String = CombatScript.formatReputationMessage(result["reputation"])
	if(repLine != ""):
		GM.main.addMessage(repLine)
	var npc = GlobalRegistry.getCharacter(npcID)
	var personalLine:String = CombatScript.formatPersonalMessage(npc.getName() if npc != null else "Someone", result["personal"])
	if(personalLine != ""):
		GM.main.addMessage(personalLine)
	return result

# After an interaction fight. result is {won, how, margin} from the fight scene. Only fights involving the player count.
func onFightAftermath(interaction, wonID, lostID, result) -> void:
	if(!(result is Dictionary) || !(wonID is String) || !(lostID is String) || (wonID == "pc") == (lostID == "pc")):
		return
	if(wonID == "pc"):
		var _w:Dictionary = runCombatOutcome(lostID, CombatScript.WIN)
		return
	if(result.get("submitter", "") == "pc"):
		# The player pressed Submit before being defeated. A pain or lust defeat is never treated as surrender.
		interaction.sandboxDefeatKind = CombatScript.DEFEAT_SURRENDERED
		var _s:Dictionary = runCombatOutcome(wonID, CombatScript.SURRENDER)
	else:
		interaction.sandboxDefeatKind = CombatScript.DEFEAT_RESISTED
		var _l:Dictionary = runCombatOutcome(wonID, CombatScript.LOSS, result.get("margin", -1.0))

# The player chose "Surrender" in an interaction before any fight.
func onPlayerSurrender(interaction, npcID) -> void:
	interaction.sandboxDefeatKind = CombatScript.DEFEAT_SURRENDERED
	var _s:Dictionary = runCombatOutcome(npcID, CombatScript.SURRENDER)

# The player started an ordinary, unprovoked fight with this NPC.
func onUnprovokedAttack(npcID) -> void:
	var _u:Dictionary = runCombatOutcome(npcID, CombatScript.UNPROVOKED)

# Called by FightScene.sandboxFightEnded when the player ends a fight. Only Fight Club arena fights are consensual; every other scene
# fight is ignored here (interaction fights are handled by onFightAftermath, scripted fights are left alone). The enemy surrendering
# is a win ("win" state) and the player submitting a loss ("lost" state), so the submitter does not change the arena result.
func onFightSceneEnded(enemyID, battleState, _submitter, battleName) -> void:
	if(battleName != "arenafight" || !(enemyID is String)):
		return
	var _c:Dictionary = runCombatOutcome(enemyID, CombatScript.CONSENSUAL_WIN if battleState == "win" else CombatScript.CONSENSUAL_LOSS)

func getAttackMultiplier(npcID) -> float:
	return getCombat().attackMultiplier(npcID)

func getDefeatPunishMultiplier(kind) -> float:
	return CombatScript.defeatPunishMultiplier(kind)

# Text for the reputation screen.
func getReputationText() -> String:
	return getCombat().describeReputation()

# ---- Injuries (see CORE_PATCHES.md) ----

# Makes the character's injury status effects match the stored injuries and keeps current stamina within the new maximum.
func refreshInjuryEffects(characterID) -> void:
	if(GM.main == null || !is_instance_valid(GM.main)):
		return
	var theChar = GM.main.getCharacter(characterID)
	if(theChar == null):
		return
	theChar.updateNonBattleEffects()
	theChar.addStamina(0)

func reportInjury(characterID, result:Dictionary) -> void:
	if(characterID != "pc" || GM.main == null || !is_instance_valid(GM.main)):
		return
	var type = result["type"]
	if(result["result"] == "new"):
		GM.main.addMessage("[color=orange]You were injured: " + InjuriesScript.fullName(type, result["to"]) + ". " + InjuriesScript.penaltyText(type, result["to"]) + ".[/color]")
	elif(result["result"] == "worsened"):
		GM.main.addMessage("[color=red]Your " + InjuriesScript.typeName(type) + " worsened from " + InjuriesScript.severityName(result["from"]) + " to " + InjuriesScript.severityName(result["to"]) + ".[/color]")
	elif(result["result"] == "refreshed"):
		GM.main.addMessage("[color=red]Your " + InjuriesScript.typeName(type) + " was aggravated. It stays Severe.[/color]")

# Called by FightScene.sandboxFightEnded with each fighter's pain as a fraction of their threshold. Both are judged on their own.
func onFightInjuries(enemyID, enemyFraction, playerFraction, battleName) -> void:
	var arena:bool = (battleName == "arenafight")
	var theInjuries = getInjuries()
	var ids:Array = ["pc"]
	var fractions:Array = [playerFraction]
	if(enemyID is String && enemyID != "" && enemyID != "pc"):
		ids.append(enemyID)
		fractions.append(enemyFraction)
	for i in range(ids.size()):
		var result:Dictionary = theInjuries.evaluateFight(ids[i], fractions[i], arena)
		if(result["result"] != "none"):
			refreshInjuryEffects(ids[i])
			reportInjury(ids[i], result)

# Called by the extender's pcHoursPassed hook with the number of in-game hours that passed.
func processInjuryHours(hours) -> void:
	for entry in getInjuries().processHours(hours):
		refreshInjuryEffects(entry["characterID"])
		if(entry["characterID"] == "pc" && GM.main != null && is_instance_valid(GM.main)):
			GM.main.addMessage("[color=green]Your " + InjuriesScript.typeName(entry["type"]) + " has healed.[/color]")

# The player's active injuries with their treatment prices, for the medbay.
func getTreatmentOptions() -> Array:
	var theInjuries = getInjuries()
	var options:Array = []
	for type in InjuriesScript.TYPES:
		if(!theInjuries.has("pc", type)):
			continue
		var severity:int = theInjuries.getSeverity("pc", type)
		var cost:int = InjuriesScript.TREATMENT_COST[severity]
		options.append({"type": type, "severity": severity, "cost": cost, "name": InjuriesScript.fullName(type, severity), "text": InjuriesScript.fullName(type, severity) + " - " + InjuriesScript.penaltyText(type, severity) + " - about " + InjuriesScript.remainingText(theInjuries.getRemainingHours("pc", type)) + " remaining. Treatment: " + str(cost) + " credits."})
	return options

# Pays and removes one injury. Nothing is charged if the injury is gone or the player cannot afford it.
func treatInjury(type) -> Dictionary:
	var theInjuries = getInjuries()
	if(!InjuriesScript.isValidType(type) || !theInjuries.has("pc", type)):
		return {"success": false, "reason": "none", "type": type}
	var severity:int = theInjuries.getSeverity("pc", type)
	var cost:int = InjuriesScript.TREATMENT_COST[severity]
	var credits:int = GM.pc.getCredits()
	if(credits < cost):
		return {"success": false, "reason": "credits", "type": type, "cost": cost, "missing": cost - credits}
	GM.pc.addCredits(-cost)
	theInjuries.remove("pc", type)
	refreshInjuryEffects("pc")
	return {"success": true, "type": type, "severity": severity, "cost": cost}

func describeTreatmentResult(result:Dictionary) -> String:
	if(result.get("success", false)):
		return "[color=green]Your " + InjuriesScript.fullName(result["type"], result["severity"]) + " was treated for " + str(result["cost"]) + " credits.[/color]"
	if(result.get("reason", "") == "credits"):
		return "[color=red]You cannot afford that treatment. It costs " + str(result["cost"]) + " credits and you are " + str(result["missing"]) + " short. Nothing was charged; the injury will heal by itself in time.[/color]"
	return "That injury is already gone. Nothing was charged."

# Multiplier for the Leg Injury, used by BaseCharacter.getMaxStamina and getDodgeChance: 1.0 when healthy, 0.9 / 0.8 / 0.7 when injured.
# Reads the stored injury directly (no character calculation), so it cannot recurse or apply twice.
func getLegInjuryScale(characterID) -> float:
	if(!GlobalRegistry.gameExtenders.has(ExtenderScript.EXTENDER_ID)):
		return 1.0
	var severity:int = getInjuries().getSeverity(characterID, InjuriesScript.LEG)
	if(severity <= 0):
		return 1.0
	return 1.0 - InjuriesScript.PENALTY_PERCENT[severity] / 100.0

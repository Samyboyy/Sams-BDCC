extends Module
class_name SandboxOverhaulModule

const ExtenderScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const ConversationScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")

func _init():
	id = "SandboxOverhaulModule"
	author = "Sam"
	
	gameExtenders = [
		"res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd",
	]

# Directed relationship service. Do not cache it across games; call this each time.
static func getRelationships():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getRelationships()

# Combat reputation service. Do not cache it across games; call this each time.
static func getCombat():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getCombat()

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

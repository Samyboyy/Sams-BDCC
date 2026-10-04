extends Module
class_name SandboxOverhaulModule

const ExtenderScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
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

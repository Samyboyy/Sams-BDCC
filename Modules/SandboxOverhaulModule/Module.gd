extends Module
class_name SandboxOverhaulModule

const ExtenderScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const ConversationScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const UpgradesScript = preload("res://Modules/SandboxOverhaulModule/Cells/CellUpgrades.gd")
const SecurityScript = preload("res://Modules/SandboxOverhaulModule/Security/Security.gd")
const SearchesScript = preload("res://Modules/SandboxOverhaulModule/Security/Searches.gd")
const ENFORCEMENT_INTERACTION = "res://Modules/SandboxOverhaulModule/Interactions/GuardEnforcement.gd"

func _init():
	id = "SandboxOverhaulModule"
	author = "Sam"
	
	gameExtenders = [
		"res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd",
	]

	scenes = [
		"res://Modules/SandboxOverhaulModule/Scenes/CellDirectoryScene.gd",
		"res://Modules/SandboxOverhaulModule/Scenes/JobBoardScene.gd",
		"res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd",
		"res://Modules/SandboxOverhaulModule/Scenes/CellUpgradesScene.gd",
	]

	worldEdits = [
		"res://Modules/SandboxOverhaulModule/WorldEdits/CellsWorldEdit.gd",
		"res://Modules/SandboxOverhaulModule/WorldEdits/WorkWorldEdit.gd",
	]

	statusEffects = [
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxArmInjury.gd",
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxLegInjury.gd",
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxBodyTrauma.gd",
	]

# Interactions cannot be listed in a module, so the guard confrontation registers itself once everything else is registered.
func postInit():
	GlobalRegistry.registerInteraction(ENFORCEMENT_INTERACTION)

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

# Cell service. Do not cache it across games; call this each time.
static func getCells():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getCells()

# Employment service. Do not cache it across games; call this each time.
static func getEmployment():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getEmployment()

# Cell upgrade and storage service. Do not cache it across games; call this each time.
static func getUpgrades():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getUpgrades()

# Security service. Do not cache it across games; call this each time.
static func getSecurity():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getSecurity()

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
	if(consent == ConsentScript.FORCED && domID == "pc"):
		recordWitnessedForcedSex(interaction)

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
	recordWitnessedViolence(npcID)

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

# ---- Cells, cellmates and the nightly routine (see CORE_PATCHES.md) ----

func blockForInmateType(inmateType) -> String:
	if(inmateType == InmateType.HighSec):
		return "red"
	if(inmateType == InmateType.SexDeviant):
		return "lilac"
	return "orange"

# Everyone who should have a home cell: the player and the dynamic inmates, including inmates who are now slaves (the Slaves pool, when they are
# inmates). Slavery can keep someone away from their cell but does not change where they live. Guards, staff and story characters are not in these
# pools. [[characterID, block], ...]
func getEligibleCellEntries() -> Array:
	var entries:Array = []
	if(GM.main == null || !is_instance_valid(GM.main)):
		return entries
	if(GM.pc != null):
		entries.append(["pc", blockForInmateType(GM.pc.getInmateType())])
	var candidates:Array = GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Inmates)
	for slaveID in GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Slaves):
		var slaveChar = GM.main.getCharacter(slaveID)
		if(slaveChar != null && slaveChar.isInmate() && !candidates.has(slaveID)):
			candidates.append(slaveID)
	for characterID in candidates:
		var theChar = GM.main.getCharacter(characterID)
		if(theChar == null || !theChar.isDynamicCharacter()):
			continue
		entries.append([characterID, blockForInmateType(theChar.getInmateType())])
	return entries

# Gives every eligible inmate without a cell the first free place. Safe to call often; nobody who has a cell is ever moved.
func refreshCells() -> int:
	return getCells().ensureAssigned(getEligibleCellEntries())

func characterName(characterID) -> String:
	if(characterID == "pc"):
		return "You"
	if(GM.main == null || !is_instance_valid(GM.main)):
		return str(characterID)
	var theChar = GM.main.getCharacter(characterID)
	return theChar.getName() if theChar != null else str(characterID)

# Alone-goals that matter more than bedtime: giving birth, laying eggs, being healed, an ambush, approaching the owner, struggling, slave errands.
const PRIORITY_GOALS = ["GiveBirth", "LayEggs", "GetHealed", "NemesisAmbush", "NpcOwnerApproach", "Struggle", "SlaveLeave", "SlaveGiveCredits"]

# True when moving this pawn would break something that matters more than bedtime: any interaction except idling (talking, fighting,
# exhaustion, stocks, slutwall, unconscious, a scripted scene), one of the priority goals above, slavery or ownership, or a quest.
func isPawnBlocked(pawn) -> bool:
	if(pawn == null || pawn.isDeleted):
		return true
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.id != "AloneInteraction"):
		return true
	if(interaction != null && interaction.goal != null && PRIORITY_GOALS.has(interaction.goal.id)):
		return true
	var theChar = pawn.getChar()
	if(theChar == null || theChar.isSlaveToPlayer() || theChar.hasEnslaveQuest()):
		return true
	if(GM.main.RS.hasSpecialRelationshipID(pawn.charID, "SoftSlavery")):
		return true
	return false

# Called by the extender's pcProcessTime hook. Runs the schedule at most once per ten in-game minutes.
func onScheduleTick() -> void:
	if(GM.main == null || !is_instance_valid(GM.main) || GM.main.isInDungeon()):
		return
	var bucket:int = GM.main.getDays() * 144 + int(GM.main.getTime() / 600)
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	if(extender.scheduleBucket == bucket):
		return
	extender.scheduleBucket = bucket
	var _placed:int = refreshCells()
	var _result:Dictionary = sweepResidents()

# True when something detectable keeps this inmate away from their cell: the player owns them, they are in SoftSlavery, or they are on an
# enslave quest. This says nothing about where they are, only that they are not simply unspawned in bed.
func isKeptElsewhere(characterID) -> bool:
	var theChar = GM.main.getCharacter(characterID)
	if(theChar == null):
		return false
	return theChar.isSlaveToPlayer() || theChar.hasEnslaveQuest() || GM.main.RS.hasSpecialRelationshipID(characterID, "SoftSlavery")

# Home or away for tonight, "" outside the character's night or without a cell. A recorded state for tonight wins; without one it is worked out
# now: a pawn that is still out, or a condition that keeps them elsewhere, means away; an inmate who is simply not spawned is assumed home.
func getAttendance(characterID) -> String:
	if(GM.main == null || !is_instance_valid(GM.main) || characterID == "pc"):
		return ""
	var theCells = getCells()
	var now:int = GM.main.getTime()
	if(!theCells.isAssigned(characterID) || !CellsScript.isNight(characterID, now)):
		return ""
	var recorded:String = theCells.getPresence(characterID, CellsScript.nightId(characterID, now, GM.main.getDays()))
	if(recorded != ""):
		return recorded
	if(GM.main.IS.hasPawn(characterID) || isKeptElsewhere(characterID)):
		return "away"
	return "home"

func recordAttendance(characterID, presence:String) -> void:
	var night:int = CellsScript.nightId(characterID, GM.main.getTime(), GM.main.getDays())
	var theCells = getCells()
	if(theCells.getPresence(characterID, night) != presence):
		var _ok:bool = theCells.setPresence(characterID, night, presence)

# Sends inmates whose bedtime has come to their cells and records who is home and who is away for the night. A pawn that is busy is left alone,
# marked away, and tried again at the next tick. A pawn near the player is made tired so BDCC's own "Leave" goal walks it back to its cell block before
# it disappears (still away until it is gone); everyone else just goes (they are somewhere the player cannot see) and is home. An inmate with no pawn
# is home unless something keeps them elsewhere. The player is never moved. Attendance of the previous night is dropped.
# Returns {"despawned": [], "walking": [], "deferred": [], "home": [], "away": []}.
func sweepResidents() -> Dictionary:
	var result:Dictionary = {"despawned": [], "walking": [], "deferred": [], "home": [], "away": []}
	if(GM.main == null || !is_instance_valid(GM.main)):
		return result
	var IS = GM.main.IS
	var theCells = getCells()
	var now:int = GM.main.getTime()
	var day:int = GM.main.getDays()
	# Waking, or a new night, invalidates old attendance.
	for characterID in theCells.state.cell_presence.keys():
		if(!theCells.isAssigned(characterID) || !CellsScript.isNight(characterID, now) || theCells.getPresence(characterID, CellsScript.nightId(characterID, now, day)) == ""):
			theCells.clearPresence(characterID)
	# Pawns in the player's room, or within two rooms when the map is loaded, are walked home instead of vanishing.
	var nearIDs:Array = []
	if(GM.pc != null):
		nearIDs = IS.getPawnIDsAt(GM.pc.getLocation())
		if(GM.world != null):
			nearIDs.append_array(IS.getPawnIDsNear(GM.pc.getLocation(), 2))
	for characterID in theCells.getAssignedIDs():
		if(characterID == "pc" || !CellsScript.isNight(characterID, now)):
			continue
		var pawn = IS.getPawn(characterID)
		var presence:String = "home"
		if(pawn != null):
			presence = "away"
			if(isPawnBlocked(pawn)):
				result["deferred"].append(characterID)
			elif(nearIDs.has(characterID)):
				pawn.tiredness = max(pawn.tiredness, 1.5)
				result["walking"].append(characterID)
			else:
				IS.deletePawn(characterID)
				result["despawned"].append(characterID)
				presence = "home"
		elif(isKeptElsewhere(characterID)):
			presence = "away"
		recordAttendance(characterID, presence)
		result[presence].append(characterID)
	return result

# Used by InteractionSystem.trySpawnPawn so an inmate who should still be in their cell is not picked for a random appearance.
func canSpawnPawn(characterID) -> bool:
	if(GM.main == null || !is_instance_valid(GM.main) || !getCells().isAssigned(characterID)):
		return true
	return !CellsScript.isNight(characterID, GM.main.getTime())

# Whether the character is in their cell now: the player when they stand in their cell room; an inmate during their night whose attendance is home.
func isInCell(characterID) -> bool:
	if(GM.main == null || !is_instance_valid(GM.main)):
		return false
	if(characterID == "pc"):
		return GM.pc != null && GM.pc.getLocation() == GM.pc.getCellLocation()
	return getAttendance(characterID) == "home"

# For later systems: it is night for this inmate, they have a cell and they are away from it (still walking about, kept busy, or kept elsewhere).
func hasFailedToReturn(characterID) -> bool:
	return getAttendance(characterID) == "away"

func getPlayerCell() -> Dictionary:
	var _placed:int = refreshCells()
	return getCells().getCell("pc")

func getPlayerCellmate() -> String:
	var _placed:int = refreshCells()
	return getCells().getCellmate("pc")

# ---- Text ----
func presenceText(characterID) -> String:
	if(isInCell(characterID)):
		return "in the cell"
	return "[color=" + CellsScript.COLOR_AWAY + "]not here[/color]"

func occupantText(characterID) -> String:
	return "[color=" + CellsScript.COLOR_NAME + "]" + characterName(characterID) + "[/color] (" + presenceText(characterID) + ")"

func getMyCellText() -> String:
	var entry:Dictionary = getPlayerCell()
	if(entry.empty()):
		return "[color=" + CellsScript.COLOR_ERROR + "]You have no cell assigned.[/color]"
	var text:String = "Your cell: " + CellsScript.coloredCellLabel(entry["block"], entry["cell"])
	var mate:String = getCells().getCellmate("pc")
	if(mate == ""):
		text += "\nCellmate: none yet"
	else:
		text += "\nCellmate: " + occupantText(mate)
	return text

func getKnownCellsText() -> String:
	var _placed:int = refreshCells()
	var theCells = getCells()
	var lines:Array = []
	for targetID in theCells.getKnownTargets("pc"):
		var entry:Dictionary = theCells.getCell(targetID)
		if(entry.empty()):
			continue
		lines.append("[color=" + CellsScript.COLOR_NAME + "]" + characterName(targetID) + "[/color]: " + CellsScript.coloredCellLabel(entry["block"], entry["cell"]))
	if(lines.empty()):
		return "You have not learned anyone else's cell yet. Ask people in conversation."
	return "Cells you know:\n" + PoolStringArray(lines).join("\n")

func getCellsScreenText() -> String:
	return getMyCellText() + "\n\n" + getKnownCellsText()

const ROSTER_PAGE_SIZE = 8

func getRosterPageCount(block) -> int:
	var _placed:int = refreshCells()
	return int(max(1, ceil(float(getCells().getOccupiedCellsInBlock(block).size()) / float(ROSTER_PAGE_SIZE))))

# The cells on one page of a block's roster: [{"block", "cell", "occupants", "line"}].
func getRosterPage(block, page:int) -> Array:
	var _placed:int = refreshCells()
	var all:Array = getCells().getOccupiedCellsInBlock(block)
	var result:Array = []
	for i in range(page * ROSTER_PAGE_SIZE, min(all.size(), (page + 1) * ROSTER_PAGE_SIZE)):
		var entry:Dictionary = all[i].duplicate()
		var names:Array = []
		for occupant in entry["occupants"]:
			names.append(occupantText(occupant))
		entry["line"] = CellsScript.coloredCellLabel(entry["block"], entry["cell"]) + ": " + PoolStringArray(names).join(", ") + (" [color=" + CellsScript.COLOR_CELL + "](your cell)[/color]" if entry["occupants"].has("pc") else "")
		result.append(entry)
	return result

# The text for looking into one cell: the shared interior, its occupants and whether they are there.
func getCellViewText(block, cell:int) -> String:
	var _placed:int = refreshCells()
	var occupants:Array = getCells().getOccupants(block, cell)
	var text:String = CellsScript.coloredCellLabel(block, cell) + "\nThe cell is a small metal room with an armored window and an automatic door, a stiff bed and a stool. The same as every other one."
	if(occupants.empty()):
		return text + "\nNobody is assigned to it."
	var names:Array = []
	for occupant in occupants:
		names.append(occupantText(occupant))
	return text + "\nAssigned: " + PoolStringArray(names).join(", ") + (".\nThis is your cell." if occupants.has("pc") else ".")

# What an inmate says when asked which cell they live in. {"found": bool, "line": say text, "note": text for the player}.
func getCellAnswer(npcID) -> Dictionary:
	var _placed:int = refreshCells()
	var entry:Dictionary = getCells().getCell(npcID)
	if(entry.empty()):
		return {"found": false, "line": "I don't have a cell like the others do.", "note": ""}
	return {"found": true, "line": "I'm in " + CellsScript.coloredCellLabel(entry["block"], entry["cell"]) + ".", "note": "[color=yellow]Cell learned:[/color] " + characterName(npcID) + " lives in " + CellsScript.coloredCellLabel(entry["block"], entry["cell"]) + "."}

# The player asks an inmate which cell they live in. Learning it changes nothing else (no relationship points, no cooldown).
func learnCell(npcID) -> bool:
	var _placed:int = refreshCells()
	return getCells().learnCell("pc", npcID)

# ---- Work, money and cell upgrades (see CORE_PATCHES.md) ----

# Interactions that hold the player somewhere against their will, with the reason shown when a shift is excused.
const BLOCKING_INTERACTIONS = {
	"InStocks": "locked in the stocks", "InSlutwall": "locked in a slutwall", "Unconscious": "unconscious", "NurseSave": "being treated after collapsing",
	"InNpcOwnerEvent": "kept busy by your owner", "CaughtOffLimits": "held by a guard", "FightExhaustion": "recovering after a lost fight",
	"PunishInteraction": "being punished", "NemesisAmbush": "caught in an ambush",
}

func isMainReady() -> bool:
	return GM.main != null && is_instance_valid(GM.main) && GM.pc != null

# "" when nothing detectable keeps the player from going to work right now, otherwise the reason. This is a snapshot of the present moment: BDCC keeps
# no history of where the player was, so it can only be asked when the shift is found overdue (see CORE_PATCHES.md and the Work README).
func getBlockedReason() -> String:
	if(!isMainReady()):
		return ""
	if(GM.main.PS != null):
		return "serving as a slave"
	if(GM.main.RS != null):
		for ownerID in GM.main.RS.special:
			if(GM.pc.isSlaveTo(ownerID)):
				return "owned by " + characterName(ownerID)
	for scene in GM.main.sceneStack:
		if(scene.sceneID == "NpcOwnerEventRunnerScene"):
			return "kept busy by your owner"
	if(GM.main.IS != null && GM.main.IS.hasPawn("pc")):
		var interaction = GM.main.IS.getPawn("pc").currentInteraction
		if(interaction != null && BLOCKING_INTERACTIONS.has(interaction.id)):
			return BLOCKING_INTERACTIONS[interaction.id]
	return ""

# Called by the extender's pcProcessTime hook: reminders, missed and excused shifts, dismissals.
func onWorkTick() -> void:
	if(!isMainReady() || GM.main.isInDungeon()):
		return
	var employment = getEmployment()
	var day:int = GM.main.getDays()
	var timeOfDay:int = GM.main.getTime()
	var blocked:String = getBlockedReason() if employment.isShiftOverdue(day, timeOfDay) else ""
	for event in employment.tick(day, timeOfDay, blocked):
		GM.main.addMessage(EmploymentScript.eventText(event))

func getWorkScreenText() -> String:
	if(!isMainReady()):
		return ""
	return getEmployment().getStatusText(GM.main.getDays(), GM.main.getTime())

# True when the player has a job and already worked their shift today.
func isShiftCompleteToday() -> bool:
	return isMainReady() && getEmployment().isShiftCompleteToday(GM.main.getDays())

# For other modules: the player could not go to work for a reason of theirs (say they were held somewhere). Excuses today's pending shift: no wage, no warning.
func recordExcusedAbsence(reason:String = "") -> bool:
	if(!isMainReady()):
		return false
	var excused:bool = getEmployment().recordExcused(GM.main.getDays())
	if(excused):
		GM.main.addMessage(EmploymentScript.eventText({"type": "excused", "job": getEmployment().getJobID(), "reason": reason if reason != "" else "something kept you away"}))
	return excused

# A copy of the work state: job, today's shift, warnings and history.
func getEmploymentState() -> Dictionary:
	return getState().work.duplicate(true)

# Takes a job from the board. Returns the service result {"ok", "reason"}.
func acceptJob(jobID) -> Dictionary:
	if(!isMainReady()):
		return {"ok": false, "reason": "Not in a game."}
	return getEmployment().accept(jobID, GM.main.getDays(), GM.main.getTime())

func leaveJob() -> bool:
	return isMainReady() && getEmployment().leave(GM.main.getDays())

# Starts and finishes today's shift: checks the window, takes the stamina and the wage in one go. Returns {"ok", "reason", "wage", "balance", "job"}.
# The caller then passes the shift time. The result is recorded before the time passes so the clock cannot mark the shift as missed.
func startShift(jobID) -> Dictionary:
	if(!isMainReady()):
		return {"ok": false, "reason": "Not in a game."}
	var employment = getEmployment()
	var day:int = GM.main.getDays()
	var timeOfDay:int = GM.main.getTime()
	var check:Dictionary = employment.canStartShift(jobID, day, timeOfDay)
	if(!check["ok"]):
		return check
	if(GM.pc.getStamina() <= 0):
		return {"ok": false, "reason": "You are too tired to work. Rest first."}
	var wage:int = employment.completeShift(jobID, day, timeOfDay)
	if(wage <= 0):
		return {"ok": false, "reason": "You have no shift to do today."}
	GM.pc.addCredits(wage)
	GM.pc.addStamina(-int(EmploymentScript.JOBS[jobID]["stamina"]))
	return {"ok": true, "reason": "", "wage": wage, "balance": GM.pc.getCredits(), "job": jobID}

# The vanilla mining credit, paid once a day. Called by WorkInMinesScene: later sessions the same day still mine but earn nothing.
func getInformalMiningPay() -> int:
	if(!isMainReady()):
		return 1
	return 1 if getEmployment().claimInformalMiningPay(GM.main.getDays()) else 0

# ---- Cell upgrades and storage ----

func getPurchasedUpgrades() -> Dictionary:
	return getUpgrades().getOwned()

# Buys an upgrade: checks the credits, charges the price once and marks it owned in the same step. Returns {"ok", "reason"}.
func buyUpgrade(upgradeID) -> Dictionary:
	if(!isMainReady()):
		return {"ok": false, "reason": "Not in a game."}
	var upgrades = getUpgrades()
	var check:Dictionary = upgrades.canBuy(upgradeID, GM.pc.getCredits())
	if(!check["ok"]):
		return check
	GM.pc.addCredits(-UpgradesScript.price(upgradeID))
	var _owned:bool = upgrades.markOwned(upgradeID)
	return {"ok": true, "reason": ""}

# The vanilla pillow stash: BDCC's "playerstash" character inventory. Null without a running game.
func getStash():
	if(!isMainReady()):
		return null
	var stashCharacter = GM.main.getCharacter("playerstash")
	return stashCharacter.getInventory() if stashCharacter != null else null

func getStashUsed() -> int:
	var stash = getStash()
	return stash.getAllItems().size() if stash != null else 0

func getStashStatusText() -> String:
	return getUpgrades().stashStatusText(getStashUsed())

func itemRecord(item) -> Dictionary:
	return {"id": item.id, "uniqueID": item.uniqueID, "data": item.saveData()}

# Ordinary (the real pillow stash, as copies of its items' saved data) or hidden (the compartment) contents.
func getStoredRecords(hidden:bool) -> Array:
	if(hidden):
		return getUpgrades().getRecords()
	var records:Array = []
	var stash = getStash()
	if(stash != null):
		for item in stash.getAllItems():
			records.append(itemRecord(item))
	return records

# Why an item cannot go into storage, "" when it can. The rule: the item sits loose in the player's own inventory (BDCC keeps worn items in the equipped slots, so a
# loose restraint is just an item and is allowed, smart lock and all, since its saved data round-trips), is not worn or attached, and is not important or persistent.
# The work credits the stash scene offers are not an inventory item and skip the carrying checks.
func getStoreRefusal(item) -> String:
	if(item == null || !isMainReady()):
		return "There is nothing to store."
	if(item.id != "WorkCredit"):
		var inventory = GM.pc.getInventory()
		if(inventory.getEquippedItems().values().has(item)):
			return "You are wearing it. Take it off first."
		if(!inventory.hasItem(item)):
			return "You are not carrying it."
		if(item.isWornByWearer()):
			return "It is attached to someone. Take it off first."
		if(item.isImportant()):
			return "It is too important to put away."
		if(item.isPersistent()):
			return "It cannot be put away."
	if(item.uniqueID == null || !(item.uniqueID is String) || item.uniqueID == ""):
		return "It cannot be put away."
	if(GlobalRegistry.getItemRef(item.id) == null):
		return "It cannot be put away."
	return ""

# Whether the pillow stash takes this item: the general rules plus the capacity (4 stacks, 12 with the locker). Used by PlayerStashScene
# and the cell upgrade screen, so both enforce the same rule. A stack that merges into one already there needs no room.
func getStashDepositRefusal(item) -> String:
	var reason:String = getStoreRefusal(item)
	if(reason != ""):
		return reason
	var stash = getStash()
	if(stash == null):
		return "There is no stash here."
	var merges:bool = item.canCombine() && stash.hasItemID(item.id)
	return getUpgrades().stashRefusal(stash.getAllItems().size(), !merges)

# Why an item cannot go into the chosen store, "" when it can.
func getDepositRefusal(item, hidden:bool) -> String:
	if(!hidden):
		return getStashDepositRefusal(item)
	var reason:String = getStoreRefusal(item)
	if(reason != ""):
		return reason
	return getUpgrades().canStore(itemRecord(item))

# Moves a carried item into the chosen store with all of its data. Returns "" on success or the reason it was refused (nothing moves then).
func depositItem(item, hidden:bool) -> String:
	var reason:String = getDepositRefusal(item, hidden)
	if(reason != ""):
		return reason
	if(hidden):
		reason = getUpgrades().store(itemRecord(item))
		if(reason != ""):
			return reason
		var _removed = GM.pc.getInventory().removeItem(item)
		return ""
	var _taken = GM.pc.getInventory().removeItem(item)
	getStash().addItem(item)
	return ""

# Moves a stored item back to the player, rebuilt from its data (hidden) or the very same object (stash). Returns "" on success or the reason.
func withdrawItem(uniqueID:String, hidden:bool) -> String:
	if(!isMainReady()):
		return "Not in a game."
	if(!hidden):
		var stash = getStash()
		var item = stash.getItemByUniqueID(uniqueID) if stash != null else null
		if(item == null):
			return "It is not in there."
		var _removed = stash.removeItem(item)
		if(item.id == "WorkCredit"):
			GM.pc.addCredits(item.getAmount())
		else:
			GM.pc.getInventory().addItem(item)
		return ""
	var upgrades = getUpgrades()
	var record:Dictionary = {}
	for candidate in upgrades.getRecords():
		if(candidate["uniqueID"] == uniqueID):
			record = candidate
	if(record.empty()):
		return "It is not in there."
	var rebuilt = GlobalRegistry.createItem(record["id"], false)
	if(rebuilt == null):
		return "That item no longer exists."
	rebuilt.uniqueID = record["uniqueID"]
	rebuilt.loadData(record["data"])
	var _taken2:Dictionary = upgrades.take(uniqueID)
	GM.pc.getInventory().addItem(rebuilt)
	return ""

# Called by RestingInCellScene after a rest in the player's own cell: the better bedding gives extra stamina. Returns the bonus.
func afterRestInOwnCell(seconds) -> int:
	if(!isMainReady() || GM.pc.getLocation() != GM.pc.getCellLocation()):
		return 0
	var hours:float = floor(float(seconds) / 3600.0)
	var multiplier:float = max(1.0 + GM.pc.getBuffsHolder().getCustom(BuffAttribute.RestEffectiveness), 0.1)
	var bonus:int = getUpgrades().restBonus(hours * 10.0 * multiplier)
	if(bonus > 0):
		GM.pc.addStamina(bonus)
		GM.main.addMessage("Your better bedding gives you " + str(bonus) + " extra stamina.")
	return bonus

# ---- Guards, searches and enforcement (see CORE_PATCHES.md and Security/) ----

# The dice for every guard decision. Tests queue values here (each call takes the next one); in the game it is always a fresh random number.
var queuedRolls:Array = []

func nextRoll() -> float:
	return float(queuedRolls.pop_front()) if !queuedRolls.empty() else randf()

func isSecurityReady() -> bool:
	return isMainReady() && GM.main.IS != null

func getSecurityNow() -> int:
	return SecurityScript.stamp(GM.main.getDays(), GM.main.getTime())

func getSecurityScreenText() -> String:
	if(!isMainReady()):
		return ""
	return getSecurity().getScreenText(getSecurityNow())

func isGuardPawn(pawn) -> bool:
	return pawn != null && !pawn.isDeleted && pawn.getChar() != null && pawn.isGuard()

# A guard who sees the player is simply a guard pawn in the same room. BDCC has no line of sight, so same-room presence is the witness rule.
# A guard who is in the middle of something else (sex, a fight, stocks...) is not a witness; the victim of an attack is, whatever they are doing.
func getGuardWitnesses(locationID:String, excludeIDs:Array = [], includeBusyID:String = "") -> Array:
	var result:Array = []
	if(!isSecurityReady()):
		return result
	for pawn in GM.main.IS.getPawnsAt(locationID):
		if(!isGuardPawn(pawn) || excludeIDs.has(pawn.charID)):
			continue
		var interaction = pawn.currentInteraction
		if(interaction == null || interaction.id == "AloneInteraction" || pawn.charID == includeBusyID):
			result.append(pawn)
	return result

# Guards who can act right now: witnesses who are not busy.
func getFreeGuards(locationID:String) -> Array:
	var result:Array = []
	for pawn in getGuardWitnesses(locationID):
		if(pawn.canBeInterrupted()):
			result.append(pawn)
	return result

func getGuardAttitude(guardID:String) -> String:
	var theChar = GM.main.getCharacter(guardID)
	var mean = 0.0
	if(theChar != null && theChar.getPersonality() != null):
		mean = theChar.getPersonality().getStat(PersonalityStat.Mean)
	return SecurityScript.attitudeFor(guardID, mean)

# Staff Reputation level plus this guard's Trust and Respect towards the player, bounded to +-0.10.
func getGuardLeniency(guardID:String) -> float:
	var level = GM.pc.getReputation().getRepLevel(RepStat.Staff)
	var relationships = getRelationships()
	return SecurityScript.leniency(level, relationships.getFeeling(guardID, "pc", "trust"), relationships.getFeeling(guardID, "pc", "respect"))

func getGuardFear(guardID:String) -> float:
	return getRelationships().getFeeling(guardID, "pc", "fear")

# Places where being undressed is expected: showers and bathrooms, the medical area, the player's own cell and solitary.
static func isNudityExemptPlace(roomID, ownCellLocation) -> bool:
	if(!(roomID is String) || roomID == ""):
		return true
	var lower:String = roomID.to_lower()
	if(roomID == ownCellLocation || lower.find("shower") != -1 || lower.find("bathroom") != -1 || lower.find("medical") != -1 || lower.begins_with("med_") || lower.begins_with("medroom") || lower.find("solitary") != -1 || lower.find("playercell") != -1 || lower.begins_with("intro_")):
		return true
	return false

# Meaningfully naked by BDCC's own standard (the same one its pawn reactions use): private parts that are not covered. Partial clothing is fine.
func isPlayerExposed() -> bool:
	return GM.pc.getExposedPrivates().size() > 0

# Unable to dress: arms bound or hands blocked, or nothing loose to put on.
func canPlayerDress() -> bool:
	if(GM.pc.hasBlockedHands() || GM.pc.hasBoundArms()):
		return false
	for item in GM.pc.getInventory().getItems():
		if([InventorySlot.Body, InventorySlot.UnderwearTop, InventorySlot.UnderwearBottom].has(item.getClothingSlotSafe())):
			return true
	return false

# True when nothing stops a guard from stopping the player: no scene, interaction, slavery, restraint of location or dungeon in the way.
func isSafeForEnforcement() -> bool:
	if(!isSecurityReady() || GM.main.isInDungeon() || GM.main.PS != null || GM.main.IS.areInteractionsDisabled()):
		return false
	if(!GM.main.playerCanBeInterrupted() || !GM.main.canShowPawns() || getBlockedReason() != ""):
		return false
	var pcPawn = GM.main.IS.getPawn("pc")
	return pcPawn != null && pcPawn.canBeInterrupted()

# One guard and the player: the pair a meeting is about. Returns [guardPawn, playerPawn] or [].
func pickGuardAndPlayer(pawn1, pawn2) -> Array:
	if(pawn1 == null || pawn2 == null):
		return []
	if(pawn2.isPlayer() && isGuardPawn(pawn1)):
		return [pawn1, pawn2]
	if(pawn1.isPlayer() && isGuardPawn(pawn2)):
		return [pawn2, pawn1]
	return []

# What this guard does about the player right now. Returns {} (nothing) or {"kind": "search" | "violent" | "severe" | "nudity_warn" | "nudity_escalate", "guard": ID}.
func evaluateGuardEncounter(guardPawn, pcPawn) -> Dictionary:
	if(!isSecurityReady() || !isGuardPawn(guardPawn) || pcPawn == null || !guardPawn.canBeInterrupted() || !isSafeForEnforcement()):
		return {}
	var locationID:String = guardPawn.getLocation()
	if(pcPawn.getLocation() != locationID):
		return {}
	var guardID:String = guardPawn.charID
	var security = getSecurity()
	var now:int = getSecurityNow()
	var backup:bool = false
	for other in getFreeGuards(locationID):
		if(other.charID != guardID):
			backup = true
	var ctx:Dictionary = {
		"now": now, "day": GM.main.getDays(), "guard": guardID, "attitude": getGuardAttitude(guardID), "leniency": getGuardLeniency(guardID),
		"fear": getGuardFear(guardID), "backup": backup, "exposed": isPlayerExposed(), "canDress": canPlayerDress(),
		"exemptPlace": isNudityExemptPlace(locationID, GM.pc.getCellLocation()),
	}
	var decision:Dictionary = security.decide(ctx, [nextRoll(), nextRoll()])
	match decision["action"]:
		"confront":
			return {"kind": decision["kind"], "guard": guardID}
		"warn_nudity":
			return {"kind": "nudity_warn", "guard": guardID}
		"escalate_nudity":
			return {"kind": "nudity_escalate", "guard": guardID}
		"search":
			return {"kind": "search", "guard": guardID}
	return {}

# Every ten in-game minutes: decay on a new day, drop a confrontation that no longer exists, the random cell search once a day, and guards in the player's room.
func onSecurityTick() -> void:
	if(!isSecurityReady() || GM.main.isInDungeon()):
		return
	var security = getSecurity()
	var now:int = getSecurityNow()
	var day:int = GM.main.getDays()
	var _decay:float = security.advanceDay(day)
	var exists:bool = false
	for interaction in GM.main.IS.interactions:
		if(interaction.id == "GuardEnforcement" && !interaction.wasDeleted):
			exists = true
	var _dropped:bool = security.dropStaleEnforcement(now, exists)
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	var bucket:int = day * 144 + int(GM.main.getTime() / 600)
	if(extender.securityBucket == bucket):
		return
	extender.securityBucket = bucket
	# The player covered up: the warning is done with
	if(!security.getWarning(now).empty() && !isPlayerExposed()):
		security.clearWarning()
	runCellSearchIfDue(day, now)
	var pcPawn = GM.main.IS.getPawn("pc")
	if(pcPawn == null || security.isActive()):
		return
	for guardPawn in getFreeGuards(pcPawn.getLocation()):
		var decision:Dictionary = evaluateGuardEncounter(guardPawn, pcPawn)
		if(!decision.empty()):
			GM.main.IS.startInteraction("GuardEnforcement", {"guard": decision["guard"], "inmate": "pc"}, {"kind": decision["kind"]})
			return

# ---- Witnessed offences ----

# The player started a fight with this character. Only a guard who sees it (same room, not busy elsewhere) counts; nobody else, nothing happens.
func recordWitnessedViolence(victimID) -> void:
	if(!isSecurityReady() || !(victimID is String)):
		return
	var witnesses:Array = getGuardWitnesses(GM.pc.getLocation(), [], victimID)
	if(witnesses.empty()):
		return
	var security = getSecurity()
	var day:int = GM.main.getDays()
	var victim = GM.main.getCharacter(victimID)
	var victimIsGuard:bool = victim != null && victim.getCharacterType() == CharacterType.Guard
	var level:String = "violent"
	if(victimIsGuard && security.recordGuardAttack(day) >= 2):
		level = "severe"
	if(security.getAttention() >= 60.0):
		level = "severe"
	var guardID:String = witnesses[0].charID
	for witness in witnesses:
		if(witness.charID == victimID):
			guardID = victimID
	var delta:float = security.recordOffence(level, day)
	var _set:bool = security.setPending(level, guardID, getSecurityNow())
	var line:String = SecurityScript.attentionChangeText(delta, security.getAttention())
	GM.main.addMessage(SecurityScript.colored("A guard saw you start that fight.", "yellow") + (" " + line if line != "" else ""))

# The player forced someone (a FORCED encounter by Milestone 1's classification) and a guard who was not part of it saw. Coerced and unknown encounters never count.
func recordWitnessedForcedSex(interaction) -> void:
	if(!isSecurityReady() || interaction == null):
		return
	var participants:Array = interaction.involvedPawns.values()
	var witnesses:Array = getGuardWitnesses(interaction.getLocation(), participants)
	if(witnesses.empty()):
		return
	var security = getSecurity()
	var delta:float = security.recordOffence("severe", GM.main.getDays())
	var _set:bool = security.setPending("severe", witnesses[0].charID, getSecurityNow())
	var line:String = SecurityScript.attentionChangeText(delta, security.getAttention())
	GM.main.addMessage(SecurityScript.colored("A guard saw what you did.", "red") + (" " + line if line != "" else ""))

# ---- Confrontation bookkeeping (called by the GuardEnforcement interaction) ----

func onEnforcementStarted(kind:String, guardID:String) -> void:
	var security = getSecurity()
	var now:int = getSecurityNow()
	security.beginEnforcement(now)
	if(kind == "nudity_warn"):
		security.issueNudityWarning(guardID, now)
	if(kind == "search"):
		security.markSearch(GM.main.getDays(), now, true)

func onEnforcementEnded(resisted:bool) -> void:
	if(!isSecurityReady()):
		return
	getSecurity().endEnforcement(getSecurityNow(), resisted)

# The player chose to resist. Returns the message for the attention change.
func onEnforcementResisted() -> String:
	var security = getSecurity()
	var delta:float = security.recordResistance(GM.main.getDays())
	return SecurityScript.attentionChangeText(delta, security.getAttention())

func onEnforcementWon() -> String:
	var security = getSecurity()
	var delta:float = security.recordWonAgainstGuard(GM.main.getDays())
	security.clearPending()
	return SecurityScript.attentionChangeText(delta, security.getAttention())

# ---- Searching ----

func looseItemEntry(item) -> Dictionary:
	return {"key": item.uniqueID, "name": item.getVisibleName(), "amount": item.getAmount(), "illegal": item.hasTag(ItemTag.Illegal), "protected": item.isImportant() || item.isPersistent()}

func hiddenRecordEntry(record:Dictionary) -> Dictionary:
	var ref = GlobalRegistry.getItemRef(record["id"])
	if(ref == null):
		return {"key": record["uniqueID"], "name": str(record["id"]), "amount": 1, "illegal": false, "protected": true}
	return {"key": record["uniqueID"], "name": ref.getVisibleName(), "amount": int(record["data"].get("amount", 1)), "illegal": ref.hasTag(ItemTag.Illegal), "protected": ref.isImportant() || ref.isPersistent()}

# Searches what the player carries (loose items only: worn clothes and restraints are not touched). Confiscates BDCC's contraband (ItemTag.Illegal),
# never important or persistent items, charges a fine of 1 to 3 credits (never more than the player has) and raises attention.
# harshness: 0 complied, 1 gave in after resisting, 2 beaten after resisting. Returns {"found": bool, "taken": Array, "fine": int, "message": String}.
func performPersonalSearch(guardID:String, harshness:int) -> Dictionary:
	var guardName:String = characterName(guardID)
	var inventory = GM.pc.getInventory()
	var entries:Array = []
	for item in inventory.getItems():
		entries.append(looseItemEntry(item))
	var taken:Array = SearchesScript.selectConfiscations(entries)
	var security = getSecurity()
	var day:int = GM.main.getDays()
	security.markSearch(day, getSecurityNow(), false)
	if(taken.empty()):
		var emptyText:String = SearchesScript.personalSearchMessage(guardName, taken, 0, "")
		security.setReport("A guard searched you and found nothing.")
		return {"found": false, "taken": taken, "fine": 0, "message": emptyText}
	for entry in taken:
		var item = inventory.getItemByUniqueID(entry["key"])
		if(item != null):
			var _removed = inventory.removeItem(item)
	var fine:int = SecurityScript.fineFor(taken.size(), security.recentContrabandCount(day), harshness, GM.pc.getCredits())
	if(fine > 0):
		GM.pc.addCredits(-fine)
	var delta:float = security.recordOffence("contraband", day)
	var attentionLine:String = SecurityScript.attentionChangeText(delta, security.getAttention())
	var text:String = SearchesScript.personalSearchMessage(guardName, taken, fine, attentionLine)
	security.setReport("A guard confiscated " + SearchesScript.describe(taken) + " in a search.")
	return {"found": true, "taken": taken, "fine": fine, "message": text}

# Searches the player's assigned cell: the ordinary stash always, the hidden compartment only when targeted and on a lucky roll.
# Returns {"found": bool, "message": String}. The message is empty when the player has no cell.
func performCellSearch(targeted:bool, hiddenRoll:float) -> Dictionary:
	var stash = getStash()
	var upgrades = getUpgrades()
	var stashEntries:Array = []
	if(stash != null):
		for item in stash.getAllItems():
			stashEntries.append(looseItemEntry(item))
	var hiddenEntries:Array = []
	for record in upgrades.getRecords():
		hiddenEntries.append(hiddenRecordEntry(record))
	var result:Dictionary = SearchesScript.cellSearch(stashEntries, hiddenEntries, targeted, hiddenRoll)
	var security = getSecurity()
	var day:int = GM.main.getDays()
	security.markCellSearch(getSecurityNow())
	var anything:bool = !result["stash"].empty() || !result["hidden"].empty()
	for entry in result["stash"]:
		var item = stash.getItemByUniqueID(entry["key"])
		if(item != null):
			var _removed = stash.removeItem(item)
	for entry in result["hidden"]:
		var _taken:Dictionary = upgrades.take(entry["key"])
	var fine:int = 0
	var attentionLine:String = ""
	if(anything):
		fine = SecurityScript.fineFor(result["stash"].size() + result["hidden"].size(), security.recentContrabandCount(day), 0, GM.pc.getCredits())
		if(fine > 0):
			GM.pc.addCredits(-fine)
		attentionLine = SecurityScript.attentionChangeText(security.recordOffence("contraband", day), security.getAttention())
	var text:String = SearchesScript.cellSearchMessage(result, fine, attentionLine)
	security.setReport("Guards searched your cell" + (" and confiscated contraband." if anything else " and found nothing."))
	return {"found": anything, "message": text}

# Considered once a day, whether or not the player is around. Only the player's own assigned cell, and only if they have one.
func runCellSearchIfDue(day:int, now:int) -> void:
	if(!getCells().isAssigned("pc")):
		return
	var security = getSecurity()
	var decision:Dictionary = security.decideCellSearch(day, now, 0.0, nextRoll())
	if(!decision["search"]):
		return
	var result:Dictionary = performCellSearch(decision["targeted"], nextRoll())
	GM.main.addMessage(result["message"])

# A nudity fine after a warning was ignored: 1 credit at most, and the warning is cleared.
func applyNudityFine(guardID:String) -> String:
	var security = getSecurity()
	var fine:int = int(min(1, GM.pc.getCredits()))
	if(fine > 0):
		GM.pc.addCredits(-fine)
	security.clearWarning()
	var delta:float = security.recordOffence("minor", GM.main.getDays())
	var text:String = SecurityScript.colored(characterName(guardID) + " fines you for indecency.", "red")
	if(fine > 0):
		text += " " + SecurityScript.colored(str(fine) + " credit taken.", "red")
	var line:String = SecurityScript.attentionChangeText(delta, security.getAttention())
	return text + (" " + line if line != "" else "")

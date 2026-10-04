extends Module
class_name SandboxOverhaulModule

const ExtenderScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const ConversationScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")

func _init():
	id = "SandboxOverhaulModule"
	author = "Sam"
	
	gameExtenders = [
		"res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd",
	]

	scenes = [
		"res://Modules/SandboxOverhaulModule/Scenes/CellDirectoryScene.gd",
	]

	worldEdits = [
		"res://Modules/SandboxOverhaulModule/WorldEdits/CellsWorldEdit.gd",
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

# Cell service. Do not cache it across games; call this each time.
static func getCells():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getCells()

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

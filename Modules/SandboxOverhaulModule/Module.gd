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
const NpcJobsScript = preload("res://Modules/SandboxOverhaulModule/Work/NpcJobs.gd")
const PopulationScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const CellLayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const WorkEventGameScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEventGame.gd")
const WorkEventsScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEvents.gd")
const SignedBarScript = preload("res://Modules/SandboxOverhaulModule/UI/SignedBar.gd")
const DailyRoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const CellHookScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellRoomHook.gd")
const CellRoomsScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellRooms.gd")
const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const GANG_TASKS = ["res://Modules/SandboxOverhaulModule/Gangs/GangHangoutTask0.gd", "res://Modules/SandboxOverhaulModule/Gangs/GangHangoutTask1.gd", "res://Modules/SandboxOverhaulModule/Gangs/GangHangoutTask2.gd", "res://Modules/SandboxOverhaulModule/Gangs/GangHangoutTask3.gd"]
const ENFORCEMENT_INTERACTION = "res://Modules/SandboxOverhaulModule/Interactions/GuardEnforcement.gd"
const HELP_REQUEST_INTERACTION = "res://Modules/SandboxOverhaulModule/Interactions/HelpRequest.gd"
const HelpRequestsScript = preload("res://Modules/SandboxOverhaulModule/Interactions/HelpRequests.gd")

func _init():
	id = "SandboxOverhaulModule"
	author = "Sam"
	
	gameExtenders = [
		"res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd",
	]

	scenes = [
		"res://Modules/SandboxOverhaulModule/Scenes/JobBoardScene.gd",
		"res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd",
		"res://Modules/SandboxOverhaulModule/Scenes/CellUpgradesScene.gd",
		"res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd",
	]

	worldEdits = [
		"res://Modules/SandboxOverhaulModule/WorldEdits/CellsWorldEdit.gd",
		"res://Modules/SandboxOverhaulModule/WorldEdits/WorkWorldEdit.gd",
		"res://Modules/SandboxOverhaulModule/WorldEdits/GangHangoutWorldEdit.gd",
		"res://Modules/SandboxOverhaulModule/WorldEdits/PopulationBootstrapWorldEdit.gd", # last: it needs the cells and hangouts the other edits build
	]

	quests = [
		"res://Modules/SandboxOverhaulModule/Quests/GangAssignmentQuest.gd",
		"res://Modules/SandboxOverhaulModule/Quests/GangAssignmentDoneQuest.gd",
	]

	statusEffects = [
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxArmInjury.gd",
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxLegInjury.gd",
		"res://Modules/SandboxOverhaulModule/StatusEffects/SandboxBodyTrauma.gd",
	]

# Interactions cannot be listed in a module, so the guard confrontation registers itself once everything else is registered.
func postInit():
	GlobalRegistry.registerInteraction(ENFORCEMENT_INTERACTION)
	GlobalRegistry.registerInteraction(HELP_REQUEST_INTERACTION)
	for path in GANG_TASKS:
		GlobalRegistry.registerGlobalTask(path)

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

# Gang services. Do not cache them across games; call these each time.
static func getGangs():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getGangs()

static func getNpcJobs():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getNpcJobs()

static func getGangAffairs():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getGangAffairs()

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
	GangGameScript.onFightResult(wonID, lostID)
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

# An NPC the player attacked gave up before any fight (GenericAttack's surrender choice, which an NPC makes from fear or a poor chance). The player has beaten them for every gang purpose.
func onNpcSurrender(npcID) -> void:
	if(!isMainReady() || !(npcID is String) || npcID == "pc"):
		return
	GangGameScript.onFightResult("pc", npcID)

# The player started an ordinary, unprovoked fight with this NPC.
func onUnprovokedAttack(npcID) -> void:
	var _u:Dictionary = runCombatOutcome(npcID, CombatScript.UNPROVOKED)
	recordWitnessedViolence(npcID)
	GangGameScript.onPlayerAttack(npcID)

# Called by FightScene.sandboxFightEnded when the player ends a fight. Only Fight Club arena fights are consensual; every other scene
# fight is ignored here (interaction fights are handled by onFightAftermath, scripted fights are left alone). The enemy surrendering
# is a win ("win" state) and the player submitting a loss ("lost" state), so the submitter does not change the arena result.
func onFightSceneEnded(enemyID, battleState, _submitter, battleName) -> void:
	if(battleName != "arenafight" || !(enemyID is String)):
		return
	var _c:Dictionary = runCombatOutcome(enemyID, CombatScript.CONSENSUAL_WIN if battleState == "win" else CombatScript.CONSENSUAL_LOSS)

# What the quest log shows for the player's gang assignment: archived false for the accepted job, true for the latest reported one. {"visible", "title", "lines"}.
func getGangTaskView(archived:bool) -> Dictionary:
	return GangGameScript.taskDoneView() if archived else GangGameScript.taskView()

func getAttackMultiplier(npcID) -> float:
	return getCombat().attackMultiplier(npcID) * GangGameScript.protectionMultiplier(npcID)

func getDefeatPunishMultiplier(kind) -> float:
	return CombatScript.defeatPunishMultiplier(kind)

# Text for the reputation screen.
func getReputationText() -> String:
	return getCombat().describeReputation()

# Draws Combat Reputation and Defiance as two signed bars (-100..+100, zero in the middle) on the current screen. Returns the two controls.
func addReputationBars() -> Array:
	var bars:Array = []
	if(!isMainReady() || GM.ui == null):
		return bars
	var combat = getCombat()
	var combatValue:float = combat.getCombatReputation()
	var defianceValue:float = combat.getDefiance()
	var combatBar = SignedBarScript.new()
	combatBar.setup("Combat Reputation", combatValue, CombatScript.getCombatBand(combatValue), CombatScript.DESCRIPTION_COMBAT, "How capable and dangerous the prison believes you are in a fight. Zero is unproven; it moves with the fights you win, lose and avoid.")
	var defianceBar = SignedBarScript.new()
	defianceBar.setup("Defiance", defianceValue, CombatScript.getDefianceBand(defianceValue), CombatScript.DESCRIPTION_DEFIANCE, "How willing the prison believes you are to resist. It is neither good nor bad: it changes how guards and inmates treat you.")
	GM.ui.addCustomControl("sandbox_rep_combat", combatBar)
	GM.ui.addCustomControl("sandbox_rep_defiance", defianceBar)
	bars.append(combatBar)
	bars.append(defianceBar)
	return bars

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
	var entries:Array = getEligibleCellEntries()
	var placed:int = getCells().ensureAssigned(entries)
	var _added:Array = ensureCellRooms(null, true, entries)
	return placed

# ---- Physical cells (see Prison/CellLayout.gd and CellRooms.gd) ----

# The world and counts the cell rooms were last built for, so the check is cheap when nothing changed.
var cellRoomsKey:String = ""

# Builds any cell room the prison needs and does not have yet. world: defaults to the running world; wire: connect new rooms to the map (needed while the game runs).
# Returns the IDs of the rooms added.
func ensureCellRooms(world = null, wire:bool = false, entries = null) -> Array:
	if(world == null):
		world = GM.world if (GM != null && GM.get("world") != null && is_instance_valid(GM.world)) else null
	if(world == null || GM.main == null || !is_instance_valid(GM.main)):
		return []
	if(entries == null):
		entries = getEligibleCellEntries()
	var counts:Dictionary = CellRoomsScript.wantedCounts(entries, getCells())
	var key:String = str(world.get_instance_id()) + JSON.print(counts, "", true)
	if(key == cellRoomsKey):
		return []
	var added:Array = CellRoomsScript.ensureRooms(world, counts, getCellHook(world), wire || CellRoomsScript.transitionsBuilt(world))
	cellRoomsKey = key
	return added

# The node that receives the cell rooms' onPreEnter signal (see Prison/CellRoomHook.gd): one per map, added to it. A stand-in world that is not a node gets the module itself.
func getCellHook(world):
	if(!(world is Node)):
		return self
	var hook = world.get_node_or_null("SandboxCellHook")
	if(hook == null):
		hook = CellHookScript.new()
		hook.name = "SandboxCellHook"
		hook.module = self
		world.add_child(hook)
	return hook

# Signal handler for a cell room's onPreEnter: the room header names who lives there; a cell that is not the player's gets a plain description.
func onCellRoomPreEnter(room) -> void:
	var info:Dictionary = CellLayoutScript.parse(room.roomID)
	if(info.empty() || !isMainReady()):
		return
	var occupants:Array = getCells().getOccupants(info["block"], info["cell"])
	var playerLives:bool = occupants.has("pc")
	var names:Array = []
	for occupant in occupants:
		if(occupant != "pc"):
			names.append(characterName(occupant))
	room.roomName = CellLayoutScript.label(info["block"], info["cell"]) # short and fixed: the sidebar title never depends on a name
	if(!playerLives):
		room.roomDescription = CellRoomsScript.baseDescription(info["block"], info["cell"])
	room.roomDescription += "\n\n" + CellRoomsScript.residentsLine(names, playerLives)

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
	return theChar.isSlaveToPlayer() || theChar.hasEnslaveQuest() || GM.main.RS.hasSpecialRelationshipID(characterID, "SoftSlavery") || getGangs().isCaptive(characterID) # captives and a gang's slaves are away at night

# Home or away for tonight, "" outside the character's night or without a cell. A recorded state for tonight wins; without one it is worked out
# now: a pawn that is still out, or a condition that keeps them elsewhere, means away; an inmate who is simply not spawned is assumed home.
func getAttendance(characterID) -> String:
	if(GM.main == null || !is_instance_valid(GM.main) || characterID == "pc"):
		return ""
	var theCells = getCells()
	var now:int = GM.main.getTime()
	if(!theCells.isAssigned(characterID) || !CellsScript.isNight(characterID, now)):
		return ""
	var pawn = GM.main.IS.getPawn(characterID)
	if(pawn != null):
		# Home only when they are physically in their own cell. Anywhere else, the hall outside included, is away.
		return "home" if pawn.getLocation() == homeRoomOf(characterID) else "away"
	var recorded:String = theCells.getPresence(characterID, CellsScript.nightId(characterID, now, GM.main.getDays()))
	if(recorded != ""):
		return recorded
	if(isKeptElsewhere(characterID)):
		return "away"
	return "home"

func recordAttendance(characterID, presence:String) -> void:
	var night:int = CellsScript.nightId(characterID, GM.main.getTime(), GM.main.getDays())
	var theCells = getCells()
	if(theCells.getPresence(characterID, night) != presence):
		var _ok:bool = theCells.setPresence(characterID, night, presence)

# Records who is home and who is away for the night. Nobody is moved, sent or removed here any more: the population director walks every inmate to their cell with their daily plan, and an
# inmate is home only once they are physically in their own cell. A pawn that is busy or still on the way is away, an inmate who has no pawn is home unless something keeps them elsewhere.
# Attendance of the previous night is dropped. Returns {"despawned": [], "walking": [], "deferred": [], "home": [], "away": []} (despawned is always empty now).
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
	for characterID in theCells.getAssignedIDs():
		if(characterID == "pc" || !CellsScript.isNight(characterID, now)):
			continue
		var pawn = IS.getPawn(characterID)
		var presence:String = "home"
		if(pawn != null):
			if(pawn.getLocation() == homeRoomOf(characterID)):
				presence = "home"
			else:
				presence = "away"
				if(isPawnBlocked(pawn)):
					result["deferred"].append(characterID)
				else:
					result["walking"].append(characterID)
		elif(isKeptElsewhere(characterID)):
			presence = "away"
		recordAttendance(characterID, presence)
		result[presence].append(characterID)
	return result

# The room ID of the character's cell ("" without one).
func homeRoomOf(characterID) -> String:
	var entry:Dictionary = getCells().getCell(characterID)
	if(entry.empty()):
		return ""
	return CellLayoutScript.roomID(entry["block"], entry["cell"])

# ---- The living prison (see Prison/PopulationDirector.gd) ----

# Called by the extender's pcProcessTime hook. The director decides by itself whether anything is due (ten-minute buckets and room changes).
func onPopulationTick() -> void:
	if(!isMainReady()):
		return
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	var _summary:Dictionary = PopulationScript.tick(self, extender.director)

# Called once when a game is loaded or started, after the map exists and before the player can see it (see WorldEdits/PopulationBootstrapWorldEdit.gd): assigns cells, builds the cell rooms,
# and puts every inmate where today's plan has them (see PopulationDirector.bootstrap). Returns how many inmates were placed.
func bootstrapPopulation(world) -> int:
	if(!isMainReady() || GM.world != world || GM.main.IS == null):
		return 0
	var entries:Array = getEligibleCellEntries()
	var _placed:int = getCells().ensureAssigned(entries)
	var _added:Array = ensureCellRooms(world, false, entries)
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	var summary:Dictionary = PopulationScript.bootstrap(self, extender.director)
	return summary["hydrated"].size() + summary["moved"].size()

# Everyone the director places: the inmates with a home cell, never the player.
func getDirectedInmateIDs() -> Array:
	var ids:Array = []
	for entry in getEligibleCellEntries():
		if(entry[0] != "pc"):
			ids.append(entry[0])
	ids.sort()
	return ids

# Held somewhere else by something with priority over the prison's routine: slavery, a quest, a captor.
func isHeldAway(characterID) -> bool:
	return isKeptElsewhere(characterID) || getGangs().isDetained(characterID)

# Can this inmate go to work today? Not when held away, hurt (a moderate or severe injury) or on one of their rare sick days.
func isAvailableForWork(characterID, day:int) -> bool:
	if(isHeldAway(characterID)):
		return false
	for type in InjuriesScript.TYPES:
		if(getInjuries().getSeverity(characterID, type) >= InjuriesScript.MODERATE):
			return false
	return ScheduleScript.hashOf(characterID, "sick" + str(day)) % 100 >= PopulationScript.SICK_PERCENT

# Used by InteractionSystem.trySpawnPawn: staff and inmates are only added while their kind is under its share of the pawn limit.
func canSpawnPawnType(pawnTypeID) -> bool:
	if(!isMainReady() || GM.main.IS == null):
		return true
	if(pawnTypeID == CharacterType.Inmate):
		# Every inmate already has a pawn for good; BDCC may still bring new prisoners, up to a population that stays cheap to simulate and to draw.
		return getDirectedInmateIDs().size() < POPULATION_CAP
	var kind:String = ""
	if(pawnTypeID == CharacterType.Guard):
		kind = "guard"
	elif(pawnTypeID == CharacterType.Nurse):
		kind = "nurse"
	elif(pawnTypeID == CharacterType.Engineer):
		kind = "engineer"
	else:
		return true
	var counts:Dictionary = PopulationScript.countByType(GM.main.IS)
	var budget:Dictionary = ScheduleScript.budgets(GM.main.IS.getMaxPawnCount(), getDirectedInmateIDs().size())
	return counts[kind] < budget[kind]

# The most inmates the prison takes in: all of them are simulated and drawn all the time, so this keeps the cost bounded (60 were measured).
const POPULATION_CAP = 45

# Whether a pawn is kept from one day to the next (see InteractionSystem.deleteAllNonImportantPawns): the prison's inmates and staff are, so a new day never wipes the prison.
func keepPawnAcrossDays(characterID) -> bool:
	if(!isMainReady() || characterID == "pc"):
		return false
	var theChar = GM.main.getCharacter(characterID)
	if(theChar == null):
		return false
	var kind = theChar.getCharacterType()
	return kind == CharacterType.Inmate || kind == CharacterType.Guard || kind == CharacterType.Nurse || kind == CharacterType.Engineer

# The map badge of a character's gang (see GangGame.badgeFor): {} for no badge.
func getGangBadge(characterID) -> Dictionary:
	if(!isMainReady()):
		return {}
	return GangGameScript.badgeFor(characterID)

# The name of the gang an inmate meets at its hangout ("" when they are in none), for the text "hanging out with Ironhand".
func hangoutLabel(characterID) -> String:
	var gangs = getGangs()
	var gid:String = gangs.gangOf(characterID)
	return gangs.gangName(gid) if gid != "" else ""

# True: the inmates and staff exist all the time, so BDCC's morning warm-up (which walks every pawn for a couple of hours) must not run over them.
func keepsPrisonersPersistent() -> bool:
	return true

# What a pawn on its routine is doing, in BDCC's text with name placeholders. Built from the real activity (kind, whether the pawn has arrived), see GoalSandboxRoutine.
func getRoutineText(kind:String, here:String, target:String, gangName:String) -> String:
	var info:Dictionary = CellLayoutScript.parse(target)
	var roomName:String = ""
	if(GM.world != null && is_instance_valid(GM.world)):
		var room = GM.world.getRoomByID(target)
		roomName = room.roomName if room != null else ""
	var placeText:String = DailyRoutineScript.placeName(kind, target, roomName)
	return DailyRoutineScript.describe(kind, here, target, placeText, int(info.get("cell", 0)), gangName)

# Used by InteractionSystem.trySpawnPawn so an inmate who should still be in their cell is not picked for a random appearance.
func canSpawnPawn(characterID) -> bool:
	if(GM.main != null && is_instance_valid(GM.main) && getGangs().isDetained(characterID)):
		return false
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

# ---- Fights between other people: taking a side or breaking it up (see CORE_PATCHES.md) ----

# Called by GenericAttack when a fight between two other people starts: somebody bound to the player may ask them for help (see Interactions/HelpRequests.gd).
func onNpcFightStarted(fight) -> void:
	if(!isMainReady()):
		return
	var _asker:String = HelpRequestsScript.onFightStarted(self, fight)

const BREAK_UP_COST = 10 # stamina

# What the player can do about two other people fighting, offered by the Look around screen. Only for the player, only while neither fighter is the player and only for
# a fight that has not been decided (or was just decided, to stop what comes after). Returns interrupt actions.
func getFightInterruptActions(interaction, pawn) -> Array:
	var actions:Array = []
	if(pawn == null || !pawn.isPlayer() || interaction == null || interaction.wasDeleted || !isMainReady()):
		return actions
	var starter:String = interaction.getRoleID("starter")
	var reacter:String = interaction.getRoleID("reacter")
	if(starter == "" || reacter == "" || starter == "pc" || reacter == "pc"):
		return actions
	if(pawn.getChar() == null || pawn.getChar().getStamina() <= 0 || pawn.getInteraction() == null || pawn.getInteraction().id != "AloneInteraction"):
		return actions
	var state:String = interaction.getState()
	if(state == ""):
		actions.append({"id": "join_starter", "name": "Help " + characterName(starter), "desc": "Take " + characterName(starter) + "'s side and fight " + characterName(reacter), "score": 0.0, "args": {}})
		actions.append({"id": "join_reacter", "name": "Help " + characterName(reacter), "desc": "Take " + characterName(reacter) + "'s side and fight " + characterName(starter), "score": 0.0, "args": {}})
	if(state == "" || state == "starter_won" || state == "reacter_won"):
		actions.append({"id": "break_up", "name": "Break it up", "desc": "Step between them and try to stop it. Whether they listen depends on how they see you. It costs " + str(BREAK_UP_COST) + " stamina.", "score": 0.0, "args": {}})
	return actions

# The chance that two fighters stop when the player steps in, from how much they fear and respect the player.
func breakUpChance(starterID:String, reacterID:String) -> float:
	var rel = getRelationships()
	var fear:float = (rel.getFeeling(starterID, "pc", "fear") + rel.getFeeling(reacterID, "pc", "fear")) / 2.0
	var respect:float = (rel.getFeeling(starterID, "pc", "respect") + rel.getFeeling(reacterID, "pc", "respect")) / 2.0
	return clamp(0.35 + fear / 100.0 * 0.4 + respect / 100.0 * 0.3 + getCombat().getCombatReputation() / 400.0, 0.15, 0.85)

# Applies the choice. Joining one side ends their fight and starts one between the player and the other fighter (the fight system has no three-way fights); breaking it up
# either ends it or fails and costs stamina.
func doFightInterruptAction(interaction, pawn, actionID) -> void:
	if(pawn == null || !pawn.isPlayer() || interaction == null || interaction.wasDeleted || !isMainReady()):
		return
	var IS = GM.main.IS
	var starter:String = interaction.getRoleID("starter")
	var reacter:String = interaction.getRoleID("reacter")
	if(starter == "" || reacter == "" || starter == "pc" || reacter == "pc"):
		return
	var rel = getRelationships()
	if(str(actionID).begins_with("join_")):
		var ally:String = starter if actionID == "join_starter" else reacter
		var foe:String = reacter if ally == starter else starter
		IS.stopInteraction(interaction)
		var _a1:float = rel.adjustFeeling(ally, "pc", "trust", 6.0)
		var _a2:float = rel.adjustFeeling(ally, "pc", "affection", 4.0)
		var _f1:float = rel.adjustFeeling(foe, "pc", "affection", -6.0)
		var _f2:float = rel.adjustFeeling(foe, "pc", "trust", -4.0)
		GM.main.addMessage("You step in on " + characterName(ally) + "'s side. " + characterName(foe) + " turns on you.")
		GangGameScript.onPlayerAttack(foe)
		IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": foe})
	elif(actionID == "break_up"):
		var chance:float = breakUpChance(starter, reacter)
		pawn.getChar().addStamina(-BREAK_UP_COST)
		if(nextRoll() < chance):
			IS.stopInteraction(interaction)
			for id in [starter, reacter]:
				var other = IS.getPawn(id)
				if(other != null):
					other.afterSocialInteraction()
				var _r:float = rel.adjustFeeling(id, "pc", "respect", 3.0)
			GM.main.addMessage("You step between " + characterName(starter) + " and " + characterName(reacter) + " until they back off.")
		else:
			GM.main.addMessage(characterName(starter) + " and " + characterName(reacter) + " ignore you. You were shoved aside, and it carries on.")

# ---- Other inmates' jobs (see Work/NpcJobs.gd) ----

# "Alec works as a Laundry hand at the laundry." once the player knows it, otherwise "".
func getKnownJobLine(npcID) -> String:
	if(!isMainReady()):
		return ""
	var text:String = getNpcJobs().knownJobText(npcID)
	return "" if text == "" else "[color=" + CellsScript.COLOR_NAME + "]" + characterName(npcID) + "[/color] works as a " + text + "."

# What an inmate says when asked about their work. {"line": say text, "note": text for the player}. Being told is learning it.
func getJobAnswer(npcID) -> Dictionary:
	if(!isMainReady()):
		return {"line": "...", "note": ""}
	var jobs = getNpcJobs()
	if(!jobs.isEmployed(npcID)):
		return {"line": "No job. I get by.", "note": ""}
	var jobID:String = jobs.getJob(npcID)
	var job:Dictionary = EmploymentScript.JOBS[jobID]
	return {"line": "I'm a " + str(job["name"]).to_lower() + ". " + str(job["workplace"]) + ", from about " + EmploymentScript.formatHour(int(job["open"])) + ".", "note": "[color=yellow]Job learned:[/color] " + characterName(npcID) + " works as a " + jobs.knownJobText(npcID) + "." if jobs.isKnown(npcID) else ""}

func learnNpcJob(npcID) -> bool:
	return isMainReady() && getNpcJobs().learn(npcID)

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

# The first time the player is out in the prison with no job and has not seen the board, they are told once where jobs are, and the canteen is marked on the map until
# they have opened the board. Never repeated.
func maybeIntroduceJobs() -> void:
	var employment = getEmployment()
	if(!employment.isIntroPending() || GM.world == null || !is_instance_valid(GM.world)):
		return
	var canteen = GM.world.getRoomByID("hall_canteen")
	var here = GM.world.getRoomByID(GM.pc.getLocation())
	if(canteen == null || here == null || here.getFloorID() != canteen.getFloorID()):
		return
	if(employment.claimIntro()):
		GM.main.addMessage("[color=yellow]Work:[/color] Inmates can earn credits here. You are unemployed. Visit the Job board in the canteen.")
		setBoardMarker(true)

# Puts the canteen marker back after a load or a new map, for a player who has been told but has not opened the board.
func refreshBoardMarker() -> void:
	if(isMainReady()):
		var employment = getEmployment()
		setBoardMarker(!employment.hasSeenBoard() && !employment.isEmployed() && !employment.isIntroPending())

# Called by the extender's pcProcessTime hook: reminders, missed and excused shifts, dismissals.
func onWorkTick() -> void:
	if(!isMainReady() || GM.main.isInDungeon()):
		return
	maybeIntroduceJobs()
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
	var crew:Array = beginShiftCrew(jobID) # who is at the workplace as the shift begins, before any time passes
	GM.pc.addCredits(wage)
	GM.pc.addStamina(-int(EmploymentScript.JOBS[jobID]["stamina"]))
	return {"ok": true, "reason": "", "wage": wage, "balance": GM.pc.getCredits(), "job": jobID, "crew": crew}

# ---- Who is at a workplace ----

# The workers of a job who are standing in its room right now (real pawns, in the workplace).
func presentCoworkers(jobID) -> Array:
	var result:Array = []
	if(!isMainReady() || !EmploymentScript.isValidJob(jobID) || GM.main.IS == null):
		return result
	var room:String = str(EmploymentScript.JOBS[jobID]["room"])
	var day:int = GM.main.getDays()
	for characterID in getNpcJobs().workers(jobID):
		if(isHeldAway(characterID) || getGangs().isCaptive(characterID) || !isAvailableForWork(characterID, day)):
			continue # somebody who is kept, hurt or off sick is not part of the crew even if they are standing in the room
		var pawn = GM.main.IS.getPawn(characterID)
		if(pawn != null && pawn.getLocation() == room):
			result.append(characterID)
	result.sort()
	return result

# A guard who is standing in the workplace, or "".
func presentSupervisor(jobID) -> String:
	if(!isMainReady() || !EmploymentScript.isValidJob(jobID) || GM.main.IS == null):
		return ""
	var guards:Array = []
	for pawn in GM.main.IS.getPawnsAt(str(EmploymentScript.JOBS[jobID]["room"])):
		if(pawn != null && !pawn.isPlayer() && pawn.isGuard()):
			guards.append(pawn.charID)
	guards.sort()
	return guards[0] if !guards.empty() else ""

# What the shift screen says about who is working there.
func getCrewText(jobID) -> String:
	var present:Array = presentCoworkers(jobID)
	if(present.empty()):
		return "Nobody else is working here at the moment."
	var names:Array = []
	for characterID in present:
		names.append(characterName(characterID))
	return "Working here now: " + CellLayoutScript.joinNames(names) + "."

# The player's shift begins: the coworkers who are at the workplace stay and work it with the player, then pack up (see PopulationDirector.crewKind).
func beginShiftCrew(jobID) -> Array:
	var present:Array = presentCoworkers(jobID)
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	if(extender == null || present.empty()):
		return present
	var _state = extender.getState() # applies the new-game reset of the director's memory
	var crews:Dictionary = extender.director.get("crews", {})
	crews[str(jobID)] = {"ids": present.duplicate(), "end": PopulationScript.clockOf(GM.main.getDays(), GM.main.getTime()) + int(EmploymentScript.JOBS[jobID]["hours"]) * 3600}
	extender.director["crews"] = crews
	return present

# ---- Workplace events (see Work/WorkEvents.gd) ----

# Called when a shift has just been paid: may start an event. Returns the event, or {}.
func rollWorkEvent(jobID, rolls:Array = []) -> Dictionary:
	if(!isMainReady()):
		return {}
	return WorkEventGameScript.rollAfterShift(self, str(jobID), GM.main.getDays(), rolls)

func getPendingWorkEvent() -> Dictionary:
	if(!isMainReady()):
		return {}
	return getState().workplace["pending"].duplicate(true)

# What the player is shown for an event: {"text", "choices": [{"id", "label", "tooltip"}]}.
func getWorkEventView(event:Dictionary) -> Dictionary:
	if(event.empty()):
		return {"text": "", "choices": []}
	return {"text": WorkEventsScript.describe(event, WorkEventGameScript.names(self, event)), "choices": WorkEventsScript.choices(event)}

# Applies the player's choice once. Returns {"ok", "text", "fight": enemy ID or "", "event"}.
func resolveWorkEvent(choiceID, rolls:Array = []) -> Dictionary:
	if(!isMainReady()):
		return {"ok": false, "text": "", "fight": ""}
	return WorkEventGameScript.resolve(self, str(choiceID), rolls)

func onWorkFightEnded(event:Dictionary, enemyID, result:Array) -> void:
	if(!isMainReady() || !(enemyID is String)):
		return
	var won:bool = result.size() > 0 && result[0] == "win"
	var _c:Dictionary = runCombatOutcome(enemyID, CombatScript.WIN if won else CombatScript.LOSS, result[2] if result.size() > 2 else -1.0)
	GangGameScript.onFightResult("pc" if won else enemyID, enemyID if won else "pc")
	WorkEventGameScript.onFightEnded(self, event, enemyID, result)

# The only way to do paid work at a workplace: the same check everywhere (mining button, workplace actions). {"ok", "reason"}.
func explainShift(jobID) -> Dictionary:
	if(!isMainReady()):
		return {"ok": false, "reason": "Not in a game."}
	var check:Dictionary = getEmployment().explainShift(jobID, GM.main.getDays(), GM.main.getTime())
	if(check["ok"] && GM.pc.getStamina() <= 0):
		return {"ok": false, "reason": "You are too tired to work. Rest first."}
	return check

# Called by the mines handler event instead of the vanilla "Work" button (see CORE_PATCHES.md): there is exactly one way to work the mines for pay, and it is the mine
# worker's shift. Returns {"enabled": bool, "label": text, "tooltip": text}.
func getMiningWorkButton() -> Dictionary:
	var check:Dictionary = explainShift("mining")
	if(check["ok"]):
		return {"enabled": true, "label": "Start mining shift", "tooltip": "Work about " + str(EmploymentScript.JOBS["mining"]["hours"]) + " hours for " + str(EmploymentScript.JOBS["mining"]["wage"]) + " credits. It costs " + str(EmploymentScript.JOBS["mining"]["stamina"]) + " stamina."}
	return {"enabled": false, "label": "Start mining shift", "tooltip": check["reason"]}

# The player opened the job board.
func onJobBoardSeen() -> void:
	if(!isMainReady()):
		return
	getEmployment().markBoardSeen()
	setBoardMarker(false)

# Shows or hides the map marker on the canteen (the existing mission marker) until the board has been visited.
func setBoardMarker(visible:bool) -> void:
	if(GM.world == null || !is_instance_valid(GM.world)):
		return
	var room = GM.world.getRoomByID("hall_canteen")
	if(room != null && room.has_method("setMissionSpriteVisible")):
		room.setMissionSpriteVisible(visible)

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

# ---- Gangs (see CORE_PATCHES.md and Gangs/) ----

# Every ten in-game minutes: set up, tidy, captives, jobs, the day's upkeep and any gang incident. All the rules live in GangGame.
func onGangTick() -> void:
	GangGameScript.tick()

extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/SecurityBootTest.tscn
# Real path: the real extender, module, MainScene clock and messages, InteractionSystem pawns (real CharacterPawn objects), the real GuardEnforcement
# interaction started through the InteractionSystem, real inventory and items, the real stash, real save/load. The world simulation inside processTime
# and the map are absent. Exits with code 1 on failure.

const SecurityScript = preload("res://Modules/SandboxOverhaulModule/Security/Security.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")

var failures = 0

class GuardNpc extends DynamicCharacter:
	func getCharacterType():
		return CharacterType.Guard

class InmateNpc extends DynamicCharacter:
	func getCharacterType():
		return CharacterType.Inmate

# The real MainScene with the world simulation cut out of processTime.
class TestMain extends "res://Game/MainScene.gd":
	var holder = null # when set, generated characters become children of this node (the real GuardGenerator needs a live MainScene)
	var generated = 0
	func processTime(_seconds):
		timeOfDay += int(round(_seconds))
	func addDynamicCharacter(character, printDebug = true):
		if(holder != null):
			holder.add_child(character)
			return
		.addDynamicCharacter(character, printDebug)
	func generateCharacterID(prefix = "dynamicnpc"):
		generated += 1
		return prefix + "gen" + str(generated)

class FakeWorldScene:
	var sceneID = "WorldScene"
	func supportsShowingPawns():
		return true
	func supportsSexEngine():
		return true
	func hasCharacter(_id):
		return false

class FakeOtherScene:
	var sceneID = "SomeStoryScene"
	func supportsShowingPawns():
		return false
	func supportsSexEngine():
		return false
	func hasCharacter(_id):
		return false

class FakeBusy:
	var id = "Talking"
	var goal = null
	func canCharIDBeInterrupted(_id):
		return false

class FakeStocks:
	var id = "InStocks"
	var goal = null
	func canCharIDBeInterrupted(_id):
		return false

class FakeSexInteraction:
	var id = "Talking"
	var involvedPawns = {"dom": "pc", "sub": "i01"}
	var stateName = "grabbed_about_to_fuck"
	var where = "hall_a"
	func getState():
		return stateName
	func getLocation():
		return where
	func getRoleID(role):
		return involvedPawns.get(role, "")

class FakeSexResult:
	func getAverageDomSatisfaction():
		return 0.5
	func getAverageSubSatisfaction():
		return 0.5

class ProtectedShiv extends "res://Inventory/Items/Weapons/Shiv.gd":
	func isImportant():
		return true

class PersistentBaton extends "res://Inventory/Items/Weapons/StunBaton.gd":
	func isPersistent():
		return true

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

var main = null
var thePlayer = null
var module = null
var IS = null
var pcPawn = null
var worldScene = null

func setTime(hours, minutes = 0, day = 0):
	main.timeOfDay = int(hours * 3600 + minutes * 60)
	main.currentDay = day

func messagesText() -> String:
	return PoolStringArray(main.getMessages()).join("\n")

func addGuard(guardID, loc):
	var c = GuardNpc.new()
	c.id = guardID
	c.name = guardID
	c.npcName = guardID
	add_child(c)
	main.dynamicCharacters[guardID] = c
	main.addDynamicCharacterToPool(guardID, CharacterPool.Guards)
	return addPawn(guardID, loc, CharacterType.Guard)

func addInmate(inmateID, loc):
	var c = InmateNpc.new()
	c.id = inmateID
	c.name = inmateID
	c.npcName = inmateID
	add_child(c)
	main.dynamicCharacters[inmateID] = c
	main.addDynamicCharacterToPool(inmateID, CharacterPool.Inmates)
	return addPawn(inmateID, loc, CharacterType.Inmate)

func addPawn(charID, loc, typeID):
	var p = CharacterPawn.new()
	p.charID = charID
	p.pawnTypeID = typeID
	p.location = loc
	IS.pawns[charID] = p
	if(!IS.pawnsByLoc.has(loc)):
		IS.pawnsByLoc[loc] = {}
	IS.pawnsByLoc[loc][charID] = true
	return p

func moveTo(pawn, loc):
	if(IS.pawnsByLoc.has(pawn.location)):
		IS.pawnsByLoc[pawn.location].erase(pawn.charID)
	pawn.location = loc
	if(!IS.pawnsByLoc.has(loc)):
		IS.pawnsByLoc[loc] = {}
	IS.pawnsByLoc[loc][pawn.charID] = true
	if(pawn.charID == "pc"):
		thePlayer.location = loc

func removePawn(charID):
	var p = IS.pawns.get(charID)
	if(p != null):
		IS.pawnsByLoc[p.location].erase(charID)
	IS.pawns.erase(charID)

func startEnforcement(guardID, kind):
	IS.startInteraction("GuardEnforcement", {"guard": guardID, "inmate": "pc"}, {"kind": kind})
	for interaction in IS.interactions:
		if(interaction.id == "GuardEnforcement" && !interaction.wasDeleted):
			return interaction
	return null

func countItems(uid) -> int:
	var n = 0
	var inv = thePlayer.getInventory()
	for item in inv.getItems():
		if(item.uniqueID == uid):
			n += 1
	for item in inv.getEquippedItems().values():
		if(item.uniqueID == uid):
			n += 1
	var stash = module.getStash()
	if(stash != null):
		for item in stash.getAllItems():
			if(item.uniqueID == uid):
				n += 1
	for record in module.getStoredRecords(true):
		if(record["uniqueID"] == uid):
			n += 1
	return n

func countInteractions(interactionID) -> int:
	var n = 0
	for interaction in IS.interactions:
		if(interaction.id == interactionID && !interaction.wasDeleted):
			n += 1
	return n

func findInteraction(interactionID):
	for interaction in IS.interactions:
		if(interaction.id == interactionID && !interaction.wasDeleted):
			return interaction
	return null

func endAllInteractions():
	for interaction in IS.interactions.duplicate():
		IS.stopInteraction(interaction)

func resetSecurity():
	SandboxOverhaulModule.getState().security = SecurityScript.defaults()
	module.queuedRolls.clear()
	main.clearMessages()

func _ready():
	# If a script error aborts this function the game would idle forever with its log unflushed: quit with a failure code instead.
	get_tree().create_timer(90.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = TestMain.new()
	GM.main = main
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	var eventSystem = EventSystem.new()
	add_child(eventSystem)
	worldScene = FakeWorldScene.new()
	main.sceneStack.append(worldScene)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	check(module != null, "module registered")
	check(GlobalRegistry.getInteractions().has("GuardEnforcement") and GlobalRegistry.createInteraction("GuardEnforcement") != null, "the guard confrontation registers itself with the interaction registry")
	var sec = SandboxOverhaulModule.getSecurity()
	var state = SandboxOverhaulModule.getState()

	# ---- A new game ----
	check(sec.getAttention() == 0.0 and !sec.isActive() and state.security["warning"]["kind"] == "" and state.schema_version == 8, "a new game has attention 0 and nothing pending")
	var screen = module.getSecurityScreenText()
	check(screen.find("0 / 100") != -1 and screen.find("Routine") != -1, "the Security section shows the attention and label: " + screen)

	# ---- The cast ----
	pcPawn = addPawn("pc", "hall_a", CharacterType.Inmate)
	moveTo(pcPawn, "hall_a")
	var g1 = addGuard("g1", "hall_a")
	var g2 = addGuard("g2", "hall_b")
	var inmate = addInmate("i01", "hall_a")
	setTime(10, 0, 5)
	check(module.isGuardPawn(g1) and !module.isGuardPawn(inmate) and !module.isGuardPawn(pcPawn) and !module.isGuardPawn(null), "guards are identified by BDCC's own character type")
	var pair = module.pickGuardAndPlayer(g1, pcPawn)
	check(pair.size() == 2 and pair[0] == g1 and pair[1] == pcPawn and module.pickGuardAndPlayer(pcPawn, g1)[0] == g1 and module.pickGuardAndPlayer(g1, inmate).empty() and module.pickGuardAndPlayer(inmate, pcPawn).empty() and module.pickGuardAndPlayer(g1, g2).empty(), "a meeting is about one guard and the player, nothing else")

	# ---- Witnesses ----
	var here = module.getGuardWitnesses("hall_a")
	check(here.size() == 1 and here[0] == g1 and module.getGuardWitnesses("hall_b").size() == 1 and module.getGuardWitnesses("hall_c").empty(), "witnesses are guards in the same room, nobody elsewhere")
	g1.currentInteraction = FakeBusy.new()
	check(module.getGuardWitnesses("hall_a").empty() and module.getGuardWitnesses("hall_a", [], "g1").size() == 1, "a guard busy with something else sees nothing, unless they are the victim")
	check(module.getFreeGuards("hall_a").empty(), "and cannot act")
	g1.currentInteraction = null
	check(module.getGuardWitnesses("hall_a", ["g1"]).empty(), "participants are excluded")

	# ---- Unwitnessed violence changes nothing ----
	resetSecurity()
	moveTo(pcPawn, "hall_c")
	module.onUnprovokedAttack("i01")
	check(sec.getAttention() == 0.0 and sec.getPending(module.getSecurityNow()).empty() and messagesText().find("saw") == -1, "an attack nobody saw adds no attention and no report")
	module.onUnprovokedAttack("g2")
	check(sec.getAttention() == 0.0 and sec.getPending(module.getSecurityNow()).empty(), "even one on a guard in another room")
	# ---- Witnessed violence ----
	resetSecurity()
	moveTo(pcPawn, "hall_a")
	var repBefore = CombatScript.new(state, SandboxOverhaulModule.getRelationships()).getDefiance()
	module.onUnprovokedAttack("i01")
	var pending = sec.getPending(module.getSecurityNow())
	check(is_equal_approx(sec.getAttention(), 20.0) and pending["kind"] == "violent" and pending["guard"] == "g1", "a guard in the room saw the player start a fight: attention +20, a report waiting")
	check(messagesText().find("A guard saw you start that fight.") != -1 and messagesText().find("yellow") != -1 and messagesText().find("rises by 20") != -1, "one yellow message says so: " + messagesText())
	check(CombatScript.new(state, SandboxOverhaulModule.getRelationships()).getDefiance() <= repBefore, "the Milestone 2 outcome ran as before (Defiance does not rise)")
	# attacking a guard who is busy being talked to: the victim sees it
	resetSecurity()
	g1.currentInteraction = FakeBusy.new()
	module.onUnprovokedAttack("g1")
	check(sec.getPending(module.getSecurityNow())["guard"] == "g1" and is_equal_approx(sec.getAttention(), 20.0), "attacking a guard: the victim is the witness")
	module.onUnprovokedAttack("g1")
	check(sec.getPending(module.getSecurityNow())["kind"] == "severe" and sec.getAttention() > 45.0, "repeated attacks on guards are severe")
	g1.currentInteraction = null
	resetSecurity()
	sec.setAttention(65)
	module.onUnprovokedAttack("i01")
	check(sec.getPending(module.getSecurityNow())["kind"] == "severe", "serious violence while already at High alert is severe")
	# scripted fights and fight scenes do not report anything
	resetSecurity()
	module.onFightSceneEnded("i01", "win", "", "somescriptedfight")
	module.onFightSceneEnded("g1", "lost", "pc", "arenafight")
	check(sec.getAttention() == 0.0 and sec.getPending(module.getSecurityNow()).empty(), "scripted fights and fight club bouts never create reports")

	# ---- Forced encounters ----
	resetSecurity()
	var sexFake = FakeSexInteraction.new()
	sexFake.where = "hall_c"
	var _r1 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(sec.getAttention() == 0.0 and sec.getPending(module.getSecurityNow()).empty(), "a forced encounter nobody saw is nothing")
	sexFake.where = "hall_a"
	var _r2 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(is_equal_approx(sec.getAttention(), 30.0) and sec.getPending(module.getSecurityNow())["kind"] == "severe" and sec.getPending(module.getSecurityNow())["guard"] == "g1" and messagesText().find("A guard saw what you did.") != -1, "a guard who saw a FORCED encounter: severe, attention +30")
	resetSecurity()
	sexFake.involvedPawns = {"dom": "pc", "sub": "g1"}
	var _r3 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(sec.getAttention() == 0.0, "the guard who was part of it is not a witness")
	resetSecurity()
	sexFake.involvedPawns = {"dom": "pc", "sub": "i01"}
	sexFake.id = "PunishInteraction"
	sexFake.stateName = "about_to_sex"
	var _r4 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(sec.getAttention() == 0.0, "a COERCED encounter is not treated as a witnessed crime")
	sexFake.id = "Talking"
	sexFake.stateName = "offered_sex_agreed"
	var _r5 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(sec.getAttention() == 0.0, "consensual sex never is")
	sexFake.stateName = "some_state_nobody_knows"
	var _r6 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(sec.getAttention() == 0.0 and sec.getPending(module.getSecurityNow()).empty(), "UNKNOWN consent without explicit evidence is not a crime")
	sexFake.stateName = "grabbed_about_to_fuck"
	sexFake.involvedPawns = {"dom": "i01", "sub": "pc"}
	var _r7 = module.applySexAftermathAndShouldRunVanilla(sexFake, ["dom", "sub"], FakeSexResult.new())
	check(sec.getAttention() == 0.0, "being the victim is not an offence")

	# ---- Safety: nothing happens in unsafe states ----
	resetSecurity()
	var _p = sec.setPending("violent", "g1", module.getSecurityNow())
	check(module.isSafeForEnforcement() and !module.evaluateGuardEncounter(g1, pcPawn).empty(), "setup: a pending report and a safe moment")
	main.sceneStack.append(FakeOtherScene.new())
	check(!module.isSafeForEnforcement() and module.evaluateGuardEncounter(g1, pcPawn).empty(), "a story or other scene on the stack: nothing")
	main.sceneStack.pop_back()
	pcPawn.currentInteraction = FakeStocks.new()
	check(!module.isSafeForEnforcement() and module.evaluateGuardEncounter(g1, pcPawn).empty(), "in the stocks (or any interaction): nothing")
	pcPawn.currentInteraction = null
	main.PS = load("res://Game/PlayerSlavery/PlayerSlaveryBase.gd").new()
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "serving as a slave: nothing")
	main.PS = null
	g1.currentInteraction = FakeBusy.new()
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "a busy guard: nothing")
	g1.currentInteraction = null
	moveTo(pcPawn, "hall_b")
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "a guard in another room: nothing")
	moveTo(pcPawn, "hall_a")
	sec.beginEnforcement(module.getSecurityNow())
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "a confrontation already running: nothing more")
	sec.endEnforcement(module.getSecurityNow(), false)

	# ---- Low attention: ordinary encounters ----
	resetSecurity()
	setTime(10, 0, 6)
	var stopped = 0
	for _n in range(25):
		module.queuedRolls = [0.5, 0.5]
		if(!module.evaluateGuardEncounter(g1, pcPawn).empty()):
			stopped += 1
	check(stopped == 0, "at attention 0, 25 ordinary meetings with a guard stop nothing")

	# ---- Nudity: warning, cover up, escalation, fine ----
	resetSecurity()
	setTime(10, 0, 7)
	check(module.isPlayerExposed() == (thePlayer.getExposedPrivates().size() > 0), "exposure comes from BDCC's own check")
	var uniform = GlobalRegistry.createItem("inmateuniform")
	thePlayer.getInventory().addItem(uniform)
	var shouldBeExposed = module.isPlayerExposed()
	check(module.canPlayerDress() == true or !shouldBeExposed, "with a loose uniform the player can dress")
	if(!shouldBeExposed):
		print("NOTE: the bare test player is not exposed; nudity checks use a stand-in below")
	check(SandboxOverhaulModule.isNudityExemptPlace("main_shower1", "cellblock_orange_playercell") and SandboxOverhaulModule.isNudityExemptPlace("cellblock_orange_playercell", "cellblock_orange_playercell") and SandboxOverhaulModule.isNudityExemptPlace("medical_shower2", "x") and SandboxOverhaulModule.isNudityExemptPlace("med_lobbymain", "x") and SandboxOverhaulModule.isNudityExemptPlace("MedRoom2", "x") and SandboxOverhaulModule.isNudityExemptPlace("intro_shower", "x") and SandboxOverhaulModule.isNudityExemptPlace("solitary_cell", "x") and SandboxOverhaulModule.isNudityExemptPlace("gym_nearbathroom", "x") and SandboxOverhaulModule.isNudityExemptPlace("cellblock_pink_playercell", "x"), "showers, bathrooms, the medical area, the own cell and solitary are exempt")
	check(!SandboxOverhaulModule.isNudityExemptPlace("hall_checkpoint", "cellblock_orange_playercell") and !SandboxOverhaulModule.isNudityExemptPlace("main_canteen", "x") and !SandboxOverhaulModule.isNudityExemptPlace("cellblock_orange_nearcell", "x") and !SandboxOverhaulModule.isNudityExemptPlace("yard_neargym", "x"), "ordinary public places are not")

	# The real exposure and dressing checks, end to end
	var exposedNow = module.isPlayerExposed()
	check(exposedNow, "the bare test player is exposed by BDCC's own check")
	if(exposedNow):
		module.queuedRolls = [0.0, 0.9]
		var nudityDecision = module.evaluateGuardEncounter(g1, pcPawn)
		check(nudityDecision.get("kind") == "nudity_warn" and nudityDecision.get("guard") == "g1", "a naked player in a public hall, on a warning roll: a nudity warning")
		module.queuedRolls = [0.9, 0.9]
		check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "most of the time nothing happens")
		moveTo(pcPawn, "main_shower1")
		moveTo(g1, "main_shower1")
		module.queuedRolls = [0.0, 0.9]
		check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "in the showers: nothing")
		moveTo(pcPawn, "hall_a")
		moveTo(g1, "hall_a")
		thePlayer.getInventory().removeItem(uniform)
		check(!module.canPlayerDress(), "with nothing to put on the player cannot dress")
		module.queuedRolls = [0.0, 0.9]
		check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "so there is no warning")
		thePlayer.getInventory().addItem(uniform)
		var equipped = thePlayer.getInventory().equipItem(uniform)
		check(equipped and !module.isPlayerExposed(), "dressed in the inmate uniform the player is not exposed")
		module.queuedRolls = [0.0, 0.9]
		check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "so no warning either")
		thePlayer.getInventory().removeEquippedItem(uniform)
		thePlayer.getInventory().addItem(uniform)
	# Attitudes from the guard's real personality
	var laxPawn = addGuard("g6", "hall_b")
	var strictPawn = addGuard("g7", "hall_b")
	if(laxPawn.getChar().getPersonality() != null):
		laxPawn.getChar().getPersonality().setStat(PersonalityStat.Mean, -1.0)
		strictPawn.getChar().getPersonality().setStat(PersonalityStat.Mean, 1.0)
		check(module.getGuardAttitude("g6") == "lax" and module.getGuardAttitude("g7") == "strict" and module.getGuardAttitude("g6") == module.getGuardAttitude("g6"), "a kind guard is lax, a mean one strict, the same every time")
	else:
		check(["lax", "standard", "strict"].has(module.getGuardAttitude("g6")), "without personality data the attitude is still valid")
	removePawn("g6")
	removePawn("g7")

	var warnInteraction = startEnforcement("g1", "nudity_warn")
	check(warnInteraction != null and warnInteraction.state == "nudity_warn" and sec.isActive() and sec.getWarning(module.getSecurityNow())["guard"] == "g1", "a nudity warning names the guard and records the warning")
	check(pcPawn.currentInteraction == warnInteraction and g1.currentInteraction == warnInteraction, "the guard and the player are in the interaction")
	var actions = warnInteraction.getActionsFinal()
	var ids = []
	for a in actions:
		ids.append(a["id"])
	check(ids.has("cover") and ids.has("ignore"), "the player can cover up or ignore")
	warnInteraction.doActionFinal("cover", {}, {})
	check(!sec.isActive() and pcPawn.currentInteraction != warnInteraction and sec.inGrace(module.getSecurityNow()), "covering up ends it cleanly and starts the grace period")
	check(!sec.getWarning(module.getSecurityNow()).empty() and !sec.getWarning(module.getSecurityNow())["ignored"], "the warning stays until the player covers up or it lapses")
	# the same warning is never printed again, and escalation needs time
	main.clearMessages()
	setTime(10, 5, 7)
	module.queuedRolls = [0.0, 0.0]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "grace: nothing routine right after")
	setTime(14, 0, 7)
	var ignoreInteraction = startEnforcement("g1", "nudity_warn")
	ignoreInteraction.doActionFinal("ignore", {}, {})
	check(sec.getWarning(module.getSecurityNow())["ignored"], "ignoring is recorded")
	# escalation fine never makes credits negative
	thePlayer.addCredits(-thePlayer.getCredits())
	var fineInteraction = startEnforcement("g1", "nudity_escalate")
	check(fineInteraction.state == "nudity_escalate", "escalation is its own state")
	main.clearMessages()
	fineInteraction.doActionFinal("accept", {}, {})
	check(thePlayer.getCredits() == 0 and messagesText().find("indecency") != -1 and messagesText().find("credit taken") == -1 and sec.getWarning(module.getSecurityNow()).empty(), "a broke player pays nothing, the warning is cleared")
	thePlayer.addCredits(5)
	var fineInteraction2 = startEnforcement("g1", "nudity_escalate")
	main.clearMessages()
	fineInteraction2.doActionFinal("accept", {}, {})
	check(thePlayer.getCredits() == 4 and messagesText().find("1 credit taken") != -1 and messagesText().find("red") != -1, "otherwise exactly one credit, in red: " + messagesText())
	check(sec.getAttention() >= 4.0 and !sec.isActive(), "the minor offence added a little attention and the incident ended")

	# ---- Personal search: comply, empty ----
	resetSecurity()
	setTime(9, 0, 8)
	var inv = thePlayer.getInventory()
	check(thePlayer.getInventory().getItemsWithTag(ItemTag.Illegal).empty(), "setup: nothing illegal carried")
	module.queuedRolls = [0.9, 0.001]
	var decision = module.evaluateGuardEncounter(g1, pcPawn)
	check(decision.get("kind") == "search" and decision.get("guard") == "g1", "a lucky roll: a routine search")
	var search = startEnforcement("g1", "search")
	check(search.state == "announce" and sec.isActive(), "the guard announces the search")
	var announceActions = []
	for a in search.getActionsFinal():
		announceActions.append(a["id"])
	check(announceActions.has("comply") and announceActions.has("resist"), "comply or resist")
	var credits0 = thePlayer.getCredits()
	main.clearMessages()
	var combatBefore = JSON.print(state.reputation)
	search.doActionFinal("comply", {}, {})
	check(search.state == "search_result" and thePlayer.getCredits() == credits0 and sec.getAttention() == 0.0 and messagesText().find("found nothing") != -1 and messagesText().find("green") != -1, "an empty search: no fine, no attention, a green message")
	check(JSON.print(state.reputation) == combatBefore, "complying changes no combat reputation")
	search.doActionFinal("done", {}, {})
	check(!sec.isActive() and sec.inGrace(module.getSecurityNow()), "it ends cleanly with a grace period")
	check(state.security["search_day"] == 8 and state.security["search_stamp"] >= 0, "the routine search is recorded")

	# ---- Personal search: contraband, exact confiscation ----
	resetSecurity()
	setTime(9, 0, 9)
	var shiv = GlobalRegistry.createItem("Shiv")
	var baton = GlobalRegistry.createItem("StunBaton")
	var key = GlobalRegistry.createItem("restraintkey")
	var legal = GlobalRegistry.createItem("Condom")
	var protectedShiv = ProtectedShiv.new()
	protectedShiv.uniqueID = "protected1"
	var persistentBaton = PersistentBaton.new()
	persistentBaton.uniqueID = "persistent1"
	for item in [shiv, baton, legal, protectedShiv, persistentBaton, key]:
		inv.addItem(item)
	var shivID = shiv.uniqueID
	var countBefore = inv.getItems().size()
	thePlayer.addCredits(10 - thePlayer.getCredits())
	var search2 = startEnforcement("g1", "search")
	main.clearMessages()
	search2.doActionFinal("comply", {}, {})
	var text = messagesText()
	check(!inv.hasItem(shiv) and !inv.hasItem(baton) and !inv.hasItem(key) and countItems(shivID) == 0, "the contraband is gone")
	check(inv.hasItem(legal) and inv.hasItem(protectedShiv) and inv.hasItem(persistentBaton) and inv.getItems().size() == countBefore - 3, "legal, important and persistent items stay; exactly three things left")
	check(text.find("confiscated:") != -1 and text.find("Shiv") != -1 and text.find("[color=red]") != -1 and text.find("2 credits taken") != -1, "one red message lists what went and the fine: " + text)
	check(thePlayer.getCredits() == 8 and sec.getAttention() >= 10.0 and main.getMessages().size() == 1, "two credits taken, attention up, and only one message for the whole search")
	search2.doActionFinal("done", {}, {})
	# repeated search finds nothing more
	var again = module.performPersonalSearch("g1", 0)
	check(!again["found"] and again["taken"].empty() and thePlayer.getCredits() == 8, "searching again takes nothing and charges nothing")
	# fine never negative
	var shiv2 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv2)
	thePlayer.addCredits(-thePlayer.getCredits())
	thePlayer.addCredits(1)
	var poorSearch = module.performPersonalSearch("g1", 2)
	check(poorSearch["found"] and poorSearch["fine"] == 1 and thePlayer.getCredits() == 0, "a fine cannot exceed what the player has")
	var shiv3 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv3)
	var brokeSearch = module.performPersonalSearch("g1", 2)
	check(brokeSearch["found"] and brokeSearch["fine"] == 0 and thePlayer.getCredits() == 0 and brokeSearch["message"].find("credit") == -1, "a broke player is never made negative")
	# worn items are not touched
	var worn = GlobalRegistry.createItem("GuardArmor")
	inv.addItem(worn)
	var _eq = inv.equipItem(worn)
	check(inv.getEquippedItems().values().has(worn) and worn.hasTag(ItemTag.Illegal), "setup: a worn, illegal uniform")
	var wornSearch = module.performPersonalSearch("g1", 0)
	check(!wornSearch["found"] and inv.getEquippedItems().values().has(worn), "a search only takes carried items, never what is worn")
	inv.removeEquippedItem(worn)

	# ---- Resist and win ----
	resetSecurity()
	setTime(9, 0, 10)
	var shiv4 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv4)
	thePlayer.addCredits(10)
	var credits1 = thePlayer.getCredits()
	var win = startEnforcement("g1", "search")
	main.clearMessages()
	win.doActionFinal("resist", {}, {})
	check(win.resisted and win.state == "about_to_fight" and is_equal_approx(sec.getAttention(), 15.0) and messagesText().find("rises by 15") != -1, "resisting raises attention and offers the fight")
	var repBeforeFight = JSON.print(state.reputation)
	win.doActionFinal("fight", {"scene_result": {"won": true, "how": "pain", "margin": 0.2, "submitter": ""}}, {})
	check(win.state == "resist_won" and inv.hasItem(shiv4) and thePlayer.getCredits() == credits1, "winning: no search, nothing taken, no fine")
	check(JSON.print(state.reputation) == repBeforeFight, "the enforcement code does not apply combat reputation itself")
	check(sec.getAttention() >= 40.0 and sec.getAttention() <= SecurityScript.WON_AGAINST_GUARD_CAP, "winning raises attention a lot, but not to the maximum: " + str(sec.getAttention()))
	win.doFightAftermath(["inmate", "guard"], {"won": true, "how": "pain", "margin": 0.2, "submitter": ""})
	var repAfterOnce = JSON.print(state.reputation)
	check(repAfterOnce != repBeforeFight, "Milestone 2's aftermath runs once through the existing path")
	win.doActionFinal("leave", {}, {})
	check(!sec.isActive() and sec.inGrace(module.getSecurityNow()) and state.security["grace_until"] - module.getSecurityNow() >= SecurityScript.GRACE_AFTER_RESIST - 5, "the incident ends with the longer grace period")
	check(g1.getExhaustion() == 1.0, "the guard is left exhausted")
	module.queuedRolls = [0.0, 0.0]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "no instant second confrontation after winning")
	setTime(11, 0, 10)
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "still in grace three hours later")
	setTime(16, 0, 10)
	module.queuedRolls = [0.9, 0.9]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "and after it ends the player is simply left alone unless dice say otherwise")

	# ---- Resist and lose ----
	resetSecurity()
	setTime(9, 0, 12)
	var shiv5 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv5)
	thePlayer.addCredits(10)
	var lose = startEnforcement("g1", "search")
	lose.doActionFinal("resist", {}, {})
	lose.doActionFinal("fight", {"scene_result": {"won": false, "how": "pain", "margin": 0.5, "submitter": ""}}, {})
	check(lose.state == "resist_lost" and lose.harshness == 2 and inv.hasItem(shiv5), "losing: nothing happens until the guard acts")
	main.clearMessages()
	lose.doActionFinal("continue", {}, {})
	check(!inv.hasItem(shiv5) and lose.state == "search_result" and lose.punishAfter, "beaten after resisting: searched and sent on to punishment")
	var loseActions = []
	for a in lose.getActionsFinal():
		loseActions.append(a["id"])
	check(loseActions == ["punish"], "the next step is the existing punishment")
	lose.doActionFinal("punish", {}, {})
	var punish = null
	for interaction in IS.interactions:
		if(interaction.id == "PunishInteraction" && !interaction.wasDeleted):
			punish = interaction
	check(punish != null and punish.getRoleID("punisher") == "g1" and punish.getRoleID("target") == "pc", "PunishInteraction is reused with the guard as the punisher")
	check(!sec.isActive(), "the confrontation ended when the punishment took over")
	if(punish != null):
		IS.stopInteraction(punish)
	# lost through lust
	resetSecurity()
	setTime(9, 0, 13)
	var lust = startEnforcement("g1", "search")
	lust.doActionFinal("resist", {}, {})
	lust.doActionFinal("fight", {"scene_result": {"won": false, "how": "lust", "margin": 0.5, "submitter": ""}}, {})
	check(lust.state == "resist_lost" and lust.lostHow == "lust" and lust.harshness == 2, "losing through lust is a loss too")
	lust.doActionFinal("continue", {}, {})
	IS.stopInteraction(lust)

	# ---- Surrender in the fight, and giving in before it ----
	resetSecurity()
	setTime(9, 0, 14)
	var shiv6 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv6)
	var sur = startEnforcement("g1", "search")
	sur.doActionFinal("resist", {}, {})
	sur.doActionFinal("fight", {"scene_result": {"won": false, "how": "submit", "margin": 0.1, "submitter": "pc"}}, {})
	check(sur.state == "resist_lost" and sur.harshness == 1 and sur.lostHow == "surrender", "surrendering during the fight is its own outcome, between complying and being beaten")
	sur.doActionFinal("continue", {}, {})
	check(!sur.punishAfter and !inv.hasItem(shiv6), "searched, but no further punishment for a search")
	sur.doActionFinal("done", {}, {})
	resetSecurity()
	setTime(9, 0, 15)
	var shiv7 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv7)
	var giveUp = startEnforcement("g1", "search")
	giveUp.doActionFinal("resist", {}, {})
	giveUp.doActionFinal("giveup", {}, {})
	check(giveUp.harshness == 1 and giveUp.state == "search_result" and !inv.hasItem(shiv7), "giving in before the fight is a milder defeat and the search happens")
	giveUp.doActionFinal("done", {}, {})

	# ---- Violence: witnessed attack leads to a confrontation after the fight ----
	resetSecurity()
	setTime(9, 0, 16)
	module.onUnprovokedAttack("i01")
	module.queuedRolls = [0.9, 0.9]
	var confront = module.evaluateGuardEncounter(g1, pcPawn)
	check(confront.get("kind") == "violent" and confront.get("guard") == "g1", "after the fight the witnessing guard confronts the player")
	module.queuedRolls = [0.9, 0.9]
	check(module.evaluateGuardEncounter(addGuard("g3", "hall_a"), pcPawn).empty(), "a guard who did not see it does nothing")
	removePawn("g3")
	var violent = startEnforcement("g1", "violent")
	var vAct = []
	for a in violent.getActionsFinal():
		vAct.append(a["id"])
	check(vAct == ["comply", "resist"] and sec.getPending(module.getSecurityNow()).size() > 0, "comply or resist, and the report is still open")
	main.clearMessages()
	violent.doActionFinal("comply", {}, {})
	check(!violent.punishAfter and violent.state == "search_result", "complying after violence: a search and a fine, no punishment scene")
	violent.doActionFinal("done", {}, {})
	check(sec.getPending(module.getSecurityNow()).empty() and !sec.isActive(), "the report is spent when the incident ends")
	module.queuedRolls = [0.0, 0.0]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "and the guard does not come back for the same thing")
	# severe
	resetSecurity()
	setTime(9, 0, 17)
	var _s1 = sec.setPending("severe", "g1", module.getSecurityNow())
	var severe = startEnforcement("g1", "severe")
	severe.doActionFinal("comply", {}, {})
	check(severe.punishAfter, "a severe offence is followed by the existing punishment even for someone who complies")
	IS.stopInteraction(severe)
	# resisting a violent confrontation
	resetSecurity()
	setTime(9, 0, 18)
	var _s2 = sec.setPending("violent", "g1", module.getSecurityNow())
	var violent2 = startEnforcement("g1", "violent")
	violent2.doActionFinal("resist", {}, {})
	violent2.doActionFinal("fight", {"scene_result": {"won": true, "how": "pain", "margin": 0.3, "submitter": ""}}, {})
	check(violent2.state == "resist_won" and sec.getPending(module.getSecurityNow()).empty(), "beating the guard who confronted you for violence clears the report")
	violent2.doActionFinal("leave", {}, {})
	module.queuedRolls = [0.0, 0.0]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "no endless reinforcements: nothing follows")
	# a second guard arriving during grace does nothing routine
	var g4 = addGuard("g4", "hall_a")
	module.queuedRolls = [0.0, 0.0]
	check(module.evaluateGuardEncounter(g4, pcPawn).empty(), "another guard in the room during grace also leaves the player alone")
	removePawn("g4")

	# ---- A guard walking in, through the interaction's own meeting check ----
	resetSecurity()
	setTime(9, 0, 20)
	var meeter = GlobalRegistry.getInteractionRef("GuardEnforcement")
	var _s3 = sec.setPending("violent", "g1", module.getSecurityNow())
	var meet = meeter.shouldRunOnMeet(g1, pcPawn, true)
	check(meet[0] and meet[1]["guard"] == "g1" and meet[1]["inmate"] == "pc" and meet[2]["kind"] == "violent", "meeting a guard who saw it starts the confrontation")
	check(!meeter.shouldRunOnMeet(inmate, pcPawn, true)[0] and !meeter.shouldRunOnMeet(g1, g2, true)[0] and !meeter.shouldRunOnMeet(pcPawn, inmate, false)[0], "meetings that are not guard and player never do")
	resetSecurity()
	module.queuedRolls = [0.9, 0.9]
	check(!meeter.shouldRunOnMeet(pcPawn, g1, false)[0], "an ordinary meeting at low attention starts nothing")

	# ---- The ten-minute check starts a confrontation by itself, once ----
	resetSecurity()
	setTime(10, 0, 21)
	var _s4 = sec.setPending("violent", "g1", module.getSecurityNow())
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	extender.securityBucket = -1
	module.onSecurityTick()
	var started = null
	for interaction in IS.interactions:
		if(interaction.id == "GuardEnforcement" && !interaction.wasDeleted):
			started = interaction
	check(started != null and started.kind == "violent" and sec.isActive(), "the periodic check starts the confrontation for a waiting report")
	extender.securityBucket = -1
	module.onSecurityTick()
	var count = 0
	for interaction in IS.interactions:
		if(interaction.id == "GuardEnforcement" && !interaction.wasDeleted):
			count += 1
	check(count == 1, "and never a second one")
	# a stale flag is dropped when the interaction is gone
	IS.stopInteraction(started)
	sec.beginEnforcement(module.getSecurityNow())
	extender.securityBucket = -1
	module.onSecurityTick()
	check(!sec.isActive(), "an active flag with no interaction behind it is dropped")

	# ---- Staff reputation, trust, respect and fear ----
	resetSecurity()
	var relationships = SandboxOverhaulModule.getRelationships()
	var neutral = module.getGuardLeniency("g1")
	thePlayer.getReputation().setLevel(RepStat.Staff, 3, false)
	var respected = module.getGuardLeniency("g1")
	thePlayer.getReputation().setLevel(RepStat.Staff, 1, false)
	var troublemaker = module.getGuardLeniency("g1")
	thePlayer.getReputation().setLevel(RepStat.Staff, 0, false)
	check(respected < neutral and troublemaker > neutral and abs(respected) <= 0.10 and abs(troublemaker) <= 0.10, "staff reputation nudges leniency, boundedly: " + str([respected, neutral, troublemaker]))
	var _f1 = relationships.setFeeling("g1", "pc", "trust", 100)
	var _f2 = relationships.setFeeling("g1", "pc", "respect", 100)
	var trusting = module.getGuardLeniency("g1")
	check(trusting < neutral and trusting >= -0.10, "a guard who trusts and respects the player is more lenient")
	var _f3 = relationships.setFeeling("g1", "pc", "fear", 90)
	check(module.getGuardFear("g1") == 90.0 and SecurityScript.fearAvoidsAlone(module.getGuardFear("g1")), "a terrified guard avoids facing the player alone")
	var _s5 = sec.setPending("violent", "g1", module.getSecurityNow())
	setTime(10, 0, 22)
	_s5 = sec.setPending("violent", "g1", module.getSecurityNow())
	module.queuedRolls = [0.9, 0.9]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "so a terrified guard alone does not confront (the report and attention stay)")
	var _backup = addGuard("g5", "hall_a")
	check(module.evaluateGuardEncounter(g1, pcPawn).get("kind") == "violent", "but does with backup in the room")
	removePawn("g5")
	var _f4 = relationships.setFeeling("g1", "pc", "fear", 0)
	check(module.getGuardAttitude("g1") == module.getGuardAttitude("g1") and ["lax", "standard", "strict"].has(module.getGuardAttitude("g1")), "the attitude is stable and valid")

	# ---- Cell searches with the real stash and hidden compartment ----
	resetSecurity()
	setTime(7, 0, 30)
	var cells = SandboxOverhaulModule.getCells()
	var _c = cells.ensureAssigned([["pc", "orange"]])
	check(cells.isAssigned("pc"), "setup: the player has an assigned cell")
	var stashChar = GlobalRegistry.createStaticCharacter("playerstash")
	add_child(stashChar)
	main.staticCharacters["playerstash"] = stashChar
	var stash = stashChar.getInventory()
	var ups = SandboxOverhaulModule.getUpgrades()
	var _m1 = ups.markOwned("hidden")
	thePlayer.addCredits(20)
	var sKey = GlobalRegistry.createItem("restraintkey")
	var sBread = GlobalRegistry.createItem("PermanentMarker")
	var sProtected = ProtectedShiv.new()
	sProtected.uniqueID = "stashprot"
	for item in [sKey, sBread]:
		inv.addItem(item)
		check(module.depositItem(item, false) == "", "setup: stashed " + str(item.id))
	stash.addItem(sProtected)
	var hKey = GlobalRegistry.createItem("ObeyPill")
	var hLegal = GlobalRegistry.createItem("GasMask")
	for item in [hKey, hLegal]:
		inv.addItem(item)
		check(module.depositItem(item, true) == "", "setup: hidden " + str(item.id))
	var hKeyID = hKey.uniqueID
	var stashUsedBefore = module.getStashUsed()
	main.clearMessages()
	var routineCell = module.performCellSearch(false, 0.0)
	check(routineCell["found"] and !stash.hasItem(sKey) and stash.hasItem(sBread) and stash.hasItem(sProtected), "a routine cell search takes the contraband from the stash and nothing else")
	check(module.getStoredRecords(true).size() == 2 and countItems(hKeyID) == 1, "the hidden compartment is untouched, even on a perfect roll")
	check(routineCell["message"].find("While you were out") != -1 and routineCell["message"].find("hidden") == -1 and routineCell["message"].find("credit") != -1, "the report says it happened while the player was out, and does not hint at the compartment")
	check(module.getStashUsed() == stashUsedBefore - 1 and thePlayer.getCredits() >= 0, "exactly one item went")
	var targetedMiss = module.performCellSearch(true, 0.5)
	check(module.getStoredRecords(true).size() == 2 and targetedMiss["message"].find("found nothing") != -1, "a targeted search that misses reveals nothing")
	var targetedHit = module.performCellSearch(true, 0.05)
	check(module.getStoredRecords(true).size() == 1 and countItems(hKeyID) == 0 and targetedHit["message"].find("hidden compartment") != -1 and module.getStoredRecords(true)[0]["id"] == "GasMask", "a lucky targeted search finds the compartment and takes only the contraband")
	check(state.security["cell_stamp"] >= 0, "the cell search is recorded")
	# due check: once a day, with a cooldown, only with a cell
	resetSecurity()
	var day = main.getDays()
	main.clearMessages()
	module.queuedRolls = [0.001, 0.9]
	module.runCellSearchIfDue(day, module.getSecurityNow())
	check(messagesText().find("While you were out") != -1 and state.security["cell_check_day"] == day, "a lucky day: the report arrives as a message")
	main.clearMessages()
	module.queuedRolls = [0.001, 0.9]
	module.runCellSearchIfDue(day, module.getSecurityNow())
	check(main.getMessages().empty(), "never twice the same day")
	module.queuedRolls = [0.001, 0.9]
	module.runCellSearchIfDue(day + 1, SecurityScript.stamp(day + 1, 7 * 3600))
	check(main.getMessages().empty(), "nor the next day (multi-day cooldown)")
	state.cell_assignments.erase("pc")
	module.queuedRolls = [0.001, 0.9]
	module.runCellSearchIfDue(day + 10, SecurityScript.stamp(day + 10, 7 * 3600))
	check(main.getMessages().empty(), "no cell, no search")
	var _c2 = cells.ensureAssigned([["pc", "orange"]])

	# ---- Save and load: once only ----
	resetSecurity()
	setTime(9, 0, 40)
	var shiv8 = GlobalRegistry.createItem("Shiv")
	inv.addItem(shiv8)
	thePlayer.addCredits(10)
	var _s6 = sec.recordOffence("violent", 40)
	var _s7 = sec.setPending("violent", "g1", module.getSecurityNow())
	sec.issueNudityWarning("g1", module.getSecurityNow())
	var searchSaved = module.performPersonalSearch("g1", 0)
	check(searchSaved["found"], "setup: a search found something")
	var creditsSaved = thePlayer.getCredits()
	var attentionSaved = sec.getAttention()
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	var sb = saved["extendersData"]["SandboxGameExtender"]
	check(sb["schema_version"] == 8 and sb["security"]["attention"] == attentionSaved and sb["security"]["pending"]["kind"] == "violent" and sb["security"]["warning"]["kind"] == "nudity" and sb["security"]["search_stamp"] >= 0, "saved at schema 8 with the attention, report, warning and cooldowns")
	SandboxOverhaulModule.getState().clear()
	check(SandboxOverhaulModule.getSecurity().getAttention() == 0.0, "cleared")
	for _k in range(3):
		GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(SandboxOverhaulModule.getSecurity().getAttention() == attentionSaved and thePlayer.getCredits() == creditsSaved and !inv.hasItem(shiv8), "loading again and again repeats no confiscation, fine or attention")
	check(SandboxOverhaulModule.getState().security["search_stamp"] == sb["security"]["search_stamp"] and !SandboxOverhaulModule.getSecurity().getPending(module.getSecurityNow()).empty(), "cooldowns and the waiting report survive")
	check(SandboxOverhaulModule.getState().work.has("job") and SandboxOverhaulModule.getState().upgrades.has("hidden"), "jobs and upgrades are still in the state")
	SandboxOverhaulModule.getState().loadData({"schema_version": 4, "reputation": {"combat": 3.0, "defiance": 0.0}})
	check(SandboxOverhaulModule.getState().schema_version == 8 and SandboxOverhaulModule.getSecurity().getAttention() == 0.0, "an older save loads at attention 0")

	# ---- Verification: the real guard pool ----
	main.holder = self
	var distribution = {"lax": 0, "standard": 0, "strict": 0}
	var lowest = 9.0
	var highest = -9.0
	var generator = GuardGenerator.new()
	for _n in range(150):
		var guardChar = generator.generate({})
		var meanValue = guardChar.getPersonality().getStat(PersonalityStat.Mean)
		lowest = min(lowest, meanValue)
		highest = max(highest, meanValue)
		distribution[SecurityScript.attitudeFor(guardChar.id, meanValue)] += 1
	main.holder = null
	print("NOTE real guards: Mean range " + str(lowest) + " to " + str(highest) + ", attitudes " + str(distribution))
	check(lowest >= -1.0 and highest <= 1.0 and distribution["lax"] + distribution["standard"] + distribution["strict"] == 150, "150 guards from BDCC's own generator: every Mean is inside -1..1 and every guard is classified")
	check(distribution["strict"] <= 150 * 0.45 and distribution["strict"] < distribution["standard"] and distribution["lax"] >= 150 * 0.05 and distribution["standard"] >= 150 * 0.35, "most real guards are not strict, and the three attitudes all occur: " + str(distribution))

	# ---- Verification: consent and witnesses, relationship aftermath once ----
	endAllInteractions()
	resetSecurity()
	setTime(9, 0, 60)
	moveTo(pcPawn, "hall_a")
	moveTo(g1, "hall_a")
	moveTo(g2, "hall_a")
	var dressed = thePlayer.getInventory().equipItem(uniform)
	check(dressed and !module.isPlayerExposed(), "setup: the player is dressed so nudity does not interfere")
	var forcedFake = FakeSexInteraction.new()
	forcedFake.where = "hall_c"
	state.directed_relationships = {}
	var _a1 = module.applySexAftermathAndShouldRunVanilla(forcedFake, ["dom", "sub"], FakeSexResult.new())
	var relUnwitnessed = JSON.print(state.directed_relationships)
	check(relUnwitnessed != "{}" and sec.getAttention() == 0.0 and sec.getPending(module.getSecurityNow()).empty(), "an unwitnessed FORCED encounter: the relationship aftermath runs, no report, no attention")
	state.directed_relationships = {}
	forcedFake.where = "hall_a"
	main.clearMessages()
	var vanillaRuns = module.applySexAftermathAndShouldRunVanilla(forcedFake, ["dom", "sub"], FakeSexResult.new())
	check(!vanillaRuns, "a FORCED encounter never lets the vanilla affection formula run")
	check(JSON.print(state.directed_relationships) == relUnwitnessed, "a witnessed one changes the relationships exactly as an unwitnessed one: the report does not touch the aftermath")
	check(is_equal_approx(sec.getAttention(), 30.0) and sec.getPending(module.getSecurityNow())["kind"] == "severe" and sec.getPending(module.getSecurityNow())["guard"] in ["g1", "g2"], "a witnessed FORCED encounter: one severe report and +30 attention")
	state.directed_relationships = {}
	var savedAttention = sec.getAttention()
	var twice = FakeSexInteraction.new()
	twice.where = "hall_c"
	var _a2 = module.applySexAftermathAndShouldRunVanilla(twice, ["dom", "sub"], FakeSexResult.new())
	var _a3 = module.applySexAftermathAndShouldRunVanilla(twice, ["dom", "sub"], FakeSexResult.new())
	check(JSON.print(state.directed_relationships) != relUnwitnessed, "two aftermaths differ from one, so a single aftermath really ran its effects once")
	check(is_equal_approx(sec.getAttention(), savedAttention), "and unwitnessed ones add no attention however often they run")
	# one aftermath, one confrontation
	resetSecurity()
	state.directed_relationships = {}
	var _a4 = module.applySexAftermathAndShouldRunVanilla(forcedFake, ["dom", "sub"], FakeSexResult.new())
	var reportedGuard = sec.getPending(module.getSecurityNow())["guard"]
	var rolls = []
	for _m in range(40):
		rolls.append(0.9)
	module.queuedRolls = rolls.duplicate()
	for _t in range(3):
		extender.securityBucket = -1
		module.onSecurityTick()
	check(countInteractions("GuardEnforcement") == 1 and findInteraction("GuardEnforcement").getRoleID("guard") == reportedGuard and findInteraction("GuardEnforcement").kind == "severe", "one aftermath makes one report and one confrontation, however often the check runs, and only the witness acts")
	check(!GlobalRegistry.getInteractionRef("GuardEnforcement").shouldRunOnMeet(g1, pcPawn, true)[0] and !GlobalRegistry.getInteractionRef("GuardEnforcement").shouldRunOnMeet(g2, pcPawn, true)[0], "no second confrontation by meeting a guard while one is running")
	# scripted: nothing starts while a story scene is up
	endAllInteractions()
	resetSecurity()
	var _a5 = module.applySexAftermathAndShouldRunVanilla(forcedFake, ["dom", "sub"], FakeSexResult.new())
	main.sceneStack.append(FakeOtherScene.new())
	module.queuedRolls = rolls.duplicate()
	extender.securityBucket = -1
	module.onSecurityTick()
	check(countInteractions("GuardEnforcement") == 0 and module.evaluateGuardEncounter(g1, pcPawn).empty() and module.evaluateGuardEncounter(g2, pcPawn).empty(), "while a story scene is on the stack no guard confronts the player, report or not")
	main.sceneStack.pop_back()
	endAllInteractions()

	# ---- Verification: saving and loading a running confrontation ----
	resetSecurity()
	setTime(9, 0, 61)
	var _a6 = sec.setPending("violent", "g1", module.getSecurityNow())
	var live = startEnforcement("g1", "violent")
	check(live != null and countInteractions("GuardEnforcement") == 1 and sec.isActive(), "setup: a confrontation is running")
	var snapshot = JSON.parse(JSON.print(IS.saveData())).result
	var securitySnapshot = JSON.parse(JSON.print(GM.GES.saveData())).result
	for _k in range(3):
		IS.loadData(JSON.parse(JSON.print(snapshot)).result)
		GM.GES.loadData(JSON.parse(JSON.print(securitySnapshot)).result)
	pcPawn = IS.getPawn("pc")
	g1 = IS.getPawn("g1")
	g2 = IS.getPawn("g2")
	inmate = IS.getPawn("i01")
	var reloaded = findInteraction("GuardEnforcement")
	check(countInteractions("GuardEnforcement") == 1 and reloaded != null and reloaded.kind == "violent" and reloaded.state == "announce" and reloaded.getRoleID("guard") == "g1" and reloaded.getRoleID("inmate") == "pc", "loading it again and again never duplicates it, and it comes back in the same state")
	check(pcPawn.currentInteraction == reloaded and g1.currentInteraction == reloaded and sec.isActive() and !sec.getPending(module.getSecurityNow()).empty(), "both pawns are back in it and the security state agrees")
	extender.securityBucket = -1
	module.queuedRolls = rolls.duplicate()
	module.onSecurityTick()
	check(countInteractions("GuardEnforcement") == 1, "the periodic check adds nothing")
	reloaded.doActionFinal("comply", {}, {})
	reloaded.doActionFinal("done", {}, {})
	check(countInteractions("GuardEnforcement") == 0 and pcPawn.currentInteraction == null and g1.currentInteraction == null and !sec.isActive() and module.isSafeForEnforcement(), "complying returns control to the player cleanly")
	# after a confiscation: no second confiscation or fine
	resetSecurity()
	setTime(9, 0, 62)
	var shiv9 = GlobalRegistry.createItem("Shiv")
	thePlayer.getInventory().addItem(shiv9)
	thePlayer.addCredits(10 - thePlayer.getCredits())
	var confiscating = startEnforcement("g1", "search")
	confiscating.doActionFinal("comply", {}, {})
	var creditsAfter = thePlayer.getCredits()
	var itemsAfter = thePlayer.getInventory().getItems().size()
	var attentionAfter = sec.getAttention()
	check(!thePlayer.getInventory().hasItem(shiv9) and creditsAfter < 10 and confiscating.state == "search_result", "setup: the search took the Shiv and a fine")
	snapshot = JSON.parse(JSON.print(IS.saveData())).result
	securitySnapshot = JSON.parse(JSON.print(GM.GES.saveData())).result
	for _k in range(2):
		IS.loadData(JSON.parse(JSON.print(snapshot)).result)
		GM.GES.loadData(JSON.parse(JSON.print(securitySnapshot)).result)
	pcPawn = IS.getPawn("pc")
	g1 = IS.getPawn("g1")
	g2 = IS.getPawn("g2")
	inmate = IS.getPawn("i01")
	var loadedSearch = findInteraction("GuardEnforcement")
	check(loadedSearch != null and loadedSearch.state == "search_result" and loadedSearch.resultText.find("confiscated") != -1 and thePlayer.getCredits() == creditsAfter and thePlayer.getInventory().getItems().size() == itemsAfter and is_equal_approx(sec.getAttention(), attentionAfter), "loading after the confiscation changes nothing: no second fine, no second attention")
	loadedSearch.doActionFinal("done", {}, {})
	check(thePlayer.getCredits() == creditsAfter and thePlayer.getInventory().getItems().size() == itemsAfter and countInteractions("GuardEnforcement") == 0, "and finishing it takes nothing more")
	# grace survives a load
	check(sec.inGrace(module.getSecurityNow()), "setup: grace after the incident")
	securitySnapshot = JSON.parse(JSON.print(GM.GES.saveData())).result
	SandboxOverhaulModule.getState().clear()
	GM.GES.loadData(JSON.parse(JSON.print(securitySnapshot)).result)
	check(sec.inGrace(module.getSecurityNow()), "grace survives save and load")
	module.queuedRolls = rolls.duplicate()
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "and still protects the player after it")
	# future and malformed cooldowns cannot block enforcement
	thePlayer.getInventory().removeEquippedItem(uniform)
	thePlayer.getInventory().addItem(uniform)
	check(module.isPlayerExposed(), "setup: the player is exposed again")
	var farFuture = SecurityScript.stamp(main.getDays() + 500, 0)
	SandboxOverhaulModule.getState().loadData({"schema_version": 5, "security": {"enforce_stamp": farFuture, "grace_until": farFuture, "nudity_stamp": farFuture, "search_stamp": farFuture, "cell_stamp": farFuture, "search_day": main.getDays() + 500, "active": true, "active_stamp": farFuture}})
	module.queuedRolls = [0.0, 0.9]
	check(module.evaluateGuardEncounter(g1, pcPawn).empty(), "an active flag from the future blocks once...")
	extender.securityBucket = -1
	module.queuedRolls = rolls.duplicate()
	module.onSecurityTick()
	check(!sec.isActive(), "...and the periodic check drops it")
	module.queuedRolls = [0.0, 0.9]
	check(module.evaluateGuardEncounter(g1, pcPawn).get("kind") == "nudity_warn", "cooldowns stamped in the future do not block anything")
	SandboxOverhaulModule.getState().loadData({"schema_version": 5, "security": {"enforce_stamp": "never", "grace_until": [1, 2], "nudity_stamp": {"a": 1}, "search_stamp": null, "active": "yes", "warning": {"kind": 5}, "pending": 7}})
	module.queuedRolls = [0.0, 0.9]
	check(module.evaluateGuardEncounter(g1, pcPawn).get("kind") == "nudity_warn", "malformed cooldowns are replaced by defaults and block nothing")
	thePlayer.getInventory().removeItem(uniform)
	var _re = thePlayer.getInventory().equipItem(uniform)

	# ---- Verification: the existing frisks are untouched ----
	endAllInteractions()
	resetSecurity()
	setTime(9, 0, 63)
	var shiv10 = GlobalRegistry.createItem("Shiv")
	thePlayer.getInventory().addItem(shiv10)
	thePlayer.addCredits(20 - thePlayer.getCredits())
	IS.startInteraction("CaughtOffLimits", {"guard": "g1", "inmate": "pc"}, {})
	var vanillaCatch = findInteraction("CaughtOffLimits")
	vanillaCatch.setState("about_to_frisk", "inmate")
	vanillaCatch.doActionFinal("frisk", {}, {})
	check(vanillaCatch.foundIllegalItems and vanillaCatch.state == "frisked" and thePlayer.getCredits() == 15 and !thePlayer.getInventory().hasItem(shiv10) and thePlayer.getInventory().getItemsWithTag(ItemTag.Illegal).empty(), "CaughtOffLimits still frisks: contraband gone and exactly 5 credits taken")
	check(sec.getAttention() == 0.0 and !sec.isActive() and countInteractions("GuardEnforcement") == 0, "and it does not involve the new system")
	IS.stopInteraction(vanillaCatch)
	var interactionIDs = GlobalRegistry.getInteractions().keys()
	check(interactionIDs.find("CaughtOffLimits") != -1 and interactionIDs.find("CaughtOffLimits") < interactionIDs.find("GuardEnforcement"), "CaughtOffLimits is registered ahead of the new confrontation, so it keeps priority in the off-limits areas")

	# ---- Verification: outcomes, PunishInteraction, no chained guards ----
	var paths = {}
	for pathName in ["comply", "win", "giveup", "surrender"]:
		endAllInteractions()
		resetSecurity()
		setTime(9, 0, 70)
		var pathInteraction = startEnforcement("g1", "search")
		if(pathName == "comply"):
			pathInteraction.doActionFinal("comply", {}, {})
			pathInteraction.doActionFinal("done", {}, {})
		elif(pathName == "win"):
			pathInteraction.doActionFinal("resist", {}, {})
			pathInteraction.doActionFinal("fight", {"scene_result": {"won": true, "how": "pain", "margin": 0.2, "submitter": ""}}, {})
			pathInteraction.doActionFinal("leave", {}, {})
		elif(pathName == "giveup"):
			pathInteraction.doActionFinal("resist", {}, {})
			pathInteraction.doActionFinal("giveup", {}, {})
			pathInteraction.doActionFinal("done", {}, {})
		else:
			pathInteraction.doActionFinal("resist", {}, {})
			pathInteraction.doActionFinal("fight", {"scene_result": {"won": false, "how": "submit", "margin": 0.1, "submitter": "pc"}}, {})
			pathInteraction.doActionFinal("continue", {}, {})
			pathInteraction.doActionFinal("done", {}, {})
		paths[pathName] = {"punish": countInteractions("PunishInteraction"), "enforcement": countInteractions("GuardEnforcement"), "free": pcPawn.currentInteraction == null and g1.currentInteraction == null and !sec.isActive() and module.isSafeForEnforcement()}
		extender.securityBucket = -1
		module.queuedRolls = [0.0, 0.0, 0.0, 0.0]
		module.onSecurityTick()
		paths[pathName]["after"] = countInteractions("GuardEnforcement") + countInteractions("PunishInteraction")
	for pathName in paths:
		check(paths[pathName]["punish"] == 0 and paths[pathName]["enforcement"] == 0 and paths[pathName]["free"] and paths[pathName]["after"] == 0, pathName + ": ends cleanly, control returns, no punishment scene, and no guard follows up: " + str(paths[pathName]))
	endAllInteractions()
	resetSecurity()
	setTime(9, 0, 71)
	var beaten = startEnforcement("g1", "search")
	beaten.doActionFinal("resist", {}, {})
	beaten.doActionFinal("fight", {"scene_result": {"won": false, "how": "pain", "margin": 0.5, "submitter": ""}}, {})
	beaten.doActionFinal("continue", {}, {})
	check(countInteractions("PunishInteraction") == 0 and countInteractions("GuardEnforcement") == 1, "being beaten does not start the punishment by itself")
	beaten.doActionFinal("punish", {}, {})
	check(countInteractions("PunishInteraction") == 1 and countInteractions("GuardEnforcement") == 0 and !sec.isActive(), "choosing it starts the existing punishment exactly once and the confrontation is over")
	extender.securityBucket = -1
	module.queuedRolls = [0.0, 0.0, 0.0, 0.0]
	module.onSecurityTick()
	check(countInteractions("PunishInteraction") == 1 and countInteractions("GuardEnforcement") == 0, "and nothing else piles on")
	endAllInteractions()

	# ---- Me screen ----
	resetSecurity()
	sec.setAttention(65)
	screen = module.getSecurityScreenText()
	check(screen.find("65 / 100") != -1 and screen.find("High alert") != -1 and screen.find("roll") == -1, "the Security section shows attention and label, no rolls: " + screen)

	# ---- New game ----
	sec.setAttention(70)
	var _s8 = sec.setPending("severe", "g1", 5)
	var main2 = TestMain.new()
	GM.main = main2
	check(SandboxOverhaulModule.getSecurity().getAttention() == 0.0 and SandboxOverhaulModule.getSecurity().getPending(5).empty(), "a new game resets enforcement state")

	GM.main = null
	GM.pc = null
	GM.ES = null
	eventSystem.free()
	stashChar.free()
	thePlayer.free()
	main.free()
	main2.free()
	print("SecurityBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

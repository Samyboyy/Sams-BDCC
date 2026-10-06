extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/SlaveryContinuityBootTest.tscn
# Slaves and escaped slaves stay the same persistent people: enslaving a visible inmate keeps the very pawn, in the very room, with the very cell; no slave action or activity teleports a slave to the
# player; "report to my cell" is a real walk that ends exactly once; an escape leaves the same pawn where it was; the earner economy and loyal defenders follow their rules.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var failures = 0

class FakeWorldScene:
	var sceneID = "WorldScene"
	func supportsShowingPawns():
		return true
	func supportsSexEngine():
		return true
	func hasCharacter(_id):
		return false
	func isSpyingOnInteractionsWith(_id):
		return false
	func resolveCustomCharacterName(_id):
		return null

class FakeFight:
	var sandboxDefeatKind = ""

class TestMain extends "res://Game/MainScene.gd":
	var holder = null
	var counter = 0
	var sceneCalls = []
	func runScene(id, _args = [], _parentSceneUniqueID = -1, _tag:String = ""):
		sceneCalls.append([id, _args]) # scenes are only recorded here: the owner event runner is exercised directly by the test
	func processTime(_seconds):
		timeOfDay += int(round(_seconds))
	func addDynamicCharacter(character, _printDebug = true):
		if(holder != null):
			holder.add_child(character)
			dynamicCharacters[character.getID()] = character
			return
		.addDynamicCharacter(character, _printDebug)
	func generateCharacterID(prefix = "dynamicnpc"):
		counter += 1
		return prefix + "g" + ("%03d" % counter)

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

var main = null
var thePlayer = null
var module = null
var IS = null
var world = null
var extender = null
var ui = null
var inmateIDs = []
var guardIDs = []

func svc():
	return module.getOwnership()

func rel():
	return module.getRelationships()

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func setClock(hour, minute, day):
	main.timeOfDay = int(hour * 3600 + minute * 60)
	main.currentDay = day

func moveTo(roomID):
	thePlayer.location = roomID
	if(IS.hasPawn("pc")):
		IS.getPawn("pc").setLocation(roomID)

func endPlayerInteractions():
	for interaction in IS.interactions.duplicate():
		if(interaction.getInvolvedPawnIDs().has("pc")):
			IS.stopInteraction(interaction)

func advance(seconds, step = 120):
	var left = int(seconds)
	while(left > 0):
		var slice = int(min(step, left))
		left -= slice
		var before = main.timeOfDay
		main.timeOfDay += slice
		if(main.timeOfDay >= 86400):
			main.timeOfDay -= 86400
		if(before < 6 * 3600 and main.timeOfDay >= 6 * 3600 and !(before > 20 * 3600)):
			main.currentDay += 1
		IS.processTime(slice)
		endPlayerInteractions()
		module.onPopulationTick()
		module.onOwnershipTick()

# Runs time forward to a clock time on the current day number rules (day rolls at 06:00) in two-minute steps.
func advanceTo(hour, minute):
	var target = int(hour * 3600 + minute * 60)
	var guard = 0
	while(main.timeOfDay != target and guard < 800):
		advance(120)
		guard += 1

func tick():
	extender.ownershipBucket = -1
	module.onOwnershipTick(true)

func pawnLoc(id):
	var pawn = IS.getPawn(id)
	return pawn.getLocation() if pawn != null else "<none>"

func messageCount(fragment):
	var count = 0
	for line in main.getMessages():
		if(str(line).find(fragment) != -1):
			count += 1
	return count

func options():
	var result = {}
	for option in ui.options.values():
		result[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	return result

func questLog() -> String:
	ui.clearButtons()
	ui.clearText()
	var scene = load("res://Scenes/QuestLogScene.gd").new()
	scene._run()
	return ui.textOutput.bbcode_text

func sideTasks() -> String:
	var text = questLog()
	return text.substr(text.find("Side tasks:"), text.find("Completed tasks:") - text.find("Side tasks:"))

func saveAndLoad():
	var savedIS = JSON.print(IS.saveData())
	var savedExt = JSON.print(GM.GES.saveData())
	IS.clearAll()
	module.getState().clear()
	IS.loadData(JSON.parse(savedIS).result)
	GM.GES.loadData(JSON.parse(savedExt).result)
	IS.updatePCLocation()

# A runner for an owner event, started the way the game does it, with the owner standing where the player is.
func ownerEvent(eventArgs, ownerID):
	var pawn = IS.getPawn(ownerID)
	if(pawn != null):
		pawn.setLocation(thePlayer.location)
	var runner = NpcOwnerEventRunner.new()
	runner.setOwnerID(ownerID)
	runner.runEvent("SandboxOwnerOps", eventArgs)
	runner.run()
	return runner

func press(runner, action):
	for button in runner.getFinalActions():
		if(button.size() > 2 and button[2] == action):
			var _result = runner.doAction(button)
			if(!runner.shouldEnd()):
				runner.run()
			return true
	return false

func buttonNames(runner) -> Array:
	var names = []
	for button in runner.getFinalActions():
		names.append(str(button[0]) + ("" if button.size() > 2 else " (off)"))
	return names

func boost(ownerID, trust, respect, affection, fear = 0.0):
	var _a = rel().setFeeling(ownerID, "pc", "trust", trust)
	var _b = rel().setFeeling(ownerID, "pc", "respect", respect)
	var _c = rel().setFeeling(ownerID, "pc", "affection", affection)
	var _d = rel().setFeeling(ownerID, "pc", "fear", fear)

func pickOwner(excluded, allowGang = false):
	var best = ""
	var bestScore = -99.0
	for id in inmateIDs:
		if(excluded.has(id) or (!allowGang and module.getGangs().gangOf(id) != "")):
			continue
		boost(id, 60.0, 70.0, 40.0)
		var decision = OwnershipGameScript.protectionDecision(id)
		if(decision["score"] > bestScore):
			bestScore = decision["score"]
			best = id
	return best

func becomeOwnedBy(ownerID, _day = 0):
	svc().data()["last_release"] = {}
	boost(ownerID, 60.0, 70.0, 40.0)
	var _ok = OwnershipGameScript.startVoluntary(ownerID)
	return svc().isOwner(ownerID)

func _ready():
	get_tree().create_timer(280.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")
	main = TestMain.new()
	GM.main = main
	main.sceneStack.append(FakeWorldScene.new())
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	main.holder = self
	ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	world = GM.world
	world.addTransitions()
	var qs = QuestSystem.new()
	add_child(qs)
	var inmateGen = InmateGenerator.new()
	for n in range(30):
		var c = inmateGen.generate({})
		c.setFlag(CharacterFlag.InmateType, InmateType.General if n < 14 else (InmateType.HighSec if n < 22 else InmateType.SexDeviant))
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	inmateIDs.sort()
	var guardGen = GuardGenerator.new()
	for _n in range(4):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	thePlayer.inmateType = InmateType.General
	thePlayer.addCredits(40 - thePlayer.getCredits())
	GangGameScript.ensureInitialized()
	for growDay in range(300, 340):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	var DAY = 60
	moveTo("yard_deadend2")
	setClock(9, 0, DAY)
	GlobalRegistry.getWorldEdit("SandboxPopulationBootstrapWorldEdit").apply(world)
	tick()
	check(!svc().hasOwner() and svc().slaveIDs().empty(), "setup: the player is owned by nobody and owns nobody")

	var npcSlavery = GlobalRegistry.getModule("NpcSlaveryModule")
	var _tb = DirectorScript.tick(module, extender.director, true)
	var candidates = []
	for id in inmateIDs:
		if(module.getGangs().gangOf(id) == "" and module.homeRoomOf(id) != "" and IS.hasPawn(id)):
			candidates.append(id)
	check(candidates.size() >= 8, "setup: enough ordinary inmates with pawns and cells: " + str(candidates.size()))
	var slaveA = candidates[0]
	var slaveB = candidates[1]
	var slaveC = candidates[2]
	var slaveD = candidates[3]
	var slaveE = candidates[4]

	# ---- 1. Seamless enslavement: a visible inmate right beside the player ----
	var pawnA = IS.getPawn(slaveA)
	var roomA = pawnA.getLocation()
	moveTo(roomA)
	var cellA = module.homeRoomOf(slaveA)
	var cellsJson = JSON.print(module.getState().cell_assignments)
	var aloneBefore = pawnA.currentInteraction
	IS.updatePCLocation()
	IS.startInteraction("Talking", {"starter": "pc", "reacter": slaveA}, {})
	var pawnCountBefore = IS.pawns.size()
	var talking = null
	for interaction in IS.interactions:
		if(interaction.id == "Talking" and interaction.getInvolvedPawnIDs().has(slaveA)):
			talking = interaction
	check(talking != null and IS.getPawn(slaveA).currentInteraction == talking, "setup: the inmate is talking to the player in front of them")
	var goalBefore = aloneBefore.goal.id if aloneBefore != null and aloneBefore.goal != null else ""
	check(npcSlavery.doEnslaveCharacter(slaveA), "enslaving works")
	check(IS.getPawn(slaveA) == pawnA and !pawnA.isDeleted and IS.hasPawn(slaveA), "the very same pawn is still there, not deleted, not re-created")
	check(pawnA.getLocation() == roomA and pawnA.getLocation() == thePlayer.location, "still in the very same room, beside the player")
	check(IS.pawns.size() == pawnCountBefore and IS.pawns.keys().count(slaveA) == 1, "one pawn before and one after, nothing duplicated")
	var inRoom = 0
	for id in IS.pawnsByLoc.get(roomA, {}).keys():
		if(id == slaveA):
			inRoom += 1
	check(inRoom == 1, "listed once in its room")
	check(talking != null and talking.wasDeleted and pawnA.currentInteraction != talking, "only the enslaving conversation ended")
	check(module.homeRoomOf(slaveA) == cellA and JSON.print(module.getState().cell_assignments) == cellsJson, "the cell assignment is the same")
	check(module.isOwnedSlave(slaveA) and GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Slaves).has(slaveA), "and they are now the player's slave")
	var absent = 0
	var cellChanged = 0
	for _step in range(12):
		advance(120)
		if(!IS.hasPawn(slaveA) or IS.getPawn(slaveA) != pawnA or pawnA.isDeleted):
			absent += 1
		if(module.homeRoomOf(slaveA) != cellA):
			cellChanged += 1
	check(absent == 0 and cellChanged == 0, "not absent for a single frame of the director's ticks, and the cell never changed: " + str(absent) + "/" + str(cellChanged))
	check(svc().hasSlave(slaveA) and svc().slaveRecord(slaveA)["role"] == "free" and module.getNpcJobs().getJob(slaveA) == "", "the module picked the slave up on the way")
	check(module.getState().presence.has(slaveA) and world.hasRoomID(str(module.getState().presence[slaveA].get("room", ""))), "the director keeps tracking them")
	check(goalBefore == "" or pawnA.currentInteraction != null, "the pawn went on with a routine: " + str(goalBefore) + " now " + str(pawnA.currentInteraction))

	# ---- 2. No slave activity teleports a slave ----
	var _e2 = npcSlavery.doEnslaveCharacter(slaveB)
	if(svc().hasSlave(slaveB)):
		svc().data()["slaves"][slaveB]["setup"] = "set" # (these tests are about what an instructed slave does)
		boost(slaveB, 30.0, 10.0, 30.0, 0.0)
	tick()
	var pawnB = IS.getPawn(slaveB)
	var farRoom = "hall_canteen" if pawnB.getLocation() != "hall_canteen" else "main_hallroom5"
	pawnB.setLocation(farRoom)
	moveTo("hall_mainentrance")
	var activities = ["Prostitution", "StuckInStocks", "StuckInSlutwall"]
	for activityID in activities:
		var before = pawnB.getLocation()
		var started = slaveBActivity(npcSlavery, slaveB, activityID)
		check(started and IS.getPawn(slaveB) == pawnB and pawnB.getLocation() == before and IS.pawns.keys().count(slaveB) == 1, activityID + " from another room does not move the slave to the player or anywhere else: " + before + " / " + pawnB.getLocation())
		npcSlavery.getSlaves() # (listing only)
		var theChar = GM.main.getCharacter(slaveB)
		theChar.getNpcSlavery().stopActivity()
		for interaction2 in IS.interactions.duplicate():
			if(interaction2.id != "AloneInteraction" and interaction2.getInvolvedPawnIDs().has(slaveB)):
				IS.stopInteraction(interaction2)
	# the same room: activities start normally
	pawnB.setLocation("hall_mainentrance")
	var startedHere = slaveBActivity(npcSlavery, slaveB, "Prostitution")
	check(startedav(slaveB, "Prostitution") and startedHere and pawnB.getLocation() == "hall_mainentrance" and IS.pawns.keys().count(slaveB) == 1, "an activity with the slave in the player's room starts normally, in place")
	GM.main.getCharacter(slaveB).getNpcSlavery().stopActivity()
	# the punishment scenes take the slave along only when they are in the player's room
	pawnB.setLocation(farRoom)
	module.slaveFollowsPlayer(slaveB, "main_punishment_spot")
	check(pawnB.getLocation() == farRoom, "a slave who is not in the player's room is never taken along")
	pawnB.setLocation("hall_mainentrance")
	module.slaveFollowsPlayer(slaveB, "main_punishment_spot")
	check(pawnB.getLocation() == "main_punishment_spot", "a slave in front of the player goes with them to the punishment spot")
	pawnB.setLocation(farRoom)
	module.slaveWalksWithPlayer(slaveB)
	check(pawnB.getLocation() == thePlayer.location, "on walkies the slave is in the room the player walks into")
	pawnB.setLocation(farRoom)
	# the slave menu
	check(!module.isSlaveWithPlayer(slaveB) and module.getSlaveStatusText(slaveB).find("is in") != -1 and module.getSlaveStatusText(slaveB).find("find them and talk to them") != -1, "from a distance the menu says where they are and what they are doing, nothing else")
	var talkScene = load("res://Modules/NpcSlaveryModule/Slavery/SlaveTalkScene.gd").new()
	talkScene._initScene([slaveB])
	ui.clearButtons()
	ui.clearText()
	talkScene._run()
	var talkText = ui.textOutput.bbcode_text
	check(talkText.find("is in") != -1 and options().size() <= 1, "so the slave menu for someone who is elsewhere has no commands: " + str(options().keys()))
	pawnB.setLocation(thePlayer.location)
	ui.clearButtons()
	ui.clearText()
	var talkScene2 = load("res://Modules/NpcSlaveryModule/Slavery/SlaveTalkScene.gd").new()
	talkScene2._initScene([slaveB])
	talkScene2._run()
	check(options().size() > 1, "and the full menu when they are standing in front of the player")

	# ---- 3. Report to my cell: a real walk ----
	var _e3 = npcSlavery.doEnslaveCharacter(slaveC)
	if(svc().hasSlave(slaveC)):
		svc().data()["slaves"][slaveC]["setup"] = "set" # (these tests are about what an instructed slave does)
		boost(slaveC, 30.0, 10.0, 30.0, 0.0)
	tick()
	var reportAction = GlobalRegistry.getSlaveAction("SbxActionReport")
	var DAY2 = main.currentDay + 1
	setClock(9, 0, DAY2)
	var pcCell = str(thePlayer.getCellLocation())
	moveTo(pcCell)
	tick()
	var pawnC = IS.getPawn(slaveC)
	var sameRoom = IS.getPawn(slaveC)
	check(sameRoom != null, "setup: slave C has a pawn")
	# (a) same room: commands work, the report is a duty for the evening and costs nothing
	pawnC.setLocation(pcCell)
	check(reportAction.checkCanDo(slaveC)[0], "asking is possible when they are with the player")
	# (b) different room: far away
	var farFrom = ""
	for room in ["hall_canteen", "yard_deadend2", "main_hallroom4", "medical_near_pccell"]:
		if(world.hasRoomID(room) and world.calculatePath(room, pcCell).size() >= 4):
			farFrom = room
			break
	check(farFrom != "", "setup: a room several rooms away from the player's cell")
	pawnC.setLocation(farFrom)
	check(reportAction.checkCanDo(slaveC)[0], "asking is possible from anywhere there is a way (they are told in person)")
	var shown = reportAction.doActionSimple(slaveC)
	check(shown["text"].find("walk") != -1 and svc().slaveRecord(slaveC)["report"]["state"] == "pending", "the order is a request to walk over, not a summons")
	advanceTo(19, 0)
	check(pawnC.getLocation() != pcCell and IS.hasPawn(slaveC) and IS.getPawn(slaveC) == pawnC, "before the evening they are not at the player's cell, and nothing moved them")
	var seen = {}
	var jumps = 0
	var last = pawnC.getLocation()
	var arrivedAt = -1
	var minutes = 0
	while(main.timeOfDay < 21 * 3600 and arrivedAt < 0):
		advance(120)
		minutes += 2
		var here = IS.getPawn(slaveC).getLocation()
		seen[here] = true
		if(here != last and world.calculatePath(last, here).size() > 4):
			jumps += 1
		last = here
		if(here == pcCell):
			arrivedAt = minutes
	check(arrivedAt > 0 and jumps == 0, "they walked room by room and arrived at the player's cell (" + str(arrivedAt) + " minutes, rooms seen " + str(seen.keys().size()) + ", jumps " + str(jumps) + ")")
	check(seen.keys().size() >= 3, "through several rooms, not in one step: " + str(seen.keys()))
	advance(600)
	check(svc().slaveRecord(slaveC)["report"]["state"] == "done" and messageCount("has come to your cell") == 1, "arrival is reported exactly once")
	advance(1800)
	check(messageCount("has come to your cell") == 1 and IS.pawns.keys().count(slaveC) == 1, "and still once later, with a single pawn")
	# save and load while travelling
	var DAY3 = main.currentDay + 1
	setClock(9, 0, DAY3)
	tick()
	advance(600)
	var pawnC2 = IS.getPawn(slaveC)
	pawnC2.setLocation(farFrom)
	svc().data()["slaves"][slaveC]["report"] = {}
	var _askAgain = reportAction.doActionSimple(slaveC)
	setClock(19, 26, main.currentDay)
	advance(600)
	var midway = IS.getPawn(slaveC).getLocation()
	var messagesBefore = messageCount("has come to your cell")
	saveAndLoad()
	check(IS.hasPawn(slaveC) and IS.pawns.keys().count(slaveC) == 1 and svc().slaveRecord(slaveC)["report"]["state"] == "pending", "after saving and loading while they are on their way they are still on the way: " + midway + " -> " + IS.getPawn(slaveC).getLocation())
	var guard = 0
	while(IS.getPawn(slaveC).getLocation() != pcCell and guard < 60):
		advance(120)
		guard += 1
	advance(600)
	check(IS.getPawn(slaveC).getLocation() == pcCell or svc().slaveRecord(slaveC)["report"]["state"] == "done", "they arrive after the load")
	check(messageCount("has come to your cell") == messagesBefore + 1 and svc().slaveRecord(slaveC)["report"]["state"] == "done", "and arrival is reported once")
	# blocked
	var DAY4 = main.currentDay + 1
	setClock(9, 0, DAY4)
	tick()
	var pawnC3 = IS.getPawn(slaveC)
	pawnC3.setLocation(farFrom)
	module.getInjuries().applyInjury(slaveC, "leg", 3)
	var problem = reportAction.checkCanDo(slaveC)
	check(!problem[0] and problem[1].find("hurt") != -1, "a badly hurt slave cannot be sent: " + str(problem))
	module.getInjuries().remove(slaveC, "leg")
	svc().data()["slaves"][slaveC]["report"] = {}
	var _ask3 = reportAction.doActionSimple(slaveC)
	module.getInjuries().applyInjury(slaveC, "leg", 3)
	advanceTo(19, 40)
	check(svc().slaveRecord(slaveC)["report"]["state"] == "cancelled" and messageCount("could not come to your cell") == 1 and IS.getPawn(slaveC).getLocation() != pcCell, "hurt after being asked: it is cancelled cleanly, once, and they do not come")
	advance(1200)
	check(messageCount("could not come to your cell") == 1 and IS.getPawn(slaveC).getLocation() != pcCell, "and nothing else happens")
	module.getInjuries().remove(slaveC, "leg")
	check(!OwnershipGameScript.routeExists("hall_canteen", "nowhere_at_all") and OwnershipGameScript.routeExists("hall_canteen", "hall_canteen") and OwnershipGameScript.routeExists("hall_canteen", pcCell), "routes: none to a room that does not exist")
	check(OwnershipGameScript.slaveBlockReason("nobody_here") == "not around", "nobody is not around")

	# ---- 3b. A held or unconscious slave does not travel ----
	var gangID = ""
	for id in inmateIDs:
		if(module.getGangs().gangOf(id) != ""):
			gangID = module.getGangs().gangOf(id)
			break
	check(gangID != "", "setup: a gang that can hold somebody")
	var DAYB = main.currentDay + 1
	setClock(9, 0, DAYB)
	tick()
	IS.getPawn(slaveC).setLocation(farFrom)
	svc().data()["slaves"][slaveC]["report"] = {}
	var _askB1 = reportAction.doActionSimple(slaveC)
	module.getState().gangs["captives"][slaveC] = {"gang": gangID, "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
	check(OwnershipGameScript.slaveBlockReason(slaveC) == "held" and OwnershipGameScript.reportProblem(slaveC).find("held") != -1, "setup: the slave is held by a gang (the game's own captive record)")
	var heldBefore = messageCount("could not come to your cell")
	setClock(19, 26, main.currentDay)
	var heldAtCell = 0
	for _stepH in range(12):
		advance(120)
		if(IS.hasPawn(slaveC) and IS.getPawn(slaveC).getLocation() == pcCell):
			heldAtCell += 1
	check(heldAtCell == 0 and IS.pawns.keys().count(slaveC) == 1, "a held slave never reaches the player's cell and is never duplicated")
	check(svc().slaveRecord(slaveC)["report"]["state"] == "cancelled" and messageCount("could not come to your cell") == heldBefore + 1, "the order is cancelled cleanly, with one message and no blame")
	var _freedC = module.getGangs().release(slaveC)
	advance(2400)
	check(svc().slaveRecord(slaveC)["report"]["state"] == "cancelled" and IS.getPawn(slaveC).getLocation() != pcCell, "once released the order does not come back on its own (a cancelled order is gone, the player can ask again tomorrow)")
	# unconscious, waking up inside the window: the order resumes
	var DAYU = main.currentDay + 1
	svc().data()["tick_day"] = main.currentDay
	setClock(9, 0, DAYU)
	tick()
	IS.getPawn(slaveC).setLocation(farFrom)
	svc().data()["slaves"][slaveC]["report"] = {}
	var _askU = reportAction.doActionSimple(slaveC)
	setClock(19, 26, main.currentDay)
	IS.startInteraction("Unconscious", {"main": slaveC})
	var knocked = IS.getPawn(slaveC).currentInteraction
	check(knocked != null and knocked.id == "Unconscious" and OwnershipGameScript.slaveBlockReason(slaveC) == "busy", "setup: the slave is unconscious (the game's own interaction)")
	var cameBefore = messageCount("has come to your cell")
	var outLoc = IS.getPawn(slaveC).getLocation()
	var atCellWhileOut = 0
	for _stepU in range(10):
		advance(120)
		if(IS.hasPawn(slaveC) and IS.getPawn(slaveC).getLocation() == pcCell):
			atCellWhileOut += 1
	check(atCellWhileOut == 0 and IS.getPawn(slaveC).getLocation() == outLoc and IS.pawns.keys().count(slaveC) == 1, "an unconscious slave does not move at all, and nothing teleports them")
	check(svc().slaveRecord(slaveC)["report"]["state"] == "pending" and svc().slaveRecord(slaveC)["report"]["delayed"], "the order is only delayed")
	IS.stopInteractionsForPawnID(slaveC)
	var resumeGuard = 0
	while(IS.getPawn(slaveC).getLocation() != pcCell and resumeGuard < 40):
		advance(120)
		resumeGuard += 1
	advance(600)
	check(svc().slaveRecord(slaveC)["report"]["state"] == "done" and messageCount("has come to your cell") == cameBefore + 1, "once they come round inside the evening window they walk over and arrive exactly once")
	# unconscious through the whole window: the order lapses without blame
	var DAYV = main.currentDay + 1
	svc().data()["tick_day"] = main.currentDay
	setClock(9, 0, DAYV)
	tick()
	IS.getPawn(slaveC).setLocation(farFrom)
	svc().data()["slaves"][slaveC]["report"] = {}
	var _askV = reportAction.doActionSimple(slaveC)
	setClock(19, 26, main.currentDay)
	IS.startInteraction("Unconscious", {"main": slaveC})
	var blameBefore = messageCount("did not come when you called")
	advanceTo(21, 40)
	check(svc().slaveRecord(slaveC)["report"]["state"] == "pending" and svc().slaveRecord(slaveC)["report"]["delayed"] and IS.getPawn(slaveC).getLocation() != pcCell, "still down at the end of the window: nothing happened")
	IS.stopInteractionsForPawnID(slaveC)
	svc().data()["tick_day"] = main.currentDay
	setClock(9, 0, main.currentDay + 1)
	tick()
	check(svc().slaveRecord(slaveC)["report"]["state"] == "cancelled" and messageCount("did not come when you called") == blameBefore, "the order lapses when the day is settled, and nobody is blamed")

	# ---- 4. A successful escape leaves the same pawn where it is ----
	var _e4 = npcSlavery.doEnslaveCharacter(slaveD)
	if(svc().hasSlave(slaveD)):
		svc().data()["slaves"][slaveD]["setup"] = "set" # (these tests are about what an instructed slave does)
		boost(slaveD, 30.0, 10.0, 30.0, 0.0)
	tick()
	var pawnD = IS.getPawn(slaveD)
	var cellD = module.homeRoomOf(slaveD)
	pawnD.setLocation("hall_mainentrance")
	moveTo("hall_mainentrance")
	boost(slaveD, -40.0, -10.0, -40.0, 5.0)
	var escapeDay = main.currentDay + 1
	svc().data()["slaves"][slaveD]["escape"] = {"stage": "gone", "day": escapeDay - 1, "why": "x"}
	svc().data()["tick_day"] = escapeDay - 1
	var poolBefore = IS.pawns.size()
	var cellsAtEscape = JSON.print(module.getState().cell_assignments)
	var trustBefore = rel().getFeeling(slaveD, "pc", "trust")
	setClock(9, 0, escapeDay)
	OwnershipGameScript.completeEscape(slaveD)
	check(IS.getPawn(slaveD) == pawnD and !pawnD.isDeleted and pawnD.getLocation() == "hall_mainentrance" and IS.pawns.size() == poolBefore, "the escaped slave is the very same pawn, still at the exit, nothing deleted or regenerated, in full view of the player")
	check(!svc().hasSlave(slaveD) and !module.isOwnedSlave(slaveD) and GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Inmates).has(slaveD), "ownership is cleared and they are an ordinary inmate")
	check(module.homeRoomOf(slaveD) == cellD and JSON.print(module.getState().cell_assignments) == cellsAtEscape, "their cell is still theirs")
	check(rel().getFeeling(slaveD, "pc", "trust") < trustBefore and rel().getFeeling(slaveD, "pc", "trust") <= -20.0, "and they remember: trust fell to " + str(rel().getFeeling(slaveD, "pc", "trust")))
	var lost = 0
	for _step in range(10):
		advance(120)
		if(!IS.hasPawn(slaveD) or IS.getPawn(slaveD) != pawnD):
			lost += 1
	check(lost == 0 and IS.pawns.keys().count(slaveD) == 1 and world.hasRoomID(pawnD.getLocation()), "they carry on from where they were with their ordinary day: " + pawnD.getLocation())

	# ---- 5. Loyal defenders ----
	var _e5 = npcSlavery.doEnslaveCharacter(slaveE)
	if(svc().hasSlave(slaveE)):
		svc().data()["slaves"][slaveE]["setup"] = "set" # (these tests are about what an instructed slave does)
		boost(slaveE, 30.0, 10.0, 30.0, 0.0)
	tick()
	var attackerID = candidates[5]
	var pawnE = IS.getPawn(slaveE)
	var attackerPawn = IS.getPawn(attackerID)
	endPlayerInteractions()
	for interaction3 in IS.interactions.duplicate():
		if(interaction3.id != "AloneInteraction" and (interaction3.getInvolvedPawnIDs().has(slaveE) or interaction3.getInvolvedPawnIDs().has(attackerID))):
			IS.stopInteraction(interaction3)
	var room5 = "hall_canteen"
	moveTo(room5)
	pawnE.setLocation(room5)
	attackerPawn.setLocation(room5)
	boost(slaveE, 60.0, 50.0, 60.0, 5.0)
	check(OwnershipGameScript.slaveDisposition(slaveE) == "loyal", "setup: a loyal slave: " + OwnershipGameScript.slaveDisposition(slaveE))
	check(OwnershipGameScript.willIntervene(slaveE, attackerID), "a loyal slave in the same room helps")
	pawnE.setLocation("hall_mainentrance")
	check(!OwnershipGameScript.willIntervene(slaveE, attackerID), "a loyal slave somewhere else does not: loyalty never puts them in the room")
	check(pawnE.getLocation() == "hall_mainentrance", "and nothing moved them")
	pawnE.setLocation(room5)
	module.getInjuries().applyInjury(slaveE, "arm", 3)
	check(!OwnershipGameScript.willIntervene(slaveE, attackerID), "a severely injured slave does not")
	module.getInjuries().remove(slaveE, "arm")
	check(OwnershipGameScript.willIntervene(slaveE, attackerID), "(recovered)")
	IS.startInteraction("Talking", {"starter": "pc", "reacter": slaveE}, {})
	check(!OwnershipGameScript.willIntervene(slaveE, attackerID), "a slave busy with something else does not")
	for interaction4 in IS.interactions.duplicate():
		if(interaction4.id != "AloneInteraction" and interaction4.getInvolvedPawnIDs().has(slaveE)):
			IS.stopInteraction(interaction4)
	svc().data()["slaves"][slaveE]["role"] = "attendant"
	boost(slaveE, 5.0, 0.0, 0.0, 60.0)
	check(OwnershipGameScript.slaveDisposition(slaveE) == "intimidated" and OwnershipGameScript.willIntervene(slaveE, attackerID), "an attendant is more reliable: even an intimidated one steps in")
	svc().data()["slaves"][slaveE]["role"] = "free"
	check(!OwnershipGameScript.willIntervene(slaveE, attackerID), "while an intimidated slave with no post does not")
	boost(slaveE, -40.0, -10.0, -40.0, 5.0)
	svc().data()["slaves"][slaveE]["role"] = "attendant"
	check(!OwnershipGameScript.willIntervene(slaveE, attackerID), "and an attendant who is defiant does not either")
	# exactly one intervention with two eligible helpers
	var slaveF = candidates[6]
	var _e6 = npcSlavery.doEnslaveCharacter(slaveF)
	if(svc().hasSlave(slaveF)):
		svc().data()["slaves"][slaveF]["setup"] = "set" # (these tests are about what an instructed slave does)
		boost(slaveF, 30.0, 10.0, 30.0, 0.0)
	tick()
	boost(slaveE, 60.0, 50.0, 60.0, 5.0)
	boost(slaveF, 60.0, 50.0, 60.0, 5.0)
	IS.getPawn(slaveF).setLocation(room5)
	svc().data()["slaves"][slaveE]["role"] = "attendant"
	svc().data()["slaves"][slaveF]["role"] = "attendant"
	IS.startInteraction("GenericAttack", {"starter": attackerID, "reacter": "pc"}, {})
	var fight = null
	for interaction5 in IS.interactions:
		if(interaction5.id == "GenericAttack" and !interaction5.wasDeleted):
			fight = interaction5
	check(fight != null, "setup: the player is being attacked")
	var stepsBefore = messageCount("steps in front of you")
	var helper = OwnershipGameScript.onPlayerAttacked(fight, attackerID)
	var defenders = 0
	for interaction6 in IS.interactions:
		if(interaction6.id == "GenericAttack" and !interaction6.wasDeleted and interaction6.getRoleID("reacter") == attackerID):
			defenders += 1
	check(helper in [slaveE, slaveF] and defenders == 1 and fight.wasDeleted and messageCount("steps in front of you") == stepsBefore + 1, "two eligible slaves: exactly one steps in, once: " + str(helper) + ", " + str(defenders) + ", " + str(fight.wasDeleted) + ", " + str(messageCount("steps in front of you")))

	print("SlaveryContinuityBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

func slaveBActivity(_npcSlavery, slaveID, activityID) -> bool:
	var theChar = GM.main.getCharacter(slaveID)
	if(theChar == null or theChar.getNpcSlavery() == null):
		return false
	return theChar.getNpcSlavery().startActivity(activityID) != null

func startedav(slaveID, activityID) -> bool:
	var theChar = GM.main.getCharacter(slaveID)
	return theChar != null and theChar.getNpcSlavery() != null and theChar.getNpcSlavery().getActivityID() == activityID

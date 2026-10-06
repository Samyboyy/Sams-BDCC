extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnerApproachBootTest.tscn
# The player's owner never teleports: the owner walks room by room to the player, a missing pawn is restored by the population system, a blocked owner postpones the visit, and the event starts once.
# (A blocked owner is held by a gang, busy, unconscious or badly hurt, or has no route.)

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
		if(id == "NpcOwnerEventRunnerScene"):
			var visit = RS.getSpecialRelationship(_args[0]) # (the real event sets the next approach day itself)
			if(visit != null && visit.get("npcOwner") != null):
				visit.npcOwner.nextApproachDay = getDays() + 3
			sceneStack.append(FakeWorldScene.new()) # the event scene is now on top: the player cannot be interrupted until the test ends it
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


	var _tb = DirectorScript.tick(module, extender.director, true)
	var ownerID = pickOwner([])
	check(ownerID != "" and becomeOwnedBy(ownerID), "setup: the player is owned by a persistent inmate")
	DAY = main.currentDay
	var gangMemberGang = ""
	for id in inmateIDs:
		if(module.getGangs().gangOf(id) != ""):
			gangMemberGang = module.getGangs().gangOf(id)
			break
	var playerRoom = "hall_canteen"
	var farRoom = ""
	for room in ["mining_nearentrance", "cellblock_orange_playercell", "yard_deadend2", "medical_near_pccell", "main_hallroom4"]:
		if(world.hasRoomID(room) and world.calculatePath(room, playerRoom).size() >= 5):
			farRoom = room
			break
	check(farRoom != "", "setup: a room several rooms away from the player")
	var farRoom2 = "main_hallroom5" if world.hasRoomID("main_hallroom5") and world.calculatePath("main_hallroom5", playerRoom).size() >= 3 else farRoom

	visitDay = DAY
	# ---- 1. The owner walks to the player, room by room, and the event starts once ----
	var pawnO = IS.getPawn(ownerID)
	var npcOwner = GM.main.RS.getSpecialRelationship(ownerID).npcOwner
	svc().record()["demand_clock"] = OwnershipGameScript.clockNow()
	prepare(ownerID, playerRoom, farRoom)
	var v1 = walkToVisit(ownerID, npcOwner, 200, -1, "")
	check(v1["arrived"] > 0 and v1["jumps"] == 0, "the owner walked to the player (" + str(v1["arrived"]) + " steps, rooms " + str(v1["rooms"].size()) + ", jumps " + str(v1["jumps"]) + ")")
	check(v1["rooms"].size() >= 4, "through several connected rooms: " + str(v1["rooms"]))
	check(v1["events"] == 1, "the event started exactly once, on meeting: " + str(v1["events"]))
	check(IS.pawns.keys().count(ownerID) == 1 and IS.getPawn(ownerID) == pawnO and !pawnO.isDeleted, "the same single pawn throughout")

	# ---- 2. The player moves during the approach ----
	prepare(ownerID, playerRoom, farRoom)
	var v2 = walkToVisit(ownerID, npcOwner, 260, 6, "hall_checkpoint" if world.hasRoomID("hall_checkpoint") else "hall_canteen")
	check(v2["arrived"] > 0 and v2["jumps"] == 0 and v2["events"] == 1, "the player moved and the owner followed on foot, never jumping (" + str(v2["arrived"]) + " steps, " + str(v2["jumps"]) + " jumps, " + str(v2["events"]) + " events)")
	check(IS.pawns.keys().count(ownerID) == 1, "one pawn")

	# ---- 3. The owner is blocked: the visit is postponed, quietly, and resumes ----
	for blocker in ["busy", "captive", "unconscious", "hurt"]:
		prepare(ownerID, playerRoom, farRoom2)
		module.getState().gangs["captives"].erase(ownerID)
		module.getInjuries().remove(ownerID, "leg")
		var clockStart = OwnershipGameScript.clockNow()
		if(blocker == "busy"):
			IS.startInteraction("InStocks", {"inmate": ownerID})
		elif(blocker == "captive"):
			module.getState().gangs["captives"][ownerID] = {"gang": gangMemberGang, "kind": "captive", "stamp": clockStart, "by": ""}
		elif(blocker == "unconscious"):
			IS.startInteraction("Unconscious", {"main": ownerID})
		else:
			module.getInjuries().applyInjury(ownerID, "leg", 3)
		var held = walkToVisit(ownerID, npcOwner, 60, -1, "")
		var reason = OwnershipGameScript.ownerApproachBlock(ownerID)
		check(reason != "" and held["events"] == 0 and held["jumps"] == 0, blocker + ": postponed (" + reason + "), no event starts and nobody jumps to the player (an owner who merely passes through the room on their ordinary day starts nothing)")
		check(IS.pawns.keys().count(ownerID) == 1, blocker + ": no duplicate")
		var retryAt = int(extender.approachRetry.get(ownerID, -1))
		check(retryAt == -1 or retryAt > clockStart, blocker + ": the retry delay lies in the future")
		IS.stopInteractionsForPawnID(ownerID)
		module.getState().gangs["captives"].erase(ownerID)
		module.getInjuries().remove(ownerID, "leg")
		extender.approachRetry = {}
		var freed = walkToVisit(ownerID, npcOwner, 400, -1, "")
		check(freed["arrived"] > 0 and freed["jumps"] == 0 and freed["events"] == 1, blocker + ": once free the owner walks over and the event starts once (" + str(freed["arrived"]) + " steps, " + str(freed["jumps"]) + " jumps, " + str(freed["events"]) + " events)")

	# retry delay: a hurt owner is weighed once and then left alone until the delay is over
	prepare(ownerID, playerRoom, farRoom2)
	module.getInjuries().applyInjury(ownerID, "leg", 3)
	extender.approachRetry = {}
	var clockHurt = OwnershipGameScript.clockNow()
	npcOwner.nextApproachDay = DAY
	advance(60, 30)
	var firstRetry = int(extender.approachRetry.get(ownerID, -1))
	advance(600, 30)
	check(firstRetry >= clockHurt + module.APPROACH_RETRY_SECONDS - 60 and int(extender.approachRetry.get(ownerID, -1)) == firstRetry, "a blocked visit is not weighed again on every tick: the delay held for ten minutes (" + str(firstRetry - clockHurt) + "s)")
	module.getInjuries().remove(ownerID, "leg")
	npcOwner.nextApproachDay = DAY + 3

	# no route
	prepare(ownerID, playerRoom, farRoom2)
	var pawnN = IS.getPawn(ownerID)
	IS.stopInteractionsForPawnID(ownerID)
	var keepLoc = pawnN.getLocation()
	pawnN.setLocation("nowhere_island")
	extender.approachRetry = {}
	npcOwner.nextApproachDay = DAY
	var goal = InteractionGoal.create("NpcOwnerApproach")
	var noRouteBlock = OwnershipGameScript.ownerApproachBlock(ownerID)
	var mayApproach = module.ownerMayApproach(ownerID)
	check(noRouteBlock == "no route" and !mayApproach and int(extender.approachRetry.get(ownerID, -1)) > OwnershipGameScript.clockNow(), "no route: the visit is postponed with a delay: " + noRouteBlock)
	check(pawnN.getLocation() == "nowhere_island", "and the owner was not moved anywhere")
	if(goal != null):
		check(goal.getScore(pawnN) == 0.0, "(the approach goal scores 0 while it is postponed)")
	pawnN.setLocation(keepLoc)
	extender.approachRetry = {}
	npcOwner.nextApproachDay = DAY + 3

	# ---- 4. A missing owner pawn is restored by the population system, never beside the player ----
	prepare(ownerID, playerRoom, farRoom2)
	var recordedRoom = farRoom2
	module.getState().presence[ownerID] = {"room": recordedRoom, "kind": "hall", "dest": recordedRoom, "act": "do", "seg": 0, "since": 0}
	IS.stopInteractionsForPawnID(ownerID)
	IS.deletePawn(ownerID)
	check(!IS.hasPawn(ownerID), "setup: the owner's pawn is missing")
	var runner = NpcOwnerEventRunner.new()
	runner.setOwnerID(ownerID)
	runner.runEvent("SandboxOwnerOps", ["approach"])
	check(runner.shouldEnd() and runner.eventStack.empty(), "an event cannot start while the owner is away")
	check(IS.hasPawn(ownerID) and IS.pawns.keys().count(ownerID) == 1, "the owner is back as one pawn")
	check(IS.getPawn(ownerID).getLocation() != thePlayer.location and world.hasRoomID(IS.getPawn(ownerID).getLocation()), "restored by the population system, not beside the player: " + IS.getPawn(ownerID).getLocation() + " (recorded " + recordedRoom + ")")
	module.getState().presence.erase(ownerID)
	IS.deletePawn(ownerID)
	var restored = module.restoreOwnerPawn(ownerID)
	check(restored != null and restored.getLocation() != thePlayer.location and world.hasRoomID(restored.getLocation()) and IS.pawns.keys().count(ownerID) == 1, "with no record they are where their routine puts them: " + (restored.getLocation() if restored != null else "<none>"))
	var theEvent = GlobalRegistry.createNpcOwnerEvent("SandboxOwnerOps")
	theEvent.setEventRunner(runner)
	var farLoc = IS.getPawn(ownerID).getLocation()
	theEvent.involveOwner()
	check(IS.getPawn(ownerID).getLocation() == farLoc and farLoc != thePlayer.location, "joining an event does not move the owner")
	IS.stopInteractionsForPawnID(ownerID)
	IS.deletePawn(ownerID)
	theEvent.involveOwner()
	check(!IS.hasPawn(ownerID), "and does not create their pawn beside the player")
	var _r2 = module.restoreOwnerPawn(ownerID)
	IS.stopInteractionsForPawnID(ownerID)
	extender.approachRetry = {}
	var v4 = walkToVisit(ownerID, npcOwner, 400, -1, "")
	check(v4["arrived"] > 0 and v4["jumps"] == 0 and v4["events"] == 1, "the restored owner walks over and the event starts once (" + str(v4["jumps"]) + " jumps, " + str(v4["events"]) + " events)")

	# ---- 5. Saving and loading mid-approach ----
	prepare(ownerID, playerRoom, farRoom)
	npcOwner.nextApproachDay = DAY
	var scenesD = main.sceneCalls.size()
	advance(150, 30)
	var midLoc = IS.getPawn(ownerID).getLocation()
	check(midLoc != farRoom and midLoc != playerRoom, "setup: the owner is on the way: " + midLoc)
	saveAndLoad()
	npcOwner = GM.main.RS.getSpecialRelationship(ownerID).npcOwner
	check(IS.pawns.keys().count(ownerID) == 1 and IS.getPawn(ownerID).getLocation() == midLoc, "after loading there is one owner, in the same place: " + IS.getPawn(ownerID).getLocation())
	check(main.sceneCalls.size() == scenesD, "and no event has started")
	var v5 = walkToVisit(ownerID, npcOwner, 400, -1, "")
	check(v5["arrived"] > 0 and v5["jumps"] == 0 and v5["events"] == 1 and IS.pawns.keys().count(ownerID) == 1, "the approach carried on after the load: one arrival, one event, one pawn (" + str(v5["arrived"]) + " steps, " + str(v5["jumps"]) + " jumps, " + str(v5["events"]) + " events)")

	print("OwnerApproachBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

var visitDay = 60

# A fresh morning: the player stands in playerRoom, the owner is put in ownerRoom once the director has caught up with the clock change.
func prepare(ownerID, playerRoom, ownerRoom):
	main.sceneStack.resize(1)
	IS.updatePCLocation()
	endPlayerInteractions()
	IS.stopInteractionsForPawnID(ownerID)
	moveTo(playerRoom)
	setClock(10, 0, visitDay)
	extender.director = {}
	extender.approachRetry = {}
	advance(60, 30)
	IS.stopInteractionsForPawnID(ownerID)
	if(IS.hasPawn(ownerID)):
		IS.getPawn(ownerID).setLocation(ownerRoom)

func visitEvents(ownerID, from) -> int:
	var count = 0
	for call in main.sceneCalls.slice(from, main.sceneCalls.size() - 1):
		if(call[0] == "NpcOwnerEventRunnerScene" and call[1][0] == ownerID):
			count += 1
	return count

# Lets the owner's visit run in 30-second steps. Returns arrived (steps until they stood in the player's room, -1 never), jumps (moves of more than two rooms), events and rooms.
# After the event is seen the visit is closed (as the real event does) and a few more steps prove that nothing starts twice.
func walkToVisit(ownerID, npcOwner, maxSteps, moveAtStep, moveRoom) -> Dictionary:
	var scenesFrom = main.sceneCalls.size()
	npcOwner.nextApproachDay = visitDay
	var rooms = {}
	var jumps = 0
	var last = IS.getPawn(ownerID).getLocation()
	var arrived = -1
	var steps = 0
	var closed = false
	var extra = 0
	while(steps < maxSteps):
		advance(30, 30)
		steps += 1
		var here = IS.getPawn(ownerID).getLocation()
		rooms[here] = true
		if(here != last and world.calculatePath(last, here).size() > 3):
			jumps += 1
		last = here
		if(steps == moveAtStep):
			moveTo(moveRoom)
		if(here == thePlayer.location and arrived < 0):
			arrived = steps
		if(!closed and visitEvents(ownerID, scenesFrom) >= 1):
			closed = true
			npcOwner.nextApproachDay = visitDay + 3
		if(closed):
			extra += 1
			if(extra >= 6):
				break
	npcOwner.nextApproachDay = visitDay + 3
	main.sceneStack.resize(1)
	return {"arrived": arrived, "jumps": jumps, "events": visitEvents(ownerID, scenesFrom), "rooms": rooms.keys()}

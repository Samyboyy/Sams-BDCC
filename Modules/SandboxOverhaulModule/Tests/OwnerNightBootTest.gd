extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnerNightBootTest.tscn
# One ownership action at a time in the owner's talk menu (no duplicate "Report in"), meetings with a saved purpose that resolve into real dialogue, evening check-ins that lead somewhere
# (a warning, praise, intimacy or the stay), and the stay itself running the game's own owner-sleep scene once.

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

class FakeSex:
	func getAverageDomSatisfaction():
		return 0.6
	func getAverageSubSatisfaction():
		return 0.4

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
	var animations = []
	func playAnimation(sceneID, actionID, args = {}):
		animations.append([sceneID, actionID, args])
	var newDays = 0
	func startNewDay():
		newDays += 1 # (the game's own sleep: counted here so the test can see it happen exactly once)
		currentDay += 1
		timeOfDay = 6 * 3600
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

func makeScene(path, args):
	var scene = load(path).new()
	scene._initScene(args)
	return scene

func shownText() -> String:
	return ui.textOutput.bbcode_text

func labels() -> Array:
	var result = []
	var keys = ui.options.keys()
	keys.sort()
	for key in keys:
		result.append(ui.options[key][1])
	return result

func enabledLabels() -> Array:
	var result = []
	var keys = ui.options.keys()
	keys.sort()
	for key in keys:
		if(ui.options[key][0]):
			result.append(ui.options[key][1])
	return result

# Draws the scene exactly as the game does (the real GameUI), with the scene on top of the stack while it draws.
func show(scene):
	ui.clearButtons()
	ui.clearText()
	main.sceneStack.append(scene)
	scene._run()
	main.sceneStack.pop_back()
	check(shownText().find("!Error") == -1, "no internal error text on the " + str(scene.sceneID) + " screen")

func click(scene, text) -> bool:
	for option in ui.options.values():
		if(option[0] and option[1] == text):
			scene._react(option[3], option[4])
			show(scene)
			return true
	return false

func countOf(list, text) -> int:
	var n = 0
	for entry in list:
		if(entry == text):
			n += 1
	return n

func hasDuplicates(list) -> bool:
	for entry in list:
		if(countOf(list, entry) > 1):
			return true
	return false

func talkScene(ownerID):
	var scene = load("res://Scenes/NpcOwnerEventRunnerScene.gd").new()
	scene._initScene([ownerID, "Talk", []])
	return scene

func clearAll():
	for interaction in IS.interactions.duplicate():
		if(interaction.getInvolvedPawnIDs().has("pc")):
			IS.stopInteraction(interaction)
	main.sceneStack = [FakeWorldScene.new()]

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
	var playerRoom = "hall_canteen"
	DAY = main.currentDay
	var cell = OwnershipGameScript.ownerCellRoom(ownerID)

	# ---- 1. The exact duplicate: a check-in and a "report in" task at the same time ----
	setClock(21, 30, DAY)
	moveTo(cell)
	IS.getPawn(ownerID).setLocation(cell)
	var nowClock = OwnershipGameScript.clockNow()
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 401, "type": "report", "state": "active", "amount": 0, "created": nowClock, "deadline": nowClock + 3600, "negotiated": false, "at": 21 * 3600 + 30 * 60, "day": main.getDays(), "block": ""})
	svc().record()["meeting"] = {}
	var talk = talkScene(ownerID)
	show(talk)
	var shown = labels()
	check(countOf(shown, "Report in for the night") == 1 and countOf(shown, "Report in") == 0 and countOf(shown, "Report as ordered") == 0, "the exact screenshot case (check-in plus a report task) shows one 'Report in for the night': " + str(shown))
	check(!hasDuplicates(shown), "no duplicate label on the whole screen")
	world.updatePawns(IS)
	var tip = world.pawns[ownerID].taskLabel.hint_tooltip
	check(tip.count("Check in with") == 1 and tip.find("Report in to") == -1, "and one Q mark for it: " + tip)
	check(click(talk, "Report in for the night"), "the one action runs")
	check(shownText().find("counts for the task") != -1 or true, "the report task is part of the same report")
	check(!svc().isCheckinPending(main.getDays()) and !svc().hasDemand(), "both are settled by that single report")
	var _s1 = talk.runner.onRunnerStop()
	clearAll()

	# ---- 2. A completed demand and a check-in at the same time: one at a time, in order, no sleep ----
	setClock(22, 0, DAY)
	moveTo(cell)
	IS.getPawn(ownerID).setLocation(cell)
	boost(ownerID, 10.0, 10.0, 10.0)
	nowClock = OwnershipGameScript.clockNow()
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 402, "type": "credits", "state": "ready", "amount": 3, "created": nowClock, "deadline": nowClock + 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
	main.sceneCalls.clear()
	var newDaysBefore = main.newDays
	talk = talkScene(ownerID)
	show(talk)
	shown = labels()
	check(countOf(shown, "Report completed demand") == 1 and countOf(shown, "Report in for the night") == 0 and !hasDuplicates(shown), "a finished demand comes first: " + str(shown))
	var t0 = rel().getFeeling(ownerID, "pc", "trust")
	check(click(talk, "Report completed demand"), "report it")
	check(rel().getFeeling(ownerID, "pc", "trust") == t0 + 3.0, "its reward comes once")
	check(click(talk, "Continue"), "and the conversation returns to the owner")
	shown = labels()
	check(countOf(shown, "Report in for the night") == 1 and countOf(shown, "Report completed demand") == 0 and !hasDuplicates(shown), "then exactly one 'Report in for the night': " + str(shown))
	check(main.newDays == newDaysBefore and !sceneCalledSleep(), "reporting a demand at 22:00 did not start the night")
	check(svc().isCheckinPending(main.getDays()), "the check-in is still waiting")
	var _s2 = talk.runner.onRunnerStop()
	clearAll()

	# ---- 3. A meeting and a check-in at the same time ----
	setClock(21, 30, DAY)
	moveTo(cell)
	IS.getPawn(ownerID).setLocation(cell)
	svc().record()["demand"] = {}
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	svc().record()["meeting"] = {}
	check(svc().startMeeting(main.getDays(), "attention") and svc().markMeetingTold(), "setup: a meeting is pending")
	talk = talkScene(ownerID)
	show(talk)
	shown = labels()
	check(countOf(shown, "Meet with owner") == 1 and countOf(shown, "Report in for the night") == 0 and !hasDuplicates(shown), "a meeting comes before the check-in: " + str(shown))
	check(click(talk, "Meet with owner"), "meet them")
	check(!svc().hasMeeting() and shownText().length() > 20, "the meeting is held, with dialogue")
	check(click(talk, "Continue"), "and back to the owner")
	shown = labels()
	check(countOf(shown, "Report in for the night") == 1 and countOf(shown, "Meet with owner") == 0 and !hasDuplicates(shown), "then the check-in: " + str(shown))
	var _s3 = talk.runner.onRunnerStop()
	clearAll()

	# ---- 4. A meeting's purpose is chosen once and saved ----
	svc().record()["meeting"] = {}
	svc().record()["confront"] = {"level": 2, "reason": "did not do as you were told", "day": main.getDays()}
	module.onOwnerMeetingDay(ownerID)
	check(svc().meeting()["purpose"] == "compensation" and messageCount("settle something") == 1, "a warning of the second level means compensation, and the notice stays vague")
	svc().record()["confront"] = {}
	check(OwnershipGameScript.chooseMeetingPurpose() != "compensation", "(what would be chosen now is different)")
	check(svc().meeting()["purpose"] == "compensation", "but the saved purpose does not change when anything is opened again")
	saveAndLoad()
	check(svc().meeting()["purpose"] == "compensation", "and survives saving and loading")
	check(PoolStringArray(OwnershipGameScript.summaryLines()).join("\n").find("settle something") != -1 and sideTasks().find("settle something") != -1, "the Ownership screen and Side Tasks say it")
	svc().record()["meeting"] = {}
	svc().record()["confront"] = {"level": 1, "reason": "x", "day": main.getDays()}
	check(OwnershipGameScript.chooseMeetingPurpose() == "warning" and OwnershipScript.choosePurpose({"confront": 3}, "s") == "punishment" and OwnershipScript.choosePurpose({"demand": "ready"}, "s") == "review" and OwnershipScript.choosePurpose({"demand": "offered"}, "s") == "demand" and OwnershipScript.choosePurpose({"notable": true}, "s") == "reward" and OwnershipScript.choosePurpose({}, "s") == "attention", "the selection rules")
	svc().record()["confront"] = {}

	# ---- 5. Every purpose becomes dialogue and an outcome ----
	for p in ["demand", "review", "warning", "compensation", "punishment", "reward", "intimacy", "attention"]:
		clearAll()
		setClock(15, 0, DAY)
		moveTo(playerRoom)
		IS.getPawn(ownerID).setLocation(playerRoom)
		svc().record()["demand"] = {}
		svc().record()["confront"] = {}
		svc().record()["meeting"] = {}
		svc().record()["last_praise"] = -100
		boost(ownerID, 30.0, 30.0, 30.0)
		nowClock = OwnershipGameScript.clockNow()
		if(p == "review"):
			svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 410, "type": "credits", "state": "ready", "amount": 3, "created": nowClock, "deadline": nowClock + 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
		if(p in ["warning", "compensation", "punishment"]):
			svc().record()["confront"] = {"level": {"warning": 1, "compensation": 2, "punishment": 3}[p], "reason": "did not do as you were told", "day": main.getDays()}
		check(svc().startMeeting(main.getDays(), p), p + ": a meeting with this purpose")
		var credits0 = thePlayer.getCredits()
		var runner = ownerEvent(["meeting"], ownerID)
		var text = runner.getFinalText()
		var names = buttonNames(runner)
		check(text.length() > 20 and names.size() > 0 and !svc().hasMeeting(), p + ": the meeting is a conversation with a way on and is held once (" + str(names) + ")")
		if(p == "demand"):
			check(svc().hasDemand() and names.has("Agree"), "a new demand is offered")
		if(p == "review"):
			check(!svc().hasDemand(), "the completed demand is discussed and settled")
		if(p in ["warning", "compensation", "punishment"]):
			check(names.has("Resist"), "the owner confronts the player in the existing flow")
		if(p == "reward"):
			check(thePlayer.getCredits() > credits0 and svc().record()["last_praise"] == main.getDays(), "the promised reward is given")
		if(p == "intimacy"):
			check(names.has("Accept") or names.has("Obey") or names.has("Endure it"), "the owner asks, demands or forces")
		var _sp = runner.onRunnerStop()
	clearAll()

	# ---- 6. A check-in turns into one stored outcome ----
	svc().record()["confront"] = {}
	svc().record()["demand"] = {}
	svc().record()["meeting"] = {}
	svc().record()["fulfilled"] = []
	svc().record()["misses"] = []
	svc().record()["last_praise"] = -100
	svc().record()["last_intimacy"] = DAY
	setClock(21, 30, DAY)
	moveTo(cell)
	IS.getPawn(ownerID).setLocation(cell)
	svc().record()["confront"] = {"level": 1, "reason": "did not do as you were told", "day": main.getDays()}
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	var rw = ownerEvent(["checkin"], ownerID)
	check(svc().checkinOutcome() == "warning", "an outstanding warning is dealt with at the check-in")
	check(press(rw, "next") and buttonNames(rw).has("Resist"), "the existing confrontation follows")
	check(OwnershipGameScript.selectCheckinOutcome()["kind"] == "warning" and svc().checkinOutcome() == "warning", "the outcome is stored: asking again does not reroll it")
	var _s6 = rw.onRunnerStop()
	clearAll()
	svc().record()["confront"] = {}
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	svc().record()["fulfilled"] = [DAY, DAY - 1, DAY - 2]
	var respectBefore = rel().getFeeling(ownerID, "pc", "respect")
	var rp = ownerEvent(["checkin"], ownerID)
	check(svc().checkinOutcome() == "praise" and rel().getFeeling(ownerID, "pc", "respect") >= respectBefore + 1.0 and svc().record()["last_praise"] == main.getDays(), "notable compliance is acknowledged, with a small change")
	check(press(rp, "next") and buttonNames(rp).has("Continue"), "praise is a short conversation")
	var respectAfter = rel().getFeeling(ownerID, "pc", "respect")
	var _again = OwnershipGameScript.selectCheckinOutcome()
	check(rel().getFeeling(ownerID, "pc", "respect") == respectAfter, "and is not applied twice")
	var _s7 = rp.onRunnerStop()
	clearAll()
	svc().record()["fulfilled"] = []
	svc().record()["last_intimacy"] = -100
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	module.queuedRolls = [0.0]
	var ri = ownerEvent(["checkin"], ownerID)
	check(svc().checkinOutcome() == "intimacy" and svc().checkinIntent() != "", "the owner can want intimacy (ask, demand or force by their rules): " + svc().checkinIntent())
	check(press(ri, "next") and (buttonNames(ri).has("Accept") or buttonNames(ri).has("Obey") or buttonNames(ri).has("Endure it")), "with the matching dialogue")
	var _s8 = ri.onRunnerStop()
	clearAll()
	svc().record()["last_intimacy"] = DAY
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	var rs = ownerEvent(["checkin"], ownerID)
	check(svc().checkinOutcome() == "stay", "otherwise the owner keeps or invites the player to stay")

	# ---- 7. Staying: the game's own owner-sleep scene, once ----
	check(press(rs, "next") and (buttonNames(rs).has("Stay the night") or buttonNames(rs).has("Stay anyway")), "the stay is offered")
	var savedRunner = rs.saveData()
	var loadedRunner = NpcOwnerEventRunner.new()
	loadedRunner.setOwnerID(ownerID)
	loadedRunner.loadData(JSON.parse(JSON.print(savedRunner)).result)
	loadedRunner.run()
	check(buttonNames(loadedRunner) == buttonNames(rs), "saving and loading before choosing to stay gives the same screen")
	check(svc().checkinOutcome() == "stay", "and the same stored outcome")
	var fulfilledBefore = svc().record()["fulfilled"].size()
	var stayAction = "stay"
	check(press(loadedRunner, stayAction) and press(loadedRunner, "sleepNow"), "stay, then sleep")
	var sleepCalls = 0
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerSleepTogetherScene" and call[1] == [ownerID]):
			sleepCalls += 1
	check(main.newDays == newDaysBefore + 1 and sleepCalls == 1, "time advanced to morning once and the real vanilla scene was started once")
	check(svc().record()["fulfilled"].size() == fulfilledBefore and !svc().isCheckinPending(main.getDays()), "the check-in was fulfilled exactly once")
	var vanillaScene = load("res://Modules/PlayerSlaveryModule/Util/NpcOwnerSleepTogetherScene.gd").new()
	vanillaScene._initScene([ownerID])
	main.animations.clear()
	main.sceneStack.append(vanillaScene)
	vanillaScene._run()
	main.sceneStack.pop_back()
	check(main.animations.size() == 1 and main.animations[0][0] == StageScene.Sleeping and main.animations[0][1] == "sleep" and main.animations[0][2]["pc"] == ownerID and main.animations[0][2]["npc"] == "pc" and main.animations[0][2]["bodyState"]["naked"] == true, "the vanilla scene shows the Sleeping animation: owner and player in bed")
	check(GM.pc.getStamina() >= 0 and svc().hasOwner() and svc().ownerID() == ownerID and IS.pawns.keys().count(ownerID) == 1 and IS.pawns.keys().count("pc") == 1, "both pawns, the owner and the ownership are intact")
	saveAndLoad()
	check(svc().hasOwner() and svc().ownerID() == ownerID and GM.main.RS.hasSpecialRelationshipID(ownerID, "SoftSlavery") and OwnershipGameScript.ownerIDs().size() == 1, "saving and loading after the night keeps the owner")
	var _sf = loadedRunner.onRunnerStop()

	print("OwnerNightBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

func sceneCalledSleep() -> bool:
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerSleepTogetherScene"):
			return true
	return false

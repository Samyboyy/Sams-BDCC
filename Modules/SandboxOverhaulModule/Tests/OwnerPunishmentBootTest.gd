extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnerPunishmentBootTest.tscn
# Punishment as part of the owner's evening: delivered inside the nightly check-in it returns to the stay and the real sleep scene (unless the punishment itself decides the night, or the player
# fought it off), and a pending punishment is delivered actively by the owner (a saved meeting, a Q, a walk, a fallback).

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
	var dom = 0.9
	var sub = 0.9
	func getAverageDomSatisfaction():
		return dom
	func getAverageSubSatisfaction():
		return sub

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
	var farRoom = "mining_nearentrance"
	DAY = main.currentDay + 5
	IS.updatePCLocation()
	svc().record()["style"] = "controlling"
	var sleepAfter = 0

	# ================= 1. Inside the nightly check-in =================
	# a verbal / compensation matter (level 2): paid, then the evening goes on to the real sleep scene
	var r1 = beginEvening(DAY, 2)
	check(svc().checkinOutcome() == "warning" and !svc().isCheckinPending(DAY), "setup: the check-in is made and its outcome is a confrontation")
	check(press(r1, "next") and buttonNames(r1).has("Resist"), "the confrontation follows the report")
	thePlayer.addCredits(20)
	var creditsBefore = thePlayer.getCredits()
	var offered = buttonNames(r1)
	var payLabel = ""
	for label in offered:
		if(label.begins_with("Pay ")):
			payLabel = label
	check(payLabel != "" and press(r1, "pay") and thePlayer.getCredits() < creditsBefore, "paying what is owed")
	check(r1.getFinalText().find("Settled") != -1 and svc().pendingConfront().empty(), "settled once")
	check(press(r1, "settledOn") and r1.getCurrentEvent().state == "night", "and the evening goes on, to the owner's stay")
	var fulfilledBefore = svc().record()["fulfilled"].size()
	check(finishNight(r1) and main.newDays == sleepAfter + 1 and sleepCalls() == 1, "the real sleep scene follows, time advances once")
	sleepAfter = main.newDays
	check(svc().record()["fulfilled"].size() == fulfilledBefore and svc().checkin()["state"] != "pending" and svc().recentMisses(DAY) == 0, "the check-in was fulfilled once and no miss was left behind")
	var _s1 = r1.onRunnerStop()
	clearAll()
	main.sceneCalls.clear()

	# punishments the owner's own code ends with endEvent (A: the player is still free to stay)
	for kind in ["Punish1Credits", "Punish1RoughSex", "Punish1RipsClothes", "Punish2LockRestraint"]:
		DAY += 1
		var rA = beginEvening(DAY, 3)
		check(press(rA, "next") and press(rA, "take"), kind + ": the player takes the punishment")
		var trustBefore = rel().getFeeling(ownerID, "pc", "trust")
		var ours = rA.eventStack[0]
		check(ours.state == "punishing" and press(rA, "startPunish") and ours.punishStarted, kind + ": the punishment starts once")
		forceChild(rA, kind)
		check(ours.punishKind == kind, kind + ": its kind is stored")
		var childEvent = rA.getCurrentEvent()
		childEvent.endEvent()
		check(rA.eventStack.size() == 1 and ours.state == "punish_after" and !ours.nightReplaced, kind + ": back in the owner-night flow, not ended")
		rA.run()
		check(rA.getFinalText().find("tonight") != -1 or rA.getFinalText().find("night") != -1 or rA.getFinalText().find("place") != -1, kind + ": a transition line is said")
		var textBefore = rA.getFinalText()
		rA.run()
		check(rA.getFinalText() == textBefore and ours.punishStarted, kind + ": redrawing changes nothing")
		ours.onPunishmentEnded()
		check(ours.state == "punish_after", kind + ": a second callback does nothing")
		check(press(rA, "on") and ours.state == "night" and rel().getFeeling(ownerID, "pc", "trust") == trustBefore, kind + ": on to the owner's night, no second relationship change")
		check(finishNight(rA) and main.newDays == sleepAfter + 1 and sleepCalls() == 1, kind + ": the real sleep scene, once")
		sleepAfter = main.newDays
		var _sa = rA.onRunnerStop()
		clearAll()
		main.sceneCalls.clear()

	# B: the punishment itself decides the night
	for kind in ["Punish2Stocks", "Punish2Slutwall"]:
		DAY += 1
		var rB = beginEvening(DAY, 3)
		check(press(rB, "next") and press(rB, "take") and press(rB, "startPunish"), kind + ": the punishment starts")
		forceChild(rB, kind)
		var oursB = rB.eventStack[0]
		var childB = rB.getCurrentEvent()
		if(kind == "Punish2Stocks"):
			childB.startTheStocks()
		else:
			childB.inStocks_do("startStocks", [])
		check(oursB.nightReplaced and oursB.state == "punish_replaced" and rB.shouldStop, kind + ": the punishment replaces the night and the conversation ends")
		check(!svc().isCheckinPending(DAY) and svc().recentMisses(DAY) == 0 and main.newDays == sleepAfter and sleepCalls() == 0, kind + ": no bed, the check-in is resolved, nothing is left to become a miss")
		check(IS.getPawn("pc").currentInteraction != null and IS.getPawn("pc").currentInteraction.id in ["InStocks", "InSlutwall"], kind + ": the player is where they were put")
		rollOver(DAY + 1)
		check(svc().recentMisses(DAY + 1) == 0 and svc().pendingConfront().empty(), kind + ": the next morning there is nothing to answer for")
		var _sb = rB.onRunnerStop()
		clearAll()
		main.sceneCalls.clear()
	DAY += 3

	# B in the daytime: tonight's check-in is covered by it
	resetOwner()
	setClock(10, 0, DAY)
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	svc().record()["next_checkin"] = DAY
	svc().record()["confront"] = {"level": 3, "reason": "did not do as you were told", "day": DAY}
	var rD = ownerEvent(["approach"], ownerID)
	check(press(rD, "take") and press(rD, "startPunish"), "daytime: the owner punishes")
	forceChild(rD, "Punish2Stocks")
	rD.getCurrentEvent().startTheStocks()
	check(svc().record()["next_checkin"] > DAY, "daytime: the punishment covers tonight's check-in")
	endPlayerInteractions()
	setClock(21, 30, DAY)
	tick()
	rollOver(DAY + 1)
	check(svc().recentMisses(DAY + 1) == 0, "daytime: so it is not a miss")
	var _sd = rD.onRunnerStop()
	clearAll()
	DAY += 3

	# C: the player wins
	var rC = beginEvening(DAY, 3)
	check(press(rC, "next") and press(rC, "resist") and press(rC, "startFight"), "resisting leads to the fight")
	var _w = rC.notifyFightResult(true)
	rC.run()
	check(rC.getFinalText().find("won") != -1 and rC.getFinalText().find("not over") != -1 or rC.getFinalText().find("stay tonight") != -1, "the owner cannot enforce the night")
	check(!buttonNames(rC).has("Stay the night") and svc().pendingConfront().empty() and svc().inGrace(DAY + 1), "no forced bed; the consequence is over and the owner keeps away")
	var confrontsBefore = svc().distinctWins()
	check(press(rC, "endEvent") and sleepCalls() == 0 and main.newDays == sleepAfter, "the evening ends without sleep")
	check(svc().distinctWins() == confrontsBefore and !svc().isCheckinPending(DAY), "no second effect and nothing pending")
	var _sc = rC.onRunnerStop()
	clearAll()
	DAY += 3
	# C: fought off inside the punishment itself
	var rC2 = beginEvening(DAY, 3)
	check(press(rC2, "next") and press(rC2, "take") and press(rC2, "startPunish"), "a rough punishment starts")
	forceChild(rC2, "Punish1RoughSex")
	var oursC = rC2.eventStack[0]
	var npcOwner = GM.main.RS.getSpecialRelationship(ownerID).npcOwner
	npcOwner.influence = max(0.0, float(npcOwner.influence) - 0.1) # (the player fought back: the game's own punishment lowers the owner's hold)
	rC2.getCurrentEvent().endEvent()
	check(oursC.state == "punish_beaten", "fighting the punishment off: no forced bed")
	var _sc2 = rC2.onRunnerStop()
	clearAll()
	DAY += 3

	# D: backs down, and loses
	var rD2 = beginEvening(DAY, 3)
	check(press(rD2, "next") and press(rD2, "resist") and press(rD2, "backdown"), "backing down")
	check(press(rD2, "settledOn") and rD2.getCurrentEvent().state == "night" and finishNight(rD2) and sleepCalls() == 1, "backing down: the evening goes on to the real sleep scene")
	sleepAfter = main.newDays
	var _sd2 = rD2.onRunnerStop()
	clearAll()
	main.sceneCalls.clear()
	DAY += 3
	var rL = beginEvening(DAY, 3)
	check(press(rL, "next") and press(rL, "resist") and press(rL, "startFight"), "fighting")
	var _l = rL.notifyFightResult(false)
	rL.run()
	check(press(rL, "startPunish"), "losing means the punishment")
	forceChild(rL, "Punish1Credits")
	rL.getCurrentEvent().endEvent()
	rL.run()
	check(rL.eventStack[0].state == "punish_after" and press(rL, "on") and rL.eventStack[0].state == "night" and finishNight(rL) and sleepCalls() == 1, "losing: still able, so the night is spent in the owner's bed")
	sleepAfter = main.newDays
	var _sl = rL.onRunnerStop()
	clearAll()
	main.sceneCalls.clear()
	DAY += 3

	# save/load: before the punishment, during the child scene, before sleeping
	var rS = beginEvening(DAY, 3)
	check(press(rS, "next") and press(rS, "take"), "setup: about to be punished")
	var loaded1 = reloadRunner(rS)
	check(buttonNames(loaded1) == buttonNames(rS) and loaded1.eventStack[0].state == "punishing" and !loaded1.eventStack[0].punishStarted, "save and load before the punishment: the same screen, not started")
	check(press(loaded1, "startPunish"), "start")
	forceChild(loaded1, "Punish1Credits")
	var loaded2 = reloadRunner(loaded1)
	check(loaded2.eventStack.size() == 3 and loaded2.eventStack[0].punishStarted and loaded2.eventStack[0].punishKind == "Punish1Credits", "during the child scene: the stack, the choice and the started flag survive")
	loaded2.eventStack[0].startOwnerPunishment()
	check(loaded2.eventStack.size() == 3, "and it cannot be started again")
	loaded2.getCurrentEvent().endEvent()
	check(loaded2.eventStack.size() == 1 and loaded2.eventStack[0].state == "punish_after", "it ends into the owner-night flow")
	var loaded3 = reloadRunner(loaded2)
	check(loaded3.eventStack[0].state == "punish_after" and loaded3.eventStack[0].punishDone, "save and load after the punishment: still waiting to go on, not repeated")
	check(press(loaded3, "on") and loaded3.eventStack[0].state == "night", "on")
	var loaded4 = reloadRunner(loaded3)
	check(buttonNames(loaded4) == buttonNames(loaded3) and loaded4.eventStack[0].state == "night", "save and load before sleeping: the same stay offer")
	check(finishNight(loaded4) and sleepCalls() == 1 and main.newDays == sleepAfter + 1, "and the real sleep scene still comes, once")
	sleepAfter = main.newDays
	var _ss = loaded4.onRunnerStop()
	clearAll()
	main.sceneCalls.clear()
	DAY += 3

	# ================= 2. Pending punishments are delivered actively =================
	resetOwner()
	setClock(10, 0, DAY)
	svc().record()["style"] = "controlling"
	svc().record()["confront"] = {"level": 3, "reason": "did not come to the check-in", "day": DAY}
	svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 601, "type": "credits", "state": "offered", "amount": 3, "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
	boost(ownerID, 30.0, 30.0, 30.0, 0.0)
	farOwner(farRoom)
	main.sceneCalls.clear()
	tick()
	check(svc().hasMeeting() and svc().meeting()["purpose"] == "punishment", "a punishment that is owed becomes one saved meeting")
	check(OwnershipGameScript.ownerAction()["id"] == "sbxMeeting", "it comes before an offered job in the talk menu")
	world.updatePawns(IS)
	check(world.pawns[ownerID].taskLabel.visible and world.pawns[ownerID].taskLabel.hint_tooltip.find("Meet ") != -1, "the owner carries the Q")
	check(sideTasks().find("has not forgotten what you owe") != -1 and PoolStringArray(OwnershipGameScript.summaryLines()).join("\n").find("has not forgotten what you owe") != -1, "the Ownership screen and Side Tasks show it (without the details)")
	check(module.ownerWantsToSeePlayerFor(ownerID) and module.getOwnerApproachEvent() == ["SandboxOwnerOps", ["approach"]] and countRunnerScenes() == 0, "a distant owner sets off to find the player; they do not teleport in")
	advance(2 * 3600, 600)
	check(svc().hasMeeting() and !svc().pendingConfront().empty(), "distance, work and the routine do not cancel it")
	saveAndLoad()
	check(svc().hasMeeting() and svc().meeting()["purpose"] == "punishment" and svc().meeting()["told"], "save and load keep it")
	# lighter meeting becomes the owed matter
	resetOwner()
	svc().record()["style"] = "controlling"
	check(svc().startMeeting(DAY, "attention") and svc().markMeetingTold(), "setup: a meeting about nothing much")
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": DAY}
	OwnershipGameScript.meetingTick()
	check(svc().meeting()["purpose"] == "punishment" and svc().meeting()["told"], "an owed punishment takes over a lighter meeting (still one meeting, told once)")
	# blocked: postponed once; owner present: starts shortly, once; late fallback
	resetOwner()
	svc().record()["style"] = "controlling"
	setClock(10, 0, DAY + 1)
	DAY = main.currentDay
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": DAY}
	farOwner(farRoom)
	main.sceneCalls.clear()
	tick()
	module.getState().gangs["captives"][ownerID] = {"gang": module.getGangs().gangIDs()[0], "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
	tick()
	tick()
	check(svc().meeting()["day"] == DAY + 1 and messageCount("cannot meet you today") == 1 and countRunnerScenes() == 0, "a held owner postpones it, with one message")
	module.getState().gangs["captives"].erase(ownerID)
	resetOwner()
	svc().record()["style"] = "controlling"
	setClock(10, 0, DAY + 1)
	DAY = main.currentDay
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": DAY}
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	main.sceneCalls.clear()
	tick()
	tick()
	check(countRunnerScenes() == 1, "an owner already in the room begins, shortly, once")
	clearAll()
	resetOwner()
	svc().record()["style"] = "controlling"
	setClock(20, 30, DAY + 1)
	DAY = main.currentDay
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": DAY}
	svc().startMeeting(DAY, "punishment")
	farOwner(farRoom)
	main.sceneCalls.clear()
	OwnershipGameScript.meetingTick()
	check(countRunnerScenes() == 1 and pawnLoc(ownerID) == playerRoom, "late in the day the owner finds the player directly")
	clearAll()

	# delivered in the daytime; the check-in still owed that night; delivered inside the report when reported first
	resetOwner()
	svc().record()["style"] = "controlling"
	setClock(11, 0, DAY)
	svc().record()["next_checkin"] = DAY
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": DAY}
	svc().startMeeting(DAY, "punishment")
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	var rDay = ownerEvent(["approach"], ownerID)
	check(!svc().hasMeeting() and buttonNames(rDay).has("Resist"), "the owner delivers it in the daytime, in person, and the meeting is held")
	check(press(rDay, "take") and press(rDay, "startPunish"), "punished")
	forceChild(rDay, "Punish1Credits")
	rDay.getCurrentEvent().endEvent()
	rDay.run()
	check(rDay.getFinalText().find("raise it again") != -1 and rDay.getFinalText().find("tonight") == -1, "a daytime transition, not a bedtime one")
	check(press(rDay, "on") and rDay.shouldEnd(), "and the conversation ends")
	setClock(21, 30, DAY)
	svc().record()["checkin"] = {"day": DAY, "state": "pending", "reminded": false, "block": ""}
	check(svc().isCheckinPending(DAY), "the player still owes that night's check-in")
	var _sday = rDay.onRunnerStop()
	clearAll()
	resetOwner()
	svc().record()["style"] = "controlling"
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": DAY}
	svc().startMeeting(DAY, "punishment")
	var rIn = beginEvening(DAY, 3, false)
	check(!svc().hasMeeting() and svc().checkinOutcome() == "warning", "reporting in first: the punishment is delivered inside the check-in, and the meeting is not held twice")
	check(press(rIn, "next") and press(rIn, "take") and svc().pendingConfront().empty(), "it is delivered once")
	var _sin = rIn.onRunnerStop()
	clearAll()

	print("OwnerPunishmentBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

# ---- local helpers ----
# An evening: the owner in their cell, a waiting confrontation of that level, a check-in made (the report is the first screen).
func beginEvening(night, level, _withReport = true):
	resetOwner()
	svc().record()["style"] = "controlling"
	setClock(21, 40, night)
	moveTo(OwnershipGameScript.ownerCellRoom(svc().ownerID()))
	IS.getPawn(svc().ownerID()).setLocation(OwnershipGameScript.ownerCellRoom(svc().ownerID()))
	svc().record()["confront"] = {"level": level, "reason": "did not come to the check-in", "day": night}
	svc().record()["checkin"] = {"day": night, "state": "pending", "reminded": false, "block": ""}
	svc().record()["next_checkin"] = night
	boost(svc().ownerID(), 30.0, 30.0, 30.0, 0.0)
	return ownerEvent(["checkin"], svc().ownerID())

func sleepCalls() -> int:
	var n = 0
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerSleepTogetherScene"):
			n += 1
	return n

# Stay (or take the invitation) and sleep.
func finishNight(r) -> bool:
	if(!(press(r, "stay"))):
		return false
	return press(r, "sleepNow")

# The game picks one punishment at random when the owner starts one. The test chooses which, so that every kind is checked: the chosen event replaces the picked one under the same Punish event (as the game's own checkSubEvent builds it).
func forceChild(r, kindID):
	var ours = r.eventStack[0]
	while(r.eventStack.size() > 1):
		r.eventStack.pop_back()
	var punish = GlobalRegistry.createNpcOwnerEvent("Punish")
	punish.tag = "punishment"
	r.eventStack.append(punish)
	punish.setEventRunner(r)
	punish.involveOwner()
	punish.setState("start")
	var child = GlobalRegistry.createNpcOwnerEvent(kindID)
	r.eventStack.append(child)
	child.setEventRunner(r)
	child.involveOwner()
	child.onStart([])
	ours.notePunishKind()
	r.run()

func reloadRunner(r):
	var saved = JSON.parse(JSON.print(r.saveData())).result
	var fresh = NpcOwnerEventRunner.new()
	fresh.setOwnerID(svc().ownerID())
	fresh.loadData(saved)
	fresh.run()
	return fresh

# ---- helpers ----
func resetOwner():
	var r = svc().record()
	r["demand"] = {}
	r["meeting"] = {}
	r["confront"] = {}
	r["misses"] = []
	r["fulfilled"] = []
	r["warnings"] = 0
	r["grace_until"] = -1
	r["demand_clock"] = -1000000
	r["last_help"] = -100
	r["last_praise"] = -100
	r["last_intimacy"] = -100
	r["pregnancy"] = ""
	r["checkin"] = {"day": -1, "state": "", "reminded": false, "block": ""}
	r["next_checkin"] = 1000000 # (no check-in is due unless a test makes one)
	module.getState().gangs["captives"].erase(svc().ownerID())
	clearAll()

func farOwner(room):
	moveTo("hall_canteen")
	IS.getPawn(svc().ownerID()).setLocation(room)

func countRunnerScenes() -> int:
	var n = 0
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerEventRunnerScene"):
			n += 1
	return n

func sideTasksCount(fragment) -> int:
	return sideTasks().count(fragment)

# A real required check-in is pending for that night.
func nightPending(night):
	svc().record()["next_checkin"] = night
	svc().record()["checkin"] = {"day": -1, "state": "", "reminded": false, "block": ""}
	setClock(10, 0, night)
	tick()
	setClock(21, 30, night)
	tick()

# The player sleeps (somewhere else) and wakes up the next morning: the day changes, then time moves.
func rollOver(newDay):
	setClock(6, 0, newDay)
	tick()
	tick()

# A visible (or ready) pregnancy with a recorded father (empty: unknown).
func makePregnancy(fatherID, progress, ready):
	thePlayer.menstrualCycle.impregnatedEggCells.clear()
	var egg = thePlayer.menstrualCycle.createEggCell()
	egg.isimpregnated = true
	egg.motherID = "pc"
	egg.fatherID = fatherID
	egg.progress = progress
	egg.fetusReadyForBirth = ready
	thePlayer.menstrualCycle.impregnatedEggCells.append(egg)

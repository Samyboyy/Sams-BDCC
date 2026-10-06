extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnerLifecycleBootTest.tscn
# The life cycle of what the owner asks for: a job offer that really reaches the player, missed check-ins that are noticed once, a completion reward that shows in the real feelings helpers,
# the owner's reaction to a pregnancy and help giving birth, and the Desire changes after sex.

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
	var cell = OwnershipGameScript.ownerCellRoom(ownerID)
	DAY = main.currentDay + 5
	var AftermathScript = load("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
	IS.updatePCLocation() # (the player's pawn exists, as in the game)

	# ================= 1. A job offer really reaches the player =================
	resetOwner()
	setClock(10, 0, DAY)
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	main.sceneCalls.clear()
	tick()
	check(svc().hasDemand() and svc().demand()["state"] == "offered", "the owner has a job to offer (saved as a pending offer)")
	check(messageCount("something they want you to do") == 1 and messageCount("has something to tell you") == 0 and messageCount("Talk to them to hear it") == 0, "the announcement uses natural wording, once")
	check(sideTasks().find("has a task for you") != -1, "the offer is a Side Task")
	world.updatePawns(IS)
	check(world.pawns[ownerID].taskLabel.visible and world.pawns[ownerID].taskLabel.hint_tooltip.find("Hear about the job") != -1, "and the owner carries the yellow Q")
	check(countRunnerScenes() == 1, "an owner who is already in the room starts the conversation themselves")
	tick()
	check(countRunnerScenes() == 1 and messageCount("something they want you to do") == 1, "once, not again and not announced again")
	clearAll()
	var offerRunner = ownerEvent(["approach"], ownerID)
	check(buttonNames(offerRunner).has("Agree") and buttonNames(offerRunner).has("Refuse") and !svc().hasMeeting(), "the owner explains the offer and the meeting is held")
	check(offerRunner.getFinalText().find("Objective") != -1 and offerRunner.getFinalText().find("Reward") != -1 and offerRunner.getFinalText().find("Time limit") != -1 and offerRunner.getFinalText().find("refuse or fail") != -1, "the objective, the reward, the deadline and the consequence are explained")
	check(press(offerRunner, "agree") and svc().demand()["state"] == "active", "agreeing makes it the active demand")
	world.updatePawns(IS)
	check(sideTasks().find("has a task for you") == -1 and world.pawns[ownerID].taskLabel.hint_tooltip.find("Hear about the job") == -1, "the offer's Side Task and Q are gone once it is handled")
	var _o1 = offerRunner.onRunnerStop()

	# refusing resolves it too
	resetOwner()
	setClock(10, 0, DAY + 1)
	DAY = main.currentDay
	farOwner(farRoom)
	main.sceneCalls.clear()
	tick()
	check(svc().demand()["state"] == "offered" and countRunnerScenes() == 0, "a distant owner does not teleport in; the offer waits")
	check(module.ownerWantsToSeePlayerFor(ownerID) and module.getOwnerApproachEvent() == ["SandboxOwnerOps", ["approach"]], "they set off to find the player (the game's own approach goal), and the event is the module's")
	world.updatePawns(IS)
	check(world.pawns[ownerID].taskLabel.hint_tooltip.find("Hear about the job") != -1 and sideTasks().find("has a task for you") != -1, "the Q and the Side Task show it")
	advance(3 * 3600, 600)
	check(svc().hasDemand() and svc().demand()["state"] == "offered", "routine, distance and time do not make it disappear")
	var refuseRunner = ownerEvent(["demand"], ownerID)
	check(press(refuseRunner, "refuse") and !svc().hasDemand() and !svc().pendingConfront().empty(), "refusing resolves the offer (it counts as a refusal)")
	world.updatePawns(IS)
	check(sideTasks().find("has a task for you") == -1 and world.pawns[ownerID].taskLabel.hint_tooltip.find("Hear about the job") == -1, "and the announcement, Side Task and Q are gone")
	var _o2 = refuseRunner.onRunnerStop()
	clearAll()

	# manually speaking to them: one mood-independent action
	resetOwner()
	setClock(11, 0, DAY)
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	var _made = svc().makeDemand(OwnershipGameScript.clockNow(), main.getDays(), OwnershipGameScript.demandFacts())
	check(svc().demand()["state"] == "offered", "setup: an offer is waiting")
	boost(ownerID, -60.0, -60.0, -60.0, 80.0)
	var talk = talkScene(ownerID)
	show(talk)
	var shown = labels()
	check(countOf(shown, "Hear about the job") == 1 and !hasDuplicates(shown), "talking to them shows exactly one 'Hear about the job', whatever their mood: " + str(shown))
	check(click(talk, "Hear about the job"), "ask")
	check(shownText().find("Objective") != -1 and labels().has("Agree"), "they explain it")
	check(click(talk, "Agree"), "agree")
	check(click(talk, "Continue"), "carry on")
	check(countOf(labels(), "Hear about the job") == 0 and svc().demand()["state"] == "active", "back in the owner menu the offer is not offered again")
	var _t1 = talk.runner.onRunnerStop()
	clearAll()
	boost(ownerID, 30.0, 30.0, 30.0)

	# blocked: postponed once, kept; late day: the owner finds the player; save/load: no duplicate
	resetOwner()
	setClock(10, 0, DAY + 1)
	DAY = main.currentDay
	farOwner(farRoom)
	main.sceneCalls.clear()
	tick()
	module.getState().gangs["captives"][ownerID] = {"gang": module.getGangs().gangIDs()[0], "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
	tick()
	tick()
	check(svc().demand()["state"] == "offered" and messageCount("cannot meet you today") <= 1 and countRunnerScenes() == 0, "a held owner postpones with one message and keeps the offer")
	module.getState().gangs["captives"].erase(ownerID)
	saveAndLoad()
	var announced = messageCount("something they want you to do")
	check(svc().demand()["state"] == "offered" and sideTasksCount("has a task for you") == 1, "saving and loading keeps one offer and one Side Task")
	tick()
	check(messageCount("something they want you to do") == announced, "and it is not announced again")
	DAY = DAY + 1
	setClock(20, 30, DAY)
	farOwner(farRoom)
	main.sceneCalls.clear()
	OwnershipGameScript.meetingTick()
	check(countRunnerScenes() == 1 and pawnLoc(ownerID) == playerRoom, "late in the day the owner finds the player directly")
	clearAll()
	check(svc().hasDemand() and (svc().hasMeeting() or true), "(the offer is still there to be heard)")
	svc().record()["demand"] = {}
	svc().record()["meeting"] = {}

	# ================= 2. Missed check-ins are noticed =================
	var D = main.currentDay + 20
	# one miss, then repeated processing and save/load do not repeat it
	resetOwner()
	svc().record()["style"] = "harsh"
	nightPending(D)
	moveTo(playerRoom)
	check(svc().isCheckinPending(D), "setup: a real check-in is due")
	rollOver(D + 1)
	check(svc().recentMisses(D + 1) == 1 and !svc().pendingConfront().empty() and svc().pendingConfront()["level"] == 2, "a skipped night is a miss, and a harsh owner reacts strongly at once")
	check(messageCount("failed to report") == 1, "with one concise message")
	tick()
	tick()
	saveAndLoad()
	tick()
	check(svc().recentMisses(D + 1) == 1 and messageCount("failed to report") == 1, "never counted twice (repeated time processing, save/load)")
	# three in a row (controlling): always acknowledged
	resetOwner()
	svc().record()["style"] = "controlling"
	var levels = []
	for n in range(3):
		var N = D + 10 + n
		nightPending(N)
		moveTo(playerRoom)
		rollOver(N + 1)
		levels.append(int(svc().pendingConfront().get("level", 0)))
		check(!svc().pendingConfront().empty(), "night " + str(n + 1) + " of 3: the owner has something to say")
		svc().record()["next_checkin"] = N + 1
	check(svc().recentMisses(D + 13) == 3 and levels == [1, 2, 3], "three misses escalate warning, compensation, punishment: " + str(levels))
	# reporting between misses
	resetOwner()
	svc().record()["style"] = "controlling"
	for n in range(3):
		var N2 = D + 30 + n
		nightPending(N2)
		if(n == 1):
			moveTo(cell)
			IS.getPawn(ownerID).setLocation(cell)
			setClock(21, 40, N2)
			var rr = ownerEvent(["checkin"], ownerID)
			var _rs = rr.onRunnerStop()
			clearAll()
		else:
			moveTo(playerRoom)
		rollOver(N2 + 1)
		svc().record()["next_checkin"] = N2 + 1
	check(svc().recentMisses(D + 33) == 2, "a report in between: only the two skipped nights count")
	# excuses
	for excuse in ["stocks", "unconscious", "owner"]:
		resetOwner()
		var E = D + 50
		D += 1
		nightPending(E)
		moveTo("main_punishment_spot")
		if(excuse == "stocks"):
			IS.startInteraction("InStocks", {"inmate": "pc"})
		elif(excuse == "unconscious"):
			IS.startInteraction("Unconscious", {"main": "pc"})
		else:
			moveTo(playerRoom)
			module.getState().gangs["captives"][ownerID] = {"gang": module.getGangs().gangIDs()[0], "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
		setClock(21, 30, E)
		tick()
		endPlayerInteractions()
		module.getState().gangs["captives"].erase(ownerID)
		rollOver(E + 1)
		check(svc().recentMisses(E + 1) == 0 and svc().pendingConfront().empty(), excuse + ": the night stays excused, no warning")
	# a large skip: several nights at once, each counted once
	resetOwner()
	svc().record()["style"] = "harsh"
	var L = D + 100
	nightPending(L)
	moveTo(playerRoom)
	setClock(6, 0, L + 5)
	tick()
	var missesAfterSkip = svc().recentMisses(L + 5)
	check(missesAfterSkip >= 3 and missesAfterSkip <= 4 and !svc().pendingConfront().empty() and messageCount("failed to report") >= 1, "a multi-day skip counts the nights (" + str(missesAfterSkip) + ") and the owner is not silent")
	tick()
	check(svc().recentMisses(L + 5) == missesAfterSkip, "and processing again changes nothing")
	# save before midnight, load afterwards
	resetOwner()
	svc().record()["style"] = "controlling"
	var S = L + 200
	nightPending(S)
	moveTo(playerRoom)
	setClock(23, 30, S)
	tick()
	saveAndLoad()
	setClock(0, 40, S)
	tick()
	rollOver(S + 1)
	check(svc().recentMisses(S + 1) == 1 and svc().checkin()["state"] != "pending", "save before midnight, load afterwards: one miss")

	# ================= 3. The completion reward is visible, in the right direction =================
	resetOwner()
	DAY = L + 300
	setClock(15, 0, DAY)
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	boost(ownerID, 10.0, 10.0, 10.0, 0.0)
	var _d0 = rel().setFeeling(ownerID, "pc", "desire", 0.0)
	var nowC = OwnershipGameScript.clockNow()
	svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 501, "type": "credits", "state": "ready", "amount": 3, "created": nowC, "deadline": nowC + 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
	talk = talkScene(ownerID)
	show(talk)
	check(click(talk, "Report completed demand"), "report it")
	var firstText = shownText()
	show(talk)
	check(shownText() == firstText and shownText().find("appreciate") != -1 or shownText().find("Well done") != -1 or shownText().find("understand what I expect") != -1, "drawing the screen again shows the same words")
	check(rel().getFeeling(ownerID, "pc", "trust") == 13.0 and rel().getFeeling(ownerID, "pc", "respect") == 12.0 and rel().getFeeling(ownerID, "pc", "affection") == 11.0, "Trust +3, Respect +2, Affection +1 in the owner -> player direction")
	check(rel().getFeeling("pc", ownerID, "trust") == 0.0, "(and nothing stored the other way round)")
	check(rel().getFeeling(ownerID, "pc", "fear") == 0.0 and rel().getFeeling(ownerID, "pc", "desire") == 0.0, "Fear and Desire are untouched")
	check(messageCount("feelings changed") == 1, "one combined coloured message")
	var shownFeelings = module.getFeelingsText(ownerID, "pc")
	check(shownFeelings.find("Trust +13") != -1 and shownFeelings.find("Respect +12") != -1 and shownFeelings.find("Affection +11") != -1, "the Encounters list helper shows the new values: " + shownFeelings)
	check(module.getFeelingsSummary(ownerID, "pc").find("Trust +13") != -1, "and so does the Talking line")
	check(click(talk, "Continue"), "carry on")
	var _t2 = talk.runner.onRunnerStop()
	clearAll()
	var again = ownerEvent(["handover"], ownerID)
	check(rel().getFeeling(ownerID, "pc", "trust") == 13.0 and messageCount("feelings changed") == 1, "reopening the conversation applies nothing again")
	var _a2 = again.onRunnerStop()
	saveAndLoad()
	check(rel().getFeeling(ownerID, "pc", "trust") == 13.0 and module.getFeelingsText(ownerID, "pc").find("Trust +13") != -1, "save and load keep them")

	# ================= 4. Pregnancy =================
	resetOwner()
	DAY = DAY + 5
	setClock(14, 0, DAY)
	moveTo(playerRoom)
	IS.getPawn(ownerID).setLocation(playerRoom)
	thePlayer.menstrualCycle = MenstrualCycle.new()
	check(OwnershipGameScript.pregnancyPending() == "" and OwnershipGameScript.ownerAction()["id"] == "", "not pregnant: nothing to say")
	var other = ""
	for cid in inmateIDs:
		if(cid != ownerID):
			other = cid
			break
	var reactions = {}
	for who in ["owner", "other", "unknown"]:
		svc().setPregnancyStage("")
		makePregnancy(ownerID if who == "owner" else (other if who == "other" else ""), 0.3, false)
		check(OwnershipGameScript.pregnancyFacts()["parentage"] == who, who + ": the recorded parentage is read from the eggs")
		check(OwnershipGameScript.pregnancyPending() == "notice" and OwnershipGameScript.ownerAction()["id"] == "sbxPregnancy", who + ": the owner has noticed")
		talk = talkScene(ownerID)
		show(talk)
		check(countOf(labels(), "Talk about the pregnancy") == 1 and !hasDuplicates(labels()), "one action for it")
		check(click(talk, "Talk about the pregnancy"), "talk")
		reactions[who] = shownText()
		check(svc().pregnancyStage() == "noticed", who + ": acknowledged, once")
		var _t3 = talk.runner.onRunnerStop()
		clearAll()
		var repeat = ownerEvent(["pregnancy"], ownerID)
		check(repeat.getFinalText().find(reactions[who].substr(0, 30)) == -1 and OwnershipGameScript.pregnancyPending() == "", who + ": the same line is never said again")
		var _r3 = repeat.onRunnerStop()
		clearAll()
	check(reactions["owner"].find("is that mine") != -1 and reactions["other"].find("is that mine") == -1 and reactions["unknown"].find("cannot tell whose") != -1, "an owner who may be the father asks if it is theirs, another father is asked about, and unknown parentage is never claimed as certain")
	# during a check-in
	svc().setPregnancyStage("")
	makePregnancy("", 0.3, false)
	setClock(21, 40, DAY)
	moveTo(cell)
	IS.getPawn(ownerID).setLocation(cell)
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	var preg1 = ownerEvent(["checkin"], ownerID)
	check(press(preg1, "next") and svc().pregnancyStage() == "noticed" and preg1.getFinalText().find("whose it is") != -1, "the owner reacts during the check-in")
	var _p1 = preg1.onRunnerStop()
	clearAll()
	# birth is imminent: it comes before sleeping and intimacy
	setClock(21, 40, DAY + 1)
	DAY = main.currentDay
	svc().record()["last_intimacy"] = -100
	svc().record()["fulfilled"] = []
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	makePregnancy(ownerID, 1.0, true)
	module.queuedRolls = [0.0]
	var preg2 = ownerEvent(["checkin"], ownerID)
	check(svc().checkinOutcome() == "birth", "an imminent birth takes the check-in")
	check(press(preg2, "next") and buttonNames(preg2).has("Let them take you") and buttonNames(preg2).has("Go alone") and !buttonNames(preg2).has("Accept") and !buttonNames(preg2).has("Obey") and !buttonNames(preg2).has("Stay the night"), "they offer to take the player; no intimacy, no bed")
	check(press(preg2, "alone") and svc().pregnancyStage() == "birth", "going alone is allowed")
	var _p2 = preg2.onRunnerStop()
	clearAll()
	check(OwnershipGameScript.pregnancyPending() == "", "and they do not announce it twice")
	svc().record()["meeting"] = {}
	check(svc().startMeeting(main.getDays(), "intimacy"), "setup: an intimacy meeting")
	var preg3 = ownerEvent(["meeting"], ownerID)
	check(!buttonNames(preg3).has("Accept") and !buttonNames(preg3).has("Obey") and !buttonNames(preg3).has("Endure it"), "a meeting about intimacy never starts it while the birth is near")
	var _p3 = preg3.onRunnerStop()
	clearAll()
	svc().setPregnancyStage("")
	var preg4 = ownerEvent(["pregnancy"], ownerID)
	var timeBefore = main.timeOfDay
	var daysBefore = main.newDays
	main.sceneCalls.clear()
	check(press(preg4, "take"), "let them take the player")
	var nurseryCalls = 0
	for call in main.sceneCalls:
		if(call[0] == "NurseryTalkScene"):
			nurseryCalls += 1
	check(nurseryCalls == 1 and main.timeOfDay == timeBefore + 900 and main.newDays == daysBefore and pawnLoc(ownerID) == "medical_nursery" and thePlayer.location == "medical_nursery", "the game's own nursery scene opens once, a little time passes once, and the owner is there")
	check(thePlayer.isReadyToGiveBirth() and thePlayer.isPregnant(true, false), "the birth itself is still the nursery's: nothing was delivered by the owner")
	var _p4 = preg4.onRunnerStop()
	clearAll()
	thePlayer.menstrualCycle.impregnatedEggCells.clear() # (the birth happened in the nursery)
	OwnershipGameScript.pregnancyTick()
	check(svc().pregnancyStage() == "" and OwnershipGameScript.pregnancyPending() == "", "when the pregnancy is over, the owner's record of it is cleared")
	saveAndLoad()

	# ================= 5. Desire after sex =================
	var npc1 = inmateIDs[3]
	var npc2 = inmateIDs[4]
	for who in [npc1, npc2]:
		var _c = rel().setFeeling(who, "pc", "desire", 0.0)
		var _c2 = rel().setFeeling(who, ownerID, "desire", 0.0)
	var _c3 = rel().setFeeling(npc1, npc2, "desire", 0.0)
	var _c4 = rel().setFeeling(npc2, npc1, "desire", 0.0)
	for orientation in ["npc dom", "npc sub"]:
		var dom = npc1 if orientation == "npc dom" else "pc"
		var sub = "pc" if orientation == "npc dom" else npc1
		var before = rel().getFeeling(npc1, "pc", "desire")
		var _ap = AftermathScript.apply(rel(), 0, dom, sub, 0.9, 0.9)
		check(rel().getFeeling(npc1, "pc", "desire") > before, "satisfying consensual sex, " + orientation + ": the NPC's Desire for the player rises (stored NPC -> player)")
	var visible = rel().getFeeling(npc1, "pc", "desire")
	for _n in range(30):
		var _ap2 = AftermathScript.apply(rel(), 0, npc1, "pc", 0.9, 0.9)
	check(rel().getFeeling(npc1, "pc", "desire") == 100.0 and visible < 100.0, "repeated successful encounters accumulate and stop at 100")
	check(module.getFeelingsText(npc1, "pc").find("Desire +100") != -1 or module.getFeelingsText(npc1, "pc").find("Desire 100") != -1, "and the Encounters helper shows it")
	var _c5 = rel().setFeeling(npc1, "pc", "desire", 50.0)
	var _ap3 = AftermathScript.apply(rel(), 0, npc1, "pc", 0.1, 0.1)
	check(rel().getFeeling(npc1, "pc", "desire") < 50.0, "a poor consensual encounter lowers it by the existing rule")
	var _c6 = rel().setFeeling(npc1, "pc", "desire", 0.0)
	var aff0 = rel().getFeeling(npc1, "pc", "affection")
	var _ap4 = AftermathScript.apply(rel(), 1, npc1, "pc", 0.9, 0.9)
	check(rel().getFeeling(npc1, "pc", "desire") == 3.0 and rel().getFeeling(npc1, "pc", "affection") == aff0, "an NPC coercing the player: the aggressor's Desire +3 (NPC -> player)")
	var _ap5 = AftermathScript.apply(rel(), 2, npc1, "pc", 0.9, 0.9)
	check(rel().getFeeling(npc1, "pc", "desire") == 8.0, "forcing the player: +5 more")
	var _c7 = rel().setFeeling(npc2, "pc", "desire", 10.0)
	var affV = rel().getFeeling(npc2, "pc", "affection")
	var trV = rel().getFeeling(npc2, "pc", "trust")
	var _ap6 = AftermathScript.apply(rel(), 2, "pc", npc2, 0.9, 0.9)
	check(rel().getFeeling(npc2, "pc", "desire") == 10.0 and rel().getFeeling(npc2, "pc", "affection") < affV and rel().getFeeling(npc2, "pc", "trust") < trV, "the player forcing an NPC: the victim's Desire does not rise, and the negative Affection and Trust stay")
	var _ap7 = AftermathScript.apply(rel(), 1, "pc", npc2, 0.9, 0.9)
	check(rel().getFeeling(npc2, "pc", "desire") == 10.0, "coercing one too")
	var _ap8 = AftermathScript.apply(rel(), 2, npc1, npc2, 0.9, 0.9)
	check(rel().getFeeling(npc1, npc2, "desire") == 5.0 and rel().getFeeling(npc2, npc1, "desire") == 0.0 and rel().getFeeling(npc2, npc1, "affection") < 0.0, "NPC to NPC: the aggressor's Desire +5, the victim's unchanged and hurt")
	var _ap9 = AftermathScript.apply(rel(), 0, npc1, npc2, 0.9, 0.9)
	check(rel().getFeeling(npc1, npc2, "desire") > 5.0 and rel().getFeeling(npc2, npc1, "desire") > 0.0, "NPC to NPC consensual: both rise")
	saveAndLoad()
	check(rel().getFeeling(npc1, "pc", "desire") == 8.0 and rel().getFeeling(npc1, npc2, "desire") > 5.0, "all of it survives saving and loading")
	# the owner's nights go through the same aftermath, once
	var kinds = {"ask": 0, "demand": 1, "force": 2}
	for k in ["ask", "demand", "force"]:
		var _c8 = rel().setFeeling(ownerID, "pc", "desire", 20.0)
		clearAll()
		setClock(22, 0, DAY)
		moveTo(cell)
		IS.getPawn(ownerID).setLocation(cell)
		var nightEv = ownerEvent(["checkin"], ownerID)
		nightEv.getCurrentEvent().checkedIn = true
		nightEv.getCurrentEvent().startedKind = kinds[k]
		nightEv.getCurrentEvent().setState("scene")
		var fakeSex = FakeSex.new()
		nightEv.getCurrentEvent().scene_sexResult(fakeSex)
		var once = rel().getFeeling(ownerID, "pc", "desire")
		nightEv.getCurrentEvent().scene_sexResult(fakeSex)
		check(rel().getFeeling(ownerID, "pc", "desire") == once, k + ": the aftermath ran once")
		if(k == "ask"):
			check(once > 20.0, "asked, consensual: the owner's Desire for the player rises")
		elif(k == "demand"):
			check(once == 23.0, "demanded, coerced: +3")
		else:
			check(once == 25.0, "forced: +5")
		var _n1 = nightEv.onRunnerStop()
	clearAll()

	print("OwnerLifecycleBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

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

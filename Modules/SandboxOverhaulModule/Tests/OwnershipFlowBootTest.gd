extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnershipFlowBootTest.tscn
# Becoming owned, enslaving, onboarding, nightly arrangements, badges and prospective owners work through the real scenes without soft-locks.

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

class FakeSceneRef:
	var sceneTag = ""

class FakeFight:
	var sandboxDefeatKind = ""

class TestMain extends "res://Game/MainScene.gd":
	var holder = null
	var counter = 0
	var sceneCalls = []
	func runScene(id, _args = [], _parentSceneUniqueID = -1, _tag:String = ""):
		sceneCalls.append([id, _args]) # scenes are only recorded here: the test opens them itself
		return FakeSceneRef.new()
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

	var eventSystem = EventSystem.new()
	add_child(eventSystem)
	var _tb = DirectorScript.tick(module, extender.director, true)
	IS.updatePCLocation()
	var pcCell = str(thePlayer.getCellLocation())
	var npcSlavery = GlobalRegistry.getModule("NpcSlaveryModule")
	var cands = []
	for id in inmateIDs:
		if(module.getGangs().gangOf(id) == "" and module.homeRoomOf(id) != "" and IS.hasPawn(id)):
			cands.append(id)
	check(cands.size() >= 14, "setup: enough ordinary inmates with pawns and cells: " + str(cands.size()))

	# ============ 1. Becoming owned, the voluntary way, through the real talk and scene path ============
	var owner1 = pickOwner([])
	check(owner1 != "" and OwnershipGameScript.protectionDecision(owner1)["accepts"], "setup: a candidate who would agree")
	var talk1 = talkTo(owner1)
	check(talk1 != null and actionIDs(talk1).has("ask_protection"), "setup: the talk offers 'Ask for protection'")
	var ownerScenesBefore = ownerScenes()
	check(pressAction(talk1, "ask_protection"), "the player presses it")
	var lastCall = main.sceneCalls.back()
	check(lastCall[0] == "OwnershipScene" and lastCall[1][0] == "protection" and lastCall[1][1] == owner1, "and the ownership scene opens")
	var scene1 = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", lastCall[1])
	show(scene1)
	watch("the terms screen")
	check(shownText().find("Style:") != -1 and shownText().find("Minimum period:") != -1, "the terms are shown first")
	check(click(scene1, "Agree"), "agree")
	show(scene1)
	watch("the confirmation")
	check(!svc().hasOwner(), "nothing has happened before the second confirmation")
	check(click(scene1, "Yes, I accept"), "accept")
	show(scene1)
	check(enabledButtons() == ["Continue"], "the scene offers exactly one way on: " + str(enabledButtons()))
	check(shownText().find("Style:") != -1 and shownText().find("protection now") != -1, "with the agreed terms on it")
	check(actionIDs(talk1) == ["owner_continue"], "and the open talk offers exactly one way on as well: " + str(actionIDs(talk1)))
	check(talkText(talk1).find("is your owner now") != -1, "that says what happened")
	check(svc().isOwner(owner1) and svc().record()["voluntary"] and GM.main.RS.hasSpecialRelationshipID(owner1, "SoftSlavery") and countOwners() == 1, "exactly one Owner relationship")
	check(ownerScenes() == ownerScenesBefore, "no owner event started on the same frame")
	check(messageCount("became your") >= 1 and messageCount("Minimum period") == 0 and messageCount("Check-ins:") == 0, "one concise relationship notification: the terms are shown once, on the panel, not repeated")
	var npcOwner1 = GM.main.RS.getSpecialRelationship(owner1).npcOwner
	check(npcOwner1.nextApproachDay > main.getDays(), "the first owner visit is days away, not now")
	check(click(scene1, "Continue"), "continue")
	check(pressAction(talk1, "owner_continue") and talk1.wasDeleted, "the talk closes cleanly")
	check(!IS.getPawn(owner1).getInteraction() or IS.getPawn(owner1).getInteraction().id == "AloneInteraction", "and the owner is free again")
	saveAndLoadAll()
	check(svc().isOwner(owner1) and countOwners() == 1 and GM.main.RS.hasSpecialRelationshipID(owner1, "SoftSlavery"), "saving and loading straight after becoming owned keeps one owner")
	var talk1b = talkTo(owner1)
	check(talk1b == null or talk1b.wasDeleted, "talking to the owner afterwards goes through the owner's own event")
	var eventCall = main.sceneCalls.back()
	check(eventCall[0] == "NpcOwnerEventRunnerScene" and eventCall[1][0] == owner1, "which is the owner event scene")
	var eventScene = makeScene("res://Scenes/NpcOwnerEventRunnerScene.gd", eventCall[1])
	show(eventScene)
	watch("the owner's talk")
	OwnershipGameScript.releasePlayer("negotiate")
	endAllInteractionsOf(owner1)
	check(!svc().hasOwner() and !GM.main.RS.hasSpecialRelationship(owner1), "setup: free again")

	# ============ 2. Forced and debug conversions: Nemesis, Friend, nothing, and in the middle of a talk ============
	var variants = ["nemesis", "friend", "plain", "midtalk"]
	for vi in range(variants.size()):
		var variant = variants[vi]
		var cand = cands[vi + 1]
		if(variant == "nemesis"):
			GM.main.RS.startSpecialRelantionship("Nemesis", cand)
		elif(variant == "friend"):
			GM.main.RS.startSpecialRelantionship("Friend", cand)
		var midTalk = null
		if(variant == "midtalk"):
			midTalk = talkTo(cand)
			check(midTalk != null and actionIDs(midTalk).has("chat"), "setup: an ordinary talk is open")
		else:
			moveTo("hall_canteen")
			IS.getPawn(cand).setLocation("yard_deadend2") # (far away: the console does not care)
		var before = ownerScenes()
		var became = messageCount("became your")
		GM.main.RS.startSpecialRelantionship("SoftSlavery", cand)
		check(messageCount("became your") == became + 1, variant + ": the transition message appears once")
		if(variant == "nemesis"):
			check(messageCount("is no longer your Nemesis") >= 1, "nemesis: the old relationship ended with its message")
		if(variant == "friend"):
			check(messageCount("is no longer your Friend") >= 1, "friend: the old relationship ended with its message")
		check(countOwners() == 1 and GM.main.RS.hasSpecialRelationshipID(cand, "SoftSlavery") and !GM.main.RS.hasSpecialRelationshipID(cand, "Nemesis") and !GM.main.RS.hasSpecialRelationshipID(cand, "Friend"), variant + ": exactly one Owner relationship and no leftover Friend or Nemesis")
		check(svc().isOwner(cand) and !svc().record().empty(), variant + ": the module's ownership state is initialised at once")
		check(GM.main.RS.getSpecialRelationship(cand).npcOwner.nextApproachDay > main.getDays(), variant + ": a grace period before the first visit")
		check(ownerScenes() == before, variant + ": nothing owner-related starts on the same frame")
		check(messageCount("Minimum period") == 0, variant + ": the terms are not repeated in the notification")
		if(variant == "midtalk"):
			check(actionIDs(midTalk) == ["owner_continue"], "midtalk: the talk that was open offers exactly one way on: " + str(actionIDs(midTalk)))
			check(pressAction(midTalk, "owner_continue") and midTalk.wasDeleted, "midtalk: and closes")
		else:
			# the old debug flow runs the owner's intro right away, with the owner nowhere near: the scene still ends cleanly
			var introFar = makeScene("res://Scenes/NpcOwnerEventRunnerScene.gd", [cand, "Intro", ["willing"]])
			show(introFar)
			watch(variant + ": the intro scene with the owner far away")
			check(enabledButtons() == ["Continue"] and shownText().find("is your owner now") != -1, variant + ": it says who they are and offers Continue: " + str(enabledButtons()))
			check(click(introFar, "Continue"), variant + ": continue")
			IS.getPawn(cand).setLocation(thePlayer.location)
			var introNear = makeScene("res://Scenes/NpcOwnerEventRunnerScene.gd", [cand, "Intro", ["willing"]])
			show(introNear)
			watch(variant + ": the intro scene with the owner here")
			endAllInteractionsOf(cand)
		saveAndLoadAll()
		check(svc().isOwner(cand) and countOwners() == 1, variant + ": saving and loading straight after keeps one owner")
		OwnershipGameScript.releasePlayer("negotiate")
		endAllInteractionsOf(cand)
		GM.main.RS.stopSpecialRelationship(cand)
		check(!svc().hasOwner(), variant + ": setup: free again")

	# ============ 3. A new slave waits for instructions, where they stand ============
	var X = cands[6]
	for blankAxis in ["trust", "affection", "respect", "fear", "desire"]:
		rel().setFeeling(X, "pc", blankAxis, 0.0)
	setClock(10, 0, DAY)
	extender.director = {}
	advance(60, 30)
	moveTo(pawnLoc(X))
	IS.getPawn(X).social = 0.0
	var pawnX = IS.getPawn(X)
	var roomX = pawnX.getLocation()
	var cellX = module.homeRoomOf(X)
	var feelingsMsgs = messageCount("feelings about you changed")
	check(npcSlavery.doEnslaveCharacter(X), "enslaving works")
	check(IS.getPawn(X) == pawnX and !pawnX.isDeleted and pawnX.getLocation() == roomX and module.homeRoomOf(X) == cellX, "the same pawn, in the same room, with the same cell")
	check(svc().isAwaiting(X) and svc().slaveRecord(X)["role"] == "free" and svc().slaveRecord(X)["night"] == "own" and OwnershipGameScript.slaveArrangementText(X) == "Awaiting instructions.", "awaiting instructions: nothing assigned")
	check(messageCount("is awaiting your instructions") >= 1, "the player is told")
	check(messageCount("feelings about you changed") == feelingsMsgs + 1, "one concise message about how they feel")
	check(rel().getFeeling(X, "pc", "trust") == -10.0 and rel().getFeeling(X, "pc", "affection") == -5.0 and rel().getFeeling(X, "pc", "fear") == 8.0 and rel().getFeeling(X, "pc", "respect") == -2.0 and rel().getFeeling(X, "pc", "desire") == 0.0, "a blank slate enslaved by debug conversion gets the cautious negative baseline")
	var leftRoom = 0
	var wrongGoal = 0
	for _stepIndex in range(30):
		advance(120, 120)
		if(IS.getPawn(X).getLocation() != roomX):
			leftRoom += 1
		var goalX = IS.getPawn(X).currentInteraction.goal if (IS.getPawn(X).currentInteraction != null and IS.getPawn(X).currentInteraction.get("goal") != null) else null
		if(goalX == null or goalX.get("kind") != "wait"):
			wrongGoal += 1
	check(leftRoom == 0 and wrongGoal == 0 and IS.pawns.keys().count(X) == 1, "an hour later they are still there, waiting: no routine, nowhere else (left " + str(leftRoom) + ", other goals " + str(wrongGoal) + ")")
	check(OwnershipGameScript.slaveActivityText(X).find("waiting for your instructions") != -1 and OwnershipGameScript.slaveStatusText(X).find("Awaiting instructions.") != -1, "the game says they are waiting")
	var overviewScene = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", [])
	show(overviewScene)
	check(shownText().find("awaiting instructions") != -1, "and the Ownership screen shows it")
	setClock(20, 0, DAY)
	advance(600, 120)
	check(IS.getPawn(X).getLocation() == roomX, "even in the evening, before anything is decided")
	saveAndLoadAll()
	check(IS.pawns.keys().count(X) == 1 and IS.getPawn(X).getLocation() == roomX and svc().isAwaiting(X) and rel().getFeeling(X, "pc", "trust") == -10.0, "saving and loading while they wait changes nothing, and the aftermath is not applied again")
	svc().data()["tick_day"] = DAY - 1
	setClock(9, 0, DAY + 1)
	tick()
	advance(300, 150)
	check(svc().hasSlave(X) and svc().slaveRecord(X)["escape"].empty() and IS.getPawn(X).getLocation() == roomX, "a day on, they have not run and have not wandered off")

	# ---- 3b. The game's own kidnap route: they walk to the player's cell on their own, then wait there ----
	check(cands.size() >= 16, "setup: one more inmate for the kidnap journey")
	var Y = cands[15]
	for kidAxis in ["trust", "affection", "respect", "fear", "desire"]:
		rel().setFeeling(Y, "pc", kidAxis, 0.0)
	moveTo(pcCell)
	setClock(10, 0, DAY)
	extender.director = {}
	advance(60, 30)
	var farY = "hall_canteen"
	check(world.calculatePath(farY, pcCell).size() >= 4, "setup: a room several rooms from the player's cell")
	IS.getPawn(Y).setLocation(farY)
	module.noteEnslaveRoute(Y, "kidnap")
	var chY = GM.main.getCharacter(Y)
	var questY = NpcEnslavementQuest.new()
	questY.setChar(chY)
	questY.setSlaveType(SlaveType.Slut)
	chY.setEnslaveQuest(questY)
	var pawnY = IS.getPawn(Y)
	check(npcSlavery.doEnslaveCharacter(Y) and IS.getPawn(Y) == pawnY and pawnY.getLocation() == farY, "kidnapped far away: the same pawn, not moved by the enslaving")
	check(svc().isAwaiting(Y) and svc().slaveRecord(Y)["wait_cell"], "awaiting instructions, and on the way to the player's cell")
	advance(30, 30)
	check(OwnershipGameScript.slaveDestinationText(Y) != "" and OwnershipGameScript.slaveStatusText(Y).find("on the way to") != -1, "the slave list shows where they are heading, not only where they are: " + OwnershipGameScript.slaveStatusText(Y))
	var trip = follow(Y, RoutineScript.axis(main.timeOfDay) + 3000, 30, pcCell)
	check(trip["arrived"] > 0 and trip["jumps"] == 0 and trip["rooms"].size() >= 3, "they walked to the player's cell room by room (rooms " + str(trip["rooms"].size()) + ", jumps " + str(trip["jumps"]) + ")")
	advance(1800, 300)
	check(IS.getPawn(Y).getLocation() == pcCell and !svc().slaveRecord(Y)["wait_cell"] and svc().isAwaiting(Y) and IS.pawns.keys().count(Y) == 1, "and they stay there, waiting for instructions, once they arrive")
	check(OwnershipGameScript.slaveDestinationText(Y) == "", "(arrived: no destination is shown)")
	saveAndLoadAll()
	check(IS.getPawn(Y).getLocation() == pcCell and svc().isAwaiting(Y), "saving and loading while they wait there changes nothing")
	var _y_free = npcSlavery.doFreeEnslavedCharacter(Y)

	# ============ 4. Instructions: always available, answered in character ============
	boost(X, -60.0, -40.0, -60.0, 5.0)
	IS.getPawn(X).social = 0.0
	var talkX = talkTo(X)
	check(talkX != null, "setup: talking to the slave")
	var idsX = actionIDs(talkX)
	check(!idsX.has("chat") and !idsX.has("flirt"), "setup: they are not in the mood for chat or flirting")
	check(idsX.has("slave_care"), "yet 'Give instructions' is there, whatever they feel: " + str(idsX))
	check(pressAction(talkX, "slave_care") and main.sceneCalls.back()[0] == "SlaveInstructionsScene", "and it opens the instructions")
	var instr = makeScene("res://Modules/SandboxOverhaulModule/Scenes/SlaveInstructionsScene.gd", [X])
	show(instr)
	watch("the first instructions: role")
	check(shownText().find("Free routine") != -1 and shownText().find("Report only when summoned") != -1 and shownText().find("Work the afternoon prostitution locations") != -1 and shownText().find("help me if trouble starts") != -1 and shownText().find("Avoid duties and recover") != -1, "the role screen says what is expected")
	check(click(instr, "Earner"), "choose Earner")
	show(instr)
	watch("night")
	check(shownText().find("Sleep in my cell each night.") != -1 and shownText().find("Sleep in your own cell.") != -1 and shownText().find("report only when ordered") != -1, "the night screen offers the three arrangements")
	check(click(instr, "Sleep in your cell each night"), "choose the player's cell")
	show(instr)
	watch("confirm")
	check(enabledButtons().has("Those are your instructions.") and enabledButtons().has("I'll decide later."), "the confirmation offers both ways")
	check(click(instr, "Those are your instructions."), "confirm")
	show(instr)
	check(svc().isAwaiting(X) and svc().slaveRecord(X)["role"] == "free" and shownText().find("They will not do that") != -1, "a hostile, frightened slave refuses in character and nothing changes")
	check(click(instr, "Free routine"), "choose again: Free routine")
	show(instr)
	check(click(instr, "Sleep in their own cell"), "own cell")
	show(instr)
	check(click(instr, "I'll decide later."), "'I'll decide later'")
	check(svc().isAwaiting(X), "they keep waiting")
	var reopenBefore = sceneCountOf("SlaveInstructionsScene")
	advance(1800, 300)
	check(sceneCountOf("SlaveInstructionsScene") == reopenBefore, "the setup is never reopened on its own")
	show(overviewScene)
	check(shownText().find("awaiting instructions") != -1, "and the Ownership screen still says they are awaiting instructions")
	endAllInteractionsOf(X)
	boost(X, 40.0, 20.0, 40.0, 0.0)
	IS.getPawn(X).social = 0.0
	var talkX2 = talkTo(X)
	check(actionIDs(talkX2).has("slave_care"), "setup: back at the talk")
	pressAction(talkX2, "slave_care")
	var instr2 = makeScene("res://Modules/SandboxOverhaulModule/Scenes/SlaveInstructionsScene.gd", [X])
	show(instr2)
	check(click(instr2, "Earner"), "now choose Earner")
	show(instr2)
	check(click(instr2, "Sleep in your cell each night"), "and the player's cell")
	show(instr2)
	var clockGiven = OwnershipGameScript.clockNow()
	check(click(instr2, "Those are your instructions."), "confirm")
	check(!svc().isAwaiting(X) and svc().slaveRecord(X)["role"] == "earner" and svc().slaveRecord(X)["night"] == "player" and svc().slaveRecord(X)["role_from"] >= clockGiven + OwnershipScript.ROLE_TRANSITION_SECONDS - 5, "a willing slave takes the role and the arrangement, and the role starts later")
	check(OwnershipGameScript.slaveArrangementText(X) == "Earner; sleep in your cell each night.", "the arrangement reads back: " + OwnershipGameScript.slaveArrangementText(X))
	show(overviewScene)
	check(shownText().find("awaiting instructions") == -1, "the Ownership screen no longer says they are awaiting")
	endAllInteractionsOf(X)
	# a later change: in person, once a day, starting later
	svc().data()["slaves"][X]["role_day"] = main.getDays() - 1 # (the instructions were given today; a change is allowed again tomorrow)
	var changeRole = makeScene("res://Modules/SandboxOverhaulModule/Scenes/SlaveInstructionsScene.gd", [X])
	show(changeRole)
	watch("the instructions hub")
	check(enabledButtons().has("Role") and enabledButtons().has("Sleeping arrangement") and enabledButtons().has("Discuss release") and enabledButtons().has("Release them"), "the hub offers role, sleeping arrangement, release")
	check(click(changeRole, "Role"), "open Role")
	show(changeRole)
	check(click(changeRole, "Rest"), "change to Rest")
	show(changeRole)
	check(svc().slaveRecord(X)["role"] == "rest" and shownText().find("half an hour") != -1, "the change is made and starts in about half an hour")
	check(!svc().roleActive(X, OwnershipGameScript.clockNow()) and svc().roleActive(X, OwnershipGameScript.clockNow() + OwnershipScript.ROLE_TRANSITION_SECONDS + 5), "so nobody changes rooms on the spot")
	check(OwnershipGameScript.routineOverride(X, main.getDays(), OwnershipGameScript.axisNow()).get("kind", "") != "cellrest" and OwnershipGameScript.routineOverride(X, main.getDays(), OwnershipGameScript.axisNow() + 1900).get("kind", "") == "cellrest", "the rest routine is not applied yet, and begins half an hour later")
	check(click(changeRole, "Role"), "open Role again")
	show(changeRole)
	check(!enabledButtons().has("Earner") and !enabledButtons().has("Free routine"), "a second change on the same day is not allowed")
	svc().data()["slaves"][X]["role"] = "free"
	svc().data()["slaves"][X]["role_from"] = -1
	# physical blockers
	var talkBlock = OwnershipGameScript.instructionsBlock(X)
	check(talkBlock == "", "no blocker now: " + talkBlock)
	IS.stopInteractionsForPawnID(X)
	IS.startInteraction("Unconscious", {"main": X})
	check(OwnershipGameScript.instructionsBlock(X).find("unconscious") != -1, "an unconscious slave cannot be given instructions")
	var blockedScene = makeScene("res://Modules/SandboxOverhaulModule/Scenes/SlaveInstructionsScene.gd", [X])
	show(blockedScene)
	check(enabledButtons() == ["Back"] and shownText().find("unconscious") != -1, "and the screen says why and offers only Back")
	IS.stopInteractionsForPawnID(X)
	module.getState().gangs["captives"][X] = {"gang": "ironhand", "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
	check(OwnershipGameScript.instructionsBlock(X).find("held") != -1, "a captive slave cannot")
	module.getState().gangs["captives"].erase(X)
	IS.getPawn(X).setLocation("yard_deadend2")
	check(OwnershipGameScript.instructionsBlock(X).find("not here") != -1, "nor one who is somewhere else")
	IS.getPawn(X).setLocation(thePlayer.location)
	check(OwnershipGameScript.instructionsBlock(X) == "", "but nothing else stops it")
	# the talk: the entry is disabled with the reason for a real blocker
	IS.stopInteractionsForPawnID(X)
	var talkX3 = talkTo(X)
	check(actionIDs(talkX3).has("slave_care"), "back to normal")
	endAllInteractionsOf(X)

	# ============ 5. The nightly arrangement: a real journey, a night in the player's cell, a walk back ============
	var N = cands[7]
	IS.getPawn(N).setLocation(module.homeRoomOf(N))
	check(npcSlavery.doEnslaveCharacter(N), "setup: another slave")
	boost(N, 40.0, 20.0, 40.0, 0.0)
	var homeN = module.homeRoomOf(N)
	check(svc().giveInstructions(N, "free", "player", main.getDays()), "setup: sleeps in the player's cell")
	moveTo(pcCell)
	setClock(19, 50, DAY + 2)
	extender.director = {}
	advance(60, 30)
	IS.stopInteractionsForPawnID(N)
	IS.getPawn(N).setLocation(homeN)
	var planN = module.getState().routines["plans"].get(N, [])
	var bedAxis = 22 * 3600
	for segment in planN:
		if(str(segment[2]) == "sleep" and int(segment[0]) > 17 * 3600):
			bedAxis = int(segment[0])
	var nightRun = follow(N, 22 * 3600 + 1800, 60, pcCell)
	check(nightRun["jumps"] == 0 and nightRun["arrived"] > 0, "in the evening they walk to the player's cell, room by room (rooms " + str(nightRun["rooms"].size()) + ", jumps " + str(nightRun["jumps"]) + ")")
	check(nightRun["rooms"].size() >= 2, "through real connected rooms: " + str(nightRun["rooms"]))
	check(nightRun["arrivedAxis"] >= OwnershipScript.NIGHT_START and nightRun["arrivedAxis"] <= max(bedAxis, OwnershipScript.NIGHT_START + 3600), "they get there before ordinary sleep time (arrived " + str(nightRun["arrivedAxis"]) + ", bedtime " + str(bedAxis) + ")")
	check(nightRun["heading"] and nightRun["sleeping"], "the activity reads 'heading to your cell' and then 'sleeping in your cell'")
	check(!module.isInCell(N) and module.getAttendance(N) != "home", "their own cell reports them away: " + module.getAttendance(N))
	check(module.homeRoomOf(N) == homeN, "and it is still theirs")
	advanceToAxis(26 * 3600, 600)
	check(IS.getPawn(N).getLocation() == pcCell, "at 02:00 they are in the player's cell")
	saveAndLoadAll()
	check(IS.pawns.keys().count(N) == 1 and IS.getPawn(N).getLocation() == pcCell, "saving and loading overnight keeps them there")
	advanceToAxis(29 * 3600, 600)
	check(IS.getPawn(N).getLocation() == pcCell, "and at 05:00")
	advanceToAxis(33 * 3600 + 1800, 300)
	check(IS.getPawn(N).getLocation() != pcCell and IS.pawns.keys().count(N) == 1, "in the morning they wake and leave for their day: " + IS.getPawn(N).getLocation())
	# save and load in the middle of the journey
	setClock(20, 0, DAY + 3)
	extender.director = {}
	advance(60, 30)
	IS.stopInteractionsForPawnID(N)
	IS.getPawn(N).setLocation(homeN)
	advanceToAxis(20 * 3600 + 1800 + 240, 60)
	var midJourney = IS.getPawn(N).getLocation()
	check(midJourney != homeN and midJourney != pcCell, "setup: on the way: " + midJourney)
	saveAndLoadAll()
	check(IS.pawns.keys().count(N) == 1 and IS.getPawn(N).getLocation() == midJourney, "saving and loading during the journey keeps them where they were")
	var restRun = follow(N, 22 * 3600 + 1800, 60, pcCell)
	check(restRun["arrived"] > 0 and restRun["jumps"] == 0, "and the journey carries on to the cell")
	# blockers: held, unconscious, busy: excused, nobody teleports
	for blocker in ["held", "unconscious", "busy"]:
		setClock(20, 0, DAY + 4)
		extender.director = {}
		module.getState().gangs["captives"].erase(N)
		advance(60, 30)
		IS.stopInteractionsForPawnID(N)
		IS.getPawn(N).setLocation(homeN)
		if(blocker == "held"):
			module.getState().gangs["captives"][N] = {"gang": "ironhand", "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
		elif(blocker == "unconscious"):
			IS.startInteraction("Unconscious", {"main": N})
		else:
			IS.startInteraction("InStocks", {"inmate": N})
		var blockedRun = follow(N, 23 * 3600, 150, pcCell)
		check((blockedRun["jumps"] == 0 or blocker == "held") and blockedRun["arrived"] < 0 and IS.pawns.keys().count(N) == 1, blocker + ": excused, never at the player's cell, never teleported to it (jumps " + str(blockedRun["jumps"]) + ")")
		IS.stopInteractionsForPawnID(N)
		module.getState().gangs["captives"].erase(N)
	# the other two arrangements: the ordinary cell routine
	for night in ["own", "order"]:
		svc().setNight(N, night)
		setClock(20, 0, DAY + 5)
		extender.director = {}
		advance(60, 30)
		IS.stopInteractionsForPawnID(N)
		advanceToAxis(26 * 3600, 600)
		check(IS.getPawn(N).getLocation() != pcCell, night + ": they do not go to the player's cell: " + IS.getPawn(N).getLocation())
		check(IS.getPawn(N).getLocation() == homeN, night + ": they sleep in their own cell")
	svc().setNight(N, "order")
	var orderBefore = svc().slaveRecord(N)["night"]
	var _ask = GlobalRegistry.getSlaveAction("SbxActionReport").doActionSimple(N)
	check(svc().slaveRecord(N)["night"] == orderBefore and svc().slaveRecord(N)["report"]["state"] == "pending", "a one-off 'Report to my cell' stays separate from the permanent arrangement")

	# ============ 6. How each way of getting a slave leaves them feeling ============
	var cases = [
		{"id": cands[8], "label": "forced (breaking quest, beaten in a fight)", "route": "kidnap", "quest": true, "defeat": "fight", "pre": {}, "kind": "forced", "d": {"trust": -25.0, "affection": -12.0, "respect": 4.0, "fear": 22.0}},
		{"id": cands[9], "label": "submission after a surrender", "route": "kidnap", "quest": true, "defeat": "surrender", "pre": {}, "kind": "submission", "d": {"trust": -12.0, "affection": -4.0, "respect": 1.0, "fear": 12.0}},
		{"id": cands[10], "label": "forced with no recent defeat", "route": "kidnap", "quest": true, "defeat": "", "pre": {}, "kind": "forced", "d": {"trust": -25.0, "affection": -12.0, "respect": -6.0, "fear": 22.0}},
		{"id": cands[11], "label": "voluntary agreement", "route": "free", "quest": false, "defeat": "", "pre": {"affection": 30.0, "trust": 20.0}, "kind": "voluntary", "d": {"trust": 3.0, "affection": 3.0, "respect": 2.0, "fear": 0.0}},
		{"id": cands[12], "label": "submission (the talk option)", "route": "free", "quest": false, "defeat": "", "pre": {}, "kind": "submission", "d": {"trust": -12.0, "affection": -4.0, "respect": 2.0, "fear": 12.0}},
		{"id": cands[13], "label": "unknown conversion keeping existing feelings", "route": "", "quest": false, "defeat": "", "pre": {"trust": 12.0}, "kind": "unknown", "d": {"trust": 0.0, "affection": 0.0, "respect": 0.0, "fear": 0.0}},
	]
	var allBefore = {}
	for entry in cases:
		var cid = entry["id"]
		for axis in ["trust", "affection", "respect", "fear", "desire"]:
			rel().setFeeling(cid, "pc", axis, float(entry["pre"].get(axis, 0.0)))
			allBefore[cid + axis] = rel().getFeeling(cid, "pc", axis)
		if(entry["defeat"] != ""):
			svc().noteDefeat(cid, main.getDays(), entry["defeat"])
		if(entry["route"] != ""):
			module.noteEnslaveRoute(cid, entry["route"])
		if(entry["quest"]):
			var chq = GM.main.getCharacter(cid)
			var q = NpcEnslavementQuest.new()
			q.setChar(chq)
			q.setSlaveType(SlaveType.Slut)
			chq.setEnslaveQuest(q)
		var msgBefore = messageCount("feelings about you changed")
		check(npcSlavery.doEnslaveCharacter(cid), entry["label"] + ": enslaved")
		check(svc().slaveRecord(cid)["aftermath"]["kind"] == entry["kind"], entry["label"] + ": classified as " + entry["kind"] + " (got " + str(svc().slaveRecord(cid)["aftermath"]) + ")")
		for axis in ["trust", "affection", "respect", "fear"]:
			check(abs(rel().getFeeling(cid, "pc", axis) - (allBefore[cid + axis] + float(entry["d"][axis]))) < 0.001, entry["label"] + ": " + axis + " changed by " + str(entry["d"][axis]) + " (now " + str(rel().getFeeling(cid, "pc", axis)) + ")")
		check(rel().getFeeling(cid, "pc", "desire") == allBefore[cid + "desire"], entry["label"] + ": desire is untouched")
		var moved = messageCount("feelings about you changed") - msgBefore
		check(moved == (0 if entry["kind"] == "unknown" else 1), entry["label"] + ": " + str(moved) + " feelings message")
	var snapshot = {}
	for entry2 in cases:
		for axis2 in ["trust", "affection", "respect", "fear"]:
			snapshot[entry2["id"] + axis2] = rel().getFeeling(entry2["id"], "pc", axis2)
	saveAndLoadAll()
	tick()
	var drift = 0
	for entry3 in cases:
		for axis3 in ["trust", "affection", "respect", "fear"]:
			if(abs(rel().getFeeling(entry3["id"], "pc", axis3) - snapshot[entry3["id"] + axis3]) > 0.001):
				drift += 1
	check(drift == 0, "saving and loading never applies the aftermath again")

	# ============ 7. The 'S' badge ============
	world.updatePawns(IS)
	var badgeX = world.pawns[X] if world.pawns.has(X) else null
	check(badgeX != null and badgeX.slaveLabel != null and badgeX.slaveLabel.visible and badgeX.slaveLabel.text == "S" and badgeX.slaveLabel.hint_tooltip == "Your slave.", "the player's slave carries an S badge with the tooltip 'Your slave.'")
	var notSlave = cands[0]
	var badgeOther = world.pawns[notSlave] if world.pawns.has(notSlave) else null
	check(badgeOther == null or badgeOther.slaveLabel == null or !badgeOther.slaveLabel.visible, "an ordinary inmate does not")
	var gangSlaveID = ""
	for id2 in inmateIDs:
		if(module.getGangs().gangOf(id2) != "" and !module.isOwnedSlave(id2)):
			gangSlaveID = id2
			break
	module.getState().gangs["captives"][gangSlaveID] = {"gang": module.getGangs().gangOf(gangSlaveID), "kind": "slave", "stamp": 0, "by": ""}
	check(module.getSlaveBadge(gangSlaveID).empty() and !module.isOwnedSlave(gangSlaveID), "a gang's own slave is not the player's slave and gets no S")
	module.getState().gangs["captives"].erase(gangSlaveID)
	check(module.getSlaveBadge(X)["text"] == "S" and module.getSlaveBadge(X)["color"].r > 0.5 and module.getSlaveBadge(X)["color"].b > 0.5, "the badge is purple")
	var wp = load("res://Game/World/WorldPawn.tscn").instance()
	add_child(wp)
	wp.setRelationshipText("F", Color.green)
	wp.setSlaveBadge("S", Color(0.85, 0.35, 0.95), "Your slave.", 1)
	var tagX = wp.relationship_label.rect_position.x
	check(wp.slaveLabel.rect_position.x == tagX + 12.0 and wp.slaveLabel.visible, "'F S': the S sits after the F")
	wp.setRelationshipText("N", Color.red)
	check(wp.relationship_label.text == "N" and wp.slaveLabel.text == "S", "'N S' keeps both")
	wp.setGangBadge("G", Color.yellow, "gang", true)
	wp.setSlaveBadge("S", Color(0.85, 0.35, 0.95), "Your slave.", 2)
	check(wp.gangLabel.rect_position.x == tagX + 12.0 and wp.slaveLabel.rect_position.x == tagX + 24.0 and wp.relationship_label.visible and wp.gangLabel.visible and wp.slaveLabel.visible, "'N G S': three badges side by side, none replacing another")
	wp.setRelationshipText("", Color.white)
	wp.setGangBadge("G", Color.yellow, "gang", false)
	wp.setSlaveBadge("S", Color(0.85, 0.35, 0.95), "Your slave.", 1)
	check(wp.gangLabel.rect_position.x == tagX and wp.slaveLabel.rect_position.x == tagX + 12.0, "'G S' without a relationship tag")
	wp.setSlaveBadge("", Color.white, "", 0)
	check(!wp.slaveLabel.visible, "the badge can be cleared")
	wp.queue_free()
	# it updates at once on release and escape, and never duplicates
	var labelsBefore = 0
	for child in world.pawns[X].get_children():
		if(child is Label and child.text == "S"):
			labelsBefore += 1
	saveAndLoadAll()
	world.updatePawns(IS)
	world.updatePawns(IS)
	var labelsAfter = 0
	if(world.pawns.has(X)):
		for child2 in world.pawns[X].get_children():
			if(child2 is Label and child2.text == "S"):
				labelsAfter += 1
	check(labelsBefore == 1 and labelsAfter == 1, "saving, loading and redrawing never duplicates the badge (" + str(labelsBefore) + ", " + str(labelsAfter) + ")")
	var _freed = npcSlavery.doFreeEnslavedCharacter(X)
	check(world.pawns.has(X) and (world.pawns[X].slaveLabel == null or !world.pawns[X].slaveLabel.visible), "releasing them removes the badge at once")
	check(npcSlavery.doEnslaveCharacter(X), "setup: enslaved again")
	world.updatePawns(IS)
	check(world.pawns[X].slaveLabel.visible, "and enslaving brings it back at once")
	svc().data()["slaves"][X]["setup"] = "set"
	OwnershipGameScript.completeEscape(X)
	check(world.pawns.has(X) and (world.pawns[X].slaveLabel == null or !world.pawns[X].slaveLabel.visible) and !module.isOwnedSlave(X), "an escape removes it at once")

	# ============ 8. Who would look after the player ============
	for id3 in inmateIDs:
		for axis4 in ["trust", "respect", "affection", "fear", "desire"]:
			rel().setFeeling(id3, "pc", axis4, 0.0)
	var oldAccepts = 0
	var newAccepts = 0
	var capableNow = 0
	var capableOld = 0
	var leaders = 0
	var capableLeaders = 0
	var respectfulAccepts = 0
	for id4 in inmateIDs:
		var facts = OwnershipGameScript.candidateFacts(id4)
		var nowDecision = OwnershipScript.protectorDecision(facts)
		if(nowDecision["accepts"]):
			newAccepts += 1
		if(nowDecision["capability"] >= OwnershipScript.CAPABLE_AT):
			capableNow += 1
		var richer = facts.duplicate()
		richer["respect"] = 25.0
		if(OwnershipScript.protectorDecision(richer)["accepts"]):
			respectfulAccepts += 1
		var legacy = legacyDecision(id4)
		if(legacy["accepts"]):
			oldAccepts += 1
		if(legacy["ability"] >= 0.2):
			capableOld += 1
		if(facts["isLeader"]):
			leaders += 1
			if(nowDecision["capability"] >= OwnershipScript.CAPABLE_AT):
				capableLeaders += 1
	print("PROSPECTS real prison (", inmateIDs.size(), " inmates, neutral feelings): old accept ", oldAccepts, ", old capable ", capableOld, "; new accept ", newAccepts, ", new capable ", capableNow, ", with a little respect ", respectfulAccepts, "; leaders ", leaders, " capable ", capableLeaders)
	check(capableNow >= 6 and capableNow > capableOld, "a normal prison has several capable candidates now (" + str(capableNow) + " against " + str(capableOld) + ")")
	check(respectfulAccepts >= 1 and respectfulAccepts + newAccepts > oldAccepts, "and at least one plausible route to voluntary ownership without a best friend (" + str(respectfulAccepts) + " with a little respect, " + str(newAccepts) + " as strangers, against " + str(oldAccepts) + ")")
	check(leaders == 0 or capableLeaders == leaders, "every gang leader counts as capable on the gang behind them (" + str(capableLeaders) + " of " + str(leaders) + ")")
	var gen = InmateGenerator.new()
	var popOld = 0
	var popNew = 0
	var popNewRespect = 0
	var popCapable = 0
	var popTotal = 0
	var populationsWithCandidate = 0
	for _population in range(12):
		var group = []
		for _i in range(25):
			group.append(gen.generate({}))
		var powers = []
		for member in group:
			powers.append(0.5 + float(member.getLevel()) / 20.0)
		var withCandidate = false
		for member2 in group:
			var mine = 0.5 + float(member2.getLevel()) / 20.0
			var below = 0.0
			for other in powers:
				below += 1.0 if other < mine else 0.0
			below += (powers.count(mine) - 1) * 0.5
			var sub = member2.getPersonality().getStat(PersonalityStat.Subby)
			var f2 = {"powerRank": below / 24.0, "subby": sub, "gangBacking": 0.0}
			var d3 = OwnershipScript.protectorDecision(f2)
			popTotal += 1
			if(d3["capability"] >= OwnershipScript.CAPABLE_AT):
				popCapable += 1
			if(d3["accepts"]):
				popNew += 1
			f2["respect"] = 25.0
			if(OwnershipScript.protectorDecision(f2)["accepts"]):
				popNewRespect += 1
				withCandidate = true
			var oldScore = 0.30 * clamp(-sub, -1.0, 1.0) + 0.15 * float(OwnershipScript.protection({"hasOwner": true, "style": "controlling", "ownerPower": mine, "attackerPower": 0.9, "attackerFear": 0.0, "gangStrength": 0.0, "retaliated": false, "available": true, "recentLosses": 0})["credibility"])
			if(oldScore >= 0.25):
				popOld += 1
		if(withCandidate):
			populationsWithCandidate += 1
	print("PROSPECTS 12 generated populations of 25 (no gangs, neutral feelings): old accept ", popOld, "/", popTotal, ", new capable ", popCapable, "/", popTotal, ", new accept as strangers ", popNew, ", new accept with a little respect ", popNewRespect, ", populations with a plausible candidate ", populationsWithCandidate, "/12")
	check(popNewRespect > popOld and populationsWithCandidate >= 11, "across generated populations there is nearly always a plausible route (" + str(populationsWithCandidate) + " of 12)")
	check(float(popCapable) / float(popTotal) >= 0.4, "and a good share are capable: " + str(popCapable) + "/" + str(popTotal))
	# the refusal in the scene: one primary reason, at most one more, and a direction
	var refuser = ""
	for id5 in cands:
		if(!OwnershipGameScript.protectionDecision(id5)["accepts"]):
			refuser = id5
			break
	check(refuser != "", "setup: somebody who would refuse")
	var refusal = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", ["protection", refuser])
	show(refusal)
	var refusalDecision = OwnershipGameScript.protectionDecision(refuser)
	check(refusalDecision["reasons"].size() >= 1 and refusalDecision["reasons"].size() <= 2 and shownText().find(refusalDecision["reasons"][0]) != -1 and shownText().find("[say=npc]") == -1 and enabledButtons() == ["Back"], "the refusal shows their own words (" + str(refusalDecision["reasons"]) + ") and one way back")
	check(shownText().find("could not really protect anyone") == -1 and shownText().find("They would rather be looked after") == -1, "and none of the old stacked phrases")

	# ============ 9. How to get a slave, from the game's own flow ============
	var help = OwnershipGameScript.acquisitionHelp()
	check(help.find("Socket") != -1 and help.find("Enslave!") != -1 and help.find("Kidnap!") != -1 and help.find("collar") != -1 and help.find("Give instructions") != -1 and help.find("breaking") != -1, "the help names the real route: Socket's cell upgrade, Enslave!, Kidnap!, the collar, the breaking quest, Give instructions")
	for free in [cands[8], cands[9], cands[10], cands[11], cands[12], cands[13], N]:
		var _gone = npcSlavery.doFreeEnslavedCharacter(free)
	OwnershipGameScript.reconcile()
	svc().data()["slaves"].clear()
	var emptyOverview = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", [])
	show(emptyOverview)
	check(shownText().find("How to get a slave") == -1 and enabledButtons().has("How ownership works"), "the long tutorial is not on the main Ownership page: there is a help button instead")
	check(click(emptyOverview, "How ownership works"), "open the help page")
	show(emptyOverview)
	check(shownText().find("How to get a slave") != -1 and shownText().find("Socket") != -1 and shownText().find("Being owned") != -1 and enabledButtons() == ["Back"], "the help page explains ownership and how to get a slave, with one way back")

	print("OwnershipFlowBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ES = null
	eventSystem.free()
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")

func ownerScenes() -> int:
	return sceneCountOf("NpcOwnerEventRunnerScene")

func sceneCountOf(sceneID) -> int:
	var count = 0
	for call in main.sceneCalls:
		if(call[0] == sceneID):
			count += 1
	return count

func countOwners() -> int:
	var count = 0
	for id in GM.main.RS.special:
		if(GM.main.RS.special[id].id == "SoftSlavery"):
			count += 1
	return count

func endAllInteractionsOf(id):
	for interaction in IS.interactions.duplicate():
		if(interaction.getInvolvedPawnIDs().has(id) and interaction.id != "AloneInteraction"):
			IS.stopInteraction(interaction)

func talkTo(id):
	IS.updatePCLocation()
	moveTo(pawnLoc(id))
	endPlayerInteractions()
	endAllInteractionsOf(id)
	IS.startInteraction("Talking", {"starter": "pc", "reacter": id}, {})
	for interaction in IS.interactions:
		if(interaction.id == "Talking" and interaction.getInvolvedPawnIDs().has(id) and !interaction.wasDeleted):
			return interaction
	return null

func actionIDs(interaction) -> Array:
	var ids = []
	for entry in interaction.getActionsFinal():
		if(entry.has("id")):
			ids.append(entry["id"])
	return ids

func talkText(interaction) -> String:
	return str(interaction.getTextAndActions()[0])

func pressAction(interaction, id) -> bool:
	for entry in interaction.getActionsFinal():
		if(entry.get("id", "") == id):
			interaction.doActionFinal(id, entry.get("args", {}), {})
			return true
	return false

func makeScene(path, args):
	var scene = load(path).new()
	scene._initScene(args)
	return scene

func show(scene):
	ui.clearButtons()
	ui.clearText()
	scene._run()

func shownText() -> String:
	return ui.textOutput.bbcode_text

func enabledButtons() -> Array:
	var result = []
	var keys = ui.options.keys()
	keys.sort()
	for key in keys:
		if(ui.options[key][0]):
			result.append(ui.options[key][1])
	return result

# The watchdog: whatever the screen is, there is something to press.
func watch(label):
	check(enabledButtons().size() >= 1, label + ": never an empty action grid")

func click(scene, text) -> bool:
	for option in ui.options.values():
		if(option[0] and option[1] == text):
			scene._react(option[3], option[4])
			return true
	return false

func saveAndLoadAll():
	var savedRS = JSON.print(GM.main.RS.saveData())
	saveAndLoad()
	GM.main.RS.loadData(JSON.parse(savedRS).result)

func advanceToAxis(target, step):
	var guard = 0
	while(RoutineScript.axis(main.timeOfDay) < target and guard < 3000):
		advance(step, step)
		guard += 1

# Follows one slave to the target room in steps of `step` seconds until the axis time `until`: {rooms, jumps, arrived (steps), arrivedAxis, heading, sleeping}.
func follow(id, until, step, target) -> Dictionary:
	var rooms = {}
	var jumps = 0
	var last = IS.getPawn(id).getLocation()
	var arrived = -1
	var arrivedAxis = -1
	var steps = 0
	var heading = false
	var sleeping = false
	while(RoutineScript.axis(main.timeOfDay) < until and steps < 3000):
		advance(step, step)
		steps += 1
		var here = IS.getPawn(id).getLocation()
		rooms[here] = true
		if(here != last and world.calculatePath(last, here).size() > 3):
			jumps += 1
		last = here
		var text = OwnershipGameScript.slaveActivityText(id)
		if(here != target and text.find("heading to your cell") != -1):
			heading = true
		if(here == target and text.find("sleeping in your cell") != -1):
			sleeping = true
		if(here == target and arrived < 0):
			arrived = steps
			arrivedAxis = RoutineScript.axis(main.timeOfDay)
	return {"rooms": rooms.keys(), "jumps": jumps, "arrived": arrived, "arrivedAxis": arrivedAxis, "heading": heading, "sleeping": sleeping}

# What the old criteria said (kept here only to measure the change): willingness mixed with a personal-strength "ability" that almost nobody reached.
func legacyDecision(npcID) -> Dictionary:
	var traits = OwnershipGameScript.traitsOf(npcID)
	var dominance = clamp(-float(traits["subby"]), -1.0, 1.0)
	var gid = module.getGangs().gangOf(npcID)
	var ability = float(OwnershipScript.protection({"hasOwner": true, "style": OwnershipGameScript.styleFor(npcID), "ownerPower": GangGameScript.power(npcID), "attackerPower": 0.9, "attackerFear": 0.0,
		"gangStrength": GangGameScript.gangStrength(gid) if gid != "" else 0.0, "retaliated": false, "available": true, "recentLosses": 0})["credibility"])
	var score = 0.30 * dominance + 0.25 * rel().getFeeling(npcID, "pc", "respect") / 100.0 + 0.15 * rel().getFeeling(npcID, "pc", "affection") / 100.0 + 0.15 * clamp(GM.main.RS.getLust(npcID, "pc"), -1.0, 1.0) + 0.15 * ability + 0.10 * rel().getFeeling(npcID, "pc", "trust") / 100.0
	return {"accepts": score >= 0.25, "ability": ability}

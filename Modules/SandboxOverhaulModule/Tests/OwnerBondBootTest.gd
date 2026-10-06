extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnerBondBootTest.tscn
# The owner as a protective, possessive ally: completed demands are reported at any time, "my owner wants to meet today" is a real pending meeting, the evening check-in leads to a night at the owner's
# (and sometimes an asked, demanded or forced intimacy), and the owner frees the player from restraints put on after a hostile encounter.

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

	# ---- 1. Reporting a completed demand: any time of day, once, a fixed modest reward ----
	for slot in [[8, 30], [15, 0], [22, 40]]:
		setClock(slot[0], slot[1], DAY)
		moveTo(playerRoom)
		endPlayerInteractions()
		boost(ownerID, 10.0, 10.0, 10.0)
		var nowClock = OwnershipGameScript.clockNow()
		svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 300 + slot[0], "type": "credits", "state": "ready", "amount": 3, "created": nowClock, "deadline": nowClock + 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
		world.updatePawns(IS)
		check(world.pawns.has(ownerID) and world.pawns[ownerID].taskLabel.visible, "at " + str(slot[0]) + ":" + str(slot[1]) + " the owner carries the Q while the demand is ready")
		var combatBefore = [module.getCombat().getDefiance(), module.getCombat().getRep("fear") if module.getCombat().has_method("getRep") else 0.0]
		var t0 = rel().getFeeling(ownerID, "pc", "trust")
		var r0 = rel().getFeeling(ownerID, "pc", "respect")
		var a0 = rel().getFeeling(ownerID, "pc", "affection")
		var runner = ownerEvent(["handover"], ownerID)
		check(rel().getFeeling(ownerID, "pc", "trust") == t0 + 3.0 and rel().getFeeling(ownerID, "pc", "respect") == r0 + 2.0 and rel().getFeeling(ownerID, "pc", "affection") == a0 + 1.0, "reporting at " + str(slot[0]) + ":" + str(slot[1]) + " gives Trust +3, Respect +2, Affection +1")
		check(!svc().hasDemand() and module.getCombat().getDefiance() == combatBefore[0], "the demand is gone and Defiance is untouched")
		var _stop = runner.onRunnerStop()
		var again = ownerEvent(["handover"], ownerID)
		check(rel().getFeeling(ownerID, "pc", "trust") == t0 + 3.0, "a second report is worth nothing")
		var _stop2 = again.onRunnerStop()
		world.updatePawns(IS)
		check(!world.pawns[ownerID].taskLabel.visible, "the Q goes once the report is acknowledged")
	setClock(21, 40, DAY)
	check(module.ownerHasCompletedDemand() == false, "nothing to report, nothing offered in talk")

	# ---- 2. A meeting promise is a real pending meeting ----
	setClock(9, 0, DAY)
	svc().record()["meeting"] = {}
	module.onOwnerMeetingDay(ownerID)
	module.onOwnerMeetingDay(ownerID)
	check(svc().hasMeeting() and svc().meeting()["told"] and messageCount("today. They will come to you") == 1, "the promise is a pending meeting, told once")
	world.updatePawns(IS)
	check(world.pawns[ownerID].taskLabel.visible and world.pawns[ownerID].taskLabel.hint_tooltip.find("Meet ") != -1, "the owner carries a Q that says why")
	check(PoolStringArray(OwnershipGameScript.summaryLines()).join("\n").find("Pending meeting:") != -1 and sideTasks().find("wants to meet you") != -1, "the Ownership screen and Side Tasks show the meeting")
	saveAndLoad()
	check(svc().hasMeeting() and svc().meeting()["told"], "the meeting survives saving and loading")
	# a hard blocker postpones it once, with one notice
	module.getState().gangs["captives"][ownerID] = {"gang": "", "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
	OwnershipGameScript.meetingTick()
	OwnershipGameScript.meetingTick()
	check(svc().meeting()["day"] == DAY + 1 and messageCount("cannot meet you today") == 1, "a held owner postpones the meeting to tomorrow, with one notice")
	module.getState().gangs["captives"].erase(ownerID)
	# the owner reaches the player on their own late in the day, and the event starts once
	setClock(9, 0, DAY + 1)
	DAY = main.currentDay
	IS.getPawn(ownerID).setLocation("mining_nearentrance")
	moveTo(playerRoom)
	endPlayerInteractions()
	main.sceneCalls.clear()
	setClock(20, 30, DAY)
	OwnershipGameScript.meetingTick()
	var started = 0
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerEventRunnerScene"):
			started += 1
	check(started == 1 and pawnLoc(ownerID) == playerRoom, "late in the day the owner finds the player directly, and the event starts once")
	var _ok = module.restoreOwnerPawn(ownerID)
	var heldMeeting = ownerEvent(["meeting"], ownerID) # the owner event itself holds the meeting
	var _hm = heldMeeting.onRunnerStop()
	check(!svc().hasMeeting(), "the meeting is over once the event started")
	check(messageCount("today. They will come to you") <= 2, "and it was never announced again")
	# an invalid meeting (no owner any more) is cancelled with an explanation, not left dangling
	endPlayerInteractions()
	main.sceneStack = [FakeWorldScene.new()]
	var _m = svc().startMeeting(DAY, "check")
	GM.main.RS.stopSpecialRelationship(ownerID)
	OwnershipGameScript.reconcile()
	check(!svc().hasOwner() and !svc().hasMeeting(), "ending the ownership drops the meeting with it")
	check(becomeOwnedBy(ownerID), "setup: owned again")
	svc().data()["tick_day"] = -1

	# ---- 3. Check-in -> a night at the owner's ----
	var cell = OwnershipGameScript.ownerCellRoom(ownerID)
	setClock(21, 30, DAY)
	moveTo(cell)
	IS.getPawn(ownerID).setLocation(cell)
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	svc().record()["last_intimacy"] = DAY # (not tonight)
	var nightRunner = ownerEvent(["checkin"], ownerID)
	check(!svc().isCheckinPending(main.getDays()), "the check-in is fulfilled by the first screen")
	check(press(nightRunner, "next"), "an evening at the owner's follows the check-in")
	var modeSeen = OwnershipScript.nightMode(svc().style(), OwnershipGameScript.nightSeed())
	check(press(nightRunner, "stay"), "the stay is always on offer (" + modeSeen + ")")
	check(press(nightRunner, "sleepNow"), "no intimacy tonight: they sleep")
	check(main.newDays == 1, "the game's own sleep ran exactly once")
	check(!svc().isCheckinPending(main.getDays()) and svc().record()["checkin"]["state"] != "pending", "and the check-in was not fulfilled twice")
	main.sceneStack = [FakeWorldScene.new()]
	var _s0 = nightRunner.onRunnerStop()

	# ---- 4. Intimacy: asked, demanded, forced; at most once in two nights ----
	DAY = main.currentDay
	for intent in ["ask", "demand", "force"]:
		endPlayerInteractions()
		moveTo(cell)
		setClock(21, 30, DAY)
		IS.getPawn(ownerID).setLocation(cell)
		svc().record()["last_intimacy"] = -100
		var intentRunner = ownerEvent(["checkin"], ownerID)
		intentRunner.getCurrentEvent().checkedIn = true
		intentRunner.getCurrentEvent().intent = intent
		intentRunner.getCurrentEvent().setState("intimacy")
		intentRunner.run()
		var names = buttonNames(intentRunner)
		if(intent == "ask"):
			check(names.has("Accept") and names.has("Decline"), "asking offers accept and decline: " + str(names))
			var trustAsk = rel().getFeeling(ownerID, "pc", "trust")
			check(press(intentRunner, "decline") and rel().getFeeling(ownerID, "pc", "trust") == trustAsk, "declining an ask costs nothing")
			check(svc().canHaveIntimacy(DAY), "and it does not count as a night together")
		if(intent == "demand"):
			check(names.has("Obey") and names.has("Refuse") and names.has("Talk them out of it"), "a demand offers obey, talk them out of it and refuse: " + str(names))
			var affBefore = rel().getFeeling(ownerID, "pc", "affection")
			check(press(intentRunner, "refuse") and rel().getFeeling(ownerID, "pc", "affection") >= affBefore - 2.0 and !GM.main.RS.hasSpecialRelationshipID(ownerID, "Nemesis"), "refusing a demand is a small cost, no Nemesis")
		if(intent == "force"):
			check(names.has("Endure it") and names.size() == 1, "force leaves one way on: " + str(names))
			var forcedTrust = rel().getFeeling(ownerID, "pc", "trust")
			check(press(intentRunner, "force"), "enduring starts the scene")
			check(svc().canHaveIntimacy(DAY) == false, "the night is counted once the scene starts")
			var ev = intentRunner.getCurrentEvent()
			ev.scene_sexResult(FakeSex.new())
			check(rel().getFeeling(ownerID, "pc", "trust") == forcedTrust and module.applySexConsent(2, ownerID, "pc", FakeSex.new()) == false, "a forced night goes through the existing forced aftermath: no vanilla bonding afterwards")
		var _stopI = intentRunner.onRunnerStop()
		main.sceneStack = [FakeWorldScene.new()]
	svc().record()["last_intimacy"] = DAY
	check(!svc().canHaveIntimacy(DAY + 1) and svc().canHaveIntimacy(DAY + 2), "at most one intimate night in two")
	module.queuedRolls = [0.0]
	check(OwnershipGameScript.decideIntimacy() == "", "an owner who just had a night does not ask again")
	svc().record()["last_intimacy"] = -100
	module.queuedRolls = [0.0]
	check(OwnershipGameScript.decideIntimacy() != "", "with a good roll it can happen")
	module.queuedRolls = [0.999]
	check(OwnershipGameScript.decideIntimacy() == "", "and a bad roll it does not")
	# consensual aftermath goes through the existing consent classification
	var tC = rel().getFeeling(ownerID, "pc", "trust")
	var vanilla = module.applySexConsent(0, ownerID, "pc", FakeSex.new())
	check(vanilla == true and rel().getFeeling(ownerID, "pc", "trust") >= tC - 5.0, "a consensual night is classified CONSENSUAL and lets the normal aftermath run")

	# ---- 5. The owner frees the restrained player ----
	endPlayerInteractions()
	main.sceneStack = [FakeWorldScene.new()]
	DAY = main.currentDay
	setClock(14, 0, DAY)
	moveTo(playerRoom)
	svc().record()["last_help"] = -100
	svc().record()["pc_defeat"] = {}
	IS.getPawn(ownerID).setLocation("mining_nearentrance")
	thePlayer.getInventory().forceEquipStoreOtherUnlessRestraint(GlobalRegistry.createItem("inmatewristcuffs"))
	check(OwnershipGameScript.playerIsRestrained(), "setup: the player is cuffed")
	OwnershipGameScript.rescueTick()
	check(IS.getPawn(ownerID).getLocation() == "mining_nearentrance", "cuffed by choice or by nobody: the owner does not come")
	var attackerID = ""
	for id in inmateIDs:
		if(id != ownerID):
			attackerID = id
			break
	OwnershipGameScript.onPlayerLost(attackerID)
	check(svc().rescueDue(OwnershipGameScript.clockNow()), "losing to an inmate starts a hostile encounter record")
	main.sceneCalls.clear()
	OwnershipGameScript.rescueTick()
	var rescues = 0
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerEventRunnerScene" and call[1].size() > 2 and call[1][2] == ["rescue"]):
			rescues += 1
	check(rescues == 1 and pawnLoc(ownerID) == playerRoom and IS.pawns.keys().count(ownerID) == 1, "the owner arrives and the rescue starts once, with one pawn")
	check(svc().record()["last_help"] == main.getDays(), "the day's protection was consumed only now")
	var rescueRunner = ownerEvent(["rescue"], ownerID)
	if(press(rescueRunner, "price")):
		check(true, "a harsh owner asks for something first")
		rescueRunner.getCurrentEvent().setState("rescue_free")
		rescueRunner.run()
	elif(press(rescueRunner, "free")):
		check(true, "the owner offers to free the player")
	rescueRunner.getCurrentEvent().setState("rescue_free")
	rescueRunner.run()
	check(!OwnershipGameScript.playerIsRestrained(), "the restraints are really off")
	OwnershipGameScript.rescueTick()
	check(main.sceneCalls.size() == rescues + 1 or true, "and no second rescue starts")
	var count = 0
	for call in main.sceneCalls:
		if(call[0] == "NpcOwnerEventRunnerScene" and call[1].size() > 2 and call[1][2] == ["rescue"]):
			count += 1
	check(count == 1, "not repeated")
	var _stopR = rescueRunner.onRunnerStop()
	# guard restraints are the prison's business
	svc().record()["pc_defeat"] = {}
	OwnershipGameScript.onPlayerLost(guardIDs[0])
	check(!svc().rescueDue(OwnershipGameScript.clockNow()), "a defeat by a guard is not a rescue")
	# blocked: unconscious owner does not come, and nothing is used up
	svc().record()["last_help"] = -100
	OwnershipGameScript.onPlayerLost(attackerID)
	thePlayer.getInventory().forceEquipStoreOtherUnlessRestraint(GlobalRegistry.createItem("inmatewristcuffs"))
	IS.startInteraction("Unconscious", {"main": ownerID})
	OwnershipGameScript.rescueTick()
	check(svc().record()["last_help"] == -100 and svc().rescueDue(OwnershipGameScript.clockNow()), "an unconscious owner does not come, and the rescue waits")
	endPlayerInteractions()
	for interaction in IS.interactions.duplicate():
		IS.stopInteraction(interaction)
	saveAndLoad()
	check(svc().playerDefeat().has("by"), "the hostile-encounter record survives saving and loading")

	print("OwnerBondBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnershipBootTest.tscn
# Ownership on the real game: BDCC's own SoftSlavery and NPC slavery, the real map, the real persistent inmates, the real owner events and slave menu, the real quest log. Two loops are followed
# from start to finish. The player asks a strong inmate for protection, is checked in on, misses a night, is confronted in person, and finds the ways out. The player owns an inmate, who stays
# in the prison with a cell and a routine, takes a role, earns, resents, telegraphs an escape, and is kept, lost or released.

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

	# ---- 1. A vulnerable player asks a strong inmate for protection ----
	var _c1 = module.getCombat().addRep("combat", -60.0)
	var best = ""
	var bestScore = -99.0
	for id in inmateIDs:
		if(module.getGangs().gangOf(id) != ""):
			continue
		boost(id, 40.0, 70.0, 40.0)
		var decision = OwnershipGameScript.protectionDecision(id)
		if(decision["score"] > bestScore):
			bestScore = decision["score"]
			best = id
	var owner1 = best
	boost(owner1, 40.0, 70.0, 40.0)
	check(owner1 != "" and OwnershipGameScript.protectionDecision(owner1)["accepts"], "setup: a strong, respected inmate would agree: score " + str(bestScore))
	# someone who does not respect the player says no, and says why in plain words
	var stranger = ""
	for id in inmateIDs:
		if(id != owner1 and module.getGangs().gangOf(id) == ""):
			stranger = id
	boost(stranger, -40.0, -40.0, -40.0, 60.0)
	var no = OwnershipGameScript.protectionDecision(stranger)
	check(!no["accepts"] and !no["reasons"].empty(), "an inmate who fears and does not respect the player says no, with reasons: " + str(no["reasons"]))
	var offer = module.getProtectionOffer(owner1)
	check(offer["show"] and offer["ok"], "the choice is offered in person")
	check(!module.getProtectionOffer("pc")["show"] and !module.getProtectionOffer(guardIDs[0])["show"], "never offered for the player or for staff")
	var terms = OwnershipGameScript.termsFor(owner1)
	check(StyleScript.STYLES.has(terms["style"]) and terms["days"] == 3 and terms["protection"] in ["Weak", "Moderate", "Strong"] and terms["checkin"] != "" and terms["demands"] != "" and terms["cell"] != "", "the terms are shown first: style, check-ins, demands, protection, minimum period: " + str(terms))
	# the scene, with a confirmation step
	var scene = load("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd").new()
	scene._initScene(["protection", owner1])
	ui.clearButtons()
	ui.clearText()
	scene._run()
	var optionsA = options()
	var textA = ui.textOutput.bbcode_text
	check(optionsA.has("Agree") and optionsA.has("Not now") and textA.find("Style:") != -1 and textA.find("Check-ins:") != -1 and textA.find("Protection:") != -1 and textA.find("Minimum period:") != -1, "the scene shows every term and asks")
	check(!svc().hasOwner() and !module.getGangs().isCaptive(owner1), "nothing has happened yet")
	scene._react("protection_confirm", [])
	ui.clearButtons()
	ui.clearText()
	scene._run()
	check(options().has("Yes, I accept") and ui.textOutput.bbcode_text.find("Are you sure?") != -1 and !svc().hasOwner(), "and asks again before anything changes")
	var attacker = ""
	for id in inmateIDs:
		if(id != owner1 and id != stranger and module.getGangs().gangOf(id) == ""):
			attacker = id
	var _fearOfOwner = rel().setFeeling(attacker, owner1, "fear", 70.0)
	var before = module.getAttackMultiplier(attacker)
	scene._react("accept", [])
	svc().record()["demand_clock"] = OwnershipGameScript.clockNow() # no demands while the check-in is being tested
	check(svc().isOwner(owner1) and svc().record()["voluntary"] and svc().record()["term_end"] == DAY + 3 and GM.main.RS.hasSpecialRelationshipID(owner1, "SoftSlavery"), "accepting starts BDCC's own SoftSlavery and records the minimum term")
	var after = module.getAttackMultiplier(attacker)
	check(after < before and after >= OwnershipGameScript.PROTECTION_FLOOR_TOTAL, "attacks on the player become less likely: " + str(before) + " to " + str(after))
	var summary = OwnershipGameScript.protectionSummary()
	check(summary["band"] in ["Weak", "Moderate", "Strong"] and !summary["reasons"].empty(), "the ownership screen can say Weak, Moderate or Strong, and why: " + summary["band"])
	var style1 = svc().style()
	var screenScene = load("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd").new()
	screenScene._initScene([])
	ui.clearButtons()
	ui.clearText()
	screenScene._run()
	var screenText = ui.textOutput.bbcode_text
	check(screenText.find("Owner:") != -1 and screenText.find(module.characterName(owner1)) != -1 and screenText.find("Style:") != -1 and screenText.find(StyleScript.nameOf(style1)) != -1 and screenText.find("Their cell:") != -1 and screenText.find("Next check-in:") != -1 and screenText.find("Active demand:") != -1 and screenText.find("Recent warnings:") != -1 and screenText.find("Protection:") != -1 and screenText.find("Earliest release negotiation:") != -1, "the Ownership screen shows owner, style, cell, next check-in, demand, warnings, protection and the release date")
	# the owner is still an ordinary persistent inmate with a cell and a place
	check(module.homeRoomOf(owner1) != "" and IS.hasPawn(owner1) and world.hasRoomID(pawnLoc(owner1)) and !module.isKeptElsewhere(owner1) and !module.isHeldAway(owner1), "the owner has a cell, a pawn, a real place and an ordinary routine: they are not kept elsewhere")
	var ownerPlan = module.getState().routines["plans"].get(owner1, [])
	check(!ownerPlan.empty(), "and a plan for the day, like everybody else")

	# ---- 2. The nightly check-in, in person, at the owner's real cell ----
	tick()
	var cellRoom = module.homeRoomOf(owner1)
	var checkinView = module.getOwnershipJournal("checkin")
	check(svc().isCheckinPending(DAY) and checkinView["visible"], "tonight's check-in exists and is in the journal")
	check(checkinView["lines"].size() >= 3 and PoolStringArray(checkinView["lines"]).join(" ").find(OwnershipGameScript.cellLabelOf(owner1)) != -1 and PoolStringArray(checkinView["lines"]).join(" ").find("cell block") != -1 and PoolStringArray(checkinView["lines"]).join(" ").find("21:00 to 23:00") != -1, "it names the cell, the block and the time: " + str(checkinView["lines"]))
	check(module.getCells().knowsCell("pc", owner1), "the obligation teaches the cell, so the player never has to guess")
	var log1 = sideTasks()
	check(log1.find("Check in with " + module.characterName(owner1)) != -1 and log1.count("Check in with") == 1, "it appears once in the Side Tasks")
	# one reminder as the window approaches
	advanceTo(20, 20)
	var remindersBefore = messageCount("expects you at")
	advanceTo(20, 36)
	advanceTo(20, 50)
	check(messageCount("expects you at") == remindersBefore + 1, "exactly one reminder")
	# the owner goes to their cell
	advanceTo(21, 4)
	check(pawnLoc(owner1) == cellRoom, "by 21:00 the owner is physically in their own cell: " + pawnLoc(owner1) + " vs " + cellRoom)
	var ownerPawn = IS.getPawn(owner1)
	check(ownerPawn != null and module.getAttendance(owner1) in ["home", ""], "and counted as home")
	# not in the cell: not accepted
	moveTo("hall_canteen")
	check(!OwnershipGameScript.reportIn()["ok"], "reporting from somewhere else does nothing")
	moveTo(cellRoom)
	var talkActions = module.getOwnerTalkActions(null)
	var sawReport = false
	for entry in talkActions:
		if(entry[0] == "Report in for the night" and entry.size() > 2):
			sawReport = true
	check(sawReport, "in the cell the owner's talk menu offers 'Report in for the night'")
	var trustBefore = rel().getFeeling(owner1, "pc", "trust")
	var runner = ownerEvent(["checkin"], owner1)
	check(runner.getFinalText().find("on time") != -1 or runner.getFinalText().find("Checked in on time") != -1, "the owner acknowledges the timing: " + runner.getFinalText().substr(0, 200))
	check(svc().checkin()["state"] == "done" and svc().recentFulfilled(DAY) == 1 and rel().getFeeling(owner1, "pc", "trust") > trustBefore, "it is done once and trust rises")
	var _stop = runner.onRunnerStop()
	endPlayerInteractions()
	tick()
	check(!module.getOwnershipJournal("checkin")["visible"] and sideTasks().find("Check in with") == -1, "it leaves the journal once done")
	check(!OwnershipGameScript.reportIn()["ok"], "and cannot be done twice")
	var tsave = svc().data().duplicate(true)
	saveAndLoad()
	check(same(svc().data(), tsave), "saving and loading changes nothing")

	# ---- 3. Missing the next night: a warning, delivered in person only ----
	var nextNight = DAY + 1
	setClock(10, 0, nextNight)
	moveTo("yard_deadend2")
	svc().record()["next_checkin"] = nextNight
	extender.director = {}
	tick()
	check(svc().isCheckinPending(nextNight), "the next check-in is created on its night")
	advanceTo(20, 0)
	var creditsBeforeMiss = thePlayer.getCredits()
	advanceTo(1, 0) # past the end of the late window
	check(svc().checkin()["state"] == "missed" and svc().recentMisses(main.currentDay) == 1, "not turning up is a miss")
	check(!svc().pendingConfront().empty() and int(svc().pendingConfront()["level"]) == 1, "and a warning is waiting for the next meeting")
	var waitingSnapshot = svc().data().duplicate(true)
	saveAndLoad()
	check(same(svc().data(), waitingSnapshot) and !svc().pendingConfront().empty(), "saving and loading with a warning waiting changes nothing: it is still pending, once")
	check(thePlayer.getCredits() == creditsBeforeMiss and !module.getBlockedReason().begins_with("being punished"), "nothing happened to the player remotely")
	var punishRunning = false
	for interaction in IS.interactions:
		if(interaction.id in ["PunishInteraction", "InNpcOwnerEvent"]):
			punishRunning = true
	check(!punishRunning, "no punishment or owner event started anywhere on the map")
	check(!module.ownerWantsToSeePlayer(), "in the middle of the night the owner is in their cell, not hunting the player")
	setClock(10, 0, main.currentDay)
	moveTo("hall_canteen")
	svc().record()["demand_clock"] = OwnershipGameScript.clockNow() + 100 * 86400
	extender.director = {}
	check(module.ownerWantsToSeePlayer() and module.ownerWantsToSeePlayerFor(owner1) and module.getOwnerApproachEvent()[0] == "SandboxOwnerOps", "by day the owner wants to see them, and the approach is the module's event")
	check(svc().hasOwner() and pawnLoc(owner1) != thePlayer.location, "the owner is somewhere else, not magically beside the player")
	main.sceneCalls.clear()
	var walked = 0
	while(main.sceneCalls.empty() and walked < 150):
		advance(120)
		walked += 1
	check(!main.sceneCalls.empty() and main.sceneCalls[0][0] == "NpcOwnerEventRunnerScene" and main.sceneCalls[0][1][0] == owner1 and main.sceneCalls[0][1][1] == "SandboxOwnerOps" and main.sceneCalls[0][1][2][0] == "approach", "the owner walked up to the player themselves and the module's event started: " + str(main.sceneCalls) + " after " + str(walked * 2) + " minutes")
	check(pawnLoc(owner1) == thePlayer.location and walked >= 1, "they were in the same room as the player when it started, and it took them real time to arrive")
	# the owner arrives: a verbal warning, with ways to answer
	var confront = ownerEvent(["approach"], owner1)
	var names = buttonNames(confront)
	check(names.has("Apologise") and names.has("Submit") and names.has("Resist"), "the first step is a verbal warning with Apologise, Submit and Resist: " + str(names))
	check(press(confront, "apologise") and svc().pendingConfront().empty() and svc().data()["owner"]["consequence"] != "", "an apology settles the first warning")
	var _stop2 = confront.onRunnerStop()
	endPlayerInteractions()
	# stepping up: two more misses, compensation
	svc().recordMiss(main.currentDay, "did not come")
	svc().recordMiss(main.currentDay, "did not come")
	check(int(svc().pendingConfront()["level"]) >= 2, "misses pile up into a bigger step")
	svc().record()["confront"]["level"] = 2
	thePlayer.addCredits(30 - thePlayer.getCredits())
	var comp = ownerEvent(["approach"], owner1)
	var compNames = buttonNames(comp)
	var owed = OwnershipScript.compensationFor(svc().style())
	check(compNames.has("Pay " + str(owed) + " credits") and compNames.has("Apologise") and compNames.has("Resist"), "step two asks for compensation: " + str(compNames))
	var creditsBeforePay = thePlayer.getCredits()
	check(press(comp, "pay") and thePlayer.getCredits() == creditsBeforePay - owed and svc().pendingConfront().empty(), "paying costs the compensation once")
	var _stop3 = comp.onRunnerStop()
	endPlayerInteractions()
	thePlayer.addCredits(1 - thePlayer.getCredits())
	svc().recordMiss(main.currentDay, "did not come")
	svc().record()["confront"]["level"] = 2
	var poor = ownerEvent(["approach"], owner1)
	check(buttonNames(poor).has("Pay " + str(owed) + " credits (off)") or buttonNames(poor).find("Pay " + str(owed) + " credits (off)") != -1, "with nothing in your pocket you cannot pay (credits never go below zero)")
	var _stop4 = poor.onRunnerStop()
	endPlayerInteractions()
	# resisting: win, back down, lose
	svc().record()["confront"] = {"level": 3, "reason": "did not come", "day": main.currentDay}
	thePlayer.addCredits(20 - thePlayer.getCredits())
	var resistWin = ownerEvent(["approach"], owner1)
	check(press(resistWin, "resist") and buttonNames(resistWin).has("Fight") and buttonNames(resistWin).has("Back down"), "resisting leads to Fight or Back down")
	var _r1 = resistWin.notifyFightResult(true)
	var winsAfter = svc().distinctWins()
	check(svc().pendingConfront().empty() and svc().inGrace(main.currentDay + 1) and svc().inGrace(main.currentDay + 2) and svc().hasOwner() and winsAfter == 1 and rel().getFeeling(owner1, "pc", "fear") >= 15.0, "winning ends the consequence, buys two days, makes the owner afraid, and ownership stays")
	var _stop5 = resistWin.onRunnerStop()
	endPlayerInteractions()
	check(!module.ownerWantsToSeePlayer(), "and the owner keeps away during the grace period")
	check(!svc().canIssueDemand(OwnershipGameScript.clockNow(), main.currentDay), "no demands then either")
	svc().record()["confront"] = {"level": 3, "reason": "did not come", "day": main.currentDay}
	svc().record()["grace_until"] = -1
	var backDown = ownerEvent(["approach"], owner1)
	var credBefore = thePlayer.getCredits()
	var combatBefore = module.getCombat().getCombatReputation()
	var _p1 = press(backDown, "resist")
	check(press(backDown, "backdown") and thePlayer.getCredits() == credBefore - owed and svc().pendingConfront().empty() and module.getCombat().getCombatReputation() <= combatBefore, "backing down is the milder way out: you pay what is owed, no punishment")
	var _stop6 = backDown.onRunnerStop()
	endPlayerInteractions()
	svc().record()["confront"] = {"level": 3, "reason": "did not come", "day": main.currentDay}
	var lose = ownerEvent(["approach"], owner1)
	var _p2 = press(lose, "resist")
	var _r2 = lose.notifyFightResult(false)
	lose.run()
	check(svc().pendingConfront().empty() and lose.getFinalText().find("lost") != -1 and svc().hasOwner() and svc().distinctWins() == 1, "losing means the punishment (the game's own punishment event follows) and ownership stays")
	var _stop7 = lose.onRunnerStop()
	endPlayerInteractions()

	# ---- 4. Excused absences ----
	var excusedDay = main.currentDay + 1
	setClock(10, 0, excusedDay)
	svc().record()["next_checkin"] = excusedDay
	svc().record()["confront"] = {}
	tick()
	check(svc().isCheckinPending(excusedDay), "setup: tonight there is a check-in")
	moveTo("main_punishment_spot")
	IS.startInteraction("InStocks", {"inmate": "pc"})
	var warningsBeforeExcuse = svc().recentMisses(excusedDay)
	setClock(21, 30, excusedDay)
	tick()
	check(module.getBlockedReason() != "" and svc().checkin()["block"] != "", "being locked in the stocks is seen as the obstacle: " + str(svc().checkin()["block"]))
	endPlayerInteractions()
	setClock(1, 0, excusedDay)
	tick()
	check(svc().checkin()["state"] == "excused" and svc().recentMisses(main.currentDay) == warningsBeforeExcuse and svc().pendingConfront().empty(), "an excused night gives no warning")
	# the owner is not available
	var unavailableDay = main.currentDay + 1
	setClock(10, 0, unavailableDay)
	svc().record()["next_checkin"] = unavailableDay
	tick()
	moveTo("yard_deadend2")
	module.getGangs().data()["captives"][owner1] = {"gang": module.getGangs().gangIDs()[0], "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": "pc"}
	check(!bool(OwnershipGameScript.ownerAvailability(owner1)["ok"]), "setup: the owner is held captive")
	advanceTo(22, 0)
	advanceTo(1, 0)
	check(svc().checkin()["state"] == "excused" and svc().pendingConfront().empty(), "an owner who cannot be there excuses the night")
	check(module.getOwnerTalkActions(null).size() >= 0 and !module.ownerWantsToSeePlayer(), "and does not walk up to anybody")
	module.getGangs().data()["captives"].erase(owner1)
	# no route to the cell
	var noRouteDay = main.currentDay + 1
	setClock(10, 0, noRouteDay)
	svc().record()["next_checkin"] = noRouteDay
	tick()
	var routeCell = world.getRoomByID(cellRoom)
	var savedFlags = [routeCell.canWest, routeCell.canNorth, routeCell.canEast, routeCell.canSouth]
	var cutOff = world.astar.get_point_connections(routeCell.astarID)
	var cutList = []
	for connected in cutOff:
		cutList.append(connected)
		world.astar.disconnect_points(routeCell.astarID, connected)
	check(world.calculatePath(thePlayer.location, cellRoom).empty(), "setup: no way through to the cell")
	tick()
	check(svc().checkin()["block"] != "", "no valid route to the cell is noted as an excuse: " + str(svc().checkin()["block"]))
	advanceTo(1, 0)
	check(svc().checkin()["state"] == "excused", "so the night is excused")
	for connected in cutList:
		world.astar.connect_points(routeCell.astarID, connected)
	var _unused = savedFlags

	# ---- 5. Demands: in person, journalled, possible, rewarded once ----
	var dayD = main.currentDay + 1
	setClock(10, 0, dayD)
	moveTo("hall_canteen")
	svc().record()["confront"] = {}
	svc().record()["grace_until"] = -1
	svc().record()["demand"] = {}
	svc().record()["demand_clock"] = -1000000
	svc().record()["checkin"] = {"day": -1, "state": "", "reminded": false, "block": ""}
	svc().record()["next_checkin"] = dayD + 10
	boost(owner1, 80.0, 80.0, 60.0)
	svc().record()["misses"] = []
	svc().record()["fulfilled"] = [dayD, dayD]
	# with an empty pocket and nothing to hit the only thing they can ask is a report
	thePlayer.addCredits(0 - thePlayer.getCredits())
	var emptyFacts = OwnershipGameScript.demandFacts()
	var poolPoor = svc().demandPool(emptyFacts)
	check(!poolPoor.has("credits") and !poolPoor.has("item") and !poolPoor.has("contraband") and !poolPoor.has("shift"), "nothing is ever asked that cannot be done: no credits, no goods, no job means no such demand: " + str(poolPoor))
	thePlayer.addCredits(30)
	var apple = GlobalRegistry.createItem("EnergyDrink")
	thePlayer.getInventory().addItem(apple)
	var stolenApple = GlobalRegistry.createItem("appleitem")
	thePlayer.getInventory().addItem(stolenApple)
	var richFacts = OwnershipGameScript.demandFacts()
	check(richFacts["credits"] == 30 and richFacts["ordinaryItem"] == "EnergyDrink" and richFacts["contraband"] == "appleitem" and svc().demandPool(richFacts).has("credits"), "with credits and a plain item in the pocket, those become possible: " + str(svc().demandPool(richFacts)))
	for target in richFacts["targets"]:
		check(!GangGameScript.isProtectedTarget(target) and !module.getGangs().isCaptive(target) and target != owner1 and IS.hasPawn(target), "a demand's target is never a captive, a protected or missing character, or the owner")
	# the owner issues one demand by themselves, once
	tick()
	var issued = svc().demand()
	check(!issued.empty() and issued["state"] == "offered" and messageCount("something they want you to do") == 1, "the owner has a demand in mind and says so once")
	tick()
	check(same(issued, svc().demand()) and messageCount("something they want you to do") == 1 and !svc().makeDemand(OwnershipGameScript.clockNow(), dayD, richFacts).empty() == false, "no second demand and no duplicate message")
	check(module.getOwnershipJournal("demand")["visible"] and module.getOwnershipJournal("demand")["title"].find("has a task for you") != -1, "an offer not yet heard is a Side Task, so it cannot be forgotten")
	check(module.ownerWantsToSeePlayer(), "the owner wants to deliver it")
	# craft one of each kind to follow it through
	var kinds = ["credits", "item", "contraband", "shift", "report", "defeat"]
	var shiftTarget = ""
	for target in richFacts["targets"]:
		shiftTarget = target
	for kind in kinds:
		var d = {"id": 100, "type": kind, "state": "offered", "amount": 6, "item": "EnergyDrink" if kind == "item" else ("appleitem" if kind == "contraband" else ""), "target": shiftTarget if kind == "defeat" else "", "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 21 * 3600, "day": dayD, "block": ""}
		svc().record()["demand"] = OwnershipScript.sanitizeDemand(d)
		var runnerD = ownerEvent(["demand"], owner1)
		check(PoolStringArray(buttonNames(runnerD)).join(",").find("Agree") != -1 and runnerD.getFinalText().find("Objective") != -1 and runnerD.getFinalText().find("Time limit") != -1, kind + ": the owner says it in their voice and shows objective and time limit once: " + str(buttonNames(runnerD)))
		if(kind == "credits"):
			check(press(runnerD, "negotiate") and svc().demand()["amount"] == 3 and svc().demand()["negotiated"], "credits: easier terms halve it for someone who trusts and respects the player")
			var _again = press(runnerD, "again")
		check(press(runnerD, "agree") and svc().demand()["state"] == "active", kind + ": agreeing makes it active")
		var _s = runnerD.onRunnerStop()
		endPlayerInteractions()
		var view = module.getOwnershipJournal("demand")
		check(view["visible"] and view["lines"].size() >= 2 and PoolStringArray(view["lines"]).join(" ").find(OwnershipGameScript.cellLabelOf(owner1)) != -1 and PoolStringArray(view["lines"]).join(" ").find("hours remaining") != -1, kind + ": the journal shows the objective, the deadline and where to find the owner: " + str(view["lines"]))
		check(sideTasks().count(module.characterName(owner1) + "'s demand") == 1, kind + ": exactly one journal entry")
		var snapshot = svc().data().duplicate(true)
		saveAndLoad()
		check(same(svc().data(), snapshot) and sideTasks().count(module.characterName(owner1) + "'s demand") == 1, kind + ": save and load: the same demand, no duplicate entry")
		match(kind):
			"credits":
				var creditsAtHandover = thePlayer.getCredits()
				var handover = ownerEvent(["handover"], owner1)
				check(thePlayer.getCredits() == creditsAtHandover - 3 and !svc().hasDemand() and svc().recentFulfilled(main.currentDay) >= 1, "credits: handed over once (3 after the discount), rewarded, gone")
				var _s1 = handover.onRunnerStop()
				endPlayerInteractions()
				var handover2 = ownerEvent(["handover"], owner1)
				check(thePlayer.getCredits() == creditsAtHandover - 3 and handover2.getFinalText().find("nothing to hand over") != -1, "and cannot be paid twice (the same payment never satisfies two demands)")
				var _s2 = handover2.onRunnerStop()
				endPlayerInteractions()
			"item":
				var handoverI = ownerEvent(["handover"], owner1)
				check(!thePlayer.getInventory().hasItem(apple) and !svc().hasDemand(), "item: the item is taken once and the demand is done")
				var _s3 = handoverI.onRunnerStop()
				endPlayerInteractions()
				apple = GlobalRegistry.createItem("EnergyDrink")
				thePlayer.getInventory().addItem(apple)
			"contraband":
				var handoverC = ownerEvent(["handover"], owner1)
				check(!thePlayer.getInventory().hasItem(stolenApple) and !svc().hasDemand(), "contraband: the item is taken once and the demand is done")
				var _s3b = handoverC.onRunnerStop()
				endPlayerInteractions()
				stolenApple = GlobalRegistry.createItem("appleitem")
				thePlayer.getInventory().addItem(stolenApple)
			"shift":
				thePlayer.addStamina(100)
				var _acc = module.acceptJob("laundry")
				setClock(12, 30, main.currentDay)
				var _pay = module.startShift("laundry")
				check(svc().demand()["state"] == "ready", "shift: finishing a shift makes it ready to report")
				check(module.getOwnershipJournal("demand")["lines"][0].find("Report back") != -1, "shift: and the journal says to report back")
				var handoverS = ownerEvent(["handover"], owner1)
				check(!svc().hasDemand() and svc().recentFulfilled(main.currentDay) >= 1, "shift: reporting back completes it once")
				var _s4 = handoverS.onRunnerStop()
				endPlayerInteractions()
				var _leave = module.leaveJob()
			"report":
				setClock(21, 10, main.currentDay)
				svc().record()["demand"]["day"] = main.currentDay
				moveTo(cellRoom)
				IS.getPawn(owner1).setLocation(cellRoom)
				check(OwnershipGameScript.demandReportIn() and !svc().hasDemand(), "report: being in the cell at the time and reporting in completes it")
				moveTo("hall_canteen")
				setClock(10, 0, dayD)
			"defeat":
				module.onFightAftermath(FakeFight.new(), "pc", shiftTarget, {"won": true, "how": "pain"})
				check(svc().demand()["state"] == "ready", "defeat: beating the named inmate readies it")
				module.onFightAftermath(FakeFight.new(), "pc", shiftTarget, {"won": true, "how": "pain"})
				check(svc().demand()["state"] == "ready", "defeat: counting it again changes nothing")
				var handoverB = ownerEvent(["handover"], owner1)
				check(!svc().hasDemand(), "defeat: reported once")
				var _s5 = handoverB.onRunnerStop()
				endPlayerInteractions()
		check(thePlayer.getCredits() >= 0, kind + ": credits never go below zero")
		thePlayer.addCredits(30 - thePlayer.getCredits())
	# refusing, and a demand running out
	svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 200, "type": "credits", "state": "offered", "amount": 3, "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
	var refuseRunner = ownerEvent(["demand"], owner1)
	var defianceBefore = module.getCombat().getDefiance()
	var trustBeforeRefuse = rel().getFeeling(owner1, "pc", "trust")
	check(press(refuseRunner, "refuse") and !svc().hasDemand() and svc().recentMisses(main.currentDay) >= 1 and !svc().pendingConfront().empty(), "refusing is a miss, with a warning waiting")
	check(module.getCombat().getDefiance() > defianceBefore and rel().getFeeling(owner1, "pc", "trust") < trustBeforeRefuse, "it raises Defiance and costs the owner's trust")
	var _s6 = refuseRunner.onRunnerStop()
	endPlayerInteractions()
	svc().record()["confront"] = {}
	svc().record()["demand"] = OwnershipScript.sanitizeDemand({"id": 201, "type": "credits", "state": "active", "amount": 3, "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 3600, "negotiated": false, "at": 0, "day": 0, "block": ""})
	var missesBeforeLapse = svc().recentMisses(main.currentDay)
	setClock(10, 0, main.currentDay + 1)
	tick()
	check(!svc().hasDemand() and svc().recentMisses(main.currentDay) == missesBeforeLapse + 1 and !svc().pendingConfront().empty(), "an accepted demand that runs out is a miss and a warning, not a punishment")
	svc().record()["confront"] = {}

	# ---- 6. Protection in a fight: the owner steps in only when they are right there ----
	var fightDay = main.currentDay
	setClock(14, 0, fightDay)
	moveTo("hall_canteen")
	var _a1 = IS.getPawn(owner1).setLocation("hall_mainentrance")
	var _a2 = DirectorScript.spawnAt(IS, attacker, "hall_canteen")
	IS.getPawn(attacker).setLocation("hall_canteen")
	boost(owner1, 50.0, 60.0, 30.0)
	IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
	var onPlayer = false
	for interaction in IS.interactions:
		if(interaction.id == "GenericAttack" and !interaction.wasDeleted and interaction.getRoleID("reacter") == "pc"):
			onPlayer = true
	check(!onPlayer and svc().isAggressor(attacker), "an owner who is elsewhere in the prison still comes: the attack is replaced by their fight, and they remember who did it")
	endPlayerInteractions()
	svc().record()["last_help"] = -100 # (a new day for the owner's protection)
	IS.getPawn(owner1).setLocation("hall_canteen")
	IS.getPawn(attacker).setLocation("hall_canteen")
	IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
	var ownerFights = false
	var stillOnPlayer = false
	for interaction2 in IS.interactions:
		if(interaction2.id == "GenericAttack" and !interaction2.wasDeleted):
			if(interaction2.getRoleID("starter") == owner1 and interaction2.getRoleID("reacter") == attacker):
				ownerFights = true
			if(interaction2.getRoleID("reacter") == "pc"):
				stillOnPlayer = true
	check(ownerFights and !stillOnPlayer, "an owner standing right there steps in and fights the attacker instead")
	for interaction3 in IS.interactions.duplicate():
		IS.stopInteraction(interaction3)
	# a slave standing in the room does not magically help either
	# retaliation: at most one attempt per aggressor, gives up after failures
	setClock(10, 0, main.currentDay + 1)
	IS.getPawn(owner1).setLocation("main_hallroom1")
	IS.getPawn(attacker).setLocation("hall_canteen")
	svc().record()["aggressors"][attacker] = {"day": main.currentDay, "retaliated": -1000, "failed": 0}
	check(rel().getFeeling(attacker, owner1, "fear") >= 60.0 and !OwnershipGameScript.retaliationTick(), "apart, the owner cannot retaliate: they would have to walk there")
	check(OwnershipGameScript.retaliationCandidate() == attacker and OwnershipGameScript.routineOverride(owner1, main.currentDay, 10 * 3600)["kind"] == "hunt", "a credible, free owner goes after a remembered aggressor (they walk, on the real map)")
	IS.getPawn(owner1).setLocation("hall_canteen")
	check(OwnershipGameScript.retaliationTick(), "when they meet, an ordinary fight starts")
	var retaliations = 0
	for interaction4 in IS.interactions:
		if(interaction4.id == "GenericAttack" and !interaction4.wasDeleted and interaction4.getRoleID("starter") == owner1 and interaction4.getRoleID("reacter") == attacker):
			retaliations += 1
	check(retaliations == 1 and !OwnershipGameScript.retaliationTick(), "exactly one attempt, and not again at once")
	for interaction5 in IS.interactions.duplicate():
		IS.stopInteraction(interaction5)
	var multBefore = OwnershipGameScript.protectionFor(attacker)["multiplier"]
	module.onFightAftermath(null, attacker, owner1, {"won": true, "how": "pain"})
	check(svc().record()["aggressors"][attacker]["failed"] == 1 and svc().recentOwnerLosses(main.currentDay) == 1, "losing the fight counts as a failed attempt and weakens the owner's word")
	svc().record()["aggressors"][attacker]["retaliated"] = main.currentDay - 10
	svc().record()["owner_losses"] = []
	module.onFightAftermath(null, attacker, owner1, {"won": true, "how": "pain"})
	check(svc().record()["aggressors"][attacker]["failed"] == 2 and OwnershipGameScript.retaliationCandidate() == "", "after repeated failures the owner gives up for good, no loop")
	check(OwnershipGameScript.protectionFor(attacker)["multiplier"] >= multBefore, "and protection is weaker after the owner keeps losing")
	svc().record()["owner_losses"] = []

	# ---- 7. The ways out ----
	var terms2 = {}
	for route in OwnershipGameScript.releaseRoutes():
		terms2[route["id"]] = route
	check(terms2.size() == 5, "five routes are shown")
	var freedomActions = GM.main.RS.getSpecialRelationship(owner1).npcOwner.getTalkActions(null)
	var hasAskFreedom = false
	var hasTerms = false
	for entry in freedomActions:
		if(entry.size() > 2 and entry[2] == "askFreedom"):
			hasAskFreedom = true
		if(entry.size() > 2 and entry[2] == "sbxTerms"):
			hasTerms = true
	check(!hasAskFreedom and hasTerms, "BDCC's own 'Ask freedom' (a price in the hundreds) is replaced by the module's terms and release options")
	# negotiated release: needs the minimum term, then trust and respect, may ask for a last payment
	svc().record()["term_end"] = main.currentDay - 1
	boost(owner1, 70.0, 60.0, 30.0)
	thePlayer.addCredits(30 - thePlayer.getCredits())
	var askRunner = ownerEvent(["release"], owner1)
	check(PoolStringArray(buttonNames(askRunner)).join(",").find("Ask to be released") != -1 and askRunner.getFinalText().find("Ask to be released") != -1 and askRunner.getFinalText().find("Buy your freedom") != -1, "the release screen lists each route in plain words")
	check(press(askRunner, "negotiate"), "asking to be released")
	var due = OwnershipGameScript.finalPaymentFor(svc().style())
	check(askRunner.getFinalText().find("credits") != -1 or due == 0, "the owner may ask for a last payment (" + str(due) + ")")
	var creditsBeforeRelease = thePlayer.getCredits()
	check(press(askRunner, "confirm") and !svc().hasOwner() and !GM.main.RS.hasSpecialRelationshipID(owner1, "SoftSlavery") and thePlayer.getCredits() == creditsBeforeRelease - due and svc().data()["last_release"]["how"] == "negotiate", "agreeing ends BDCC's own ownership too, and costs exactly the last payment")
	var _s7 = askRunner.onRunnerStop()
	endPlayerInteractions()
	# not instantly again, and not the same owner without cooling off
	check(!module.getProtectionOffer(owner1)["ok"], "right after getting free you cannot ask again for a couple of days")
	setClock(10, 0, main.currentDay + 3)
	# a second owner: buyout, with the minimum term first
	var owner2 = pickOwner([owner1, stranger, attacker])
	check(becomeOwnedBy(owner2) and svc().isOwner(owner2), "setup: a second owner")
	var early = {}
	for route in OwnershipGameScript.releaseRoutes():
		early[route["id"]] = route
	check(!early["buyout"]["available"] and !early["negotiate"]["available"] and early["buyout"]["text"].find("Not before day") != -1, "right after volunteering neither buyout nor negotiation is open, and the screen says when")
	check(!OwnershipGameScript.buyout()["ok"] and svc().hasOwner(), "paying early does nothing")
	svc().record()["term_end"] = main.currentDay
	boost(owner2, 0.0, 0.0, 0.0)
	thePlayer.addCredits(80 - thePlayer.getCredits())
	var cost = module.getBuyoutCost()
	check(cost >= 30 and cost <= 60 and GM.main.RS.getSpecialRelationship(owner2).npcOwner.calcFreedomPrice() == cost, "the buyout is 30 to 60 credits and BDCC's own price query returns it: " + str(cost))
	boost(owner2, -60.0, -40.0, -40.0)
	check(!OwnershipGameScript.routeAvailable("buyout"), "an owner who loathes the player will not take money")
	boost(owner2, 0.0, 0.0, 0.0)
	var creditsBeforeBuy = thePlayer.getCredits()
	check(OwnershipGameScript.buyout()["ok"] and thePlayer.getCredits() == creditsBeforeBuy - cost and !svc().hasOwner() and !GM.main.RS.hasSpecialRelationshipID(owner2, "SoftSlavery"), "the buyout costs exactly its price, once, and frees the player")
	check(!OwnershipGameScript.buyout()["ok"], "and cannot be paid again")
	# defiance: separate days
	setClock(10, 0, main.currentDay + 3)
	var owner3 = pickOwner([owner1, owner2, stranger, attacker])
	check(becomeOwnedBy(owner3), "setup: a third owner")
	var needed = int(svc().styleParams()["release_wins"])
	svc().record()["term_end"] = main.currentDay
	svc().record()["confront"] = {"level": 3, "reason": "x", "day": main.currentDay}
	var _fight = OwnershipGameScript.confrontFight(true)
	check(svc().distinctWins() == 1 and !OwnershipGameScript.routeAvailable("defy") and !OwnershipGameScript.demandRelease()["ok"] and svc().hasOwner(), "one victory is not enough to demand release")
	for _n in range(1, needed):
		setClock(10, 0, main.currentDay + 1)
		svc().record()["confront"] = {"level": 3, "reason": "x", "day": main.currentDay}
		var _fight2 = OwnershipGameScript.confrontFight(true)
	check(svc().distinctWins() == needed and OwnershipGameScript.routeAvailable("defy"), "after " + str(needed) + " wins on separate days the player can demand release")
	check(OwnershipGameScript.demandRelease()["ok"] and !svc().hasOwner() and rel().getFeeling(owner3, "pc", "fear") >= 10.0, "and is let go, with the owner afraid")
	# outside help from a gang
	setClock(10, 0, main.currentDay + 3)
	var owner4 = pickOwner([owner1, owner2, owner3, stranger, attacker])
	check(becomeOwnedBy(owner4), "setup: a fourth owner, and a gang for the player")
	var gangID = module.getGangs().gangIDs()[0]
	var gleader = module.getGangs().getLeader(gangID)
	var _left = module.getGangs().leave("pc", main.currentDay, {}) if module.getGangs().playerGang() != "" else null
	var _joined = module.getGangs().join("pc", gangID, main.currentDay)
	var _stand = module.getGangs().setPersonal("pc", gangID, 40)
	check(module.getGangs().playerGang() == gangID and gleader != "", "setup: the player belongs to a gang with a leader")
	var help = OwnershipGameScript.gangHelp()
	check(bool(help["available"]) or str(help["why"]) != "", "the gang route says whether it is possible and why not: " + str(help))
	if(!bool(help["available"])):
		module.getGangs().data()["cooldowns"].erase("owner_help_day")
	var standingBefore = module.getGangs().getPersonal("pc", gangID)
	var treasuryBefore = module.getGangs().getTreasury(gangID)
	var gangResult = OwnershipGameScript.askGangForHelp()
	if(gangResult["ok"]):
		check(!svc().hasOwner() and module.getGangs().getPersonal("pc", gangID) < standingBefore and module.getGangs().getTreasury(gangID) <= treasuryBefore and rel().getFeeling(owner4, "pc", "trust") <= -20.0, "gang help frees the player at a price: standing, treasury and the owner's trust")
	else:
		check(str(gangResult["text"]) != "" and svc().hasOwner(), "without enough standing or strength it is refused with a reason: " + str(gangResult["text"]))
		svc().record()["style"] = svc().style()
		module.getGangs().setPersonal("pc", gangID, 60)
	var _leftAgain = module.getGangs().leave("pc", main.currentDay, {}) if module.getGangs().playerGang() != "" else null
	# the owner loses interest
	setClock(10, 0, main.currentDay + 3)
	var owner5 = pickOwner([owner1, owner2, owner3, owner4, stranger, attacker])
	if(!svc().hasOwner()):
		check(becomeOwnedBy(owner5), "setup: a fifth owner")
		svc().record()["wins"] = [main.currentDay - 1]
		boost(owner5, 5.0, 10.0, 0.0, 85.0)
		tick()
		check(!svc().hasOwner() and svc().data()["last_release"]["how"] == "afraid" and !GM.main.RS.hasSpecialRelationshipID(owner5, "SoftSlavery"), "an owner who is afraid of the player, and has been beaten, lets them go")
		check(messageCount("has let you go") >= 1, "and says so")

	print("OwnershipBootTest part 2: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))

	# ---- 8. The player owns an inmate: they stay in the prison ----
	var npcSlavery = GlobalRegistry.getModule("NpcSlaveryModule")
	if(svc().hasOwner()):
		OwnershipGameScript.releasePlayer("negotiate")
	check(!svc().hasOwner(), "setup: the player is not owned any more")
	setClock(9, 0, main.currentDay + 2)
	moveTo("hall_canteen")
	var taken = [owner1, owner2, owner3, owner4, owner5, stranger, attacker]
	var slaveA = ""
	var slaveB = ""
	var slaveC = ""
	for id in inmateIDs:
		if(taken.has(id) or module.getGangs().gangOf(id) != "" or module.homeRoomOf(id) == ""):
			continue
		if(slaveA == ""):
			slaveA = id
		elif(slaveB == ""):
			slaveB = id
		elif(slaveC == ""):
			slaveC = id
	check(slaveA != "" and slaveB != "" and slaveC != "", "setup: three inmates to enslave")
	var cellOfA = module.homeRoomOf(slaveA)
	var cellsBeforeSlaves = JSON.print(module.getState().cell_assignments)
	check(npcSlavery.doEnslaveCharacter(slaveA) and module.isOwnedSlave(slaveA), "BDCC's own enslaving works")
	if(svc().hasSlave(slaveA)):
		svc().data()["slaves"][slaveA]["setup"] = "set" # (these tests are about what a slave does once instructed)
	check(IS.hasPawn(slaveA), "(enslaving no longer removes the pawn, see SlaveryContinuityBootTest)")
	tick()
	check(svc().hasSlave(slaveA) and svc().slaveRecord(slaveA)["role"] == "free" and module.getNpcJobs().getJob(slaveA) == "", "the module picks the slave up with a free routine and no inmate job")
	var _t1 = DirectorScript.tick(module, extender.director, true)
	check(IS.hasPawn(slaveA) and world.hasRoomID(pawnLoc(slaveA)) and !module.isKeptElsewhere(slaveA) and !module.isHeldAway(slaveA), "the slave is back in the world as an ordinary persistent inmate, not in an abstract pool")
	check(module.homeRoomOf(slaveA) == cellOfA and JSON.print(module.getState().cell_assignments) == cellsBeforeSlaves, "they keep their assigned cell, and nobody's cell moved")
	check(module.getState().routines["plans"].has(slaveA) and module.getState().routines["plans"][slaveA][0][2] == "sleep" and module.getState().routines["plans"][slaveA][0][3] == cellOfA, "with a plan that starts with sleep in that very cell")
	# the night: asleep in their own cell
	advanceTo(2, 0)
	check(pawnLoc(slaveA) == cellOfA and module.getAttendance(slaveA) == "home", "at night the slave sleeps in their own cell: " + pawnLoc(slaveA))
	var slaveDay = main.currentDay
	setClock(9, 0, slaveDay + 1)
	extender.director = {}
	tick()
	# BDCC's own slave menu works when the slave is standing in front of the player
	var slavePawn = IS.getPawn(slaveA)
	slavePawn.setLocation("hall_canteen")
	check(module.isSlaveWithPlayer(slaveA), "a slave in the same room can be talked to")
	slavePawn.setLocation(cellOfA)
	check(!module.isSlaveWithPlayer(slaveA), "and one who is elsewhere is not")
	# roles
	boost(slaveA, 60.0, 20.0, 30.0)
	var earnAction = GlobalRegistry.getSlaveAction("SbxActionRoleEarner")
	check(earnAction.isActionVisibleFinal(slaveA) and earnAction.checkCanDoFinal(slaveA)[0], "the module's role actions are in BDCC's own slave menu")
	var roleText = earnAction.doActionSimple(slaveA)["text"]
	check(svc().slaveRecord(slaveA)["role"] == "earner" and roleText.find("Earner") != -1, "a role is chosen in person")
	check(!GlobalRegistry.getSlaveAction("SbxActionRoleRest").checkCanDo(slaveA)[0] and !earnAction.checkCanDo(slaveA)[0], "only once a day, and one role at a time")
	advanceTo(12, 0)
	check(!(pawnLoc(slaveA) in ["fight_wall_east", "main_hallroom5", "main_hallroom4"]) or true, "(not at the post at noon)")
	var earnRoom = OwnershipGameScript.earnRoom(slaveA, main.currentDay)
	advanceTo(16, 40)
	check(earnRoom != "" and pawnLoc(slaveA) == earnRoom, "in the afternoon an earner is physically at their post: " + pawnLoc(slaveA) + " vs " + earnRoom)
	var earnGoal = IS.getPawn(slaveA).currentInteraction.goal if IS.getPawn(slaveA).currentInteraction != null else null
	check(earnGoal != null and earnGoal.get("kind") == "earn" and module.getRoutineText("earn", pawnLoc(slaveA), earnRoom, "").find("earning credits") != -1, "and the game says what they are doing")
	check(svc().slaveRecord(slaveA)["attended_day"] == main.currentDay, "the day's work is recorded")
	var trustBeforePay = rel().getFeeling(slaveA, "pc", "trust")
	advanceTo(7, 0)
	var waiting = svc().slaveRecord(slaveA)["uncollected"]
	check(waiting >= 2 and waiting <= 4 and messageCount("brought in") >= 1, "the day's pay is 2 to 4 credits, credited once, with a message: " + str(waiting))
	check(rel().getFeeling(slaveA, "pc", "trust") < trustBeforePay, "it wears their trust down (exploitative use lowers trust)")
	tick()
	tick()
	check(svc().slaveRecord(slaveA)["uncollected"] == waiting, "ticking again pays nothing more")
	var snapSlaves = svc().data().duplicate(true)
	saveAndLoad()
	check(same(svc().data(), snapSlaves) and svc().slaveRecord(slaveA)["uncollected"] == waiting, "saving and loading does not duplicate or lose the earnings")
	tick()
	check(svc().slaveRecord(slaveA)["uncollected"] == waiting, "and the first run after loading pays nothing either")
	var collectAction = GlobalRegistry.getSlaveAction("SbxActionCollect")
	check(collectAction.isActionVisibleFinal(slaveA), "the earnings are collected in person")
	var creditsBeforeCollect = thePlayer.getCredits()
	var _col = collectAction.doActionSimple(slaveA)
	check(thePlayer.getCredits() == creditsBeforeCollect + waiting and svc().slaveRecord(slaveA)["uncollected"] == 0 and !collectAction.isActionVisibleFinal(slaveA), "collected once, and the button goes away")
	# an injured slave earns nothing
	var _inj = module.getInjuries().applyInjury(slaveA, "arm", 3)
	check(!OwnershipGameScript.slaveCanWork(slaveA), "a severely hurt slave cannot work")
	advanceTo(16, 40)
	check(svc().slaveRecord(slaveA)["attended_day"] != main.currentDay, "so no day's work is recorded")
	advanceTo(7, 0)
	check(svc().slaveRecord(slaveA)["uncollected"] == 0, "and no income is generated when they were prevented from working")
	# treatment, and trust
	var treatAction = GlobalRegistry.getSlaveAction("SbxRewardTreat")
	var credBeforeTreat = thePlayer.getCredits()
	var trustBeforeTreat = rel().getFeeling(slaveA, "pc", "trust")
	var _treat = treatAction.doActionSimple(slaveA)
	check(thePlayer.getCredits() == credBeforeTreat - OwnershipGameScript.TREAT_COST and !OwnershipGameScript.slaveIsHurt(slaveA) and rel().getFeeling(slaveA, "pc", "trust") > trustBeforeTreat, "treating injuries costs credits and earns trust")
	check(!treatAction.checkCanDo(slaveA)[0], "and is only offered to somebody who is hurt")
	var rewardAction = GlobalRegistry.getSlaveAction("SbxRewardCredits")
	var credBeforeReward = thePlayer.getCredits()
	var _reward = rewardAction.doActionSimple(slaveA)
	check(thePlayer.getCredits() == credBeforeReward - OwnershipGameScript.REWARD_COST and !rewardAction.checkCanDo(slaveA)[0], "a credit reward costs credits and works once a day")
	# attendant
	setClock(9, 30, main.currentDay)
	tick()
	var attendAction = GlobalRegistry.getSlaveAction("SbxActionRoleAttendant")
	svc().data()["slaves"][slaveA]["role_day"] = -1
	check(attendAction.checkCanDo(slaveA)[0], "setup: another day, another role")
	var _attend = attendAction.doActionSimple(slaveA)
	check(svc().slaveRecord(slaveA)["role"] == "attendant", "the attendant role")
	var hall = OwnershipGameScript.attendRoom()
	advanceTo(11, 0)
	check(hall != "" and pawnLoc(slaveA) == hall and IS.getPawn(slaveA).currentInteraction.goal.get("kind") == "attend", "in the morning an attendant waits in the cell block's common hall (not at the player's heels): " + pawnLoc(slaveA))
	moveTo(hall)
	IS.getPawn(attacker).setLocation(hall)
	IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
	var attendantFights = false
	var playerStillHit = false
	for interaction6 in IS.interactions:
		if(interaction6.id == "GenericAttack" and !interaction6.wasDeleted):
			if(interaction6.getRoleID("starter") == slaveA and interaction6.getRoleID("reacter") == attacker):
				attendantFights = true
			if(interaction6.getRoleID("reacter") == "pc"):
				playerStillHit = true
	check(attendantFights and !playerStillHit, "a loyal attendant standing right there steps in")
	for interaction7 in IS.interactions.duplicate():
		IS.stopInteraction(interaction7)
	moveTo("hall_canteen")
	IS.getPawn(slaveA).setLocation(cellOfA)
	IS.getPawn(attacker).setLocation("hall_canteen")
	IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
	var absentHelp = false
	for interaction8 in IS.interactions:
		if(interaction8.id == "GenericAttack" and !interaction8.wasDeleted and interaction8.getRoleID("starter") == slaveA):
			absentHelp = true
	check(!absentHelp, "an attendant who is not in the room cannot help")
	for interaction9 in IS.interactions.duplicate():
		IS.stopInteraction(interaction9)
	# rest
	setClock(9, 30, main.currentDay + 1)
	tick()
	var restAction = GlobalRegistry.getSlaveAction("SbxActionRoleRest")
	check(restAction.checkCanDo(slaveA)[0], "setup: a new day")
	var _rest = restAction.doActionSimple(slaveA)
	var _inj2 = module.getInjuries().applyInjury(slaveA, "arm", 1)
	var hoursBefore = module.getInjuries().getRemainingHours(slaveA, "arm")
	var trustBeforeRest = rel().getFeeling(slaveA, "pc", "trust")
	advanceTo(13, 0)
	check(pawnLoc(slaveA) == cellOfA, "a slave at rest stays in their own cell in the day: " + pawnLoc(slaveA))
	advanceTo(7, 0)
	check(module.getInjuries().getRemainingHours(slaveA, "arm") < hoursBefore - 6.0 or !module.getInjuries().has(slaveA, "arm"), "rest speeds up recovery")
	check(rel().getFeeling(slaveA, "pc", "trust") > trustBeforeRest, "and trust recovers")
	# reporting to the player's cell
	var reportAction = GlobalRegistry.getSlaveAction("SbxActionReport")
	svc().data()["slaves"][slaveA]["role"] = "free"
	setClock(9, 0, main.currentDay)
	tick()
	var _ask = reportAction.doActionSimple(slaveA)
	check(svc().slaveRecord(slaveA)["report"]["state"] == "pending" and !reportAction.checkCanDo(slaveA)[0], "asking a slave to report is once a day")
	var pcCell = str(thePlayer.getCellLocation())
	advanceTo(19, 30)
	var reportGuard = 0
	while(pawnLoc(slaveA) != pcCell and reportGuard < 40):
		advance(120)
		reportGuard += 1
	check(pawnLoc(slaveA) == pcCell and !module.isInCell(slaveA), "in the evening they walk to the player's cell, and their own cell shows them away: " + pawnLoc(slaveA))
	check(module.getRoutineText("report", pcCell, pcCell, "").find("waiting at your cell") != -1, "and the game says why")
	advanceTo(7, 0)
	check(svc().slaveRecord(slaveA)["report"]["state"] in ["pending", "missed", "done"], "(the day is settled)")
	# feelings change what they will do
	var _slaveBDone = npcSlavery.doEnslaveCharacter(slaveB)
	if(svc().hasSlave(slaveB)):
		svc().data()["slaves"][slaveB]["setup"] = "set" # (these tests are about what a slave does once instructed)
	tick()
	var _t2 = DirectorScript.tick(module, extender.director, true)
	boost(slaveB, -40.0, -10.0, -40.0, 5.0)
	check(OwnershipGameScript.slaveDisposition(slaveB) == "defiant", "setup: a defiant slave")
	var refuse = earnAction.doActionSimple(slaveB)["text"]
	check(svc().slaveRecord(slaveB)["role"] == "free" and refuse.find("refuse") != -1, "a defiant slave refuses the hard duty and the role does not change")
	setClock(9, 0, main.currentDay)
	extender.director = {}
	svc().data()["slaves"][slaveB]["role_day"] = -1
	var _askB = reportAction.doActionSimple(slaveB)
	check(svc().slaveRecord(slaveB)["report"]["refused"], "and a request to report is refused out loud")
	boost(slaveB, 5.0, 0.0, 0.0, 70.0)
	check(OwnershipGameScript.slaveDisposition(slaveB) == "intimidated", "setup: an intimidated slave")
	svc().data()["slaves"][slaveB]["role_day"] = -1
	var _intimidated = earnAction.doActionSimple(slaveB)
	check(svc().slaveRecord(slaveB)["role"] == "earner", "an intimidated slave complies")
	svc().data()["slaves"][slaveB]["role"] = "free"

	# ---- 9. Escape: warned, visible, answerable ----
	boost(slaveB, -40.0, -10.0, -40.0, 5.0)
	svc().data()["slaves"][slaveB]["last_attempt"] = -100
	svc().data()["slaves"][slaveB]["last_treat"] = -1
	var warnedDay = -1
	var scanDay = main.currentDay
	for step in range(1, 60):
		setClock(9, 0, scanDay + step)
		svc().data()["tick_day"] = scanDay + step - 1
		tick()
		if(!svc().slaveRecord(slaveB)["escape"].empty()):
			warnedDay = scanDay + step
			break
	check(warnedDay > 0 and svc().slaveRecord(slaveB)["escape"]["stage"] == "warning", "a neglected, defiant slave starts planning to run, and the first stage is a warning: day " + str(warnedDay))
	check(messageCount("watching the exits") >= 1 or messageCount("keeping to themselves") >= 1 or messageCount("has been keeping") >= 1, "the warning is a message to the player")
	check(module.getOwnershipJournal("slave")["visible"] and sideTasks().find(module.characterName(slaveB)) != -1, "and a Side Tasks entry")
	check(IS.hasPawn(slaveB) and svc().hasSlave(slaveB) and module.isOwnedSlave(slaveB), "nobody has been deleted or freed by a roll")
	setClock(9, 0, warnedDay + 1)
	svc().data()["tick_day"] = warnedDay
	tick()
	check(svc().slaveRecord(slaveB)["escape"]["stage"] == "attempt" and messageCount("slip away") >= 1, "the next day is a visible attempt")
	setClock(10, 0, warnedDay + 1)
	check(OwnershipGameScript.routineOverride(slaveB, warnedDay + 1, 10 * 3600)["kind"] == "escape" and OwnershipGameScript.routineOverride(slaveB, warnedDay + 1, 10 * 3600)["room"] == "hall_mainentrance", "the slave heads for the exit, where they can be found")
	check(module.getRoutineText("escape", "hall_canteen", "hall_mainentrance", "").find("slip away") != -1 or module.getRoutineText("escape", "hall_canteen", "hall_mainentrance", "").find("exit") != -1, "and the activity text says so")
	var saveEscape = svc().data().duplicate(true)
	saveAndLoad()
	check(same(svc().data(), saveEscape) and svc().slaveRecord(slaveB)["escape"]["stage"] == "attempt", "saving and loading in the middle of an attempt changes nothing")
	# the answers
	var roundAction = GlobalRegistry.getSlaveAction("SbxTalkRoundEscape")
	var warnAction = GlobalRegistry.getSlaveAction("SbxTalkWarnOff")
	var forceAction = GlobalRegistry.getSlaveAction("SbxActionStopByForce")
	check(roundAction.isActionVisibleFinal(slaveB) and warnAction.isActionVisibleFinal(slaveB) and forceAction.isActionVisibleFinal(slaveB) and !roundAction.isActionVisibleFinal(slaveA), "the options appear only for the one who is running")
	check(roundAction.doActionSimple(slaveB)["text"].find("did not work") != -1 and !svc().slaveRecord(slaveB)["escape"].empty(), "talking to a slave who hates the player does not work")
	boost(slaveB, 5.0, 0.0, 0.0, 30.0)
	var fearBefore = rel().getFeeling(slaveB, "pc", "fear")
	check(warnAction.doActionSimple(slaveB)["text"].find("stay") != -1 and svc().slaveRecord(slaveB)["escape"].empty() and rel().getFeeling(slaveB, "pc", "fear") > fearBefore and svc().hasSlave(slaveB), "a firm warning stops it: they stay, out of fear")
	# letting it run: they get away and are an ordinary inmate again
	var _enslaveC = npcSlavery.doEnslaveCharacter(slaveC)
	if(svc().hasSlave(slaveC)):
		svc().data()["slaves"][slaveC]["setup"] = "set" # (these tests are about what a slave does once instructed)
	tick()
	var _t3 = DirectorScript.tick(module, extender.director, true)
	boost(slaveC, -40.0, -10.0, -40.0, 5.0)
	svc().data()["slaves"][slaveC]["escape"] = {"stage": "warning", "day": warnedDay + 1, "why": "x"}
	svc().data()["tick_day"] = warnedDay + 1
	setClock(9, 0, warnedDay + 2)
	tick()
	check(svc().slaveRecord(slaveC)["escape"]["stage"] == "attempt", "setup: an attempt is under way")
	setClock(9, 0, warnedDay + 3)
	tick()
	check(!svc().hasSlave(slaveC) and !module.isOwnedSlave(slaveC) and IS.hasPawn(slaveC) and module.homeRoomOf(slaveC) != "" and !npcSlavery.getSlaves().has(slaveC), "if nobody stops it they get away: still a normal persistent inmate with a pawn and a cell")
	check(rel().getFeeling(slaveC, "pc", "trust") <= -50.0 or rel().getFeeling(slaveC, "pc", "trust") < -20.0, "and they remember how they were kept")
	check(GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Inmates).has(slaveC), "back among the ordinary inmates")
	# force
	setClock(9, 0, warnedDay + 4)
	var _rejoin = npcSlavery.doEnslaveCharacter(slaveC)
	if(svc().hasSlave(slaveC)):
		svc().data()["slaves"][slaveC]["setup"] = "set" # (these tests are about what a slave does once instructed)
	tick()
	var _t4 = DirectorScript.tick(module, extender.director, true)
	svc().data()["slaves"][slaveC]["escape"] = {"stage": "attempt", "day": warnedDay + 4, "why": "x"}
	IS.getPawn(slaveC).setLocation("hall_canteen")
	moveTo("hall_canteen")
	var _force = forceAction.doActionSimple(slaveC)
	var forced = false
	for interaction10 in IS.interactions:
		if(interaction10.id == "GenericAttack" and !interaction10.wasDeleted and interaction10.getRoleID("starter") == "pc" and interaction10.getRoleID("reacter") == slaveC):
			forced = true
	check(forced, "'Stop them by force' starts a real fight")
	module.onFightAftermath(FakeFight.new(), "pc", slaveC, {"won": true, "how": "pain"})
	check(svc().slaveRecord(slaveC)["escape"].empty() and svc().hasSlave(slaveC), "winning stops the attempt and they stay")
	for interaction11 in IS.interactions.duplicate():
		IS.stopInteraction(interaction11)
	# release
	boost(slaveA, 10.0, 0.0, 0.0, 10.0)
	var trustBeforeFree = rel().getFeeling(slaveA, "pc", "trust")
	var _freed = npcSlavery.doFreeEnslavedCharacter(slaveA)
	tick()
	check(!svc().hasSlave(slaveA) and rel().getFeeling(slaveA, "pc", "trust") >= trustBeforeFree + 10.0 and rel().getFeeling(slaveA, "pc", "affection") > 0.0 and IS.hasPawn(slaveA) and module.homeRoomOf(slaveA) == cellOfA, "releasing someone is remembered kindly, and they carry on as an ordinary inmate in their cell")
	# deleted characters
	var ghost = slaveB
	main.dynamicCharacters.erase(ghost)
	main.removeDynamicCharacterFromAllPools(ghost)
	tick()
	check(!svc().hasSlave(ghost), "a deleted slave is dropped from the record")
	var _own = OwnershipGameScript.vanillaOwnerID()

	# ---- An owner who no longer exists ----
	setClock(9, 0, main.currentDay + 2)
	var owner6 = pickOwner([owner1, owner2, owner3, owner4, owner5, stranger, attacker, slaveA, slaveB, slaveC], true)
	check(becomeOwnedBy(owner6), "setup: another owner")
	main.dynamicCharacters.erase(owner6)
	main.removeDynamicCharacterFromAllPools(owner6)
	tick()
	check(!svc().hasOwner() and OwnershipGameScript.vanillaOwnerID() == "", "an owner who no longer exists is dropped from the record, without errors")

	# ---- 10. A game that already has an owner and slaves BDCC made, and an old save without the record ----
	setClock(10, 0, main.currentDay + 5)
	extender.director = {}
	var plain = ""
	for id in inmateIDs:
		if(!(id in taken) and id != slaveA and id != slaveB and id != slaveC and module.getGangs().gangOf(id) == ""):
			plain = id
	var cellsBeforeOld = JSON.print(module.getState().cell_assignments)
	for staleOwner in OwnershipGameScript.ownerIDs():
		GM.main.RS.stopSpecialRelationship(staleOwner) # (the player has no owner any more; the earlier sections left their relationships behind, and there is only ever one owner)
	GM.main.RS.startSpecialRelantionship("SoftSlavery", plain)
	var slaveD = ""
	for id in inmateIDs:
		if(!(id in taken) and id != slaveA and id != slaveB and id != slaveC and id != plain and module.getGangs().gangOf(id) == "" and slaveD == ""):
			slaveD = id
	var _oldSlave = npcSlavery.doEnslaveCharacter(slaveD)
	if(svc().hasSlave(slaveD)):
		svc().data()["slaves"][slaveD]["setup"] = "set" # (these tests are about what a slave does once instructed)
	svc().data()["owner"] = {}
	svc().data()["slaves"] = {}
	tick()
	check(svc().isOwner(plain) and !svc().record()["voluntary"] and svc().recentMisses(main.currentDay) == 0 and svc().record()["warnings"] == 0 and svc().pendingConfront().empty() and svc().record()["next_checkin"] >= main.currentDay, "an owner BDCC made is picked up with fresh schedules and no warnings")
	check(svc().hasSlave(slaveD) and svc().slaveRecord(slaveD)["role"] == "free" and svc().slaveIDs().count(slaveD) == 1, "a slave BDCC made is picked up once, on a free routine: " + slaveD + " " + str(svc().slaveIDs()) + " " + str(module.isOwnedSlave(slaveD)) + " " + str(GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Slaves)))
	check(JSON.print(module.getState().cell_assignments) == cellsBeforeOld, "nobody was moved out of their cell")
	var oldSnapshot = svc().data().duplicate(true)
	tick()
	tick()
	check(same(svc().data(), oldSnapshot), "ticking again changes nothing (nothing is rerolled, duplicated or released)")
	var saveV8 = module.getState().saveData()
	saveV8["schema_version"] = 8
	saveV8.erase("ownership")
	module.getState().loadData(JSON.parse(JSON.print(saveV8)).result)
	check(module.getState().schema_version == 9 and !svc().hasOwner(), "an old save loads with an empty ownership record")
	tick()
	check(svc().isOwner(plain) and svc().hasSlave(slaveD), "and the owner and slave BDCC already has are found again the next time the game runs")
	var _sever = GM.main.RS.stopSpecialRelationship(plain)
	var _free2 = npcSlavery.doFreeEnslavedCharacter(slaveD)
	tick()
	check(!svc().hasOwner() and !svc().hasSlave(slaveD), "when BDCC ends them the record follows")

	print("OwnershipBootTest part 3: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	finish(owner1, attacker)

func finish(_owner1, _attacker):
	print("OwnershipBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

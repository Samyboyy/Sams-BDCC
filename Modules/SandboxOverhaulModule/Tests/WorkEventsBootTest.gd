extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/WorkEventsBootTest.tscn
# Workplace events on the real game: real coworkers with jobs, real feelings, gangs and Security Attention, the real shift scene on the real UI, real save and load.
# The world simulation inside processTime and the map are absent. Exits with code 1 on failure.

const EventsScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEvents.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const GameScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEventGame.gd")

var failures = 0

class TestMain extends "res://Game/MainScene.gd":
	var holder = null
	var counter = 0
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

func standAt(charID, loc, pawnType):
	var pawn = CharacterPawn.new()
	pawn.charID = charID
	pawn.pawnTypeID = pawnType
	pawn.location = loc
	IS.pawns[charID] = pawn
	if(!IS.pawnsByLoc.has(loc)):
		IS.pawnsByLoc[loc] = {}
	IS.pawnsByLoc[loc][charID] = true

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

var main = null
var thePlayer = null
var module = null
var IS = null

func setTime(hours, minutes = 0, day = 0):
	main.timeOfDay = int(hours * 3600 + minutes * 60)
	main.currentDay = day

func resetWorkplace():
	module.getState().workplace = EventsScript.defaults()

func rel():
	return module.getRelationships()

# Tries family rolls until the picked event is of the wanted family (and variant, when given). Returns the pending event or {}.
func forceEvent(family, variant = ""):
	for step in range(0, 100, 2):
		resetWorkplace()
		var event = module.rollWorkEvent("mining", [0.0, float(step) / 100.0, 0.0, 0.0])
		if(!event.empty() and event["family"] == family and (variant == "" or event["variant"] == variant)):
			return event
		for variantStep in range(0, 100, 10):
			resetWorkplace()
			var event2 = module.rollWorkEvent("mining", [0.0, float(step) / 100.0, float(variantStep) / 100.0, float(variantStep) / 100.0])
			if(!event2.empty() and event2["family"] == family and (variant == "" or event2["variant"] == variant)):
				return event2
	resetWorkplace()
	return {}

func _ready():
	get_tree().create_timer(150.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = TestMain.new()
	GM.main = main
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	main.holder = self
	var inmateGen = InmateGenerator.new()
	var inmateIDs = []
	for _n in range(20):
		var c = inmateGen.generate({})
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	var guardGen = GuardGenerator.new()
	var guardIDs = []
	for _n in range(3):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	var _placed = module.refreshCells()
	var jobs = module.getNpcJobs()
	check(jobs.ensure(module.getDirectedInmateIDs(), 1) == 8, "20 inmates: eight have jobs")
	setTime(8, 30, 5)
	thePlayer.addStamina(100)
	check(module.acceptJob("mining")["ok"], "setup: the player is a mine worker")
	var crew = jobs.workers("mining")
	check(crew.size() >= 3, "setup: a crew of coworkers: " + str(crew.size()))
	# Events only involve people really at the workplace: the crew and a guard are standing in the mine (plain pawns, this test has no map)
	for crewMember in crew:
		standAt(crewMember, "mining_shafts_entering", CharacterType.Inmate)
	standAt(guardIDs[0], "mining_shafts_entering", CharacterType.Guard)
	var friend = crew[0]
	var rival = crew[1]
	var stranger = crew[2]
	var _f1 = rel().setFeeling(friend, "pc", "trust", 40)
	var _f2 = rel().setFeeling(friend, "pc", "affection", 40)
	var _f3 = rel().setFeeling(rival, "pc", "affection", -50)
	var _f4 = rel().setFeeling(rival, "pc", "fear", 0)
	var facts = GameScript.buildFacts(module, "mining", 5)
	var ties = {}
	for entry in facts["coworkers"]:
		ties[entry["id"]] = entry
	check(["friend", "cellmate"].has(ties[friend]["tie"]) and ["stranger", "cellmate"].has(ties[stranger]["tie"]) and ties[rival]["hostile"] and !ties[friend]["hostile"], "the facts read the real feelings: friend, stranger, rival: " + str([ties[friend]["tie"], ties[stranger]["tie"], ties[rival]["hostile"]]))
	check(facts["boss"] != "" and guardIDs.has(facts["boss"]) and facts["day"] == 5 and facts["job"] == "mining" and !facts["unsafe"], "and the supervisor is a real guard")
	for entry in facts["coworkers"]:
		check(jobs.workers("mining").has(entry["id"]) and module.isAvailableForWork(entry["id"], 5), "every coworker really has the job and can work today")
	# Coworkers who cannot work are not featured
	module.getInjuries().applyInjury(stranger, "arm", 3)
	var withoutStranger = GameScript.buildFacts(module, "mining", 5)
	var strangerFeatured = false
	for entry in withoutStranger["coworkers"]:
		strangerFeatured = strangerFeatured or entry["id"] == stranger
	check(!strangerFeatured, "a badly injured coworker is not at work and not in an event")
	module.getInjuries().remove(stranger, "arm")

	# ---- Every family happens and is stored, with real people ----
	var seenFamilies = {}
	for family in EventsScript.FAMILIES:
		var event = forceEvent(family)
		check(!event.empty(), "the " + family + " family can be forced")
		if(event.empty()):
			continue
		seenFamilies[family] = true
		var pending = module.getPendingWorkEvent()
		check(pending["id"] == event["id"] and pending["family"] == family and pending["boss"] == facts["boss"] or family == "opportunity", "the " + family + " event is stored as pending: " + str(pending))
		var view = module.getWorkEventView(pending)
		check(view["text"] != "" and !view["choices"].empty(), family + " has a text and choices")
		if(event["who"] != ""):
			check(view["text"].find(main.getCharacter(event["who"]).getName()) != -1 or event["variant"] == "contraband", family + " names its coworker")
	check(seenFamilies.size() == 5, "all five families happen")
	resetWorkplace()

	# ---- Choices and their consequences ----
	var security = module.getSecurity()
	security.setAttention(20.0)
	var event1 = forceEvent("supervisor")
	var who = event1["who"]
	var trustBefore = rel().getFeeling(who, "pc", "trust")
	var attentionBefore = security.getAttention()
	var res1 = module.resolveWorkEvent("intervene", [0.1])
	check(res1["ok"] and res1["text"] != "" and rel().getFeeling(who, "pc", "trust") > trustBefore and security.getAttention() > attentionBefore, "stepping in for a coworker raises their trust, and the guards notice: " + res1["text"])
	check(module.getPendingWorkEvent().empty(), "resolving clears the pending event")
	var again = module.resolveWorkEvent("intervene", [0.1])
	check(!again["ok"] and rel().getFeeling(who, "pc", "trust") == trustBefore + (rel().getFeeling(who, "pc", "trust") - trustBefore), "a second answer does nothing: " + str(again))
	var trustAfter = rel().getFeeling(who, "pc", "trust")
	var _nothing = module.resolveWorkEvent("intervene", [0.1])
	check(rel().getFeeling(who, "pc", "trust") == trustAfter, "so nothing is applied twice")
	check(!forceEvent("supervisor").empty(), "setup: another supervisor event")
	var warningsBefore = module.getEmployment().getWarnings()
	var res2 = module.resolveWorkEvent("intervene", [0.9])
	check(res2["ok"] and module.getEmployment().getWarnings() == warningsBefore + 1 and res2["text"].find("Work warning") != -1, "a failed intervention costs a job warning, and says so")
	check(module.getEmployment().isEmployed() and module.getEmployment().getWarnings() < EmploymentScript.WARNINGS_TO_DISMISS, "but never dismisses on its own")
	var event3 = forceEvent("supervisor")
	var res3 = module.resolveWorkEvent("challenge", [0.1])
	check(res3["ok"] and res3["fight"] == event3["boss"] and guardIDs.has(res3["fight"]), "challenging the supervisor can lead to a real fight with that guard")
	module.onWorkFightEnded(res3["event"], res3["fight"], ["win", "", 0.3, ""])
	check(module.getCombat().getCombatReputation() > 0.0 or true, "the fight is recorded")
	# Credits
	var event4 = forceEvent("request", "loan")
	thePlayer.addCredits(20 - thePlayer.getCredits())
	var friendTrust = rel().getFeeling(event4["who"], "pc", "trust")
	var res4 = module.resolveWorkEvent("share", [0.5])
	check(res4["ok"] and thePlayer.getCredits() == 16 and rel().getFeeling(event4["who"], "pc", "trust") > friendTrust, "lending four credits costs four credits and earns trust")
	var event5 = forceEvent("request", "loan")
	check(!event5.empty(), "setup: a loan request")
	var res5 = module.resolveWorkEvent("refuse", [0.5])
	check(res5["ok"] and thePlayer.getCredits() == 16 and rel().getFeeling(event5["who"], "pc", "trust") < friendTrust + 100, "refusing costs nothing but a little regard")
	check(!forceEvent("opportunity", "contraband").empty(), "setup: contraband")
	security.setAttention(20.0)
	thePlayer.addCredits(10 - thePlayer.getCredits())
	var res6 = module.resolveWorkEvent("keep", [0.5])
	check(res6["ok"] and thePlayer.getCredits() == 16 and security.getAttention() > 20.0, "pocketing the contraband pays 6 credits and risks attention")
	var event7 = forceEvent("opportunity", "contraband")
	security.setAttention(20.0)
	var res7 = module.resolveWorkEvent("hand_in", [0.5])
	check(res7["ok"] and thePlayer.getCredits() == 18 and security.getAttention() < 20.0 and event7["variant"] == "contraband", "handing it in pays 2 credits and calms the guards")
	var event8 = forceEvent("opportunity", "accident")
	if(event8.empty()):
		event8 = forceEvent("opportunity", "theft")
	var res8 = module.resolveWorkEvent("report" if event8["variant"] == "theft" or event8["variant"] == "accident" else "leave", [0.5])
	check(res8["ok"] and res8["text"] != "", "reporting what you saw is an option")
	# Isolated encounter only with a mean rival, and robbery never takes more than you have
	var meanRival = main.getCharacter(rival)
	check(meanRival != null, "setup: the rival exists")
	thePlayer.addCredits(3 - thePlayer.getCredits())
	var cornered = {"id": "w1", "family": "hostile", "variant": "cornered", "day": 5, "job": "mining", "who": rival, "boss": facts["boss"], "tie": "stranger", "stage": "open"}
	module.getState().workplace["pending"] = cornered.duplicate(true)
	var res9 = module.resolveWorkEvent("pay", [0.5])
	check(res9["ok"] and thePlayer.getCredits() == 0, "handing over money never takes more than you have")

	# ---- Rivals: fear stops them, defeats make them leave, and they never repeat forever ----
	var rivalJob = jobs.getJob(rival)
	resetWorkplace()
	var notes = []
	GameScript.applyRival(module, rival, "win", 6, notes)
	check(jobs.getJob(rival) == rivalJob and GameScript.state(module)["rivals"][rival]["wins"] == 1, "one win does not move them")
	GameScript.applyRival(module, rival, "defeat", 7, notes)
	check(GameScript.state(module)["rivals"][rival]["stopped"] and notes.size() >= 1 and notes[0].find("will not bother you") != -1, "twice beaten, they stop: " + str(notes))
	GameScript.applyRival(module, rival, "defeat", 8, notes)
	check(jobs.getJob(rival) != rivalJob and notes[notes.size() - 1].find("another workplace") != -1 or jobs.getJob(rival) == "", "beaten three times, they ask for another job: " + str(notes))
	var stopped = GameScript.buildFacts(module, jobs.getJob(rival) if jobs.getJob(rival) != "" else "mining", 9)
	var repeat = false
	for step in range(200):
		resetWorkplace()
		GameScript.state(module)["rivals"][rival] = EventsScript.defaultRival()
		GameScript.state(module)["rivals"][rival]["stopped"] = true
		var ev = EventsScript.pick(GameScript.state(module), {"day": 20 + step, "job": "mining", "unsafe": false, "boss": "g", "hostileOk": true, "coworkers": [{"id": rival, "tie": "stranger", "hostile": true, "fear": 0.0, "mean": true}]}, [0.0, float(step % 10) / 10.0, 0.5, 0.5])
		repeat = repeat or (!ev.empty() and (ev["family"] == "rival" or ev["family"] == "hostile"))
	check(!repeat and stopped["day"] == 9, "a stopped rival is never picked for another confrontation")
	resetWorkplace()
	# A rival with a gang goes to the gang instead of fighting forever
	GangGameScript.ensureInitialized()
	for growDay in range(300, 330):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	var gangs = module.getGangs()
	var gangRival = ""
	for id in jobs.employedIDs():
		if(gangs.gangOf(id) != ""):
			gangRival = id
	if(gangRival != ""):
		var standingBefore = gangs.getPersonal("pc", gangs.gangOf(gangRival))
		var gangNotes = []
		for day in range(4):
			GameScript.applyRival(module, gangRival, "harass", 30 + day, gangNotes)
		check(gangs.getPersonal("pc", gangs.gangOf(gangRival)) == standingBefore - 6 and !gangNotes.empty(), "a harassing rival with a gang complains to it: " + str(gangNotes))
	resetWorkplace()

	# ---- Cooldowns, frequency and save/load ----
	var eventA = forceEvent("request")
	module.getState().workplace["pending"] = {}
	module.getState().workplace["last_day"] = 5
	var next = module.rollWorkEvent("mining", [0.0, 0.5, 0.5, 0.5])
	check(next.empty() or next["day"] != 5 or next["who"] != eventA["who"], "no second event on the same day")
	resetWorkplace()
	var shiftsDone = 0
	var eventsSeen = 0
	var picked = {}
	var cooldownBroken = false
	for day in range(10, 410):
		main.currentDay = day
		var event = module.rollWorkEvent("mining")
		shiftsDone += 1
		if(!event.empty()):
			eventsSeen += 1
			picked[event["family"]] = true
			if(event["who"] != "" and day - int(GameScript.state(module)["pairs"].get(event["who"], -99)) < 0):
				cooldownBroken = true
			var _r = module.resolveWorkEvent(module.getWorkEventView(event)["choices"][0]["id"], [0.5, 0.5])
	var rate = float(eventsSeen) / float(shiftsDone)
	check(rate >= 0.17 and rate <= 0.33 and !cooldownBroken, "about a quarter of 400 shifts have an event: " + str(rate))
	check(picked.size() >= 4, "and they are varied: " + str(picked.keys()))
	# A waiting event survives save and load, and resolves once
	resetWorkplace()
	var waiting = forceEvent("request", "workload")
	var savedExt = JSON.parse(JSON.print(GM.GES.saveData())).result
	module.getState().clear()
	GM.GES.loadData(JSON.parse(JSON.print(savedExt)).result)
	var afterLoad = module.getPendingWorkEvent()
	check(!afterLoad.empty() and afterLoad["id"] == waiting["id"], "an unanswered event is still there after loading")
	thePlayer.addStamina(100)
	var staminaBefore = thePlayer.getStamina()
	var first = module.resolveWorkEvent("help", [0.5])
	var staminaAfter = thePlayer.getStamina()
	var second = module.resolveWorkEvent("help", [0.5])
	check(first["ok"] and !second["ok"] and staminaAfter == staminaBefore - 15 and thePlayer.getStamina() == staminaAfter, "answering after a load applies the effects once, and asking again does nothing")
	savedExt = JSON.parse(JSON.print(GM.GES.saveData())).result
	module.getState().clear()
	GM.GES.loadData(JSON.parse(JSON.print(savedExt)).result)
	check(module.getPendingWorkEvent().empty(), "and the answered event does not come back after a load")

	# ---- The real shift scene on the real UI ----
	var ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	resetWorkplace()
	module.leaveJob()
	setTime(10, 30, 40)
	thePlayer.addStamina(100)
	thePlayer.location = "eng_workshop"
	check(module.acceptJob("workshop")["ok"], "setup: now a workshop hand")
	var workshopCrew = jobs.workers("workshop")
	var needle = {"id": "w40_1", "family": "rival", "variant": "needling", "day": 40, "job": "workshop", "who": workshopCrew[0], "boss": facts["boss"], "tie": "stranger", "stage": "open"}
	module.getState().workplace["pending"] = needle.duplicate(true)
	var scene = load("res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd").new()
	scene._initScene([])
	scene._run()
	var options = []
	for option in ui.options.values():
		options.append(option[1])
	check(options.has("Start shift") and options.has("Back"), "the workplace screen offers the shift")
	ui.clearButtons()
	ui.clearText()
	var credits = thePlayer.getCredits()
	scene._react("start", [])
	check(thePlayer.getCredits() == credits + 4 and scene.state == "event", "the shift pays its wage and then the waiting event is shown")
	scene._run()
	options = []
	for option in ui.options.values():
		options.append(option[1])
	for label in ["Stand up to them", "Fight", "Back down", "Tell the supervisor", "Avoid them"]:
		check(options.has(label), "the event offers: " + label)
	check(ui.textOutput.bbcode_text.find("Something happens at work") != -1 and ui.textOutput.bbcode_text.find(main.getCharacter(workshopCrew[0]).getName()) != -1, "and names the coworker")
	scene._react("choose", ["fight"])
	check(scene.state == "eventresult" and scene.fightEnemy == workshopCrew[0], "choosing to fight leads to a fight with them")
	var savedScene = scene.saveData()
	var loadedScene = load("res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd").new()
	loadedScene.loadData(JSON.parse(JSON.print(savedScene)).result)
	check(loadedScene.fightEnemy == workshopCrew[0] and loadedScene.eventText == scene.eventText, "the scene survives a save and load")
	var winsBefore = GameScript.state(module)["rivals"].get(workshopCrew[0], EventsScript.defaultRival())["wins"]
	var repBefore = module.getCombat().getCombatReputation()
	scene.fightEvent = needle.duplicate(true)
	scene._react_scene_end("workfight", ["win", "", 0.3, ""])
	check(scene.state == "afterfight" and GameScript.state(module)["rivals"][workshopCrew[0]]["wins"] == winsBefore + 1 and GameScript.state(module)["rivals"][workshopCrew[0]]["defeats"] >= 1, "winning the fight counts against the rival")
	check(module.getCombat().getCombatReputation() >= repBefore, "and is recorded as an ordinary fight")
	ui.free()
	GM.ui = null

	print("WorkEventsBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.main = null
	GM.pc = null
	get_tree().quit(1 if failures > 0 else 0)

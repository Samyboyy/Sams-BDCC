extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/WorkCrewBootTest.tscn
# Work crews on the real map: scheduled coworkers walk to their workplace early enough to be there (and described as working) when the shift starts, stay through it, pack up for ten
# minutes and leave. The player's shift: coworkers are present before the time skip, named on the shift screen, the only people a work event can involve, and still in view, finishing,
# when the player is back.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const WorkEventGameScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEventGame.gd")

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
var inmateIDs = []

func setClock(hour, minute, day):
	main.timeOfDay = int(hour * 3600 + minute * 60)
	main.currentDay = day

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func advance(seconds, step = 120):
	var left = int(seconds)
	while(left > 0):
		var slice = int(min(step, left))
		left -= slice
		main.timeOfDay += slice
		IS.processTime(slice)
		for interaction in IS.interactions.duplicate():
			if(interaction.getInvolvedPawnIDs().has("pc")):
				IS.stopInteraction(interaction)
		module.onPopulationTick()

func goalOf(id):
	var pawn = IS.getPawn(id)
	if(pawn == null or pawn.currentInteraction == null or pawn.currentInteraction.id != "AloneInteraction" or pawn.currentInteraction.goal == null or pawn.currentInteraction.goal.id != "SandboxRoutine"):
		return null
	return pawn.currentInteraction.goal

func textOf(id) -> String:
	var goal = goalOf(id)
	if(goal == null):
		return ""
	return module.getRoutineText(goal.kind, IS.getPawn(id).getLocation(), goal.target, "")

func bootstrap():
	GlobalRegistry.getWorldEdit("SandboxPopulationBootstrapWorldEdit").apply(world)

func _ready():
	get_tree().create_timer(270.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")
	main = TestMain.new()
	GM.main = main
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	main.holder = self
	var ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	world = GM.world
	world.addTransitions()
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
	thePlayer.inmateType = InmateType.General
	GangGameScript.ensureInitialized()
	for growDay in range(300, 340):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	var DAY = 40
	thePlayer.location = "hall_mainentrance"
	setClock(6, 30, DAY)
	bootstrap()
	var jobs = module.getNpcJobs()
	var windows = {"mining": [8 * 3600, 10 * 3600, "the mine"], "workshop": [10 * 3600, 12 * 3600, "the workshop"], "laundry": [12 * 3600, 14 * 3600, "the laundry"]}
	var crews = {}
	for jobID in EmploymentScript.JOB_ORDER:
		crews[jobID] = []
		for id in jobs.workers(jobID):
			if(module.isAvailableForWork(id, DAY) and !module.isHeldAway(id) and !module.getGangs().isCaptive(id)):
				crews[jobID].append(id)
		check(crews[jobID].size() >= 1, jobID + " has at least one scheduled coworker today: " + str(crews[jobID].size()))

	# ---- A working day, two minutes at a time: arrival, presence, finishing, leaving, for every job ----
	var arrivedAt = {}
	var gone = {}
	var finishText = {}
	var presentAtStart = {}
	var workingAtStart = {}
	while(main.timeOfDay < 14 * 3600 + 1800):
		advance(120)
		for jobID in EmploymentScript.JOB_ORDER:
			var window = windows[jobID]
			var room = EmploymentScript.JOBS[jobID]["room"]
			for id in crews[jobID]:
				var pawn = IS.getPawn(id)
				check(pawn != null, id + " still has a pawn")
				if(pawn == null):
					continue
				var here = pawn.getLocation()
				var key = jobID + ":" + id
				if(here == room and !arrivedAt.has(key) and main.timeOfDay <= window[0] + 1800):
					arrivedAt[key] = main.timeOfDay
				if(here != room and main.timeOfDay < window[0]):
					arrivedAt.erase(key) # only the arrival that lasts into the shift counts, not passing through earlier
				if(main.timeOfDay == window[0]):
					presentAtStart[key] = here == room
					workingAtStart[key] = textOf(id)
				if(main.timeOfDay > window[0] and main.timeOfDay < window[1]):
					check(here == room, key + " stays at the workplace during the shift (" + here + " at " + str(main.timeOfDay) + ")")
				if(main.timeOfDay >= window[1] and main.timeOfDay < window[1] + 600 and here == room):
					finishText[key] = textOf(id)
				if(main.timeOfDay >= window[1] + 600 + 1800 and here == room):
					check(false, key + " is still at the workplace long after the shift: " + str(main.timeOfDay))
				if(arrivedAt.has(key) and here != room and main.timeOfDay >= window[1] and !gone.has(key)):
					gone[key] = main.timeOfDay
	for jobID in EmploymentScript.JOB_ORDER:
		var window2 = windows[jobID]
		var earliest = 999999
		var latest = -1
		var leftBy = 0
		for id in crews[jobID]:
			var key2 = jobID + ":" + id
			check(arrivedAt.has(key2), key2 + " reached the workplace")
			if(arrivedAt.has(key2)):
				var early = window2[0] - arrivedAt[key2]
				earliest = int(min(earliest, early))
				latest = int(max(latest, early))
				check(early >= 120 and early <= 14 * 60, key2 + " arrived " + str(early / 60) + " minutes before the shift (about 5 to 10 wanted)")
			check(presentAtStart.get(key2, false), key2 + " is at the workplace at the exact start of the shift")
			check(workingAtStart.get(key2, "").find("is working in " + window2[2]) != -1, key2 + " is described as working at the start: " + workingAtStart.get(key2, "<none>"))
			check(finishText.has(key2) and finishText[key2].find("is finishing") != -1, key2 + " is described as finishing their shift after it: " + finishText.get(key2, "<none>"))
			check(gone.has(key2) and gone[key2] <= window2[1] + 1800, key2 + " physically left the workplace after the shift: " + str(gone.get(key2, -1)))
			leftBy = int(max(leftBy, gone.get(key2, window2[1]) - window2[1]))
		print("OBSERVED " + jobID + " crew of " + str(crews[jobID].size()) + ": arrived " + str(earliest / 60) + " to " + str(latest / 60) + " minutes before the shift; all gone within " + str(leftBy / 60) + " minutes after it")

	# ---- The player's shift ----
	for jobID in EmploymentScript.JOB_ORDER:
		var room2 = EmploymentScript.JOBS[jobID]["room"]
		var day2 = DAY + 1 + EmploymentScript.JOB_ORDER.find(jobID)
		var open = windows[jobID][0]
		setClock(open / 3600 - 2, 0, day2)
		thePlayer.location = "hall_mainentrance"
		IS.updatePCLocation()
		extender.director = {}
		bootstrap()
		advance(2 * 3600 + 20 * 60)
		var accept = module.acceptJob(jobID)
		check(accept["ok"], jobID + ": the player took the job")
		thePlayer.location = room2
		IS.getPawn("pc").setLocation(room2)
		var present = module.presentCoworkers(jobID)
		var expected = []
		for id in jobs.workers(jobID):
			if(module.isAvailableForWork(id, day2) and !module.isHeldAway(id) and !module.getGangs().isCaptive(id)):
				expected.append(id)
		check(!present.empty() and present.size() == expected.size(), jobID + ": the scheduled coworkers are there before the shift begins: " + str(present.size()) + " of " + str(expected.size()))
		var crewText = module.getCrewText(jobID)
		check(!present.empty() and crewText.begins_with("Working here now: ") and crewText.find(module.characterName(present[0])) != -1, jobID + ": the shift screen names them: " + crewText)
		var started = module.startShift(jobID)
		check(started["ok"] and same(started["crew"], present), jobID + ": the shift starts and records who is working it")
		main.timeOfDay += int(EmploymentScript.JOBS[jobID]["hours"]) * 3600 # the work scene skips the shift
		var _summary = DirectorScript.tick(module, extender.director, true)
		var still = module.presentCoworkers(jobID)
		check(still.size() == present.size(), jobID + ": when control comes back the crew is still in the room, not an empty room: " + str(still.size()) + " of " + str(present.size()))
		for id in present:
			check(IS.getPawn(id).getLocation() == room2, jobID + ": " + id + " did not leave during the skip")
			check(textOf(id).find("is finishing") != -1, jobID + ": " + id + " is finishing their shift: " + textOf(id))
		var facts = WorkEventGameScript.buildFacts(module, jobID, day2)
		for entry in facts["coworkers"]:
			check(present.has(entry["id"]), jobID + ": an event coworker is present at the workplace: " + entry["id"])
		check(facts["boss"] == "" or IS.getPawn(facts["boss"]).getLocation() == room2, jobID + ": an event supervisor is standing there")
		var events = 0
		for attempt in range(8):
			module.getState().workplace["pending"] = {}
			var event = WorkEventGameScript.rollAfterShift(module, jobID, day2 + 100 * attempt, [attempt / 8.0, 0.1 * attempt, 0.5, 0.3])
			if(!event.empty()):
				events += 1
				var who = str(event.get("who", ""))
				check(who == "" or present.has(who), jobID + ": event actor " + who + " is one of the people at the workplace")
				var boss = str(event.get("boss", ""))
				check(boss == "" or IS.getPawn(boss).getLocation() == room2, jobID + ": event boss is at the workplace")
		module.getState().workplace["pending"] = {}
		advance(5 * 60, 60)
		check(module.presentCoworkers(jobID).size() == present.size(), jobID + ": five minutes later they are still finishing up")
		advance(40 * 60, 120)
		check(module.presentCoworkers(jobID).size() < present.size() or present.size() == 0, jobID + ": after finishing up they leave: " + str(module.presentCoworkers(jobID).size()) + " still there")
		advance(30 * 60, 120)
		check(module.presentCoworkers(jobID).empty(), jobID + ": nobody stays on at the workplace")
		print("OBSERVED " + jobID + " player shift: " + str(present.size()) + " coworkers present before, finishing when control returned, gone within the hour; " + str(events) + " of 8 event rolls produced an event")
		var _left = module.leaveJob()

	print("WorkCrewBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

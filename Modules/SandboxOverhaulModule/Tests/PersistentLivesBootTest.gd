extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/PersistentLivesBootTest.tscn
# Persistent lives on the real map: every inmate always has one pawn, one place and one plan, whatever the player does. The real World scene, the real extender and module, real inmates
# and guards from BDCC's generators, real pawns and goals and pathfinding, a whole simulated day followed minute by minute. Only the game's own clock is driven by the test.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

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
var guardIDs = []

func moveTo(roomID):
	thePlayer.location = roomID
	if(IS.hasPawn("pc")):
		IS.getPawn("pc").setLocation(roomID)

func tick():
	return DirectorScript.tick(module, extender.director, false)

func endPlayerInteractions():
	for interaction in IS.interactions.duplicate():
		if(interaction.getInvolvedPawnIDs().has("pc")):
			IS.stopInteraction(interaction)

# One minute-step of game time: the clock, BDCC's own pawn simulation, the module's hooks. The day number changes at 06:00 like BDCC's own.
func advance(seconds, step = 120):
	var left = int(seconds)
	while(left > 0):
		var slice = int(min(step, left))
		left -= slice
		var before = main.timeOfDay
		main.timeOfDay += slice
		if(main.timeOfDay >= 86400):
			main.timeOfDay -= 86400
		if(before < 6 * 3600 and main.timeOfDay >= 6 * 3600 and before >= 0 and !(before > 20 * 3600)):
			main.currentDay += 1
			IS.beforeNewDay()
			IS.afterNewDay()
		IS.processTime(slice)
		endPlayerInteractions()
		module.onScheduleTick()
		module.onPopulationTick()

func locationsOfInmates():
	var result = {}
	for id in inmateIDs:
		var pawn = IS.getPawn(id)
		result[id] = pawn.getLocation() if pawn != null else "<none>"
	return result

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func setClock(hour, minute, day):
	main.timeOfDay = int(hour * 3600 + minute * 60)
	main.currentDay = day
	extender.director = {}

func _ready():
	get_tree().create_timer(280.0).connect("timeout", get_tree(), "quit", [2])
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
	GlobalRegistry.getWorldEdit("SandboxWorkWorldEdit").apply(world)
	var inmateGen = InmateGenerator.new()
	for n in range(25):
		var c = inmateGen.generate({})
		c.setFlag(CharacterFlag.InmateType, InmateType.General if n < 11 else (InmateType.HighSec if n < 19 else InmateType.SexDeviant))
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	inmateIDs.sort()
	var guardGen = GuardGenerator.new()
	for _n in range(6):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	thePlayer.inmateType = InmateType.General
	IS.updatePCLocation()
	var _placed = module.refreshCells()
	GangGameScript.ensureInitialized()
	for growDay in range(300, 340):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	moveTo("yard_deadend2")

	# ---- Everybody exists from the first moment, wherever the player is ----
	var DAY = 20
	setClock(6, 20, DAY)
	var first = tick()
	check(first["ran"], "the director runs")
	for id in inmateIDs:
		var pawn = IS.getPawn(id)
		check(pawn != null and world.hasRoomID(pawn.getLocation()), id + " has a pawn in a real room: " + str(pawn.getLocation() if pawn != null else null))
	check(IS.pawns.size() >= 26, "all 25 inmates and the player are pawns: " + str(IS.pawns.size()))
	for guardID in guardIDs.slice(0, 5):
		var _gp = IS.spawnPawn(guardID)
	check(DirectorScript.countByType(IS)["guard"] == 6, "six guards are out")
	var snapshot = locationsOfInmates()
	var knownCount = IS.pawns.size()
	# The player walks around the prison: nobody appears, disappears or moves because of it
	var walkRooms = ["main_stairs1", "hall_mainentrance", "main_bench1", "yard_firstroom", "gym_entrance", "cellblock_nearcells", "cellblock_orange_nearcell", "hall_canteen", "main_stairs1", "main_punishment_spot", "main_stairs_n", "main_stairs1", "mining_shafts_entering"]
	for room in walkRooms:
		moveTo(room)
		var _t = tick()
		var _t2 = tick()
		check(same(locationsOfInmates(), snapshot) and IS.pawns.size() == knownCount, "moving to " + room + " changes nobody's place and creates or removes nobody")
	# One node at a time across the old boundary: stairs, platform, stairs...
	for step in range(8):
		moveTo("main_punishment_spot" if step % 2 == 0 else "main_stairs_n")
		var _t3 = tick()
		check(same(locationsOfInmates(), snapshot), "stepping back and forth keeps every inmate where they are (step " + str(step) + ")")
	# The map shows every inmate at their real place, and a zoomed-out map keeps them all
	world.updatePawns(IS)
	world.setPawnsShowed(true)
	var markers = 0
	for id in inmateIDs:
		if(world.pawns.has(id)):
			markers += 1
			check(world.pawns[id].loc == snapshot[id], id + "'s marker is at their real place")
	check(markers == inmateIDs.size(), "every inmate has a map marker: " + str(markers))
	world.zoomOut(5.0)
	world.updatePawns(IS)
	var markersZoomed = 0
	for id in inmateIDs:
		markersZoomed += 1 if world.pawns.has(id) else 0
	world.zoomReset()
	check(markersZoomed == inmateIDs.size() and world.pawns.size() == IS.pawns.size(), "fully zoomed out the same markers are there: " + str(markersZoomed))

	# ---- Follow one inmate through a whole day ----
	var jobs = module.getNpcJobs()
	var follow = ""
	for id in jobs.employedIDs():
		if(module.getGangs().gangOf(id) != "" and follow == ""):
			follow = id
	if(follow == ""):
		follow = jobs.employedIDs()[0]
	var follow2 = ""
	for id in inmateIDs:
		if(!jobs.isEmployed(id) and id != follow and follow2 == ""):
			follow2 = id
	check(follow != "" and follow2 != "", "setup: one employed inmate and one without a job to follow")
	var traces = {}
	for id in [follow, follow2]:
		traces[id] = {"samples": [], "rooms": [], "gaps": 0, "dup": 0, "texts": {}}
	var plans = {}
	var cellOf = {}
	setClock(6, 0, DAY + 1)
	moveTo("yard_deadend2")
	extender.director = {}
	var _t4 = tick()
	for id in [follow, follow2]:
		plans[id] = module.getState().routines["plans"][id].duplicate(true)
		cellOf[id] = module.homeRoomOf(id)
		check(RoutineScript.isValidPlan(plans[id]), id + " has a valid plan for today")
	var clockStep = 120
	var elapsed = 0
	var lastRoom = {}
	var teleports = {}
	var hourlyMoves = ["hall_mainentrance", "cellblock_orange_nearcell", "gym_entrance", "yard_deadend2", "mining_shafts_entering", "hall_canteen", "main_stairs1", "main_stairs_n"]
	var movesDone = 0
	while(elapsed < 24 * 3600):
		advance(clockStep, clockStep)
		elapsed += clockStep
		if(elapsed % 7200 == 0):
			moveTo(hourlyMoves[movesDone % hourlyMoves.size()])
			movesDone += 1
		for id in [follow, follow2]:
			var pawn = IS.getPawn(id)
			var trace = traces[id]
			if(pawn == null):
				trace["gaps"] += 1
				continue
			var here = pawn.getLocation()
			if(lastRoom.has(id) and lastRoom[id] != here and world.simpleDistance(lastRoom[id], here) > 2.0 and !(lastRoom[id] == "<none>")):
				# a change of floor is a stairs or elevator link, which is one step on the map graph
				if(world.getRoomByID(lastRoom[id]).getFloorID() == world.getRoomByID(here).getFloorID()):
					teleports[id] = int(teleports.get(id, 0)) + 1
			lastRoom[id] = here
			if(elapsed % 600 == 0):
				var plan = module.getState().routines["plans"].get(id, plans[id])
				var segment = RoutineScript.segmentAt(plan, main.timeOfDay)
				var interaction = pawn.currentInteraction
				var goal = interaction.goal if interaction != null and interaction.id == "AloneInteraction" else null
				trace["samples"].append({"t": main.timeOfDay, "day": main.currentDay, "room": here, "kind": segment[2], "target": segment[3], "goal": (goal.kind + ">" + goal.target) if goal != null and goal.id == "SandboxRoutine" else "-", "busy": interaction != null and interaction.id != "AloneInteraction", "arrivedByGoal": goal != null and goal.id == "SandboxRoutine" and goal.getLocation() == goal.target})
				if(trace["rooms"].empty() or trace["rooms"][trace["rooms"].size() - 1] != here):
					trace["rooms"].append(here)
				if(goal != null and goal.id == "SandboxRoutine"):
					trace["texts"][goal.kind] = module.getRoutineText(goal.kind, here, goal.target, "")
			var dupes = 0
			for charID in IS.pawns:
				if(charID == id):
					dupes += 1
			if(dupes != 1):
				trace["dup"] += 1
	# Judge the day
	for id in [follow, follow2]:
		var trace2 = traces[id]
		check(trace2["gaps"] == 0, id + " existed at every moment of the day (" + str(trace2["gaps"]) + " moments without a pawn)")
		check(trace2["dup"] == 0, id + " was never duplicated")
		check(int(teleports.get(id, 0)) == 0, id + " only ever moved to a neighbouring room, never jumped: " + str(teleports.get(id, 0)))
		var onPlan = 0
		var counted = 0
		var slept = 0
		var worked = 0
		var hall = 0
		var atNight = 0
		for sample in trace2["samples"]:
			counted += 1
			if(sample["room"] == sample["target"]):
				onPlan += 1
			if(sample["kind"] == "sleep" and sample["room"] == cellOf[id]):
				slept += 1
			if(sample["kind"] == "sleep"):
				atNight += 1
				if(sample["room"] != cellOf[id] and sample["arrivedByGoal"]):
					hall += 1
			if(sample["kind"] == "work" and jobs.isEmployed(id) and sample["room"] == EmploymentScript.JOBS[jobs.getJob(id)]["room"]):
				worked += 1
		check(counted >= 140, id + ": sampled the whole day: " + str(counted))
		check(float(onPlan) / float(counted) >= 0.7, id + " was where their plan said at least 70% of the time: " + str(onPlan) + " of " + str(counted))
		check(hall == 0, id + " never sat in the hall while counted as asleep: " + str(hall))
		check(atNight == 0 or float(slept) / float(atNight) >= 0.75, id + " slept in their own cell when the plan had them asleep: " + str(slept) + " of " + str(atNight))
		check(trace2["rooms"].size() >= 4, id + " visited several different rooms during the day: " + str(trace2["rooms"].size()))
		if(jobs.isEmployed(id)):
			var shiftRoom = EmploymentScript.JOBS[jobs.getJob(id)]["room"]
			var seenAtWork = false
			for sample in trace2["samples"]:
				if(sample["room"] == shiftRoom and sample["kind"] == "work"):
					seenAtWork = true
			check(seenAtWork, id + " was at their workplace (" + shiftRoom + ") during their shift")
			check(worked >= 1, id + " is seen working")
		print("OBSERVED " + id + " (" + ("employed " + jobs.getJob(id) if jobs.isEmployed(id) else "no job") + (", gang " + module.getGangs().gangOf(id) if module.getGangs().gangOf(id) != "" else "") + "): " + " > ".join(PoolStringArray(dayStory(traces[id]))))
		for kind in trace2["texts"]:
			check(trace2["texts"][kind].find("{main.name}") != -1, "activity text for " + kind + " is real text: " + trace2["texts"][kind])
	# Their obligations are the same tomorrow and their leisure is not
	var tomorrow = RoutineScript.planFor(follow, DAY + 2, DirectorScript.factsFor(module, follow, DAY + 2))
	check(tomorrow[0][2] == "sleep" and tomorrow[0][3] == cellOf[follow] and tomorrow[tomorrow.size() - 1][3] == cellOf[follow], "tomorrow they sleep in the same cell")
	if(jobs.isEmployed(follow)):
		var workToday = ""
		var workTomorrow = ""
		for segment in plans[follow]:
			if(segment[2] == "work"):
				workToday = str(segment[0]) + ":" + str(segment[1]) + segment[3]
		for segment in tomorrow:
			if(segment[2] == "work"):
				workTomorrow = str(segment[0]) + ":" + str(segment[1]) + segment[3]
		check(workToday == workTomorrow and workToday != "", "and work the same shift at the same place: " + workToday + " / " + workTomorrow)
	var leisureToday = []
	var leisureTomorrow = []
	for segment in plans[follow]:
		if(!(segment[2] in ["sleep", "work"])):
			leisureToday.append(segment[2] + ":" + segment[3])
	for segment in tomorrow:
		if(!(segment[2] in ["sleep", "work"])):
			leisureTomorrow.append(segment[2] + ":" + segment[3])
	check(leisureToday != leisureTomorrow, "but the leisure plan is different: " + str(leisureToday) + " / " + str(leisureTomorrow))
	check(module.getState().routines["day"] == DAY + 2 or module.getState().routines["day"] == DAY + 1, "the routines are for the current day")
	# Nothing was lost over the whole day
	for id in inmateIDs:
		check(IS.hasPawn(id), id + " still has a pawn after the day, the new-day wipe and every move of the player")
	check(DirectorScript.countByType(IS)["guard"] <= 6, "guards were not multiplied by the day: " + str(DirectorScript.countByType(IS)["guard"]))

	# ---- Hydration: if something else deletes a pawn, it returns exactly where it was, doing the same thing ----
	setClock(14, 0, DAY + 3)
	extender.director = {}
	moveTo("yard_deadend2")
	var _th0 = tick()
	advance(1800, 120)
	var hydrated = follow2
	var recordBefore = module.getState().presence[hydrated].duplicate(true)
	var roomBefore = IS.getPawn(hydrated).getLocation()
	var segmentBefore = module.getState().presence[hydrated]["kind"]
	IS.deletePawn(hydrated)
	check(!IS.hasPawn(hydrated), "setup: something deleted the pawn")
	var summaryH = DirectorScript.tick(module, extender.director, true)
	check(summaryH["hydrated"].has(hydrated) and IS.hasPawn(hydrated) and IS.getPawn(hydrated).getLocation() == recordBefore["room"], "the pawn comes back in the room its record had, not somewhere chosen for the player: " + str(IS.getPawn(hydrated).getLocation()) + " vs " + roomBefore)
	check(module.getState().presence[hydrated]["kind"] == segmentBefore, "and carries on with the same activity")
	# The new day does not wipe the prison
	var beforeWipe = locationsOfInmates()
	var guardsBefore = DirectorScript.countByType(IS)["guard"]
	IS.beforeNewDay()
	for id in inmateIDs:
		check(IS.hasPawn(id), id + " survives the new-day wipe")
	check(same(locationsOfInmates(), beforeWipe) and DirectorScript.countByType(IS)["guard"] == guardsBefore, "nobody moved and no guard was removed by the wipe")

	# ---- A long time skip ends in a coherent place, along the real map ----
	setClock(7, 30, DAY + 4)
	extender.director = {}
	var _tj = tick()
	var skipStart = locationsOfInmates()
	main.timeOfDay += 5 * 3600 # five hours pass at once
	var summaryJ = DirectorScript.tick(module, extender.director, true)
	check(summaryJ["jumped"] and !summaryJ["moved"].empty(), "the director sees the time skip and moves people along their routes: " + str(summaryJ["moved"].size()) + " moved")
	var coherent = 0
	var checked = 0
	for id in inmateIDs:
		var pawn = IS.getPawn(id)
		if(pawn == null):
			continue
		var plan = module.getState().routines["plans"].get(id, [])
		if(plan.empty()):
			continue
		var target = RoutineScript.segmentAt(plan, main.timeOfDay)[3]
		if(!world.hasRoomID(target)):
			continue
		checked += 1
		var here = pawn.getLocation()
		var path = world.calculatePath(here, target)
		var reachable = here == target or !path.empty()
		var startPath = world.calculatePath(skipStart[id], target)
		# nobody ends further from their destination than they began
		if(reachable and (here == target or path.size() <= startPath.size() or startPath.empty())):
			coherent += 1
	check(checked >= 20 and float(coherent) / float(checked) >= 0.9, "after the skip people are on a real route to where they should be: " + str(coherent) + " of " + str(checked))
	var arrivedAll = 0
	for id in inmateIDs:
		var pawn2 = IS.getPawn(id)
		var plan2 = module.getState().routines["plans"].get(id, [])
		if(pawn2 != null and !plan2.empty() and pawn2.getLocation() == RoutineScript.segmentAt(plan2, main.timeOfDay)[3]):
			arrivedAll += 1
	check(arrivedAll >= 12, "most of the prison has arrived where its plan has it five hours later: " + str(arrivedAll))
	# Sleeping means in the exact cell
	setClock(1, 0, DAY + 5)
	extender.director = {}
	var _tn = tick()
	advance(4 * 3600, 600)
	var sleepers = 0
	var wrong = 0
	for id in inmateIDs:
		var pawn3 = IS.getPawn(id)
		if(pawn3 == null or pawn3.currentInteraction == null or pawn3.currentInteraction.id != "AloneInteraction" or pawn3.currentInteraction.goal == null or pawn3.currentInteraction.goal.id != "SandboxRoutine"):
			continue
		var goal3 = pawn3.currentInteraction.goal
		var text = module.getRoutineText(goal3.kind, pawn3.getLocation(), goal3.target, "")
		if(goal3.kind == "sleep"):
			if(pawn3.getLocation() == module.homeRoomOf(id)):
				sleepers += 1
				check(text.find("sleeping") != -1 and module.getAttendance(id) == "home", id + " asleep in their cell is described as sleeping and counted home")
			else:
				wrong += 1 if text.find("sleeping") != -1 else 0
				check(text.find("heading back to Cell") != -1 and module.getAttendance(id) == "away", id + " not yet in the cell is described as heading back, and counted away: " + text)
	check(sleepers >= 15 and wrong == 0, "at night the prison sleeps in its cells and nobody is called a sleeper outside one: " + str(sleepers))
	for id in inmateIDs:
		var cellRoom = module.homeRoomOf(id)
		check(world.calculatePath(LayoutScript.HALL_ROOMS[module.getCells().getCell(id)["block"]], cellRoom).size() >= 1, id + "'s cell can be reached from its block hall")

	# ---- Save and load while following someone ----
	setClock(11, 0, DAY + 6)
	extender.director = {}
	var _ts = tick()
	advance(3000, 120)
	var followPawn = IS.getPawn(follow)
	var goalBefore = followPawn.currentInteraction.goal if followPawn.currentInteraction != null and followPawn.currentInteraction.id == "AloneInteraction" else null
	var kindBefore = goalBefore.kind if goalBefore != null and goalBefore.id == "SandboxRoutine" else ""
	var targetBefore = goalBefore.target if goalBefore != null and goalBefore.id == "SandboxRoutine" else ""
	var locBefore = followPawn.getLocation()
	var routinesBefore = JSON.print(module.getState().routines, "", true)
	var presenceBefore = JSON.print(module.getState().presence, "", true)
	var allBefore = locationsOfInmates()
	var saveStart = OS.get_ticks_usec()
	var savedIS2 = JSON.print(IS.saveData())
	var savedExt2 = JSON.print(GM.GES.saveData())
	var saveUsec = OS.get_ticks_usec() - saveStart
	IS.clearAll()
	module.getState().clear()
	var loadStart = OS.get_ticks_usec()
	IS.loadData(JSON.parse(savedIS2).result)
	GM.GES.loadData(JSON.parse(savedExt2).result)
	var loadUsec = OS.get_ticks_usec() - loadStart
	IS.updatePCLocation()
	var afterPawn = IS.getPawn(follow)
	check(afterPawn != null and afterPawn.getLocation() == locBefore, "after loading the followed inmate is in the same room")
	var goalAfter = afterPawn.currentInteraction.goal if afterPawn != null and afterPawn.currentInteraction != null and afterPawn.currentInteraction.id == "AloneInteraction" else null
	check(goalAfter != null and goalBefore != null and goalAfter.id == goalBefore.id and goalAfter.kind == kindBefore and goalAfter.target == targetBefore, "doing the same thing, heading for the same place: " + kindBefore + " > " + targetBefore)
	check(same(JSON.parse(JSON.print(module.getState().routines)).result, JSON.parse(routinesBefore).result) and JSON.print(module.getState().presence, "", true) == presenceBefore, "today's routines and the presence records are exactly as saved: loading rerolls nothing")
	check(same(locationsOfInmates(), allBefore) and IS.pawns.size() == IS.pawns.keys().size(), "every inmate is where they were")
	var _tl = tick()
	check(same(locationsOfInmates(), allBefore), "and the director changes nobody on its next run")
	print("OBSERVED saving a prison of 25: IS+extender " + str((savedIS2.length() + savedExt2.length()) / 1024) + " KB, save " + str(saveUsec / 1000) + " ms, load " + str(loadUsec / 1000) + " ms")

	# ---- Cost with 25, 40 and 60 inmates (full pawns for all of them) ----
	var inmateGen2 = InmateGenerator.new()
	for target in [25, 40, 60]:
		while(inmateIDs.size() < target):
			var extra = inmateGen2.generate({})
			main.addDynamicCharacterToPool(extra.getID(), CharacterPool.Inmates)
			inmateIDs.append(extra.getID())
		var _pl = module.refreshCells()
		setClock(10, 0, DAY + 7 + target)
		extender.director = {}
		moveTo("hall_mainentrance")
		var t0 = OS.get_ticks_usec()
		var _tf = DirectorScript.tick(module, extender.director, true)
		var directorFirst = OS.get_ticks_usec() - t0
		var t1 = OS.get_ticks_usec()
		var _tf2 = DirectorScript.tick(module, extender.director, true)
		var directorSteady = OS.get_ticks_usec() - t1
		var t2 = OS.get_ticks_usec()
		IS.processTime(600)
		var simulate = OS.get_ticks_usec() - t2
		var t3 = OS.get_ticks_usec()
		var hourly = 0
		for _n in range(6):
			IS.processTime(600)
			var _th = DirectorScript.tick(module, extender.director, true)
		hourly = OS.get_ticks_usec() - t3
		var t4 = OS.get_ticks_usec()
		world.updatePawns(IS)
		var markerUsec = OS.get_ticks_usec() - t4
		world.zoomOut(5.0)
		var t5 = OS.get_ticks_usec()
		world.updatePawns(IS)
		var zoomedMarkers = OS.get_ticks_usec() - t5
		world.zoomReset()
		var t6 = OS.get_ticks_usec()
		var big = JSON.print(IS.saveData()).length() + JSON.print(GM.GES.saveData()).length()
		var saveCost = OS.get_ticks_usec() - t6
		var pawnCount = IS.pawns.size()
		var withPawns = 0
		for id in inmateIDs:
			withPawns += 1 if IS.hasPawn(id) else 0
		print("OBSERVED " + str(target) + " inmates (" + str(pawnCount) + " pawns, " + str(world.pawns.size()) + " markers): director " + str(directorFirst / 1000) + " ms first, " + str(directorSteady / 1000) + " ms steady; ten minutes of pawn simulation " + str(simulate / 1000) + " ms; an hour (6 steps with the director) " + str(hourly / 1000) + " ms; map markers " + str(markerUsec / 1000) + " ms (zoomed out " + str(zoomedMarkers / 1000) + " ms); saved state " + str(big / 1024) + " KB in " + str(saveCost / 1000) + " ms")
		check(withPawns == target and world.pawns.size() >= target, str(target) + " inmates all have pawns and markers")
		check(directorFirst < 120000 and directorSteady < 60000, str(target) + ": the director stays cheap: " + str(directorFirst / 1000) + " ms")
		check(simulate < 500000 and hourly < 3000000, str(target) + ": ten minutes of the whole prison costs " + str(simulate / 1000) + " ms")
		check(markerUsec < 400000 and zoomedMarkers < 400000, str(target) + ": drawing the markers is cheap")
		check(big < 4000000, str(target) + ": the saved state stays small: " + str(big / 1024) + " KB")
	var guardsLeft = DirectorScript.countByType(IS)["guard"]
	check(guardsLeft >= 1 and guardsLeft <= 6, "staff stayed: " + str(guardsLeft) + " guards")

	print("PersistentLivesBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

func dayStory(trace) -> Array:
	var story = []
	var lastLine = ""
	for sample in trace["samples"]:
		var line = sample["kind"] + "@" + sample["room"] + "[" + sample["goal"] + "]"
		if(line != lastLine):
			story.append(str(int(sample["t"] / 3600)).pad_zeros(2) + ":" + str(int(sample["t"] % 3600 / 60)).pad_zeros(2) + " " + line)
			lastLine = line
	return story

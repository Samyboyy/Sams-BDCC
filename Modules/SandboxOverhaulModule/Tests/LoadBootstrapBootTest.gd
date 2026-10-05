extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/LoadBootstrapBootTest.tscn
# Loading a game: the prison must already be lived in when control returns. The real world edit that runs when a game loads (after the map exists, before the first frame) is applied to a
# save with no presence records (an old save, schema 7), with and without vanilla pawns lying around. Everyone must be where today's plan has them (or on the route there), the same every
# time, with nobody created and sent away in front of the player afterwards.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")

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

func places() -> Dictionary:
	var result = {}
	for id in inmateIDs:
		var pawn = IS.getPawn(id)
		result[id] = pawn.getLocation() if pawn != null else "<none>"
	return result

# What an old save looks like: no routines, no presence, and (when scattered) vanilla pawns for some inmates in random rooms.
func makeOldSave(scatter: bool):
	IS.clearAll()
	module.getState().routines = PresenceStateScript().defaultRoutines()
	module.getState().presence = {}
	extender.director = {}
	thePlayer.location = "hall_mainentrance"
	IS.updatePCLocation()
	if(scatter):
		var rooms = ["yard_firstroom", "hall_canteen", "main_stairs1", "gym_entrance", "hall_mainentrance", "cellblock_nearcells", "main_bench1"]
		for index in range(inmateIDs.size()):
			if(index % 2 == 0):
				var pawn = IS.spawnPawn(inmateIDs[index])
				if(pawn != null):
					pawn.setLocation(rooms[index % rooms.size()])

func PresenceStateScript():
	return load("res://Modules/SandboxOverhaulModule/Prison/PresenceState.gd")

func loadTheGame():
	GlobalRegistry.getWorldEdit("SandboxPopulationBootstrapWorldEdit").apply(world)

func _ready():
	get_tree().create_timer(250.0).connect("timeout", get_tree(), "quit", [2])
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
	for n in range(25):
		var c = inmateGen.generate({})
		c.setFlag(CharacterFlag.InmateType, InmateType.General if n < 11 else (InmateType.HighSec if n < 19 else InmateType.SexDeviant))
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	inmateIDs.sort()
	thePlayer.inmateType = InmateType.General
	GangGameScript.ensureInitialized()
	for growDay in range(300, 340):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	var DAY = 30

	# ---- The world edit is registered and does nothing outside a running game ----
	check(GlobalRegistry.getWorldEdit("SandboxPopulationBootstrapWorldEdit") != null, "the bootstrap world edit is registered")

	var moments = [[2, 30], [7, 20], [11, 5], [14, 20], [19, 40], [23, 10]]
	for moment in moments:
		var label = "%02d:%02d" % [moment[0], moment[1]]
		setClock(moment[0], moment[1], DAY)
		makeOldSave(false)
		check(places().values().count("<none>") == inmateIDs.size(), label + ": setup: an old save has no inmate pawns yet")
		loadTheGame() # what happens while the game loads, before the first frame
		var firstPlaces = places()
		check(!firstPlaces.values().has("<none>"), label + ": every inmate is in the world the moment loading ends")
		var routines = JSON.print(module.getState().routines, "", true)
		var presence = JSON.print(module.getState().presence, "", true)
		var now = main.timeOfDay
		var atPlan = 0
		var onRoute = 0
		var inCellAtNight = 0
		var inCellNeeded = 0
		for id in inmateIDs:
			if(!module.getState().routines["plans"].has(id)):
				check(module.getGangs().isCaptive(id) or module.isHeldAway(id), label + ": " + id + " has a plan unless somebody holds them")
				atPlan += 1 # held by a gang or a quest: kept at their holder's place, not on the routine
				continue
			var plan = module.getState().routines["plans"][id]
			var index = RoutineScript.segmentIndex(plan, now)
			var segment = plan[index]
			var here = firstPlaces[id]
			check(world.hasRoomID(here), label + ": " + id + " starts in a real room")
			if(here == segment[3]):
				atPlan += 1
			else:
				var from = plan[index - 1][3] if index > 0 else segment[3]
				var path = world.calculatePath(from, segment[3])
				if(path.has(here)):
					onRoute += 1
			if(segment[2] == "sleep"):
				inCellNeeded += 1
				if(here == module.homeRoomOf(id)):
					inCellAtNight += 1
			var record = module.getState().presence.get(id, {})
			check(!record.empty() and record["room"] == here, label + ": " + id + " has a presence record that says where they are")
		check(atPlan + onRoute == inmateIDs.size(), label + ": everyone is at their activity or on the way there: " + str(atPlan) + " there, " + str(onRoute) + " on the way, of " + str(inmateIDs.size()))
		check(inCellAtNight == inCellNeeded, label + ": whoever should be asleep is already in their own cell: " + str(inCellAtNight) + " of " + str(inCellNeeded))
		if(moment[0] == 2):
			check(inCellNeeded >= 20, "in the dead of night nearly everyone sleeps: " + str(inCellNeeded))
		# Nothing is created in view and sent away: the first director run and a while of play add nobody and move nobody away from their route
		var pawnsBefore = IS.pawns.size()
		var summary = DirectorScript.tick(module, extender.director, true)
		check(summary["hydrated"].empty(), label + ": the first director run has nobody left to create")
		check(IS.pawns.size() == pawnsBefore, label + ": the number of pawns did not change")
		for id in inmateIDs:
			var pawn2 = IS.getPawn(id)
			check(pawn2.getLocation() == firstPlaces[id], label + ": " + id + " did not move in the first director run (they were already in place)")
		# The same save loaded again, with a different mess around it, gives the same places and plans
		makeOldSave(true)
		loadTheGame()
		check(same(places(), firstPlaces), label + ": loading the same save again (with other pawns lying around) puts everyone in the same place")
		check(JSON.print(module.getState().routines, "", true) == routines, label + ": and gives the same plans")
		check(JSON.print(module.getState().presence, "", true) == presence, label + ": and the same presence records")
		# A save that already has records keeps them (no reroll, no move)
		var kept = places()
		var savedIS = JSON.print(IS.saveData())
		var savedExt = JSON.print(GM.GES.saveData())
		IS.clearAll()
		module.getState().clear()
		IS.loadData(JSON.parse(savedIS).result)
		GM.GES.loadData(JSON.parse(savedExt).result)
		loadTheGame()
		check(same(places(), kept), label + ": a save that has presence records loads to exactly where they were")
		check(JSON.print(module.getState().routines, "", true) == routines, label + ": with the same plans")

	# ---- Cells are not empty at night the moment the map appears ----
	setClock(1, 15, DAY + 1)
	makeOldSave(false)
	loadTheGame()
	var inCells = 0
	for id in inmateIDs:
		if(IS.getPawn(id).getLocation() == module.homeRoomOf(id)):
			inCells += 1
	check(inCells >= 20, "at 01:15 the cells are full when the map first appears: " + str(inCells) + " of " + str(inmateIDs.size()))

	print("LoadBootstrapBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

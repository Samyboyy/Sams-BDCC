extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/CellsBootTest.tscn
# Real path: the real extender, module, InteractionSystem pawns (real CharacterPawn objects), real Talking branch, real time-of-day on the real
# MainScene, real save/load. Only the map (no GM.world) is absent. Exits with code 1 on failure.

const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")

var failures = 0

class InmateNpc extends DynamicCharacter:
	var theType = 0
	var slaveFlag = false
	func getInmateType():
		return theType
	func isSlaveToPlayer():
		return slaveFlag
	func getCharacterType():
		return CharacterType.Inmate

class FakePawn:
	var character = null
	var pc = false
	func isPlayer():
		return pc

class FakeTalking extends "res://Game/InteractionSystem/Interactions/Talking.gd":
	var pawns = {}
	func getRolePawn(role:String):
		return pawns[role]

class FakeInteraction:
	var id = "Talking"
	var goal = null

class FakeAlone:
	var id = "AloneInteraction"
	var goal = null

class FakeGoal:
	var id = ""

class FakeRoom extends Node2D:
	pass

class FakeWorld:
	var rooms = {}
	func getRoomByID(roomID):
		return rooms.get(roomID)

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

var main = null
var thePlayer = null
var module = null
var IS = null

func addNpc(npcID, pool, inmateType = 0, isSlaveNpc = false):
	var c = InmateNpc.new()
	c.id = npcID
	c.name = npcID
	c.npcName = npcID
	c.theType = inmateType
	c.slaveFlag = isSlaveNpc
	main.dynamicCharacters[npcID] = c
	if(pool != ""):
		main.addDynamicCharacterToPool(npcID, pool)
	return c

func removeNpc(npcID):
	main.dynamicCharacters.erase(npcID)
	for pool in main.dynamicCharactersPools:
		main.dynamicCharactersPools[pool].erase(npcID)

func addPawn(charID, loc):
	var p = CharacterPawn.new()
	p.charID = charID
	p.pawnTypeID = CharacterType.Inmate
	p.location = loc
	IS.pawns[charID] = p
	if(!IS.pawnsByLoc.has(loc)):
		IS.pawnsByLoc[loc] = {}
	IS.pawnsByLoc[loc][charID] = true
	return p

func setTime(hours, minutes = 0, day = 0):
	main.timeOfDay = int(hours * 3600 + minutes * 60)
	main.currentDay = day

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = load("res://Game/MainScene.gd").new()
	GM.main = main
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	check(module != null and GlobalRegistry.getWorldEdit("SandboxCellsWorldEdit") != null and GlobalRegistry.getModule("SandboxOverhaulModule") != null, "module and world edit registered")

	# ---- Assignment from the real game state ----
	var types = {"i01": InmateType.General, "i02": InmateType.General, "i03": InmateType.General, "i04": InmateType.HighSec, "i05": InmateType.HighSec, "i06": InmateType.SexDeviant, "i07": InmateType.General}
	for id in types:
		addNpc(id, CharacterPool.Inmates, types[id])
	addNpc("slave1", CharacterPool.Inmates, InmateType.HighSec, true)
	addNpc("guard1", CharacterPool.Guards)
	addNpc("story1", "")
	var placed = module.refreshCells()
	var cells = SandboxOverhaulModule.getCells()
	check(placed == 9, "the player, seven inmates and an enslaved inmate are placed: " + str(placed))
	check(cells.getCell("pc")["block"] == "orange" and cells.getCell("pc")["cell"] == 1, "the player gets a valid cell")
	check(module.getPlayerCell()["cell"] == 1 and module.getPlayerCellmate() == "i01", "the player's cellmate is the first eligible inmate of their block: " + module.getPlayerCellmate())
	check(cells.getCell("i02")["cell"] == 2 and cells.getCellmate("i02") == "i03" and cells.getCell("i07")["cell"] == 3, "npcs share cells with each other")
	check(cells.getCell("i04")["block"] == "red" and cells.getCellmate("i04") == "i05" and cells.getCell("i06")["block"] == "lilac", "blocks follow the inmate type")
	check(!cells.isAssigned("guard1") and !cells.isAssigned("story1"), "guards and characters outside the inmate pool get no cell")
	check(cells.isAssigned("slave1") and cells.getCell("slave1")["block"] == "red", "an inmate who is already enslaved still gets a cell")
	var snapshot = JSON.print(SandboxOverhaulModule.getState().cell_assignments)
	check(module.refreshCells() == 0 and JSON.print(SandboxOverhaulModule.getState().cell_assignments) == snapshot, "refreshing again changes nothing")
	addNpc("i08", CharacterPool.Inmates, InmateType.General)
	check(module.refreshCells() == 1 and cells.getCell("i08")["cell"] == 3 and cells.getCellmate("i08") == "i07", "a new inmate takes the first free place without moving anyone")
	check(JSON.print(SandboxOverhaulModule.getState().cell_assignments["i03"]) == JSON.print({"block": "orange", "cell": 2}), "existing assignments untouched")

	# ---- Learning a cell through the real Talking branch ----
	var rel = SandboxOverhaulModule.getRelationships()
	var t = FakeTalking.new()
	t.involvedPawns = {"starter": "pc", "reacter": "i04"}
	for role in t.involvedPawns:
		var p = FakePawn.new()
		p.pc = (t.involvedPawns[role] == "pc")
		t.pawns[role] = p
	t.init_do("ask_cell", {}, {})
	check(t.state == "asked_cell" and cells.knowsCell("pc", "i04") and !cells.knowsCell("i04", "pc"), "asking stores the knowledge in the player's direction")
	check(SandboxOverhaulModule.getState().known_cells == {"pc": {"i04": true}} or JSON.print(SandboxOverhaulModule.getState().known_cells) == JSON.print({"pc": {"i04": true}}), "known_cells has exactly that")
	check(rel.getCharacterIDs().empty() and main.RS.getAffection("i04", "pc") == 0.0 and SandboxOverhaulModule.getState().cooldowns.empty(), "asking changes no relationship value and adds no cooldown")
	var answer = module.getCellAnswer("i04")
	check(answer["found"] and answer["line"] == "I'm in [color=cyan]Red 1[/color]." and answer["note"] == "[color=yellow]Cell learned:[/color] i04 lives in [color=cyan]Red 1[/color].", "the answer names the exact cell in colour: " + str(answer))
	t.asked_cell_text()
	check(Util.join(t.textBuffer, "\n").find("[color=cyan]Red 1[/color]") != -1, "the real asked_cell state shows the cell")
	t.involvedPawns["reacter"] = "guard1"
	t.pawns["reacter"] = FakePawn.new()
	t.init_do("ask_cell", {}, {})
	var noCell = module.getCellAnswer("guard1")
	check(!noCell["found"] and noCell["note"] == "" and !cells.knowsCell("pc", "guard1") and cells.getKnownTargets("pc") == ["i04"], "someone without an ordinary cell answers neutrally and nothing is stored")
	t.init_do("ask_cell", {}, {})
	t.involvedPawns["reacter"] = "i04"
	t.init_do("ask_cell", {}, {})
	check(cells.getKnownTargets("pc") == ["i04"], "asking twice stores it once")
	check(module.getKnownCellsText().find("[color=cyan]Red 1[/color]") != -1 and module.getKnownCellsText().find("i04") != -1, "the review text lists the learned cell")
	check(module.getCellsScreenText().find("Your cell:") != -1 and module.getCellsScreenText().find("Cells you know:") != -1, "the cells screen shows both")

	# ---- Player cell, cellmate and presence ----
	thePlayer.location = "cellblock_orange_nearcell"
	setTime(12)
	check(!module.isInCell("pc") and !module.isInCell("i01"), "by day nobody is counted as in their cell")
	check(module.getMyCellText().find("[color=cyan]Orange 1[/color]") != -1 and module.getMyCellText().find("[color=green]i01[/color]") != -1 and module.getMyCellText().find("not here") != -1, "the player's cell text names the cell and the absent cellmate: " + module.getMyCellText())
	thePlayer.location = thePlayer.getCellLocation()
	check(module.isInCell("pc"), "the player is in their cell when standing in it")
	setTime(23)
	check(module.isInCell("i01") and module.getMyCellText().find("in the cell") != -1, "at night the cellmate (no pawn out) is in the cell")
	var page = module.getRosterPage("orange", 0)
	check(page.size() == 3 and page[0]["cell"] == 1 and page[0]["line"].find("(your cell)") != -1 and page[0]["line"].find("[color=green]You[/color]") != -1 and page[1]["line"].find("[color=green]i02[/color]") != -1, "the roster lists cells with occupants and marks the player's: " + str(page[0]["line"]))
	check(module.getRosterPageCount("orange") == 1 and module.getRosterPage("red", 0).size() == 2 and module.getRosterPage("lilac", 0)[0]["occupants"] == ["i06"], "other blocks have their own roster")
	var view = module.getCellViewText("orange", 1)
	check(view.find("[color=cyan]Orange 1[/color]") != -1 and view.find("This is your cell.") != -1 and module.getCellViewText("orange", 3).find("i07") != -1 and module.getCellViewText("orange", 99).find("Nobody is assigned") != -1, "the shared cell view names occupants")
	thePlayer.location = "cellblock_orange_nearcell"

	# ---- Scene and world edit plumbing ----
	var scene = load("res://Modules/SandboxOverhaulModule/Scenes/CellDirectoryScene.gd").new()
	thePlayer.location = "cellblock_red_nearcell"
	scene._initScene([])
	check(scene.block == "red" and scene.state == "", "in a hall the scene opens that block's roster")
	thePlayer.location = "cellblock_orange_playercell"
	scene = load("res://Modules/SandboxOverhaulModule/Scenes/CellDirectoryScene.gd").new()
	scene._initScene([])
	check(scene.state == "cell" and scene.viewedCell == 1 and scene.block == "orange", "in the player's cell the scene opens that cell")
	scene._react("viewcell", [3])
	check(scene.state == "cell" and scene.viewedCell == 3, "choosing a cell shows it")
	scene._react("directory", [])
	check(scene.state == "", "and back to the directory")
	scene._react("nextpage", [])
	scene._react("prevpage", [])
	scene._react("prevpage", [])
	check(scene.page == 0, "paging is clamped")
	var world = FakeWorld.new()
	var edit = GlobalRegistry.getWorldEdit("SandboxCellsWorldEdit")
	for roomID in edit.HALLS + edit.PLAYER_CELLS:
		var room = FakeRoom.new()
		world.rooms[roomID] = room
	edit.addAction(world, "cellblock_orange_nearcell", "Cell directory", "tip", false)
	edit.addAction(world, "cellblock_orange_nearcell", "Cell directory", "tip", false)
	edit.addAction(world, "cellblock_orange_playercell", "Cell info", "tip", true)
	edit.addAction(world, "missing_room", "x", "x", false)
	var hallAction = world.rooms["cellblock_orange_nearcell"].get_node_or_null("SandboxCellAction")
	var cellAction = world.rooms["cellblock_orange_playercell"].get_node_or_null("SandboxCellAction")
	check(hallAction != null and world.rooms["cellblock_orange_nearcell"].get_child_count() == 1, "the action is added once however often the edit applies")
	check(hallAction.ActionScene == "CellDirectoryScene" and hallAction._shouldShow() == true, "block halls always show the directory")
	check(cellAction._shouldShow() == true, "the player's own cell shows its info")
	thePlayer.location = "cellblock_red_nearcell"
	check(cellAction._shouldShow() == false, "another cell does not")
	for roomID in world.rooms:
		world.rooms[roomID].free()

	# ---- The nightly schedule on real pawns ----
	var ids = []
	for i in range(1, 9):
		ids.append("i0" + str(i))
	var early = ids[0]
	var late = ids[0]
	for id in ids:
		if(CellsScript.bedtimeSeconds(id) < CellsScript.bedtimeSeconds(early)):
			early = id
		if(CellsScript.bedtimeSeconds(id) > CellsScript.bedtimeSeconds(late)):
			late = id
	check(CellsScript.bedtimeSeconds(early) < CellsScript.bedtimeSeconds(late), "setup: two inmates with different bedtimes")
	thePlayer.location = "main_hall_somewhere"
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	var farPawns = {}
	for id in ids:
		farPawns[id] = addPawn(id, "far_" + id)
	addPawn("pc", "main_hall_somewhere")

	# Before bedtime nothing is forced
	setTime(19, 0, 5)
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(IS.pawns.size() == 9, "before bedtime no pawn is moved")

	# At the early inmate's bedtime only those whose bedtime has come settle
	var tEarly = CellsScript.bedtimeSeconds(early)
	main.timeOfDay = tEarly
	main.currentDay = 5
	extender.scheduleBucket = -1
	module.onScheduleTick()
	var settled = 0
	for id in ids:
		if(!IS.hasPawn(id)):
			settled += 1
			check(CellsScript.isNight(id, tEarly), id + " only settles once its own bedtime has come")
	check(!IS.hasPawn(early) and settled >= 1 and settled < 8 and IS.hasPawn(late), "the prison settles gradually: " + str(settled) + " of 8 gone at the first bedtime")
	check(IS.hasPawn("pc"), "the player is never moved")
	var countAfterFirst = IS.pawns.size()
	module.onScheduleTick()
	check(IS.pawns.size() == countAfterFirst, "running again in the same ten minutes does nothing")
	addPawn("i99", "far_i99")
	main.timeOfDay = tEarly + 60
	module.onScheduleTick()
	check(IS.hasPawn("i99"), "an unassigned character is not swept")

	# Late evening: everybody is in
	setTime(22, 30, 5)
	module.onScheduleTick()
	var remaining = []
	for id in ids:
		if(IS.hasPawn(id)):
			remaining.append(id)
	check(remaining.empty(), "overnight no inmate is out: " + str(remaining))
	for id in ids:
		check(module.isInCell(id) and !module.hasFailedToReturn(id), id + " is in their cell at night")
	check(module.canSpawnPawn("i01") == false and module.canSpawnPawn("guard1") == true and module.canSpawnPawn("i99") == true, "a sleeping inmate is not spawned; others are")

	# Blocked pawns defer and return once free
	setTime(21, 30, 6)
	var blockedKinds = {}
	for id in ["i01", "i02", "i03", "i04", "i05", "i06"]:
		blockedKinds[id] = addPawn(id, "far_" + id)
	blockedKinds["i01"].currentInteraction = FakeInteraction.new()
	var healer = FakeAlone.new()
	healer.goal = FakeGoal.new()
	healer.goal.id = "GetHealed"
	blockedKinds["i02"].currentInteraction = healer
	var idle = FakeAlone.new()
	idle.goal = FakeGoal.new()
	idle.goal.id = "Wander"
	blockedKinds["i03"].currentInteraction = idle
	main.timeOfDay = 23 * 3600 + 30 * 60 + 600
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(IS.hasPawn("i01") and IS.hasPawn("i02"), "a pawn in an interaction or a priority goal is deferred, not removed")
	check(!IS.hasPawn("i03") and !IS.hasPawn("i04"), "an idle pawn wandering goes home")
	check(module.hasFailedToReturn("i01") and module.hasFailedToReturn("i02") and !module.isInCell("i01"), "later systems can see who has not come back")
	check(blockedKinds["i01"].currentInteraction != null, "the active interaction is untouched")
	main.timeOfDay += 600
	module.onScheduleTick()
	check(IS.hasPawn("i01") and IS.hasPawn("i02"), "still deferred at the next tick while busy, without errors")
	blockedKinds["i01"].currentInteraction = null
	healer.goal.id = "Wander"
	main.timeOfDay += 600
	module.onScheduleTick()
	check(!IS.hasPawn("i01") and !IS.hasPawn("i02"), "once available they go home during the night")
	var _slavePawn = addPawn("slave1", "far_s")
	var _storyPawn = addPawn("story1", "far_t")
	main.timeOfDay += 600
	module.onScheduleTick()
	check(IS.hasPawn("slave1") and IS.hasPawn("story1"), "a busy slave and a character without a cell are left alone")
	IS.pawns.erase("slave1") # the stub slave has no slavery data, so remove it without the normal delete
	IS.pawnsByLoc["far_s"].erase("slave1")
	IS.deletePawn("story1")

	# A pawn in the player's room walks home through BDCC's own Leave goal instead of vanishing
	thePlayer.location = "hall_x"
	var near = addPawn("i05", "hall_x")
	near.tiredness = 0.0
	main.timeOfDay += 600
	module.onScheduleTick()
	check(IS.hasPawn("i05") and near.tiredness >= 1.5, "a pawn in front of the player stays visible and is made tired so it walks off")
	near.tiredness = 0.0
	IS.deletePawn("i05")

	# Morning
	setTime(6, 30, 7)
	check(module.canSpawnPawn("i01") == (!CellsScript.isNight("i01", 6 * 3600 + 30 * 60)), "spawning follows the wake time")
	setTime(8, 0, 7)
	for id in ids:
		check(module.canSpawnPawn(id) and !module.isInCell(id), id + " may leave the cell after the wake window")
	var _morningPawn = addPawn("i04", "main_stairs1")
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(IS.hasPawn("i04"), "daytime pawns are not touched")
	IS.deletePawn("i04")
	# Crossing midnight and a long skip: the result depends only on the time
	setTime(0, 40, 8)
	addPawn("i04", "far_a")
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(!IS.hasPawn("i04"), "after midnight inmates are still settled")

	# ---- Attendance: home, away and failed to return ----
	for id in IS.pawns.keys():
		if(id != "pc"):
			IS.deletePawn(id)
	SandboxOverhaulModule.getState().cell_presence.clear()
	var stateRef = SandboxOverhaulModule.getState()

	# An ordinary unspawned inmate is assumed home after bedtime; before bedtime nobody has failed to return
	setTime(19, 0, 9)
	var _outPawn = addPawn("i06", "far_i06")
	check(module.getAttendance("i06") == "" and !module.hasFailedToReturn("i06") and !module.isInCell("i06"), "before bedtime there is no attendance and nobody has failed to return, even if out")
	IS.deletePawn("i06")
	setTime(22, 30, 9)
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(module.getAttendance("i06") == "home" and module.isInCell("i06") and !module.hasFailedToReturn("i06"), "an ordinary unspawned inmate is home after bedtime")
	check(stateRef.cell_presence["i06"]["state"] == "home" and stateRef.cell_presence["i06"]["night"] == 9, "and it is recorded for tonight")

	# An unspawned enslaved inmate is away, not home, and keeps their cell
	check(module.getAttendance("slave1") == "away" and !module.isInCell("slave1") and module.hasFailedToReturn("slave1"), "an unspawned enslaved inmate is away")
	check(cells.getCell("slave1")["cell"] == 2 and cells.getCell("slave1")["block"] == "red", "and keeps their assigned cell")

	# Enslaving the player's cellmate keeps the cell; they stop returning; freeing keeps it too
	var mateCell = JSON.print(stateRef.cell_assignments["i01"])
	var assignmentsBefore = JSON.print(stateRef.cell_assignments)
	check(module.getAttendance("i01") == "home", "setup: the cellmate is home")
	var mate = main.dynamicCharacters["i01"]
	mate.slaveFlag = true
	main.removeDynamicCharacterFromAllPools("i01")
	main.addDynamicCharacterToPool("i01", CharacterPool.Slaves)
	check(module.refreshCells() == 0 and JSON.print(stateRef.cell_assignments) == assignmentsBefore, "enslaving the cellmate changes no assignment")
	check(module.getPlayerCellmate() == "i01" and JSON.print(stateRef.cell_assignments["i01"]) == mateCell, "the player's cellmate is still that person")
	extender.scheduleBucket = -1
	setTime(22, 40, 9)
	module.onScheduleTick()
	check(module.getAttendance("i01") == "away" and !module.isInCell("i01") and module.hasFailedToReturn("i01"), "the enslaved cellmate is now away, so the player can notice")
	check(module.getMyCellText().find("[color=green]i01[/color] (" + "[color=#c8b560]not here[/color])") != -1, "the player's cell text shows the missing cellmate: " + module.getMyCellText())
	check(module.getRosterPage("orange", 0)[0]["line"].find("not here") != -1 and module.getCellViewText("orange", 1).find("not here") != -1, "the directory and the cell view show it too")
	mate.slaveFlag = false
	main.removeDynamicCharacterFromAllPools("i01")
	main.addDynamicCharacterToPool("i01", CharacterPool.Inmates)
	check(module.refreshCells() == 0 and JSON.print(stateRef.cell_assignments) == assignmentsBefore, "freeing them creates no new cell")
	extender.scheduleBucket = -1
	setTime(22, 50, 9)
	module.onScheduleTick()
	check(module.getAttendance("i01") == "home" and module.isInCell("i01") and !module.hasFailedToReturn("i01"), "once free and unspawned they are home again")

	# A newly encountered, already enslaved inmate gets a cell
	var _newSlave = addNpc("i11", CharacterPool.Slaves, InmateType.HighSec, true)
	check(module.refreshCells() == 1 and cells.isAssigned("i11"), "a new enslaved inmate gets a cell")
	check(JSON.print(stateRef.cell_assignments["i03"]) == JSON.print({"block": "orange", "cell": 2}) and cells.getCell("pc")["cell"] == 1, "nobody else moved")
	removeNpc("i11")
	cells.removeCharacter("i11")

	# A spawned blocked inmate is away; they become home once the blocker ends and they settle
	var busy = addPawn("i07", "far_i07")
	busy.currentInteraction = FakeInteraction.new()
	extender.scheduleBucket = -1
	setTime(23, 0, 9)
	module.onScheduleTick()
	check(IS.hasPawn("i07") and module.getAttendance("i07") == "away" and !module.isInCell("i07") and module.hasFailedToReturn("i07"), "a blocked inmate is away after bedtime")
	check(stateRef.cell_presence["i07"]["state"] == "away", "recorded as away")
	busy.currentInteraction = null
	setTime(23, 10, 9)
	module.onScheduleTick()
	check(!IS.hasPawn("i07") and module.getAttendance("i07") == "home" and module.isInCell("i07") and !module.hasFailedToReturn("i07"), "after the blocker ends and settling succeeds they are home")
	var _walker = addPawn("i08", "hall_x")
	thePlayer.location = "hall_x"
	setTime(23, 20, 9)
	module.onScheduleTick()
	check(IS.hasPawn("i08") and module.getAttendance("i08") == "away" and module.hasFailedToReturn("i08"), "a pawn still walking home in front of the player is away until it is gone")
	IS.deletePawn("i08")
	thePlayer.location = "main_hall_somewhere"

	# Save and load during the night keep home and away
	var blockedAgain = addPawn("i05", "far_i05")
	blockedAgain.currentInteraction = FakeInteraction.new()
	setTime(23, 30, 9)
	module.onScheduleTick()
	check(module.getAttendance("i05") == "away" and module.getAttendance("i06") == "home", "setup: one away, one home")
	var presenceBefore = JSON.print(stateRef.cell_presence)
	var nightSaved = JSON.parse(JSON.print(GM.GES.saveData())).result
	check(JSON.print(nightSaved["extendersData"]["SandboxGameExtender"]["cell_presence"]) == presenceBefore, "attendance is saved")
	stateRef.clear()
	GM.GES.loadData(JSON.parse(JSON.print(nightSaved)).result)
	check(module.getAttendance("i05") == "away" and module.getAttendance("i06") == "home" and JSON.print(SandboxOverhaulModule.getState().cell_presence) == presenceBefore, "after loading mid-night the same people are home and away")
	blockedAgain.currentInteraction = null
	IS.deletePawn("i05")

	# Waking invalidates the night's attendance, and a new night does not inherit it
	setTime(8, 0, 10)
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(SandboxOverhaulModule.getState().cell_presence.empty() and module.getAttendance("i06") == "" and !module.isInCell("i06") and !module.hasFailedToReturn("i05"), "after waking the attendance is cleared and nobody counts as home or failed")
	check(CellsScript.nightId("i06", 6 * 3600, 10) == 9 and CellsScript.nightId("i06", 22 * 3600, 9) == 9 and CellsScript.nightId("i06", 22 * 3600, 10) == 10, "the early morning belongs to the night that began the day before")
	var _ok = cells.setPresence("i06", 9, "away")
	setTime(22, 30, 10)
	check(module.getAttendance("i06") == "home", "an old night's record is ignored on a new night")
	setTime(2, 0, 11)
	check(CellsScript.nightId("i06", 2 * 3600, 11) == 10, "the same night continues after midnight")
	cells.clearPresence("i06")

	# ---- Save, load, prune, new game ----
	var rel2 = SandboxOverhaulModule.getRelationships()
	var _f = rel2.setFeeling("i01", "pc", "trust", 12)
	SandboxOverhaulModule.getCombat().addRep("combat", 9)
	SandboxOverhaulModule.getInjuries().applyInjury("pc", "trauma", 2)
	var before = JSON.print(SandboxOverhaulModule.getState().cell_assignments)
	removeNpc("i02")
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	var savedCells = saved["extendersData"]["SandboxGameExtender"]["cell_assignments"]
	check(!savedCells.has("i02") and savedCells.has("i03") and savedCells.has("pc"), "a removed character is pruned before saving")
	check(saved["extendersData"]["SandboxGameExtender"]["schema_version"] == 3 and saved["extendersData"]["SandboxGameExtender"]["known_cells"]["pc"].has("i04"), "saved at schema 3 with the known cells")
	SandboxOverhaulModule.getState().clear()
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(SandboxOverhaulModule.getCells().getCell("i03")["cell"] == 2 and SandboxOverhaulModule.getCells().getCellmate("pc") == "i01" and SandboxOverhaulModule.getCells().knowsCell("pc", "i04"), "assignments and learned cells survive a load exactly")
	check(rel2.getFeeling("i01", "pc", "trust") == 12.0 and SandboxOverhaulModule.getCombat().getCombatReputation() == 9.0 and SandboxOverhaulModule.getInjuries().has("pc", "trauma"), "relationships, reputation and injuries survive")
	var _again = module.refreshCells()
	addNpc("i10", CharacterPool.Inmates, InmateType.General)
	check(module.refreshCells() == 1 and SandboxOverhaulModule.getCells().getCell("i10")["cell"] == 2 and SandboxOverhaulModule.getCells().getCellmate("i10") == "i03", "the freed place is reused and nobody else moved")
	for id in ["i01", "i03", "i04", "i05", "i06", "i07", "i08"]:
		check(JSON.parse(before).result[id]["cell"] == SandboxOverhaulModule.getCells().getCell(id)["cell"], "unchanged after save, prune and load: " + id)

	# An older save without cells loads and creates them on first use
	SandboxOverhaulModule.getState().loadData({"schema_version": 2, "injuries": {}})
	check(SandboxOverhaulModule.getState().cell_assignments.empty() and SandboxOverhaulModule.getState().schema_version == 3, "an older save loads with no cells")
	check(module.refreshCells() > 0 and SandboxOverhaulModule.getCells().isAssigned("pc") and SandboxOverhaulModule.getCells().getCell("pc")["cell"] == 1, "and the cells are created on first use, the player first")

	var main2 = load("res://Game/MainScene.gd").new()
	GM.main = main2
	check(SandboxOverhaulModule.getState().cell_assignments.empty() and SandboxOverhaulModule.getState().known_cells.empty(), "a new game resets cells and known cells")

	GM.main = null
	GM.pc = null
	main.dynamicCharacters.clear()
	main.free()
	main2.free()
	print("CellsBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

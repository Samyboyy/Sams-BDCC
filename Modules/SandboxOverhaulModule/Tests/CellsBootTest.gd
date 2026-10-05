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
	thePlayer.location = "cellblock_orange_nearcell"

	# ---- Attendance on real pawns: home only when physically in the cell ----
	var ids = []
	for i in range(1, 9):
		ids.append("i0" + str(i))
	thePlayer.location = "main_hall_somewhere"
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	var stateRef = SandboxOverhaulModule.getState()
	addPawn("pc", "main_hall_somewhere")
	# Before bedtime nothing is recorded
	setTime(19, 0, 5)
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(stateRef.cell_presence.empty(), "before bedtime no attendance is recorded")
	for id in ids:
		check(module.getAttendance(id) == "" and !module.isInCell(id) and !module.hasFailedToReturn(id), id + ": no attendance before bedtime")
	# At night an inmate with no pawn is home; one whose pawn is anywhere but their own cell is away; one in their own cell is home
	setTime(23, 30, 5)
	for id in ["i01", "i02", "i03"]:
		check(module.getAttendance(id) == "home" and module.isInCell(id) and !module.hasFailedToReturn(id), id + ": no pawn, no reason to be out: home")
	var hallPawn = addPawn("i01", "cellblock_orange_nearcell")
	var _cellPawn = addPawn("i02", module.homeRoomOf("i02"))
	var farPawn = addPawn("i03", "far_i03")
	extender.scheduleBucket = -1
	var sweep = module.sweepResidents()
	check(module.getAttendance("i01") == "away" and module.hasFailedToReturn("i01") and !module.isInCell("i01"), "a pawn still in the hall outside the cell is away, not home")
	check(module.getAttendance("i02") == "home" and module.isInCell("i02") and !module.hasFailedToReturn("i02"), "a pawn that is in its own cell is home")
	check(module.getAttendance("i03") == "away" and sweep["walking"].has("i03") and sweep["walking"].has("i01") and sweep["home"].has("i02") and sweep["despawned"].empty(), "the sweep records them and removes nobody")
	check(IS.hasPawn("i01") and IS.hasPawn("i02") and IS.hasPawn("i03"), "nobody is removed from the world")
	farPawn.currentInteraction = FakeInteraction.new()
	module.sweepResidents()
	check(module.getAttendance("i03") == "away" and module.sweepResidents()["deferred"].has("i03"), "a busy pawn is away and deferred")
	farPawn.currentInteraction = null
	# Arrival makes them home, and only then
	hallPawn.setLocation(module.homeRoomOf("i01"))
	check(module.getAttendance("i01") == "home" and module.isInCell("i01"), "once they walk into their cell they are home")
	check(module.canSpawnPawn("i01") == false and module.canSpawnPawn("guard1") == true and module.canSpawnPawn("i99") == true, "a sleeping inmate is not picked for a random appearance; others are")
	IS.deletePawn("i01")
	IS.deletePawn("i02")
	IS.deletePawn("i03")

	# ---- Home, away and failed to return for inmates something keeps elsewhere ----
	SandboxOverhaulModule.getState().cell_presence.clear()
	check(module.getAttendance("slave1") == "away" and !module.isInCell("slave1") and module.hasFailedToReturn("slave1"), "an unspawned enslaved inmate is away")
	check(cells.getCell("slave1")["cell"] == 2 and cells.getCell("slave1")["block"] == "red", "and keeps their assigned cell")
	var mateCell = JSON.print(stateRef.cell_assignments["i01"])
	var assignmentsBefore = JSON.print(stateRef.cell_assignments)
	check(module.getAttendance("i01") == "home", "setup: the cellmate is home")
	var mate = main.dynamicCharacters["i01"]
	mate.slaveFlag = true
	main.removeDynamicCharacterFromAllPools("i01")
	main.addDynamicCharacterToPool("i01", CharacterPool.Slaves)
	check(module.refreshCells() == 0 and JSON.print(stateRef.cell_assignments) == assignmentsBefore, "enslaving the cellmate changes no assignment")
	check(module.getPlayerCellmate() == "i01" and JSON.print(stateRef.cell_assignments["i01"]) == mateCell, "the player's cellmate is still that person")
	setTime(22, 40, 9)
	check(module.getAttendance("i01") == "away" and !module.isInCell("i01") and module.hasFailedToReturn("i01"), "the enslaved cellmate is now away, so the player can notice")
	check(module.getMyCellText().find("[color=green]i01[/color] (" + "[color=#c8b560]not here[/color])") != -1, "the player's cell text shows the missing cellmate: " + module.getMyCellText())
	mate.slaveFlag = false
	main.removeDynamicCharacterFromAllPools("i01")
	main.addDynamicCharacterToPool("i01", CharacterPool.Inmates)
	check(module.refreshCells() == 0 and JSON.print(stateRef.cell_assignments) == assignmentsBefore, "freeing them creates no new cell")
	setTime(22, 50, 9)
	check(module.getAttendance("i01") == "home" and module.isInCell("i01") and !module.hasFailedToReturn("i01"), "once free and without a pawn they are home again")
	# A newly encountered, already enslaved inmate gets a cell
	var _newSlave = addNpc("i11", CharacterPool.Slaves, InmateType.HighSec, true)
	check(module.refreshCells() == 1 and cells.isAssigned("i11"), "a new enslaved inmate gets a cell")
	check(JSON.print(stateRef.cell_assignments["i03"]) == JSON.print({"block": "orange", "cell": 2}) and cells.getCell("pc")["cell"] == 1, "nobody else moved")
	removeNpc("i11")
	cells.removeCharacter("i11")
	# Record, save and load keep home and away
	var blockedAgain = addPawn("i05", "far_i05")
	blockedAgain.currentInteraction = FakeInteraction.new()
	setTime(23, 30, 9)
	extender.scheduleBucket = -1
	module.onScheduleTick()
	check(module.getAttendance("i05") == "away" and module.getAttendance("i06") == "home", "setup: one away, one home")
	var presenceBefore = JSON.print(stateRef.cell_presence)
	var nightSaved = JSON.parse(JSON.print(GM.GES.saveData())).result
	check(JSON.print(nightSaved["extendersData"]["SandboxGameExtender"]["cell_presence"]) == presenceBefore, "attendance is saved")
	stateRef.clear()
	GM.GES.loadData(JSON.parse(JSON.print(nightSaved)).result)
	check(module.getAttendance("i06") == "home" and JSON.print(SandboxOverhaulModule.getState().cell_presence) == presenceBefore, "after loading mid-night the recorded attendance is the same")
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
	check(saved["extendersData"]["SandboxGameExtender"]["schema_version"] == 8 and saved["extendersData"]["SandboxGameExtender"]["known_cells"]["pc"].has("i04"), "saved at schema 8 with the known cells")
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
	check(SandboxOverhaulModule.getState().cell_assignments.empty() and SandboxOverhaulModule.getState().schema_version == 8, "an older save loads with no cells")
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

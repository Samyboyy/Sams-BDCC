extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/LivingPrisonBootTest.tscn
# The physical cells, the people in them and the population director, on the real map: the real World scene with every floor, the real extender and module, real
# inmates and guards from BDCC's own generators, real pawns spawned through the InteractionSystem, real goals and pathfinding. Only the world simulation inside
# processTime is cut out (time passes by setting the clock).

const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const RoomsScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellRooms.gd")
const JobsScript = preload("res://Modules/SandboxOverhaulModule/Work/NpcJobs.gd")
const WorkEventGame = preload("res://Modules/SandboxOverhaulModule/Work/WorkEventGame.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")

const HelpScript = preload("res://Modules/SandboxOverhaulModule/Interactions/HelpRequests.gd")

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

func setTime(hours, minutes = 0, day = 0):
	main.timeOfDay = int(hours * 3600 + minutes * 60)
	main.currentDay = day

func moveTo(roomID):
	thePlayer.location = roomID
	if(IS.hasPawn("pc")):
		IS.getPawn("pc").setLocation(roomID)

func memory():
	return extender.director

func tick():
	return DirectorScript.tick(module, memory(), true)

# Cut the director loose: whoever is not busy forgets where they were sent, so each run starts fresh.
func resetDirector():
	extender.director = {}

func pawnsOfKind(kind):
	var result = []
	for charID in IS.pawns:
		var pawn = IS.pawns[charID]
		if(pawn.isPlayer()):
			continue
		if((kind == "inmate" and pawn.isInmate()) or (kind == "guard" and pawn.isGuard()) or (kind == "nurse" and pawn.isNurse()) or (kind == "engineer" and pawn.isEngineer())):
			result.append(charID)
	result.sort()
	return result

func clearPawns():
	for charID in IS.pawns.keys():
		if(charID != "pc"):
			IS.deletePawn(charID)
	for interaction in IS.interactions.duplicate():
		if(!interaction.involvedPawns.has("main") or interaction.involvedPawns["main"] != "pc"):
			IS.stopInteraction(interaction)

func _ready():
	get_tree().create_timer(170.0).connect("timeout", get_tree(), "quit", [2])
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
	world = GM.world # the UI brings the real world with it
	check(GM.world == world and world.hasRoomID("cellblock_orange_nearcell") and world.hasRoomID("hall_canteen"), "the real map is loaded")
	world.addTransitions() # the game does this after applying the world edits
	GlobalRegistry.getWorldEdit("SandboxWorkWorldEdit").apply(world)

	# ---- A prison of 25 inmates: 11 general, 8 high security, 6 sex deviants ----
	var inmateGen = InmateGenerator.new()
	var inmateIDs = []
	var typeOf = {}
	for n in range(25):
		var c = inmateGen.generate({})
		var theType = InmateType.General if n < 11 else (InmateType.HighSec if n < 19 else InmateType.SexDeviant)
		c.setFlag(CharacterFlag.InmateType, theType)
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
		typeOf[c.getID()] = theType
	inmateIDs.sort()
	var guardGen = GuardGenerator.new()
	var guardIDs = []
	for _n in range(10):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	thePlayer.inmateType = InmateType.General
	IS.updatePCLocation()
	var _placed = module.refreshCells()
	check(module.getDirectedInmateIDs().size() == 25, "25 eligible inmates are directed")

	# ---- Physical cells ----
	var cells = module.getCells()
	var counts = RoomsScript.wantedCounts(module.getEligibleCellEntries(), cells)
	check(LayoutScript.totalCells(counts) == 13, "25 inmates and the player need 13 cells: " + str(counts))
	var cellRooms = world.get_tree().get_nodes_in_group("sbx_cell")
	check(cellRooms.size() == LayoutScript.totalCells(counts), "every cell is a real room on the map: " + str(cellRooms.size()))
	var orangeLast = LayoutScript.roomID("orange", counts["orange"])
	check(world.hasRoomID(orangeLast) and world.hasRoomID("sbx_cell_red_2") and world.hasRoomID("sbx_cell_lilac_2"), "the later cells exist with their stable IDs")
	var firstRoom = world.getRoomByID("sbx_cell_orange_2")
	check(firstRoom != null and firstRoom.getCell() == LayoutScript.position("orange", 2) and firstRoom.getFloorID() == world.getRoomByID("cellblock_orange_nearcell").getFloorID(), "orange cell 2 is where the layout puts it, on the Cellblock floor: " + str(firstRoom.getCell() if firstRoom != null else null))
	check(firstRoom.roomName == "Orange Cell 2" and firstRoom.roomSprite == RoomStuff.RoomSprite.BED and firstRoom.roomColor == RoomStuff.RoomColor.Orange, "named, with the bed icon and the block's colour")
	check(world.getRoomByID("sbx_cell_red_2").roomColor == RoomStuff.RoomColor.Red and world.getRoomByID("sbx_cell_lilac_2").roomColor == RoomStuff.RoomColor.Pink, "red and lilac cells have their own colours")
	for roomID in ["cellblock_orange_playercell", "sbx_cell_orange_2", "sbx_cell_red_3", "sbx_cell_lilac_3"]:
		var theRoom = world.getRoomByID(roomID)
		var number = theRoom.get_node_or_null("SandboxCellNumber")
		var parsed = LayoutScript.parse(roomID)
		check(number != null and number.text == str(parsed["cell"]), "the cell number is shown on " + roomID)
	var path = world.calculatePath("cellblock_orange_nearcell", orangeLast)
	check(path.size() >= 2 and path[0] == "cellblock_orange_nearcell" and path[path.size() - 1] == orangeLast, "the last orange cell can be walked to from the hall: " + str(path))
	for block in LayoutScript.BLOCKS:
		for cell in range(2, counts[block] + 1):
			check(world.calculatePath(LayoutScript.HALL_ROOMS[block], LayoutScript.roomID(block, cell)).size() >= 2, LayoutScript.label(block, cell) + " is reachable from its hall")
	check(world.calculatePath("sbx_cell_red_2", "sbx_cell_lilac_2").size() >= 2, "and the blocks are connected through the halls")
	var wasCount = cellRooms.size()
	check(module.ensureCellRooms(world, true).empty() and world.get_tree().get_nodes_in_group("sbx_cell").size() == wasCount, "building again adds nothing")
	var edit = GlobalRegistry.getWorldEdit("SandboxCellsWorldEdit")
	edit.apply(world)
	check(world.get_tree().get_nodes_in_group("sbx_cell").size() == wasCount, "the world edit applied again adds nothing either")

	# The cell rooms never offer the player's private features, and the directory is gone
	for roomID in ["cellblock_orange_nearcell", "cellblock_red_nearcell", "cellblock_lilac_nearcell", "sbx_cell_orange_2", "cellblock_red_playercell"]:
		var theRoom = world.getRoomByID(roomID)
		for child in theRoom.get_children():
			check(child.name != "SandboxCellAction" and (!(child is RoomAction) or child.ActionScene != "CellDirectoryScene"), roomID + " has no directory action")
	var gone = File.new()
	check(!gone.file_exists("res://Modules/SandboxOverhaulModule/Scenes/CellDirectoryScene.gd") and !gone.file_exists("res://Modules/SandboxOverhaulModule/WorldEdits/CellDirectoryAction.gd"), "the directory scene and its action are deleted")
	moveTo("cellblock_orange_playercell")
	var upgradesAction = world.getRoomByID("cellblock_orange_playercell").get_node_or_null("SandboxCellUpgrades")
	check(upgradesAction != null and upgradesAction._shouldShow(), "the player's own cell keeps its upgrades")
	moveTo("cellblock_red_playercell")
	var redAction = world.getRoomByID("cellblock_red_playercell").get_node_or_null("SandboxCellUpgrades")
	check(redAction != null and !redAction._shouldShow(), "another block's cell 1 does not offer the player's upgrades")
	check(world.getRoomByID("sbx_cell_orange_2").get_node_or_null("SandboxCellUpgrades") == null, "a new cell has no upgrades at all")

	# Entering a cell names its residents
	var mate = cells.getCellmate("pc")
	moveTo("cellblock_orange_playercell")
	var ownRoom = world.getRoomByID("cellblock_orange_playercell")
	ownRoom.emit_signal("onPreEnter", ownRoom)
	check(ownRoom.roomName == "Orange Cell 1" and mate != "" and ownRoom.roomDescription.find("Residents: you and " + main.getCharacter(mate).getName() + ".") != -1, "the player's cell has a short title and lists the player and the cellmate in the description: " + ownRoom.roomName)
	var otherCellInfo = cells.getOccupants("orange", 2)
	check(otherCellInfo.size() == 2, "setup: orange cell 2 has two residents")
	var theRoom2 = world.getRoomByID("sbx_cell_orange_2")
	theRoom2.emit_signal("onPreEnter", theRoom2)
	check(theRoom2.roomName == "Orange Cell 2" and theRoom2.roomDescription.find("Residents: " + LayoutScript.joinNames([main.getCharacter(otherCellInfo[0]).getName(), main.getCharacter(otherCellInfo[1]).getName()]) + ".") != -1, "another cell has a short title and lists its two residents in the description: " + theRoom2.roomName + " / " + theRoom2.roomDescription)
	var emptyRoom = world.getRoomByID(LayoutScript.roomID("lilac", counts["lilac"]))
	emptyRoom.emit_signal("onPreEnter", emptyRoom)
	check(emptyRoom.roomName == "Lilac Cell " + str(counts["lilac"]) and emptyRoom.roomDescription.find("Residents:") != -1 or emptyRoom.roomDescription.find("Nobody is assigned") != -1, "every cell has its number in the title: " + emptyRoom.roomName)
	for longName in ["Bartholomew Featherstonehaugh-Montgomery", "Anna", "Zoe"]:
		var one = RoomsScript.residentsLine([longName], false)
		var two = RoomsScript.residentsLine([longName, "Rowena"], false)
		check(one == "Residents: " + longName + "." and two == "Residents: " + longName + " and Rowena." and RoomsScript.residentsLine([], false) == "Nobody is assigned to this cell." and RoomsScript.residentsLine([longName], true) == "Residents: you and " + longName + ".", "residents are written in the description, however long the name: " + one)
	check(LayoutScript.label("orange", 12).length() <= 14 and LayoutScript.label("lilac", 60).length() <= 14, "a cell title is always short enough for the sidebar")
	for block in LayoutScript.BLOCKS:
		for cell in range(1, counts[block] + 1):
			check(cells.getOccupants(block, cell).size() <= 2, "at most two residents in " + LayoutScript.label(block, cell))

	# ---- Fights between other people: watch, take a side, or break it up ----
	clearPawns()
	resetDirector()
	setTime(15, 0, 16)
	moveTo("hall_mainentrance")
	var strangers = []
	for candidate in module.getDirectedInmateIDs():
		if(HelpScript.bondOf(module, candidate) == ""):
			strangers.append(candidate)
	var fighterA = strangers[0]
	var fighterB = strangers[1]
	var pa = DirectorScript.spawnAt(IS, fighterA, "hall_mainentrance")
	var pb = DirectorScript.spawnAt(IS, fighterB, "hall_mainentrance")
	var pcPawn = IS.getPawn("pc")
	check(pcPawn != null and pa != null and pb != null, "setup: two inmates and the player in one room")
	pcPawn.getInteraction()
	IS.startInteraction("GenericAttack", {"starter": fighterA, "reacter": fighterB})
	var fight = null
	for interaction in IS.interactions:
		if(interaction.id == "GenericAttack" and !interaction.wasDeleted):
			fight = interaction
	check(fight != null, "setup: they are fighting")
	thePlayer.addStamina(100)
	var offered = fight.getInterruptActionsFinal(pcPawn)
	var offeredIDs = []
	for action in offered:
		offeredIDs.append(action["id"])
	check(offeredIDs.has("join_starter") and offeredIDs.has("join_reacter") and offeredIDs.has("break_up"), "the player can take either side or break it up (not only watch): " + str(offeredIDs))
	check(fight.getInterruptActionsFinal(pa).empty(), "nobody else is offered these")
	module.queuedRolls = [0.0]
	fight.doInterruptActionFinal(pcPawn, "break_up", {})
	check(fight.wasDeleted, "a successful break-up ends the fight")
	IS.startInteraction("GenericAttack", {"starter": fighterA, "reacter": fighterB})
	fight = null
	for interaction in IS.interactions:
		if(interaction.id == "GenericAttack" and !interaction.wasDeleted):
			fight = interaction
	module.queuedRolls = [0.999]
	var staminaBefore = thePlayer.getStamina()
	fight.doInterruptActionFinal(pcPawn, "break_up", {})
	check(!fight.wasDeleted and thePlayer.getStamina() < staminaBefore, "a failed attempt costs stamina and the fight goes on")
	var trustBefore = module.getRelationships().getFeeling(fighterA, "pc", "trust")
	fight.doInterruptActionFinal(pcPawn, "join_starter", {})
	var mine = null
	for interaction in IS.interactions:
		if(interaction.id == "GenericAttack" and !interaction.wasDeleted):
			mine = interaction
	check(fight.wasDeleted and mine != null and mine.getRoleID("starter") == "pc" and mine.getRoleID("reacter") == fighterB and module.getRelationships().getFeeling(fighterA, "pc", "trust") > trustBefore, "joining takes your friend's side: you fight their opponent and they remember it")
	check(main.dynamicCharacters.has(fighterA) and main.dynamicCharacters.has(fighterB), "nobody was lost")
	IS.stopInteraction(mine)
	# The director starts quarrels now and then, never with the player
	clearPawns()
	resetDirector()
	main.RS.setAffection(fighterA, fighterB, -0.6)
	var qa = DirectorScript.spawnAt(IS, fighterA, "hall_mainentrance")
	var qb = DirectorScript.spawnAt(IS, fighterB, "hall_mainentrance")
	check(qa != null and qb != null, "setup: two inmates who cannot stand each other, in view")
	module.queuedRolls = [0.0]
	var mem = {"incident_stamp": -999999}
	var started = DirectorScript.maybeIncident(module, IS, DirectorScript.ringOf(world, "hall_mainentrance"), mem, 100000)
	check(started.size() == 2 and started[0] == fighterA and IS.getPawn(fighterA).getInteraction().id == "GenericAttack", "a visible quarrel starts a fight between them: " + str(started))
	check(DirectorScript.maybeIncident(module, IS, DirectorScript.ringOf(world, "hall_mainentrance"), mem, 100100).empty(), "and not again for hours")
	IS.stopInteractionsForPawnID(fighterA)

	# ---- The mines handler event: one button, the mine worker's shift ----
	clearPawns()
	main.setFlag("Mining_IntroducedToMinning", true)
	var mineEvent = load("res://Events/Event/MinesHandlerEvent.gd").new()
	ui.clearButtons()
	ui.clearText()
	thePlayer.addStamina(100)
	setTime(7, 0, 50)
	mineEvent.run("", [])
	var mineButtons = {}
	for option in ui.options.values():
		mineButtons[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	check(mineButtons.has("Start mining shift") and !mineButtons.has("Work") and mineButtons.size() == 1 and !mineButtons["Start mining shift"]["enabled"] and mineButtons["Start mining shift"]["tooltip"] == "You need to take the Mine worker job from the canteen job board.", "after the intro the mines show one disabled button that says where the job is: " + str(mineButtons))
	module.leaveJob()
	check(module.acceptJob("mining")["ok"], "setup: a mine worker")
	setTime(8, 30, 50)
	ui.clearButtons()
	mineEvent.run("", [])
	mineButtons = {}
	for option in ui.options.values():
		mineButtons[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	check(mineButtons.has("Start mining shift") and mineButtons["Start mining shift"]["enabled"] and mineButtons.size() == 1, "the mine worker inside the window can start the shift: " + str(mineButtons))
	setTime(11, 0, 50)
	ui.clearButtons()
	mineEvent.run("", [])
	mineButtons = {}
	for option in ui.options.values():
		mineButtons[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	check(mineButtons.has("Start mining shift") and !mineButtons["Start mining shift"]["enabled"] and mineButtons["Start mining shift"]["tooltip"].find("closed") != -1, "outside the window it is disabled and says the window is closed: " + str(mineButtons))
	main.setFlag("Mining_IntroducedToMinning", false)
	ui.clearButtons()
	mineEvent.run("", [])
	var firstTimeButtons = []
	for option in ui.options.values():
		firstTimeButtons.append(option[1])
	check(firstTimeButtons == ["Work"], "before the story introduction the vanilla first-time button is untouched: " + str(firstTimeButtons))
	module.leaveJob()

	# ---- The reputation bars on the real UI ----
	module.getState().reputation["combat"] = 6.0
	module.getState().reputation["defiance"] = -70.0
	ui.clearButtons()
	ui.clearText()
	var bars = module.addReputationBars()
	check(bars.size() == 2 and abs(bars[0].rightBar.value - 6.0) < 0.01 and abs(bars[0].leftBar.value) < 0.01 and abs(bars[1].leftBar.value - 70.0) < 0.01 and abs(bars[1].rightBar.value) < 0.01, "Combat Reputation +6 and Defiance -70 are drawn on the real screen")
	check(bars[0].valueLabel.text == "+6 — Unproven" and bars[1].valueLabel.text == "-70 — Highly compliant", "with the number and the band: " + bars[0].valueLabel.text + " / " + bars[1].valueLabel.text)
	check(bars[0].is_inside_tree() and bars[1].is_inside_tree(), "and they are part of the screen")
	ui.clearText()
	module.getState().reputation["combat"] = 0.0
	module.getState().reputation["defiance"] = 0.0

	GM.ui = null
	print("LivingPrisonBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

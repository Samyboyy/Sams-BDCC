extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/PopulationBootTest.tscn
# The prison's population stays bounded over 30 simulated days, overcrowded saves are never trimmed, and the guards' nudity flow is still connected.

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
	var ScheduleScript = load("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")

	# ============ A. The schedule on its own ============
	var line = ""
	var previous = -1
	var steady = true
	for day in range(0, 31):
		var limit = ScheduleScript.inmateLimit(day)
		line += str(day) + ":" + str(limit) + " "
		if(limit < previous or limit > ScheduleScript.INMATE_SOFT_TARGET):
			steady = false
		previous = limit
	print("POP schedule (day:limit) ", line)
	check(steady and ScheduleScript.inmateLimit(0) == ScheduleScript.INMATE_START and ScheduleScript.inmateLimit(14) <= 21 and ScheduleScript.inmateLimit(30) <= ScheduleScript.INMATE_SOFT_TARGET, "the limit starts at " + str(ScheduleScript.INMATE_START) + ", never falls, never passes the soft target, and is about " + str(ScheduleScript.inmateLimit(14)) + " on day 14")
	check(ScheduleScript.INMATE_START >= 8, "enough inmates from the start for the gangs to form")
	check(!ScheduleScript.mayAdmitInmate(30, 500) and !ScheduleScript.mayAdmitInmate(45, 500) and !ScheduleScript.mayAdmitInmate(26, 500) and ScheduleScript.mayAdmitInmate(10, 5), "nobody is admitted at or past the soft target, and never past the hard cap")
	var budgets30 = ScheduleScript.budgets(30, 40)
	var budgets90 = ScheduleScript.budgets(90, 100)
	check(budgets30["guard"] == 6 and budgets30["nurse"] == 3 and budgets30["engineer"] == 3, "at the default pawn limit (30) the staff budgets are 6, 3 and 3")
	check(budgets90["guard"] == ScheduleScript.MAX_GUARDS and budgets90["nurse"] == ScheduleScript.MAX_NURSES and budgets90["engineer"] == ScheduleScript.MAX_ENGINEERS, "and a large pawn limit (90) is held to " + str(ScheduleScript.MAX_GUARDS) + ", " + str(ScheduleScript.MAX_NURSES) + " and " + str(ScheduleScript.MAX_ENGINEERS) + " (it used to give 18, 9 and 9)")

	# ============ B. Thirty days of the real admission gate, from an empty prison ============
	for id in inmateIDs:
		main.dynamicCharacters.erase(id)
		main.removeDynamicCharacterFromAllPools(id)
		if(IS.hasPawn(id)):
			IS.deletePawn(id)
	for id in guardIDs:
		main.dynamicCharacters.erase(id)
		main.removeDynamicCharacterFromAllPools(id)
	var capsToTry = [30, 90]
	var results = {}
	for cap in capsToTry:
		OPTIONS.sandboxPawnCount = cap
		for kind in [CharacterPool.Inmates, CharacterPool.Guards, CharacterPool.Nurses, CharacterPool.Engineers]:
			for existing in main.getDynamicCharacterIDsFromPool(kind).duplicate():
				if(IS.hasPawn(existing)):
					IS.deletePawn(existing)
				main.dynamicCharacters.erase(existing)
				main.removeDynamicCharacterFromAllPools(existing)
		var table = []
		var maxInmates = 0
		var maxGuards = 0
		var maxNurses = 0
		var maxEngineers = 0
		var lastTotal = 0
		var biggestStep = 0
		for simDay in range(1, 31):
			main.currentDay = simDay
			for _attempt in range(60): # the morning wave and the spawner's tries
				for kindID in [CharacterType.Inmate, CharacterType.Guard, CharacterType.Nurse, CharacterType.Engineer]:
					if(!module.canSpawnPawnType(kindID)):
						continue
					if(kindID == CharacterType.Inmate):
						var ic = InmateGenerator.new().generate({})
						main.addDynamicCharacterToPool(ic.getID(), CharacterPool.Inmates)
					elif(kindID == CharacterType.Guard):
						var gc = GuardGenerator.new().generate({})
						main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
						IS.spawnPawn(gc.getID())
					elif(kindID == CharacterType.Nurse):
						var nc = NurseGenerator.new().generate({})
						main.addDynamicCharacterToPool(nc.getID(), CharacterPool.Nurses)
						IS.spawnPawn(nc.getID())
					else:
						var ec = EngineerGenerator.new().generate({})
						main.addDynamicCharacterToPool(ec.getID(), CharacterPool.Engineers)
						IS.spawnPawn(ec.getID())
			var inmates = main.getDynamicCharactersPoolSize(CharacterPool.Inmates)
			var guards = main.getDynamicCharactersPoolSize(CharacterPool.Guards)
			var nurses = main.getDynamicCharactersPoolSize(CharacterPool.Nurses)
			var engineers = main.getDynamicCharactersPoolSize(CharacterPool.Engineers)
			table.append([simDay, inmates, guards, nurses, engineers])
			maxInmates = max(maxInmates, inmates)
			maxGuards = max(maxGuards, guards)
			maxNurses = max(maxNurses, nurses)
			maxEngineers = max(maxEngineers, engineers)
			if(simDay > 1):
				biggestStep = max(biggestStep, inmates - lastTotal)
			lastTotal = inmates
		var text = ""
		for row in table:
			if(row[0] in [1, 2, 3, 5, 7, 10, 14, 20, 25, 30]):
				text += "d" + str(row[0]) + " " + str(row[1]) + "/" + str(row[2]) + "/" + str(row[3]) + "/" + str(row[4]) + "  "
		print("POP pawn limit ", cap, " (inmates/guards/nurses/engineers): ", text)
		results[cap] = table
		check(maxInmates <= ScheduleScript.INMATE_SOFT_TARGET and maxInmates <= ScheduleScript.INMATE_HARD_CAP, "limit " + str(cap) + ": inmates never pass the soft target (" + str(maxInmates) + ")")
		check(table[13][1] <= 21 and table[13][1] >= 10, "limit " + str(cap) + ": 45 by day 14 is gone, day 14 has " + str(table[13][1]))
		check(table[29][1] >= 20 and table[29][1] <= 26, "limit " + str(cap) + ": by day 30 about two dozen: " + str(table[29][1]))
		check(table[0][1] >= 8, "limit " + str(cap) + ": enough on the first day for gangs: " + str(table[0][1]))
		check(table[29][1] - table[13][1] <= 5, "limit " + str(cap) + ": it settles instead of racing (" + str(table[13][1]) + " to " + str(table[29][1]) + " over days 14 to 30)")
		check(maxGuards <= ScheduleScript.MAX_GUARDS and maxNurses <= ScheduleScript.MAX_NURSES and maxEngineers <= ScheduleScript.MAX_ENGINEERS, "limit " + str(cap) + ": staff stay restrained (" + str(maxGuards) + " guards, " + str(maxNurses) + " nurses, " + str(maxEngineers) + " engineers)")
		check(maxGuards >= 2 and maxNurses >= 1 and maxEngineers >= 1, "limit " + str(cap) + ": and there is staff")
		check(biggestStep <= 8, "limit " + str(cap) + ": no day brings a flood (the largest daily admission after day 1 is " + str(biggestStep) + ")")
	OPTIONS.sandboxPawnCount = 30

	# ============ C. An overcrowded save is never trimmed, and nothing new is created ============
	main.currentDay = 40
	for kind in [CharacterPool.Inmates, CharacterPool.Guards, CharacterPool.Nurses, CharacterPool.Engineers]:
		for existing2 in main.getDynamicCharacterIDsFromPool(kind).duplicate():
			if(IS.hasPawn(existing2)):
				IS.deletePawn(existing2)
			main.dynamicCharacters.erase(existing2)
			main.removeDynamicCharacterFromAllPools(existing2)
	var crowd = []
	for _n in range(45):
		var cc = InmateGenerator.new().generate({})
		main.addDynamicCharacterToPool(cc.getID(), CharacterPool.Inmates)
		crowd.append(cc.getID())
	for _n2 in range(18):
		var cg = GuardGenerator.new().generate({})
		main.addDynamicCharacterToPool(cg.getID(), CharacterPool.Guards)
		IS.spawnPawn(cg.getID())
	check(!module.canSpawnPawnType(CharacterType.Inmate) and !module.canSpawnPawnType(CharacterType.Guard) and !module.mayCreateCharacter(CharacterPool.Inmates) and !module.mayCreateCharacter(CharacterPool.Guards), "an old save with 45 inmates and 18 guards: nobody new is admitted")
	var inmatesBefore = main.getDynamicCharactersPoolSize(CharacterPool.Inmates)
	var picked = NpcFinder.generateNpcForPool(CharacterPool.Inmates, InmateGenerator.new(), {})
	check(main.getDynamicCharactersPoolSize(CharacterPool.Inmates) == inmatesBefore and crowd.has(picked), "an event that wants a new inmate meets one who is already here instead")
	var guardsBefore = main.getDynamicCharactersPoolSize(CharacterPool.Guards)
	var pickedGuard = NpcFinder.generateNpcForPool(CharacterPool.Guards, GuardGenerator.new(), {})
	check(main.getDynamicCharactersPoolSize(CharacterPool.Guards) == guardsBefore and pickedGuard != null, "and so for a guard")
	for crowdID in crowd:
		if(main.getCharacter(crowdID) == null):
			check(false, "an existing inmate was removed")
	check(main.getDynamicCharactersPoolSize(CharacterPool.Inmates) == 45, "nothing is deleted from the crowded save")
	# below the hard cap an event may still create somebody
	for crowdID2 in crowd.slice(0, 30):
		main.removeDynamicCharacterFromAllPools(crowdID2)
	check(module.mayCreateCharacter(CharacterPool.Inmates), "while the stored inmates are under the hard cap an event may still create one")

	# ============ D. The guards' nudity flow is still connected (audit only) ============
	check(module.isPlayerExposed(), "setup: the bare test player is exposed by BDCC's own check")
	thePlayer.getInventory().addItem(GlobalRegistry.createItem("inmateuniform")) # a guard only warns somebody who could dress (a loose uniform to put on)
	check(module.canPlayerDress(), "setup: the player has something to put on, so a warning makes sense")
	var guardsForAudit = []
	for _n3 in range(8):
		var ag = GuardGenerator.new().generate({})
		main.addDynamicCharacterToPool(ag.getID(), CharacterPool.Guards)
		guardsForAudit.append(ag.getID())
	for existing3 in main.getDynamicCharacterIDsFromPool(CharacterPool.Inmates).duplicate():
		main.removeDynamicCharacterFromAllPools(existing3)
	for _n4 in range(14):
		var ic2 = InmateGenerator.new().generate({})
		main.addDynamicCharacterToPool(ic2.getID(), CharacterPool.Inmates)
	var _cells = module.refreshCells()
	setClock(9, 0, 41)
	extender.director = {}
	moveTo("main_hall_west" if world.hasRoomID("main_hall_west") else "hall_canteen")
	IS.updatePCLocation()
	var _auditTick = DirectorScript.tick(module, extender.director, true)
	var warnings = 0
	var escalations = 0
	var meetings = 0
	var guardTicks = 0
	var stopKinds = []
	var hours = 24
	for _tickIndex in range(hours * 6):
		IS.processTime(600)
		main.timeOfDay += 600
		module.onPopulationTick()
		extender.securityBucket = -1
		if(module.getFreeGuards(thePlayer.location).size() > 0):
			guardTicks += 1
		module.onSecurityTick()
		for interaction in IS.interactions.duplicate():
			if(interaction.id == "GuardEnforcement" and !interaction.wasDeleted):
				stopKinds.append(interaction.state)
				meetings += 1
				if(interaction.state == "nudity_warn"):
					warnings += 1
				elif(interaction.state == "nudity_escalate"):
					escalations += 1
				IS.stopInteraction(interaction)
		endPlayerInteractions()
	print("NUDITY audit: the player stands naked in a public hall for ", hours, " in-game hours with persistent guards walking: ", meetings, " guard stops, ", warnings, " nudity warnings, ", escalations, " fines; a free guard shared the room on ", guardTicks, " of ", hours * 6, " ten-minute checks; stop kinds ", stopKinds)
	check(guardTicks >= 1, "persistent guards do share the player's room now and then (" + str(guardTicks) + " of " + str(hours * 6) + " checks)")
	check(warnings >= 1, "a naked player in a public hall is warned by a persistent guard: the nudity flow is connected and reachable (" + str(warnings) + " warnings, " + str(escalations) + " fines in " + str(hours) + " hours)")

	print("PopulationBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
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
	main.sceneStack.append(scene) # the scene is on top while it draws, as in the game: the speaker of [say=npc] lines is resolved through it
	scene._run()
	main.sceneStack.pop_back()
	check(shownText().find("!Error") == -1, "no internal error text on the " + str(scene.sceneID) + " screen")

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

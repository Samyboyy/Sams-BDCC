extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/WorkBootTest.tscn
# Real path: the real extender, module, MainScene clock and messages, Player credits and stamina, real inventory and items, the real scenes,
# real save/load. Only the map (no GM.world) is absent. Exits with code 1 on failure.

const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const UpgradesScript = preload("res://Modules/SandboxOverhaulModule/Cells/CellUpgrades.gd")

var failures = 0

# The real MainScene with the world simulation cut out of processTime: time passes and the game extender's time hook runs (as Player.processTime would).
class TestMain extends "res://Game/MainScene.gd":
	func processTime(_seconds):
		timeOfDay += int(round(_seconds))
		GlobalRegistry.getGameExtender("SandboxGameExtender").pcProcessTime(GM.pc, _seconds)

class PersistentItem extends "res://Inventory/Items/GasMask.gd":
	func isPersistent():
		return true

class FakeInteraction:
	var id = "InStocks"
	var goal = null

class FakeScene:
	var sceneID = "NpcOwnerEventRunnerScene"

class FakeRoom extends Node2D:
	var roomID = ""

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

func setTime(hours, minutes = 0, day = 0):
	main.timeOfDay = int(hours * 3600 + minutes * 60)
	main.currentDay = day

# The real GameUI keeps the drawn buttons in options (index -> [enabled, text, tooltip, ...]); this turns them into text -> {enabled, tooltip}.
func buttonMap(ui) -> Dictionary:
	var result = {}
	for option in ui.options.values():
		result[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	return result

func uiText(ui) -> String:
	return ui.textOutput.bbcode_text

# How many places hold an item with this unique ID: the player's inventory (carried and worn), the stash and the hidden compartment.
func countUnique(uid) -> int:
	var n = 0
	var inv = thePlayer.getInventory()
	for item in inv.getItems():
		if(item.uniqueID == uid):
			n += 1
	for item in inv.getEquippedItems().values():
		if(item.uniqueID == uid):
			n += 1
	for item in module.getStash().getAllItems():
		if(item.uniqueID == uid):
			n += 1
	for record in module.getStoredRecords(true):
		if(record["uniqueID"] == uid):
			n += 1
	return n

func stashIDs() -> Array:
	var ids = []
	for item in module.getStash().getAllItems():
		ids.append(item.uniqueID)
	ids.sort()
	return ids

func messagesText() -> String:
	return PoolStringArray(main.getMessages()).join("\n")

func newScene(path):
	var scene = load(path).new()
	scene._initScene([])
	return scene

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = TestMain.new()
	GM.main = main
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	var eventSystem = EventSystem.new()
	add_child(eventSystem)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	check(module != null and GlobalRegistry.getWorldEdit("SandboxWorkWorldEdit") != null, "module and world edit registered")
	for path in ["JobBoardScene", "WorkShiftScene", "CellUpgradesScene"]:
		check(GlobalRegistry.getSceneCreator(path) != null, path + " is registered")
	var emp = SandboxOverhaulModule.getEmployment()
	var ups = SandboxOverhaulModule.getUpgrades()

	# ---- A new game: unemployed, nothing bought ----
	check(!emp.isEmployed() and emp.getWarnings() == 0 and JSON.print(module.getPurchasedUpgrades()) == JSON.print(UpgradesScript.defaults()), "a new game is unemployed with nothing bought")
	check(!module.isShiftCompleteToday() and module.getEmploymentState()["job"] == "" and module.getStoredRecords(false).empty() and module.getStoredRecords(true).empty(), "the API shows no job, no shift and empty stores")
	check(module.getWorkScreenText().find("job board") != -1, "the Me screen points at the job board")

	# ---- World edit: job board, workplaces and the cell ----
	var world = FakeWorld.new()
	var edit = GlobalRegistry.getWorldEdit("SandboxWorkWorldEdit")
	for roomID in ["hall_canteen", "mining_shafts_entering", "eng_workshop", "main_laundry", "cellblock_orange_playercell", "cellblock_red_playercell", "cellblock_pink_playercell"]:
		var room = FakeRoom.new()
		room.roomID = roomID
		world.rooms[roomID] = room
	edit.applyAll(world)
	edit.applyAll(world)
	check(world.rooms["hall_canteen"].get_child_count() == 1 and world.rooms["eng_workshop"].get_child_count() == 1 and world.rooms["cellblock_orange_playercell"].get_child_count() == 1, "each action is added once however often the edit applies")
	var board = world.rooms["hall_canteen"].get_node("SandboxJobBoard")
	var shiftMining = world.rooms["mining_shafts_entering"].get_node("SandboxStartShift")
	var shiftLaundry = world.rooms["main_laundry"].get_node("SandboxStartShift")
	var upgradesAction = world.rooms["cellblock_orange_playercell"].get_node("SandboxCellUpgrades")
	check(board.ActionScene == "JobBoardScene" and shiftMining.ActionScene == "WorkShiftScene" and upgradesAction.ActionScene == "CellUpgradesScene" and board.ActionName == "Job board" and shiftMining.ActionName == "Start shift", "the actions open the module scenes")
	check(board._shouldShow(), "the job board is always there")
	check(!shiftMining._shouldShow() and !shiftLaundry._shouldShow(), "no Start shift without a job")
	thePlayer.location = "cellblock_orange_playercell"
	check(upgradesAction._shouldShow(), "the cell upgrades show in the player's own cell")
	thePlayer.location = "cellblock_orange_nearcell"
	check(!upgradesAction._shouldShow(), "but not in the hall")

	# ---- The job board scene ----
	setTime(7, 0, 3)
	var boardScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/JobBoardScene.gd")
	boardScene._react("confirmaccept", ["mining"])
	check(boardScene.state == "confirmaccept" and boardScene.pendingJob == "mining" and !emp.isEmployed(), "choosing a job asks for confirmation and does not take it")
	boardScene._react("", [])
	check(boardScene.state == "" and !emp.isEmployed(), "cancelling takes nothing")
	boardScene._react("confirmaccept", ["mining"])
	boardScene._react("doaccept", [])
	check(boardScene.state == "result" and emp.getJobID() == "mining" and boardScene.resultText.find("Mine worker") != -1 and emp.hasOpenShift(3), "confirming takes the job")
	boardScene._react("", [])
	boardScene._react("confirmaccept", ["laundry"])
	boardScene._react("doaccept", [])
	check(emp.getJobID() == "mining" and boardScene.resultText.find("already have a job") != -1, "a second job is refused with a reason")
	boardScene._react("", [])
	boardScene._react("confirmleave", [])
	check(boardScene.state == "confirmleave" and emp.isEmployed(), "leaving asks for confirmation")
	boardScene._react("doleave", [])
	check(!emp.isEmployed() and boardScene.resultText == "You gave up your job.", "confirming leaves the job")

	# ---- Shift: wage, balance, stamina, time ----
	boardScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/JobBoardScene.gd")
	boardScene._react("confirmaccept", ["mining"])
	boardScene._react("doaccept", [])
	check(emp.getJobID() == "mining", "rehired for the shift")
	thePlayer.location = "mining_shafts_entering"
	check(shiftMining._shouldShow() and !shiftLaundry._shouldShow(), "Start shift shows at the player's own workplace only")
	var credits = thePlayer.getCredits()
	check(!module.startShift("mining")["ok"] and thePlayer.getCredits() == credits and !emp.isShiftCompleteToday(3), "before the window opens nothing is paid")
	main.clearMessages()
	setTime(8, 0, 3)
	module.onWorkTick()
	check(messagesText().find("Work:") != -1 and messagesText().find("shift can start") != -1, "a reminder when the window opens: " + messagesText())
	main.clearMessages()
	module.onWorkTick()
	check(main.getMessages().empty(), "only one reminder")
	check(module.getWorkScreenText().find("ready to start") != -1, "the Me screen shows the shift is ready")
	thePlayer.addStamina(-thePlayer.getStamina())
	check(!module.startShift("mining")["ok"] and thePlayer.getCredits() == credits and !emp.isShiftCompleteToday(3), "too tired to work: nothing is paid and the shift stays open")
	thePlayer.addStamina(100)
	var shiftScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd")
	setTime(8, 30, 3)
	var timeBefore = main.timeOfDay
	shiftScene._react("start", [])
	check(thePlayer.getCredits() == credits + 3, "the wage of 3 credits is paid: " + str(thePlayer.getCredits() - credits))
	check(thePlayer.getStamina() == 100 - 40, "the existing mining stamina cost is used: " + str(thePlayer.getStamina()))
	check(main.timeOfDay == timeBefore + 2 * 3600, "about two hours pass: " + str(main.timeOfDay - timeBefore))
	check(emp.isShiftCompleteToday(3) and module.isShiftCompleteToday() and shiftScene.resultText.find("3 credits") != -1 and shiftScene.resultText.find(str(credits + 3)) != -1, "the result shows the wage and the new balance: " + shiftScene.resultText)
	check(messagesText().find("Shift pay: 3 credits. You now have " + str(credits + 3)) != -1, "and so does the message")
	check(emp.getHistory()["completed"] == 1 and emp.getHistory()["wages"] == 3 and emp.getWarnings() == 0, "the shift is recorded")
	var again = module.startShift("mining")
	check(!again["ok"] and thePlayer.getCredits() == credits + 3, "no second payment the same day")
	shiftScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd")
	shiftScene._react("start", [])
	check(thePlayer.getCredits() == credits + 3, "the scene cannot pay twice either")
	module.onWorkTick()
	check(emp.getWarnings() == 0 and emp.getHistory()["missed"] == 0, "a finished shift is not missed when the window closes")

	# ---- No job switching farming ----
	var _l = module.leaveJob()
	var swap = module.acceptJob("workshop")
	check(swap["ok"] and emp.getJobID() == "workshop" and !emp.hasOpenShift(3) and !module.startShift("workshop")["ok"] and thePlayer.getCredits() == credits + 3, "switching jobs the same day gives no second shift")
	var _l2 = module.leaveJob()
	check(emp.getHistory()["completed"] == 1 and emp.getHistory()["wages"] == 3, "leaving keeps the history")

	# ---- Informal mining pays once a day ----
	check(module.getInformalMiningPay() == 1 and module.getInformalMiningPay() == 0 and module.getInformalMiningPay() == 0, "the vanilla credit is paid once a day")
	setTime(7, 0, 4)
	check(module.getInformalMiningPay() == 1, "and again the next day")
	var mines = load("res://Scenes/Mineshaft/WorkInMinesScene.gd").new()
	setTime(7, 0, 5)
	credits = thePlayer.getCredits()
	mines._react("work", [])
	check(thePlayer.getCredits() == credits + 1, "the mining scene pays the first session of the day")
	mines = load("res://Scenes/Mineshaft/WorkInMinesScene.gd").new()
	setTime(7, 0, 5)
	main.clearMessages()
	mines._react("work", [])
	mines._react("work", [])
	check(thePlayer.getCredits() == credits + 1 and messagesText().find("earned nothing") != -1, "more sessions the same day still mine but pay nothing, and say so")
	setTime(7, 0, 6)
	credits = thePlayer.getCredits()
	_l = module.acceptJob("mining")
	setTime(8, 30, 6)
	thePlayer.addStamina(100)
	check(module.startShift("mining")["ok"] and thePlayer.getCredits() == credits + 3, "the shift pays its wage")
	setTime(11, 0, 6)
	mines._react("work", [])
	check(thePlayer.getCredits() == credits + 3 + 1, "and the informal mining credit is still paid, once, on top")
	_l = module.leaveJob()

	# ---- Missed, excused, dismissed through the real clock ----
	_l = module.acceptJob("laundry")
	setTime(7, 0, 10)
	module.onWorkTick()
	main.clearMessages()
	setTime(14, 5, 10)
	module.onWorkTick()
	check(emp.getWarnings() == 1 and emp.getShiftStatus(10) == "missed" and messagesText().find("missed your Laundry hand shift") != -1 and messagesText().find("Warning 1 of 3") != -1, "an unexcused miss adds a warning and says so: " + messagesText())
	# stocks
	var pawn = CharacterPawn.new()
	pawn.charID = "pc"
	main.IS.pawns["pc"] = pawn
	pawn.currentInteraction = FakeInteraction.new()
	check(module.getBlockedReason() == "locked in the stocks", "the stocks block going to work: " + module.getBlockedReason())
	setTime(7, 0, 11)
	module.onWorkTick()
	main.clearMessages()
	setTime(14, 5, 11)
	module.onWorkTick()
	check(emp.getWarnings() == 1 and emp.getShiftStatus(11) == "excused" and emp.getHistory()["excused"] == 1 and messagesText().find("excused") != -1 and messagesText().find("locked in the stocks") != -1, "stuck in the stocks at the deadline is excused: no warning: " + messagesText())
	pawn.currentInteraction = null
	check(module.getBlockedReason() == "", "free again")
	main.PS = load("res://Game/PlayerSlavery/PlayerSlaveryBase.gd").new()
	check(module.getBlockedReason() == "serving as a slave", "player slavery blocks")
	main.PS = null
	main.sceneStack.append(FakeScene.new())
	check(module.getBlockedReason() == "kept busy by your owner", "an owner scene blocks")
	main.sceneStack.clear()
	main.IS.pawns.erase("pc")
	# external excuse
	setTime(7, 0, 12)
	module.onWorkTick()
	main.clearMessages()
	check(module.recordExcusedAbsence("held at the infirmary") and emp.getShiftStatus(12) == "excused" and messagesText().find("held at the infirmary") != -1 and !module.recordExcusedAbsence("again") and emp.getWarnings() == 1, "another module can excuse today's shift once")
	# dismissal
	setTime(7, 0, 13)
	module.onWorkTick()
	setTime(14, 1, 13)
	main.clearMessages()
	module.onWorkTick()
	check(emp.getWarnings() == 2 and emp.isEmployed(), "second warning")
	setTime(7, 0, 14)
	module.onWorkTick()
	setTime(15, 0, 14)
	main.clearMessages()
	module.onWorkTick()
	check(!emp.isEmployed() and emp.isDismissed(14) and emp.getReapplyDay() == 17 and messagesText().find("dismissed") != -1 and messagesText().find("day 17") != -1, "three warnings dismiss: " + messagesText())
	check(module.getWorkScreenText().find("dismissed") != -1 and module.getWorkScreenText().find("day 17") != -1, "the Me screen says when to apply again")
	check(!module.acceptJob("mining")["ok"], "no new job during the wait")
	setTime(6, 0, 17)
	main.clearMessages()
	module.onWorkTick()
	check(messagesText().find("apply for a job again") != -1 and module.acceptJob("mining")["ok"], "after three days you are told you can reapply, and can")
	_l = module.leaveJob()
	check(emp.getHistory()["completed"] == 2 and emp.getHistory()["missed"] == 3 and emp.getHistory()["excused"] == 2 and emp.getHistory()["dismissals"] == 1, "the whole history is kept: " + JSON.print(emp.getHistory()))

	# ---- The hook is wired to the real extender ----
	_l = module.acceptJob("mining")
	setTime(7, 0, 20)
	module.onWorkTick()
	setTime(10, 5, 20)
	main.clearMessages()
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	extender.pcProcessTime(thePlayer, 60)
	check(emp.getShiftStatus(20) == "missed" and messagesText().find("missed") != -1, "the extender's pcProcessTime drives the work clock")
	_l = module.leaveJob()

	# ---- The free pillow stash is the vanilla stash, shared with the cell screen ----
	var stashChar = GlobalRegistry.createStaticCharacter("playerstash")
	add_child(stashChar)
	main.staticCharacters["playerstash"] = stashChar
	var stash = stashChar.getInventory()
	var inv = thePlayer.getInventory()
	var vanilla = load("res://Scenes/PlayerStashScene.gd").new()
	var carried = {}
	for itemID in ["appleitem", "Condom", "GasMask", "PermanentMarker", "lube", "EnergyDrink"]:
		var made = GlobalRegistry.createItem(itemID)
		if(itemID == "appleitem"):
			made.setAmount(5)
		inv.addItem(made)
		carried[itemID] = made
	check(module.getStash() == stash and module.getStashUsed() == 0 and module.getStoredRecords(false).empty() and module.getStashStatusText().find("0 of 4") != -1, "the module reads the real playerstash inventory, empty at the start with 4 stacks of room")
	vanilla._react("hideallitems", ["appleitem"])
	vanilla._react("hideallitems", ["Condom"])
	vanilla._react("hideallitems", ["GasMask"])
	check(stash.getItemByUniqueID(carried["appleitem"].uniqueID) == carried["appleitem"] and !inv.hasItem(carried["appleitem"]) and module.getStashUsed() == 3, "a deposit through the vanilla scene moves the real item into the stash")
	var seen = {}
	for record in module.getStoredRecords(false):
		seen[record["uniqueID"]] = record["id"]
	check(seen.size() == 3 and seen[carried["appleitem"].uniqueID] == "appleitem" and seen[carried["Condom"].uniqueID] == "Condom" and seen[carried["GasMask"].uniqueID] == "GasMask", "and the cell screen's list shows the same three items")
	check(module.depositItem(carried["PermanentMarker"], false) == "" and stash.getItemByUniqueID(carried["PermanentMarker"].uniqueID) == carried["PermanentMarker"] and module.getStashUsed() == 4 and !inv.hasItem(carried["PermanentMarker"]), "a deposit through the cell screen lands in the same stash")
	var markerSeen = false
	for item in stash.getAllItems():
		if(item.id == "PermanentMarker"):
			markerSeen = true
	check(markerSeen and module.getStashStatusText().find("4 of 4") != -1, "so the vanilla stash lists it too")
	main.clearMessages()
	var lube = carried["lube"]
	check(module.getStashDepositRefusal(lube).find("full") != -1 and module.depositItem(lube, false).find("full") != -1 and inv.hasItem(lube) and module.getStashUsed() == 4, "with the module the free capacity is 4 stacks: the cell screen refuses a fifth")
	vanilla._react("hideallitems", ["lube"])
	check(inv.hasItem(lube) and !stash.hasItem(lube) and messagesText().find("full") != -1, "and so does the vanilla scene, with a message")
	vanilla.state = "hideitemmenu"
	main.clearMessages()
	vanilla.onInventoryItemInteracted(lube)
	check(inv.hasItem(lube) and !stash.hasItem(lube) and messagesText().find("full") != -1, "also from the inventory screen")
	var apples2 = GlobalRegistry.createItem("appleitem")
	apples2.setAmount(3)
	inv.addItem(apples2)
	vanilla._react("stashx", [apples2, 1])
	check(stash.getFirstOf("appleitem").getAmount() == 6 and apples2.getAmount() == 2 and inv.hasItem(apples2) and module.getStashUsed() == 4, "a stack that merges into an existing one still fits when full (vanilla split)")
	check(module.depositItem(apples2, false) == "" and stash.getFirstOf("appleitem").getAmount() == 8 and !inv.hasItem(apples2) and module.getStashUsed() == 4 and !inv.hasItem(apples2), "and from the cell screen")
	check(countUnique(carried["appleitem"].uniqueID) == 1 and countUnique(carried["Condom"].uniqueID) == 1 and countUnique(lube.uniqueID) == 1, "nothing is duplicated")
	var stashBefore = stashIDs()
	check(module.withdrawItem("nope", false) == "It is not in there." and stashIDs() == stashBefore, "a failed withdrawal changes nothing")
	var condomID = carried["Condom"].uniqueID
	vanilla._react("takeallitems", ["Condom"])
	check(inv.getItemByUniqueID(condomID) == carried["Condom"] and !stash.hasItem(carried["Condom"]) and countUnique(condomID) == 1 and module.getStashUsed() == 3, "a vanilla withdrawal gives back the same item and the cell screen no longer lists it")
	var gasMaskID = carried["GasMask"].uniqueID
	check(module.withdrawItem(gasMaskID, false) == "" and inv.getItemByUniqueID(gasMaskID) == carried["GasMask"] and countUnique(gasMaskID) == 1 and module.getStashUsed() == 2, "a cell screen withdrawal removes the same underlying item")
	var energy = carried["EnergyDrink"]
	check(module.depositItem(lube, false) == "" and module.depositItem(energy, false) == "" and module.getStashUsed() == 4, "refill the stash to 4")
	check(module.getStashDepositRefusal(carried["GasMask"]) != "", "full again")

	# Without the module the vanilla stash is unlimited
	var moduleRef = GlobalRegistry.modules["SandboxOverhaulModule"]
	GlobalRegistry.modules.erase("SandboxOverhaulModule")
	check(vanilla.getStashRefusal(carried["GasMask"]) == "", "without the module the stash scene never refuses")
	vanilla._react("hideallitems", ["GasMask"])
	check(stash.getAllItems().size() == 5 and stash.hasItem(carried["GasMask"]), "a fifth stack goes in as in vanilla")
	GlobalRegistry.modules["SandboxOverhaulModule"] = moduleRef

	# An old save with more than the capacity: nothing is lost, withdrawals work, deposits are refused
	var overIDs = stashIDs()
	check(module.getStashUsed() == 5 and module.getStashStatusText().find("over capacity") != -1, "five stacks in a stash of four are over capacity")
	var extraItem = GlobalRegistry.createItem("PlasticBottle")
	inv.addItem(extraItem)
	main.clearMessages()
	check(module.depositItem(extraItem, false).find("more than it fits") != -1 and inv.hasItem(extraItem) and stashIDs() == overIDs, "over capacity: a new deposit is refused with an explanation and nothing moves")
	vanilla._react("hideallitems", ["PlasticBottle"])
	check(inv.hasItem(extraItem) and stashIDs() == overIDs and messagesText().find("more than it fits") != -1, "the vanilla scene refuses it too")
	check(module.getStashStatusText().find("take things out") != -1, "the status text tells the player they can take things out")
	var idsBeforeBuy = stashIDs()

	# ---- Upgrades: purchases charge once ----
	thePlayer.addCredits(-thePlayer.getCredits())
	thePlayer.addCredits(8)
	var shortBuy = module.buyUpgrade("storage")
	check(!shortBuy["ok"] and thePlayer.getCredits() == 8 and !ups.owns("storage"), "too poor: nothing charged, nothing bought")
	thePlayer.addCredits(1)
	var buy = module.buyUpgrade("storage")
	check(buy["ok"] and thePlayer.getCredits() == 0 and ups.owns("storage"), "bought for exactly 9 credits")
	thePlayer.addCredits(50)
	var twice = module.buyUpgrade("storage")
	check(!twice["ok"] and thePlayer.getCredits() == 50 and !module.buyUpgrade("nonsense")["ok"] and thePlayer.getCredits() == 50, "no double charge, no charge for nothing")
	var upScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/CellUpgradesScene.gd")
	upScene._react("confirmbuy", ["hidden"])
	check(upScene.state == "confirmbuy" and !ups.owns("hidden") and thePlayer.getCredits() == 50, "the scene asks first")
	upScene._react("", [])
	check(!ups.owns("hidden") and thePlayer.getCredits() == 50, "cancelling costs nothing")
	upScene._react("confirmbuy", ["hidden"])
	upScene._react("dobuy", [])
	check(ups.owns("hidden") and thePlayer.getCredits() == 38 and upScene.state == "" and upScene.note.find("38 credits") != -1, "confirming charges once: " + str(thePlayer.getCredits()))
	upScene._react("dobuy", [])
	check(thePlayer.getCredits() == 38, "repeating the confirmation charges nothing more")

	# ---- The locker raises the same stash, the hidden compartment is separate ----
	check(ups.owns("storage") and ups.getStashCapacity() == 12 and ups.owns("hidden"), "the locker and the hidden compartment are installed")
	check(stashIDs() == idsBeforeBuy and module.getStashUsed() == 5, "buying the locker disturbed nothing in the stash")
	check(module.getStashStatusText().find("5 of 12") != -1 and module.getStashStatusText().find("over capacity") == -1, "the same stash now shows 12 stacks")
	check(module.depositItem(extraItem, false) == "" and stash.hasItem(extraItem) and module.getStashUsed() == 6, "a deposit through the cell screen uses the new capacity")
	var apples3 = GlobalRegistry.createItem("appleitem")
	inv.addItem(apples3)
	main.clearMessages()
	vanilla._react("hideallitems", ["appleitem"])
	check(stash.getAllItems().size() == 6 and messagesText() == "" and !inv.hasItem(apples3), "the vanilla scene uses the same stash (the apples merge into the stack already there)")
	var mask = GlobalRegistry.createItem("GasMask")
	inv.addItem(mask)
	var gag = GlobalRegistry.createItem("ballgag")
	inv.addItem(gag)
	var worn = GlobalRegistry.createItem("GasMask")
	inv.addItem(worn)
	var _eq = inv.equipItem(worn)
	check(inv.getEquippedItems().values().has(worn) and !inv.hasItem(worn), "setup: one mask is worn")
	check(module.getStoreRefusal(mask) == "" and module.getStoreRefusal(worn).find("wearing") != -1 and module.getStoreRefusal(gag) == "" and module.getStoreRefusal(null) != "", "worn items are refused with a reason, a loose restraint is not")
	var cage = GlobalRegistry.createItem("ChastityCageAdvanced")
	inv.addItem(cage)
	check(module.getStoreRefusal(cage) != "", "important items are refused")
	var stashNow = stashIDs()
	check(module.depositItem(worn, false).find("wearing") != -1 and module.depositItem(cage, false) != "" and module.depositItem(worn, true) != "" and stashIDs() == stashNow and module.getStoredRecords(true).empty(), "refused items go nowhere in either store")
	# Loose restraints are ordinary inventory items: they can be stored, a worn one cannot
	gag.restraintData.level = 3
	gag.restraintData.tightness = 0.7
	var gagID = gag.uniqueID
	var gagData = JSON.print(gag.saveData())
	check(module.getStashDepositRefusal(gag) == "" and module.getDepositRefusal(gag, true) == "", "a loose restraint is allowed in both stores")
	check(module.depositItem(gag, false) == "" and stash.getItemByUniqueID(gagID) == gag and !inv.hasItem(gag) and countUnique(gagID) == 1, "a loose restraint goes into the stash")
	check(JSON.print(gag.saveData()) == gagData and gag.restraintData.level == 3, "and keeps its saved data")
	check(module.withdrawItem(gagID, false) == "" and inv.getItemByUniqueID(gagID) == gag and JSON.print(gag.saveData()) == gagData and countUnique(gagID) == 1, "and comes back unchanged")
	var gag2 = GlobalRegistry.createItem("ballgag")
	inv.addItem(gag2)
	gag2.restraintData.level = 4
	gag2.restraintData.tightness = 0.4
	var gag2ID = gag2.uniqueID
	check(module.depositItem(gag2, true) == "" and !inv.hasItem(gag2) and countUnique(gag2ID) == 1 and !stash.hasItem(gag2), "a loose restraint goes into the hidden compartment")
	check(module.getStoredRecords(true)[0]["data"]["restraintData"]["level"] == 4 and abs(module.getStoredRecords(true)[0]["data"]["restraintData"]["tightness"] - 0.4) < 0.001, "the hidden record keeps its restraint data")
	check(module.withdrawItem(gag2ID, true) == "" and inv.getItemByUniqueID(gag2ID) != null and countUnique(gag2ID) == 1 and inv.getItemByUniqueID(gag2ID).restraintData.level == 4 and abs(inv.getItemByUniqueID(gag2ID).restraintData.tightness - 0.4) < 0.001, "and is rebuilt from it without losing data")
	var gag3 = GlobalRegistry.createItem("ballgag")
	inv.addItem(gag3)
	var _eq3 = inv.equipItem(gag3)
	check(inv.getEquippedItems().values().has(gag3) and module.getStoreRefusal(gag3) != "" and module.depositItem(gag3, false) != "" and module.depositItem(gag3, true) != "" and inv.getEquippedItems().values().has(gag3) and countUnique(gag3.uniqueID) == 1, "a worn restraint is refused by both stores and stays worn")
	check(gag3.isWornByWearer() == (gag3.getWearer() == thePlayer and inv.getEquippedItem(gag3.getClothingSlotSafe()) == gag3), "BDCC's own worn check agrees with the equipped slots")
	var persistent = PersistentItem.new()
	persistent.uniqueID = "persist1"
	inv.addItem(persistent)
	check(module.getStoreRefusal(persistent) != "" and module.depositItem(persistent, false) != "" and module.depositItem(persistent, true) != "" and inv.hasItem(persistent), "persistent items are still refused")
	check(module.getStoreRefusal(cage) != "" and module.depositItem(cage, true) != "" and inv.hasItem(cage), "important items are still refused")
	inv.removeItem(persistent)
	var uniqueMask = mask.uniqueID
	check(module.depositItem(mask, true) == "" and !inv.hasItem(mask) and countUnique(uniqueMask) == 1 and !stash.hasItem(mask), "the hidden compartment takes an item (as a record, not in the stash)")
	var hiddenRecord = module.getStoredRecords(true)[0]
	check(hiddenRecord["id"] == "GasMask" and hiddenRecord["uniqueID"] == uniqueMask, "the hidden record keeps the item's ID and data")
	var ordinaryIDs = []
	for record in module.getStoredRecords(false):
		ordinaryIDs.append(record["uniqueID"])
	check(!ordinaryIDs.has(uniqueMask) and module.getStoredRecords(true).size() == 1 and module.getStoredRecords(false).size() == 6, "ordinary and hidden storage are queried separately")
	check(module.withdrawItem(uniqueMask, false) == "It is not in there." and module.withdrawItem("nope", true) == "It is not in there." and module.getStoredRecords(true).size() == 1, "each store only gives back its own things")
	var bottleHidden = GlobalRegistry.createItem("PlasticBottle")
	inv.addItem(bottleHidden)
	var bottleID = bottleHidden.uniqueID
	check(module.depositItem(bottleHidden, true) == "" and module.withdrawItem(bottleID, true) == "" and inv.getItemByUniqueID(bottleID) != null and countUnique(bottleID) == 1 and module.getStoredRecords(true).size() == 1, "a hidden item can be put in and taken out again")
	# over even the upgraded capacity
	for _i in range(8):
		var filler = GlobalRegistry.createItem("GasMask")
		stash.addItem(filler)
	check(module.getStashUsed() == 14, "setup: an old stash with 14 stacks")
	var fourteen = stashIDs()
	var one = GlobalRegistry.createItem("PlasticBottle")
	inv.addItem(one)
	check(module.getStashDepositRefusal(one).find("more than it fits") != -1 and module.getStashDepositRefusal(one).find("locker") == -1 and module.depositItem(one, false) != "" and stashIDs() == fourteen, "still over the upgraded capacity: refused, nothing removed")
	var firstID = fourteen[0]
	check(module.withdrawItem(firstID, false) == "" and module.getStashUsed() == 13 and countUnique(firstID) == 1, "but withdrawing works")
	check(module.depositItem(one, false) != "" and module.getStashUsed() == 13, "still refused at 13")
	check(module.withdrawItem(stashIDs()[0], false) == "" and module.getStashUsed() == 12 and module.depositItem(one, false).find("full") != -1, "at exactly 12 it is full, not over capacity")
	check(module.withdrawItem(stashIDs()[0], false) == "" and module.depositItem(one, false) == "" and module.getStashUsed() == 11 + 1 and countUnique(one.uniqueID) == 1, "once it is back under the limit deposits work again")
	# comfort
	check(module.afterRestInOwnCell(3600 * 4) == 0, "no better bedding yet, no bonus")
	thePlayer.addCredits(50)
	var comfort = module.buyUpgrade("comfort")
	check(comfort["ok"] and ups.owns("comfort"), "bought the bedding")
	thePlayer.location = "cellblock_orange_nearcell"
	thePlayer.addStamina(-thePlayer.getStamina())
	thePlayer.addStamina(10)
	check(module.afterRestInOwnCell(3600 * 4) == 0 and thePlayer.getStamina() == 10, "no bonus outside the player's own cell")
	thePlayer.location = thePlayer.getCellLocation()
	var staminaNow = thePlayer.getStamina()
	var bonus = module.afterRestInOwnCell(3600 * 4)
	check(bonus == 20 and thePlayer.getStamina() == staminaNow + 20, "resting 4 hours in the own cell gives half again as much: " + str(bonus))

	# ---- The scenes draw what they should ----
	var ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	_l = module.leaveJob()
	setTime(9, 0, 40)
	module.onWorkTick()
	boardScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/JobBoardScene.gd")
	boardScene._run()
	check(buttonMap(ui)["Take: Mine worker"]["enabled"] and buttonMap(ui)["Take: Workshop hand"]["enabled"] and buttonMap(ui)["Take: Laundry hand"]["enabled"] and !buttonMap(ui).has("Leave job") and uiText(ui).find("pay 3 credits") != -1 and uiText(ui).find("10:00-12:00") != -1, "the board lists the jobs with pay and window, and offers to take any")
	_l = module.acceptJob("mining")
	ui.clearButtons()
	ui.clearText()
	boardScene._run()
	check(!buttonMap(ui)["Take: Laundry hand"]["enabled"] and buttonMap(ui)["Take: Laundry hand"]["tooltip"].find("already have a job") != -1 and buttonMap(ui)["Leave job"]["enabled"], "with a job the others are disabled with a reason and Leave job appears")
	boardScene.state = "confirmaccept"
	boardScene.pendingJob = "workshop"
	ui.clearButtons()
	boardScene._run()
	check(buttonMap(ui).has("Take the job") and buttonMap(ui).has("Cancel"), "the confirmation has both choices")
	thePlayer.location = "mining_shafts_entering"
	shiftScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd")
	ui.clearButtons()
	shiftScene._run()
	check(buttonMap(ui)["Start shift"]["enabled"] and buttonMap(ui)["Start shift"]["tooltip"].find("3 credits") != -1, "Start shift is offered inside the window")
	setTime(11, 0, 40)
	ui.clearButtons()
	shiftScene._run()
	check(!buttonMap(ui)["Start shift"]["enabled"] and buttonMap(ui)["Start shift"]["tooltip"].find("closed") != -1, "and disabled after it with the reason")
	thePlayer.location = "main_laundry"
	ui.clearButtons()
	ui.clearText()
	shiftScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/WorkShiftScene.gd")
	shiftScene._run()
	check(uiText(ui).find("not your workplace") != -1 and !buttonMap(ui).has("Start shift"), "another workplace says so")
	thePlayer.location = thePlayer.getCellLocation()
	upScene = newScene("res://Modules/SandboxOverhaulModule/Scenes/CellUpgradesScene.gd")
	ui.clearButtons()
	ui.clearText()
	upScene._run()
	check(uiText(ui).find("Personal locker") != -1 and uiText(ui).find("Hidden compartment") != -1 and uiText(ui).find("Better bedding") != -1 and uiText(ui).find("of 12 stacks") != -1 and buttonMap(ui).has("Cell stash") and !buttonMap(ui)["Personal locker"]["enabled"] and buttonMap(ui).has("Hidden compartment") and !buttonMap(ui)["Better bedding"]["enabled"], "the upgrades screen lists the three upgrades; owned ones can be used")
	upScene.state = "storage"
	upScene.hidden = true
	ui.clearButtons()
	ui.clearText()
	upScene._run()
	check(uiText(ui).find("1 of 3 slots") != -1 and uiText(ui).find("harder to find") != -1 and buttonMap(ui).has("Put something in"), "the hidden compartment explains why protection will matter")
	upScene.state = "deposit"
	ui.clearButtons()
	upScene._run()
	check(buttonMap(ui).has("Back"), "the deposit list draws")
	ui.queue_free()
	GM.ui = null

	# ---- Save and load ----
	_l = module.leaveJob()
	_l = module.acceptJob("laundry")
	setTime(12, 0, 30)
	module.onWorkTick()
	setTime(13, 0, 30)
	var _w = module.startShift("laundry")
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	var sb = saved["extendersData"]["SandboxGameExtender"]
	check(sb["schema_version"] == 5 and sb["work"]["job"] == "laundry" and sb["work"]["history"]["completed"] == 3 and sb["upgrades"]["storage"] == true and !sb.has("storage") and sb["hidden_storage"].size() == 1, "saved at schema 5 with the job, upgrades and the hidden compartment (the stash is not duplicated)")
	var workBefore = JSON.print(SandboxOverhaulModule.getState().work)
	var _w2 = module.withdrawItem(stashIDs()[0], false)
	var saveGag = GlobalRegistry.createItem("ballgag")
	inv.addItem(saveGag)
	saveGag.restraintData.level = 5
	var saveGagID = saveGag.uniqueID
	check(module.depositItem(saveGag, false) == "" and stash.getItemByUniqueID(saveGagID) == saveGag, "setup: a loose restraint sits in the stash at save time")
	var stashSaved = JSON.parse(JSON.print(stashChar.saveData())).result
	var stashSnapshot = stashIDs()
	SandboxOverhaulModule.getState().clear()
	check(!SandboxOverhaulModule.getEmployment().isEmployed() and !SandboxOverhaulModule.getUpgrades().owns("storage"), "cleared")
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(JSON.print(SandboxOverhaulModule.getState().work) == workBefore and SandboxOverhaulModule.getEmployment().getJobID() == "laundry" and module.isShiftCompleteToday(), "the job, shift and history survive a load")
	check(SandboxOverhaulModule.getUpgrades().owns("storage") and SandboxOverhaulModule.getUpgrades().owns("hidden") and SandboxOverhaulModule.getUpgrades().owns("comfort"), "the upgrades survive")
	check(module.getStoredRecords(true).size() == 1 and stashIDs() == stashSnapshot, "the hidden compartment survives, the stash is untouched by loading the sandbox state")
	stashChar.loadData(JSON.parse(JSON.print(stashSaved)).result)
	check(stashIDs() == stashSnapshot and module.getStashUsed() == stashSnapshot.size(), "the stash survives BDCC's own save and load")
	stashChar.loadData(JSON.parse(JSON.print(stashSaved)).result)
	stashChar.loadData(JSON.parse(JSON.print(stashSaved)).result)
	var noDupes = true
	for uid in stashSnapshot:
		if(countUnique(uid) != 1):
			noDupes = false
	check(noDupes and stashIDs() == stashSnapshot, "loading again and again duplicates and destroys nothing")
	var loadedGag = stash.getItemByUniqueID(saveGagID)
	check(loadedGag != null and loadedGag.restraintData.level == 5 and countUnique(saveGagID) == 1, "the loose restraint is in the stash exactly once after loading, with its data")
	check(module.withdrawItem(mask.uniqueID, true) == "" and inv.getItemByUniqueID(mask.uniqueID) != null and module.getStoredRecords(true).empty(), "a loaded stored item can be taken out")
	var oldCredits = thePlayer.getCredits()
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(thePlayer.getCredits() == oldCredits and module.getStoredRecords(true).size() == 1, "loading restores the stores, not the player's credits (those come from the player's own save)")

	# ---- Old saves ----
	SandboxOverhaulModule.getState().loadData({"schema_version": 3, "reputation": {"combat": 4.0, "defiance": 0.0}})
	check(SandboxOverhaulModule.getState().schema_version == 5 and !SandboxOverhaulModule.getEmployment().isEmployed() and !SandboxOverhaulModule.getUpgrades().owns("storage"), "a version 3 save is unemployed with no upgrades")
	check(SandboxOverhaulModule.getCombat().getCombatReputation() == 4.0, "and keeps what it had")

	# ---- New game ----
	_l = module.acceptJob("mining")
	var _buy2 = module.buyUpgrade("storage")
	var main2 = load("res://Game/MainScene.gd").new()
	GM.main = main2
	check(!SandboxOverhaulModule.getEmployment().isEmployed() and SandboxOverhaulModule.getEmployment().getHistory()["completed"] == 0 and !SandboxOverhaulModule.getUpgrades().owns("storage") and SandboxOverhaulModule.getState().hidden_storage.empty(), "a new game resets the job, history, upgrades and the hidden compartment")

	GM.main = null
	GM.pc = null
	GM.ES = null
	stashChar.free()
	eventSystem.free()
	thePlayer.free()
	for room in world.rooms.values():
		room.free()
	main.free()
	main2.free()
	print("WorkBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

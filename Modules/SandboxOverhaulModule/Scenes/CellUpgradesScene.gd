extends SceneBase

# Upgrades for the player's own cell: buy them, and use the storage locker and the hidden compartment. Opened from "Cell upgrades" in the player's cell.

const UpgradesScript = preload("res://Modules/SandboxOverhaulModule/Cells/CellUpgrades.gd")
const PAGE_SIZE = 9

var pendingUpgrade:String = ""
var hidden:bool = false
var page:int = 0
var note:String = ""

func _init():
	sceneID = "CellUpgradesScene"

func _run():
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var upgrades = module.getUpgrades()
	if(note != ""):
		saynn(note)
		note = ""
	if(state == ""):
		saynn("[b]Cell upgrades[/b]\nYou have " + str(GM.pc.getCredits()) + " credits. " + module.getStashStatusText())
		for upgradeID in UpgradesScript.ORDER:
			var upgrade:Dictionary = UpgradesScript.UPGRADES[upgradeID]
			sayn("[b]" + upgrade["name"] + "[/b] (" + ("owned" if upgrades.owns(upgradeID) else str(upgrade["price"]) + " credits") + "): " + upgrade["text"])
		sayn("")
		addButton("Cell stash", "The stash under your pillow. It is ordinary storage, the same one as in your cell menu.", "open", [false])
		for upgradeID in UpgradesScript.ORDER:
			var upgrade:Dictionary = UpgradesScript.UPGRADES[upgradeID]
			if(upgrades.owns(upgradeID)):
				if(upgradeID == "hidden"):
					addButton(upgrade["name"], "Use it", "open", [true])
				else:
					addDisabledButton(upgrade["name"], "Already installed.")
			else:
				var check:Dictionary = upgrades.canBuy(upgradeID, GM.pc.getCredits())
				if(check["ok"]):
					addButton("Buy: " + upgrade["name"], str(upgrade["price"]) + " credits", "confirmbuy", [upgradeID])
				else:
					addDisabledButton("Buy: " + upgrade["name"], check["reason"])
		addButton("Leave", "Done", "endthescene")
	if(state == "confirmbuy"):
		var upgrade:Dictionary = UpgradesScript.UPGRADES[pendingUpgrade]
		saynn("Buy [b]" + upgrade["name"] + "[/b] for " + str(upgrade["price"]) + " credits? You have " + str(GM.pc.getCredits()) + ".")
		addButton("Buy", "Pay once and have it installed", "dobuy")
		addButton("Cancel", "Not now", "")
	if(state == "storage"):
		var records:Array = module.getStoredRecords(hidden)
		if(hidden):
			saynn("[b]Hidden compartment[/b] - " + str(records.size()) + " of " + str(UpgradesScript.HIDDEN_SLOTS) + " slots used.")
			saynn("Nothing searches cells yet. When guards start, what is in here will be much harder to find than what is in the stash or the locker.")
		else:
			saynn("[b]Cell stash[/b]\n" + module.getStashStatusText() + " This is ordinary storage: it is the same stash as under your pillow, and it does not hide anything from searches.")
		if(records.empty()):
			saynn("It is empty.")
		for record in records:
			addButton("Take: " + recordName(record), "Take it back, exactly as you left it", "withdraw", [record["uniqueID"]])
		addButton("Put something in", "Choose a carried item to store", "deposit")
		addButton("Back", "Back to the upgrades", "")
	if(state == "deposit"):
		var items:Array = GM.pc.getInventory().getItems()
		saynn("What do you want to put away? " + (str(upgrades.getFreeSlots()) + " free slots." if hidden else module.getStashStatusText()) + " Worn items have to be taken off first. Each stack takes one slot.")
		var pages:int = int(max(1, ceil(float(items.size()) / PAGE_SIZE)))
		page = int(clamp(page, 0, pages - 1))
		for i in range(page * PAGE_SIZE, int(min(items.size(), (page + 1) * PAGE_SIZE))):
			var item = items[i]
			var reason:String = module.getDepositRefusal(item, hidden)
			if(reason == ""):
				addButton(item.getVisibleName() + (" x" + str(item.getAmount()) if item.getAmount() > 1 else ""), "Put it away", "dodeposit", [item.uniqueID])
			else:
				addDisabledButton(item.getVisibleName(), reason)
		if(page > 0):
			addButton("Previous page", "Earlier items", "prevpage")
		if(page + 1 < pages):
			addButton("Next page", "Later items", "nextpage")
		addButton("Back", "Done putting things away", "storage")

func recordName(record:Dictionary) -> String:
	var item = GlobalRegistry.createItem(record["id"], false)
	if(item == null):
		return str(record["id"])
	item.loadData(record["data"])
	return item.getVisibleName() + (" x" + str(item.getAmount()) if item.getAmount() > 1 else "")

func _react(_action: String, _args):
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "confirmbuy"):
		pendingUpgrade = str(_args[0])
	if(_action == "dobuy"):
		var result:Dictionary = module.buyUpgrade(pendingUpgrade)
		if(result["ok"]):
			note = "You bought [b]" + UpgradesScript.UPGRADES[pendingUpgrade]["name"] + "[/b]. You now have " + str(GM.pc.getCredits()) + " credits."
		else:
			note = result["reason"]
		setState("")
		return
	if(_action == "open"):
		hidden = bool(_args[0])
		setState("storage")
		return
	if(_action == "deposit"):
		page = 0
	if(_action == "nextpage"):
		page += 1
		setState("deposit")
		return
	if(_action == "prevpage"):
		page = int(max(0, page - 1))
		setState("deposit")
		return
	if(_action == "dodeposit"):
		var item = GM.pc.getInventory().getItemByUniqueID(str(_args[0]))
		var itemName:String = item.getVisibleName() if item != null else "That"
		var reason:String = module.depositItem(item, hidden)
		note = (itemName + " is put away.") if reason == "" else reason
		setState("deposit")
		return
	if(_action == "withdraw"):
		var reason:String = module.withdrawItem(str(_args[0]), hidden)
		note = "You take it back." if reason == "" else reason
		setState("storage")
		return
	setState(_action)

func saveData():
	var data = .saveData()
	data["pendingUpgrade"] = pendingUpgrade
	data["hidden"] = hidden
	data["page"] = page
	return data

func loadData(_data):
	.loadData(_data)
	pendingUpgrade = SAVE.loadVar(_data, "pendingUpgrade", "")
	hidden = SAVE.loadVar(_data, "hidden", false)
	page = SAVE.loadVar(_data, "page", 0)

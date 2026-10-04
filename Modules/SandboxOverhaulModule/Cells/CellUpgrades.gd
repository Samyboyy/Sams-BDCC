extends Reference
class_name CellUpgrades

# Upgrades for the player's own cell: personal storage, a hidden compartment and better bedding. No game access here, so it can be tested on its own.
#
# SandboxState.upgrades = {"storage": bool (the personal locker), "hidden": bool, "comfort": bool}
# SandboxState.hidden_storage = [{"id": item id, "uniqueID": String, "data": ItemBase.saveData()}, ...]
# A record is exactly what Inventory.saveData() keeps for an item, so nothing about an item (amount, state, colour, fluids...) is lost.
# Each record is one slot. Stacks go in whole. The ordinary storage is not stored here: it is the vanilla pillow stash (see below).

const UPGRADES = {
	"storage": {"name": "Personal locker", "price": 9, "slots": 12,
		"text": "A lockable footlocker bolted under your bunk. Your cell stash (the pillow stash) then holds 12 stacks of items instead of 4. Everything already in it stays. It is ordinary storage: it does not hide anything from searches."},
	"hidden": {"name": "Hidden compartment", "price": 12, "slots": 3,
		"text": "A loose panel behind the toilet pipes. Holds up to 3 stacks of items. Nothing searches cells yet, but once guards do, anything in here will be much harder to find than anything in the locker or under your pillow."},
	"comfort": {"name": "Better bedding", "price": 12, "slots": 0,
		"text": "A spare mattress layer and a real blanket. Resting in your own cell restores half again as much stamina."},
}
const ORDER = ["storage", "hidden", "comfort"]
const STASH_BASE_SLOTS = 4 # what the free pillow stash holds with the module active
const HIDDEN_SLOTS = 3
const COMFORT_REST_BONUS = 0.5 # extra stamina from resting in the player's own cell, as a share of the normal amount

var state

func _init(_state):
	state = _state

# ---- Pure helpers ----
static func isValidUpgrade(upgradeID) -> bool:
	return (upgradeID is String) && UPGRADES.has(upgradeID)

static func price(upgradeID:String) -> int:
	return int(UPGRADES[upgradeID]["price"])

static func defaults() -> Dictionary:
	return {"storage": false, "hidden": false, "comfort": false}

# Only true values for known upgrades count. Nothing is aliased.
static func sanitizeUpgrades(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(raw is Dictionary):
		for key in result:
			result[key] = typeof(raw.get(key)) == TYPE_BOOL && raw[key]
	return result

static func isValidRecord(record) -> bool:
	return (record is Dictionary) && (record.get("id") is String) && record["id"] != "" && (record.get("uniqueID") is String) && (record.get("data") is Dictionary)

# Valid records only, at most `capacity` of them (the first ones win), unique IDs only. Never aliases the input.
static func sanitizeRecords(raw, capacity:int) -> Array:
	var result:Array = []
	var seen:Dictionary = {}
	if(!(raw is Array)):
		return result
	for record in raw:
		if(result.size() >= capacity):
			break
		if(!isValidRecord(record) || seen.has(record["uniqueID"])):
			continue
		seen[record["uniqueID"]] = true
		result.append({"id": record["id"], "uniqueID": record["uniqueID"], "data": record["data"].duplicate(true)})
	return result

# ---- Upgrades ----
func owns(upgradeID) -> bool:
	return isValidUpgrade(upgradeID) && state.upgrades.get(upgradeID, false)

func getOwned() -> Dictionary:
	return state.upgrades.duplicate(true)

# Whether the upgrade can be bought with this many credits, and why not. Does not change anything.
func canBuy(upgradeID, credits:int) -> Dictionary:
	if(!isValidUpgrade(upgradeID)):
		return {"ok": false, "reason": "There is no such upgrade."}
	if(owns(upgradeID)):
		return {"ok": false, "reason": "You already have this."}
	if(credits < price(upgradeID)):
		return {"ok": false, "reason": "You need " + str(price(upgradeID)) + " credits."}
	return {"ok": true, "reason": ""}

# Marks the upgrade as owned. The caller has already checked canBuy and charges the price in the same step, so a purchase is all or nothing.
func markOwned(upgradeID) -> bool:
	if(!isValidUpgrade(upgradeID) || owns(upgradeID)):
		return false
	state.upgrades[upgradeID] = true
	return true

# ---- Cell stash (the vanilla pillow stash) ----
# The ordinary storage is BDCC's own "playerstash" character inventory, not a copy. Here is only the capacity rule. A stack that merges into
# an existing stack needs no new slot. Items already inside are never touched: when the stash holds more than it fits, nothing is removed,
# withdrawals work and only new stacks are refused.
func getStashCapacity() -> int:
	return int(UPGRADES["storage"]["slots"]) if owns("storage") else STASH_BASE_SLOTS

# "" when the stash can take the item, otherwise why not.
func stashRefusal(used:int, needsNewSlot:bool) -> String:
	if(!needsNewSlot):
		return ""
	var capacity:int = getStashCapacity()
	if(used > capacity):
		return "Your stash holds more than it fits (" + str(used) + " of " + str(capacity) + " stacks). Take something out first" + ("." if owns("storage") else ", or buy the personal locker.")
	if(used >= capacity):
		return "Your stash is full (" + str(used) + " of " + str(capacity) + " stacks)" + ("." if owns("storage") else ". The personal locker would hold more.")
	return ""

func stashStatusText(used:int) -> String:
	var capacity:int = getStashCapacity()
	var text:String = "Cell stash: " + str(used) + " of " + str(capacity) + " stacks used."
	if(used > capacity):
		text += " It is over capacity: you can take things out, but nothing new fits until it holds fewer than " + str(capacity) + " stacks" + ("." if owns("storage") else " (or buy the personal locker).")
	elif(!owns("storage")):
		text += " The personal locker raises this to " + str(UPGRADES["storage"]["slots"]) + "."
	return text

# ---- Hidden compartment (module-owned records) ----
func getRecords() -> Array:
	return state.hidden_storage.duplicate(true)

func getFreeSlots() -> int:
	return int(max(0, HIDDEN_SLOTS - state.hidden_storage.size()))

# "" when the record fits, otherwise why not.
func canStore(record) -> String:
	if(!owns("hidden")):
		return "You do not have this upgrade."
	if(!isValidRecord(record)):
		return "That item cannot be stored."
	if(getFreeSlots() <= 0):
		return "It is full."
	if(hasRecord(record["uniqueID"])):
		return "That item is already in there."
	return ""

# Adds a copy of the record. Returns "" on success or the reason it was refused (nothing changes then).
func store(record) -> String:
	var reason:String = canStore(record)
	if(reason != ""):
		return reason
	state.hidden_storage.append({"id": record["id"], "uniqueID": record["uniqueID"], "data": record["data"].duplicate(true)})
	return ""

func hasRecord(uniqueID:String) -> bool:
	for existing in state.hidden_storage:
		if(existing["uniqueID"] == uniqueID):
			return true
	return false

# Removes and returns the record, or {} when it is not there.
func take(uniqueID:String) -> Dictionary:
	for i in range(state.hidden_storage.size()):
		if(state.hidden_storage[i]["uniqueID"] == uniqueID):
			var record:Dictionary = state.hidden_storage[i]
			state.hidden_storage.remove(i)
			return record
	return {}

# Extra stamina for a rest: the bonus share of what the rest gave, rounded down. Zero without the upgrade.
func restBonus(baseStamina:float) -> int:
	if(!owns("comfort") || baseStamina <= 0.0):
		return 0
	return int(floor(baseStamina * COMFORT_REST_BONUS))

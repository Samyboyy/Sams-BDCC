extends Reference
class_name GuardSearches

# What a search takes. No game access: the caller describes each item as an entry and removes the chosen ones itself.
# An entry is {"key": unique ID, "name": text, "amount": int, "illegal": bool, "protected": bool}.
#   illegal   = BDCC's own contraband classification (ItemTag.Illegal)
#   protected = important, persistent or otherwise not safely removable: never confiscated, even if illegal

const SecurityScript = preload("res://Modules/SandboxOverhaulModule/Security/Security.gd")

static func isConfiscatable(entry) -> bool:
	return (entry is Dictionary) && entry.get("illegal", false) == true && entry.get("protected", false) != true && (entry.get("key") is String) && entry["key"] != ""

# The entries a search takes, in order, each key once. Everything else stays.
static func selectConfiscations(entries:Array) -> Array:
	var result:Array = []
	var seen:Dictionary = {}
	for entry in entries:
		if(!isConfiscatable(entry) || seen.has(entry["key"])):
			continue
		seen[entry["key"]] = true
		result.append(entry)
	return result

static func entryName(entry) -> String:
	var name:String = str(entry.get("name", "an item"))
	var amount:int = int(entry.get("amount", 1))
	return name + (" x" + str(amount) if amount > 1 else "")

static func describe(entries:Array) -> String:
	var names:Array = []
	for entry in entries:
		names.append(entryName(entry))
	return PoolStringArray(names).join(", ")

# A search of the cell. Ordinary storage is always searched. The hidden compartment is only found by a targeted search and only on a lucky roll (12%);
# a failed roll reveals nothing. Returns {"stash": [...], "hidden": [...], "foundHidden": bool}.
static func cellSearch(stashEntries:Array, hiddenEntries:Array, targeted:bool, hiddenRoll:float) -> Dictionary:
	var result:Dictionary = {"stash": selectConfiscations(stashEntries), "hidden": [], "foundHidden": false}
	if(targeted && hiddenRoll < SecurityScript.HIDDEN_DISCOVERY_CHANCE):
		result["foundHidden"] = true
		result["hidden"] = selectConfiscations(hiddenEntries)
	return result

# ---- Messages ----
static func personalSearchMessage(guardName:String, taken:Array, fine:int, attentionLine:String) -> String:
	if(taken.empty()):
		return SecurityScript.colored(guardName + " searched you and found nothing.", "green")
	var text:String = SecurityScript.colored(guardName + " searched you and confiscated: " + describe(taken) + ".", "red")
	if(fine > 0):
		text += " " + SecurityScript.colored(str(fine) + " credit" + ("s" if fine != 1 else "") + " taken as a fine.", "red")
	if(attentionLine != ""):
		text += " " + attentionLine
	return text

static func cellSearchMessage(result:Dictionary, fine:int, attentionLine:String) -> String:
	var taken:Array = []
	taken.append_array(result["stash"])
	taken.append_array(result["hidden"])
	if(taken.empty()):
		return SecurityScript.colored("While you were out, guards searched your cell and found nothing.", "green")
	var text:String = SecurityScript.colored("While you were out, guards searched your cell and confiscated: " + describe(taken) + ".", "red")
	if(!result["hidden"].empty()):
		text += " " + SecurityScript.colored("They found your hidden compartment.", "red")
	if(fine > 0):
		text += " " + SecurityScript.colored(str(fine) + " credit" + ("s" if fine != 1 else "") + " taken as a fine.", "red")
	if(attentionLine != ""):
		text += " " + attentionLine
	return text

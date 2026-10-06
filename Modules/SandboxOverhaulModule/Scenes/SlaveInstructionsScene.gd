extends SceneBase

# "Give instructions": the one place where the player manages somebody they own, in person. It does not depend on the slave's mood for ordinary conversation (chat and flirting can be refused; this cannot),
# only on real physical blockers (see OwnershipGame.instructionsBlock). A slave who has just been enslaved waits for a first set of instructions: a role, where they sleep at night, and a confirmation
# ("Those are your instructions." or "I'll decide later." - then they keep waiting, shown as "Awaiting instructions" on the Ownership screen, and this is never reopened on its own).
# Later changes use the same screens and take effect a little later, not on the spot. The slave answers in character from how they feel (trust, fear, respect, affection).
#
# args: [slaveID]

const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const TextScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipText.gd")

var npcID:String = ""
var pendingRole:String = "free"
var pendingNight:String = "own"
var wizard:bool = false
var note:String = ""

func _init():
	sceneID = "SlaveInstructionsScene"

func _initScene(_args = []):
	npcID = str(_args[0]) if (_args is Array && _args.size() > 0) else ""
	var rec:Dictionary = svc().slaveRecord(npcID) if OwnershipGameScript.isReady() else {}
	if(!rec.empty()):
		pendingRole = str(rec["role"])
		pendingNight = str(rec["night"])
		wizard = rec["setup"] == "awaiting"
	if(wizard):
		state = "role"

func svc():
	return OwnershipGameScript.svc()

func nameOf(id) -> String:
	return OwnershipGameScript.nameOf(id)

func resolveCustomCharacterName(_charID):
	if(_charID == "npc"):
		return npcID

func supportsShowingPawns() -> bool:
	return true

func _run():
	if(!OwnershipGameScript.isReady() || !svc().hasSlave(npcID)):
		saynn("They are not your slave.")
		addButton("Back", "Never mind", "endthescene")
		return
	addCharacter(npcID)
	playAnimation(StageScene.Duo, "stand", {npc=npcID})
	if(note != ""):
		saynn(note)
		note = ""
	var block:String = OwnershipGameScript.instructionsBlock(npcID)
	if(block != ""):
		saynn(block)
		addButton("Back", "Never mind", "endthescene")
		return
	match(state):
		"role":
			roleScreen()
		"night":
			nightScreen()
		"confirm":
			confirmScreen()
		_:
			hub()

func disposition() -> String:
	return OwnershipGameScript.slaveDisposition(npcID)

func rec() -> Dictionary:
	return svc().slaveRecord(npcID)

# ---- The hub ----
func hub() -> void:
	var r:Dictionary = rec()
	saynn("[b]" + nameOf(npcID) + "[/b]\n" + OwnershipGameScript.slaveArrangementText(npcID) + "\n[color=#c8c8d8]" + str(OwnershipScript.DISPOSITION_TEXT[disposition()]) + "[/color]")
	if(r["setup"] == "awaiting"):
		saynn("[color=yellow]They are still waiting for your instructions.[/color]")
	addButton("Role", "What they are expected to do", "role")
	addButton("Sleeping arrangement", "Where they sleep at night", "night")
	var report = GlobalRegistry.getSlaveAction("SbxActionReport")
	var reportCheck:Array = report.checkCanDo(npcID)
	if(reportCheck[0]):
		addButton("Report to my cell", "A one-off order for this evening: they walk to your cell", "report")
	else:
		addDisabledButton("Report to my cell", str(reportCheck[1]))
	addButton("How are they coping?", "Ask how they are getting on", "coping")
	var credits = GlobalRegistry.getSlaveAction("SbxRewardCredits")
	var creditsCheck:Array = credits.checkCanDo(npcID)
	if(creditsCheck[0]):
		addButton("Reward", "Give them a little credit for good work", "reward")
	else:
		addDisabledButton("Reward", str(creditsCheck[1]))
	var treat = GlobalRegistry.getSlaveAction("SbxRewardTreat")
	var treatCheck:Array = treat.checkCanDo(npcID)
	if(treatCheck[0]):
		addButton("Look after them", "Treat their injuries or let them rest", "treat")
	else:
		addDisabledButton("Look after them", str(treatCheck[1]))
	addButton("Discuss release", "Talk about letting them go", "release_talk")
	addButton("Release them", "Free them and let them leave your cell", "release")
	addButton("Full slave menu", "BDCC's own slave menu", "full_menu")
	addButtonAt(14, "Back", "Done here", "endthescene")

# ---- Role ----
func roleScreen() -> void:
	var lines:Array = []
	for roleID in OwnershipScript.ROLES:
		var mark:String = " [color=cyan](current)[/color]" if (roleID == str(rec()["role"]) && !wizard) else ""
		lines.append("[b]" + str(OwnershipScript.ROLE_NAMES[roleID]) + "[/b]" + mark + "\n\"" + str(OwnershipScript.ROLE_TEXT[roleID]) + "\"\n[color=#c8c8d8]" + str(OwnershipScript.ROLE_EFFECT[roleID]) + "[/color]")
	saynn("[b]Role[/b]\nThese are standing arrangements. They follow them as part of their day; you do not summon them.\n\n" + PoolStringArray(lines).join("\n\n"))
	if(!wizard && !svc().canChangeRole(npcID, OwnershipGameScript.today())):
		saynn("[color=#c8c8d8]Their role was already changed today.[/color]")
	for roleID in OwnershipScript.ROLES:
		var changeable:bool = wizard || (roleID != str(rec()["role"]) && svc().canChangeRole(npcID, OwnershipGameScript.today()))
		if(changeable):
			addButton(str(OwnershipScript.ROLE_NAMES[roleID]), str(OwnershipScript.ROLE_TEXT[roleID]), "pick_role", [roleID])
		else:
			addDisabledButton(str(OwnershipScript.ROLE_NAMES[roleID]), "Already their role, or changed today")
	addButtonAt(14, "Back", "Back", "" if !wizard else "endthescene")

# ---- Night ----
func nightScreen() -> void:
	var lines:Array = []
	for nightID in OwnershipScript.NIGHTS:
		var mark:String = " [color=cyan](current)[/color]" if (nightID == str(rec()["night"]) && !wizard) else ""
		lines.append("[b]" + str(OwnershipScript.NIGHT_NAMES[nightID]) + "[/b]" + mark + "\n\"" + str(OwnershipScript.NIGHT_TEXT[nightID]) + "\"")
	saynn("[b]Sleeping arrangement[/b]\nIf they sleep in your cell they start walking over in the evening (from 20:30) and leave in the morning when they wake. Their own cell stays theirs.\n\n" + PoolStringArray(lines).join("\n\n"))
	for nightID in OwnershipScript.NIGHTS:
		addButton(str(OwnershipScript.NIGHT_NAMES[nightID]), str(OwnershipScript.NIGHT_TEXT[nightID]), "pick_night", [nightID])
	addButtonAt(14, "Back", "Back", "" if !wizard else "role")

# ---- Confirm (first instructions) ----
func confirmScreen() -> void:
	saynn("[b]Your instructions to " + nameOf(npcID) + "[/b]\n[b]Role:[/b] " + str(OwnershipScript.ROLE_NAMES[pendingRole]) + " - \"" + str(OwnershipScript.ROLE_TEXT[pendingRole]) + "\"\n[b]Nights:[/b] \"" + str(OwnershipScript.NIGHT_TEXT[pendingNight]) + "\"")
	addButton("Those are your instructions.", "Give them", "confirm")
	addButton("I'll decide later.", "They keep waiting", "later")
	addButtonAt(14, "Back", "Change something", "night")

# ---- Replies, in character ----
func accepts(role:String, night:String) -> Array:
	var d:String = disposition()
	if(!OwnershipScript.willDo(role, d)):
		return [false, TextScript.refuseDuty(role, d)]
	if(night == "player" && !OwnershipScript.willDo("report", d)):
		return [false, TextScript.refuseDuty("night", d)]
	return [true, ""]

func acceptLine() -> String:
	match(disposition()):
		"loyal":
			return "Of course. I will do as you say."
		"intimidated":
			return "...Yes. As you say."
		"resentful":
			return "Fine."
		"defiant":
			return "Whatever."
		"recovering":
			return "All right. That sounds fair."
	return "I will try."

func _react(_action: String, _args):
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "full_menu"):
		runScene("SlaveTalkScene", [npcID])
		return
	if(_action == "release"):
		runScene("ActionSlaveryFreeSlaveScene", [npcID])
		return
	if(!OwnershipGameScript.isReady() || !svc().hasSlave(npcID)):
		return
	var s = svc()
	var day:int = OwnershipGameScript.today()
	var clock:int = OwnershipGameScript.clockNow()
	match(_action):
		"pick_role":
			var role:String = str(_args[0])
			if(wizard):
				pendingRole = role
				setState("night")
				return
			var verdict:Array = accepts(role, "own")
			if(!bool(verdict[0])):
				note = "You tell {npc.name} what you expect.\n\n[say=npc]" + str(verdict[1]) + "[/say]\n\n[color=#c8c8d8]They refuse. Treat them better, or look after their trust, and ask again.[/color]"
			elif(s.setRole(npcID, role, day, clock)):
				note = "You give {npc.name} a new role: " + str(OwnershipScript.ROLE_NAMES[role]) + ".\n\n[say=npc]" + acceptLine() + "[/say]\n\n[color=#c8c8d8]" + str(OwnershipScript.ROLE_TEXT[role]) + " It starts in about half an hour, not on the spot.[/color]"
			setState("")
			return
		"pick_night":
			var night:String = str(_args[0])
			if(wizard):
				pendingNight = night
				setState("confirm")
				return
			var nightVerdict:Array = accepts(str(rec()["role"]), night)
			if(!bool(nightVerdict[0])):
				note = "You tell {npc.name} where you want {npc.him} to sleep.\n\n[say=npc]" + str(nightVerdict[1]) + "[/say]\n\n[color=#c8c8d8]They refuse. Treat them better and ask again.[/color]"
			elif(s.setNight(npcID, night)):
				note = "You tell {npc.name}: \"" + str(OwnershipScript.NIGHT_TEXT[night]) + "\"\n\n[say=npc]" + acceptLine() + "[/say]"
			setState("")
			return
		"confirm":
			var verdict2:Array = accepts(pendingRole, pendingNight)
			if(!bool(verdict2[0])):
				note = "You give {npc.name} {npc.his} instructions.\n\n[say=npc]" + str(verdict2[1]) + "[/say]\n\n[color=#c8c8d8]They will not do that. Choose something else, or treat them better first.[/color]"
				setState("role")
				return
			var _ok:bool = s.giveInstructions(npcID, pendingRole, pendingNight, day, clock)
			GM.main.addMessage(nameOf(npcID) + " has their instructions: " + str(OwnershipScript.ROLE_NAMES[pendingRole]) + "; " + str(OwnershipScript.NIGHT_NAMES[pendingNight]).to_lower() + ".")
			endScene()
			return
		"later":
			GM.main.addMessage(nameOf(npcID) + " will wait for your instructions. The Ownership screen shows who is still waiting.")
			endScene()
			return
		"report":
			var result:Dictionary = GlobalRegistry.getSlaveAction("SbxActionReport").doActionSimple(npcID)
			note = str(result.get("text", ""))
			setState("")
			return
		"coping":
			var coping:Dictionary = GlobalRegistry.getSlaveAction("SbxTalkRole").doActionSimple(npcID)
			note = str(coping.get("text", ""))
			setState("")
			return
		"reward":
			var rewarded:Dictionary = GlobalRegistry.getSlaveAction("SbxRewardCredits").doActionSimple(npcID)
			note = str(rewarded.get("text", ""))
			setState("")
			return
		"treat":
			var treated:Dictionary = GlobalRegistry.getSlaveAction("SbxRewardTreat").doActionSimple(npcID)
			note = str(treated.get("text", ""))
			setState("")
			return
		"release_talk":
			var talked:Dictionary = GlobalRegistry.getSlaveAction("SbxTalkRelease").doActionSimple(npcID)
			note = str(talked.get("text", ""))
			setState("")
			return
	setState(_action)

func saveData():
	var data = .saveData()
	data["npcID"] = npcID
	data["pendingRole"] = pendingRole
	data["pendingNight"] = pendingNight
	data["wizard"] = wizard
	data["note"] = note
	return data

func loadData(_data):
	.loadData(_data)
	npcID = SAVE.loadVar(_data, "npcID", "")
	pendingRole = SAVE.loadVar(_data, "pendingRole", "free")
	pendingNight = SAVE.loadVar(_data, "pendingNight", "own")
	wizard = SAVE.loadVar(_data, "wizard", false)
	note = SAVE.loadVar(_data, "note", "")

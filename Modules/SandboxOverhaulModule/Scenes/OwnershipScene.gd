extends SceneBase

# Me > Ownership, and asking an inmate for protection. One scene, two entry points: args [] = the overview, args ["protection", characterID] = asking that character to look after the player.
#
# The overview is information only (who owns you and on what terms, how protected you are, the ways out; and a short list of the people you own, each opening BDCC's own slave menu).
# Everything that actually changes anything (reporting in, demands, release, what a slave does) happens in person, through the owner's own talk menu and the slave menu.

const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")
const TextScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipText.gd")

const DISPOSITION_COLORS = {"loyal": "green", "recovering": "cyan", "uncertain": "#c8c8d8", "intimidated": "yellow", "resentful": "orange", "defiant": "red"}

var mode:String = ""
var npcID:String = ""
var note:String = ""

func _init():
	sceneID = "OwnershipScene"

func _initScene(_args = []):
	mode = str(_args[0]) if (_args is Array && _args.size() > 0) else ""
	npcID = str(_args[1]) if (_args is Array && _args.size() > 1) else ""
	if(mode == "protection"):
		state = "protection"

func svc():
	return OwnershipGameScript.svc()

func nameOf(id) -> String:
	return OwnershipGameScript.nameOf(id)

func resolveCustomCharacterName(_charID):
	if(_charID == "npc"):
		return npcID # the candidate or the slave is the speaker of [say=npc] lines

func _run():
	OwnershipGameScript.reconcile()
	if(npcID != "" && (mode == "protection")):
		addCharacter(npcID)
	if(note != ""):
		saynn(note)
		note = ""
	if(state == ""):
		overview()
	elif(state == "routes"):
		routes()
	elif(state == "protection"):
		protection()
	elif(state == "protection_confirm"):
		protectionConfirm()
	elif(state == "started"):
		started()
	elif(state == "help"):
		help()

# ---- The overview ----
func overview() -> void:
	var s = svc()
	var shown:bool = false
	if(s.hasOwner()):
		shown = true
		saynn("[b]You are owned[/b]\n" + PoolStringArray(OwnershipGameScript.summaryLines()).join("\n"))
		saynn("[color=#c8c8d8]Check-ins, demands and anything to do with ending this happen in person: find your owner, and use their talk menu. Their cell is shown above.[/color]")
		addButton("Ways out", "How you could get free, and what each would take", "routes")
	var slaves:Array = s.slaveIDs()
	if(!slaves.empty()):
		shown = true
		saynn("[b]Your slaves[/b]")
		for id in slaves:
			saynn(slaveLine(id))
		var earners:int = 0
		for id in slaves:
			if(svc().slaveRecord(id)["role"] == "earner"):
				earners += 1
		if(earners >= 2):
			saynn("[color=#c8c8d8]Several earners share the same few customers, so each brings in less: the first up to 4 credits a day, the second up to 3, the rest about 1, and never more than 8 credits a day from all of them together.[/color]")
		saynn("[color=#c8c8d8]To give one of them an order, find them and talk to them (Slave). Orders are only given in person: picking one here shows where they are and what they are doing, and the full slave menu opens only when they are standing in front of you.[/color]")
		for id in slaves:
			addButton(nameOf(id), "Open the slave menu for " + nameOf(id), "slave", [id])
	if(!shown):
		saynn("[b]Ownership[/b]\nNobody owns you, and you own nobody. If you ever want somebody to look after you, you can ask a strong inmate for protection when you talk to them. You are told their terms first and nothing happens until you agree.")
	addButton("How ownership works", "Being owned, owning slaves, and how to get a slave", "help")
	addButton("Back", "Close", "endthescene")

func slaveLine(id:String) -> String:
	var s = svc()
	var rec:Dictionary = s.slaveRecord(id)
	var d:String = OwnershipGameScript.slaveDisposition(id)
	var word:String = d.capitalize()
	var color:String = str(DISPOSITION_COLORS.get(d, "#c8c8d8"))
	var line:String = "[b]" + nameOf(id) + "[/b] - " + OwnershipGameScript.slaveArrangementText(id) + " - " + OwnershipGameScript.slaveLocationText(id) + " (" + OwnershipGameScript.slaveActivityText(id) + ")" + (" - on the way to " + OwnershipGameScript.slaveDestinationText(id) if OwnershipGameScript.slaveDestinationText(id) != "" else "") + " - [color=" + color + "]" + word + "[/color]"
	if(rec["setup"] == "awaiting"):
		line += " - [color=yellow]awaiting instructions[/color]"
	var injury:String = OwnershipGameScript.slaveInjuryText(id)
	if(injury != "none"):
		line += " - injury: " + injury
	if(int(rec["uncollected"]) > 0):
		line += " - [color=yellow]" + str(rec["uncollected"]) + " credits to collect[/color]"
	if(!rec["escape"].empty()):
		line += " - [color=red]planning to run[/color]"
	return line

# ---- Help ----
func help() -> void:
	saynn("[b]How ownership works[/b]")
	saynn("[b]Being owned.[/b] An owner has a style (lenient, controlling or harsh) that sets how often they expect you at their cell at night (between 21:00 and 23:00), how often they make demands, how hard they push back and how well they protect you. Check-ins and demands are done in person. Missing them brings a warning first, then consequences. You can get free by negotiating (after the minimum term), buying your way out, beating the owner on separate days, a gang's help, or the owner letting go.")
	saynn("[b]Protection.[/b] A credible owner makes attacks on you less likely, and may step in when you are attacked: at most once every two days, only if they are free, awake, not badly hurt and close enough to hear. The overview says when that is ready.")
	saynn("[b]Owning slaves.[/b] Slaves stay in the prison as people with cells and daily plans. Talk to one and choose Give instructions: a role, where they sleep at night, rewards and release. Orders are only given in person.")
	saynn("[b]How to get a slave.[/b]\n" + OwnershipGameScript.acquisitionHelp())
	addButton("Back", "Back to the overview", "")

# ---- The ways out ----
func routes() -> void:
	var s = svc()
	if(!s.hasOwner()):
		saynn("You are not owned.")
		addButton("Back", "Back", "")
		return
	var lines:Array = []
	for route in OwnershipGameScript.releaseRoutes():
		var mark:String = "[color=green]available[/color]" if route["available"] else "[color=#a0a0a0]not yet[/color]"
		lines.append("[b]" + str(route["name"]) + "[/b] (" + mark + ")\n" + str(route["text"]))
	saynn("[b]Ways out[/b]\n\n" + PoolStringArray(lines).join("\n\n"))
	saynn("[color=#c8c8d8]These are done in person, through your owner's talk menu (Ownership terms, then Discuss release), or for help from a gang, through your gang's leader.[/color]")
	addButton("Back", "Back to the overview", "")

# ---- Asking for protection ----
func protection() -> void:
	var info:Dictionary = OwnershipGameScript.canAskProtection(npcID)
	if(!bool(info["ok"])):
		saynn("You cannot ask " + nameOf(npcID) + " for that now. " + str(info["reason"]))
		addButton("Back", "Never mind", "endthescene")
		return
	var decision:Dictionary = OwnershipGameScript.protectionDecision(npcID)
	if(!bool(decision["accepts"])):
		saynn("You ask " + nameOf(npcID) + " whether they would look after you.")
		saynn("[say=npc]" + PoolStringArray(decision["reasons"]).join(" ") + "[/say]")
		if(str(decision["hint"]) != ""):
			saynn("[color=#c8c8d8]" + str(decision["hint"]) + "[/color]")
		addButton("Back", "Never mind", "endthescene")
		return
	var terms:Dictionary = OwnershipGameScript.termsFor(npcID)
	saynn("You ask " + nameOf(npcID) + " to look after you. They think about it, and they will do it, on these terms:")
	saynn(PoolStringArray(OwnershipGameScript.termsLines(terms)).join("\n"))
	saynn("[color=#c8c8d8]You can still say no. Nothing happens until you agree.[/color]")
	addButton("Agree", "Go ahead", "protection_confirm")
	addButton("Not now", "Walk away", "endthescene")

func started() -> void:
	saynn("You are under " + nameOf(npcID) + "'s protection now.")
	saynn(PoolStringArray(OwnershipGameScript.termsLines(OwnershipGameScript.termsFor(npcID))).join("\n"))
	saynn("[color=#c8c8d8]Expect your first check-in at their cell tonight or tomorrow night, as the terms say.[/color]")
	addButton("Continue", "Carry on", "endthescene")

func protectionConfirm() -> void:
	saynn("Are you sure? " + nameOf(npcID) + " will own you from now on, on the terms above, for at least " + str(OwnershipScript.MIN_TERM_DAYS) + " days. They may expect you at their cell at night, and ask things of you.")
	addButton("Yes, I accept", "Become their charge", "accept")
	addButton("Back", "Think again", "protection")

func _react(_action: String, _args):
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "slave"):
		runScene("SlaveTalkScene", [str(_args[0])])
		return
	if(_action == "accept"):
		if(OwnershipGameScript.startVoluntary(npcID)):
			setState("started") # a screen with the agreed terms and one way on
		else:
			note = "[color=red]It did not work out. They changed their mind.[/color]"
			setState("")
		return
	setState(_action)

func saveData():
	var data = .saveData()
	data["mode"] = mode
	data["npcID"] = npcID
	data["note"] = note
	return data

func loadData(_data):
	.loadData(_data)
	mode = SAVE.loadVar(_data, "mode", "")
	npcID = SAVE.loadVar(_data, "npcID", "")
	note = SAVE.loadVar(_data, "note", "")

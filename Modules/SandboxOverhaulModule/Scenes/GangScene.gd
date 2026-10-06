extends SceneBase

# The Gangs screen (from the Me menu) and a conversation about gangs with one character (from the "Gangs" button in Talking). One scene, two entry points:
# args [] = the overview, args [characterID] = talking to that character. All the rules are in GangGame, GangAffairs and GangService, and what each page says is in GangViews.
#
# The overview is a short list (one entry per gang, a "View" button each). A gang's page is information (the essentials, its members, its relations) and, for the player's own gang,
# the leader's controls. Everything social happens in person: joining, jobs, reporting back, handing things over and leaving are conversations with the gang's leader, started from the
# "Gangs" button when talking to them. Every page has a Back.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const ViewsScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangViews.gd")
const ServiceScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")
const PAGE_SIZE = 8
const ORDER_NAMES = {"intimidate": "Intimidate", "beat": "Beat up", "capture": "Capture", "rescue": "Rescue a held member"}
const ORDER_TIPS = {"intimidate": "Scare them so they fear you", "beat": "Hurt them", "capture": "Take a rival gang member away for a while", "rescue": "Get a captured member of your gang out"}

var npcID:String = ""
var viewGid:String = ""
var page:int = 0
var note:String = ""
var pendingKind:String = ""
var pendingTarget:String = ""
var gangName:String = ""
var gangHangout:String = ""
var invitees:Array = []

func _init():
	sceneID = "GangScene"

func _initScene(_args = []):
	npcID = str(_args[0]) if (_args is Array && _args.size() > 0) else ""
	GangGameScript.ensureInitialized()
	var offer:Dictionary = a().getAssignment()
	if(npcID != "" && !offer.empty() && str(offer.get("state", "")) == "offered" && npcID == g().getLeader(str(offer.get("gang", "")))):
		setState("job") # their leader has a job for you: talking to them about gangs opens it straight away

func g():
	return GangGameScript.gangs()

func a():
	return GangGameScript.affairs()

func nameOf(id) -> String:
	return GangGameScript.nameOf(id)

func _run():
	GangGameScript.ensureInitialized()
	if(note != ""):
		saynn(note)
		note = ""
	if(state == ""):
		if(npcID == ""):
			overview()
		else:
			talkMenu()
	elif(state == "view"):
		gangPage()
	elif(state == "members"):
		membersPage()
	elif(state == "relations"):
		relationsPage()
	elif(state == "create_name"):
		saynn("[b]Found a gang[/b]\nWhat will it be called? (" + str(ServiceScript.NAME_MIN) + "-" + str(ServiceScript.NAME_MAX) + " letters, numbers, spaces, apostrophes, hyphens.) It costs [color=yellow]" + str(ServiceScript.CREATE_COST) + " credits[/color].")
		var textBox:LineEdit = addTextbox("gang_name")
		var _ok = textBox.connect("text_entered", self, "onTextBoxEnterPressed")
		if(gangName != ""):
			textBox.text = gangName
		addButton("Confirm name", "Use this name", "namechosen")
		addButton("Back", "Not now", backState())
	elif(state == "create_hangout"):
		saynn("Where will " + gangName + " meet? Members will tend to be there in the daytime.")
		for room in a().freeHangouts():
			addButton(ServiceScript.hangoutName(room), "Meet here", "hangoutchosen", [room])
		addButton("Back", "Change the name", "create_name")
	elif(state == "create_members"):
		var recruits:Array = GangGameScript.recruits()
		saynn("Who comes with you? Pick at least " + str(ServiceScript.CREATE_MIN_RECRUITS) + " of the inmates willing to follow you (" + str(invitees.size()) + " chosen).")
		if(recruits.empty()):
			saynn("[color=red]Nobody is willing right now.[/color]")
		for id in pageOf(recruits):
			addButton(("[x] " if invitees.has(id) else "") + nameOf(id), "Add or remove", "togglerecruit", [id])
		pagingButtons(recruits.size(), "create_members")
		if(invitees.size() >= ServiceScript.CREATE_MIN_RECRUITS):
			addButton("Found the gang", "Pay " + str(ServiceScript.CREATE_COST) + " credits and start", "found")
		addButton("Back", "Choose another meeting place", "create_hangout")
	elif(state == "confirm_leave"):
		saynn("Leave " + g().gangName(g().playerGang()) + "? They will think less of you, and their rivals a little better. Your past with the rivals does not go away.")
		addButton("Leave", "Walk away", "doleave")
		addButton("Stay", "Never mind", backState())
	elif(state == "confirm_disband"):
		saynn("Disband " + g().gangName(ServiceScript.PLAYER_GANG_ID) + "? Your members go free. Nobody is punished.")
		addButton("Disband", "End the gang", "dodisband")
		addButton("Keep it", "Never mind", backState())
	elif(state == "initiation"):
		var oathGid:String = g().gangOf(npcID)
		saynn(GangGameScript.initiationText(oathGid))
		saynn("[color=#c8c8d8]Joining means taking on " + g().gangName(oathGid) + "'s enemies: " + enemiesText(oathGid) + ".[/color]")
		addButton("I agree", "Take the oath and join " + g().gangName(oathGid), "doinitiate", [oathGid])
		addButton("Not yet", "Tell them you need more time. The offer stays open.", "notyet", [oathGid])
	elif(state == "join"):
		var gid:String = g().gangOf(npcID)
		var check:Dictionary = GangGameScript.joinCheck(gid)
		if(check["ok"]):
			saynn(GangGameScript.initiationText(gid))
			saynn("[color=#c8c8d8]Joining means taking on " + g().gangName(gid) + "'s enemies: " + enemiesText(gid) + ".[/color]")
			addButton("I agree", "Take the oath and join " + g().gangName(gid), "doinitiate", [gid])
			addButton("Not yet", "Tell them you need more time. The offer stays open.", "notyet", [gid])
			return
		saynn((nameOf(npcID) + " looks you over. " if npcID != "" else "") + "[color=cyan]" + g().gangName(gid) + "[/color] - " + str(ServiceScript.establishedDef(gid).get("recruit", "")))
		if(check["needsIntro"]):
			saynn("[color=yellow]" + PoolStringArray(check["reasons"]).join(" ") + "[/color]")
			addButton("Hear what they want", "They set you a job that shows what they are about. Finish it and report back to them in person.", "takeintro", [gid])
		else:
			saynn("[color=red]" + PoolStringArray(check["reasons"]).join(" ") + "[/color]")
		addButton("Back", "Not now", backState())
	elif(state == "job"):
		jobMenu()
	elif(state == "orders"):
		saynn("[b]Gang orders[/b] Treasury: [color=yellow]" + str(g().availableTreasury(ServiceScript.PLAYER_GANG_ID)) + "[/color] available. Each order costs " + str(ServiceScript.ORDER_COST) + " and your people need a day between orders.")
		for kind in ServiceScript.ORDER_KINDS:
			addButton(ORDER_NAMES[kind], ORDER_TIPS[kind], "orderkind", [kind])
		addButton("Back", "Close", backState())
	elif(state == "order_target"):
		var targets:Array = GangGameScript.targetsFor(pendingKind)
		saynn(ORDER_NAMES[pendingKind] + ": whom?")
		if(targets.empty()):
			saynn("There is nobody who can be a target.")
		for id in pageOf(targets):
			var gid2:String = g().gangOf(id)
			addButton(nameOf(id) + ((" (" + g().gangName(gid2) + ")") if gid2 != "" else ""), "Pick them", "ordertarget", [id])
		pagingButtons(targets.size(), "order_target")
		addButton("Back", "Pick another order", "orders")
	elif(state == "order_confirm"):
		var check2:Dictionary = a().canOrder(pendingKind, pendingTarget, GangGameScript.orderContext(pendingTarget))
		var chance:float = a().orderSuccess(GangGameScript.gangStrength(ServiceScript.PLAYER_GANG_ID), GangGameScript.power(pendingTarget), GangGameScript.feeling(pendingTarget, "pc", "fear"), GangGameScript.orderContext(pendingTarget)["members"])
		var likelihood:String = "likely" if chance >= 0.6 else ("uncertain" if chance >= 0.35 else "unlikely")
		saynn(ORDER_NAMES[pendingKind] + " " + nameOf(pendingTarget) + ": success looks [color=yellow]" + likelihood + "[/color]. Cost [color=yellow]" + str(ServiceScript.ORDER_COST) + "[/color] from the treasury. Failing can get one of your people hurt or held for a while, and harming a rival gang's people turns that gang against you.")
		if(check2["ok"]):
			addButton("Give the order", "Send them", "doorder")
		else:
			saynn("[color=red]" + check2["reason"] + "[/color]")
		addButton("Back", "Pick someone else", "order_target")
	elif(state == "roster"):
		var members:Array = g().getMembers(ServiceScript.PLAYER_GANG_ID)
		members.erase("pc")
		saynn("[b]Your gang[/b] (" + str(members.size() + 1) + " with you). Pick a member to remove, or an inmate to invite.")
		var rows:Array = []
		for id in members:
			rows.append(["Remove: " + nameOf(id), "remove", id])
		for id in GangGameScript.recruits():
			rows.append(["Invite: " + nameOf(id), "inviteid", id])
		for row in pageOf(rows):
			addButton(row[0], "Do it", row[1], [row[2]])
		pagingButtons(rows.size(), "roster")
		addButton("Back", "Close", backState())
	elif(state == "hangout"):
		saynn("Move " + g().gangName(ServiceScript.PLAYER_GANG_ID) + "'s meeting place? You can only do this every couple of days.")
		for room in a().freeHangouts():
			addButton(ServiceScript.hangoutName(room), "Meet here", "sethangout", [room])
		addButton("Back", "Close", backState())

func pageOf(list:Array) -> Array:
	var last:int = int(min(list.size(), (page + 1) * PAGE_SIZE)) - 1
	return list.slice(page * PAGE_SIZE, last) if last >= page * PAGE_SIZE else []

func pagingButtons(total:int, _backState:String) -> void:
	if(page > 0):
		addButton("Previous page", "Earlier", "prev")
	if((page + 1) * PAGE_SIZE < total):
		addButton("Next page", "Later", "next")

func enemiesText(gid:String) -> String:
	var names:Array = []
	for enemy in g().enemiesOf(gid):
		names.append(g().gangName(enemy))
	return PoolStringArray(names).join(", ") if !names.empty() else "none"

# Where "Back" goes: the open gang's page, or the first page.
func backState() -> String:
	return "view" if (viewGid != "" && npcID == "") else ""

# The landing page: who you are in this world of gangs, one short entry per gang, and nothing else.
func overview() -> void:
	saynn("[b]Gangs[/b]\n" + ViewsScript.statusLine())
	var entries:Array = ViewsScript.landing()
	for entry in entries:
		saynn(ViewsScript.landingEntryText(entry))
	for entry in entries:
		addButton("View " + str(entry["name"]), "Open this gang's page", "viewgang", [entry["gid"]])
	if(!entries.empty()):
		saynn("[color=#a0a0a0]" + PoolStringArray(ViewsScript.legendLines()).join(" ") + "[/color]")
	if(g().playerGang() == "" && g().isInitialized()):
		addButton("Found a gang", "Make your own gang. It takes reputation, followers and money.", "createstart")
	addButton("Close", "Done looking", "endthescene")

# One gang's page: the essentials, then a button for each thing you can do.
func gangPage() -> void:
	var gid:String = viewGid
	if(!g().hasGang(gid)):
		saynn("That gang is gone.")
		addButton("Back", "Back to the list", "")
		return
	saynn(PoolStringArray(ViewsScript.detailLines(gid)).join("\n"))
	var own:String = g().playerGang()
	addButton("Members", "Who is in it", "members")
	addButton("Relations", "How it stands with the other gangs and with you", "relations")
	if(own == gid && g().isLeader("pc", gid) && g().getGang(gid).get("player", false)):
		addButton("Orders", "Send your people after someone", "orders")
		addButton("Roster", "Invite or remove members", "roster")
		addButton("Hangout", "Change where you meet", "hangout")
		addButton("Contribute 5", "Put 5 credits in the treasury", "contribute")
		addButton("Disband", "End your gang", "confirm_disband")
	addButton("Back", "Back to the list of gangs", "")

func membersPage() -> void:
	var view:Dictionary = ViewsScript.memberLines(viewGid, page)
	saynn("[b]" + g().gangName(viewGid) + " - members[/b]\n" + PoolStringArray(view["lines"]).join("\n"))
	if(page > 0):
		addButton("Previous page", "Earlier members", "prev")
	if(page + 1 < int(view["pages"])):
		addButton("Next page", "More members", "next")
	addButton("Back", "Back to the gang's page", "view")

func relationsPage() -> void:
	saynn("[b]" + g().gangName(viewGid) + " - relations[/b]\n" + PoolStringArray(ViewsScript.relationLines(viewGid)).join("\n"))
	addButton("Back", "Back to the gang's page", "view")

func talkMenu() -> void:
	var gid:String = g().gangOf(npcID)
	var own:String = g().playerGang()
	var isLeader:bool = gid != "" && g().isLeader(npcID, gid) && !g().getGang(gid).get("player", false)
	saynn(GangGameScript.leaderGreeting(gid) if isLeader else "You talk to " + nameOf(npcID) + " about gangs.")
	var cold:bool = isLeader && GangGameScript.leaderMood(npcID) == "hostile"
	addButton("Are you in a gang?", "Ask whose side they are on", "askgang")
	if(gid != ""):
		addButton("Where do you meet?", "Ask where the gang hangs out", "askwhere")
		addButton("Who leads it?", "Ask who is in charge", "askleader")
	if(own == "" && gid != "" && !g().getGang(gid).get("player", false)):
		if(isLeader):
			if(cold):
				addDisabledButton("Ask about joining", nameOf(npcID) + " wants nothing to do with you right now. Earn your way back first.")
			else:
				addButton("Ask about joining", "Ask to join", "join")
		else:
			addButton("Ask about joining", "Ask how to join", "askjoin")
	if(own != "" && g().isLeader(npcID, own) && !g().getGang(own).get("player", false)):
		if(cold):
			addDisabledButton("Discuss a job", nameOf(npcID) + " does not trust you with work right now.")
		else:
			addButton("Discuss a job", "Ask what they need", "job")
		addButton("Leave the gang", "Tell them you are done", "confirm_leave")
	if(own == "" && isLeader && a().hasAssignment() && a().getAssignment()["gang"] == gid):
		addButton("Discuss the job", "About that introductory job", "job")
	if(a().canCourier(npcID, GangGameScript.now())):
		addButton("Deliver the package", "Hand over the " + str(a().getAssignment()["amount"]) + " credits you were given to carry", "courier")
	if(g().slaveOwner(npcID) != ""):
		addButton("Help them get free", "Get them away from " + g().gangName(g().slaveOwner(npcID)) + ". The gang will not like it.", "freeslave")
	if(own == ServiceScript.PLAYER_GANG_ID):
		if(gid == ""):
			addButton("Invite to my gang", "Ask them to follow you", "inviteid", [npcID])
		elif(gid == own && npcID != "pc"):
			addButton("Remove from my gang", "Send them away", "remove", [npcID])
	addButton("Back", "End the conversation", "endthescene")

func jobMenu() -> void:
	var assignment:Dictionary = a().getAssignment()
	var own:String = g().playerGang()
	if(assignment.empty()):
		var check:Dictionary = a().canOffer(GangGameScript.now())
		if(check["ok"]):
			saynn("[color=cyan]" + nameOf(g().getLeader(own)) + "[/color] considers it.")
			addButton("Ask for work", "See if they have something", "askwork")
		else:
			saynn(check["reason"])
	else:
		if(assignment["state"] == "offered"):
			saynn(GangGameScript.offerSpeechText(assignment))
			saynn("[color=#c8c8d8]" + GangGameScript.offerPanelText(assignment) + "[/color]")
			addButton("Accept", "Take the job", "acceptjob")
			addButton("Decline", "Turn it down (no penalty)", "declinejob")
		elif(assignment["state"] == "ready"):
			saynn("[color=#c8c8d8]" + GangGameScript.statusPanelText(assignment) + "[/color]")
			addButton("Report back", "Tell them it is done", "report")
		else:
			saynn(GangGameScript.reminderText(assignment))
			saynn("[color=#c8c8d8]" + GangGameScript.statusPanelText(assignment) + "[/color]")
			if(assignment["type"] == "deliver"):
				addButton("Deliver", "Hand it over now", "deliver")
			if(assignment["type"] == "capture" && assignment["stage"] == "defeated"):
				addButton("Hand over the captive", "Give them the beaten target", "handover")
	addButton("Back", "Close", backState())

func _react(_action: String, _args):
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "next" || _action == "prev"):
		page = int(max(0, page + (1 if _action == "next" else -1)))
		return
	if(_action == "viewgang"):
		viewGid = str(_args[0])
		page = 0
		setState("view")
		return
	if(_action == "view" || _action == "members" || _action == "relations"):
		page = 0
		setState(_action)
		return
	if(_action == "join"):
		GangGameScript.noteJoinRequest(g().gangOf(npcID))
		setState("join")
		return
	if(_action == "report"):
		var reportGid:String = g().gangOf(npcID)
		note = GangGameScript.reportAssignment()
		setState("initiation" if GangGameScript.canInitiate(reportGid) && a().hasIntroDone(reportGid) else "")
		return
	if(_action == "doinitiate"):
		note = GangGameScript.initiate(str(_args[0]))
		setState("")
		return
	if(_action == "notyet"):
		note = GangGameScript.postponeInitiation(str(_args[0]))
		setState("")
		return
	if(_action == "courier"):
		note = GangGameScript.deliverCourier(npcID)
		return
	if(_action == "askgang"):
		var gid:String = g().gangOf(npcID)
		if(gid == ""):
			note = "[say=" + npcID + "]Me? I keep to myself.[/say]"
		else:
			var _learned:bool = g().learnGang(npcID) # they told you
			note = "[say=" + npcID + "]I run with " + g().gangName(gid) + ".[/say] " + str(ServiceScript.establishedDef(gid).get("text", "A gang."))
		return
	if(_action == "askwhere"):
		note = "[say=" + npcID + "]You will find us at " + ServiceScript.hangoutName(g().getHangout(g().gangOf(npcID))) + ", most days.[/say]"
		return
	if(_action == "askleader"):
		var askedGid:String = g().gangOf(npcID)
		var leader:String = g().getLeader(askedGid)
		var _learnedLeader:bool = g().learnGang(leader)
		note = "[say=" + npcID + "]" + GangDialogue.whoLeads(leader == npcID, nameOf(leader) if leader != "" else "", g().gangName(askedGid)) + "[/say]"
		return
	if(_action == "freeslave"):
		note = GangGameScript.freeGangSlave(npcID)
		return
	if(_action == "askjoin"):
		var gid2:String = g().gangOf(npcID)
		note = "[say=" + npcID + "]Talk to " + nameOf(g().getLeader(gid2)) + ", our leader. They decide.[/say]"
		return
	if(_action == "createstart"):
		var check:Dictionary = a().canCreate(GangGameScript.createContext())
		if(!check["ok"]):
			note = "[color=red]" + PoolStringArray(check["reasons"]).join(" ") + "[/color]"
			return
		page = 0
		setState("create_name")
		return
	if(_action == "namechosen"):
		var named:Dictionary = ServiceScript.validName(getTextboxData("gang_name"))
		gangName = named["name"]
		if(!named["ok"]):
			note = "[color=red]" + named["reason"] + "[/color]"
			return
		setState("create_hangout")
		return
	if(_action == "hangoutchosen"):
		gangHangout = str(_args[0])
		page = 0
		invitees = []
		setState("create_members")
		return
	if(_action == "togglerecruit"):
		var rid:String = str(_args[0])
		if(invitees.has(rid)):
			invitees.erase(rid)
		else:
			invitees.append(rid)
		return
	if(_action == "found"):
		note = GangGameScript.createGang(gangName, gangHangout, invitees)
		invitees = []
		viewGid = ServiceScript.PLAYER_GANG_ID if g().playerGang() == ServiceScript.PLAYER_GANG_ID else ""
		setState("view" if viewGid != "" else "")
		return
	if(_action == "contribute"):
		note = GangGameScript.contribute(5)
		return
	if(_action == "doleave"):
		note = GangGameScript.leave()
		setState("view" if viewGid != "" && npcID == "" else "")
		return
	if(_action == "dodisband"):
		note = "[color=yellow]You disbanded the gang.[/color]" if a().disbandPlayerGang() else "[color=red]You cannot do that.[/color]"
		GangGameScript.refreshHangoutZones()
		viewGid = ""
		setState("")
		return
	if(_action == "takeintro"):
		var offered:String = GangGameScript.offerIntro(str(_args[0]))
		note = "" if offered != "" else "[color=yellow]" + nameOf(g().getLeader(str(_args[0]))) + " has nothing for you right now. Come back another day.[/color]"
		setState("job" if offered != "" else "")
		return
	if(_action == "askwork"):
		var text:String = GangGameScript.offerAssignment()
		note = text if text != "" else "[color=cyan]They have nothing for you right now.[/color]"
		setState("job")
		return
	if(_action == "acceptjob"):
		note = GangGameScript.acceptAssignment()
		setState("")
		return
	if(_action == "declinejob"):
		note = GangGameScript.declineAssignment()
		setState(backState())
		return
	if(_action == "deliver"):
		note = GangGameScript.deliverAssignment()
		return
	if(_action == "handover"):
		var handGid:String = g().gangOf(npcID)
		note = GangGameScript.handOverCaptive()
		setState("initiation" if GangGameScript.canInitiate(handGid) && a().hasIntroDone(handGid) else "")
		return
	if(_action == "orderkind"):
		pendingKind = str(_args[0])
		page = 0
		setState("order_target")
		return
	if(_action == "ordertarget"):
		pendingTarget = str(_args[0])
		setState("order_confirm")
		return
	if(_action == "doorder"):
		var module = GlobalRegistry.getModule("SandboxOverhaulModule")
		note = GangGameScript.orderAction(pendingKind, pendingTarget, [module.nextRoll(), module.nextRoll()])
		setState("orders")
		return
	if(_action == "inviteid"):
		note = GangGameScript.invite(str(_args[0]))
		return
	if(_action == "remove"):
		note = GangGameScript.removeMember(str(_args[0]))
		return
	if(_action == "sethangout"):
		note = GangGameScript.changeHangout(str(_args[0]))
		setState(backState())
		return
	page = 0
	setState(_action)

func onTextBoxEnterPressed(_text):
	GM.main.pickOption("namechosen", [])

func saveData():
	var data = .saveData()
	data["npcID"] = npcID
	data["viewGid"] = viewGid
	data["page"] = page
	data["pendingKind"] = pendingKind
	data["pendingTarget"] = pendingTarget
	data["gangName"] = gangName
	data["gangHangout"] = gangHangout
	data["invitees"] = invitees
	return data

func loadData(_data):
	.loadData(_data)
	npcID = SAVE.loadVar(_data, "npcID", "")
	viewGid = SAVE.loadVar(_data, "viewGid", "")
	page = SAVE.loadVar(_data, "page", 0)
	pendingKind = SAVE.loadVar(_data, "pendingKind", "")
	pendingTarget = SAVE.loadVar(_data, "pendingTarget", "")
	gangName = SAVE.loadVar(_data, "gangName", "")
	gangHangout = SAVE.loadVar(_data, "gangHangout", "")
	invitees = SAVE.loadVar(_data, "invitees", [])

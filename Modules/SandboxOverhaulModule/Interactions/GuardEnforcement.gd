extends PawnInteractionBase

# A guard dealing with the player: a nudity warning (and its fine), a search, or a confrontation after witnessed violence or a forced encounter.
# Registered by SandboxOverhaulModule.postInit. The rules (who, when, how often) live in the module and GuardSecurity; this only plays the scene.
# Fights reuse BDCC's own fight path, so Milestone 2 reputation and Milestone 3 injuries apply exactly once. Punishment reuses PunishInteraction.
#
# kind: "nudity_warn", "nudity_escalate", "search", "violent", "severe"
# harshness: 0 complied, 1 gave in after resisting or surrendered in the fight, 2 beaten in the fight

const ATTITUDE_LINES = {
	"nudity_warn": {
		"lax": "{guard.name} glances at you and sighs. [say=guard]Cover up, would you? Not in the hallway.[/say]",
		"standard": "{guard.name} stops and frowns. [say=guard]Put some clothes on, inmate. This isn't the showers.[/say]",
		"strict": "{guard.name} blocks your way. [say=guard]Cover yourself. Now. I won't say it twice.[/say]",
	},
	"search": {
		"lax": "{guard.name} waves you over. [say=guard]Quick check, inmate. Won't take long.[/say]",
		"standard": "{guard.name} steps in front of you. [say=guard]Random search, inmate. Stay where you are.[/say]",
		"strict": "{guard.name} grabs your attention. [say=guard]Search. Hands where I can see them.[/say]",
	},
}

var kind:String = "search"
var harshness:int = 0
var resisted:bool = false
var resultText:String = ""
var punishAfter:bool = false
var lostHow:String = ""

func _init():
	id = "GuardEnforcement"

func start(_pawns:Dictionary, _args:Dictionary):
	doInvolvePawn("guard", _pawns["guard"])
	doInvolvePawn("inmate", _pawns["inmate"])
	kind = str(_args.get("kind", "search"))
	var sandbox = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(sandbox != null):
		sandbox.onEnforcementStarted(kind, getRoleID("guard"))
	var startState:String = {"nudity_warn": "nudity_warn", "nudity_escalate": "nudity_escalate", "search": "announce", "violent": "announce", "severe": "announce"}.get(kind, "announce")
	setState(startState, "inmate")

# A guard and the player meet (either of them walked in). The module decides whether anything happens; most of the time nothing does.
func shouldRunOnMeet(_pawn1, _pawn2, _pawn2Moved:bool):
	var sandbox = getSandbox()
	if(sandbox == null):
		return [false]
	var pair:Array = sandbox.pickGuardAndPlayer(_pawn1, _pawn2)
	if(pair.empty()):
		return [false]
	var decision:Dictionary = sandbox.evaluateGuardEncounter(pair[0], pair[1])
	if(decision.empty()):
		return [false]
	return [true, {"guard": decision["guard"], "inmate": "pc"}, {"kind": decision["kind"]}]

func onStopped():
	var sandbox = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(sandbox != null):
		sandbox.onEnforcementEnded(resisted)

func getSandbox():
	return GlobalRegistry.getModule("SandboxOverhaulModule")

func attitude() -> String:
	return getSandbox().getGuardAttitude(getRoleID("guard"))

# ---- Nudity ----
func nudity_warn_text():
	saynn(ATTITUDE_LINES["nudity_warn"][attitude()])
	saynn("[color=yellow]Warning: cover up, or the next guard to see you like this may do more than talk.[/color]")
	addAction("cover", "Cover up", "Tell them you will get dressed", "default", 1.0, 30, {})
	addAction("ignore", "Ignore them", "Walk off without answering", "default", 1.0, 30, {})

func nudity_warn_do(_id:String, _args:Dictionary, _context:Dictionary):
	if(_id == "ignore"):
		getSandbox().getSecurity().markWarningIgnored()
	stopMe()

func nudity_escalate_text():
	saynn("{guard.name} comes back with a scowl. [say=guard]I told you to cover up. Now it costs you.[/say]")
	addAction("accept", "Take the fine", "Pay it and move on", "default", 1.0, 30, {})

func nudity_escalate_do(_id:String, _args:Dictionary, _context:Dictionary):
	addMessage(getSandbox().applyNudityFine(getRoleID("guard")))
	stopMe()

# ---- Search, violence and severe offences: comply or resist ----
func announce_text():
	if(kind == "search"):
		saynn(ATTITUDE_LINES["search"][attitude()])
	elif(kind == "violent"):
		saynn("{guard.name} saw what you did and moves in. [say=guard]Enough! Hands up, inmate. You're being searched.[/say]")
	else:
		saynn("{guard.name} saw what you did, and this is not a warning. [say=guard]You're coming with me, inmate. Hands behind your head.[/say]")
	addAction("comply", "Comply", "Do as you are told", "default", 1.0, 60, {})
	addAction("resist", "Resist", "Refuse. This will end in a fight", "default", 1.0, 30, {})

func announce_do(_id:String, _args:Dictionary, _context:Dictionary):
	if(_id == "comply"):
		harshness = 0
		doSearch()
	if(_id == "resist"):
		resisted = true
		addMessage(getSandbox().onEnforcementResisted())
		setState("about_to_fight", "inmate")

func about_to_fight_text():
	saynn("{inmate.name} prepares for a fight.")
	sayLine("guard", "GuardCaughtOffLimitsFight", {guard="guard", inmate="inmate"})
	addAction("fight", "Fight", "Begin the fight", "fight", 1.0, 600, {start_fight=["inmate", "guard"],})
	addAction("giveup", "Give in", "You changed your mind", "surrender", 1.0, 30, {})

func about_to_fight_do(_id:String, _args:Dictionary, _context:Dictionary):
	if(_id == "giveup"):
		harshness = 1
		doSearch()
	if(_id == "fight"):
		var fightResult = getFightResult(_args)
		if(fightResult["won"]):
			addMessage(getSandbox().onEnforcementWon())
			setState("resist_won", "inmate")
			sendSocialEvent("inmate", "guard", SocialEventType.LostFight)
		else:
			if(fightResult.get("submitter", "") == "pc"):
				harshness = 1
				lostHow = "surrender"
			else:
				harshness = 2
				lostHow = fightResult.get("how", "pain")
			setState("resist_lost", "inmate")
			sendSocialEvent("guard", "inmate", SocialEventType.LostFight)

func resist_won_text():
	saynn("{guard.name} hits the floor. {inmate.name} won!")
	sayLine("guard", "FightLostGeneric", {winner="inmate", loser="guard"})
	saynn("[color=yellow]There is no search this time, but security will not forget this.[/color]")
	addAction("leave", "Leave", "Get away while you can", "default", 1.0, 30, {})

func resist_won_do(_id:String, _args:Dictionary, _context:Dictionary):
	makeRoleExhausted("guard")
	stopMe()

func resist_lost_text():
	if(lostHow == "surrender"):
		saynn("{inmate.name} gives up and drops to {inmate.his} knees. {guard.name} pulls {inmate.him} back up.")
		sayLine("guard", "GuardInmateSurrender", {guard="guard", inmate="inmate"})
	else:
		saynn("{inmate.name} hits the floor" + (", too turned on to fight on." if lostHow == "lust" else ", beaten.") + " {guard.name} won.")
		sayLine("guard", "FightWonGeneric", {winner="guard", loser="inmate"})
	addAction("continue", "Continue", "See what the guard does", "default", 1.0, 60, {})

func resist_lost_do(_id:String, _args:Dictionary, _context:Dictionary):
	doSearch()

# The search itself, whichever way we got here. Beaten players and serious offences are also sent on to the existing punishment.
func doSearch():
	var result:Dictionary = getSandbox().performPersonalSearch(getRoleID("guard"), harshness)
	resultText = result["message"]
	addMessage(resultText)
	punishAfter = (harshness >= 2 || kind == "severe")
	setState("search_result", "inmate")

func search_result_text():
	saynn(resultText)
	if(punishAfter):
		saynn("[color=red]" + ("That was serious." if harshness < 2 else "Fighting back made it worse.") + " {guard.name} is not done with you.[/color]")
		addAction("punish", "Face the punishment", "See what the guard decides", "default", 1.0, 60, {})
	else:
		addAction("done", "Continue", "Move on", "default", 1.0, 30, {})

func search_result_do(_id:String, _args:Dictionary, _context:Dictionary):
	if(_id == "punish"):
		startInteraction("PunishInteraction", {punisher=getRoleID("guard"), target=getRoleID("inmate")})
		return
	stopMe()

func getAnimData() -> Array:
	if(getCurrentAction() == "fight"):
		return [StageScene.Duo, "shove", {pc="inmate", npc="guard", npcAction="hurt"}]
	return [StageScene.Duo, "stand", {pc="inmate", npc="guard"}]

func getActivityIconForRole(_role:String):
	return RoomStuff.PawnActivity.Chat

func getPreviewLineForRole(_role:String) -> String:
	if(_role == "guard"):
		return "{guard.name} is dealing with {inmate.name}."
	if(_role == "inmate"):
		return "{inmate.name} was stopped by {guard.name}."
	return .getPreviewLineForRole(_role)

func saveData():
	var data = .saveData()
	data["kind"] = kind
	data["harshness"] = harshness
	data["resisted"] = resisted
	data["resultText"] = resultText
	data["punishAfter"] = punishAfter
	data["lostHow"] = lostHow
	return data

func loadData(_data):
	.loadData(_data)
	kind = SAVE.loadVar(_data, "kind", "search")
	harshness = SAVE.loadVar(_data, "harshness", 0)
	resisted = SAVE.loadVar(_data, "resisted", false)
	resultText = SAVE.loadVar(_data, "resultText", "")
	punishAfter = SAVE.loadVar(_data, "punishAfter", false)
	lostHow = SAVE.loadVar(_data, "lostHow", "")

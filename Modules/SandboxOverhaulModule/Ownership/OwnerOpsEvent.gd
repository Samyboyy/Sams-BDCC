extends NpcOwnerEventBase

# The owner's side of the module's ownership rules, as one of BDCC's own owner events (it runs inside the same event runner as every other owner event, and reuses the existing punishment
# event). It is reached in person only: when the owner walks up to the player with something to say (a warning, a demand), or when the player talks to the owner (the module adds entries to the
# owner's talk menu). Nothing here starts anywhere but where the two of them stand.

const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")
const TextScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipText.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")

var level:int = 1
var lastText:String = ""
var apologised:bool = false
var released:bool = false
var intent:String = "" # how the owner goes about the night: "ask", "demand" or "force"
var persuaded:bool = false
var afterSex:String = "" # where the event goes once the scene is over: "night" (sleep) or "rescue" (the restraints come off)
var rescued:bool = false
var purpose:String = "" # a meeting: why the owner asked for it (saved with the meeting, never rerolled)
var checkText:String = "" # what the owner said about the check-in (kept: opening the scene again neither repeats nor changes it)
var praiseNote:String = ""
var rewardCredits:int = 0
var pregBack:String = "" # where the conversation goes after the owner has reacted to the pregnancy: "outcome" (the check-in carries on), "meeting" or "" (it ends)
var pregText:String = ""
var sexApplied:bool = false # the sex scene's aftermath goes through exactly once
var punishStarted:bool = false # the punishment was started once (a redraw or a reload never starts it again)
var punishKind:String = "" # which of the game's punishment events it turned into (so that what follows is not rerolled)
var punishDone:bool = false
var punishInfluence:float = -1.0 # the owner's hold on the player when the punishment began: a punishment the player fought off lowers it
var nightReplaced:bool = false # the punishment itself decided the night
var fromCheckin:bool = false # a warning dealt with during the evening check-in: the evening carries on afterwards

const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")

func _init():
	id = "SandboxOwnerOps"

func svc():
	return OwnershipGameScript.svc()

func ownerLine(text:String) -> void:
	saynn(TextScript.say(getOwnerID(), text))

func onStart(_args:Array):
	var mode:String = str(_args[0]) if _args.size() > 0 else "approach"
	if(mode in ["checkin", "demand", "handover", "meeting", "terms", "release", "pregnancy"]):
		setSubResult(SUB_CONTINUE) # started from the owner's talk menu: when it is done, the conversation goes on (the next ownership action, if any, is offered there)
	match(mode):
		"pregnancy":
			pregBack = ""
			if(!openPregnancy()):
				setState("nothing")
		"meeting":
			openMeeting()
		"approach":
			if(svc().meetingDue(OwnershipGameScript.today())):
				openMeeting() # the owner came for the meeting they asked for
			elif(svc().hasDemand() && svc().demand()["state"] == "ready"):
				setState("handover") # a finished demand is reported first, whenever the owner turns up
			elif(!svc().pendingConfront().empty()):
				level = int(svc().pendingConfront()["level"])
				setState("confront")
			elif(svc().hasDemand() && svc().demand()["state"] == "offered"):
				setState("demand")
			else:
				setState("nothing")
		"checkin":
			setState("checkin")
		"rescue":
			setState("rescue")
		"demand":
			setState("demand")
		"handover":
			setState("handover")
		"terms":
			setState("terms")
		"release":
			setState("release")
		_:
			setState("nothing")

func nothing():
	playStand()
	saynn("{npc.name} looks at you and shrugs. There is nothing more to say right now.")
	addContinue("endEvent")

func nothing_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

# ---- Check-in ----
var checkedIn:bool = false

func checkin():
	playStand()
	if(!checkedIn):
		var result:Dictionary = OwnershipGameScript.reportIn()
		checkText = str(result["text"])
		checkedIn = bool(result["ok"]) # (once: the check-in is fulfilled exactly once, whatever happens next)
		if(checkedIn):
			praiseNote = str(result.get("note", ""))
			if(OwnershipGameScript.demandReportIn()):
				checkText += "\n\nThat counts for the task they gave you too."
	saynn(checkText)
	if(!checkedIn):
		addContinue("endEvent")
		return
	addContinue("next")

func checkin_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()
	if(_id == "next"):
		pregBack = "outcome"
		if(!openPregnancy()):
			routeOutcome()

# What the evening turns into was chosen once when the check-in was made (a birth, a warning, praise, intimacy or just the stay).
func routeOutcome():
	match(svc().checkinOutcome()):
		"birth":
			setState("birth")
		"warning":
			if(svc().hasMeeting() && str(svc().meeting()["purpose"]) in OwnershipScript.OWED_PURPOSES):
				var _covered:bool = svc().finishMeeting() # the owed matter is dealt with here, now: not twice
			if(!svc().pendingConfront().empty()):
				fromCheckin = true
				level = int(svc().pendingConfront()["level"])
				setState("confront")
			else:
				setState("night")
		"praise":
			setState("praise")
		"intimacy":
			intent = svc().checkinIntent()
			afterSex = "night"
			setState("intimacy")
		_:
			setState("night")

# The owner's reaction to a pregnancy they have just noticed, or to the birth being near: once per pregnancy, in a check-in, a meeting or a conversation. Returns true when a pregnancy screen took over.
func openPregnancy() -> bool:
	var pending:String = OwnershipGameScript.pregnancyPending()
	if(pending == "notice"):
		pregText = OwnershipGameScript.pregnancyNoticeText()
		setState("pregnancy_notice")
		return true
	if(pending == "birth" || (pregBack == "outcome" && svc().checkinOutcome() == "birth")):
		setState("birth")
		return true
	return false

func pregnancy_notice():
	playStand()
	saynn(pregText)
	addContinue("on")

func pregnancy_notice_do(_id:String, _args:Array):
	if(_id == "on"):
		if(OwnershipGameScript.pregnancyPending() == "birth"):
			setState("birth")
		elif(pregBack == "outcome"):
			routeOutcome()
		elif(pregBack == "meeting"):
			resumeMeeting()
		else:
			endEvent()

# The player is ready to give birth: the owner says so and offers to go with them; going alone is always allowed. The birth itself is the game's (the nursery), never repeated here.
func birth():
	playStand()
	ownerLine(TextScript.birthNotice(svc().style()))
	addButton("Let them take you", "They take you to the nursery and stay with you", "take")
	addButton("Go alone", "You would rather do this alone", "alone")

func birth_do(_id:String, _args:Array):
	if(_id == "take"):
		stopRunner()
		endEvent()
		OwnershipGameScript.takeToNursery()
	if(_id == "alone"):
		svc().setPregnancyStage("birth")
		lastText = TextScript.birthAlone(svc().style())
		setState("birth_alone")

func birth_alone():
	playStand()
	ownerLine(lastText)
	addContinue("endEvent")

func birth_alone_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent() # (nobody puts somebody in labour to bed)

func praise():
	playStand()
	ownerLine(TextScript.praiseLine(svc().style()))
	if(praiseNote != ""):
		saynn("[color=#c8c8d8]" + praiseNote + "[/color]")
	addContinue("on")

func praise_do(_id:String, _args:Array):
	if(_id == "on"):
		setState("night")

# ---- A meeting the owner asked for: a real conversation, by the reason it was asked for ----
func openMeeting():
	var s = svc()
	purpose = str(s.meeting().get("purpose", "attention")) if s.hasMeeting() else "attention"
	var _held:bool = s.finishMeeting() # it is being held now: it is not asked for again
	pregBack = "meeting"
	if(openPregnancy()):
		return # the owner has noticed the pregnancy: that comes first, then the meeting carries on
	resumeMeeting()

func resumeMeeting():
	var s = svc()
	if(purpose == "intimacy" && OwnershipGameScript.birthImminent()):
		purpose = "attention" # (never intimacy when the birth is near)
	match(purpose):
		"demand":
			if(OwnershipGameScript.meetingGiveDemand()):
				setState("demand")
				return
			purpose = "attention"
		"review":
			if(s.hasDemand() && s.demand()["state"] == "ready"):
				setState("handover")
				return
			setState("settled_already")
			return
		"warning", "compensation", "punishment":
			if(!s.pendingConfront().empty()):
				level = int(s.pendingConfront()["level"])
				setState("confront")
			else:
				setState("settled_already")
			return
		"reward":
			rewardCredits = int(OwnershipGameScript.meetingReward()["credits"])
			setState("reward")
			return
		"intimacy":
			intent = OwnershipScript.intimacyIntent(s.style(), OwnershipGameScript.feeling(getOwnerID(), "pc", "affection"), OwnershipGameScript.feeling(getOwnerID(), "pc", "trust"))
			afterSex = "meeting"
			setState("intimacy")
			return
	OwnershipGameScript.meetingAttention()
	setState("attention")

func reward():
	playStand()
	ownerLine(TextScript.rewardLine(svc().style()))
	saynn("[color=#c8c8d8]They give you " + str(rewardCredits) + " credits.[/color]")
	addContinue("endEvent")

func reward_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

func attention():
	playStand()
	ownerLine(TextScript.attentionLine(svc().style()))
	ownerLine(TextScript.attentionClose(svc().style()))
	addContinue("endEvent")

func attention_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

func settled_already():
	playStand()
	ownerLine(TextScript.settledAlready(svc().style()))
	addContinue("endEvent")

func settled_already_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

# ---- The evening at the owner's ----
# After a valid evening check-in the owner requires, invites or allows a stay (by style). Staying is the game's own sleep: the next morning, the same recovery as in the player's own cell.
func night():
	playStand()
	var s = svc()
	var mode:String = OwnershipScript.nightMode(s.style(), OwnershipGameScript.nightSeed())
	match(mode):
		"require":
			ownerLine(TextScript.nightRequire(s.style()))
			addButton("Stay the night", "Do as they say and sleep here", "stay")
		"invite":
			ownerLine(TextScript.nightInvite(s.style()))
			addButton("Stay the night", "Sleep here", "stay")
			addButton("Leave", "Go back to your own cell", "endEvent")
		_:
			ownerLine(TextScript.nightAllow(s.style()))
			addButton("Leave", "Go back to your own cell", "endEvent")
			addButton("Stay anyway", "Sleep here, if they do not mind", "stay")

func night_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()
	if(_id == "stay"):
		setState("sleep") # (whether the night turns intimate was chosen with the check-in)

func sleep():
	playStand()
	saynn("You settle in for the night. Their cell is quiet and safe.")
	addContinue("sleepNow")

func sleep_do(_id:String, _args:Array):
	if(_id == "sleepNow"):
		stopRunner() # the evening is over: nothing of the conversation is left to go back to
		endEvent()
		OwnershipGameScript.sleepAtOwners() # morning: the same recovery as in the player's own cell, saved once by the game itself

# ---- Intimacy: asked, demanded or forced ----
func intimacy():
	playStand()
	var styleName:String = svc().style()
	match(intent):
		"ask":
			ownerLine(TextScript.intimacyAsk(styleName))
			addButton("Accept", "Spend the night with them", "accept")
			addButton("Decline", "Say no. They will take it well, and nothing is lost", "decline")
		"demand":
			ownerLine(TextScript.intimacyDemand(styleName))
			addButton("Obey", "Give them what they want. You are not doing it willingly", "obey")
			if(persuaded):
				addDisabledButton("Talk them out of it", "You already tried.")
			else:
				addButton("Talk them out of it", "Whether it works depends on how much they trust and respect you", "persuade")
			addButton("Refuse", "Say no. They will not like it", "refuse")
		_:
			ownerLine(TextScript.intimacyForce(styleName))
			addButton("Endure it", "You cannot stop them", "force")

func intimacy_do(_id:String, _args:Array):
	var kind:int = ConsentScript.CONSENSUAL
	match(_id):
		"decline":
			lastText = TextScript.intimacyWentOff("ask")
			setState("declined")
			return
		"persuade":
			persuaded = true
			if(OwnershipGameScript.intimacyNegotiationWorks()):
				lastText = TextScript.intimacyWentOff("demand")
				setState("declined")
			else:
				lastText = "They are not in a mood to be talked out of it."
				setState("intimacy_refused")
			return
		"refuse":
			lastText = TextScript.intimacyWentOff("demand")
			setState("declined_hard")
			return
		"obey":
			kind = ConsentScript.COERCED
		"force":
			kind = ConsentScript.FORCED
	startedKind = kind
	svc().noteIntimacy(OwnershipGameScript.today())
	runSexTo(kind)

var startedKind:int = ConsentScript.CONSENSUAL

# The one scene: the game's own sex engine, run by the owner event runner; the sandbox aftermath is applied once from its result.
func runSexTo(kind:int) -> void:
	startedKind = kind
	sexApplied = false
	setState("scene")

func scene():
	playStand()
	addButton("Continue", "See what happens next", "startSex", [getOwnerID(), "pc", SexType.DefaultSex, {SexMod.DisableDynamicJoiners:true}])

func scene_sexResult(_sexResult):
	if(!sexApplied):
		sexApplied = true # (once, whatever happens to the screen afterwards)
		var _vanilla:bool = GlobalRegistry.getModule("SandboxOverhaulModule").applySexConsent(startedKind, getOwnerID(), "pc", _sexResult)
	setState("after_sex")

func after_sex():
	playStand()
	saynn("It is over.")
	addContinue("go")

func after_sex_do(_id:String, _args:Array):
	if(_id == "go"):
		if(afterSex == "rescue"):
			setState("rescue_free")
		elif(afterSex == "meeting"):
			endEvent()
		else:
			setState("sleep")

func intimacy_refused():
	playStand()
	ownerLine(lastText)
	addContinue("again")

func intimacy_refused_do(_id:String, _args:Array):
	if(_id == "again"):
		setState("intimacy")

func declined():
	playStand()
	ownerLine(lastText)
	addContinue("sleepOn")

func declined_do(_id:String, _args:Array):
	if(_id == "sleepOn"):
		declinedOn()

# After a no: a meeting just ends; an evening carries on with the stay.
func declinedOn():
	if(afterSex == "meeting"):
		endEvent()
	else:
		setState("night")

# A refusal of a demand is a small loss of their patience, not a catastrophe: a little Respect, never a Nemesis.
func declined_hard():
	playStand()
	var _r:float = OwnershipGameScript.rel().adjustFeeling(getOwnerID(), "pc", "affection", -1.0)
	ownerLine(lastText)
	addContinue("sleepOn")

func declined_hard_do(_id:String, _args:Array):
	if(_id == "sleepOn"):
		declinedOn()

# ---- The owner frees the restrained player ----
func rescue():
	playStand()
	var styleName:String = svc().style()
	ownerLine(TextScript.rescueLine(styleName))
	if(styleName == StyleScript.HARSH && OwnershipGameScript.playerIsRestrained() && !OwnershipGameScript.birthImminent()):
		ownerLine(TextScript.rescuePrice(styleName))
		addButton("Pay the price", "Let them have what they want first", "price")
		addButton("Not now", "Ask them to just take them off", "free")
	else:
		addContinue("free")

func rescue_do(_id:String, _args:Array):
	if(_id == "price"):
		intent = "demand"
		afterSex = "rescue"
		startedKind = ConsentScript.COERCED
		setState("scene")
		return
	if(_id == "free"):
		setState("rescue_free")

func rescue_free():
	playStand()
	if(!rescued):
		rescued = true
		var count:int = OwnershipGameScript.removePlayerRestraints()
		svc().markRescueDone()
		saynn("{npc.name} takes your restraints off." if count > 0 else "{npc.name} checks you over. There is nothing left to take off.")
	else:
		saynn("{npc.name} nods. You are free.")
	if(svc().style() == StyleScript.CONTROLLING):
		ownerLine("Be more careful. I will not always be this close.")
	addContinue("endEvent")

func rescue_free_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

# ---- A demand ----
func demand():
	playStand()
	var s = svc()
	if(!s.hasDemand() || s.demand()["state"] != "offered"):
		setState("nothing")
		return
	var d:Dictionary = s.demand()
	var ctx:Dictionary = OwnershipGameScript.demandContext()
	var hours:int = int(max(1, round(float(int(d["deadline"]) - OwnershipGameScript.clockNow()) / 3600.0)))
	saynn("{npc.name} has something for you.")
	ownerLine(TextScript.demandSpeech(s.style(), d, ctx))
	saynn("[color=#c8c8d8]" + TextScript.demandPanel(d, ctx, hours) + "[/color]")
	addButton("Agree", "Do as they ask", "agree")
	if(d["negotiated"]):
		addDisabledButton("Ask for easier terms", "You already asked.")
	else:
		addButton("Ask for easier terms", "See whether they will ease it. How open they are depends on how much they trust and respect you, and on what kind of owner they are.", "negotiate")
	addButton("Refuse", "Say no. It counts as a miss, and costs you their trust, but not your pride.", "refuse")

func demand_do(_id:String, _args:Array):
	var s = svc()
	if(_id == "agree"):
		var _ok:bool = OwnershipGameScript.demandAccept()
		setState("demand_agreed")
	if(_id == "negotiate"):
		var res:Dictionary = OwnershipGameScript.demandNegotiate()
		lastText = TextScript.negotiateSpeech(str(res.get("result", "refused")), s.style())
		setState("demand_negotiated")
	if(_id == "refuse"):
		var _lvl:int = OwnershipGameScript.demandRefuse()
		setState("demand_refused")

func demand_agreed():
	playStand()
	ownerLine(TextScript.demandAgreeSpeech(svc().style()))
	saynn("[color=#c8c8d8]Added to your Side Tasks.[/color]")
	addContinue("endEvent")

func demand_agreed_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

func demand_negotiated():
	playStand()
	ownerLine(lastText)
	addContinue("again")

func demand_negotiated_do(_id:String, _args:Array):
	if(_id == "again"):
		setState("demand")

func demand_refused():
	playStand()
	ownerLine(TextScript.demandRefuseSpeech(svc().style()))
	saynn("[color=#c8c8d8]A warning is noted. Your owner will deal with it when they next see you.[/color]")
	addContinue("endEvent")

func demand_refused_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

# ---- Handing over, or reporting a finished task ----
var handoverText:String = "" # (the report is applied once; drawing the screen again shows the same words and changes nothing)

func handover():
	playStand()
	if(handoverText == ""):
		var result:Dictionary = OwnershipGameScript.demandHandOver()
		if(bool(result["ok"])):
			handoverText = str(result["text"])
		else:
			saynn(str(result["text"]))
			addContinue("endEvent")
			return
	saynn(handoverText)
	addContinue("endEvent")

func handover_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

# ---- Confrontation ----
func confront():
	playStand()
	var s = svc()
	var pending:Dictionary = s.pendingConfront()
	if(!pending.empty()):
		level = int(pending["level"])
	var styleName:String = s.style()
	ownerLine(TextScript.confrontSpeech(styleName, level, str(pending.get("reason", "did not do as you were told"))))
	var owed:int = OwnershipGameScript.compensationFor(styleName)
	match(level):
		1:
			addButton("Apologise", "Say you are sorry and mean it", "apologise")
			addButton("Submit", "Accept the warning without a fuss. It lowers your Defiance a little.", "submit")
		2:
			if(GM.pc.getCredits() >= owed):
				addButton("Pay " + str(owed) + " credits", "Make it right with a payment", "pay")
			else:
				addDisabledButton("Pay " + str(owed) + " credits", "You do not have that much.")
			addButton("Apologise", "Say you are sorry. They may or may not believe you.", "apologise")
			if(apologised):
				addDisabledButton("Ask for easier terms", "They have heard enough from you.")
			else:
				addButton("Ask for easier terms", "Ask them to settle for less", "negotiate")
		_:
			addButton("Take the punishment", "Accept what is coming. It will be the usual punishment.", "take")
			addButton("Apologise", "Beg, and hope", "apologise")
	addButton("Resist", "Refuse and fight, or back down at the last moment", "resist")

func confront_do(_id:String, _args:Array):
	var styleName:String = svc().style()
	if(_id == "resist"):
		setState("resist")
		return
	var effect:Dictionary = OwnershipGameScript.applyConfront(_id, level)
	if(effect["refused"]):
		apologised = true
		lastText = TextScript.apologyRefused(styleName) if str(effect["text"]) == "refused" else "You cannot afford that."
		setState("confront_refused")
		return
	lastText = ""
	match(str(effect["text"])):
		"accepted":
			lastText = TextScript.apologyAccepted(styleName)
		"paid":
			lastText = "They take the credits and say nothing more about it."
		"eased":
			lastText = TextScript.negotiateSpeech("eased", styleName)
		"punished":
			lastText = "They nod, and it begins."
	if(effect["punish"]):
		setState("punishing")
	else:
		setState("settled")

func confront_refused():
	playStand()
	if(lastText == "You cannot afford that."):
		saynn(lastText)
	else:
		ownerLine(lastText)
	addContinue("again")

func confront_refused_do(_id:String, _args:Array):
	if(_id == "again"):
		setState("confront")

func settled():
	playStand()
	if(lastText != ""):
		if(lastText.begins_with("They ")):
			saynn(lastText)
		else:
			ownerLine(lastText)
	saynn("[color=#c8c8d8]Settled. The warning is dealt with.[/color]")
	addContinue("settledOn") # (not "endEvent": the base class ends the event for that id before any state code can run)

func settled_do(_id:String, _args:Array):
	if(_id == "settledOn"):
		if(fromCheckin):
			fromCheckin = false
			setState("night") # the warning is dealt with; the evening goes on
		else:
			endEvent()

func punishing():
	playStand()
	saynn(lastText)
	addContinue("startPunish")

func punishing_do(_id:String, _args:Array):
	if(_id == "startPunish"):
		startOwnerPunishment()

# The game's own punishment event (Punish and the punishment it picks) runs as a child of this one. When it ends, this event gets the callback (reactEnded below) and decides what the evening does next.
# Punishments that put the player somewhere for the night (stocks, slutwall, being sold on, the test subject room) end the conversation: their own code stops the runner afterwards.
const PUNISH_REPLACES_NIGHT = ["Punish2Slutwall", "Punish2Stocks", "Punish3Sell", "Punish3TestSubject"]

func startOwnerPunishment():
	if(punishStarted):
		return
	punishStarted = true
	var theOwner = getNpcOwner()
	punishInfluence = float(theOwner.influence) if theOwner != null else -1.0
	runPunishment()
	notePunishKind()

# Which punishment the game picked: the event now running under this one.
func notePunishKind():
	var top = getRunner().getCurrentEvent()
	punishKind = str(top.id) if (top != null && top != self) else ""

func reactEnded(_event, _tag:String, _args:Array):
	if(_tag == "punishment"):
		onPunishmentEnded()
		return
	.reactEnded(_event, _tag, _args)

func onPunishmentEnded():
	if(punishDone):
		return # (once)
	punishDone = true
	var theOwner = getNpcOwner()
	if(theOwner != null && punishInfluence >= 0.0 && float(theOwner.influence) < punishInfluence - 0.0001):
		fromCheckin = false # the player fought the punishment off: the owner cannot enforce the evening normally
		setState("punish_beaten")
		return
	if(PUNISH_REPLACES_NIGHT.has(punishKind)):
		nightReplaced = true
		OwnershipGameScript.punishmentCoversNight()
		setState("punish_replaced")
		return
	setState("punish_after")

func punish_after():
	playStand()
	ownerLine(TextScript.punishAfter(svc().style(), fromCheckin))
	addContinue("on")

func punish_after_do(_id:String, _args:Array):
	if(_id == "on"):
		if(fromCheckin):
			fromCheckin = false
			setState("night") # the evening goes on: the stay, in the owner's bed
		else:
			endEvent()

func punish_beaten():
	playStand()
	ownerLine(TextScript.ownerBeaten(svc().style()))
	addContinue("endEvent")

func punish_beaten_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

func punish_replaced():
	playStand()
	ownerLine(TextScript.punishReplaces(svc().style()))
	addContinue("endEvent")

func punish_replaced_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

# ---- Resisting ----
func resist():
	playAnimation(StageScene.Duo, "stand", {npc=getOwnerID()})
	saynn("You square up to {npc.name}. {npc.He} " + ("hesitates." if svc().recentOwnerLosses(OwnershipGameScript.today()) >= 2 else "does not back down."))
	addButton("Fight", "Fight them. If you win, they back off for at least two days and begin to fear you. If you lose, you are punished.", "startFight", [getOwnerID()])
	addButton("Back down", "Step back at the last moment. It is milder than losing: you pay what is owed and lose a little standing.", "backdown")

func resist_do(_id:String, _args:Array):
	if(_id == "backdown"):
		var _effect:Dictionary = OwnershipGameScript.confrontBackDown(level)
		lastText = TextScript.backDownSpeech(svc().style())
		setState("settled")

func resist_fightResult(_didWin:bool):
	var result:Dictionary = OwnershipGameScript.confrontFight(_didWin)
	if(result["won"]):
		setState("fightWon")
	else:
		setState("fightLost")

func fightWon():
	playAnimation(StageScene.Duo, "stand", {npc=getOwnerID(), npcAction="kneel"})
	saynn("You won. {npc.name} is on {npc.his} knees in front of you.")
	ownerLine(TextScript.fightWonSpeech(svc().style()))
	if(fromCheckin):
		fromCheckin = false # (the evening does not carry on: they cannot make the player stay tonight)
		ownerLine(TextScript.ownerBeaten(svc().style()))
	addInfluenceResist()
	var wins:int = svc().distinctWins()
	var needed:int = int(svc().styleParams()["release_wins"])
	saynn("[color=#c8c8d8]The consequence is over. They will keep their distance for a couple of days. You have beaten them on " + str(wins) + " separate day" + ("s" if wins != 1 else "") + (" - enough to demand release." if wins >= needed else " (" + str(needed) + " are needed to demand release).") + "[/color]")
	addContinue("endEvent")

func fightWon_do(_id:String, _args:Array):
	if(_id == "endEvent"):
		endEvent()

func fightLost():
	playAnimation(StageScene.Duo, "kneel", {npc=getOwnerID()})
	saynn("You lost the fight.")
	ownerLine(TextScript.fightLostSpeech(svc().style()))
	addContinue("startPunish")

func fightLost_do(_id:String, _args:Array):
	if(_id == "startPunish"):
		startOwnerPunishment()

# ---- Terms and ways out ----
func terms():
	playStand()
	var lines:Array = OwnershipGameScript.summaryLines()
	saynn("{npc.name} is your owner.\n\n" + PoolStringArray(lines).join("\n"))
	addButton("Discuss release", "See how you could get out of this", "release")
	addButton("Back", "Leave it for now", "endEvent")

func terms_do(_id:String, _args:Array):
	if(_id == "release"):
		setState("release")
	if(_id == "endEvent"):
		endEvent()

func release():
	playStand()
	var s = svc()
	var lines:Array = []
	for route in OwnershipGameScript.releaseRoutes():
		var mark:String = "[color=green]available[/color]" if route["available"] else "[color=#a0a0a0]not yet[/color]"
		lines.append("[b]" + str(route["name"]) + "[/b] (" + mark + "): " + str(route["text"]))
	saynn("You ask what it would take to be free.\n\n" + PoolStringArray(lines).join("\n\n"))
	if(OwnershipGameScript.routeAvailable("negotiate")):
		addButton("Ask to be released", "Ask them to let you go", "negotiate")
	else:
		addDisabledButton("Ask to be released", "Not available yet.")
	var cost:int = 0
	for route in OwnershipGameScript.releaseRoutes():
		if(route["id"] == "buyout"):
			cost = int(route["cost"])
	if(OwnershipGameScript.routeAvailable("buyout")):
		addButton("Pay " + str(cost) + " credits", "Buy your freedom", "buyout")
	else:
		addDisabledButton("Buy your freedom", "Not available right now.")
	if(OwnershipGameScript.routeAvailable("defy")):
		addButton("Demand release", "You have beaten them often enough. Tell them it is over.", "defy")
	else:
		addDisabledButton("Demand release", "You need to beat them on " + str(s.styleParams()["release_wins"]) + " separate days first.")
	addButton("Back", "Not now", "endEvent")

func release_do(_id:String, _args:Array):
	if(_id == "negotiate"):
		setState("release_negotiate")
	if(_id == "buyout"):
		var result:Dictionary = OwnershipGameScript.buyout()
		lastText = str(result["text"])
		released = bool(result["ok"])
		setState("release_done")
	if(_id == "defy"):
		var res:Dictionary = OwnershipGameScript.demandRelease()
		lastText = str(res["text"])
		released = bool(res["ok"])
		setState("release_done")
	if(_id == "endEvent"):
		endEvent()

func release_negotiate():
	playStand()
	var result:Dictionary = OwnershipGameScript.negotiateRelease(false)
	saynn(str(result["text"]))
	if(result.get("asking", false)):
		var due:int = int(result["needs"])
		if(GM.pc.getCredits() >= due):
			addButton("Agree" + (" and pay " + str(due) if due > 0 else ""), "Take the deal", "confirm")
		else:
			addDisabledButton("Agree", "You cannot pay that yet.")
	addButton("Back", "Not now", "back")

func release_negotiate_do(_id:String, _args:Array):
	if(_id == "confirm"):
		var result:Dictionary = OwnershipGameScript.negotiateRelease(true)
		lastText = str(result["text"])
		released = bool(result["ok"])
		setState("release_done")
	if(_id == "back"):
		setState("release")

func release_done():
	playStand()
	saynn(lastText)
	if(released):
		saynn("[color=#c8c8d8]You are no longer owned.[/color]")
	addContinue("finish")

func release_done_do(_id:String, _args:Array):
	if(_id == "finish"):
		if(released):
			stopRunner()
		endEvent()

func saveData() -> Dictionary:
	var data := .saveData()
	data["level"] = level
	data["lastText"] = lastText
	data["apologised"] = apologised
	data["released"] = released
	data["intent"] = intent
	data["persuaded"] = persuaded
	data["afterSex"] = afterSex
	data["rescued"] = rescued
	data["checkedIn"] = checkedIn
	data["handoverText"] = handoverText
	data["punishStarted"] = punishStarted
	data["punishKind"] = punishKind
	data["punishDone"] = punishDone
	data["punishInfluence"] = punishInfluence
	data["nightReplaced"] = nightReplaced
	data["pregBack"] = pregBack
	data["pregText"] = pregText
	data["sexApplied"] = sexApplied
	data["purpose"] = purpose
	data["checkText"] = checkText
	data["praiseNote"] = praiseNote
	data["rewardCredits"] = rewardCredits
	data["fromCheckin"] = fromCheckin
	data["startedKind"] = startedKind
	return data

func loadData(_data:Dictionary):
	.loadData(_data)
	level = SAVE.loadVar(_data, "level", 1)
	lastText = SAVE.loadVar(_data, "lastText", "")
	apologised = SAVE.loadVar(_data, "apologised", false)
	released = SAVE.loadVar(_data, "released", false)
	intent = SAVE.loadVar(_data, "intent", "")
	persuaded = SAVE.loadVar(_data, "persuaded", false)
	afterSex = SAVE.loadVar(_data, "afterSex", "")
	rescued = SAVE.loadVar(_data, "rescued", false)
	checkedIn = SAVE.loadVar(_data, "checkedIn", false)
	handoverText = SAVE.loadVar(_data, "handoverText", "")
	punishStarted = SAVE.loadVar(_data, "punishStarted", false)
	punishKind = SAVE.loadVar(_data, "punishKind", "")
	punishDone = SAVE.loadVar(_data, "punishDone", false)
	punishInfluence = SAVE.loadVar(_data, "punishInfluence", -1.0)
	nightReplaced = SAVE.loadVar(_data, "nightReplaced", false)
	pregBack = SAVE.loadVar(_data, "pregBack", "")
	pregText = SAVE.loadVar(_data, "pregText", "")
	sexApplied = SAVE.loadVar(_data, "sexApplied", false)
	purpose = SAVE.loadVar(_data, "purpose", "")
	checkText = SAVE.loadVar(_data, "checkText", "")
	praiseNote = SAVE.loadVar(_data, "praiseNote", "")
	rewardCredits = SAVE.loadVar(_data, "rewardCredits", 0)
	fromCheckin = SAVE.loadVar(_data, "fromCheckin", false)
	startedKind = SAVE.loadVar(_data, "startedKind", ConsentScript.CONSENSUAL)

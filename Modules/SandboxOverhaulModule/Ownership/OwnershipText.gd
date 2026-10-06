extends Reference

# What owners say and the plain information next to it. No game access, so it can be tested on its own. Owners speak in their own voice (one line each, by style); facts (deadlines, costs, protection) are
# given separately by the caller as plain lines, never in a character's mouth.

const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")

static func say(speakerID:String, text:String) -> String:
	return "[say=" + speakerID + "]" + text + "[/say]"

static func pick(style:String, lenient:String, controlling:String, harsh:String) -> String:
	match(style):
		StyleScript.LENIENT:
			return lenient
		StyleScript.HARSH:
			return harsh
	return controlling

# ---- After a punishment ----
static func punishAfter(style:String, evening:bool) -> String:
	if(!evening):
		return pick(style, "I do not enjoy doing that. It is behind us now.", "That matter is settled. Do not make me raise it again.", "Now that you remember your place, do not forget it.")
	return pick(style, "I do not enjoy doing that. Stay here tonight, and we will put it behind us.", "That matter is settled. You will remain here for the night.", "Now that you remember your place, you are staying here tonight.")

static func punishReplaces(_style:String) -> String:
	return "You will not be sharing my bed tonight. You will spend the night where I put you."

static func ownerBeaten(_style:String) -> String:
	return "There is no making you stay tonight, is there? Fine. Go where you like. This is not over."

# ---- Pregnancy ----
# parentage: "owner" (they are recorded as possible or actual father), "other" (somebody else is) or "unknown" (nothing is recorded: never claim certainty).
static func pregnancyNotice(style:String, parentage:String, affection:float, desire:float) -> String:
	var warm:bool = affection >= 15.0 || desire >= 30.0
	if(parentage == "owner"):
		if(style == StyleScript.HARSH):
			return "Wait... is that mine? " + ("Good. Then it is mine twice over." if warm else "You will tell me exactly what is going on, and what you plan to do about it.")
		if(style == StyleScript.CONTROLLING):
			return "Wait... is that mine? You should have told me. I want to know everything about it from now on."
		return "Wait... is that mine? " + ("Oh. Come here. Are you all right?" if warm else "Tell me honestly. I will not be angry.")
	if(parentage == "other"):
		if(style == StyleScript.HARSH):
			return ("Whose is that? Somebody touched what is mine." if desire >= 30.0 || affection >= 15.0 else "That belly. Who is the father? You will tell me, and you will not lie to me.")
		if(style == StyleScript.CONTROLLING):
			return "You are pregnant. Who is the father? I want a name, and I want to hear how it happened."
		return "You are pregnant. Are you all right? Is somebody looking after you?"
	if(style == StyleScript.HARSH):
		return "That belly. I cannot tell whose it is, and I do not like not knowing. Is it mine?"
	if(style == StyleScript.CONTROLLING):
		return "You are pregnant. I cannot tell whose it is. Is it mine? Tell me what you know."
	return "You are pregnant... I did not realise. I cannot tell whose it is. Are you all right?"

static func birthNotice(style:String) -> String:
	return pick(style, "It is time, is it not? Let me help. I can take you to the nursery, or you can go on your own, whichever you prefer.", "It is time. I am coming with you to the nursery. Unless you would rather go alone.", "It is time. I am taking you to the nursery. You can argue about it afterwards.")

static func birthAlone(style:String) -> String:
	return pick(style, "All right. Go. Send for me if you need me.", "Go, then. Do not take your time about it.", "Go. Come straight back to me afterwards.")

# ---- Meetings, praise and rewards ----
static func praiseLine(style:String) -> String:
	return pick(style, "You have been dependable lately. I noticed, and I am grateful.", "You have been behaving. Keep it up and you will find me easy to live with.", "You have been obedient. I noticed. Do not make me regret saying so.")

static func praiseNote(kind:String) -> String:
	if(kind == "warning"):
		return "They let the last small matter go."
	if(kind == "demand"):
		return "They will not ask anything of you for a day."
	return ""

static func rewardLine(style:String) -> String:
	return pick(style, "I promised you something. Here. You have earned it.", "I said there would be something for good behaviour. Here. Do not spend it all in one place.", "I keep my promises. Take it. And remember who gives it to you.")

static func attentionLine(style:String) -> String:
	return pick(style, "I wanted to see you, that is all. How are you holding up? Eat something. Stay safe.", "I like to know how you are, and where. Tell me about your day.", "I wanted to look at you. Mine. Now tell me where you have been, and who you spoke to.")

static func attentionClose(style:String) -> String:
	return pick(style, "Good. Come and find me whenever you like.", "Good. Do not make me come looking for you.", "That will do. Do not wander off.")

static func settledAlready(_style:String) -> String:
	return "Never mind. It is already dealt with."

# What the player is told about a meeting before it happens. Sensitive details stay hidden: only the broad kind is said.
static func meetingHint(purpose:String) -> String:
	match(purpose):
		"demand":
			return "has something they want you to do"
		"warning":
			return "expects you for a warning"
		"compensation":
			return "expects you to settle something"
		"punishment":
			return "has not forgotten what you owe"
		"reward":
			return "has promised you a reward"
	return "wants to speak with you"

static func meetingShort(purpose:String) -> String:
	match(purpose):
		"warning", "compensation", "punishment":
			return "something is owed"
		"reward":
			return "a reward"
	return "to talk"

# ---- The evening at the owner's, and the rescue ----
static func nightRequire(style:String) -> String:
	return pick(style, "I would like you to stay tonight. Please.", "You are staying tonight. Do not make a fuss about it.", "You stay. That is not a question.")

static func nightInvite(style:String) -> String:
	return pick(style, "You could stay, if you like. I would enjoy the company.", "Stay a while. I would like you to.", "Stay. Or go. But I would rather you stayed.")

static func nightAllow(style:String) -> String:
	return pick(style, "That is all for tonight. Sleep well. You may stay if you want to.", "That will do. You may go.", "Go on, then. I have no use for you tonight.")

static func intimacyAsk(style:String) -> String:
	return pick(style, "Would you like to spend the night with me, properly? You can say no.", "I would like you tonight. Would you? I will not insist.", "I want you tonight. You may say no, and I will hear it.")

static func intimacyDemand(style:String) -> String:
	return pick(style, "Tonight you are mine. I do hope you will not argue.", "I want you tonight. I expect you to oblige me.", "You are mine tonight. Do not argue.")

static func intimacyForce(style:String) -> String:
	return pick(style, "Come here. This is not up for discussion.", "Come here. I am not asking.", "Strip. I am taking what is mine, and I am not asking.")

static func intimacyWentOff(kind:String) -> String:
	match(kind):
		"ask":
			return "Of course. Another night, then. Sleep well."
		"demand":
			return "Hmph. Fine. Not tonight."
	return "Tch. Fine. Get out of my sight."

static func rescueLine(style:String) -> String:
	return pick(style, "Oh, no. Hold still, I will have those off you in a moment.", "Look at the state of you. Hold still. I will help you, but you are still mine.", "I told you what happens when you are careless. Hold still. I will help you, but you are still mine.")

static func rescuePrice(style:String) -> String:
	return pick(style, "There. Better. You are mine, and I do not like others touching what is mine.", "There. You can thank me later.", "I will take them off, but you are still mine, and I will have something for it first.")

# ---- Check-in ----
static func checkinSpeech(style:String, timing:String) -> String:
	match(timing):
		"early":
			return pick(style, "You are early. Sit down, then. Good to see you.", "Early. Good. That is how it should be.", "Early? Good. Keep it up and we will get along.")
		"late":
			return pick(style, "Late, but you came. Do not make a habit of it.", "You are late. Do not let it become a habit.", "Late. Next time it will cost you.")
	return pick(style, "Right on time. Thank you.", "On time. Good.", "On time. As you should be.")

static func checkinEffects(timing:String) -> Dictionary:
	if(timing == "late"):
		return {"trust": 0.5, "respect": 0.0, "defiance": 0.0}
	return {"trust": 2.0, "respect": 0.5, "defiance": -0.5}

static func checkinNote(timing:String) -> String:
	match(timing):
		"early":
			return "Checked in early."
		"late":
			return "Checked in late. Counted, with less credit."
	return "Checked in on time."

static func tooSoonNote() -> String:
	return "It is too early to report in. They expect you from 20:30, and properly between 21:00 and 23:00."

static func windowText() -> String:
	return "21:00 to 23:00"

# ---- Demands ----
static func demandSpeech(style:String, d:Dictionary, ctx:Dictionary) -> String:
	var what:String = str(ctx.get("itemName", "that thing"))
	match(str(d.get("type", ""))):
		"credits":
			return pick(style, "Could you spare " + str(d.get("amount", 0)) + " credits? Bring them to me when you can.", "I need " + str(d.get("amount", 0)) + " credits. Bring them to me.", "Give me " + str(d.get("amount", 0)) + " credits. Now, or close enough to it.")
		"item":
			return pick(style, "I could use a " + what + ". Bring me one if you can.", "I want a " + what + ". Bring it to me.", "Bring me a " + what + ". Do not make me ask twice.")
		"contraband":
			return "I want a " + what + ", something that should not be in here. You know how to get it. Bring it to me."
		"shift":
			return pick(style, "You have a job, do you not? Put in a full shift and let me know.", "You work. Do a full shift and report to me when it is done.", "Get to work. A full shift. Then tell me it is done.")
		"report":
			return "Be at my cell at " + str(ctx.get("timeText", "the time I said")) + ". Do not make me wait."
		"defeat":
			return str(ctx.get("targetName", "Someone")) + " has been getting on my nerves. Put them down, then tell me about it."
	return "I have something for you."

static func demandAgreeSpeech(style:String) -> String:
	return pick(style, "Thank you. I will be waiting.", "Good. Do not let me down.", "Good. Do not make me come looking for you.")

static func demandRefuseSpeech(style:String) -> String:
	return pick(style, "I thought you might say that. I will not forget it.", "Refusing me? You will hear about this.", "You do not say no to me. Remember that.")

static func negotiateSpeech(result:String, style:String) -> String:
	match(result):
		"eased":
			return pick(style, "Fine, fine. Half of it will do.", "All right. Half. Do not push your luck.", "Half. This once.")
		"extended":
			return pick(style, "Take another day, then.", "One more day. Not two.", "One more day. That is all you get.")
		"replaced":
			return pick(style, "That is too much to ask of you. A few credits will do instead.", "Too much for you? A few credits, then.", "You are not up to it. Pay me instead.")
		"already":
			return "I already heard your side."
	return pick(style, "No. I am sorry.", "No.", "No. Do as you are told.")

static func demandObjective(d:Dictionary, ctx:Dictionary) -> String:
	var what:String = str(ctx.get("itemName", "the item"))
	match(str(d.get("type", ""))):
		"credits":
			return "Give " + str(ctx.get("owner", "your owner")) + " " + str(d.get("amount", 0)) + " credits"
		"item", "contraband":
			return "Bring " + str(ctx.get("owner", "your owner")) + " a " + what
		"shift":
			return "Work a full shift, then report to " + str(ctx.get("owner", "your owner"))
		"report":
			return "Be at " + str(ctx.get("owner", "your owner")) + "'s cell at " + str(ctx.get("timeText", "the time given"))
		"defeat":
			return "Defeat " + str(ctx.get("targetName", "the named inmate")) + ", then report to " + str(ctx.get("owner", "your owner"))
	return "Do what your owner asked"

static func demandPanel(d:Dictionary, ctx:Dictionary, hours:int) -> String:
	var lines:Array = [
		"[b]Objective:[/b] " + demandObjective(d, ctx),
		"[b]Time limit:[/b] " + str(hours) + (" hour" if hours == 1 else " hours"),
		"[b]Reward:[/b] their trust, respect and a little warmth",
		"[b]If you refuse or fail:[/b] a warning first, and worse if it keeps happening; being late counts for less than not appearing",
	]
	return PoolStringArray(lines).join("\n")

static func demandDoneSpeech(style:String, _type:String) -> String:
	return pick(style, "Thank you. I appreciate that.", "Well done. I knew you could handle it.", "Good. At least you understand what I expect.")

# ---- Confrontation ----
static func confrontSpeech(style:String, level:int, reason:String) -> String:
	match(level):
		1:
			return pick(style, "You missed something I asked of you. Do not let it happen again.", "You " + reason + ". That is a warning.", "You " + reason + ". I will say this once.")
		2:
			return pick(style, "I asked politely and you let me down. I think you owe me something for it.", "You have done it again. Make it right: pay me.", "Twice now. You will pay for it.")
	return pick(style, "I have been patient, and you kept testing me. Now there are consequences.", "Enough warnings. You are going to be dealt with.", "No more warnings. Now you learn.")

static func confrontLevelName(level:int) -> String:
	match(level):
		1:
			return "a warning"
		2:
			return "a demand for compensation"
	return "a punishment"

static func apologyAccepted(style:String) -> String:
	return pick(style, "I accept that. Thank you.", "Fine. Do not make me regret it.", "Fine. Once.")

static func apologyRefused(style:String) -> String:
	return pick(style, "I would like to believe you, but I need more than words.", "Words are cheap.", "Words are worth nothing to me.")

static func backDownSpeech(style:String) -> String:
	return pick(style, "That is the sensible thing. Pay what you owe and we are done.", "Smart. Pay up and we will leave it there.", "Smart. Now pay, and kneel while you do it.")

static func fightWonSpeech(style:String) -> String:
	return pick(style, "All right. All right. You win. I will leave you be.", "Ugh. Fine. Not today. I will not bother you.", "...Fine. You made your point. Stay out of my sight for a while.")

static func fightLostSpeech(style:String) -> String:
	return pick(style, "You should not have made me do that.", "That was a mistake, and you made it.", "Stupid. Now you will pay for it.")

# ---- Release ----
static func releaseSpeech(how:String, style:String) -> String:
	match(how):
		"negotiate":
			return pick(style, "You have been good to me. Go, and take care of yourself.", "You have earned it. You are free to go.", "You have earned it. Do not make me regret this.")
		"buyout":
			return pick(style, "That will do. You are free, and no hard feelings.", "A deal is a deal. Go.", "Pay and go. And stay out of my way.")
		"defy":
			return pick(style, "Fine. You have shown me what you are. Go.", "I cannot keep you. Go.", "...I cannot make you stay. Get out of my sight.")
		"afraid":
			return "I do not want you near me. Go. I do not own you."
		"fond":
			return "I do not think I should hold on to you. Go. Come see me if you want to."
	return "You are free."

static func releaseRefused(style:String) -> String:
	return pick(style, "Not yet. I would like to, but not yet.", "No. Not yet.", "No. You belong to me. Ask again when you have earned it.")

static func finalPaymentText(style:String, credits:int) -> String:
	if(credits <= 0):
		return "They ask nothing more of you."
	return "Before they let you go, " + pick(style, "they ask for a small thank-you", "they want a last payment", "they want one last payment") + " of " + str(credits) + " credits."

# ---- The ownership screen ----
static func protectionLine(band:String) -> String:
	return "Protection: " + band

static func nextCheckinLine(day:int, nextDay:int, pending:bool, windowStateText:String) -> String:
	if(pending):
		return "Tonight, " + windowText() + " (" + windowStateText + ")"
	if(nextDay <= day):
		return "Tonight, " + windowText()
	var gap:int = nextDay - day
	return "In " + str(gap) + (" night" if gap == 1 else " nights")

# ---- Slaves ----
static func holdingUp(disposition:String, role:String, hurt:bool, tired:bool) -> String:
	var lines:Array = []
	match(disposition):
		"loyal":
			lines.append("I am fine. Better than I would have thought, to be honest. You treat me well.")
		"intimidated":
			lines.append("I am fine. I am doing what I am told. Please do not make it worse.")
		"resentful":
			lines.append("How do you think? I did not choose this. You could be better at it.")
		"defiant":
			lines.append("Do not bother asking. I am not your friend, and I am not afraid of you.")
		"recovering":
			lines.append("Better, thank you. A bit of rest helps.")
		_:
			lines.append("I am getting by. I am still working out what you want from me.")
	match(role):
		"earner":
			lines.append("The work is draining, but I am doing it.")
		"attendant":
			lines.append("I am keeping an eye on things around you.")
		"rest":
			lines.append("Having no duties for a while is a relief.")
	if(hurt):
		lines.append("My injuries still hurt.")
	if(tired):
		lines.append("I am worn out.")
	return PoolStringArray(lines).join(" ")

static func roleLine(role:String, willing:bool) -> String:
	var base:String = "I am on " + str(role) + " duty."
	if(role == "free"):
		base = "I just follow the usual day. Nothing special."
	elif(role == "rest"):
		base = "I have no duties for now."
	return base + ("" if willing else " I would rather not.")

static func refuseDuty(role:String, disposition:String) -> String:
	if(disposition == "defiant"):
		return "No. I am not doing that for you."
	if(role == "earner"):
		return "I do not want to do that. Do not make me."
	return "I would rather not."

static func telegraphWarning(slaveName:String, why:String) -> String:
	return "[color=orange]" + slaveName + " has been keeping to themselves and watching the exits (" + why + "). It might be worth talking to them.[/color]"

static func telegraphAttempt(slaveName:String) -> String:
	return "[color=red]" + slaveName + " is trying to slip away from you! Find them and do something about it before they are gone.[/color]"

static func telegraphGone(slaveName:String) -> String:
	return "[color=orange]" + slaveName + " got away. They are a free inmate again, and they remember how they were treated.[/color]"

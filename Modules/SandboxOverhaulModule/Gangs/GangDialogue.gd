extends Reference
class_name GangDialogue

# What gang leaders say, and the short information panels that go with it. No game access, so it can be tested on its own.
#
# Character speech and system information are kept apart: a leader talks in their own voice ("You want a place with Ironhand? ..."), and the facts of an assignment (objective, reward,
# failure, time limit) are shown once, in a plain panel below, never recited by the character. The same functions feed the conversation screens and the Side Tasks entry.
#
# ctx (all text already resolved by the caller): {"gang": display name, "leader": leader's name, "target": name, "targetGang": their gang's name or "" when the player does not know it,
# "recipientGang": same for a courier's recipient, "rival": name (rescue), "amount": credits, "item": bool}.

const MINUS = "−"

const GANG_IDS = ["ironhand", "hushmarket", "collarcircle"]

# The three commitments a new member agrees to. Roleplay only: nothing enforces them.
const CODES = {
	"ironhand": ["Stand beside fellow members.", "Show strength against rivals.", "Put Ironhand before outsiders."],
	"hushmarket": ["Keep the gang's secrets.", "Honour bargains made through the gang.", "Protect its trade and members."],
	"collarcircle": ["Respect the gang hierarchy.", "Help enforce its claims.", "Protect members and controlled assets."],
}

const INITIATION = {
	"ironhand": "You have shown what you are made of. Before you wear the name, you should know what it asks of you.",
	"hushmarket": "You kept your head, and the job got done. Before I tell you how the Market works, understand what it asks of you.",
	"collarcircle": "You did what was asked and you did not flinch. If you are to join the Circle, you should know what we expect.",
}

const WELCOME = {
	"ironhand": "Then you are Ironhand now. Stand with us and we will stand with you.",
	"hushmarket": "Then you are one of the Market now. Keep your word and keep it quiet, and you will do well here.",
	"collarcircle": "Then you belong to the Circle now. Know your place and you will rise.",
}

const NOT_YET = {
	"ironhand": "Take your time. The offer does not go away. Come back when you are ready to stand with us.",
	"hushmarket": "Think it over. The offer will keep. Come back when you are ready.",
	"collarcircle": "Do not take too long. The offer stands, for now. Come back when you are ready.",
}

const ACCEPT = {
	"ironhand": "Good. Come back when it is done.",
	"hushmarket": "Good. Keep it quiet. Come back when it is done.",
	"collarcircle": "Good. Do not keep me waiting. Come back when it is done.",
}

# ---- Speech ----
# One line of a character's speech. BDCC's say tag writes the speaker's name in front of the words in the character's colour, so the name is not repeated.
static func line(_speakerName:String, speakerID:String, text:String) -> String:
	return "[say=" + speakerID + "]" + text + "[/say]"

static func codeOf(gid:String) -> Array:
	return CODES.get(gid, ["Stand by the gang.", "Keep its confidence.", "Look after its people."])

static func has(gid:String) -> bool:
	return CODES.has(gid)

static func initiationSpeech(gid:String) -> String:
	return str(INITIATION.get(gid, "You have earned a place. Before you join, you should know what is expected."))

static func welcomeSpeech(gid:String) -> String:
	return str(WELCOME.get(gid, "Then you are one of us now. Stand with us and we will stand with you."))

static func notYetSpeech(gid:String) -> String:
	return str(NOT_YET.get(gid, "Take your time. The offer stands."))

static func acceptSpeech(gid:String) -> String:
	return str(ACCEPT.get(gid, "Good. Come back when it is done."))

# A leader who is asked who leads the gang: first person for the leader, third person for everybody else.
static func whoLeads(speakerIsLeader:bool, leaderName:String, gangName:String) -> String:
	if(leaderName == ""):
		return "Nobody, right now."
	if(speakerIsLeader):
		return "I am in charge of " + gangName + "."
	return leaderName + " is in charge of " + gangName + "."

# What the leader says when naming a job. intro: the job that opens the way into the gang.
static func offerSpeech(_gid:String, type:String, intro:bool, ctx:Dictionary) -> String:
	var target:String = str(ctx.get("target", "someone"))
	var theirs:String = str(ctx.get("targetGang", ""))
	var gang:String = str(ctx.get("gang", "the gang"))
	var rivals:String = ("one of our rivals" if theirs == "" else theirs + ", one of our rivals")
	var amount:int = int(ctx.get("amount", 0))
	var recipient:String = str(ctx.get("recipientGang", ""))
	var whose:String = (" of " + recipient) if recipient != "" else ""
	if(intro):
		match(type):
			"defeat":
				return "You want a place with " + gang + "? Prove you can handle yourself. " + target + " runs with " + rivals + ". Put them down, then come back to me."
			"courier":
				return "You want in with " + gang + "? We do not take strangers on trust. Take " + str(amount) + " credits to " + target + whose + " and put them in their hand. Quietly. Then come and tell me it is done."
			"capture":
				return "You want a place in " + gang + "? Then show me you can take what you want. " + target + (" of " + theirs if theirs != "" else "") + " needs to learn their place. Beat them, then bring them to me."
		return "You want a place with " + gang + "? Do a job for me first."
	match(type):
		"defeat":
			return "I have a job for you. " + target + " runs with " + rivals + " and has been a nuisance. Put them down and come back to me."
		"deliver":
			return "I need something brought to me. " + (str(amount) + " credits, to be exact." if bool(ctx.get("credits", true)) else "You know the kind of thing, and where to find it.") + " Bring it here, and quickly."
		"capture":
			return target + (" of " + theirs if theirs != "" else "") + " has to be taken in. Beat them, then hand them over to me."
		"rescue":
			return "One of ours is being held. Get " + target + " out, or deal with " + str(ctx.get("rival", "whoever took them")) + " and the rest follows."
		"courier":
			return "I need a package carried. Take " + str(amount) + " credits to " + target + whose + " and tell me when it is done."
	return "I have something for you."

# What the leader says when the player comes back about a job that is not finished.
static func reminderSpeech(_gid:String, type:String, ctx:Dictionary) -> String:
	var target:String = str(ctx.get("target", "them"))
	match(type):
		"defeat":
			return "You know what I asked. " + target + " is still walking around."
		"capture":
			return "I am still waiting on " + target + ". Beat them, then bring them to me."
		"courier":
			return "That package will not carry itself. " + target + " is waiting."
		"rescue":
			return "Every hour they are held is an hour wasted. Get " + target + " out."
	return "I am waiting. Finish what you started."

# What the leader says when the player reports a finished job.
static func reportSpeech(gid:String, type:String, intro:bool, ctx:Dictionary) -> String:
	var target:String = str(ctx.get("target", "them"))
	var opener:String = ""
	match(type):
		"defeat":
			opener = "I heard about " + target + ". "
		"courier":
			opener = "So it reached " + target + ". "
		"capture":
			opener = target + " is ours now. "
		"rescue":
			opener = "They are back among us. "
		"deliver":
			opener = "That is what I asked for. "
	match(gid):
		"ironhand":
			return opener + ("Good work." if !intro else "That is the kind of nerve we look for.")
		"hushmarket":
			return opener + ("Well done." if !intro else "Discreet and reliable. That is rarer than strength.")
		"collarcircle":
			return opener + ("Acceptable." if !intro else "You follow orders and you follow through. Good.")
	return opener + "Good work."

# ---- Information panels (system text, never in a character's mouth) ----
static func hoursText(hours:int) -> String:
	return str(hours) + (" hour" if hours == 1 else " hours")

# How long is left: "About 47 hours remaining." / "Less than an hour remaining." / "Time is up."
static func remainingText(deadline:int, now:int, hourSeconds:int = 3600) -> String:
	var left:int = deadline - now
	if(left <= 0):
		return "Time is up."
	var hours:int = int(ceil(float(left) / float(hourSeconds)))
	if(left < hourSeconds):
		return "Less than an hour remaining."
	return "About " + str(hours) + (" hour remaining." if hours == 1 else " hours remaining.")

static func objective(a:Dictionary, ctx:Dictionary) -> String:
	var target:String = str(ctx.get("target", "them"))
	var gang:String = str(ctx.get("gang", "the gang"))
	var leader:String = str(ctx.get("leader", "the leader"))
	match(str(a.get("type", ""))):
		"defeat":
			return "Defeat " + target
		"capture":
			return ("Hand " + target + " over to " + leader) if str(a.get("stage", "")) == "defeated" else ("Capture " + target + ": beat them, then hand them over to " + leader)
		"courier":
			var recipient:String = str(ctx.get("recipientGang", ""))
			return "Deliver " + str(a.get("amount", 0)) + " credits to " + target + ((" (" + recipient + ")") if recipient != "" else "")
		"deliver":
			return "Bring " + gang + (" " + str(a.get("amount", 0)) + " credits" if str(a.get("item", "")) == "" else " the item they asked for")
		"rescue":
			return "Free " + target + ", or beat " + str(ctx.get("rival", "whoever took them"))
	return "Do the job"

static func rewardText(a:Dictionary, ctx:Dictionary) -> String:
	var parts:Array = []
	if(int(a.get("reward", 0)) > 0):
		parts.append(str(a["reward"]) + " credits")
	if(bool(a.get("intro", false))):
		parts.append("Eligibility to join " + str(ctx.get("gang", "the gang")))
	parts.append("Standing +" + str(a.get("standing", 0)))
	return PoolStringArray(parts).join("; ")

# The panel before the job is accepted: four short lines. Nothing is repeated from the leader's speech.
static func offerPanel(a:Dictionary, ctx:Dictionary, hourSeconds:int = 3600) -> String:
	var hours:int = int(round(float(int(a.get("deadline", 0)) - int(a.get("created", 0))) / float(hourSeconds)))
	var lines:Array = [
		"[b]Objective:[/b] " + objective(a, ctx),
		"[b]Reward:[/b] " + rewardText(a, ctx),
		"[b]Failure:[/b] Standing " + MINUS + str(a.get("penalty", 0)),
		"[b]Time limit:[/b] " + hoursText(hours),
	]
	return PoolStringArray(lines).join("\n")

# The panel for a job already taken: what is left to do and how long it has.
static func statusPanel(a:Dictionary, ctx:Dictionary, now:int, hourSeconds:int = 3600) -> String:
	if(str(a.get("state", "")) == "ready"):
		return "[b]Status:[/b] Ready to report to " + str(ctx.get("leader", "the leader")) + "."
	return "[b]Objective:[/b] " + objective(a, ctx) + "\n[b]Time left:[/b] " + remainingText(int(a.get("deadline", 0)), now, hourSeconds)

# ---- Side Tasks ----
# The title of the entry: "Ironhand Initiation" for the job that opens the way in, "<gang> job" for any other.
static func taskTitle(a:Dictionary, ctx:Dictionary) -> String:
	return str(ctx.get("gang", "Gang")) + (" Initiation" if bool(a.get("intro", false)) else " job")

# The lines of the entry, in the order the quest log expects (it shows the last one first): [status/time, location clue, description].
static func taskLines(a:Dictionary, ctx:Dictionary, now:int, hourSeconds:int = 3600) -> Array:
	var target:String = str(ctx.get("target", "them"))
	var leader:String = str(ctx.get("leader", "the leader"))
	var theirs:String = str(ctx.get("targetGang", ""))
	var description:String = ""
	var ready:bool = str(a.get("state", "")) == "ready"
	match(str(a.get("type", ""))):
		"defeat":
			description = (target + " has been defeated. Report back to " + leader + ".") if ready else ("Defeat " + target + ", a member of " + (theirs if theirs != "" else "a rival gang") + ", then report back to " + leader + ".")
		"capture":
			if(ready):
				description = target + " has been dealt with. Report back to " + leader + "."
			elif(str(a.get("stage", "")) == "defeated"):
				description = "You beat " + target + ". Hand them over to " + leader + "."
			else:
				description = "Beat " + target + ", a member of " + (theirs if theirs != "" else "a rival gang") + ", and hand them over to " + leader + "."
		"courier":
			var recipient:String = str(ctx.get("recipientGang", ""))
			description = ("You delivered the package to " + target + ". Report back to " + leader + ".") if ready else ("Take " + str(a.get("amount", 0)) + " credits to " + target + ((" of " + recipient) if recipient != "" else "") + ", then report back to " + leader + ".")
		"deliver":
			description = "Bring " + str(ctx.get("gang", "the gang")) + (" " + str(a.get("amount", 0)) + " credits." if str(a.get("item", "")) == "" else " the item they asked for.")
		"rescue":
			description = (target + " is free. Report back to " + leader + ".") if ready else ("Free " + target + ", who is being held, or beat " + str(ctx.get("rival", "whoever took them")) + ", then report back to " + leader + ".")
	var lines:Array = []
	if(ready):
		lines.append("Status: ready to report.")
	else:
		lines.append(remainingText(int(a.get("deadline", 0)), now, hourSeconds))
	var clue:String = str(ctx.get("clue", ""))
	if(clue != "" && !ready):
		lines.append(clue)
	lines.append(description)
	return lines

# The archived entry after a successful report.
static func doneLines(last:Dictionary, ctx:Dictionary) -> Array:
	var leader:String = str(ctx.get("leader", "the leader"))
	return ["You reported back to " + leader + "." + (" You were offered a place in " + str(ctx.get("gang", "the gang")) + "." if bool(last.get("intro", false)) else "")]

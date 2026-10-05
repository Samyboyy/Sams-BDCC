extends Reference
class_name GangViews

# What each page of the Gangs screen says. Static, reads GangGame/GangService, returns plain lines so the scene only has to show them and so tests can check them.
# The pages: the landing page (one short entry per gang), a gang's page (the essentials), its members, and how it stands with the other gangs and with the player.
# Finances (treasury, reservations) are only ever shown to the gang's own members.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const ServiceScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")

const MEMBERS_PER_PAGE = 10

static func g():
	return GangGameScript.gangs()

static func colored(text:String, color:String) -> String:
	return "[color=" + color + "]" + text + "[/color]"

# One short line saying what the gang is.
static func tagOf(gid:String) -> String:
	if(g().hasGang(gid) && g().getGang(gid).get("player", false)):
		return "Your own gang."
	return str(ServiceScript.establishedDef(gid).get("tag", "A gang."))

# The longer description, shown on the gang's own page.
static func descriptionOf(gid:String) -> String:
	if(g().hasGang(gid) && g().getGang(gid).get("player", false)):
		return "A gang you built from your own followers. You decide who joins, where it meets and who it goes after."
	return str(ServiceScript.establishedDef(gid).get("text", "A gang."))

# How the gang regards the player, in words ("your gang" for their own). {"text", "color"}.
static func standingToward(gid:String) -> Dictionary:
	var own:String = g().playerGang()
	if(own == gid):
		return {"text": "your gang", "color": GangGameScript.COLOR_GOOD}
	var status:Dictionary = g().effectiveStatus("pc", gid)
	return {"text": str(status["label"]), "color": ServiceScript.bandColor(status["score"])}

static func statusLine() -> String:
	if(!GangGameScript.isReady()):
		return ""
	GangGameScript.ensureInitialized()
	if(!g().isInitialized()):
		return "The prison's gangs have not formed yet: too few inmates are about."
	var own:String = g().playerGang()
	if(own == ""):
		return "You are independent."
	if(g().isLeader("pc", own)):
		return "You lead " + colored(g().gangName(own), "cyan") + "."
	return "You are in " + colored(g().gangName(own), "cyan") + " (" + ServiceScript.personalBand(g().getPersonal("pc", own)) + ")."

# The landing page: [{"gid", "name", "tag", "hangout", "standing": {text, color}}], the player's own gang last.
static func landing() -> Array:
	var result:Array = []
	if(!GangGameScript.isReady()):
		return result
	GangGameScript.ensureInitialized()
	if(!g().isInitialized()):
		return result
	for gid in g().gangIDs():
		result.append({"gid": gid, "name": g().gangName(gid), "tag": tagOf(gid), "hangout": ServiceScript.hangoutName(g().getHangout(gid)), "standing": standingToward(gid)})
	return result

# The text of one entry on the landing page.
static func landingEntryText(entry:Dictionary) -> String:
	return "[b]" + entry["name"] + "[/b] - " + entry["tag"] + "\nMeets at " + entry["hangout"] + ". Toward you: " + colored(entry["standing"]["text"], entry["standing"]["color"]) + "."

# The essentials of one gang, one idea per line.
static func detailLines(gid:String) -> Array:
	var lines:Array = []
	if(!g().hasGang(gid)):
		return ["That gang does not exist."]
	var leader:String = g().getLeader(gid)
	var members:Array = g().getMembers(gid)
	var held:Array = g().captivesOf(gid)
	var slaves:Array = g().getGang(gid)["slaves"]
	lines.append("[b]" + g().gangName(gid) + "[/b]")
	lines.append(descriptionOf(gid))
	lines.append("Leader: " + (GangGameScript.nameOf(leader) if leader != "" else "none"))
	lines.append("Meets at: " + ServiceScript.hangoutName(g().getHangout(gid)))
	lines.append("Strength: " + GangGameScript.bandOf(gid))
	var count:String = "Members: " + str(members.size())
	var extras:Array = []
	if(!held.empty()):
		extras.append(str(held.size()) + " held captive")
	if(!slaves.empty()):
		extras.append(str(slaves.size()) + " enslaved")
	lines.append(count + (" (" + PoolStringArray(extras).join(", ") + ")" if !extras.empty() else ""))
	var own:String = g().playerGang()
	if(!g().getGang(gid).get("player", false)):
		lines.append(presenceLine(gid))
	if(own == gid):
		lines.append("You are one of them. Your standing: " + standingWords("pc", gid))
		lines.append(treasuryLine(gid))
	else:
		lines.append("Your standing with them: " + standingWords("pc", gid))
		if(own != "" && g().hasGang(own)):
			lines.append("Through your own gang, they are " + officialWords(own, gid) + " to you.")
		if(own == "" && !g().getGang(gid).get("player", false)):
			lines.append("To join, find " + (GangGameScript.nameOf(leader) if leader != "" else "their leader") + " in person and talk to them.")
	return lines

# When the leader is normally to be found: at the gang's hangout during the afternoon window (their daily plan puts them there unless a job or something worse keeps them).
static func presenceLine(gid:String) -> String:
	var leader:String = g().getLeader(gid)
	if(leader == ""):
		return ""
	return GangGameScript.nameOf(leader) + " is normally at " + ServiceScript.hangoutName(g().getHangout(gid)) + " in the afternoon, from about " + RoutineScript.formatWindow() + "."

# What the badges on the map mean. Colour is only part of it: the badge's tooltip says it in words.
static func legendLines() -> Array:
	return ["On the map, G marks a gang member whose gang you know: green your gang, blue friendly to you, yellow neutral, red hostile.", "The usual O (owner), F (friend) and N (nemesis) stay beside it."]

# "respected (+32)": the word first, the number after.
static func standingWords(characterID, gid:String) -> String:
	var value:int = g().getPersonal(characterID, gid)
	return colored(ServiceScript.personalBand(value), ServiceScript.bandColor(value)) + " (" + signedNumber(value) + ")"

# How one gang stands with another, in words with the number after.
static func officialWords(a:String, b:String) -> String:
	var value:int = g().getRelation(a, b)
	var band:String = ServiceScript.relationBand(value)
	var color:String = GangGameScript.COLOR_BAD if band == "enemies" else (GangGameScript.COLOR_GOOD if band == "friendly" else GangGameScript.COLOR_INFO)
	return colored(band, color) + " (" + signedNumber(value) + ")"

static func signedNumber(value:int) -> String:
	return ("+" if value > 0 else "") + str(value)

# Members' money: only for a gang the player belongs to. "" for everybody else.
static func treasuryLine(gid:String) -> String:
	if(g().playerGang() != gid):
		return ""
	var reserved:int = g().reservedAmount(gid)
	return "Treasury: " + colored(str(g().getTreasury(gid)) + " credits", "yellow") + (" (" + str(reserved) + " set aside for a job)" if reserved > 0 else "")

static func canSeeFinances(gid:String) -> bool:
	return g().hasGang(gid) && g().playerGang() == gid

# Member lines of a gang for one page: {"lines": [...], "pages": n}. Each member on a line of their own; leaders, captives and the enslaved are marked.
static func memberLines(gid:String, page:int = 0) -> Dictionary:
	var rows:Array = []
	if(!g().hasGang(gid)):
		return {"lines": [], "pages": 1}
	var leader:String = g().getLeader(gid)
	var members:Array = g().getMembers(gid)
	for id in members:
		var tags:Array = []
		if(id == leader):
			tags.append("leader")
		if(id == "pc"):
			tags.append("you")
		if(g().isDetained(id)):
			tags.append("held by " + g().gangName(str(g().getCaptive(id).get("gang", ""))))
		rows.append("- " + GangGameScript.nameOf(id) + (" (" + PoolStringArray(tags).join(", ") + ")" if !tags.empty() else ""))
	for id in g().getGang(gid)["slaves"]:
		rows.append("- " + GangGameScript.nameOf(id) + " (enslaved by this gang)")
	var pages:int = int(max(1, ceil(float(rows.size()) / float(MEMBERS_PER_PAGE))))
	var from:int = int(clamp(page, 0, pages - 1)) * MEMBERS_PER_PAGE
	var lines:Array = []
	for index in range(from, int(min(rows.size(), from + MEMBERS_PER_PAGE))):
		lines.append(rows[index])
	if(rows.empty()):
		lines.append("Nobody.")
	return {"lines": lines, "pages": pages}

# How the gang stands with the other gangs (one per line, the word first) and how it sees the player: personal standing apart from what the player's own gang brings.
static func relationLines(gid:String) -> Array:
	var lines:Array = []
	if(!g().hasGang(gid)):
		return lines
	lines.append("[b]With the other gangs[/b]")
	for other in g().gangIDs():
		if(other != gid):
			lines.append("- " + g().gangName(other) + ": " + officialWords(gid, other))
	lines.append("[b]With you[/b]")
	lines.append("- Personally: " + standingWords("pc", gid))
	var own:String = g().playerGang()
	if(own != "" && own != gid && g().hasGang(own)):
		lines.append("- Through " + g().gangName(own) + ": " + officialWords(own, gid))
	elif(own == gid):
		lines.append("- You belong to this gang.")
	else:
		lines.append("- You belong to no gang, so only your own record counts.")
	return lines

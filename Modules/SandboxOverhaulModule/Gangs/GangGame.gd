extends Reference
class_name GangGame

# The game side of the gangs: it reads real characters, pawns, relationships and the clock, calls the pure GangService and GangAffairs rules, and applies the results
# (credits, messages, injuries, items, attacks through the existing GenericAttack interaction). Everything is static; the state lives in SandboxState.gangs.

const ServiceScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")
const SecurityScript = preload("res://Modules/SandboxOverhaulModule/Security/Security.gd")
const COLOR_GOOD = "green"
const COLOR_BAD = "red"
const COLOR_WARN = "yellow"
const COLOR_INFO = "cyan"
const TOPUP_PER_DAY = 2 # at most this many inmates are recruited into gangs a day until about 40% belong to one
const HANGOUT_FROM_HOUR = 8
const HANGOUT_TO_HOUR = 20
const HANGOUT_VISIT_CHANCE = 0.15 # a free member in a hostile gang's hangout, per ten-minute check with the player there
const WILLING_FEELING = 30.0 # Trust plus Respect towards the player (each halved) that makes an inmate willing to follow them

static func gangs():
	return GlobalRegistry.getGameExtender("SandboxGameExtender").getGangs()

static func affairs():
	return GlobalRegistry.getGameExtender("SandboxGameExtender").getGangAffairs()

static func module():
	return GlobalRegistry.getModule("SandboxOverhaulModule")

static func isReady() -> bool:
	var m = module()
	return m != null && m.isMainReady() && GM.main.IS != null

static func now() -> int:
	return ServiceScript.stamp(GM.main.getDays(), GM.main.getTime())

static func nameOf(characterID) -> String:
	return module().characterName(characterID)

static func say(text:String, color:String = COLOR_INFO) -> void:
	if(GM.main != null && is_instance_valid(GM.main)):
		GM.main.addMessage("[color=" + color + "]" + text + "[/color]")

# ---- Characters ----
static func isEligibleInmate(characterID) -> bool:
	var c = GM.main.getCharacter(characterID)
	return c != null && c.isDynamicCharacter() && c.getCharacterType() == CharacterType.Inmate && !c.isSlaveToPlayer() && !c.hasEnslaveQuest()

static func eligibleIDs() -> Array:
	var result:Array = []
	if(GM.main == null):
		return result
	var ids:Array = GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Inmates)
	ids.sort()
	for id in ids:
		if(isEligibleInmate(id)):
			result.append(id)
	return result

static func power(characterID) -> float:
	var c = GM.main.getCharacter(characterID)
	return 0.5 + float(c.getLevel()) / 20.0 if c != null else 0.5

static func traitEntry(characterID) -> Dictionary:
	var c = GM.main.getCharacter(characterID)
	var entry:Dictionary = {"id": characterID, "power": power(characterID), "mean": 0.0, "subby": 0.0, "coward": 0.0, "naive": 0.0, "brat": 0.0, "respect": 0.0}
	if(c != null && c.getPersonality() != null):
		var p = c.getPersonality()
		entry["mean"] = p.getStat(PersonalityStat.Mean)
		entry["subby"] = p.getStat(PersonalityStat.Subby)
		entry["coward"] = p.getStat(PersonalityStat.Coward)
		entry["naive"] = p.getStat(PersonalityStat.Naive)
		entry["brat"] = p.getStat(PersonalityStat.Brat)
	return entry

static func powers() -> Dictionary:
	var result:Dictionary = {}
	var g = gangs()
	for gid in g.gangIDs():
		for id in g.getMembers(gid):
			result[id] = power(id) if id != "pc" else 0.5 + float(GM.pc.getLevel()) / 20.0
	return result

static func combatReputation() -> float:
	return module().getCombat().getCombatReputation()

static func feeling(observerID, targetID, axis:String) -> float:
	return module().getRelationships().getFeeling(observerID, targetID, axis)

static func gangStrength(gid) -> float:
	return gangs().strength(gid, powers(), combatReputation() if gangs().playerGang() == gid else 0.0)

static func bandOf(gid) -> String:
	return ServiceScript.strengthBand(gangStrength(gid))

# ---- Setting up and keeping the roster tidy ----
static func ensureInitialized() -> void:
	var g = gangs()
	if(g.isInitialized()):
		return
	var ids:Array = eligibleIDs()
	if(ids.size() < ServiceScript.FORMATION_MIN):
		return
	var entries:Array = []
	for id in ids:
		entries.append(traitEntry(id))
	var _n:int = g.initialize(entries, GM.main.getDays())
	refreshHangoutZones()

static func validIDs() -> Array:
	var ids:Array = ["pc"]
	if(GM.main != null):
		ids.append_array(GM.main.dynamicCharacters.keys())
	return ids

static func topUpNewcomers(day:int) -> Array:
	var g = gangs()
	if(!g.isInitialized() || int(g.data()["cooldowns"].get("topup_day", -1)) == day):
		return []
	g.data()["cooldowns"]["topup_day"] = day
	var ids:Array = eligibleIDs()
	var unaffiliated:Array = []
	var affiliated:int = 0
	for id in ids:
		if(g.gangOf(id) != ""):
			affiliated += 1
		elif(!g.isCaptive(id)):
			unaffiliated.append(traitEntry(id))
	return g.topUp(unaffiliated, affiliated, ids.size(), TOPUP_PER_DAY, day)

# ---- Hangouts ----
static func slotOf(gid) -> int:
	if(gid == ServiceScript.PLAYER_GANG_ID):
		return ServiceScript.ESTABLISHED.size()
	for i in range(ServiceScript.ESTABLISHED.size()):
		if(ServiceScript.ESTABLISHED[i]["id"] == gid):
			return i
	return -1

static func gangForSlot(slot:int) -> String:
	if(slot == ServiceScript.ESTABLISHED.size()):
		return ServiceScript.PLAYER_GANG_ID
	if(slot >= 0 && slot < ServiceScript.ESTABLISHED.size()):
		return ServiceScript.ESTABLISHED[slot]["id"]
	return ""

# Puts each gang's hangout room into its own zone group (zone_gang0 to zone_gang3) so BDCC's HangoutAt goal can send members there.
static func refreshHangoutZones(world = null) -> void:
	var theWorld = world if world != null else GM.world
	if(theWorld == null || !is_instance_valid(theWorld) || GM.main == null || !is_instance_valid(GM.main)):
		return
	var g = gangs()
	for slot in range(ServiceScript.ESTABLISHED.size() + 1):
		var group:String = "zone_gang" + str(slot)
		for room in theWorld.get_tree().get_nodes_in_group(group):
			if(is_instance_valid(room)):
				room.remove_from_group(group)
		var hangoutRoom:String = g.getHangout(gangForSlot(slot))
		var room2 = theWorld.getRoomByID(hangoutRoom) if hangoutRoom != "" else null
		if(room2 != null):
			room2.add_to_group(group)

# Whether this member may go and stand at their hangout right now: a free, ordinary daytime member of that gang. The task also needs the pawn to be free, so
# bedtime, work, interactions, slavery and punishment always win.
static func canHangOut(characterID, slot:int) -> bool:
	if(!isReady()):
		return false
	var gid:String = gangForSlot(slot)
	var g = gangs()
	if(gid == "" || !g.hasGang(gid) || !g.isMember(characterID, gid) || g.isCaptive(characterID) || characterID == "pc"):
		return false
	var hour:int = int(GM.main.getTime() / 3600)
	if(hour < HANGOUT_FROM_HOUR || hour >= HANGOUT_TO_HOUR):
		return false
	return !module().isKeptElsewhere(characterID) && !module().isInCell(characterID)

static func hangoutOf(characterID) -> String:
	var gid:String = gangs().gangOf(characterID)
	return gangs().getHangout(gid) if gid != "" else ""

# ---- Messages for what changed ----
static func relationText(a:String, b:String) -> String:
	var g = gangs()
	var value:int = g.getRelation(a, b)
	var band:String = ServiceScript.relationBand(value)
	var color:String = COLOR_BAD if band == "enemies" else (COLOR_GOOD if band == "friendly" else COLOR_INFO)
	return g.gangName(b) + ": [color=" + color + "]" + band + " (" + str(value) + ")[/color]"

static func personalText(characterID, gid) -> String:
	var g = gangs()
	var value:int = g.getPersonal(characterID, gid)
	return g.gangName(gid) + ": [color=" + ServiceScript.bandColor(value) + "]" + ServiceScript.personalBand(value) + " (" + str(value) + ")[/color]"

static func impressionText(impressions:Dictionary) -> String:
	var parts:Array = []
	for gid in impressions:
		var d:int = impressions[gid]
		if(d != 0):
			parts.append(gangs().gangName(gid) + " " + ("+" if d > 0 else "") + str(d))
	return "" if parts.empty() else "[color=cyan]Personal standing: " + PoolStringArray(parts).join(", ") + ".[/color]"

# ---- Joining, leaving, creating ----
static func joinContext(gid:String) -> Dictionary:
	var leader:String = gangs().getLeader(gid)
	return {"day": GM.main.getDays(), "trust": feeling(leader, "pc", "trust") if leader != "" else 0.0, "respect": feeling(leader, "pc", "respect") if leader != "" else 0.0, "combat": combatReputation()}

static func joinCheck(gid:String) -> Dictionary:
	return gangs().joinCheck("pc", gid, joinContext(gid))

# Joins after the check passed. Returns the message to show.
static func join(gid:String) -> String:
	var check:Dictionary = joinCheck(gid)
	if(!check["ok"]):
		return "[color=red]" + PoolStringArray(check["reasons"]).join(" ") + "[/color]"
	var result:Dictionary = gangs().join("pc", gid, GM.main.getDays())
	gangs().addLog("You joined " + gangs().gangName(gid) + ".")
	adjustLeader(gid, 4.0, 3.0) # being taken in builds a connection with the one who did it, not a friendship
	var leaderID:String = gangs().getLeader(gid)
	var _known:bool = gangs().learnGang(leaderID)
	# The facts of joining, as plain information (the leader's welcome is spoken separately, see initiate)
	var lines:Array = ["[color=green]Joined " + gangs().gangName(gid) + ".[/color]"]
	var own:int = int(result["impressions"].get(gid, 0))
	if(own != 0):
		lines.append("Personal standing: " + gangs().gangName(gid) + " " + ("+" if own > 0 else GangDialogue.MINUS) + str(abs(own)))
	for other in result["impressions"]:
		if(other != gid && int(result["impressions"][other]) < 0):
			lines.append(gangs().gangName(other) + " now regards you as a rival.")
	return PoolStringArray(lines).join("\n")

static func leave() -> String:
	var gid:String = gangs().playerGang()
	if(gid == "" || gid == ServiceScript.PLAYER_GANG_ID):
		return "You are not in a gang you can leave."
	var result:Dictionary = gangs().leave("pc", GM.main.getDays(), leaderScores(gid))
	adjustLeader(gid, -6.0, -3.0)
	gangs().addLog("You left " + gangs().gangName(gid) + ".")
	return "[color=yellow]You left " + gangs().gangName(gid) + ".[/color] " + impressionText(result["impressions"]) + " What you did to their rivals is not forgotten."

static func leaderScores(gid) -> Dictionary:
	var scores:Dictionary = {}
	for id in gangs().getMembers(gid):
		scores[id] = ServiceScript.leaderScore(traitEntry(id)) if id != "pc" else 0.0
	return scores

static func expelPlayer(reason:String, severity:int) -> void:
	var gid:String = gangs().playerGang()
	if(gid == "" || gid == ServiceScript.PLAYER_GANG_ID):
		return
	var result:Dictionary = gangs().expel("pc", reason, severity, GM.main.getDays(), leaderScores(gid))
	gangs().addLog("You were thrown out of " + gangs().gangName(gid) + ": " + reason + ".")
	say("You were thrown out of " + gangs().gangName(gid) + ": " + reason + ". " + impressionText(result["impressions"]).replace("[color=cyan]", "").replace("[/color]", "") + " Expect trouble in a couple of days.", COLOR_BAD)

static func willing(characterID) -> bool:
	return feeling(characterID, "pc", "trust") * 0.5 + feeling(characterID, "pc", "respect") * 0.5 >= WILLING_FEELING * 0.5 && !isHostileTo(characterID)

static func isHostileTo(characterID) -> bool:
	var gid:String = gangs().gangOf(characterID)
	return gid != "" && gangs().effectiveStatus("pc", gid)["hostile"]

static func recruits() -> Array:
	var result:Array = []
	for id in eligibleIDs():
		if(gangs().gangOf(id) == "" && !gangs().isCaptive(id) && willing(id)):
			result.append(id)
	return result

static func bestRespect() -> float:
	var best:float = 0.0
	for id in eligibleIDs():
		best = max(best, feeling(id, "pc", "respect"))
	return best

static func createContext() -> Dictionary:
	return {"combat": combatReputation(), "respect": bestRespect(), "recruits": recruits().size(), "credits": GM.pc.getCredits()}

static func createGang(rawName, hangout, invitees:Array) -> String:
	var check:Dictionary = affairs().canCreate(createContext())
	if(!check["ok"]):
		return "[color=red]" + PoolStringArray(check["reasons"]).join(" ") + "[/color]"
	var made:Dictionary = affairs().createPlayerGang(rawName, hangout, invitees, GM.main.getDays())
	if(!made["ok"]):
		return "[color=red]" + made["reason"] + "[/color]"
	GM.pc.addCredits(-ServiceScript.CREATE_COST)
	refreshHangoutZones()
	return "[color=green]You founded " + gangs().gangName(ServiceScript.PLAYER_GANG_ID) + ".[/color] [color=red]" + str(ServiceScript.CREATE_COST) + " credits spent[/color], [color=yellow]" + str(ServiceScript.PLAYER_START_TREASURY) + " of them start the treasury[/color]."

static func invite(characterID) -> String:
	var result:Dictionary = affairs().inviteMember(characterID, willing(characterID))
	if(result["ok"]):
		return "[color=green]" + nameOf(characterID) + " joins your gang.[/color]"
	return "[color=red]" + result["reason"] + "[/color]"

static func removeMember(characterID) -> String:
	var result:Dictionary = affairs().removeFromPlayerGang(characterID)
	return ("[color=yellow]" + nameOf(characterID) + " is out of your gang.[/color]") if result["ok"] else ("[color=red]" + result["reason"] + "[/color]")

static func changeHangout(room) -> String:
	var result:Dictionary = affairs().changeHangout(room, now())
	if(result["ok"]):
		refreshHangoutZones()
		return "[color=cyan]Your gang now meets at " + ServiceScript.hangoutName(room) + ".[/color]"
	return "[color=red]" + result["reason"] + "[/color]"

static func contribute(amount:int) -> String:
	var gid:String = gangs().playerGang()
	if(gid == "" || amount <= 0 || GM.pc.getCredits() < amount):
		return "[color=red]You cannot contribute that.[/color]"
	GM.pc.addCredits(-amount)
	var _t:int = gangs().addTreasury(gid, amount)
	if(gid != ServiceScript.PLAYER_GANG_ID):
		var d:int = gangs().addPersonal("pc", gid, min(5.0, float(amount) / 2.0))
		return "[color=yellow]" + str(amount) + " credits go to " + gangs().gangName(gid) + ".[/color] [color=green]Standing +" + str(d) + ".[/color]"
	return "[color=yellow]" + str(amount) + " credits go into the treasury.[/color]"

# ---- Assignments ----
static func contrabandItemID() -> String:
	for item in GM.pc.getInventory().getItems():
		if(item.hasTag(ItemTag.Illegal) && !item.isImportant() && !item.isPersistent() && item.uniqueID is String):
			return item.id
	return ""

static func assignmentNames() -> Dictionary:
	var names:Dictionary = {}
	var a:Dictionary = affairs().getAssignment()
	for key in ["target", "rival"]:
		if(!a.empty() && a[key] != ""):
			names[a[key]] = nameOf(a[key])
	if(!a.empty() && gangs().hasGang(a["gang"]) && gangs().getLeader(a["gang"]) != ""):
		names["leader"] = nameOf(gangs().getLeader(a["gang"]))
	return names

static func offerAssignment() -> String:
	var g = gangs()
	var gid:String = g.playerGang()
	if(gid == "" || g.getGang(gid).get("player", false)):
		return ""
	var rivals:Array = []
	for other in g.gangIDs():
		if(other != gid && g.getRelation(gid, other) < ServiceScript.FRIEND_AT):
			for id in g.activeMembers(other):
				rivals.append(id)
	rivals.sort()
	var held:Array = g.captivesOf(gid)
	var captors:Array = []
	for id in held:
		var captor:String = g.getCaptive(id)["gang"]
		var members:Array = g.activeMembers(captor)
		captors.append(members[0] if !members.empty() else "")
	var ctx:Dictionary = {"day": GM.main.getDays(), "rivals": rivals, "heldMembers": held, "captors": captors, "contrabandItem": contrabandItemID()}
	var offer:Dictionary = affairs().makeOffer(ctx, now())
	if(offer.empty()):
		return ""
	return "[color=cyan]" + nameOf(g.getLeader(gid)) + " has something they want you to do. Talk to them (Gangs) to hear about the job.[/color]"

static func acceptAssignment() -> String:
	if(!affairs().accept(now())):
		return "[color=red]There is nothing to accept, or the gang can no longer afford it.[/color]"
	var named:String = str(affairs().getAssignment().get("target", ""))
	if(named != ""):
		var _learned:bool = gangs().learnGang(named) # the job names them, so you know whose they are
	var taken:Dictionary = affairs().getAssignment()
	var ctx:Dictionary = speechContext(taken)
	return GangDialogue.line(str(ctx["leader"]), gangs().getLeader(str(taken["gang"])), GangDialogue.acceptSpeech(str(taken["gang"]))) + "\n\n[color=green]" + ("Introductory assignment accepted." if taken["intro"] else "Assignment accepted.") + "[/color]"

static func declineAssignment() -> String:
	return "[color=cyan]You turned it down. No harm done.[/color]" if affairs().decline(now()) else "[color=red]There is nothing to decline.[/color]"

# Pays a finished job once and describes it as plain information, one fact a line (nothing here is spoken by a character).
static func applyReward(result:Dictionary) -> String:
	if(result.empty()):
		return ""
	var lines:Array = [("[color=green]Introductory assignment complete.[/color]" if result.get("intro", false) else "[color=green]Assignment complete.[/color]")]
	if(result["credits"] > 0):
		GM.pc.addCredits(result["credits"])
		lines.append("Reward: " + str(result["credits"]) + " credits")
	lines.append("Personal standing: " + gangs().gangName(result["gang"]) + " +" + str(result["standing"]))
	if(result.get("respect", 0) > 0):
		var leader:String = gangs().getLeader(result["gang"])
		if(leader != ""):
			adjustLeader(result["gang"], float(result.get("trust", 0)), float(result["respect"]))
			lines.append(nameOf(leader) + ": " + ("Trust and Respect up" if result.get("trust", 0) > 0 else "Respect up"))
	if(result.get("intro", false)):
		lines.append("You are now eligible to join " + gangs().gangName(result["gang"]) + ".")
	gangs().addLog("You finished a job for " + gangs().gangName(result["gang"]) + ".")
	return PoolStringArray(lines).join("\n")

# Hands over the requested payment or contraband. Everything is taken first, then the job is completed once; a failure to find the item takes nothing.
static func deliverAssignment() -> String:
	var a:Dictionary = affairs().getAssignment()
	if(!affairs().canDeliver(now())):
		return "[color=red]There is nothing to deliver.[/color]"
	if(a["item"] == ""):
		if(GM.pc.getCredits() < a["amount"]):
			return "[color=red]You need " + str(a["amount"]) + " credits.[/color]"
		GM.pc.addCredits(-a["amount"])
		var _t:int = gangs().addTreasury(a["gang"], a["amount"])
	else:
		var found = null
		for item in GM.pc.getInventory().getItems():
			if(item.id == a["item"] && item.hasTag(ItemTag.Illegal) && !item.isImportant() && !item.isPersistent()):
				found = item
				break
		if(found == null):
			return "[color=red]You are not carrying what they asked for.[/color]"
		var _removed = GM.pc.getInventory().removeItem(found)
	var paid:String = "[color=yellow]" + (str(a["amount"]) + " credits handed over. " if a["item"] == "" else "Item handed over. ") + "[/color]"
	var finished:Dictionary = affairs().complete(now())
	return paid + "\n" + applyReward(finished)

static func handOverCaptive() -> String:
	var result:Dictionary = affairs().handOverCaptive(now())
	if(!result["ok"]):
		return "[color=red]" + result["reason"] + "[/color]"
	var victim:String = result.get("victimGang", "")
	var extra:String = ""
	if(victim != ""):
		extra = " [color=red]" + gangs().gangName(victim) + " will remember this.[/color]"
	return "[color=yellow]You hand them over.[/color]" + extra + "\n" + applyReward(result["result"])

static func checkAssignment() -> void:
	var outcome:Dictionary = affairs().checkExpiry(now(), validIDs())
	if(outcome["event"] == "failed"):
		adjustLeader(outcome["gang"], -4.0, -3.0)
		say("You failed the job for " + gangs().gangName(outcome["gang"]) + ": standing " + str(outcome["standing"]) + ".", COLOR_BAD)
		gangs().addLog("You failed a job for " + gangs().gangName(outcome["gang"]) + ".")
	elif(outcome["event"] == "cancelled"):
		say("Your job was called off (" + outcome["reason"] + "). You are not blamed.", COLOR_INFO)

# ---- Fights (called by the Milestone 2 hooks) ----
# The player started a fight with this character.
static func onPlayerAttack(victimID) -> void:
	if(!isReady() || !(victimID is String)):
		return
	ensureInitialized()
	var g = gangs()
	var victimGang:String = g.gangOf(victimID)
	if(victimGang == ""):
		return
	var own:String = g.playerGang()
	if(victimGang == own):
		var lost:int = g.recordBetrayal(own, "attack")
		say("Attacking one of your own: standing " + str(lost) + " with " + g.gangName(own) + ".", COLOR_BAD)
		return
	var _h:int = g.recordHarm("pc", victimGang, "attack")
	var _learnedVictim:bool = g.learnGang(victimID) # a fight tells you whose they are
	say("People in " + g.gangName(victimGang) + " will hear that you started a fight with one of theirs.", COLOR_WARN)

# A fight involving the player ended. won is the winner's character ID.
static func onFightResult(wonID, lostID) -> void:
	if(!isReady() || !(wonID is String) || !(lostID is String)):
		return
	var g = gangs()
	if(wonID == "pc" && lostID != "pc"):
		var theirs:String = g.gangOf(lostID)
		var own:String = g.playerGang()
		if(theirs != "" && theirs != own):
			var _d:int = g.recordHarm("pc", theirs, "defeat")
			g.recordLoss(theirs)
			if(own != "" && g.areEnemies(own, theirs) && !g.getGang(own).get("player", false)):
				var gained:int = g.addPersonal("pc", own, 4.0)
				if(gained > 0):
					say("You beat a rival of " + g.gangName(own) + ": standing +" + str(gained) + ".", COLOR_GOOD)
		var _learnedLoser:bool = g.learnGang(lostID)
		var outcome:Dictionary = affairs().onPlayerWon(lostID, now())
		if(outcome["event"] == "ready"):
			say("That settles it. Report back to " + nameOf(g.getLeader(affairs().getAssignment()["gang"])) + " in person.", COLOR_GOOD)
		elif(outcome["event"] == "defeated"):
			say("They are beaten. Take them to " + nameOf(g.getLeader(g.playerGang())) + " to hand them over.", COLOR_INFO)

# ---- Captives ----
static func releaseText(characterID, escaped:bool) -> String:
	return nameOf(characterID) + (" got away from their captors." if escaped else " is free.")

static func handleCaptiveExpiry() -> void:
	for entry in gangs().expireCaptives(now()):
		say(releaseText(entry["id"], true), COLOR_INFO)
		gangs().addLog(releaseText(entry["id"], true))

# (Held members and gang slaves are no longer taken off the map: the population director keeps them at the holding gang's hangout.)

# The player enslaved a gang member (or a gang's slave): the gang regards them as an enemy, and the character leaves the gang's books.
static func handlePlayerSlaves() -> void:
	var g = gangs()
	for gid in g.gangIDs():
		for id in g.getMembers(gid) + g.getGang(gid).get("slaves", []):
			if(id == "pc"):
				continue
			var c = GM.main.getCharacter(id)
			if(c != null && c.isSlaveToPlayer()):
				if(g.isMember(id, gid)):
					var _r:String = g.removeMember(id, leaderScores(gid))
				else:
					var _f:String = g.freeSlave(id)
				var lost:int = g.recordHarm("pc", gid, "enslave")
				say("You enslaved " + nameOf(id) + " of " + g.gangName(gid) + ". [color=red]They will not forgive that (" + str(lost) + ").[/color]", COLOR_BAD)
				g.addLog("You enslaved " + nameOf(id) + " of " + g.gangName(gid) + ".")
				if(g.playerGang() == gid):
					expelPlayer("you enslaved one of their own", 3)

# The player helps one of a gang's slaves get free. The owning gang takes it badly; the slave goes back to the ordinary inmates.
static func freeGangSlave(characterID) -> String:
	var g = gangs()
	var owner:String = g.freeSlave(characterID)
	if(owner == ""):
		return "[color=red]They are not held by a gang.[/color]"
	var harm:int = g.recordHarm("pc", owner, "free_slave")
	g.addLog("You helped " + nameOf(characterID) + " get away from " + g.gangName(owner) + ".")
	return "[color=green]" + nameOf(characterID) + " is free.[/color] [color=red]" + g.gangName(owner) + " will not forgive it (" + str(harm) + ").[/color]"

# ---- Ordered actions ----
static func isProtectedTarget(characterID) -> bool:
	var c = GM.main.getCharacter(characterID)
	if(c == null || !c.isDynamicCharacter() || c.getCharacterType() != CharacterType.Inmate):
		return true
	return c.isSlaveToPlayer() || c.hasEnslaveQuest() || c.isPlayerOwner()

static func orderContext(targetID) -> Dictionary:
	return {"now": now(), "members": gangs().activeMembers(ServiceScript.PLAYER_GANG_ID).size() - 1, "targetOk": !isProtectedTarget(targetID)}

static func targetsFor(kind:String) -> Array:
	var g = gangs()
	var result:Array = []
	if(kind == "rescue"):
		for id in g.captivesOf(ServiceScript.PLAYER_GANG_ID):
			result.append(id)
		return result
	for id in eligibleIDs():
		var gid:String = g.gangOf(id)
		if(gid == ServiceScript.PLAYER_GANG_ID || g.isCaptive(id)):
			continue
		if(kind == "capture" && gid == ""):
			continue
		result.append(id)
	return result

# Carries out an ordered action. dice: [success roll, who is lost]. Returns the message.
static func orderAction(kind:String, targetID:String, dice:Array) -> String:
	var g = gangs()
	var check:Dictionary = affairs().canOrder(kind, targetID, orderContext(targetID))
	if(!check["ok"]):
		return "[color=red]" + check["reason"] + "[/color]"
	var targetPower:float = power(targetID)
	var fear:float = feeling(targetID, "pc", "fear")
	var chance:float = affairs().orderSuccess(gangStrength(ServiceScript.PLAYER_GANG_ID), targetPower, fear, orderContext(targetID)["members"])
	var result:Dictionary = affairs().resolveOrder(kind, targetID, chance, float(dice[0]), float(dice[1]), now())
	var who:String = nameOf(targetID)
	var lines:Array = []
	if(result["success"]):
		match kind:
			"intimidate":
				var _f:float = module().getRelationships().adjustFeeling(targetID, "pc", "fear", 12.0)
				lines.append("[color=green]Your people scare " + who + " badly.[/color] Their Fear of you rises.")
			"beat":
				var _i:Dictionary = module().getInjuries().applyInjury(targetID, "trauma", 1)
				var _f2:float = module().getRelationships().adjustFeeling(targetID, "pc", "fear", 8.0)
				lines.append("[color=green]Your people beat " + who + " up.[/color] They are hurt and afraid.")
			"capture":
				lines.append("[color=yellow]Your people drag " + who + " away.[/color] They are held for a day and a half unless someone frees them.")
			"rescue":
				lines.append("[color=green]Your people get " + who + " out.[/color]")
				var _p:Dictionary = affairs().onRescued(targetID, now())
		if(result["harm"] != 0 && result["targetGang"] != ""):
			lines.append("[color=red]" + g.gangName(result["targetGang"]) + " will not like it (" + str(result["harm"]) + ").[/color]")
	else:
		lines.append("[color=red]The order fails. " + who + " is too much for them.[/color]")
		if(result["lost"] != ""):
			if(result["lostCaptured"]):
				lines.append("[color=red]" + nameOf(result["lost"]) + " was caught and is now held by " + g.gangName(result["targetGang"]) + ".[/color]")
			else:
				var _i2:Dictionary = module().getInjuries().applyInjury(result["lost"], "trauma", 1)
				lines.append("[color=yellow]" + nameOf(result["lost"]) + " comes back hurt.[/color]")
	lines.append("[color=yellow]-" + str(ServiceScript.ORDER_COST) + " from the treasury.[/color]")
	return PoolStringArray(lines).join(" ")

# ---- Hostile gangs, retaliation, hangout visits ----
static func playerPawn():
	return GM.main.IS.getPawn("pc")

static func freeMemberPawnsAt(gid:String, locationID:String) -> Array:
	var result:Array = []
	for pawn in GM.main.IS.getPawnsAt(locationID):
		if(pawn != null && !pawn.isPlayer() && gangs().isMember(pawn.charID, gid) && !gangs().isCaptive(pawn.charID) && pawn.canBeInterrupted()):
			result.append(pawn)
	return result

static func startAttack(attackerID:String) -> bool:
	if(!module().isSafeForEnforcement()):
		return false
	GM.main.IS.startInteraction("GenericAttack", {"starter": attackerID, "reacter": "pc"}, {})
	return true

static func maxFear(gid:String) -> float:
	var best:float = 0.0
	for id in gangs().getMembers(gid):
		best = max(best, feeling(id, "pc", "fear"))
	return best

# A gang that should come for the player. Returns true if someone did.
static func tryHostileIncident(day:int, rolls:Array) -> bool:
	var pp = playerPawn()
	if(pp == null || !module().isSafeForEnforcement()):
		return false
	var g = gangs()
	var location:String = pp.getLocation()
	var guards:int = module().getFreeGuards(location).size()
	var attention:float = module().getSecurity().getAttention()
	var combat:float = combatReputation()
	# Retaliation for an expulsion comes first and is its own thing
	for gid in g.gangIDs():
		var ctx:Dictionary = {"day": day, "combat": combat, "fear": maxFear(gid)}
		if(g.retaliationDue(gid, ctx) && guards == 0 && gangStrength(gid) >= 1.0):
			var members:Array = freeMemberPawnsAt(gid, location)
			if(!members.empty() && startAttack(members[0].charID)):
				g.markRetaliation(gid, ctx)
				affairs().markIncident(gid, day)
				say(g.gangName(gid) + " has come to settle things.", COLOR_BAD)
				return true
	# Rival gangs: someone present who regards the player as an enemy, at most one major incident a day
	var incidentCtx:Dictionary = {"day": day, "guards": guards, "attention": attention, "fear": 0.0, "powers": powers(), "combat": combat}
	var picked:String = affairs().incidentGang(incidentCtx, rolls)
	if(picked == ""):
		# a visit to a hostile gang's hangout makes trouble likelier
		var here:String = hangoutOwner(location)
		if(here != "" && here != g.playerGang() && g.effectiveStatus("pc", here)["hostile"] && guards == 0 && float(rolls[rolls.size() - 1] if !rolls.empty() else 1.0) < HANGOUT_VISIT_CHANCE && int(g.data()["player"]["incident_day"]) != day):
			picked = here
	if(picked == ""):
		return false
	var members2:Array = freeMemberPawnsAt(picked, location)
	if(members2.empty()):
		return false
	var fear:float = maxFear(picked)
	if(fear >= 60.0):
		say(g.gangName(picked) + "'s members eye you but keep their distance.", COLOR_WARN)
		affairs().markIncident(picked, day)
		return false
	if(!startAttack(members2[0].charID)):
		return false
	affairs().markIncident(picked, day)
	say(g.gangName(picked) + " does not like you in their space.", COLOR_BAD)
	return true

static func hangoutOwner(roomID:String) -> String:
	for gid in gangs().gangIDs():
		if(gangs().getHangout(gid) == roomID):
			return gid
	return ""

# ---- The gangs on their own ----
static func dailyUpkeep(day:int, rolls:Array) -> void:
	var g = gangs()
	var a = affairs()
	var income:Dictionary = g.collectIncome(day)
	for gid in income:
		g.addLog(g.gangName(gid) + " collects " + str(income[gid]) + " credits from its slaves.")
	var events:Array = a.abstractConflicts(day, now(), powers(), rolls)
	for event in events:
		var names:String = g.gangName(event["gangs"][0]) + " and " + g.gangName(event["gangs"][1])
		if(event["type"] == "kidnap"):
			var line:String = g.gangName(event["by"]) + " took " + nameOf(event["victim"]) + " of " + g.gangName(g.gangOf(event["victim"])) + "."
			g.addLog(line)
			if(isRelevantToPlayer(event["victim"])):
				say(line, COLOR_WARN)
		else:
			g.addLog(names + " clashed.")
	var views:Array = churnViews()
	var change:Dictionary = a.churn(now(), powers(), views, float(rolls[rolls.size() - 1] if !rolls.empty() else 1.0))
	if(!change.empty()):
		var text:String = nameOf(change["id"]) + (" left " if change["type"] != "defect" else " defected from ") + g.gangName(change["from"]) + (" to " + g.gangName(change["to"]) if change["to"] != "" else "") + ": " + change["reason"] + "."
		if(change["type"] == "expel"):
			text = nameOf(change["id"]) + " was thrown out of " + g.gangName(change["from"]) + ": " + change["reason"] + "."
		g.addLog(text)
		if(isRelevantToPlayer(change["id"]) || g.playerGang() == change["from"]):
			say(text, COLOR_INFO)
	var standing:Dictionary = g.checkStanding(day)
	if(standing["event"] == "warning"):
		say("Your standing in " + g.gangName(g.playerGang()) + " is low. Do some work for them or you will be thrown out.", COLOR_WARN)
	elif(standing["event"] == "expel"):
		expelPlayer(standing["reason"], 2)
	for gid in g.closeRetaliations({"combat": combatReputation(), "fear": 0.0}):
		say(g.gangName(gid) + " has given up on you.", COLOR_GOOD)
	var newcomers:Array = topUpNewcomers(day)
	for entry in newcomers:
		g.addLog(nameOf(entry["id"]) + " joined " + g.gangName(entry["gang"]) + ".")

static func isRelevantToPlayer(characterID) -> bool:
	if(characterID == module().getPlayerCellmate()):
		return true
	var g = gangs()
	return g.playerGang() != "" && g.isMember(characterID, g.playerGang())

static func churnViews() -> Array:
	var views:Array = []
	var g = gangs()
	for gid in g.gangIDs():
		if(g.getGang(gid).get("player", false)):
			continue
		var leader:String = g.getLeader(gid)
		for id in g.getMembers(gid):
			if(id == "pc" || id == leader || leader == ""):
				continue
			var bestOther:String = ""
			var bestValue:float = -1000.0
			for other in g.gangIDs():
				var otherLeader:String = g.getLeader(other)
				if(other == gid || otherLeader == "" || otherLeader == "pc"):
					continue
				var value:float = feeling(id, otherLeader, "trust") + feeling(id, otherLeader, "respect")
				if(value > bestValue):
					bestValue = value
					bestOther = other
			views.append({"id": id, "gang": gid, "leaderTrust": feeling(id, leader, "trust") + feeling(id, leader, "respect"), "leaderRegard": feeling(leader, id, "trust"), "bestOther": bestOther, "bestOtherValue": bestValue})
	return views

# ---- The ten-minute check ----
static func tick() -> void:
	if(!isReady() || GM.main.isInDungeon()):
		return
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	var bucket:int = GM.main.getDays() * 144 + int(GM.main.getTime() / 600)
	if(extender.gangBucket == bucket):
		return
	extender.gangBucket = bucket
	ensureInitialized()
	var g = gangs()
	if(!g.isInitialized()):
		return
	var day:int = GM.main.getDays()
	var _pruned:Array = g.pruneMissing(validIDs())
	handlePlayerSlaves()
	handleCaptiveExpiry()
	checkAssignment()
	if(int(g.data()["cooldowns"].get("daily_day", -1)) != day):
		g.data()["cooldowns"]["daily_day"] = day
		var rolls:Array = []
		for _n in range(8):
			rolls.append(module().nextRoll())
		dailyUpkeep(day, rolls)
		var offered:String = offerAssignment()
		if(offered != ""):
			say(offered.replace("[color=cyan]", "").replace("[/color]", ""), COLOR_INFO)
	var incidentRolls:Array = []
	for _m in range(5):
		incidentRolls.append(module().nextRoll())
	var _started:bool = tryHostileIncident(day, incidentRolls)

# ---- Protection (called from Module.getAttackMultiplier) ----
static func protectionMultiplier(attackerID) -> float:
	if(!isReady() || !gangs().isInitialized()):
		return 1.0
	return affairs().protectionMultiplier(attackerID, powers(), combatReputation())

# ---- Badges on the map ----
const BADGE_COLORS = {"own": Color(0.35, 0.9, 0.45), "friendly": Color(0.4, 0.62, 1.0), "neutral": Color(0.96, 0.86, 0.3), "hostile": Color(1.0, 0.32, 0.32)}

# How a gang stands with the player, as one of "own", "friendly", "neutral", "hostile": their own gang is "own"; to a gang member, another gang by what the two gangs think of each other;
# to an independent player, by what that gang thinks of them personally.
static func standingKey(gid:String) -> String:
	var g = gangs()
	var own:String = g.playerGang()
	if(own == gid):
		return "own"
	if(own != ""):
		var band:String = ServiceScript.relationBand(g.getRelation(own, gid))
		return "friendly" if band == "friendly" else ("hostile" if band == "enemies" else "neutral")
	var label:String = str(g.effectiveStatus("pc", gid)["label"])
	if(label == "hated" || label == "hostile"):
		return "hostile"
	if(label == "respected" || label == "trusted"):
		return "friendly"
	return "neutral"

static func standingWord(key:String) -> String:
	return {"own": "your gang", "friendly": "friendly to you", "neutral": "neutral toward you", "hostile": "hostile to you"}.get(key, "")

# The "G" badge for a character: {"text", "color", "tooltip"}, or {} when they are in no gang or the player does not know their gang. Independent of the owner/friend/nemesis tag.
static func badgeFor(characterID) -> Dictionary:
	if(!isReady() || !gangs().isInitialized() || !gangs().knowsGang(characterID)):
		return {}
	var gid:String = gangs().gangOf(characterID)
	var key:String = standingKey(gid)
	return {"text": "G", "color": BADGE_COLORS[key], "tooltip": gangs().gangName(gid) + " member (" + standingWord(key) + ")", "key": key}

# ---- Leaders: the person behind a gang (see GangScene) ----
# How a leader's own feelings stand towards the player: "warm", "neutral", "wary" or "hostile", from their Trust and Respect (directed, separate from the gang's standing).
static func leaderMood(leaderID) -> String:
	if(leaderID == "" || !isReady()):
		return "neutral"
	var score:float = (feeling(leaderID, "pc", "trust") + feeling(leaderID, "pc", "respect")) / 2.0
	if(score <= -30.0):
		return "hostile"
	if(score <= -8.0):
		return "wary"
	if(score >= 30.0):
		return "warm"
	return "neutral"

# What a leader's face says before they say anything.
static func leaderGreeting(gid:String) -> String:
	var leaderID:String = gangs().getLeader(gid)
	var name:String = nameOf(leaderID)
	var own:bool = gangs().playerGang() == gid
	match(leaderMood(leaderID)):
		"hostile":
			return name + " looks at you with open contempt and does not offer you a seat."
		"wary":
			return name + " watches you carefully, arms folded."
		"warm":
			return name + " nods when they see you." + (" [say=" + leaderID + "]One of ours.[/say]" if own else " They seem to like what they have heard.")
	return name + " looks up as you approach." + (" [say=" + leaderID + "]What do you need?[/say]" if own else "")

# Moves the leader's directed Trust and Respect towards the player (clamped by the relationship system). Joining or finishing a job builds a connection, never an instant friendship.
static func adjustLeader(gid:String, trust:float, respect:float) -> void:
	var leaderID:String = gangs().getLeader(gid)
	if(leaderID == "" || leaderID == "pc" || !isReady()):
		return
	if(trust != 0.0):
		var _t:float = module().getRelationships().adjustFeeling(leaderID, "pc", "trust", trust)
	if(respect != 0.0):
		var _r:float = module().getRelationships().adjustFeeling(leaderID, "pc", "respect", respect)

# Asking a leader to take you in is a small step towards them, once a day per gang (so it cannot be farmed).
static func noteJoinRequest(gid:String) -> void:
	if(gid == "" || !isReady()):
		return
	var key:String = "askjoin_" + gid
	var cooldowns:Dictionary = gangs().data()["cooldowns"]
	if(int(cooldowns.get(key, -1)) == GM.main.getDays()):
		return
	cooldowns[key] = GM.main.getDays()
	adjustLeader(gid, 1.0, 0.0)

# ---- What a leader says and shows (see GangDialogue) ----
# The resolved names for an assignment's speech and panels.
static func speechContext(a:Dictionary) -> Dictionary:
	var g = gangs()
	var gid:String = str(a.get("gang", ""))
	var leaderID:String = g.getLeader(gid) if gid != "" else ""
	var target:String = str(a.get("target", ""))
	var rival:String = str(a.get("rival", ""))
	var type:String = str(a.get("type", ""))
	var targetGang:String = ""
	var recipientGang:String = ""
	var clue:String = ""
	if(target != "" && g.gangOf(target) != ""):
		var theirs:String = g.gangOf(target)
		if(type == "courier"):
			recipientGang = g.gangName(theirs)
		if(type != "courier" && (g.knowsGang(target) || str(a.get("state", "")) != "offered")):
			targetGang = g.gangName(theirs)
		if(type == "courier" || g.knowsGang(target)):
			clue = clueFor(theirs)
	if(type == "rescue" && rival != "" && g.gangOf(rival) != ""):
		clue = clueFor(g.gangOf(rival))
	return {"gang": g.gangName(gid) if gid != "" else "the gang", "leader": nameOf(leaderID) if leaderID != "" else "the leader", "target": nameOf(target) if target != "" else "",
		"targetGang": targetGang, "recipientGang": recipientGang, "rival": nameOf(rival) if rival != "" else "", "amount": int(a.get("amount", 0)), "credits": str(a.get("item", "")) == "", "clue": clue}

# Where the player can look for a gang's people, if the gang has a place: "Members of Ironhand usually gather at the gym weights room."
static func clueFor(gid:String) -> String:
	var room:String = gangs().getHangout(gid)
	if(room == ""):
		return ""
	return "Members of " + gangs().gangName(gid) + " usually gather at " + ServiceScript.hangoutName(room) + "."

# The leader's words about a job, in their voice, and the one panel of facts under it.
static func offerSpeechText(a:Dictionary) -> String:
	var ctx:Dictionary = speechContext(a)
	return GangDialogue.line(str(ctx["leader"]), gangs().getLeader(str(a["gang"])), GangDialogue.offerSpeech(str(a["gang"]), str(a["type"]), bool(a["intro"]), ctx))

static func offerPanelText(a:Dictionary) -> String:
	return GangDialogue.offerPanel(a, speechContext(a), ServiceScript.HOUR)

# A job that is already accepted: the leader's reminder and a short status.
static func reminderText(a:Dictionary) -> String:
	var ctx:Dictionary = speechContext(a)
	return GangDialogue.line(str(ctx["leader"]), gangs().getLeader(str(a["gang"])), GangDialogue.reminderSpeech(str(a["gang"]), str(a["type"]), ctx))

static func statusPanelText(a:Dictionary) -> String:
	return GangDialogue.statusPanel(a, speechContext(a), now(), ServiceScript.HOUR)

# ---- Introductory jobs (see GangAffairs.makeIntro) ----
# Members of other gangs the leader of `gid` would send the player after: not friends of this gang, not captive, not a story or player-owned character.
static func introRivals(gid:String) -> Array:
	var g = gangs()
	var result:Array = []
	for other in g.gangIDs():
		if(other == gid || g.getRelation(gid, other) >= ServiceScript.FRIEND_AT || g.getGang(other).get("player", false)):
			continue
		for id in g.activeMembers(other):
			if(id != g.getLeader(other) && !isProtectedTarget(id) && !g.isCaptive(id)):
				result.append(id)
	result.sort()
	return result

# Members of gangs friendly or at least not hostile to `gid`, who can receive a courier delivery.
static func introRecipients(gid:String) -> Array:
	var g = gangs()
	var result:Array = []
	for other in g.gangIDs():
		if(other == gid || g.areEnemies(gid, other) || g.getGang(other).get("player", false)):
			continue
		for id in g.activeMembers(other):
			if(id != g.getLeader(other) && !isProtectedTarget(id) && !g.isCaptive(id)):
				result.append(id)
	result.sort()
	return result

# The leader names the introductory job. Returns what is shown (the leader's words, then the panel), or "" when there is nobody to name.
static func offerIntro(gid:String) -> String:
	var offer:Dictionary = affairs().makeIntro(gid, now(), {"rivals": introRivals(gid), "recipients": introRecipients(gid), "day": GM.main.getDays()})
	if(offer.empty()):
		return ""
	adjustLeader(gid, 1.0, 0.0) # asking, and hearing them out, is a small step
	return offerSpeechText(offer) + "\n\n" + offerPanelText(offer)

# The player reports a finished job to the leader in person. The leader answers, the reward is paid once, and an introductory job makes the player eligible to join (the leader then offers
# membership, see canInitiate and initiate; nothing joins the player automatically).
static func reportAssignment() -> String:
	var a:Dictionary = affairs().getAssignment()
	if(!affairs().canReport()):
		return "[color=red]There is nothing to report.[/color]"
	var gid:String = str(a["gang"])
	var ctx:Dictionary = speechContext(a)
	var speech:String = GangDialogue.line(str(ctx["leader"]), gangs().getLeader(gid), GangDialogue.reportSpeech(gid, str(a["type"]), bool(a["intro"]), ctx))
	var result:Dictionary = affairs().complete(now())
	if(result.empty()):
		return "[color=red]There is nothing to report.[/color]"
	var text:String = speech + "\n\n" + applyReward(result)
	var hold:String = initiationBlocker(result)
	if(hold != ""):
		text += "\n\n" + hold
	return text

# For an introductory job just finished: why the leader cannot take the player in yet ("" when they can, or when the job was not introductory).
static func initiationBlocker(result:Dictionary) -> String:
	if(!result.get("intro", false)):
		return ""
	var gid:String = str(result.get("gang", ""))
	var check:Dictionary = joinCheck(gid)
	if(check["ok"]):
		return ""
	return "[color=yellow]" + nameOf(gangs().getLeader(gid)) + " is satisfied with the job, but " + PoolStringArray(check["reasons"]).join(" ") + "[/color]"

# Whether this gang's leader can offer the player membership now: the player is in no gang, qualifies (an introductory job counts) and nothing else stands in the way.
static func canInitiate(gid:String) -> bool:
	if(!isReady() || gid == "" || !gangs().hasGang(gid) || gangs().playerGang() != "" || gangs().getGang(gid).get("player", false)):
		return false
	return bool(joinCheck(gid)["ok"])

# The leader explains what joining asks, in their voice and the gang's code, one commitment to a line.
static func initiationText(gid:String) -> String:
	var leaderID:String = gangs().getLeader(gid)
	var lines:Array = [GangDialogue.line(nameOf(leaderID), leaderID, GangDialogue.initiationSpeech(gid)), ""]
	for commitment in GangDialogue.codeOf(gid):
		lines.append("• " + str(commitment))
	return PoolStringArray(lines).join("\n")

# The player agrees: the leader welcomes them in their voice, then the plain facts of joining. Joins exactly once (a player already in a gang, or one who no longer qualifies, is refused with a reason).
static func initiate(gid:String) -> String:
	if(!canInitiate(gid)):
		var check:Dictionary = joinCheck(gid)
		if(!check["reasons"].empty()):
			return "[color=red]" + PoolStringArray(check["reasons"]).join(" ") + "[/color]"
		return "[color=red]They cannot take you in right now.[/color]"
	var leaderID:String = gangs().getLeader(gid)
	var facts:String = join(gid)
	return GangDialogue.line(nameOf(leaderID), leaderID, GangDialogue.welcomeSpeech(gid)) + "\n\n" + facts

# The player says they are not ready. Nothing is lost: the introductory job stays done.
static func postponeInitiation(gid:String) -> String:
	var leaderID:String = gangs().getLeader(gid)
	return GangDialogue.line(nameOf(leaderID), leaderID, GangDialogue.notYetSpeech(gid))

# The player hands a courier job's payment to its recipient in person. The credits go to the recipient's gang; the job is then ready to be reported.
static func deliverCourier(recipientID:String) -> String:
	var a:Dictionary = affairs().getAssignment()
	if(!affairs().canCourier(recipientID, now())):
		return "[color=red]You have nothing to deliver to them.[/color]"
	if(GM.pc.getCredits() < int(a["amount"])):
		return "[color=red]You need " + str(a["amount"]) + " credits for it.[/color]"
	GM.pc.addCredits(-int(a["amount"]))
	var theirs:String = gangs().gangOf(recipientID)
	if(theirs != ""):
		var _t:int = gangs().addTreasury(theirs, int(a["amount"]))
	var _ok:bool = affairs().completeCourier(now())
	var _known:bool = gangs().learnGang(recipientID)
	return "[color=yellow]" + str(a["amount"]) + " credits handed over to " + nameOf(recipientID) + ".[/color] They nod. Report back to " + nameOf(gangs().getLeader(str(a["gang"]))) + " in person."

# ---- The Side Tasks list (see Quests/GangAssignmentQuest.gd) ----
# What the quest log shows for the accepted job: {"visible", "title", "lines"}. An offered job that was not accepted is not listed.
static func taskView() -> Dictionary:
	if(!isReady() || !gangs().isInitialized()):
		return {"visible": false, "title": "", "lines": []}
	var a:Dictionary = affairs().getAssignment()
	if(!a.empty() && str(a.get("state", "")) == "offered"):
		var leaderName:String = nameOf(gangs().getLeader(str(a.get("gang", ""))))
		return {"visible": true, "title": leaderName + " has a job for you", "lines": [leaderName + " wants to give you a job. Talk to them and open Gangs to hear about it. You can accept or decline."]}
	if(a.empty() || !["active", "ready"].has(str(a.get("state", "")))):
		return {"visible": false, "title": "", "lines": []}
	var ctx:Dictionary = speechContext(a)
	return {"visible": true, "title": GangDialogue.taskTitle(a, ctx), "lines": GangDialogue.taskLines(a, ctx, now(), ServiceScript.HOUR)}

# Who the accepted gang job points at right now, for the map's yellow Q: [[kind, tooltip text]] where kind is "target" (somebody to beat, free or capture) or "contact" (somebody to take something to, hand somebody to, or report to).
# Read from the live assignment (nothing is stored), so it follows the objective, disappears when the job is reported, fails or lapses, and is the same thing the Side Tasks entry shows.
static func taskMarks(characterID) -> Array:
	var marks:Array = []
	if(!isReady() || !gangs().isInitialized()):
		return marks
	var a:Dictionary = affairs().getAssignment()
	if(a.empty() || !["offered", "active", "ready"].has(str(a.get("state", "")))):
		return marks
	var leader:String = gangs().getLeader(str(a.get("gang", "")))
	if(str(a["state"]) == "offered"):
		if(characterID == leader && leader != ""):
			marks.append(["contact", "Hear about the job from " + nameOf(leader)])
		return marks
	var target:String = str(a.get("target", ""))
	if(str(a["state"]) == "ready"):
		if(characterID == leader && leader != ""):
			marks.append(["contact", "Report to " + nameOf(leader)])
		return marks
	match(str(a.get("type", ""))):
		"defeat":
			if(characterID == target && target != ""):
				marks.append(["target", "Defeat " + nameOf(target)])
		"capture":
			if(str(a.get("stage", "")) == "defeated"):
				if(characterID == leader && leader != ""):
					marks.append(["contact", "Hand " + nameOf(target) + " over to " + nameOf(leader)])
			elif(characterID == target && target != ""):
				marks.append(["target", "Beat " + nameOf(target) + " and hand them over"])
		"courier":
			if(characterID == target && target != ""):
				marks.append(["contact", "Deliver to " + nameOf(target)])
		"deliver":
			if(characterID == leader && leader != ""):
				marks.append(["contact", "Deliver to " + nameOf(leader)])
		"rescue":
			if(characterID == target && target != ""):
				marks.append(["target", "Free " + nameOf(target)])
			var rival:String = str(a.get("rival", ""))
			if(characterID == rival && rival != ""):
				marks.append(["target", "Beat " + nameOf(rival) + " to free " + nameOf(target)])
	return marks

# The archived entry for the latest job reported back: {"visible", "title", "lines"}.
static func taskDoneView() -> Dictionary:
	if(!isReady() || !gangs().isInitialized()):
		return {"visible": false, "title": "", "lines": []}
	var last:Dictionary = gangs().data()["player"].get("last_job", {})
	if(last.empty() || !gangs().hasGang(str(last["gang"]))):
		return {"visible": false, "title": "", "lines": []}
	var ctx:Dictionary = speechContext({"gang": last["gang"], "target": last["target"], "type": last["type"], "state": "done"})
	return {"visible": true, "title": GangDialogue.taskTitle(last, ctx), "lines": GangDialogue.doneLines(last, ctx)}

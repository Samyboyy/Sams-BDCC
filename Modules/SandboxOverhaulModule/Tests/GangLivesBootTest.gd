extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/GangLivesBootTest.tscn
# The gangs as people: leaders and members at their hangouts every afternoon, joining each gang in person through that gang's own introductory job, the "G" badges on the map next to
# O/F/N, and friends, gang mates, leaders and owners asking for help in a fight. The real map, UI, scenes, extender, module and pawns; only the game clock is driven by the test.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const ViewsScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangViews.gd")
const HelpScript = preload("res://Modules/SandboxOverhaulModule/Interactions/HelpRequests.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")

var failures = 0

class TestMain extends "res://Game/MainScene.gd":
	var holder = null
	var counter = 0
	func processTime(_seconds):
		timeOfDay += int(round(_seconds))
	func addDynamicCharacter(character, _printDebug = true):
		if(holder != null):
			holder.add_child(character)
			dynamicCharacters[character.getID()] = character
			return
		.addDynamicCharacter(character, _printDebug)
	func generateCharacterID(prefix = "dynamicnpc"):
		counter += 1
		return prefix + "g" + ("%03d" % counter)

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

var main = null
var thePlayer = null
var module = null
var IS = null
var world = null
var extender = null
var ui = null
var inmateIDs = []
var guardIDs = []

func gs():
	return GangGameScript.gangs()

func af():
	return GangGameScript.affairs()

func rel():
	return module.getRelationships()

func moveTo(roomID):
	thePlayer.location = roomID
	if(IS.hasPawn("pc")):
		IS.getPawn("pc").setLocation(roomID)

func endPlayerInteractions():
	for interaction in IS.interactions.duplicate():
		if(interaction.getInvolvedPawnIDs().has("pc")):
			IS.stopInteraction(interaction)

func advance(seconds, step = 120):
	var left = int(seconds)
	while(left > 0):
		var slice = int(min(step, left))
		left -= slice
		main.timeOfDay += slice
		if(main.timeOfDay >= 86400):
			main.timeOfDay -= 86400
		IS.processTime(slice)
		endPlayerInteractions()
		module.onPopulationTick()

func setClock(hour, minute, day):
	main.timeOfDay = int(hour * 3600 + minute * 60)
	main.currentDay = day
	extender.director = {}

func options():
	var result = {}
	for option in ui.options.values():
		result[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	return result

func screen(sceneScript):
	ui.clearButtons()
	ui.clearText()
	sceneScript._run()
	return options()

func placeAt(id, room):
	var pawn = DirectorScript.spawnAt(IS, id, room)
	if(pawn != null and pawn.getLocation() != room):
		var wasDisabled = IS.interactionsDisabled
		IS.interactionsDisabled = true
		pawn.setLocation(room)
		IS.interactionsDisabled = wasDisabled
	return pawn

func newScene(args = []):
	var scene = load("res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd").new()
	scene._initScene(args)
	return scene

func _ready():
	get_tree().create_timer(280.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")
	main = TestMain.new()
	GM.main = main
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	main.holder = self
	ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	world = GM.world
	world.addTransitions()
	GlobalRegistry.getWorldEdit("SandboxWorkWorldEdit").apply(world)
	var inmateGen = InmateGenerator.new()
	for n in range(30):
		var c = inmateGen.generate({})
		c.setFlag(CharacterFlag.InmateType, InmateType.General if n < 14 else (InmateType.HighSec if n < 23 else InmateType.SexDeviant))
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	inmateIDs.sort()
	var guardGen = GuardGenerator.new()
	for _n in range(4):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	thePlayer.inmateType = InmateType.General
	IS.updatePCLocation()
	var _placed = module.refreshCells()
	GangGameScript.ensureInitialized()
	for growDay in range(300, 340):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	var g = gs()
	check(g.isInitialized() and g.gangIDs().size() == 3, "setup: three gangs")
	var leaders = {}
	for gid in g.gangIDs():
		leaders[gid] = g.getLeader(gid)
	moveTo("yard_deadend2")

	# ---- Hangouts: the leader and at least one other member are there every afternoon, nobody is sent there because the player came ----
	var DAY = 40
	var hangouts = {}
	for gid in g.gangIDs():
		hangouts[gid] = g.getHangout(gid)
	setClock(12, 30, DAY)
	var _t = DirectorScript.tick(module, extender.director, true)
	for gid in g.gangIDs():
		check(module.getNpcJobs().getJob(leaders[gid]) == "", gid + "'s leader has no job to keep them away from the hangout")
	advance(3 * 3600 + 15 * 60, 120)
	var at = {}
	var outsiders = 0
	var rivalsInEnemyHangout = 0
	for gid in g.gangIDs():
		var present = []
		for id in g.activeMembers(gid):
			var pawn = IS.getPawn(id)
			if(pawn != null and pawn.getLocation() == hangouts[gid]):
				present.append(id)
		at[gid] = present
		check(present.has(leaders[gid]), "at 15:45 the leader of " + gid + " is at " + hangouts[gid] + ": present " + str(present.size()))
		check(present.size() >= 2, gid + " has at least the leader and one other member at the hangout: " + str(present.size()))
	for id in inmateIDs:
		var pawn = IS.getPawn(id)
		if(pawn == null):
			continue
		var gid = g.gangOf(id)
		for other in hangouts:
			if(pawn.getLocation() == hangouts[other] and gid != other):
				if(gid == "" and !g.isCaptive(id)):
					outsiders += 1
				elif(gid != "" and g.areEnemies(gid, other)):
					rivalsInEnemyHangout += 1
	check(outsiders <= 3, "unaffiliated inmates mostly spend the afternoon elsewhere: " + str(outsiders) + " at gang hangouts")
	check(rivalsInEnemyHangout == 0, "rival gang members stay out of their enemies' hangouts: " + str(rivalsInEnemyHangout))
	var detail = PoolStringArray(ViewsScript.detailLines("ironhand")).join(" ")
	check(detail.find("normally at") != -1 and detail.find("15:00 to 17:30") != -1 and detail.find("find ") != -1, "the gang's page says where and when to find the leader and to go in person: " + detail.substr(0, 300))
	# The player walking in changes nothing: the same people are already there
	var before = {}
	for gid in g.gangIDs():
		before[gid] = at[gid].size()
		moveTo(hangouts[gid])
		var present2 = 0
		for id in g.activeMembers(gid):
			var pawn2 = IS.getPawn(id)
			if(pawn2 != null and pawn2.getLocation() == hangouts[gid]):
				present2 += 1
		check(present2 == before[gid], "walking into " + gid + "'s hangout does not summon anybody: " + str(present2) + " there before and after")
	moveTo("yard_deadend2")
	# And at night they are in their cells, not at the hangout
	setClock(23, 30, DAY)
	extender.director = {}
	advance(2 * 3600, 120)
	var leaderPawn = IS.getPawn(leaders["ironhand"])
	check(leaderPawn != null and leaderPawn.getLocation() != hangouts["ironhand"], "late at night the leader is not at the hangout")

	# ---- Joining each gang in person ----
	thePlayer.addCredits(60 - thePlayer.getCredits())
	var expectedType = {"ironhand": "defeat", "hushmarket": "courier", "collarcircle": "capture"}
	for gid in ["ironhand", "hushmarket", "collarcircle"]:
		var leader = leaders[gid]
		# a clean slate with this gang
		gs().data()["player"]["intro"].clear()
		gs().data()["player"]["left_day"] = -1
		gs().data()["player"]["left_from"] = ""
		gs().data()["assignment"] = {}
		gs().data()["cooldowns"].clear()
		var _p = gs().setPersonal("pc", gid, 0)
		rel().setFeeling(leader, "pc", "trust", 0)
		rel().setFeeling(leader, "pc", "respect", 0)
		rel().setFeeling(leader, "pc", "affection", 0)
		var trustBefore = rel().getFeeling(leader, "pc", "trust")
		var respectBefore = rel().getFeeling(leader, "pc", "respect")
		# the information screen offers nothing social
		var page = newScene([])
		page._react("viewgang", [gid])
		var pageOptions = screen(page)
		check(!pageOptions.has("Join") and !pageOptions.has("Assignment") and !pageOptions.has("Leave gang") and !pageOptions.has("Report back"), gid + ": the gang page is information only, nothing can be done remotely: " + str(pageOptions.keys()))
		# the leader, in person
		var talk = newScene([leader])
		var talkOptions = screen(talk)
		check(talkOptions.has("Ask about joining") and talkOptions["Ask about joining"]["enabled"] and ui.textOutput.bbcode_text.find(GangGameScript.nameOf(leader)) != -1, gid + ": talking to the leader offers joining, with the leader's own greeting")
		talk._react("join", [])
		var joinOptions = screen(talk)
		check(joinOptions.has("Hear what they want") and !joinOptions.has("Join"), gid + ": an unknown outsider is not simply let in; the leader names a job: " + str(joinOptions.keys()))
		check(rel().getFeeling(leader, "pc", "trust") > trustBefore, gid + ": asking, once, moves the leader's trust a little")
		var creditsBefore = thePlayer.getCredits()
		talk._react("takeintro", [gid])
		var offer = af().getAssignment()
		check(!offer.empty() and offer["type"] == expectedType[gid] and offer["intro"] and offer["state"] == "offered" and offer["reward"] == 0, gid + "'s introductory job is its own kind of job: " + str(offer.get("type")))
		check(thePlayer.getCredits() == creditsBefore, "nothing was charged for hearing it")
		var target = str(offer["target"])
		check(target != "" and !GangGameScript.isProtectedTarget(target) and g.gangOf(target) != "" and g.gangOf(target) != gid and g.gangOf(target) != "player", gid + ": the target is a named, valid member of another gang: " + target)
		if(gid == "ironhand"):
			check(g.areEnemies("ironhand", g.gangOf(target)) or g.getRelation("ironhand", g.gangOf(target)) < 40, "Ironhand's target is a rival, not a guard or a friend")
		if(gid == "hushmarket"):
			check(!g.areEnemies("hushmarket", g.gangOf(target)), "the Hush Market's courier job goes to someone the market does not fight")
		if(gid == "collarcircle"):
			check(g.getRelation("collarcircle", g.gangOf(target)) < 40, "the Collar Circle's target is not one of its friends")
		check(GangGameScript.reportAssignment().find("nothing to report") != -1 and g.playerGang() == "", gid + ": nothing can be reported before the job is done, and the player is not in the gang")
		check(!GangGameScript.joinCheck(gid)["ok"], gid + ": still not accepted")
		# accept it, then save and load in the middle of the job
		talk._react("job", [])
		var jobOptions = screen(talk)
		check(jobOptions.has("Accept") and jobOptions.has("Decline"), gid + ": the job menu offers Accept and Decline")
		talk._react("acceptjob", [])
		check(af().getAssignment()["state"] == "active" and g.knowsGang(target), gid + ": accepted; the job names the target, so the player now knows their gang")
		var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
		for _k in range(2):
			GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
		check(af().getAssignment()["state"] == "active" and af().getAssignment()["target"] == target and af().getAssignment()["type"] == expectedType[gid], gid + ": the job survives a save and load unchanged")
		# do it
		if(gid == "hushmarket"):
			check(GangGameScript.deliverCourier(leader).find("nothing to deliver") != -1, "the package cannot be given to the wrong person")
			check(GangGameScript.deliverCourier(target).find("handed over") != -1 and af().getAssignment()["state"] == "ready", "handing the package to its named recipient readies the job")
		else:
			GangGameScript.onFightResult("pc", target)
		if(gid == "collarcircle"):
			check(af().getAssignment()["stage"] == "defeated" and g.playerGang() == "", "the target is beaten, and still has to be brought to the leader")
			talk._react("job", [])
			check(screen(talk).has("Hand over the captive"), "handing over happens at the leader")
			talk._react("handover", [])
		elif(gid == "ironhand"):
			check(af().getAssignment()["state"] == "ready" and g.playerGang() == "" and thePlayer.getCredits() == creditsBefore, "Ironhand's rival is beaten but the player is not admitted until they report back")
		else:
			check(af().getAssignment()["state"] == "ready" and g.playerGang() == "", "the courier job is done but the player is not admitted until they report back")
		if(gid != "collarcircle"):
			var saved2 = JSON.parse(JSON.print(GM.GES.saveData())).result
			GM.GES.loadData(JSON.parse(JSON.print(saved2)).result)
			check(af().canReport() and g.playerGang() == "", gid + ": a finished job waiting for the report survives a load")
			talk._react("job", [])
			check(screen(talk).has("Report back"), gid + ": the leader has a Report back button")
			talk._react("report", [])
		check(g.playerGang() == "" and af().hasIntroDone(gid) and !af().hasAssignment(), gid + ": reporting back (or handing over) pays and makes the player eligible, but does not join them")
		var oathOptions = screen(talk)
		check(talk.state == "initiation" and oathOptions.has("I agree") and oathOptions.has("Not yet"), gid + ": the leader offers membership and the gang's code: " + str(oathOptions.keys()))
		talk._react("doinitiate", [gid])
		check(g.playerGang() == gid and g.isMember("pc", gid), gid + ": agreeing to the code joins the player")
		check(rel().getFeeling(leader, "pc", "trust") > trustBefore + 5.0 and rel().getFeeling(leader, "pc", "respect") > respectBefore + 5.0, gid + ": the leader's trust and respect rose with the introduction and joining: " + str(rel().getFeeling(leader, "pc", "trust")) + " / " + str(rel().getFeeling(leader, "pc", "respect")))
		check(rel().getFeeling(leader, "pc", "trust") + rel().getFeeling(leader, "pc", "affection") < 40.0 and module.getRelationships().getFeeling(leader, "pc", "affection") < 20.0, gid + ": joining does not make the leader a friend")
		check(g.knowsGang(leader) and GangGameScript.badgeFor(leader).get("key", "") == "own", gid + ": the player knows the leader, who shows as their own gang's on the map")
		var greeting = GangGameScript.leaderGreeting(gid)
		check(greeting.find(GangGameScript.nameOf(leader)) != -1 and greeting.find("One of ours") != -1 or GangGameScript.leaderMood(leader) != "warm", gid + ": the leader greets a member by their relationship")
		# leaving is a conversation too
		var leaveTalk = newScene([leader])
		check(screen(leaveTalk).has("Leave the gang"), gid + ": leaving is offered by the leader in person")
		var memberPage = newScene([])
		memberPage._react("viewgang", [gid])
		var memberPageOptions = screen(memberPage)
		check(!memberPageOptions.has("Leave gang") and !memberPageOptions.has("Contribute 5") and !memberPageOptions.has("Assignment"), gid + ": and not from the information page")
		var _left = GangGameScript.leave()
		check(g.playerGang() == "", "setup: left again")
	# A leader who hates the player is not a menu
	var coldGang = "ironhand"
	var coldLeader = leaders[coldGang]
	gs().data()["player"]["left_day"] = -1
	gs().data()["player"]["left_from"] = ""
	gs().data()["assignment"] = {}
	rel().setFeeling(coldLeader, "pc", "trust", -70)
	rel().setFeeling(coldLeader, "pc", "respect", -70)
	check(GangGameScript.leaderMood(coldLeader) == "hostile", "setup: the leader loathes the player")
	var coldTalk = newScene([coldLeader])
	var coldOptions = screen(coldTalk)
	check(coldOptions.has("Ask about joining") and !coldOptions["Ask about joining"]["enabled"] and coldOptions["Ask about joining"]["tooltip"].find("wants nothing to do with you") != -1, "a leader who loathes the player will not discuss joining: " + str(coldOptions.get("Ask about joining")))
	check(ui.textOutput.bbcode_text.find("contempt") != -1, "and their face says so")
	rel().setFeeling(coldLeader, "pc", "trust", 0)
	rel().setFeeling(coldLeader, "pc", "respect", 0)
	# An invalid target is cancelled without blame and replaced
	gs().data()["cooldowns"].clear()
	gs().data()["player"]["intro"].clear()
	var _o = GangGameScript.offerIntro("ironhand")
	var firstTarget = str(af().getAssignment()["target"])
	var _acc = GangGameScript.acceptAssignment()
	var standingBefore = gs().getPersonal("pc", "ironhand")
	var _r = gs().removeMember(firstTarget)
	GangGameScript.checkAssignment()
	check(!af().hasAssignment() and gs().getPersonal("pc", "ironhand") == standingBefore, "a target who left their gang cancels the job without penalty")
	var again = GangGameScript.offerIntro("ironhand")
	check(again != "" and str(af().getAssignment()["target"]) != firstTarget, "and the leader names somebody else")
	gs().data()["assignment"] = {}

	# ---- Badges: G beside O/F/N, by how the gang stands with the player ----
	if(gs().playerGang() != ""):
		var _l = gs().leave("pc", 50, {})
	var own = "ironhand"
	var _j = gs().join("pc", own, 60)
	check(gs().playerGang() == own, "setup: the player is in Ironhand")
	var mate = ""
	for id in gs().activeMembers(own):
		if(id != "pc" and id != leaders[own]):
			mate = id
	var otherGang = "hushmarket"
	var third = "collarcircle"
	var otherMember = ""
	for id in gs().activeMembers(otherGang):
		if(id != leaders[otherGang]):
			otherMember = id
	var thirdMember = ""
	for id in gs().activeMembers(third):
		if(id != leaders[third]):
			thirdMember = id
	check(mate != "" and otherMember != "" and thirdMember != "", "setup: members to look at")
	var _k1 = gs().setRelation(own, otherGang, -60)
	var _k2 = gs().setRelation(own, third, 0)
	check(GangGameScript.badgeFor(mate)["key"] == "own" and GangGameScript.badgeFor(mate)["text"] == "G" and GangGameScript.badgeFor(mate)["tooltip"].find("your gang") != -1, "a member of your own gang: green G, and the tooltip says so")
	check(GangGameScript.badgeFor(otherMember).empty() and GangGameScript.badgeFor("nobody").empty(), "a member of another gang whose gang you do not know has no badge")
	var _learn = gs().learnGang(otherMember)
	var _learn2 = gs().learnGang(thirdMember)
	var hostileBadge = GangGameScript.badgeFor(otherMember)
	var neutralBadge = GangGameScript.badgeFor(thirdMember)
	check(hostileBadge["key"] == "hostile" and hostileBadge["color"] == GangGameScript.BADGE_COLORS["hostile"] and hostileBadge["tooltip"].find("hostile") != -1, "an enemy gang's member: red G, hostile in words")
	check(neutralBadge["key"] == "neutral" and neutralBadge["color"] == GangGameScript.BADGE_COLORS["neutral"] and neutralBadge["tooltip"].find("neutral") != -1, "a neutral gang's member: yellow G, neutral in words")
	var _k3 = gs().setRelation(own, third, 60)
	var friendlyBadge = GangGameScript.badgeFor(thirdMember)
	check(friendlyBadge["key"] == "friendly" and friendlyBadge["color"] == GangGameScript.BADGE_COLORS["friendly"] and friendlyBadge["tooltip"].find("friendly") != -1, "an allied gang's member: blue G, friendly in words")
	check(GangGameScript.BADGE_COLORS["own"] != GangGameScript.BADGE_COLORS["friendly"] and GangGameScript.BADGE_COLORS["neutral"] != GangGameScript.BADGE_COLORS["hostile"] and GangGameScript.BADGE_COLORS["own"] != GangGameScript.BADGE_COLORS["hostile"], "four different colours")
	# an independent player: by how the gang regards them
	if(gs().playerGang() != ""):
		var _leave = gs().leave("pc", 70, {})
	var _s1 = gs().setPersonal("pc", otherGang, -50)
	var _s2 = gs().setPersonal("pc", third, 0)
	var _s3 = gs().setPersonal("pc", own, 40)
	check(GangGameScript.badgeFor(otherMember)["key"] == "hostile" and GangGameScript.badgeFor(thirdMember)["key"] == "neutral" and GangGameScript.badgeFor(mate).empty(), "for an independent player the colour follows how the gang regards them")
	var _l2 = gs().learnGang(mate)
	check(GangGameScript.badgeFor(mate)["key"] == "friendly", "a gang that respects you shows blue")
	# real map markers: the owner/friend/nemesis tag and the gang badge side by side
	var _j2 = gs().join("pc", own, 90)
	main.RS.startSpecialRelantionship("Friend", mate)
	main.RS.startSpecialRelantionship("Nemesis", otherMember)
	main.RS.startSpecialRelantionship("SoftSlavery", thirdMember)
	for id in [mate, otherMember, thirdMember]:
		if(!IS.hasPawn(id)):
			var _sp = DirectorScript.spawnAt(IS, id, "hall_mainentrance")
	world.updatePawns(IS)
	var markerMate = world.pawns[mate]
	var markerOther = world.pawns[otherMember]
	var markerThird = world.pawns[thirdMember]
	check(markerMate.relationship_label.visible and markerMate.relationship_label.text == "F" and markerMate.gangLabel != null and markerMate.gangLabel.visible and markerMate.gangLabel.text == "G", "a friend in your gang shows F and G together")
	check(markerMate.gangLabel.rect_position.x > markerMate.relationship_label.rect_position.x and markerMate.gangLabel.get_color("font_color") == GangGameScript.BADGE_COLORS["own"], "G sits beside F, not over it, and is green")
	check(markerOther.relationship_label.text == "N" and markerOther.gangLabel.text == "G" and markerOther.gangLabel.get_color("font_color") == GangGameScript.BADGE_COLORS["hostile"], "a nemesis in an enemy gang shows N and a red G")
	check(markerThird.relationship_label.text == "O" and markerThird.gangLabel.text == "G", "an owner in a gang shows O and G")
	check(markerMate.gangLabel.hint_tooltip.find("your gang") != -1 and markerOther.gangLabel.hint_tooltip.find("hostile") != -1, "the badge's tooltip says it in words")
	var plain = ""
	for id in inmateIDs:
		if(gs().gangOf(id) == "" and IS.hasPawn(id) and !main.RS.hasSpecialRelationshipID(id, "Friend")):
			plain = id
	world.updatePawns(IS)
	check(plain == "" or world.pawns[plain].gangLabel == null or !world.pawns[plain].gangLabel.visible, "somebody in no gang has no badge")
	var legend = ViewsScript.legendLines()
	check(legend[0].find("green") != -1 and legend[0].find("blue") != -1 and legend[0].find("yellow") != -1 and legend[0].find("red") != -1 and legend[1].find("O") != -1, "the gang screen explains the badges")
	var landing = newScene([])
	var _lo = screen(landing)
	check(ui.textOutput.bbcode_text.find("green your gang") != -1, "and the landing page shows the legend")
	if(gs().playerGang() != ""):
		var _l3 = gs().leave("pc", 100, {})

	# ---- Help requests in a fight ----
	var _lj = gs().join("pc", own, 120)
	var fighters = []
	for id in inmateIDs:
		if(gs().gangOf(id) == "" and !gs().isCaptive(id)):
			fighters.append(id)
	var friendID = fighters[0]
	var foeID = fighters[1]
	var strangerID = fighters[2]
	var ownerID = fighters[3]
	var gangmate = mate
	var leaderID = leaders[own]
	thePlayer.addStamina(200)
	moveTo("hall_mainentrance")
	for id in [friendID, foeID, strangerID, gangmate, leaderID]:
		placeAt(id, "hall_mainentrance")
	var _a = rel().setFeeling(friendID, "pc", "trust", 50)
	var _b = rel().setFeeling(friendID, "pc", "affection", 50)
	check(HelpScript.bondOf(module, friendID) == "friend" and HelpScript.bondOf(module, gangmate) == "gangmate" and HelpScript.bondOf(module, leaderID) == "leader" and HelpScript.bondOf(module, strangerID) == "" and HelpScript.bondOf(module, "pc") == "", "who would ask: a friend, a gang mate, the leader, not a stranger")
	check(HelpScript.rank("owner") > HelpScript.rank("leader") and HelpScript.rank("leader") > HelpScript.rank("gangmate") and HelpScript.rank("gangmate") > HelpScript.rank("friend") and HelpScript.rank("friend") > HelpScript.rank("ally"), "bonds rank owner, leader, gang mate, friend, ally")
	# Friend asks
	var trust0 = rel().getFeeling(friendID, "pc", "trust")
	var respect0 = rel().getFeeling(friendID, "pc", "respect")
	IS.startInteraction("GenericAttack", {"starter": friendID, "reacter": foeID})
	var request = IS.getPawn("pc").currentInteraction
	check(request != null and request.id == "SandboxHelpRequest" and request.asker == friendID and request.foe == foeID and request.bond == "friend", "a friend in a fight in front of the player asks for help")
	var fight = HelpScript.findFight(friendID, foeID)
	check(fight != null and !fight.wasDeleted, "and the fight goes on while the player decides")
	check(!request.delivered, "the request has not been shown yet, so nothing can be owed")
	check(HelpScript.resolve(module, friendID, foeID, "friend", "refuse", request.delivered) == "" and rel().getFeeling(friendID, "pc", "trust") == trust0, "refusing a request the player never saw changes nothing")
	var shown = request.getTextAndActions()
	check(request.delivered and shown[0].find("friend") != -1 and shown[1].size() == 3, "when the request is shown it offers three answers: " + str(shown[1].size()))
	var answers = []
	for action in shown[1]:
		answers.append(action["name"])
	check(answers == ["Help them", "Try to break it up", "Refuse"], "Help them, Try to break it up, Refuse: " + str(answers))
	var secondAsk = HelpScript.onFightStarted(module, fight)
	check(secondAsk == "", "the same fight never asks twice")
	request.init_do("refuse", {}, {})
	check(rel().getFeeling(friendID, "pc", "trust") == trust0 - 5.0 and rel().getFeeling(friendID, "pc", "respect") == respect0 - 3.0, "refusing a friend costs modest trust and respect")
	endPlayerInteractions()
	IS.stopInteraction(fight)
	# Help
	rel().setFeeling(friendID, "pc", "trust", 50)
	rel().setFeeling(friendID, "pc", "respect", 0)
	rel().setFeeling(friendID, "pc", "affection", 50)
	gs().data()["cooldowns"].clear()
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": friendID, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	var _show2 = request.getTextAndActions()
	request.init_do("help", {}, {})
	var mine = null
	for interaction in IS.interactions:
		if(interaction.id == "GenericAttack" and !interaction.wasDeleted and interaction.getRoleID("starter") == "pc"):
			mine = interaction
	check(mine != null and mine.getRoleID("reacter") == foeID and rel().getFeeling(friendID, "pc", "respect") >= 5.0 and rel().getFeeling(friendID, "pc", "trust") > 50.0, "helping takes the friend's side and earns trust and respect")
	if(mine != null):
		IS.stopInteraction(mine)
	endPlayerInteractions()
	# Break it up
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": friendID, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	var _show3 = request.getTextAndActions()
	module.queuedRolls = [0.0]
	var trust1 = rel().getFeeling(friendID, "pc", "trust")
	request.init_do("breakup", {}, {})
	check(HelpScript.findFight(friendID, foeID) == null and rel().getFeeling(friendID, "pc", "trust") == trust1 + 3.0, "breaking it up stops the fight and the friend is grateful")
	endPlayerInteractions()
	# Gang mate refuses
	var standing0 = gs().getPersonal("pc", own)
	var mateTrust0 = rel().getFeeling(gangmate, "pc", "trust")
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": gangmate, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	check(request != null and request.id == "SandboxHelpRequest" and request.bond == "gangmate", "a member of the player's gang asks")
	var _show4 = request.getTextAndActions()
	request.init_do("refuse", {}, {})
	check(gs().getPersonal("pc", own) == standing0 - 3 and rel().getFeeling(gangmate, "pc", "trust") == mateTrust0 - 4.0 and gs().refusalCount(own) == 1, "refusing a gang mate costs gang standing and their trust, and is counted")
	var fightMate = HelpScript.findFight(gangmate, foeID)
	if(fightMate != null):
		IS.stopInteraction(fightMate)
	endPlayerInteractions()
	# The leader asks; refusing costs more, repeated refusals more still
	var leaderStanding0 = gs().getPersonal("pc", own)
	var leaderTrust0 = rel().getFeeling(leaderID, "pc", "trust")
	var leaderRespect0 = rel().getFeeling(leaderID, "pc", "respect")
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": leaderID, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	check(request != null and request.bond == "leader", "the leader of the player's gang asks")
	var _show5 = request.getTextAndActions()
	request.init_do("refuse", {}, {})
	check(gs().getPersonal("pc", own) == leaderStanding0 - 6 and rel().getFeeling(leaderID, "pc", "trust") == leaderTrust0 - 6.0 and rel().getFeeling(leaderID, "pc", "respect") == leaderRespect0 - 6.0 and gs().refusalCount(own) == 2, "refusing the leader costs more: standing -6, their trust and respect -6")
	var fightLeader = HelpScript.findFight(leaderID, foeID)
	if(fightLeader != null):
		IS.stopInteraction(fightLeader)
	endPlayerInteractions()
	main.timeOfDay += 600
	var before3 = gs().getPersonal("pc", own)
	IS.startInteraction("GenericAttack", {"starter": leaderID, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	var _show6 = request.getTextAndActions()
	request.init_do("refuse", {}, {})
	check(gs().refusalCount(own) == 3 and gs().getPersonal("pc", own) == before3 - 10, "a third refusal weighs heavier: standing -10")
	var fightLeader2 = HelpScript.findFight(leaderID, foeID)
	if(fightLeader2 != null):
		IS.stopInteraction(fightLeader2)
	endPlayerInteractions()
	# An owner asks: the refusal is recorded for later
	main.RS.startSpecialRelantionship("SoftSlavery", ownerID)
	placeAt(ownerID, "hall_mainentrance")
	check(thePlayer.isSlaveTo(ownerID) and HelpScript.bondOf(module, ownerID) == "owner", "setup: this inmate owns the player")
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": ownerID, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	check(request != null and request.id == "SandboxHelpRequest" and request.bond == "owner", "an owner asks")
	var _show7 = request.getTextAndActions()
	request.init_do("refuse", {}, {})
	check(gs().refusalCount("owner:" + ownerID) == 1, "refusing an owner is recorded for later systems, without a second ownership system")
	var fightOwner = HelpScript.findFight(ownerID, foeID)
	if(fightOwner != null):
		IS.stopInteraction(fightOwner)
	endPlayerInteractions()
	# Nothing is asked when the player is not there, cannot act, or nobody has a bond
	moveTo("main_stairs1")
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": friendID, "reacter": foeID})
	check(IS.getPawn("pc").currentInteraction == null or IS.getPawn("pc").currentInteraction.id != "SandboxHelpRequest", "a fight the player is not in the room for asks nothing")
	var farFight = HelpScript.findFight(friendID, foeID)
	if(farFight != null):
		IS.stopInteraction(farFight)
	moveTo("hall_mainentrance")
	thePlayer.addStamina(-thePlayer.getStamina())
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": friendID, "reacter": foeID})
	check(IS.getPawn("pc").currentInteraction == null or IS.getPawn("pc").currentInteraction.id != "SandboxHelpRequest", "a player who is too exhausted to act is not asked")
	var tiredFight = HelpScript.findFight(friendID, foeID)
	if(tiredFight != null):
		IS.stopInteraction(tiredFight)
	thePlayer.addStamina(200)
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": strangerID, "reacter": foeID})
	var strangersFight = HelpScript.findFight(strangerID, foeID)
	check(IS.getPawn("pc").currentInteraction == null or IS.getPawn("pc").currentInteraction.id != "SandboxHelpRequest", "strangers fighting ask for nothing")
	if(strangersFight != null):
		IS.stopInteraction(strangersFight)
	# A request that outlives its fight changes nothing
	main.timeOfDay += 600
	IS.startInteraction("GenericAttack", {"starter": friendID, "reacter": foeID})
	request = IS.getPawn("pc").currentInteraction
	var endedFight = HelpScript.findFight(friendID, foeID)
	if(endedFight != null):
		IS.stopInteraction(endedFight)
	var trustEnd = rel().getFeeling(friendID, "pc", "trust")
	var shownEnded = request.getTextAndActions()
	check(!request.delivered and shownEnded[0].find("over") != -1, "if the fight is over before the request is shown it says so")
	request.init_do("leave", {}, {})
	check(rel().getFeeling(friendID, "pc", "trust") == trustEnd, "and nobody is blamed")
	endPlayerInteractions()

	print("GangLivesBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

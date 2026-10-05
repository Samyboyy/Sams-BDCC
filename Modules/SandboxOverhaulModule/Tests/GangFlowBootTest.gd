extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/GangFlowBootTest.tscn
# Talking to gang leaders: first-person answers, the introductory assignment's presentation (speech apart from the facts), the real Side Tasks list, every way a target can be beaten
# (surrender included), and the initiation: a finished job makes the player eligible, the leader offers the code, and nothing joins the player until they agree. Real scenes, UI,
# extender, module, pawns and quest log; only the game clock is driven by the test.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const ViewsScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangViews.gd")
const HelpScript = preload("res://Modules/SandboxOverhaulModule/Interactions/HelpRequests.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")

var failures = 0

class FakeFight:
	var sandboxDefeatKind = ""

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


	var DAY = 40
	setClock(14, 0, DAY)
	var qs = QuestSystem.new()
	add_child(qs)
	var theNames = {"ironhand": "Ironhand", "hushmarket": "The Hush Market", "collarcircle": "The Collar Circle"}

	# ---- 1. A leader speaks about themselves in the first person ----
	for gid in g.gangIDs():
		var leader = leaders[gid]
		var member = ""
		for id in g.activeMembers(gid):
			if(id != leader and member == ""):
				member = id
		var leaderTalk = newScene([leader])
		leaderTalk._react("askleader", [])
		check(leaderTalk.note.find("I am in charge of " + theNames[gid] + ".") != -1 and leaderTalk.note.find(GangGameScript.nameOf(leader)) == -1, gid + ": the leader says it in the first person: " + leaderTalk.note)
		var memberTalk = newScene([member])
		memberTalk._react("askleader", [])
		check(memberTalk.note.find(GangGameScript.nameOf(leader) + " is in charge of " + theNames[gid] + ".") != -1, gid + ": a member names the leader: " + memberTalk.note)

	# ---- 2. The introductory assignment: speech apart from facts, shown once ----
	var expected = {
		"ironhand": {"type": "defeat", "speech": ["You want a place with Ironhand?", "Prove you can handle yourself.", "one of our rivals", "Put them down, then come back to me."], "accept": "Good. Come back when it is done.", "hours": "48 hours"},
		"hushmarket": {"type": "courier", "speech": ["You want in with The Hush Market?", "We do not take strangers on trust.", "credits to", "Quietly."], "accept": "Good. Keep it quiet. Come back when it is done.", "hours": "72 hours"},
		"collarcircle": {"type": "capture", "speech": ["You want a place in The Collar Circle?", "show me you can take what you want", "Beat them, then bring them to me."], "accept": "Good. Do not keep me waiting. Come back when it is done.", "hours": "72 hours"},
	}
	var codes = {
		"ironhand": ["Stand beside fellow members.", "Show strength against rivals.", "Put Ironhand before outsiders."],
		"hushmarket": ["Keep the gang's secrets.", "Honour bargains made through the gang.", "Protect its trade and members."],
		"collarcircle": ["Respect the gang hierarchy.", "Help enforce its claims.", "Protect members and controlled assets."],
	}
	var welcomes = {"ironhand": "Then you are Ironhand now. Stand with us and we will stand with you.", "hushmarket": "Then you are one of the Market now.", "collarcircle": "Then you belong to the Circle now."}
	thePlayer.addCredits(60 - thePlayer.getCredits())
	var firstGang = true
	for gid in ["ironhand", "hushmarket", "collarcircle"]:
		var leader2 = leaders[gid]
		cleanSlate(gid, leader2)
		var talk = newScene([leader2])
		var _o = screen(talk)
		talk._react("join", [])
		var _o2 = screen(talk)
		talk._react("takeintro", [gid])
		var _o3 = screen(talk)
		var text = ui.textOutput.bbcode_text
		var offer = af().getAssignment()
		check(!offer.empty() and offer["type"] == expected[gid]["type"] and offer["intro"], gid + ": the introductory job is " + expected[gid]["type"])
		for phrase in expected[gid]["speech"]:
			check(text.find(phrase) != -1, gid + ": the leader says '" + phrase + "': " + text.substr(0, 400))
		check(text.find(GangGameScript.nameOf(leader2)) != -1, gid + ": the screen names who is speaking")
		for label in ["Objective:", "Reward:", "Failure:", "Time limit:"]:
			check(text.count(label) == 1, gid + ": '" + label + "' appears exactly once (" + str(text.count(label)) + ")")
		check(text.find("Eligibility to join " + theNames[gid]) != -1 and text.find("Standing +10") != -1 and text.find("Standing −8") != -1 and text.find("Time limit:[/b] " + expected[gid]["hours"]) != -1, gid + ": the panel carries the facts: " + text.substr(text.find("Objective:") - 5, 400))
		check(text.find("introductory job") == -1 and text.find("This is the introductory") == -1, gid + ": no 'introductory job' wording")
		var splitAt = text.find("[b]Objective:")
		var spoken = text.substr(0, splitAt)
		check(spoken.find("Standing") == -1 and spoken.find("Reward") == -1 and spoken.find("Failure") == -1 and spoken.find("Eligibility") == -1, gid + ": the character does not recite reward or failure data")
		var targetName = GangGameScript.nameOf(offer["target"])
		check(text.count(targetName) <= (3 if gid == "hushmarket" else 2), gid + ": the target is named in the speech and in the objective, not recited a third time: " + str(text.count(targetName)))
		# a click on Decline then asking again does not matter here; accept it
		talk._react("acceptjob", [])
		var _o4 = screen(talk)
		var acceptedText = ui.textOutput.bbcode_text
		check(acceptedText.find(expected[gid]["accept"]) != -1 and acceptedText.find("Introductory assignment accepted.") != -1, gid + ": accepting gets a short answer and one system line: " + acceptedText.substr(0, 300))
		check(acceptedText.find("Objective:") == -1 and acceptedText.find("Reward:") == -1 and acceptedText.find("Failure:") == -1 and acceptedText.count("Introductory assignment accepted.") == 1, gid + ": the reward block is not repeated after accepting")

		# ---- 3. The Side Tasks list is the game's own quest log ----
		var logText = questLog()
		var sideStart = logText.find("Side tasks:")
		var doneStart = logText.find("Completed tasks:")
		var side = logText.substr(sideStart, doneStart - sideStart)
		var title = theNames[gid] + " Initiation"
		check(side.find(title) != -1 and logText.count(title) == 1, gid + ": the accepted job is listed once under Side tasks as '" + title + "'")
		var other = g.gangOf(offer["target"])
		match(expected[gid]["type"]):
			"defeat":
				check(side.find("Defeat " + targetName + ", a member of " + theNames[other] + ", then report back to " + GangGameScript.nameOf(leader2) + ".") != -1, gid + ": the objective names target and leader: " + side)
			"capture":
				check(side.find("Beat " + targetName) != -1 and side.find("hand them over to " + GangGameScript.nameOf(leader2)) != -1, gid + ": the capture objective: " + side)
			"courier":
				check(side.find("Take 8 credits to " + targetName) != -1 and side.find("report back to " + GangGameScript.nameOf(leader2)) != -1, gid + ": the courier objective: " + side)
		check(side.find("About 48 hours remaining.") != -1 or side.find("About 72 hours remaining.") != -1, gid + ": the time left is shown: " + side)
		check(side.find("usually gather at") != -1, gid + ": a location clue is given once the gang is known: " + side)
		main.timeOfDay += 3600
		var later = questLog()
		check(later.find("About 47 hours remaining.") != -1 or later.find("About 71 hours remaining.") != -1, gid + ": and it counts down")
		# save and load: the same single entry, no duplicate
		var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
		for _k in range(2):
			GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
		check(questLog().count(title) == 1, gid + ": after saving and loading the list still has exactly one entry")

		# ---- 4. Finish it ----
		var target = str(offer["target"])
		if(gid == "hushmarket"):
			check(GangGameScript.deliverCourier(target).find("handed over") != -1, "the package is handed over")
		else:
			GangGameScript.onFightResult("pc", target)
		if(gid == "collarcircle"):
			talk._react("job", [])
			var _o5 = screen(talk)
			var capLog = questLog()
			check(capLog.find("You beat " + targetName + ". Hand them over to " + GangGameScript.nameOf(leader2) + ".") != -1, gid + ": the entry updates once they are beaten: " + capLog.substr(capLog.find("Side tasks:"), 400))
			talk._react("handover", [])
		else:
			var readyLog = questLog()
			var readyText = {"ironhand": targetName + " has been defeated. Report back to " + GangGameScript.nameOf(leader2) + ".", "hushmarket": "You delivered the package to " + targetName + ". Report back to " + GangGameScript.nameOf(leader2) + "."}[gid]
			check(readyLog.find(readyText) != -1 and readyLog.find("Status: ready to report.") != -1, gid + ": the entry says it is ready to report: " + readyLog.substr(readyLog.find("Side tasks:"), 400))
			talk._react("job", [])
			var _o6 = screen(talk)
			talk._react("report", [])
		var _o7 = screen(talk)
		var reportText = ui.textOutput.bbcode_text
		check(g.playerGang() == "" and af().hasIntroDone(gid) and !af().hasAssignment(), gid + ": reporting success makes the player eligible but does not join them")
		check(reportText.find("Introductory assignment complete.") != -1 and reportText.find("You are now eligible to join " + theNames[gid] + ".") != -1, gid + ": the report says so as plain information")
		check(talk.state == "initiation", gid + ": the leader offers membership: state " + talk.state)
		check(reportText.find(GangDialogue.initiationSpeech(gid)) != -1, gid + ": in the leader's voice")
		for commitment in codes[gid]:
			check(reportText.find(commitment) != -1, gid + ": the code says '" + commitment + "'")
		check(reportText.count("•") == 3, gid + ": exactly three commitments")
		var oathOptions = options()
		check(oathOptions.has("I agree") and oathOptions.has("Not yet"), gid + ": the player can agree or say Not yet")
		var afterLog = questLog()
		var afterSide = afterLog.substr(afterLog.find("Side tasks:"), afterLog.find("Completed tasks:") - afterLog.find("Side tasks:"))
		check(afterSide.find(title) == -1 and afterLog.substr(afterLog.find("Completed tasks:")).find(title) != -1, gid + ": after reporting it moves to the completed list")
		# rewards exactly once, across a load
		var standingAfterReport = g.getPersonal("pc", gid)
		var creditsAfterReport = thePlayer.getCredits()
		var savedAfter = JSON.parse(JSON.print(GM.GES.saveData())).result
		GM.GES.loadData(JSON.parse(JSON.print(savedAfter)).result)
		check(GangGameScript.reportAssignment().find("nothing to report") != -1 and g.getPersonal("pc", gid) == standingAfterReport and thePlayer.getCredits() == creditsAfterReport, gid + ": reporting again after a load pays nothing more")
		check(af().hasIntroDone(gid) and !af().hasAssignment(), gid + ": the eligibility survives the load")

		# ---- 5. Not yet, then agreeing, without doing the job again ----
		if(firstGang):
			talk._react("notyet", [gid])
			var _o8 = screen(talk)
			var delayedText = ui.textOutput.bbcode_text
			check(delayedText.find(GangDialogue.notYetSpeech(gid)) != -1 and g.playerGang() == "" and !af().hasAssignment() and af().hasIntroDone(gid), gid + ": 'Not yet' is answered, nothing is lost and no new job appears")
			firstGang = false
			var again = newScene([leader2])
			var againOptions = screen(again)
			check(againOptions.has("Ask about joining") and !againOptions.has("Hear what they want"), gid + ": back later the leader still has the offer")
			again._react("join", [])
			var joinAgain = screen(again)
			check(joinAgain.has("I agree") and !joinAgain.has("Hear what they want") and !af().hasAssignment(), gid + ": asking about joining goes straight to the code, not to another job")
			talk = again
		talk._react("doinitiate", [gid])
		var _o9 = screen(talk)
		var welcomeText = ui.textOutput.bbcode_text
		check(g.playerGang() == gid and g.isMember("pc", gid), gid + ": agreeing joins the player")
		var welcomeSplit = welcomeText.find("[color=green]Joined")
		check(welcomeSplit != -1 and welcomeText.substr(0, welcomeSplit).find(welcomes[gid]) != -1, gid + ": the leader welcomes them in their own voice: " + welcomeText.substr(0, 300))
		check(welcomeText.substr(0, welcomeSplit).find("Joined") == -1 and welcomeText.substr(0, welcomeSplit).find("Personal standing") == -1, gid + ": the welcome does not narrate the mechanics")
		check(welcomeText.find("Joined " + theNames[gid] + ".") != -1 and welcomeText.find("Personal standing: " + theNames[gid] + " +5") != -1, gid + ": the effects are listed separately: " + welcomeText.substr(welcomeSplit, 300))
		for otherGid in g.gangIDs():
			if(otherGid != gid and g.areEnemies(gid, otherGid)):
				check(welcomeText.find(theNames[otherGid] + " now regards you as a rival.") != -1, gid + ": the rival is named: " + theNames[otherGid])
		var standingNow = g.getPersonal("pc", gid)
		var savedMember = JSON.parse(JSON.print(GM.GES.saveData())).result
		GM.GES.loadData(JSON.parse(JSON.print(savedMember)).result)
		check(g.playerGang() == gid and g.getPersonal("pc", gid) == standingNow, gid + ": the membership and standing are the same after a load")
		var second = GangGameScript.initiate(gid)
		check(second.find("already") != -1 and g.getPersonal("pc", gid) == standingNow, gid + ": joining twice does nothing: " + second)
		var _left = GangGameScript.leave()
		check(g.playerGang() == "", "setup: left again")

	# ---- 6. Failed, lapsed and cancelled jobs leave the list ----
	cleanSlate("ironhand", leaders["ironhand"])
	var failTalk = newScene([leaders["ironhand"]])
	failTalk._react("join", [])
	failTalk._react("takeintro", ["ironhand"])
	var _f1 = screen(failTalk)
	failTalk._react("acceptjob", [])
	check(questLog().find("Ironhand Initiation") != -1, "a new accepted job is listed")
	main.currentDay += 4
	GangGameScript.checkAssignment()
	check(!af().hasAssignment(), "a job that ran out of time is gone")
	var logAfterFail = questLog()
	check(logAfterFail.substr(0, logAfterFail.find("Completed tasks:")).find("Initiation") == -1, "and is not in Side tasks after failing")
	cleanSlate("ironhand", leaders["ironhand"])
	var cancelTalk = newScene([leaders["ironhand"]])
	cancelTalk._react("join", [])
	cancelTalk._react("takeintro", ["ironhand"])
	var _c1 = screen(cancelTalk)
	cancelTalk._react("acceptjob", [])
	var cancelTarget = str(af().getAssignment()["target"])
	var _removed = g.removeMember(cancelTarget, {})
	GangGameScript.checkAssignment()
	var logAfterCancel = questLog()
	check(!af().hasAssignment() and logAfterCancel.substr(0, logAfterCancel.find("Completed tasks:")).find("Initiation") == -1, "a cancelled job (the target left the gang) is removed from Side tasks")
	# an offered job that was never accepted is not listed
	cleanSlate("ironhand", leaders["ironhand"])
	var offeredTalk = newScene([leaders["ironhand"]])
	offeredTalk._react("join", [])
	offeredTalk._react("takeintro", ["ironhand"])
	check(af().getAssignment()["state"] == "offered" and questLog().find("Ironhand Initiation") == -1, "a job that is only offered is not in the list yet")

	# ---- 7. Every way of beating the target counts, once ----
	var outcomes = ["pain", "lust", "submit", "npc_surrender"]
	for outcome in outcomes:
		cleanSlate("ironhand", leaders["ironhand"])
		var jobTalk = newScene([leaders["ironhand"]])
		jobTalk._react("join", [])
		jobTalk._react("takeintro", ["ironhand"])
		jobTalk._react("acceptjob", [])
		var victim = str(af().getAssignment()["target"])
		moveTo("hall_mainentrance")
		var _vp = placeAt(victim, "hall_mainentrance")
		var _bystander = 0
		match(outcome):
			"pain":
				module.onFightAftermath(null, "pc", victim, {"won": true, "how": "pain"})
			"lust":
				module.onFightAftermath(null, "pc", victim, {"won": true, "how": "lust"})
			"submit":
				module.onFightAftermath(null, "pc", victim, {"won": true, "how": "submit", "submitter": victim})
			"npc_surrender":
				IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": victim})
				var attack = null
				for interaction in IS.interactions:
					if(interaction.id == "GenericAttack" and !interaction.wasDeleted and interaction.getRoleID("reacter") == victim):
						attack = interaction
				check(attack != null, "setup: the player attacks them")
				if(attack != null):
					attack.init_do("surrender", {}, {})
					IS.stopInteraction(attack)
		check(af().getAssignment()["state"] == "ready", "target beaten by " + outcome + " advances the assignment")
		var creditsBefore = thePlayer.getCredits()
		var standingBefore = g.getPersonal("pc", "ironhand")
		module.onFightAftermath(null, "pc", victim, {"won": true, "how": outcome})
		GangGameScript.onFightResult("pc", victim)
		check(af().getAssignment()["state"] == "ready" and thePlayer.getCredits() == creditsBefore and g.getPersonal("pc", "ironhand") == standingBefore, outcome + ": counting it again changes nothing")
		jobTalk._react("report", [])
		var _s = screen(jobTalk)
		check(af().hasIntroDone("ironhand") and !af().hasAssignment() and g.getPersonal("pc", "ironhand") > standingBefore, outcome + ": completion is recorded once, on the report")
		endPlayerInteractions()

	# Things that do not count
	var negatives = ["player_surrenders", "abandoned", "someone_else", "unresolved", "player_loses"]
	for kind in negatives:
		cleanSlate("ironhand", leaders["ironhand"])
		var negTalk = newScene([leaders["ironhand"]])
		negTalk._react("join", [])
		negTalk._react("takeintro", ["ironhand"])
		negTalk._react("acceptjob", [])
		var victim2 = str(af().getAssignment()["target"])
		moveTo("hall_mainentrance")
		var _vp2 = placeAt(victim2, "hall_mainentrance")
		match(kind):
			"player_surrenders":
				IS.startInteraction("GenericAttack", {"starter": victim2, "reacter": "pc"})
				var attack2 = null
				for interaction2 in IS.interactions:
					if(interaction2.id == "GenericAttack" and !interaction2.wasDeleted and interaction2.getRoleID("starter") == victim2):
						attack2 = interaction2
				if(attack2 != null):
					attack2.init_do("surrender", {}, {})
					IS.stopInteraction(attack2)
			"abandoned":
				IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": victim2})
				endPlayerInteractions()
			"someone_else":
				var bystanders = []
				for id in inmateIDs:
					if(id != victim2 and id != "pc" and g.gangOf(id) != "ironhand" and bystanders.empty()):
						bystanders.append(id)
				module.onFightAftermath(null, bystanders[0], victim2, {"won": true, "how": "pain"})
			"unresolved":
				IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": victim2})
			"player_loses":
				module.onFightAftermath(FakeFight.new(), victim2, "pc", {"won": false, "how": "pain"})
		check(af().getAssignment()["state"] == "active", kind + ": does not count as defeating the target (state " + af().getAssignment()["state"] + ")")
		endPlayerInteractions()

	print("GangFlowBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

func cleanSlate(gid, leader):
	gs().data()["player"]["intro"].clear()
	gs().data()["player"]["left_day"] = -1
	gs().data()["player"]["left_from"] = ""
	gs().data()["player"]["last_job"] = {}
	gs().data()["assignment"] = {}
	gs().data()["cooldowns"].clear()
	if(gs().playerGang() != ""):
		var _l = gs().leave("pc", 50, {})
	var _p = gs().setPersonal("pc", gid, 0)
	rel().setFeeling(leader, "pc", "trust", 0)
	rel().setFeeling(leader, "pc", "respect", 0)
	rel().setFeeling(leader, "pc", "affection", 0)

func questLog() -> String:
	ui.clearButtons()
	ui.clearText()
	var scene = load("res://Scenes/QuestLogScene.gd").new()
	scene._run()
	return ui.textOutput.bbcode_text

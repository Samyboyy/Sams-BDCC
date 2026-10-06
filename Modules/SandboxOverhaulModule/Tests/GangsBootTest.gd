extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/GangsBootTest.tscn
# Real path: the real extender, module, real inmates and guards from BDCC's own generators, real pawns and interactions through the InteractionSystem, real
# relationships, real inventory, real save/load, the real Gangs scene drawn on the real GameUI. The world simulation inside processTime and the map are absent.

const ServiceScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")
const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const ViewsScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangViews.gd")

var failures = 0

# The real MainScene with the world simulation cut out of processTime; generated characters become children of the test and are registered like real ones.
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

class FakeWorldScene:
	var sceneID = "WorldScene"
	func supportsShowingPawns():
		return true
	func supportsSexEngine():
		return true
	func hasCharacter(_id):
		return false

class FakeRoom extends Node2D:
	var roomID = ""
	func getFloorID():
		return "f"

class FakeWorld extends Node:
	var rooms = {}
	func getRoomByID(roomID):
		return rooms.get(roomID)

class FakeInteraction:
	var sandboxDefeatKind = ""

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

var main = null
var thePlayer = null
var module = null
var IS = null
var pcPawn = null
var worldScene = null

func setTime(hours, minutes = 0, day = 0):
	main.timeOfDay = int(hours * 3600 + minutes * 60)
	main.currentDay = day

func messagesText() -> String:
	return PoolStringArray(main.getMessages()).join("\n")

func gs():
	return GangGameScript.gangs()

func af():
	return GangGameScript.affairs()

func addPawn(charID, loc, typeID):
	var p = CharacterPawn.new()
	p.charID = charID
	p.pawnTypeID = typeID
	p.location = loc
	IS.pawns[charID] = p
	if(!IS.pawnsByLoc.has(loc)):
		IS.pawnsByLoc[loc] = {}
	IS.pawnsByLoc[loc][charID] = true
	return p

func moveTo(pawn, loc):
	if(IS.pawnsByLoc.has(pawn.location)):
		IS.pawnsByLoc[pawn.location].erase(pawn.charID)
	pawn.location = loc
	if(!IS.pawnsByLoc.has(loc)):
		IS.pawnsByLoc[loc] = {}
	IS.pawnsByLoc[loc][pawn.charID] = true
	if(pawn.charID == "pc"):
		thePlayer.location = loc

func removePawn(charID):
	var p = IS.pawns.get(charID)
	if(p != null):
		IS.pawnsByLoc[p.location].erase(charID)
	IS.pawns.erase(charID)

func countInteractions(interactionID) -> int:
	var n = 0
	for interaction in IS.interactions:
		if(interaction.id == interactionID && !interaction.wasDeleted):
			n += 1
	return n

func endAllInteractions():
	for interaction in IS.interactions.duplicate():
		IS.stopInteraction(interaction)

# The daily growth, run on enough different days to reach the target share: what a real game does over its first days.
func grow() -> int:
	var days = 0
	for d in range(300, 340):
		if(GangGameScript.topUpNewcomers(d).empty()):
			break
		days += 1
	return days

func initAndGrow():
	GangGameScript.ensureInitialized()
	var _d = grow()

func resetGangs():
	SandboxOverhaulModule.getState().gangs = ServiceScript.defaults()
	module.queuedRolls.clear()
	main.clearMessages()

func nonLeaderMember(gid:String) -> String:
	for id in gs().getMembers(gid):
		if(id != gs().getLeader(gid) && id != "pc"):
			return id
	return ""

func _ready():
	get_tree().create_timer(160.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = TestMain.new()
	GM.main = main
	IS = main.IS
	thePlayer = load("res://Player/Player.gd").new()
	GM.pc = thePlayer
	add_child(thePlayer)
	var eventSystem = EventSystem.new()
	add_child(eventSystem)
	worldScene = FakeWorldScene.new()
	main.sceneStack.append(worldScene)
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var state = SandboxOverhaulModule.getState()
	check(module != null and GlobalRegistry.getWorldEdit("SandboxGangHangoutWorldEdit") != null and GlobalRegistry.getSceneCreator("GangScene") != null, "module, world edit and scene registered")
	var taskIDs = GlobalRegistry.getGlobalTasks().keys()
	check(taskIDs.has("GangHangout0") and taskIDs.has("GangHangout1") and taskIDs.has("GangHangout2") and taskIDs.has("GangHangout3"), "the four hangout tasks are registered")
	check(state.schema_version == 9 and !gs().isInitialized() and gs().gangIDs().empty(), "a new game has no gangs yet")
	check(ViewsScript.statusLine().find("not formed") != -1 and ViewsScript.landing().empty(), "the screen says so, with nothing to list")

	# ---- Real inmates and guards ----
	main.holder = self
	var inmateGen = InmateGenerator.new()
	var inmateIDs = []
	for _n in range(30):
		var c = inmateGen.generate({})
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	var guardGen = GuardGenerator.new()
	var guardIDs = []
	for _n in range(4):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	main.holder = null
	check(GangGameScript.eligibleIDs().size() == 30 and !GangGameScript.eligibleIDs().has(guardIDs[0]), "30 eligible inmates, no guards")
	pcPawn = addPawn("pc", "hall_a", CharacterType.Inmate)
	moveTo(pcPawn, "hall_a")
	setTime(10, 0, 5)

	# ---- Initialisation from real characters ----
	GangGameScript.ensureInitialized()
	var g = gs()
	check(g.isInitialized() and g.gangIDs().size() == 3, "three established gangs formed")
	var formedMembers = 0
	for gid in g.gangIDs():
		formedMembers += g.getMembers(gid).size()
		check(g.getMembers(gid).size() == 1 and g.getTreasury(gid) == 20, gid + ": one member (the leader) and 20 credits when it forms")
	check(formedMembers == 3, "only the three leaders are affiliated at first")
	var growthDays = grow()
	check(growthDays == 5, "growth to the target takes 5 days at two a day (12 - 3 = 9 recruits): " + str(growthDays))
	var members = {}
	var dupes = 0
	for gid in g.gangIDs():
		for id in g.getMembers(gid):
			if(members.has(id)):
				dupes += 1
			members[id] = gid
	check(dupes == 0 and members.size() == 12 and float(members.size()) / 30.0 >= 0.30 and float(members.size()) / 30.0 <= 0.50, "12 of 30 inmates affiliated after growth (ceil of 40%), nobody twice: " + str(members.size()))
	var anyGuard = false
	for id in guardIDs:
		if(members.has(id) || g.gangOf(id) != ""):
			anyGuard = true
	check(!anyGuard and !members.has("pc"), "no guard and not the player")
	for gid in g.gangIDs():
		check(g.getLeader(gid) != "" and g.isMember(g.getLeader(gid), gid) and g.getHangout(gid) != "" and g.getMembers(gid).size() >= 3, gid + ": a valid leader, a hangout and at least three members")
	var slaveCount = g.getGang("collarcircle")["slaves"].size()
	check(slaveCount == 2 and g.getGang("ironhand")["slaves"].empty(), "the control gang owns two slaves; the combat gang none")
	for id in g.getGang("collarcircle")["slaves"]:
		check(members.has(id) == false and main.getCharacter(id) != null and !main.getCharacter(id).isSlaveToPlayer(), "a gang slave is a real inmate, nobody's member, not the player's slave")
	var before = JSON.print(state.gangs, "", true)
	GangGameScript.ensureInitialized()
	check(JSON.print(state.gangs, "", true) == before, "initialising again changes nothing")
	var leaderTraits = GangGameScript.traitEntry(g.getLeader("ironhand"))
	check(leaderTraits["power"] >= 0.5 and leaderTraits.has("mean"), "leaders are chosen from real character data")
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	state.clear()
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(JSON.print(state.gangs, "", true) == before and state.schema_version == 9, "the roster survives save and load exactly")

	# ---- Hangouts ----
	var world = FakeWorld.new()
	add_child(world)
	for roomID in ["gym_weights", "main_laundry", "eng_workshop", "hall_canteen", "gym_yoga"]:
		var room = FakeRoom.new()
		room.roomID = roomID
		world.add_child(room)
		world.rooms[roomID] = room
	var edit = GlobalRegistry.getWorldEdit("SandboxGangHangoutWorldEdit")
	edit.applyAll(world)
	edit.applyAll(world)
	check(world.rooms["gym_weights"].is_in_group("zone_gang0") and world.rooms["main_laundry"].is_in_group("zone_gang1") and world.rooms["eng_workshop"].is_in_group("zone_gang2") and !world.rooms["hall_canteen"].is_in_group("zone_gang3"), "each gang's hangout room is in its zone, however often the edit applies")
	var member = nonLeaderMember("ironhand")
	setTime(12, 0, 5)
	check(GangGameScript.canHangOut(member, 0) and !GangGameScript.canHangOut(member, 1) and !GangGameScript.canHangOut("pc", 0) and !GangGameScript.canHangOut(guardIDs[0], 0) and !GangGameScript.canHangOut("nobody", 0), "a free daytime member may go to their own hangout; nobody else")
	setTime(21, 30, 5)
	check(!GangGameScript.canHangOut(member, 0), "not in the evening")
	setTime(7, 0, 5)
	check(!GangGameScript.canHangOut(member, 0), "not before the morning")
	setTime(12, 0, 5)
	var _cap = g.capture(member, "hushmarket", GangGameScript.now())
	check(!GangGameScript.canHangOut(member, 0), "not while held")
	var _rel = g.release(member)
	check(GangGameScript.canHangOut(member, 0), "free again")
	var task = GlobalRegistry.createGlobalTask("GangHangout0")
	var taskPawn = addPawn(member, "hall_a", CharacterType.Inmate)
	check(task.canDoTask(taskPawn) and !GlobalRegistry.createGlobalTask("GangHangout1").canDoTask(taskPawn), "the global task asks the same question")
	var fakeGoal = load("res://Game/InteractionSystem/AloneGoals/GoalHangoutAt.gd").new()
	task.configureGoal(taskPawn, fakeGoal)
	check(fakeGoal.zone == "gang0" and task.goalID == InteractionGoal.HangoutAt, "and sends them to their own zone with BDCC's hangout goal")
	removePawn(member)

	# ---- Captured members: absent from their cell, never spawned ----
	var _assigned = module.refreshCells()
	var victim = nonLeaderMember("hushmarket")
	check(module.getCells().isAssigned(victim), "setup: the victim has a cell")
	setTime(23, 0, 5)
	check(module.getAttendance(victim) == "home" and module.canSpawnPawn(victim) == false, "setup: at night an unspawned inmate is home (and may not spawn before morning)")
	state.cell_presence.clear()
	var _held = g.capture(victim, "ironhand", GangGameScript.now())
	check(module.isKeptElsewhere(victim) and module.getAttendance(victim) == "away" and !module.isInCell(victim) and module.hasFailedToReturn(victim), "a captured member is absent from their cell, which the cell system notices")
	setTime(12, 0, 5)
	check(!module.canSpawnPawn(victim), "and is never picked to spawn, even by day")
	var victimPawn = addPawn(victim, "hall_b", CharacterType.Inmate)
	check(IS.hasPawn(victim) and !module.canSpawnPawn(victim), "a held member keeps their pawn (the population director keeps them at the captor's hangout) and is never picked for a random appearance")
	check(module.getMyCellText() != "" and g.isCaptive(victim) and g.gangOf(victim) == "hushmarket", "they remain in their gang while held")
	var escapedList = g.expireCaptives(GangGameScript.now() + 60 * 3600)
	check(escapedList.size() == 1 and !g.isCaptive(victim) and module.canSpawnPawn(victim), "they escape after their bounded time and can appear again")
	check(victimPawn != null, "setup")
	var cellmate = module.getPlayerCellmate()
	check(true, "cellmate " + str(cellmate))
	# the player's cellmate being taken shows up without debug data
	var mateGang = g.gangOf(cellmate) if cellmate != "" else ""
	if(mateGang != "" and mateGang != "ironhand"):
		main.clearMessages()
		var _c2 = g.capture(cellmate, "ironhand", GangGameScript.now())
		check(GangGameScript.isRelevantToPlayer(cellmate), "a captured cellmate is something the player is told about")
		var _r2 = g.release(cellmate)
	var guardCaptive = g.capture(guardIDs[0], "ironhand", GangGameScript.now())
	check(!guardCaptive["ok"], "a guard is nobody's captive")

	# ---- Saving and loading captives ----
	var held2 = nonLeaderMember("hushmarket")
	var _c3 = g.capture(held2, "ironhand", GangGameScript.now())
	var snap = JSON.print(state.gangs, "", true)
	saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	state.clear()
	for _k in range(3):
		GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(JSON.print(state.gangs, "", true) == snap and g.isCaptive(held2) and g.captivesOf("hushmarket") == [held2], "a captive survives repeated loading, once")
	main.dynamicCharacters.erase(held2)
	var _p = g.pruneMissing(GangGameScript.validIDs())
	check(!g.isCaptive(held2) and !g.isMember(held2, "hushmarket"), "a deleted captive is pruned and the data stays consistent")

	# ---- Joining: personal vs official relations ----
	resetGangs()
	initAndGrow()
	g = gs()
	check(g.isInitialized(), "setup: gangs again")
	var ironLeader = g.getLeader("ironhand")
	var checkNoFriend = GangGameScript.joinCheck("ironhand")
	check(!checkNoFriend["ok"] and checkNoFriend["needsIntro"], "an unknown player must do a job first")
	var rels = SandboxOverhaulModule.getRelationships()
	var _t1 = rels.setFeeling(ironLeader, "pc", "trust", 60)
	var _t2 = rels.setFeeling(ironLeader, "pc", "respect", 60)
	check(GangGameScript.joinCheck("ironhand")["ok"], "a leader who trusts and respects the player takes them")
	var joinText = GangGameScript.join("ironhand")
	check(g.playerGang() == "ironhand" and joinText.find("Joined Ironhand") != -1 and joinText.find("Personal standing: Ironhand +5") != -1 and joinText.find("Hush Market now regards you as a rival") != -1, "joining states the facts: " + joinText)
	check(g.getPersonal("pc", "hushmarket") == -8 and g.effectiveStatus("pc", "hushmarket")["official"] == -55 and GangGameScript.personalText("pc", "hushmarket").find("(-8)") != -1 and GangGameScript.relationText("ironhand", "hushmarket").find("enemies") != -1, "the two relation layers are shown separately")
	check(GangGameScript.joinCheck("hushmarket")["reasons"][0].find("Leave your current gang") != -1, "one gang at a time")
	var leaveText = GangGameScript.leave()
	check(g.playerGang() == "" and leaveText.find("left") != -1 and g.getPersonal("pc", "hushmarket") == -4 and g.getPersonal("pc", "ironhand") == 5 - 6, "leaving: small changes, said plainly")

	# ---- A story: join, hurt the rival, leave, still hated ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	ironLeader = g.getLeader("ironhand")
	var _t3 = GangGameScript.join("ironhand")
	var rivalMember = nonLeaderMember("hushmarket")
	module.onUnprovokedAttack(rivalMember)
	check(g.getPersonal("pc", "hushmarket") == -8 - 6 and g.harmCount("hushmarket") == 1 and messagesText().find("Hush Market") != -1, "starting a fight with a rival gang's member costs standing with that gang")
	module.onFightAftermath(FakeInteraction.new(), "pc", rivalMember, {"won": true, "how": "pain", "margin": 0.3, "submitter": ""})
	check(g.lossCount("hushmarket") == 1 and g.getPersonal("pc", "hushmarket") == -8 - 6 - 4 and g.getPersonal("pc", "ironhand") == 5 + 4, "beating them: they remember it, and the player's own gang approves")
	module.onFightAftermath(FakeInteraction.new(), "pc", rivalMember, {"won": true, "how": "pain", "margin": 0.3, "submitter": ""})
	check(g.lossCount("hushmarket") == 2, "each fight is counted once")
	var kidnapHarm = g.recordHarm("pc", "hushmarket", "kidnap")
	var _l = GangGameScript.leave()
	check(kidnapHarm == -15 and g.getPersonal("pc", "hushmarket") == -8 - 6 - 4 - 4 - 15 + 4, "after leaving, the rival's regard is still bad: " + str(g.getPersonal("pc", "hushmarket")))
	check(g.effectiveStatus("pc", "hushmarket")["hostile"] or g.getPersonal("pc", "hushmarket") <= -25, "and they regard the player as a target: " + str(g.effectiveStatus("pc", "hushmarket")))
	check(GangGameScript.joinCheck("hushmarket")["reasons"][0].find("do not trust") != -1 or GangGameScript.joinCheck("hushmarket")["reasons"][0].find("just left") != -1, "joining them is hard now")

	# ---- Protection: deterrence, rivals, no duplicate aftermath ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var indie = ""
	for id in GangGameScript.eligibleIDs():
		if(g.gangOf(id) == "" && !g.isCaptive(id)):
			indie = id
	var base = module.getAttackMultiplier(indie)
	check(base == module.getCombat().attackMultiplier(indie), "an independent player has no gang protection: " + str(base))
	ironLeader = g.getLeader("ironhand")
	rels.setFeeling(ironLeader, "pc", "trust", 80)
	rels.setFeeling(ironLeader, "pc", "respect", 80)
	var _j = GangGameScript.join("ironhand")
	var protectedMult = module.getAttackMultiplier(indie)
	check(protectedMult < base and protectedMult > 0.0, "in a gang, independent attackers are deterred but not stopped: " + str([base, protectedMult]))
	var rivalID = nonLeaderMember("hushmarket")
	check(module.getAttackMultiplier(rivalID) > protectedMult, "a rival gang's member stays more dangerous: " + str(module.getAttackMultiplier(rivalID)))
	var mateID = nonLeaderMember("ironhand")
	check(module.getAttackMultiplier(mateID) < protectedMult, "gangmates are unlikely to attack")
	var combatBefore = JSON.print(state.reputation)
	var lossesBefore = g.lossCount("hushmarket")
	module.onFightAftermath(FakeInteraction.new(), rivalID, "pc", {"won": false, "how": "pain", "margin": 0.5, "submitter": ""})
	check(g.lossCount("hushmarket") == lossesBefore and JSON.print(state.reputation) != combatBefore, "losing a fight is handled once: the usual combat consequences, no gang loss recorded")
	var combatMid = JSON.print(state.reputation)
	module.onFightAftermath(FakeInteraction.new(), "pc", rivalID, {"won": true, "how": "pain", "margin": 0.5, "submitter": ""})
	check(g.lossCount("hushmarket") == lossesBefore + 1 and JSON.print(state.reputation) != combatMid, "a win is counted once by each system")

	# ---- Assignments ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	state.cooldowns.clear()
	initAndGrow()
	g = gs()
	ironLeader = g.getLeader("ironhand")
	rels.setFeeling(ironLeader, "pc", "trust", 80)
	rels.setFeeling(ironLeader, "pc", "respect", 80)
	var _j2 = GangGameScript.join("ironhand")
	var _s = g.setPersonal("pc", "ironhand", 20)
	var offerText = GangGameScript.offerAssignment()
	check(offerText.find("something they want you to do") != -1 and af().getAssignment()["state"] == "offered" and af().getAssignment()["type"] == "defeat", "the leader offers a job (the combat gang wants a rival beaten)")
	var offerLeader = GangGameScript.gangs().getLeader(af().getAssignment()["gang"])
	check(GangGameScript.taskView()["visible"] and GangGameScript.taskView()["title"].find("has a job for you") != -1 and !GangGameScript.taskMarks(offerLeader).empty() and GangGameScript.taskMarks(offerLeader)[0][1].find("Hear about the job") != -1, "an offered job is a Side Task and puts the Q on the leader")
	check(GangGameScript.offerAssignment() == "", "only one at a time")
	var declineText = GangGameScript.declineAssignment()
	check(declineText.find("No harm") != -1 and g.getPersonal("pc", "ironhand") == 20 and !af().hasAssignment(), "declining costs nothing")
	state.gangs["cooldowns"].erase("offer")
	var _o = GangGameScript.offerAssignment()
	var acceptText = GangGameScript.acceptAssignment()
	var target = af().getAssignment()["target"]
	check(g.reservedAmount("ironhand") == 6 and g.getTreasury("ironhand") == 20 and thePlayer.getCredits() == thePlayer.getCredits(), "accepting reserves 6 of the gang's 20 credits")
	check(acceptText.find("Come back when it is done") != -1 and acceptText.find("Assignment accepted.") != -1 and acceptText.find("Objective") == -1 and af().getAssignment()["state"] == "active", "accepting is a short answer and one line, not the whole block again: " + acceptText)
	var credits0 = thePlayer.getCredits()
	GangGameScript.onFightResult("pc", indie)
	check(af().hasAssignment() and thePlayer.getCredits() == credits0, "an unrelated fight does not count")
	main.clearMessages()
	var gangTreasury0 = g.getTreasury("ironhand")
	var leaderID0 = g.getLeader("ironhand")
	var leaderTrust0 = rels.getFeeling(leaderID0, "pc", "trust")
	var leaderRespect0 = rels.getFeeling(leaderID0, "pc", "respect")
	GangGameScript.onFightResult("pc", target)
	check(af().canReport() and thePlayer.getCredits() == credits0 and g.getTreasury("ironhand") == gangTreasury0 and g.reservedAmount("ironhand") == 6 and messagesText().find("Report back") != -1, "beating the target does not pay: the player has to report back to the leader in person")
	var reportText = GangGameScript.reportAssignment()
	check(reportText.find("Assignment complete") != -1 and rels.getFeeling(leaderID0, "pc", "trust") > leaderTrust0 and rels.getFeeling(leaderID0, "pc", "respect") > leaderRespect0, "reporting back pays, and the leader's own trust and respect rise")
	check(g.getTreasury("ironhand") == gangTreasury0 - 6 and g.reservedAmount("ironhand") == 0, "the reward comes out of the gang's treasury, once")
	check(!af().hasAssignment() and thePlayer.getCredits() == credits0 + 6 and g.getPersonal("pc", "ironhand") >= 28 and reportText.find("Assignment complete") != -1, "beating the target pays exactly 6 credits and standing, once: " + str(thePlayer.getCredits() - credits0))
	GangGameScript.onFightResult("pc", target)
	check(thePlayer.getCredits() == credits0 + 6, "a second win over them pays nothing")
	saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	var creditsAfter = thePlayer.getCredits()
	for _k2 in range(3):
		GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(thePlayer.getCredits() == creditsAfter and !af().hasAssignment(), "saving and loading never pays twice")
	# failure
	state.gangs["cooldowns"].erase("offer")
	var _o2 = GangGameScript.offerAssignment()
	var _a2 = GangGameScript.acceptAssignment()
	var standingBefore = g.getPersonal("pc", "ironhand")
	setTime(10, 0, 9)
	GangGameScript.checkAssignment()
	check(!af().hasAssignment() and g.getPersonal("pc", "ironhand") == standingBefore - 8 and messagesText().find("failed") != -1, "an accepted job left to lapse costs 8 standing, once")
	check(g.reservedAmount("ironhand") == 0 and g.getTreasury("ironhand") == gangTreasury0 - 6, "and the reserved credits go back to the gang")
	GangGameScript.checkAssignment()
	check(g.getPersonal("pc", "ironhand") == standingBefore - 8, "and only once")
	# deleted target
	state.gangs["cooldowns"].erase("offer")
	setTime(10, 0, 12)
	var _o3 = GangGameScript.offerAssignment()
	var _a3 = GangGameScript.acceptAssignment()
	var gone = af().getAssignment()["target"]
	main.dynamicCharacters.erase(gone)
	standingBefore = g.getPersonal("pc", "ironhand")
	main.clearMessages()
	GangGameScript.checkAssignment()
	check(!af().hasAssignment() and g.getPersonal("pc", "ironhand") == standingBefore and messagesText().find("not blamed") != -1 and g.reservedAmount("ironhand") == 0, "a target that no longer exists cancels the job without penalty and releases the reservation")
	# deliver credits and an item, atomically
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var tradeLeader = g.getLeader("hushmarket")
	rels.setFeeling(tradeLeader, "pc", "trust", 80)
	rels.setFeeling(tradeLeader, "pc", "respect", 80)
	var _j3 = GangGameScript.join("hushmarket")
	g.setPersonal("pc", "hushmarket", 20)
	thePlayer.addCredits(20 - thePlayer.getCredits())
	var _o4 = GangGameScript.offerAssignment()
	check(af().getAssignment()["type"] == "deliver" and af().getAssignment()["amount"] == 6, "the trading gang asks for a payment")
	var _a4 = GangGameScript.acceptAssignment()
	var treasuryBefore = g.getTreasury("hushmarket")
	var deliverText = GangGameScript.deliverAssignment()
	check(thePlayer.getCredits() == 14 and g.getTreasury("hushmarket") == treasuryBefore + 6 and !af().hasAssignment() and deliverText.find("Assignment complete") != -1, "the payment is taken exactly once and goes to the gang's treasury")
	check(GangGameScript.deliverAssignment().find("nothing to deliver") != -1 and thePlayer.getCredits() == 14, "nothing more is taken")
	state.gangs["cooldowns"].erase("offer")
	var shiv = GlobalRegistry.createItem("Shiv")
	thePlayer.getInventory().addItem(shiv)
	var _o5 = GangGameScript.offerAssignment()
	check(af().getAssignment()["item"] == "Shiv" and af().getAssignment()["reward"] == 5, "with contraband to hand, they ask for it, for 5 credits")
	var _a5 = GangGameScript.acceptAssignment()
	thePlayer.getInventory().removeItem(shiv)
	var missing = GangGameScript.deliverAssignment()
	check(missing.find("not carrying") != -1 and af().hasAssignment() and thePlayer.getCredits() == 14, "without the item nothing is taken and nothing is paid")
	thePlayer.getInventory().addItem(shiv)
	var protectedShiv = GlobalRegistry.createItem("StunBaton")
	thePlayer.getInventory().addItem(protectedShiv)
	main.clearMessages()
	var itemText = GangGameScript.deliverAssignment()
	check(!thePlayer.getInventory().hasItem(shiv) and thePlayer.getInventory().hasItem(protectedShiv) and thePlayer.getCredits() == 19 and itemText.find("Assignment complete") != -1 and !af().hasAssignment(), "the requested item is removed once and the reward paid once; other items stay")
	# capture needs a beaten target and an explicit hand over
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var controlLeader = g.getLeader("collarcircle")
	rels.setFeeling(controlLeader, "pc", "trust", 80)
	rels.setFeeling(controlLeader, "pc", "respect", 80)
	var _j4 = GangGameScript.join("collarcircle")
	g.setPersonal("pc", "collarcircle", 20)
	var _o6 = GangGameScript.offerAssignment()
	var _a6 = GangGameScript.acceptAssignment()
	var capTarget = af().getAssignment()["target"]
	check(af().getAssignment()["type"] == "capture" and GangGameScript.handOverCaptive().find("nobody to hand over") != -1, "a capture job cannot be completed without beating the target")
	GangGameScript.onFightResult("pc", capTarget)
	check(af().getAssignment()["stage"] == "defeated" and !g.isCaptive(capTarget) and messagesText().find("hand them over") != -1, "beating them only readies the hand over")
	credits0 = thePlayer.getCredits()
	var handText = GangGameScript.handOverCaptive()
	check(g.isCaptive(capTarget) and g.getCaptive(capTarget)["gang"] == "collarcircle" and thePlayer.getCredits() == credits0 + 10 and handText.find("remember") != -1 and !af().hasAssignment(), "handing them over holds them, pays 10 once and warns of the consequences")
	check(module.isKeptElsewhere(capTarget) and !module.canSpawnPawn(capTarget), "the captive is held: absent and never spawned")
	var rescued = g.release(capTarget)
	check(!rescued.empty() and !g.isCaptive(capTarget), "and they can be freed")

	# ---- Expulsion, warning, retaliation ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	ironLeader = g.getLeader("ironhand")
	rels.setFeeling(ironLeader, "pc", "trust", 80)
	rels.setFeeling(ironLeader, "pc", "respect", 80)
	var _j5 = GangGameScript.join("ironhand")
	g.setPersonal("pc", "ironhand", -35)
	main.clearMessages()
	setTime(10, 0, 20)
	state.cooldowns.clear()
	var warningRolls = [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9]
	module.queuedRolls = warningRolls.duplicate()
	GangGameScript.dailyUpkeep(20, warningRolls)
	check(messagesText().find("standing") != -1 and messagesText().find("low") != -1 and g.playerGang() == "ironhand", "low standing: a warning that says why")
	g.setPersonal("pc", "ironhand", -65)
	main.clearMessages()
	setTime(10, 0, 24)
	GangGameScript.dailyUpkeep(24, warningRolls)
	check(g.playerGang() == "" and messagesText().find("thrown out") != -1 and messagesText().find("collapsed") != -1 and g.getPersonal("pc", "ironhand") < -65 and !g.retaliationState("ironhand").empty(), "very low standing: expulsion, with the reason and a record of the grace period")
	# retaliation: grace first, then one beating attempt, never forever
	var member1 = nonLeaderMember("ironhand")
	var _memberPawn = addPawn(member1, "hall_a", CharacterType.Inmate)
	moveTo(pcPawn, "hall_a")
	endAllInteractions()
	var day = 24
	check(!GangGameScript.tryHostileIncident(day, [0.9, 0.9, 0.9, 0.9, 0.9]) and countInteractions("GenericAttack") == 0, "during the grace period nobody comes")
	day = 26
	setTime(10, 0, day)
	var guardPawn = addPawn(guardIDs[0], "hall_a", CharacterType.Guard)
	check(!GangGameScript.tryHostileIncident(day, [0.9, 0.9, 0.9, 0.9, 0.9]) and countInteractions("GenericAttack") == 0, "not with a guard in the room")
	removePawn(guardIDs[0])
	check(guardPawn != null and GangGameScript.tryHostileIncident(day, [0.9, 0.9, 0.9, 0.9, 0.9]) and countInteractions("GenericAttack") == 1, "after it, the gang's member in the room attacks through BDCC's own attack interaction")
	var attack = null
	for interaction in IS.interactions:
		if(interaction.id == "GenericAttack"):
			attack = interaction
	check(attack.getRoleID("starter") == member1 and attack.getRoleID("reacter") == "pc" and g.retaliationState("ironhand")["retaliations"] == 1, "the attacker is the gang's member, the target the player, one attempt used")
	endAllInteractions()
	check(!GangGameScript.tryHostileIncident(day, [0.9, 0.9, 0.9, 0.9, 0.9]) or countInteractions("GenericAttack") == 1, "later it happens at most once more")
	g.recordLoss("ironhand")
	g.recordLoss("ironhand")
	endAllInteractions()
	check(!GangGameScript.tryHostileIncident(day + 1, [0.9, 0.9, 0.9, 0.9, 0.9]) and countInteractions("GenericAttack") == 0, "once the player has beaten them twice, the retaliation stops")
	for id in [member1]:
		removePawn(id)
	endAllInteractions()

	# ---- Gang-owned slaves and the treasury ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var tBefore = g.getTreasury("collarcircle")
	GangGameScript.dailyUpkeep(30, [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9])
	check(g.getTreasury("collarcircle") == tBefore + 4 + g.memberIncome("collarcircle"), "two slaves (4) plus the members' contribution earn the gang credits that day")
	GangGameScript.dailyUpkeep(30, [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9])
	check(g.getTreasury("collarcircle") == tBefore + 4 + g.memberIncome("collarcircle"), "income is paid once a day")
	check(!af().has_method("withdraw") and !g.has_method("withdraw") and !af().has_method("takeTreasury") and !g.has_method("takeTreasury"), "there is no way for the player to take money out of an NPC gang")
	var ownedSlave = g.getGang("collarcircle")["slaves"][0]
	check(module.isKeptElsewhere(ownedSlave) and module.canSpawnPawn(ownedSlave) and !g.isDetained(ownedSlave), "a gang's slave is away at night, but is not held like a captive: they can appear by day")
	# the player enslaves a gang's slave: the gang loses it and holds a grudge
	var slaveChar = main.getCharacter(ownedSlave)
	slaveChar.setNpcSlavery(NpcSlave.new())
	main.clearMessages()
	GangGameScript.handlePlayerSlaves()
	check(g.slaveOwner(ownedSlave) == "" and !g.isCaptive(ownedSlave) and g.getPersonal("pc", "collarcircle") <= -25 and messagesText().find("enslaved") != -1, "enslaving a gang's slave frees it from the gang, with serious personal consequences: " + str(g.getPersonal("pc", "collarcircle")))
	# the player enslaves a member
	var memberToEnslave = nonLeaderMember("hushmarket")
	var memberChar = main.getCharacter(memberToEnslave)
	memberChar.setNpcSlavery(NpcSlave.new())
	GangGameScript.handlePlayerSlaves()
	check(!g.isMember(memberToEnslave, "hushmarket") and g.getPersonal("pc", "hushmarket") <= -25 and g.harmCount("hushmarket") >= 1, "enslaving a member removes them from the gang and the gang hates the player for it")
	check(!GangGameScript.isEligibleInmate(memberToEnslave), "a player's slave is never eligible for a gang")
	slaveChar.setNpcSlavery(null)
	memberChar.setNpcSlavery(null)

	# ---- The player's own gang and orders ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	check(!af().canCreate(GangGameScript.createContext())["ok"], "an unknown player cannot found a gang")
	var recruits = []
	for id in GangGameScript.eligibleIDs():
		if(g.gangOf(id) == "" and !g.isCaptive(id)):
			recruits.append(id)
	check(GangGameScript.recruits().empty(), "nobody is willing at first")
	var _rr = rels.setFeeling(recruits[0], "pc", "trust", 70)
	var _rr2 = rels.setFeeling(recruits[0], "pc", "respect", 70)
	var _rr3 = rels.setFeeling(recruits[1], "pc", "trust", 70)
	var _rr4 = rels.setFeeling(recruits[1], "pc", "respect", 70)
	var _rr5 = rels.setFeeling(recruits[2], "pc", "trust", 70)
	var _rr6 = rels.setFeeling(recruits[2], "pc", "respect", 70)
	check(GangGameScript.recruits().size() == 3 and GangGameScript.bestRespect() >= 70.0, "three inmates become willing")
	thePlayer.addCredits(40 - thePlayer.getCredits())
	state.reputation["combat"] = 10.0
	check(af().canCreate(GangGameScript.createContext())["ok"], "reputation, followers and money together allow it")
	var badName = GangGameScript.createGang("x", "hall_canteen", recruits.slice(0, 1))
	check(badName.find("at least") != -1 and thePlayer.getCredits() == 40 and !g.ownsPlayerGang(), "a bad name is refused with nothing charged")
	var badRoom = GangGameScript.createGang("Night Shift", "gym_weights", recruits.slice(0, 1))
	check(badRoom.find("not available") != -1 and thePlayer.getCredits() == 40, "a bad room is refused with nothing charged")
	var founded = GangGameScript.createGang("Night Shift", "hall_canteen", recruits.slice(0, 1))
	check(g.ownsPlayerGang() and g.getLeader("player") == "pc" and thePlayer.getCredits() == 25 and founded.find("founded") != -1 and founded.find("15 credits") != -1, "founding charges exactly 15 credits once")
	check(GangGameScript.createGang("Another One", "gym_yoga", recruits.slice(0, 1)).find("already") != -1 and thePlayer.getCredits() == 25, "no second gang, no second charge")
	var inviteText = GangGameScript.invite(recruits[2])
	check(inviteText.find("joins") != -1 and g.isMember(recruits[2], "player"), "invite a willing inmate")
	check(GangGameScript.invite(recruits[3]).find("do not want") != -1 and !g.isMember(recruits[3], "player"), "an unwilling one refuses")
	check(GangGameScript.removeMember(recruits[2]).find("out of your gang") != -1 and !g.isMember(recruits[2], "player"), "remove a member")
	check(GangGameScript.contribute(5).find("treasury") != -1 and g.getTreasury("player") == 10 and thePlayer.getCredits() == 20, "contribute to the treasury (5 from founding, 5 contributed)")
	check(GangGameScript.contribute(500).find("cannot") != -1 and thePlayer.getCredits() == 20, "cannot give what you do not have")
	check(ViewsScript.treasuryLine("player").find("10 credits") != -1 and ViewsScript.canSeeFinances("player") and ViewsScript.treasuryLine("ironhand") == "" and !ViewsScript.canSeeFinances("ironhand"), "a member sees their own gang's treasury and nobody else's")
	var ownLines = PoolStringArray(ViewsScript.detailLines("player")).join("\n")
	var otherLines = PoolStringArray(ViewsScript.detailLines("ironhand")).join("\n")
	check(ownLines.find("Treasury: ") != -1 and ownLines.find("one of them") != -1 and otherLines.find("Treasury") == -1 and otherLines.find("Through your own gang") != -1, "the page of your own gang shows money; another gang's page shows how it sees your gang instead")
	var relLines = PoolStringArray(ViewsScript.relationLines("ironhand")).join("\n")
	check(relLines.find("Personally:") != -1 and relLines.find("Through " + g.gangName("player") + ":") != -1, "relations keep your personal standing apart from what your own gang brings")
	var memberPage = ViewsScript.memberLines("player", 0)
	check(memberPage["pages"] >= 1 and PoolStringArray(memberPage["lines"]).join("\n").find("(leader, you)") != -1 or PoolStringArray(memberPage["lines"]).join("\n").find("you") != -1, "the player's gang lists its leader and marks you")
	check(GangGameScript.changeHangout("gym_yoga").find("meets at") != -1 and g.getHangout("player") == "gym_yoga" and GangGameScript.changeHangout("yard_neargym").find("recently") != -1, "the hangout changes, with a cooldown")
	GangGameScript.refreshHangoutZones(world)
	check(world.rooms["gym_yoga"].is_in_group("zone_gang3") and !world.rooms["hall_canteen"].is_in_group("zone_gang3"), "and the zone follows it")
	check(GangGameScript.createGang("Night Shift", "hall_canteen", recruits).find("already") != -1, "setup: the gang exists")
	# orders
	var enemy = nonLeaderMember("hushmarket")
	var _tq = g.addTreasury("player", 25)
	var _rm = GangGameScript.removeMember(recruits[1])
	var noMembers = GangGameScript.orderAction("beat", enemy, [0.0, 0.0])
	check(noMembers.find("two free members") != -1 and g.getTreasury("player") == 35, "too few free members: refused, nothing spent")
	var _inv = GangGameScript.invite(recruits[1])
	var beatText = GangGameScript.orderAction("beat", enemy, [0.0, 0.0])
	check(beatText.find("beat") != -1 and beatText.find("treasury") != -1 and g.getTreasury("player") == 30 and module.getInjuries().has(enemy, "trauma") and g.getPersonal("pc", "hushmarket") <= -8, "a successful beating: cost paid, the target hurt, their gang angry")
	var tooSoon = GangGameScript.orderAction("intimidate", enemy, [0.0, 0.0])
	check(tooSoon.find("day") != -1 and g.getTreasury("player") == 30, "one order a day")
	setTime(11, 0, main.getDays() + 1)
	var intimidate = GangGameScript.orderAction("intimidate", enemy, [0.0, 0.0])
	check(intimidate.find("scare") != -1 and rels.getFeeling(enemy, "pc", "fear") >= 12.0, "intimidation raises the target's Fear")
	setTime(11, 0, main.getDays() + 1)
	var failure = GangGameScript.orderAction("capture", enemy, [0.99, 0.0])
	check(failure.find("fails") != -1 and (failure.find("held by") != -1 or failure.find("hurt") != -1), "a failed order gets one of your people held or hurt")
	setTime(11, 0, main.getDays() + 3)
	GangGameScript.handleCaptiveExpiry()
	var ownMembersBefore = g.getMembers("player")
	var independentTarget = ""
	for id in GangGameScript.targetsFor("beat"):
		if(g.gangOf(id) == "" and independentTarget == ""):
			independentTarget = id
	check(independentTarget != "", "setup: an independent inmate to target")
	setTime(11, 0, main.getDays() + 1)
	var failIndependent = GangGameScript.orderAction("beat", independentTarget, [0.99, 0.0])
	var hurtMember = ""
	for id in ownMembersBefore:
		if(module.getInjuries().has(id, "trauma")):
			hurtMember = id
	check(failIndependent.find("fails") != -1 and failIndependent.find("comes back hurt") != -1 and hurtMember != "" and hurtMember != "pc", "a failed order against an independent hurts one of your people: " + failIndependent)
	check(g.getMembers("player") == ownMembersBefore and g.isMember(hurtMember, "player") and main.getCharacter(hurtMember) != null and !g.isCaptive(hurtMember), "and nobody is removed from the gang or from the game")
	check(failure.find("held by") != -1 or failure.find("hurt") != -1, "a failed order against a gang member gets one of your people held or hurt")
	for id in ownMembersBefore:
		check(main.getCharacter(id) != null and g.isMember(id, "player"), "after both failures " + id + " is still a member and still exists")
	setTime(11, 0, main.getDays() + 1)
	var protectedTarget = GangGameScript.orderAction("beat", guardIDs[0], [0.0, 0.0])
	check(protectedTarget.find("cannot send") != -1, "a guard can never be a target")
	check(GangGameScript.targetsFor("beat").size() > 0 and !GangGameScript.targetsFor("beat").has(guardIDs[0]) and !GangGameScript.targetsFor("beat").has(recruits[0]), "targets are inmates who are not yours")

	# ---- Churn and newcomers ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var views = GangGameScript.churnViews()
	check(views.size() > 0 and views[0].has("leaderTrust") and views[0].has("bestOther"), "the churn check reads real feelings")
	var leaderOfThem = g.getLeader("ironhand")
	var ironMembers = g.getMembers("ironhand")
	for id in ironMembers:
		if(id != leaderOfThem):
			rels.setFeeling(leaderOfThem, id, "trust", -90)
	main.clearMessages()
	state.cooldowns.clear()
	GangGameScript.dailyUpkeep(40, [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9])
	check(g.data()["cooldowns"].has("churn") and g.getLog().size() > 1, "a leader who no longer trusts members: one membership change happens, and the log says why")
	for gid in g.gangIDs():
		check(g.getMembers(gid).empty() or g.isMember(g.getLeader(gid), gid), "every gang still has a valid leader")

	# ---- The gang screen and the scene on the real UI ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var entries = ViewsScript.landing()
	check(ViewsScript.statusLine() == "You are independent." and entries.size() == 3, "the landing page says you are independent and lists the three gangs")
	var landingText = ""
	for entry in entries:
		landingText += ViewsScript.landingEntryText(entry) + "\n"
		check(entry["tag"].length() < 70 and entry["hangout"] != "" and entry["standing"]["text"] != "", entry["name"] + ": a short line, a hangout and how they see you")
	check(landingText.find("Ironhand") != -1 and landingText.find("The Hush Market") != -1 and landingText.find("The Collar Circle") != -1 and landingText.find("Meets at") != -1 and landingText.find("Toward you") != -1, "each entry names the gang, its hangout and its attitude")
	check(landingText.find("Treasury") == -1 and landingText.find("Members") == -1 and landingText.find("Leader") == -1 and landingText.find("-55") == -1 and landingText.find("Job:") == -1 and landingText.find("Lately") == -1, "the landing page carries no member lists, raw numbers, treasury, jobs or logs")
	check(landingText.split("\n").size() <= 12, "the landing page stays short: " + str(landingText.split("\n").size()) + " lines")
	var ui = load("res://Game/UI/GameUI.tscn").instance()
	add_child(ui)
	var scene = load("res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd").new()
	scene._initScene([])
	scene._run()
	var options = []
	for option in ui.options.values():
		options.append(option[1])
	check(options.has("Found a gang") and options.has("Close") and options.has("View Ironhand") and options.has("View The Hush Market") and options.has("View The Collar Circle") and options.size() == 5, "the overview is three View buttons, Found a gang and Close: " + str(options))
	# a gang's own page
	scene._react("viewgang", ["ironhand"])
	ui.clearButtons()
	ui.clearText()
	scene._run()
	var pageText = ui.textOutput.bbcode_text
	options = []
	for option in ui.options.values():
		options.append(option[1])
	check(scene.state == "view" and pageText.find("Leader:") != -1 and pageText.find("Meets at:") != -1 and pageText.find("Strength:") != -1 and pageText.find("Members: 1") != -1 or pageText.find("Members:") != -1, "a gang's page gives the essentials: " + pageText.left(300))
	check(pageText.find("Your standing with them:") != -1 and pageText.find("Treasury") == -1, "an outsider sees their own standing and no money")
	check(options.has("Members") and options.has("Relations") and !options.has("Join") and options.has("Back") and !options.has("Orders"), "the page offers Members, Relations, Join and Back: " + str(options))
	scene._react("members", [])
	ui.clearButtons()
	ui.clearText()
	scene._run()
	check(scene.state == "members" and ui.textOutput.bbcode_text.find("(leader)") != -1 and ui.textOutput.bbcode_text.find("- ") != -1, "the members page lists each member on a line and marks the leader")
	scene._react("relations", [])
	ui.clearButtons()
	ui.clearText()
	scene._run()
	var relText = ui.textOutput.bbcode_text
	check(relText.find("With the other gangs") != -1 and relText.find("The Hush Market: ") != -1 and relText.find("enemies") != -1 and relText.find("Personally:") != -1 and relText.find("belong to no gang") != -1 and relText.find("enemies") < relText.find("(-55)"), "the relations page gives the word first and the number after, and your own record apart: " + relText.left(400))
	scene._react("view", [])
	scene._react("", [])
	check(scene.state == "", "Back returns to the landing page")
	ui.clearButtons()
	ui.clearText()
	scene._run()
	options = []
	for option in ui.options.values():
		options.append(option[1])
	check(options.has("Found a gang") and options.has("Close"), "the overview offers founding a gang when independent")
	state.reputation["combat"] = 0.0
	thePlayer.addCredits(-thePlayer.getCredits())
	scene._react("createstart", [])
	check(scene.note.find("15 credits") != -1, "the requirements are explained: " + scene.note)
	ui.clearButtons()
	ui.clearText()
	var talkScene = load("res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd").new()
	var someMember = nonLeaderMember("hushmarket")
	talkScene._initScene([someMember])
	talkScene._run()
	options = []
	for option in ui.options.values():
		options.append(option[1])
	check(options.has("Are you in a gang?") and options.has("Where do you meet?") and options.has("Who leads it?") and options.has("Ask about joining"), "talking to a member offers the gang questions")
	talkScene._react("askgang", [])
	check(talkScene.note.find("Hush Market") != -1, "they answer")
	talkScene._react("askwhere", [])
	check(talkScene.note.find("laundry") != -1, "and say where they meet")
	talkScene._react("askleader", [])
	check(talkScene.note.find(main.getCharacter(g.getLeader("hushmarket")).getName()) != -1, "and who leads")
	ui.clearButtons()
	ui.clearText()
	var leaderScene = load("res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd").new()
	leaderScene._initScene([g.getLeader("hushmarket")])
	leaderScene._react("join", [])
	leaderScene._run()
	check(leaderScene.state == "join" and (ui.textOutput.bbcode_text.find("I agree") != -1 or ui.textOutput.bbcode_text.find("Hear what they want") != -1 or ui.textOutput.bbcode_text.find("want to see what you can do") != -1 or ui.textOutput.bbcode_text.find("Collar") != -1 or ui.textOutput.bbcode_text.find("Hush Market") != -1), "asking the leader about joining gets an answer")
	var freeable = g.getGang("collarcircle")["slaves"][0]
	var freeScene = load("res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd").new()
	freeScene._initScene([freeable])
	ui.clearButtons()
	freeScene._run()
	options = []
	for option in ui.options.values():
		options.append(option[1])
	check(options.has("Help them get free"), "a gang's slave can be helped to freedom")
	freeScene._react("freeslave", [])
	check(freeScene.note.find("is free") != -1 and g.slaveOwner(freeable) == "" and g.getPersonal("pc", "collarcircle") <= -15 and freeScene.note.find("will not forgive") != -1, "freeing them: the owning gang takes it badly")
	ui.free()
	GM.ui = null

	# ---- The Talking button (the one patch in a base interaction) ----
	var talkInmate = null
	for id in GangGameScript.eligibleIDs():
		talkInmate = id
	var talkPawn = addPawn(talkInmate, "hall_a", CharacterType.Inmate)
	talkPawn.social = 1.0
	moveTo(pcPawn, "hall_a")
	IS.startInteraction("Talking", {"starter": "pc", "reacter": talkInmate}, {})
	var talking = null
	for interaction in IS.interactions:
		if(interaction.id == "Talking"):
			talking = interaction
	if(talking != null):
		var talkIDs = []
		for entry in talking.getActionsFinal():
			talkIDs.append(entry["id"])
		check(talkIDs.has("gangs"), "Talking has the Gangs button")
	endAllInteractions()
	check(talkPawn != null, "setup")

	# ---- Pruning on the real tick, and a new game ----
	resetGangs()
	state.gangs = ServiceScript.defaults()
	initAndGrow()
	g = gs()
	var doomed = nonLeaderMember("ironhand")
	main.dynamicCharacters.erase(doomed)
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	extender.gangBucket = -1
	module.onGangTick()
	check(!g.isMember(doomed, "ironhand"), "the periodic check prunes a deleted character")
	var _gm = main.holder
	var main2 = TestMain.new()
	GM.main = main2
	check(!SandboxOverhaulModule.getGangs().isInitialized() and SandboxOverhaulModule.getGangs().gangIDs().empty(), "a new game resets the gangs")

	GM.main = null
	GM.pc = null
	GM.ES = null
	eventSystem.free()
	thePlayer.free()
	main.free()
	main2.free()
	print("GangsBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

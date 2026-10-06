extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/OwnershipClaimsBootTest.tscn
# Protection dialogue, exactly one owner, ownership disputes, remote owner defence, unified task victory and the Q badge.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")
const DirectorScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")
const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var failures = 0

class FakeWorldScene:
	var sceneID = "WorldScene"
	func supportsShowingPawns():
		return true
	func supportsSexEngine():
		return true
	func hasCharacter(_id):
		return false
	func isSpyingOnInteractionsWith(_id):
		return false
	func resolveCustomCharacterName(_id):
		return null

class FakeSceneRef:
	var sceneTag = ""

class FakeFight:
	var sandboxDefeatKind = ""

class TestMain extends "res://Game/MainScene.gd":
	var holder = null
	var counter = 0
	var sceneCalls = []
	func runScene(id, _args = [], _parentSceneUniqueID = -1, _tag:String = ""):
		sceneCalls.append([id, _args]) # scenes are only recorded here: the test opens them itself
		return FakeSceneRef.new()
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

func svc():
	return module.getOwnership()

func rel():
	return module.getRelationships()

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func setClock(hour, minute, day):
	main.timeOfDay = int(hour * 3600 + minute * 60)
	main.currentDay = day

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
		var before = main.timeOfDay
		main.timeOfDay += slice
		if(main.timeOfDay >= 86400):
			main.timeOfDay -= 86400
		if(before < 6 * 3600 and main.timeOfDay >= 6 * 3600 and !(before > 20 * 3600)):
			main.currentDay += 1
		IS.processTime(slice)
		endPlayerInteractions()
		module.onPopulationTick()
		module.onOwnershipTick()

# Runs time forward to a clock time on the current day number rules (day rolls at 06:00) in two-minute steps.
func advanceTo(hour, minute):
	var target = int(hour * 3600 + minute * 60)
	var guard = 0
	while(main.timeOfDay != target and guard < 800):
		advance(120)
		guard += 1

func tick():
	extender.ownershipBucket = -1
	module.onOwnershipTick(true)

func pawnLoc(id):
	var pawn = IS.getPawn(id)
	return pawn.getLocation() if pawn != null else "<none>"

func messageCount(fragment):
	var count = 0
	for line in main.getMessages():
		if(str(line).find(fragment) != -1):
			count += 1
	return count

func options():
	var result = {}
	for option in ui.options.values():
		result[option[1]] = {"enabled": option[0], "tooltip": option[2]}
	return result

func questLog() -> String:
	ui.clearButtons()
	ui.clearText()
	var scene = load("res://Scenes/QuestLogScene.gd").new()
	scene._run()
	return ui.textOutput.bbcode_text

func sideTasks() -> String:
	var text = questLog()
	return text.substr(text.find("Side tasks:"), text.find("Completed tasks:") - text.find("Side tasks:"))

func saveAndLoad():
	var savedIS = JSON.print(IS.saveData())
	var savedExt = JSON.print(GM.GES.saveData())
	IS.clearAll()
	module.getState().clear()
	IS.loadData(JSON.parse(savedIS).result)
	GM.GES.loadData(JSON.parse(savedExt).result)
	IS.updatePCLocation()

# A runner for an owner event, started the way the game does it, with the owner standing where the player is.
func ownerEvent(eventArgs, ownerID):
	var pawn = IS.getPawn(ownerID)
	if(pawn != null):
		pawn.setLocation(thePlayer.location)
	var runner = NpcOwnerEventRunner.new()
	runner.setOwnerID(ownerID)
	runner.runEvent("SandboxOwnerOps", eventArgs)
	runner.run()
	return runner

func press(runner, action):
	for button in runner.getFinalActions():
		if(button.size() > 2 and button[2] == action):
			var _result = runner.doAction(button)
			if(!runner.shouldEnd()):
				runner.run()
			return true
	return false

func buttonNames(runner) -> Array:
	var names = []
	for button in runner.getFinalActions():
		names.append(str(button[0]) + ("" if button.size() > 2 else " (off)"))
	return names

func boost(ownerID, trust, respect, affection, fear = 0.0):
	var _a = rel().setFeeling(ownerID, "pc", "trust", trust)
	var _b = rel().setFeeling(ownerID, "pc", "respect", respect)
	var _c = rel().setFeeling(ownerID, "pc", "affection", affection)
	var _d = rel().setFeeling(ownerID, "pc", "fear", fear)

func pickOwner(excluded, allowGang = false):
	var best = ""
	var bestScore = -99.0
	for id in inmateIDs:
		if(excluded.has(id) or (!allowGang and module.getGangs().gangOf(id) != "")):
			continue
		boost(id, 60.0, 70.0, 40.0)
		var decision = OwnershipGameScript.protectionDecision(id)
		if(decision["score"] > bestScore):
			bestScore = decision["score"]
			best = id
	return best

func becomeOwnedBy(ownerID, _day = 0):
	svc().data()["last_release"] = {}
	boost(ownerID, 60.0, 70.0, 40.0)
	var _ok = OwnershipGameScript.startVoluntary(ownerID)
	return svc().isOwner(ownerID)

func _ready():
	get_tree().create_timer(280.0).connect("timeout", get_tree(), "quit", [2])
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")
	main = TestMain.new()
	GM.main = main
	main.sceneStack.append(FakeWorldScene.new())
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
	var qs = QuestSystem.new()
	add_child(qs)
	var inmateGen = InmateGenerator.new()
	for n in range(30):
		var c = inmateGen.generate({})
		c.setFlag(CharacterFlag.InmateType, InmateType.General if n < 14 else (InmateType.HighSec if n < 22 else InmateType.SexDeviant))
		main.addDynamicCharacterToPool(c.getID(), CharacterPool.Inmates)
		inmateIDs.append(c.getID())
	inmateIDs.sort()
	var guardGen = GuardGenerator.new()
	for _n in range(4):
		var gc = guardGen.generate({})
		main.addDynamicCharacterToPool(gc.getID(), CharacterPool.Guards)
		guardIDs.append(gc.getID())
	thePlayer.inmateType = InmateType.General
	thePlayer.addCredits(40 - thePlayer.getCredits())
	GangGameScript.ensureInitialized()
	for growDay in range(300, 340):
		if(GangGameScript.topUpNewcomers(growDay).empty()):
			break
	var DAY = 60
	moveTo("yard_deadend2")
	setClock(9, 0, DAY)
	GlobalRegistry.getWorldEdit("SandboxPopulationBootstrapWorldEdit").apply(world)
	tick()
	check(!svc().hasOwner() and svc().slaveIDs().empty(), "setup: the player is owned by nobody and owns nobody")

	var eventSystem = EventSystem.new()
	add_child(eventSystem)
	var _tb = DirectorScript.tick(module, extender.director, true)
	IS.updatePCLocation()
	DAY = 70
	setClock(10, 0, DAY)
	var cands = []
	for id in inmateIDs:
		if(module.getGangs().gangOf(id) == "" and module.homeRoomOf(id) != "" and IS.hasPawn(id)):
			cands.append(id)
	check(cands.size() >= 10, "setup: ordinary inmates: " + str(cands.size()))
	var gangIDs = module.getGangs().gangIDs()
	check(gangIDs.size() == 3, "setup: three gangs")
	var playerRoom = "hall_canteen"

	# ============ 1. The protection dialogue: the candidate speaks, no internal errors ============
	for id0 in inmateIDs:
		for axis in ["trust", "respect", "affection", "fear", "desire"]:
			rel().setFeeling(id0, "pc", axis, 0.0)
	var capable = ""
	var weak = ""
	var submissive = ""
	var hostileGangMember = ""
	for id1 in cands:
		var f1 = OwnershipGameScript.candidateFacts(id1)
		if(capable == "" and f1["injury"] == 0 and OwnershipScript.protectorCapability(f1) >= OwnershipScript.CAPABLE_AT and f1["subby"] < 0.45):
			capable = id1
		elif(weak == "" and OwnershipScript.protectorCapability(f1) < OwnershipScript.CAPABLE_AT and f1["subby"] < 0.4):
			weak = id1
	for id2 in cands:
		if(id2 != capable and id2 != weak and submissive == ""):
			submissive = id2
	for gid in gangIDs:
		for id3 in module.getGangs().getMembers(gid):
			if(id3 != module.getGangs().getLeader(gid) and id3 != "pc" and hostileGangMember == "" and IS.hasPawn(id3)):
				hostileGangMember = id3
	check(capable != "" and submissive != "", "setup: a capable candidate and a temperament case")
	rel().setFeeling(capable, "pc", "respect", 60.0)
	rel().setFeeling(capable, "pc", "trust", 30.0)
	var okScene = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", ["protection", capable])
	show(okScene)
	check(shownText().find("!Error") == -1 and enabledButtons() == ["Agree", "Not now"] and shownText().find("Style:") != -1, "a capable, willing candidate: terms and Agree, no error text")
	if(weak != ""):
		rel().setFeeling(weak, "pc", "respect", 60.0)
		var weakScene = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", ["protection", weak])
		show(weakScene)
		check(shownText().find("!Error") == -1 and shownText().find("I'm not strong enough to keep anyone off you.") != -1 and enabledButtons() == ["Back"], "physical weakness: they say so in their own words")
	GM.main.getCharacter(submissive).getPersonality().setStat(PersonalityStat.Subby, 0.9)
	rel().setFeeling(submissive, "pc", "respect", 60.0)
	var subScene = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", ["protection", submissive])
	show(subScene)
	check(shownText().find("!Error") == -1 and shownText().find("I'd rather be the one receiving protection.") != -1, "temperament: they would rather be protected")
	if(hostileGangMember != ""):
		var hostileGid = module.getGangs().gangOf(hostileGangMember)
		var _p = module.getGangs().setPersonal("pc", hostileGid, -100)
		rel().setFeeling(hostileGangMember, "pc", "respect", 60.0)
		GM.main.getCharacter(hostileGangMember).getPersonality().setStat(PersonalityStat.Subby, -0.5)
		var hostileScene = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", ["protection", hostileGangMember])
		show(hostileScene)
		check(shownText().find("!Error") == -1 and shownText().find("My gang wouldn't accept that while you stand with our enemies.") != -1 and shownText().find("standing") != -1, "a hostile gang: their gang would not accept it, and the direction is given")
		var _q = module.getGangs().setPersonal("pc", hostileGid, 0)
	saveAndLoadAll()
	show(subScene)
	check(shownText().find("!Error") == -1 and shownText().find("I'd rather be the one receiving protection.") != -1, "the same refusal after saving and loading")

	# ============ 2. Exactly one owner, by every route ============
	var O1 = capable
	check(OwnershipGameScript.startVoluntary(O1) and OwnershipGameScript.ownerIDs() == [O1], "setup: the player is owned by one inmate")
	var asked = OwnershipGameScript.canAskProtection(cands[3])
	check(asked["show"] and !asked["ok"] and asked["reason"].find("already have an owner") != -1, "asking somebody else for protection says you already have an owner")
	var refusalWhileOwned = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipScene.gd", ["protection", cands[3]])
	show(refusalWhileOwned)
	check(shownText().find("!Error") == -1 and shownText().find("already have an owner") != -1 and enabledButtons() == ["Back"], "and the screen says so, with no error")
	var rivals = []
	for id4 in cands:
		if(id4 != O1 and rivals.size() < 6):
			rivals.append(id4)
	# routes into a second owner: the console/debug conversion, the ambush, an old event: all are startSpecialRelantionship
	module.queuedRolls = [0.0]
	GM.main.RS.startSpecialRelantionship("SoftSlavery", rivals[0])
	check(OwnershipGameScript.ownerIDs().size() == 1, "a debug or ambush conversion cannot add a second owner")
	check(svc().data()["disputes"].has(rivals[0]) or svc().data()["last_dispute"] >= DAY - 1, "it became a dispute, recorded once")
	# the talk options go through the dispute scene
	var talkRival = talkTo(rivals[1])
	talkRival.setState("npcEnslaveOffer", "reacter")
	var beforeScenes = sceneCountOf("OwnershipDisputeScene")
	talkRival.setState("playerAgreedToBeEnslaved", "starter")
	check(pressAction(talkRival, "continue"), "the talk's last step is pressed")
	check(sceneCountOf("OwnershipDisputeScene") == beforeScenes + 1 and OwnershipGameScript.ownerIDs().size() == 1, "the talk option opens the ownership dispute and never adds a second owner")
	endAllInteractionsOf(rivals[1])

	# ============ 3. Two-owner saves are repaired the same way every time ============
	var savedRS = GM.main.RS.saveData()
	var twin = rivals[2]
	var twice = JSON.parse(JSON.print(savedRS)).result
	var injected = false
	for entry in twice["special"].duplicate():
		if(str(entry.get("id", "")) == "SoftSlavery" and str(entry.get("charID", "")) == O1):
			var copy = JSON.parse(JSON.print(entry)).result
			copy["charID"] = twin
			twice["special"].append(copy)
			injected = true
	check(injected, "setup: a save with two owners")
	var messagesBefore = messageCount("Conflicting ownership records were repaired")
	GM.main.RS.loadData(twice)
	check(OwnershipGameScript.ownerIDs().size() == 2, "setup: loaded with two owners")
	OwnershipGameScript.reconcile()
	check(OwnershipGameScript.ownerIDs() == [O1] and svc().ownerID() == O1, "the owner recorded by the module's state stays the owner")
	check(!GM.main.RS.hasSpecialRelationship(twin) and GM.main.getCharacter(twin) != null, "the other loses the status only: the character and everything else stays")
	check(messageCount("Conflicting ownership records were repaired") == messagesBefore + 1, "and the player is told once")
	OwnershipGameScript.reconcile()
	check(messageCount("Conflicting ownership records were repaired") == messagesBefore + 1, "never twice")
	# with no record at all the lowest character id stays
	var lowest = O1 if O1 < twin else twin
	var other = twin if lowest == O1 else O1
	svc().data()["owner"] = {}
	var twice2 = JSON.parse(JSON.print(savedRS)).result
	for entry2 in twice2["special"].duplicate():
		if(str(entry2.get("id", "")) == "SoftSlavery" and str(entry2.get("charID", "")) == O1):
			var copy2 = JSON.parse(JSON.print(entry2)).result
			copy2["charID"] = twin
			twice2["special"].append(copy2)
	GM.main.RS.loadData(twice2)
	check(OwnershipGameScript.ownerIDs().size() == 2, "setup: loaded with two owners and no record")
	OwnershipGameScript.repairOwners()
	check(OwnershipGameScript.ownerIDs() == [lowest], "with no valid record the owner with the lowest id stays (" + lowest + " not " + other + ")")
	OwnershipGameScript.reconcile()
	check(svc().ownerID() == lowest and OwnershipGameScript.ownerIDs().size() == 1, "and the module's state follows")
	var O2 = lowest

	# ============ 4. Disputes: who wins, who backs down, who cannot answer ============
	var C = rivals[3] if rivals[3] != O2 else rivals[4]
	setClock(10, 0, DAY + 5)
	extender.director = {}
	advance(60, 30)
	svc().data()["disputes"].clear()
	svc().data()["last_dispute"] = -100
	# a) the owner wins
	module.queuedRolls = [0.0]
	var winOwner = OwnershipGameScript.resolveClaim(C, "none")
	check((winOwner["result"] in ["owner_wins", "backs_down", "owner_yields"]) and OwnershipGameScript.ownerIDs().size() == 1, "a claim: " + winOwner["result"] + ", still exactly one owner")
	if(winOwner["result"] == "owner_wins"):
		check(!winOwner["claimantOwns"] and svc().ownerID() == O2 and GM.main.RS.hasSpecialRelationshipID(O2, "SoftSlavery") and module.getInjuries().highestSeverity(C) >= 1, "owner wins: they stay the owner and the claimant is hurt")
	# cooldown: not again at once, whoever the claimant is
	var again = OwnershipGameScript.resolveClaim(C, "none")
	check(again["result"] == "cooldown" and !again["claimantOwns"] and svc().ownerID() == O2, "a second claim straight away is refused: no repeated fights")
	var someoneElse = OwnershipGameScript.resolveClaim(rivals[5], "none")
	check(someoneElse["result"] == "cooldown", "even from somebody else (one dispute every two days)")
	# b) the claimant wins
	setClock(10, 0, DAY + 9)
	svc().data()["disputes"].clear()
	svc().data()["last_dispute"] = -100
	module.getInjuries().remove(C, "trauma")
	module.queuedRolls = [0.999]
	var winClaimant = OwnershipGameScript.resolveClaim(C, "none")
	if(winClaimant["result"] == "claimant_wins" or winClaimant["result"] == "owner_yields"):
		check(winClaimant["claimantOwns"] and !GM.main.RS.hasSpecialRelationship(O2), "claimant wins: the old owner has lost the status at once")
		GM.main.RS.startSpecialRelantionship("SoftSlavery", C)
		check(OwnershipGameScript.ownerIDs() == [C] and svc().ownerID() == C, "and the claimant is the only owner (" + winClaimant["result"] + ")")
		var O3 = C
		# unavailable owner: cannot contest right now, nothing changes, no cooldown consumed
		setClock(10, 0, DAY + 20)
		svc().data()["disputes"].clear()
		svc().data()["last_dispute"] = -100
		IS.stopInteractionsForPawnID(O3)
		IS.startInteraction("Unconscious", {"main": O3})
		var postponed = OwnershipGameScript.resolveClaim(O2, "none")
		check(postponed["result"] == "postponed" and !postponed["claimantOwns"] and svc().ownerID() == O3 and svc().data()["last_dispute"] == -100, "an owner who is knocked out cannot contest immediately: it is postponed, nothing changes, no cooldown used")
		IS.stopInteractionsForPawnID(O3)
		module.getState().gangs["captives"][O3] = {"gang": gangIDs[0], "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
		check(OwnershipGameScript.resolveClaim(O2, "none")["result"] == "postponed", "a held owner cannot either")
		module.getState().gangs["captives"].erase(O3)
		module.getInjuries().applyInjury(O3, "leg", 3)
		check(OwnershipGameScript.resolveClaim(O2, "none")["result"] == "postponed", "nor a badly injured one")
		module.getInjuries().remove(O3, "leg")
		O2 = O3
	else:
		check(!winClaimant["claimantOwns"] and OwnershipGameScript.ownerIDs().size() == 1, "(this claimant backed down or was beaten: " + winClaimant["result"] + "), still one owner")
	# c) the claimant backs down
	setClock(10, 0, DAY + 30)
	svc().data()["disputes"].clear()
	svc().data()["last_dispute"] = -100
	var coward = rivals[4] if rivals[4] != svc().ownerID() else rivals[5]
	GM.main.getCharacter(coward).getPersonality().setStat(PersonalityStat.Coward, 0.9)
	var backs = OwnershipGameScript.resolveClaim(coward, "none")
	check(backs["result"] == "backs_down" and !backs["claimantOwns"] and OwnershipGameScript.ownerIDs().size() == 1, "a timid claimant backs down")
	# d) the player's side
	setClock(10, 0, DAY + 40)
	svc().data()["disputes"].clear()
	svc().data()["last_dispute"] = -100
	var scene4 = makeScene("res://Modules/SandboxOverhaulModule/Scenes/OwnershipDisputeScene.gd", [rivals[0] if rivals[0] != svc().ownerID() else rivals[1]])
	show(scene4)
	watch("the dispute screen")
	check(enabledButtons().size() == 3 and enabledButtons().has("Stay out of it") and shownText().find("wants you") != -1, "the player can back the owner, back the claimant or stay out of it")
	module.queuedRolls = [0.0]
	var ownerBeforeScene = svc().ownerID()
	var trustBefore = rel().getFeeling(ownerBeforeScene, "pc", "trust")
	check(click(scene4, "Stay out of it"), "stay out")
	show(scene4)
	check(enabledButtons() == ["Continue"] and shownText().find(GM.main.getCharacter(ownerBeforeScene).getName()) != -1 or OwnershipGameScript.ownerIDs().size() == 1, "one result and one way on")
	check(OwnershipGameScript.ownerIDs().size() == 1 and OwnershipGameScript.ownerIDs().size() == (1 if svc().hasOwner() else 0), "still exactly one owner after the dispute scene")
	check(rel().getFeeling(ownerBeforeScene, "pc", "trust") == trustBefore, "staying out costs nothing")
	saveAndLoadAll()
	check(OwnershipGameScript.ownerIDs().size() == 1 and svc().hasOwner() and GM.main.RS.hasSpecialRelationshipID(svc().ownerID(), "SoftSlavery"), "saving and loading keeps exactly one owner and the dispute record")
	check(svc().data()["last_dispute"] >= DAY, "the dispute cooldown survives the load")

	# ============ 5. The owner protects the player, from anywhere, once per day ============
	var owner5 = svc().ownerID()
	setClock(10, 0, DAY + 60)
	extender.director = {}
	advance(60, 30)
	endPlayerInteractions()
	moveTo(playerRoom)
	var farRoom = "mining_nearentrance"
	var attacker = ""
	for id5 in cands:
		if(id5 != owner5 and id5 != svc().ownerID() and attacker == ""):
			attacker = id5
	svc().record()["last_help"] = -100
	IS.stopInteractionsForPawnID(owner5)
	IS.getPawn(owner5).setLocation(farRoom)
	IS.getPawn(attacker).setLocation(playerRoom)
	check(OwnershipGameScript.interventionStatus()["state"] == "ready" and OwnershipGameScript.interventionStatus()["text"].begins_with("Protection ready"), "the Ownership screen says protection is ready: " + OwnershipGameScript.interventionStatus()["text"])
	var rec5 = svc().record()
	var winsBefore = rec5["wins"].size() + rec5["owner_losses"].size()
	IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
	var helperFights = 0
	var originalAlive = false
	for interaction5 in IS.interactions:
		if(interaction5.id == "GenericAttack" and !interaction5.wasDeleted and interaction5.getRoleID("reacter") == attacker and interaction5.getRoleID("starter") == owner5):
			helperFights += 1
		if(interaction5.id == "GenericAttack" and !interaction5.wasDeleted and interaction5.getRoleID("reacter") == "pc"):
			originalAlive = true
	check(helperFights == 1 and !originalAlive, "an owner on the far side of the prison comes, with no roll: the attack is replaced by the owner's fight, once")
	check(IS.getPawn(owner5).getLocation() == playerRoom and IS.pawns.keys().count(owner5) == 1 and messageCount("comes straight to you") == 1, "they arrive in the room, once, announced, and there is still only one of them")
	check(svc().record()["last_help"] == main.getDays() and OwnershipGameScript.interventionStatus()["state"] == "used" and OwnershipGameScript.interventionStatus()["text"].begins_with("Protection used today"), "the Ownership screen now says it is used today")
	var helperFight = null
	for interaction6 in IS.interactions:
		if(interaction6.id == "GenericAttack" and !interaction6.wasDeleted and interaction6.getRoleID("starter") == owner5):
			helperFight = interaction6
	if(helperFight != null):
		helperFight.currentActionArgs = {"fight": ["starter", "reacter"]}
		helperFight.doActionFinal("fight", {}, {})
		check(svc().record()["wins"].size() + svc().record()["owner_losses"].size() == winsBefore + 1, "the fight's aftermath is recorded exactly once")
		IS.stopInteraction(helperFight)
	# cooldown
	IS.getPawn(owner5).setLocation(farRoom)
	IS.getPawn(attacker).setLocation(playerRoom)
	endAllInteractionsOf(attacker)
	IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
	check(IS.getPawn(owner5).getLocation() == farRoom and messageCount("comes straight to you") == 1, "a second attack the same day: protection is used, the attack goes ahead")
	endAllInteractionsOf(attacker)
	saveAndLoadAll()
	check(svc().record()["last_help"] == main.getDays() and OwnershipGameScript.interventionStatus()["state"] == "used", "saving and loading keeps the cooldown")
	main.currentDay += OwnershipScript.INTERVENTION_GAP_DAYS
	endAllInteractionsOf(owner5)
	check(OwnershipGameScript.interventionStatus()["state"] == "ready", "the next day it is ready again: " + OwnershipGameScript.interventionStatus()["text"])
	# hard blockers: nothing is used up, and the screen says why
	for blocker in ["unconscious", "held", "hurt", "busy"]:
		endPlayerInteractions()
		moveTo(playerRoom)
		IS.stopInteractionsForPawnID(owner5)
		module.getState().gangs["captives"].erase(owner5)
		module.getInjuries().remove(owner5, "leg")
		IS.getPawn(owner5).setLocation(farRoom)
		IS.getPawn(attacker).setLocation(playerRoom)
		endAllInteractionsOf(attacker)
		svc().record()["last_help"] = -100
		if(blocker == "unconscious"):
			IS.startInteraction("Unconscious", {"main": owner5})
		elif(blocker == "held"):
			module.getState().gangs["captives"][owner5] = {"gang": gangIDs[0], "kind": "captive", "stamp": OwnershipGameScript.clockNow(), "by": ""}
		elif(blocker == "hurt"):
			module.getInjuries().applyInjury(owner5, "leg", 3)
		elif(blocker == "busy"):
			IS.startInteraction("InStocks", {"inmate": owner5})
		var locBefore = IS.getPawn(owner5).getLocation()
		var status = OwnershipGameScript.interventionStatus()
		check(status["state"] == "unavailable" and status["text"].begins_with("Protection unavailable"), blocker + ": the screen says it is unavailable and why: " + status["text"])
		var usedBefore = svc().record()["last_help"]
		IS.startInteraction("GenericAttack", {"starter": attacker, "reacter": "pc"})
		check(IS.getPawn(owner5).getLocation() == locBefore and svc().record()["last_help"] == usedBefore, blocker + ": the owner does not come, is not moved, and the protection is not used up")
		endAllInteractionsOf(attacker)
		endAllInteractionsOf(owner5)
		module.getState().gangs["captives"].erase(owner5)
		module.getInjuries().remove(owner5, "leg")
	endAllInteractionsOf(attacker)


	# ============ 6. One shared victory: gang jobs and the owner's demands count the same outcomes ============
	var leaders = {}
	for gid2 in gangIDs:
		leaders[gid2] = module.getGangs().getLeader(gid2)
	var gid6 = "ironhand"
	var leader6 = leaders[gid6]
	var owner6 = svc().ownerID()
	check(owner6 != "" and owner6 != leader6, "setup: the player has an owner who is not the gang leader")
	moveTo("yard_deadend2")
	setClock(14, 0, DAY + 80)
	extender.director = {}
	advance(60, 30)
	var yields = ["pain", "lust", "submit", "surrender"]
	for yieldKind in yields:
		cleanSlate(gid6, leader6)
		svc().record()["demand"] = {}
		var jobTalk = newGangScene([leader6])
		jobTalk._react("join", [])
		jobTalk._react("takeintro", [gid6])
		jobTalk._react("acceptjob", [])
		var victim = str(module.getGangs().affairsAssignment()["target"]) if false else str(GangGameScript.affairs().getAssignment()["target"])
		moveTo("hall_mainentrance")
		var _vp = placeAt(victim, "hall_mainentrance")
		svc().record()["demand"] = {"id": 1, "type": "defeat", "state": "active", "amount": 0, "item": "", "target": victim, "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 0, "day": 0, "block": ""}
		check(GangGameScript.affairs().getAssignment()["state"] == "active" and svc().demand()["state"] == "active", yieldKind + ": setup: a gang job and an owner's demand both ask for the same defeat")
		endAllInteractionsOf(victim)
		IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": victim})
		var attack = null
		for interaction8 in IS.interactions:
			if(interaction8.id == "GenericAttack" and !interaction8.wasDeleted and interaction8.getRoleID("reacter") == victim):
				attack = interaction8
		check(attack != null, yieldKind + ": setup: the player attacks them")
		attack.currentActionArgs = {"fight": ["starter", "reacter"]}
		match(yieldKind):
			"pain":
				attack.doFightAftermath(["starter", "reacter"], {"won": true, "how": "pain"})
			"lust":
				attack.doFightAftermath(["starter", "reacter"], {"won": true, "how": "lust"})
			"submit":
				attack.doFightAftermath(["starter", "reacter"], {"won": true, "how": "submit", "submitter": victim})
			"surrender":
				attack.init_do("surrender", {}, {})
		check(GangGameScript.affairs().getAssignment()["state"] == "ready", yieldKind + ": the gang job counts it")
		check(svc().demand()["state"] == "ready", yieldKind + ": the owner's demand counts it")
		var creditsBeforeJob = thePlayer.getCredits()
		var trustBeforeDemand = rel().getFeeling(owner6, "pc", "trust")
		attack.doFightAftermath(["starter", "reacter"], {"won": true, "how": yieldKind}) # the same encounter reported again
		check(GangGameScript.affairs().getAssignment()["state"] == "ready" and svc().demand()["state"] == "ready" and thePlayer.getCredits() == creditsBeforeJob, yieldKind + ": reporting the same encounter twice changes nothing")
		jobTalk._react("report", [])
		check(!GangGameScript.affairs().hasAssignment() and thePlayer.getCredits() >= creditsBeforeJob, yieldKind + ": the gang job completes on the report")
		var creditsAfterJob = thePlayer.getCredits()
		jobTalk._react("report", [])
		check(thePlayer.getCredits() == creditsAfterJob, yieldKind + ": and pays only once")
		var handed = OwnershipGameScript.demandHandOver()
		check(handed["ok"] and svc().demand().empty() and rel().getFeeling(owner6, "pc", "trust") > trustBeforeDemand, yieldKind + ": the owner's demand completes on the report, with its reward")
		var trustAfterDemand = rel().getFeeling(owner6, "pc", "trust")
		var handedAgain = OwnershipGameScript.demandHandOver()
		check(!handedAgain["ok"] and rel().getFeeling(owner6, "pc", "trust") == trustAfterDemand, yieldKind + ": and rewards only once")
		endAllInteractionsOf(victim)
	# what must not count
	var nots = ["player_loses", "player_surrenders", "abandoned", "someone_else", "unfinished"]
	for notKind in nots:
		cleanSlate(gid6, leader6)
		var negTalk = newGangScene([leader6])
		negTalk._react("join", [])
		negTalk._react("takeintro", [gid6])
		negTalk._react("acceptjob", [])
		var victim2 = str(GangGameScript.affairs().getAssignment()["target"])
		moveTo("hall_mainentrance")
		var _vp2 = placeAt(victim2, "hall_mainentrance")
		svc().record()["demand"] = {"id": 2, "type": "defeat", "state": "active", "amount": 0, "item": "", "target": victim2, "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 0, "day": 0, "block": ""}
		endAllInteractionsOf(victim2)
		IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": victim2})
		var attack2 = null
		for interaction9 in IS.interactions:
			if(interaction9.id == "GenericAttack" and !interaction9.wasDeleted and interaction9.getRoleID("reacter") == victim2):
				attack2 = interaction9
		attack2.currentActionArgs = {"fight": ["starter", "reacter"]}
		match(notKind):
			"player_loses":
				attack2.doFightAftermath(["starter", "reacter"], {"won": false, "how": "pain"})
			"player_surrenders":
				IS.stopInteraction(attack2)
				IS.startInteraction("GenericAttack", {"starter": victim2, "reacter": "pc"})
				for interaction10 in IS.interactions:
					if(interaction10.id == "GenericAttack" and !interaction10.wasDeleted and interaction10.getRoleID("starter") == victim2):
						interaction10.init_do("surrender", {}, {})
			"abandoned":
				IS.stopInteraction(attack2)
			"someone_else":
				module.onFightAftermath(null, cands[0], victim2, {"won": true, "how": "pain"})
			"unfinished":
				pass
		check(GangGameScript.affairs().getAssignment()["state"] == "active" and svc().demand()["state"] == "active", notKind + ": neither task counts it")
		endAllInteractionsOf(victim2)
		svc().record()["demand"] = {}

	# ============ 7. The yellow Q: derived from the live task state ============
	cleanSlate(gid6, leader6)
	var qJob = newGangScene([leader6])
	qJob._react("join", [])
	qJob._react("takeintro", [gid6])
	qJob._react("acceptjob", [])
	var qTarget = str(GangGameScript.affairs().getAssignment()["target"])
	var _vp3 = placeAt(qTarget, "hall_mainentrance")
	GM.main.getCharacter(qTarget).npcName = "Bartholomew Alexander Montgomery-Featherstonehaugh"
	world.updatePawns(IS)
	var qPawn = world.pawns[qTarget]
	check(qPawn.taskLabel != null and qPawn.taskLabel.visible and qPawn.taskLabel.text == "Q" and qPawn.taskLabel.hint_tooltip == "Task target: Defeat Bartholomew Alexander Montgomery-Featherstonehaugh", "an active defeat target carries a Q, with a tooltip that names the task (even with a long name): " + str(qPawn.taskLabel.hint_tooltip if qPawn.taskLabel != null else ""))
	check(qPawn.taskLabel.get_color("font_color").r > 0.9 and qPawn.taskLabel.get_color("font_color").g > 0.7 and qPawn.taskLabel.get_color("font_color").b < 0.3, "it is yellow")
	check(qPawn.gangLabel != null and qPawn.gangLabel.visible and qPawn.taskLabel.rect_position.x == qPawn.gangLabel.rect_position.x + 12.0, "next to the gang badge G, which stays")
	var leaderPawn = world.pawns.get(leader6, null)
	check(leaderPawn == null or leaderPawn.taskLabel == null or !leaderPawn.taskLabel.visible, "the gang leader has no Q while the job is still out there")
	GangGameScript.onFightResult("pc", qTarget)
	world.updatePawns(IS)
	check(!qPawn.taskLabel.visible, "the Q leaves the target the moment they are beaten")
	var qLeader = world.pawns[leader6]
	check(qLeader.taskLabel != null and qLeader.taskLabel.visible and qLeader.taskLabel.hint_tooltip == "Task contact: Report to " + GangGameScript.nameOf(leader6), "and appears on the gang leader to report back to: " + str(qLeader.taskLabel.hint_tooltip))
	saveAndLoadAll()
	world.updatePawns(IS)
	world.updatePawns(IS)
	var qCount = 0
	for child in world.pawns[leader6].get_children():
		if(child is Label and child.text == "Q"):
			qCount += 1
	check(qCount == 1 and world.pawns[leader6].taskLabel.visible, "saving and loading does not duplicate it (" + str(qCount) + ")")
	qJob = newGangScene([leader6])
	qJob._react("report", [])
	world.updatePawns(IS)
	check(!world.pawns[leader6].taskLabel.visible, "reporting back removes it")
	# the owner's tasks
	var ownerQ = svc().ownerID()
	svc().record()["demand"] = {"id": 3, "type": "credits", "state": "active", "amount": 4, "item": "", "target": "", "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 0, "day": 0, "block": ""}
	world.updatePawns(IS)
	check(world.pawns[ownerQ].taskLabel.visible and world.pawns[ownerQ].taskLabel.hint_tooltip.find("Task contact: Hand it over to") != -1, "an owner who is owed something carries a Q")
	svc().record()["demand"]["state"] = "ready"
	world.updatePawns(IS)
	check(world.pawns[ownerQ].taskLabel.hint_tooltip.find("Task contact: Report to") != -1, "or one to report back to")
	svc().record()["demand"] = {}
	svc().record()["meeting"] = {}
	svc().record()["checkin"] = {"day": main.getDays(), "state": "pending", "reminded": false, "block": ""}
	world.updatePawns(IS)
	check(world.pawns[ownerQ].taskLabel.visible and world.pawns[ownerQ].taskLabel.hint_tooltip.find("Check in with") != -1, "or one to check in with")
	svc().record()["checkin"] = {"day": -1, "state": "", "reminded": false, "block": ""}
	var defeatVictim = cands[1]
	svc().record()["demand"] = {"id": 4, "type": "defeat", "state": "active", "amount": 0, "item": "", "target": defeatVictim, "created": OwnershipGameScript.clockNow(), "deadline": OwnershipGameScript.clockNow() + 36 * 3600, "negotiated": false, "at": 0, "day": 0, "block": ""}
	world.updatePawns(IS)
	check(world.pawns[defeatVictim].taskLabel.visible and world.pawns[defeatVictim].taskLabel.hint_tooltip.find("Task target: Defeat") != -1, "an owner's defeat demand marks its target")
	svc().record()["demand"] = {}
	svc().record()["meeting"] = {} # (a told demand also made a pending meeting: that is its own Q)
	world.updatePawns(IS)
	check(!world.pawns[defeatVictim].taskLabel.visible and !world.pawns[ownerQ].taskLabel.visible, "and all of it disappears when the demand is gone (completed, failed or cancelled)")
	# a slave about to run
	var slaveQ = cands[2]
	var npcSlaveryQ = GlobalRegistry.getModule("NpcSlaveryModule")
	check(npcSlaveryQ.doEnslaveCharacter(slaveQ), "setup: a slave")
	svc().data()["slaves"][slaveQ]["setup"] = "set"
	svc().data()["slaves"][slaveQ]["escape"] = {"stage": "warning", "day": main.getDays(), "why": "x"}
	world.updatePawns(IS)
	check(world.pawns[slaveQ].slaveLabel.visible and world.pawns[slaveQ].taskLabel.visible and world.pawns[slaveQ].taskLabel.hint_tooltip.find("Talk to") != -1 and world.pawns[slaveQ].taskLabel.rect_position.x == world.pawns[slaveQ].slaveLabel.rect_position.x + 12.0, "a slave about to run carries S and Q side by side")
	svc().data()["slaves"][slaveQ]["escape"] = {}
	world.updatePawns(IS)
	check(!world.pawns[slaveQ].taskLabel.visible and world.pawns[slaveQ].slaveLabel.visible, "the Q goes when the warning is dealt with and the S stays")
	var _slaveFree = npcSlaveryQ.doFreeEnslavedCharacter(slaveQ)
	# every combination on a real map label
	var wp = load("res://Game/World/WorldPawn.tscn").instance()
	add_child(wp)
	var tag0 = wp.relationship_label.rect_position.x
	wp.setRelationshipText("O", Color.red)
	wp.setGangBadge("G", Color.yellow, "gang", true)
	wp.setSlaveBadge("S", Color(0.85, 0.35, 0.95), "Your slave.", 2)
	wp.setTaskBadge("Q", Color(1.0, 0.85, 0.1), "Task target: Defeat a person with a very long name indeed", 3)
	check(wp.relationship_label.visible and wp.gangLabel.visible and wp.slaveLabel.visible and wp.taskLabel.visible and wp.gangLabel.rect_position.x == tag0 + 12.0 and wp.slaveLabel.rect_position.x == tag0 + 24.0 and wp.taskLabel.rect_position.x == tag0 + 36.0, "'O G S Q': four badges side by side, none hiding another")
	wp.setRelationshipText("F", Color.green)
	wp.setGangBadge("", Color.white, "", false)
	wp.setSlaveBadge("", Color.white, "", 0)
	wp.setTaskBadge("Q", Color(1.0, 0.85, 0.1), "contact", 1)
	check(wp.relationship_label.text == "F" and wp.taskLabel.rect_position.x == tag0 + 12.0 and !wp.gangLabel.visible and !wp.slaveLabel.visible, "'F Q'")
	wp.setRelationshipText("N", Color.red)
	wp.setTaskBadge("Q", Color(1.0, 0.85, 0.1), "contact", 1)
	check(wp.relationship_label.text == "N" and wp.taskLabel.visible, "'N Q' keeps the tag")
	wp.setRelationshipText("", Color.white)
	wp.setTaskBadge("Q", Color(1.0, 0.85, 0.1), "contact", 0)
	check(!wp.relationship_label.visible and wp.taskLabel.rect_position.x == tag0, "a Q on its own sits where the first badge goes")
	wp.setTaskBadge("", Color.white, "", 0)
	check(!wp.taskLabel.visible, "and can be cleared")
	wp.queue_free()

	print("OwnershipClaimsBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	GM.ES = null
	eventSystem.free()
	GM.ui = null
	GM.main = null
	GM.pc = null
	GM.world = null
	get_tree().quit(1 if failures > 0 else 0)

func cleanSlate(gid, leader):
	var g = module.getGangs()
	g.data()["player"]["intro"].clear()
	g.data()["player"]["left_day"] = -1
	g.data()["player"]["left_from"] = ""
	g.data()["player"]["last_job"] = {}
	g.data()["assignment"] = {}
	g.data()["cooldowns"].clear()
	if(g.playerGang() != ""):
		var _l = g.leave("pc", 50, {})
	var _p = g.setPersonal("pc", gid, 0)
	rel().setFeeling(leader, "pc", "trust", 0)
	rel().setFeeling(leader, "pc", "respect", 0)
	rel().setFeeling(leader, "pc", "affection", 0)

func newGangScene(args):
	var scene = load("res://Modules/SandboxOverhaulModule/Scenes/GangScene.gd").new()
	scene._initScene(args)
	return scene

func placeAt(id, room):
	var pawn = DirectorScript.spawnAt(IS, id, room)
	if(pawn != null and pawn.getLocation() != room):
		var wasDisabled = IS.interactionsDisabled
		IS.interactionsDisabled = true
		pawn.setLocation(room)
		IS.interactionsDisabled = wasDisabled
	return pawn
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")

func ownerScenes() -> int:
	return sceneCountOf("NpcOwnerEventRunnerScene")

func sceneCountOf(sceneID) -> int:
	var count = 0
	for call in main.sceneCalls:
		if(call[0] == sceneID):
			count += 1
	return count

func countOwners() -> int:
	var count = 0
	for id in GM.main.RS.special:
		if(GM.main.RS.special[id].id == "SoftSlavery"):
			count += 1
	return count

func endAllInteractionsOf(id):
	for interaction in IS.interactions.duplicate():
		if(interaction.getInvolvedPawnIDs().has(id) and interaction.id != "AloneInteraction"):
			IS.stopInteraction(interaction)

func talkTo(id):
	IS.updatePCLocation()
	moveTo(pawnLoc(id))
	endPlayerInteractions()
	endAllInteractionsOf(id)
	IS.startInteraction("Talking", {"starter": "pc", "reacter": id}, {})
	for interaction in IS.interactions:
		if(interaction.id == "Talking" and interaction.getInvolvedPawnIDs().has(id) and !interaction.wasDeleted):
			return interaction
	return null

func actionIDs(interaction) -> Array:
	var ids = []
	for entry in interaction.getActionsFinal():
		if(entry.has("id")):
			ids.append(entry["id"])
	return ids

func talkText(interaction) -> String:
	return str(interaction.getTextAndActions()[0])

func pressAction(interaction, id) -> bool:
	for entry in interaction.getActionsFinal():
		if(entry.get("id", "") == id):
			interaction.doActionFinal(id, entry.get("args", {}), {})
			return true
	return false

func makeScene(path, args):
	var scene = load(path).new()
	scene._initScene(args)
	return scene

func show(scene):
	ui.clearButtons()
	ui.clearText()
	main.sceneStack.append(scene) # the scene is on top while it draws, as in the game: the speaker of [say=npc] lines is resolved through it
	scene._run()
	main.sceneStack.pop_back()
	check(shownText().find("!Error") == -1, "no internal error text on the " + str(scene.sceneID) + " screen")

func shownText() -> String:
	return ui.textOutput.bbcode_text

func enabledButtons() -> Array:
	var result = []
	var keys = ui.options.keys()
	keys.sort()
	for key in keys:
		if(ui.options[key][0]):
			result.append(ui.options[key][1])
	return result

# The watchdog: whatever the screen is, there is something to press.
func watch(label):
	check(enabledButtons().size() >= 1, label + ": never an empty action grid")

func click(scene, text) -> bool:
	for option in ui.options.values():
		if(option[0] and option[1] == text):
			scene._react(option[3], option[4])
			return true
	return false

func saveAndLoadAll():
	var savedRS = JSON.print(GM.main.RS.saveData())
	saveAndLoad()
	GM.main.RS.loadData(JSON.parse(savedRS).result)

func advanceToAxis(target, step):
	var guard = 0
	while(RoutineScript.axis(main.timeOfDay) < target and guard < 3000):
		advance(step, step)
		guard += 1

# Follows one slave to the target room in steps of `step` seconds until the axis time `until`: {rooms, jumps, arrived (steps), arrivedAxis, heading, sleeping}.
func follow(id, until, step, target) -> Dictionary:
	var rooms = {}
	var jumps = 0
	var last = IS.getPawn(id).getLocation()
	var arrived = -1
	var arrivedAxis = -1
	var steps = 0
	var heading = false
	var sleeping = false
	while(RoutineScript.axis(main.timeOfDay) < until and steps < 3000):
		advance(step, step)
		steps += 1
		var here = IS.getPawn(id).getLocation()
		rooms[here] = true
		if(here != last and world.calculatePath(last, here).size() > 3):
			jumps += 1
		last = here
		var text = OwnershipGameScript.slaveActivityText(id)
		if(here != target and text.find("heading to your cell") != -1):
			heading = true
		if(here == target and text.find("sleeping in your cell") != -1):
			sleeping = true
		if(here == target and arrived < 0):
			arrived = steps
			arrivedAxis = RoutineScript.axis(main.timeOfDay)
	return {"rooms": rooms.keys(), "jumps": jumps, "arrived": arrived, "arrivedAxis": arrivedAxis, "heading": heading, "sleeping": sleeping}

# What the old criteria said (kept here only to measure the change): willingness mixed with a personal-strength "ability" that almost nobody reached.
func legacyDecision(npcID) -> Dictionary:
	var traits = OwnershipGameScript.traitsOf(npcID)
	var dominance = clamp(-float(traits["subby"]), -1.0, 1.0)
	var gid = module.getGangs().gangOf(npcID)
	var ability = float(OwnershipScript.protection({"hasOwner": true, "style": OwnershipGameScript.styleFor(npcID), "ownerPower": GangGameScript.power(npcID), "attackerPower": 0.9, "attackerFear": 0.0,
		"gangStrength": GangGameScript.gangStrength(gid) if gid != "" else 0.0, "retaliated": false, "available": true, "recentLosses": 0})["credibility"])
	var score = 0.30 * dominance + 0.25 * rel().getFeeling(npcID, "pc", "respect") / 100.0 + 0.15 * rel().getFeeling(npcID, "pc", "affection") / 100.0 + 0.15 * clamp(GM.main.RS.getLust(npcID, "pc"), -1.0, 1.0) + 0.15 * ability + 0.10 * rel().getFeeling(npcID, "pc", "trust") / 100.0
	return {"accepts": score >= 0.25, "ability": ability}

extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/ConversationBootTest.tscn
# Drives the real Talking branch methods (with stub pawns), the real doReactToChat and reactToLustFocus helpers,
# the real RelationshipSystem (including Nemesis creation) and the real CharacterPawn. Exits with code 1 on failure.

var failures = 0

class FakePawn:
	var character = null
	var pc = false
	func afterSocialInteraction():
		pass
	func afterFailedSocialInteraction():
		pass
	func isPlayer():
		return pc
	func getChar():
		return character
	func scoreAffection(_other):
		return 0.0
	func scoreLust(_other):
		return 0.0
	func scorePersonalityMax(_stats, _minValue = -999.9):
		return 0.0
	func getFocusedLikenessSummary(_other, _focus, _flag = false):
		return {"topicsLikedPresence": [], "topicsLikedAbsence": [], "topicsDislikedPresence": [], "topicsDislikedAbsence": [], "resultValue": 1.0}

class FakeTalking extends "res://Game/InteractionSystem/Interactions/Talking.gd":
	var pawns = {}
	var eventsSent = []
	var oldFormulaCalls = []
	func getRolePawn(role:String):
		return pawns[role]
	# Records the event and forwards it to the real RelationshipSystem, so Nemesis creation is real.
	func sendSocialEvent(_roleActor:String, _roleTarget:String, _eventID:int, _args:Array = []):
		eventsSent.append(_eventID)
		GM.main.RS.sendSocialEvent(getRoleID(_roleActor), getRoleID(_roleTarget), _eventID, _args)
	func affectAffection(role1:String, role2:String, howMuch:float):
		oldFormulaCalls.append(["affection", role1, role2, howMuch])
	func affectLust(role1:String, role2:String, howMuch:float):
		oldFormulaCalls.append(["lust", role1, role2, howMuch])

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func addNpc(main, npcID):
	var c = DynamicCharacter.new()
	c.id = npcID
	c.name = npcID
	c.npcName = npcID
	c.lustInterests = LustInterests.new()
	c.personality = Personality.new()
	main.dynamicCharacters[npcID] = c
	return c

# npcIsStarter false: the player starts and the NPC reacts. True: the NPC starts and the player reacts.
func makeTalking(npcID, npcIsStarter, npcs):
	var t = FakeTalking.new()
	t.involvedPawns = {"starter": npcID if npcIsStarter else "pc", "reacter": "pc" if npcIsStarter else npcID}
	for role in t.involvedPawns:
		var p = FakePawn.new()
		p.pc = (t.involvedPawns[role] == "pc")
		p.character = npcs.get(t.involvedPawns[role])
		t.pawns[role] = p
	return t

func directedCount(main) -> int:
	var n = 0
	for m in main.messages:
		if(m.find("feelings changed") != -1):
			n += 1
	return n

func lastDirected(main) -> String:
	for i in range(main.messages.size() - 1, -1, -1):
		if(main.messages[i].find("feelings changed") != -1):
			return main.messages[i]
	return ""

func messagesText(main) -> String:
	return Util.join(main.messages, "\n")

# Runs the real Talking branch for a named scenario.
func runBranch(t, scenario):
	var chatArgs = {"startRole": "starter", "reactRole": "reacter", "topicID": "topicX"}
	if(scenario == "chat_agree_strong"):
		t.chat = chatArgs
		t.chat_asked_do("react", {"answer": "agree", "chat": chatArgs}, {})
	elif(scenario == "chat_agree_weak"):
		chatArgs["topicID"] = "topicY"
		t.chat = chatArgs
		t.chat_asked_do("react", {"answer": "agree", "chat": chatArgs}, {})
	elif(scenario == "chat_disagree"):
		t.chat = chatArgs
		t.chat_asked_do("react", {"answer": "disagree", "chat": chatArgs}, {})
	elif(scenario == "chat_whatever"):
		t.chat = chatArgs
		t.chat_asked_do("react", {"answer": "whatever", "chat": chatArgs}, {})
	elif(scenario == "pickup_accept"):
		t.flirt_pickupline_do("accept", {}, {})
	elif(scenario == "pickup_deny"):
		t.flirt_pickupline_do("deny", {}, {})
	elif(scenario == "focus_accept" or scenario == "focus_deny"):
		t.lust = {"focus": "Body", "role1": "starter", "role2": "reacter"}
		t.flirt_flirted_do("flirt_react", {"answer": "accept" if scenario == "focus_accept" else "deny", "likeness": 1.0 if scenario == "focus_accept" else 0.0}, {})
	elif(scenario == "sex_offer_agree"):
		t.offered_sex_do("agree", {}, {})
	elif(scenario == "sex_offer_deny"):
		t.offered_sex_do("deny", {}, {})
	elif(scenario == "self_offer_agree"):
		t.offered_self_do("agree", {}, {})
	elif(scenario == "self_offer_deny"):
		t.offered_self_do("deny", {}, {})

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	var main = load("res://Game/MainScene.gd").new()
	GM.main = main
	var RS = main.RS
	var thePlayer = load("res://Player/Player.gd").new()
	thePlayer.reputation = Reputation.new()
	thePlayer.lustInterests = LustInterests.new()
	GM.pc = thePlayer
	var npcMap = {}
	var rel = SandboxOverhaulModule.getRelationships()
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")

	# ---- Every mapped outcome, in both orientations ----
	# scenario: [directed values after one run, legacy affection, legacy lust, rewarding, can the npc start it]
	var table = {
		"chat_agree_strong": [{"affection": 3.0, "trust": 1.0}, 0.03, 0.0, true, true],
		"chat_agree_weak": [{"affection": 2.0, "trust": 1.0}, 0.02, 0.0, true, false],
		"chat_disagree": [{"affection": -1.0}, -0.01, 0.0, false, true],
		"chat_whatever": [{}, 0.0, 0.0, false, true],
		"pickup_accept": [{"affection": 2.0, "desire": 4.0}, 0.02, 0.04, true, true],
		"pickup_deny": [{"desire": -2.0}, 0.0, -0.02, false, true],
		"focus_accept": [{"affection": 2.0, "desire": 4.0}, 0.02, 0.04, true, true],
		"focus_deny": [{"desire": -2.0}, 0.0, -0.02, false, true],
		"sex_offer_agree": [{"desire": 2.0}, 0.0, 0.02, true, true],
		"sex_offer_deny": [{}, 0.0, 0.0, false, true],
		"self_offer_agree": [{"desire": 2.0}, 0.0, 0.02, true, true],
		"self_offer_deny": [{}, 0.0, 0.0, false, true],
	}
	var axes = ["affection", "trust", "respect", "fear", "desire"]
	var index = 0
	for scenario in table:
		index += 1
		var npcID = "npc" + str(index)
		npcMap[npcID] = addNpc(main, npcID)
		npcMap[npcID].getLustInterests().addInterest("topicX", "Loves")
		npcMap[npcID].getLustInterests().addInterest("topicY", "KindaLikes")
		var entry = table[scenario]
		# Legacy lust cannot go below 0, so a reduction is only visible from a positive start.
		var lustBase = 0.1 if entry[2] < 0.0 else 0.0
		if(lustBase > 0.0):
			RS.addLust(npcID, "pc", lustBase, false, false)
		var orientations = [false, true] if entry[4] else [false]
		var runNumber = 0
		for npcIsStarter in orientations:
			runNumber += 1
			var label = scenario + " (" + ("npc starts" if npcIsStarter else "npc reacts") + ")"
			var t = makeTalking(npcID, npcIsStarter, npcMap)
			var messagesBefore = directedCount(main)
			runBranch(t, scenario)
			# Rewarding outcomes pay once across both orientations; the others apply on every run.
			var times = 1 if entry[3] else runNumber
			for axis in axes:
				var want = entry[0].get(axis, 0.0) * times
				check(near(rel.getFeeling(npcID, "pc", axis), want), label + ": directed " + axis + " is " + str(want) + ", got " + str(rel.getFeeling(npcID, "pc", axis)))
			check(!rel.hasRelationship("pc", npcID) and rel.getFeeling("pc", npcID, "affection") == 0.0, label + ": nothing stored in the direction pc -> npc")
			check(near(RS.getAffection(npcID, "pc"), entry[1] * times) and near(RS.getLust(npcID, "pc"), lustBase + entry[2] * times), label + ": legacy values " + str(RS.getAffection(npcID, "pc")) + " / " + str(RS.getLust(npcID, "pc")))
			check(t.oldFormulaCalls.empty(), label + ": the old formula did not also run")
			check(!t.eventsSent.has(SocialEventType.GotRefused), label + ": no GotRefused event")
			var expectMessage = (not entry[0].empty()) and (not entry[3] or runNumber == 1)
			check(directedCount(main) == messagesBefore + (1 if expectMessage else 0), label + ": message count")
			if(expectMessage):
				check(lastDirected(main).begins_with(npcID + "'s feelings changed:"), label + ": the message names the npc: " + lastDirected(main))
		check(!RS.hasSpecialRelationship(npcID), scenario + ": no special relationship")
	check(messagesText(main).find("towards you") == -1, "no legacy percentage message from any migrated outcome")

	# ---- Maximally mean and hostile NPC: refusals and disagreement can never start a Nemesis ----
	npcMap["mean1"] = addNpc(main, "mean1")
	npcMap["mean1"].getPersonality().setStat(PersonalityStat.Mean, 1.0)
	npcMap["mean1"].getPersonality().setStat(PersonalityStat.Subby, -1.0)
	RS.setAffection("mean1", "pc", -1.0)
	var refusalScenarios = ["chat_disagree", "chat_whatever", "pickup_deny", "focus_deny", "sex_offer_deny", "self_offer_deny"]
	var refused = 0
	for _attempt in range(40):
		main.currentDay += 1
		for scenario in refusalScenarios:
			for npcIsStarter in [false, true]:
				var t = makeTalking("mean1", npcIsStarter, npcMap)
				runBranch(t, scenario)
				refused += 1
	check(refused == 40 * 12, "ran every refusal attempt")
	check(!RS.hasSpecialRelationship("mean1"), "480 refusals and disagreements against a maximally hostile NPC: no Nemesis")

	# Control: the bad event itself does create a Nemesis against the same kind of NPC, so the check above is meaningful.
	npcMap["control1"] = addNpc(main, "control1")
	npcMap["control1"].getPersonality().setStat(PersonalityStat.Mean, 1.0)
	npcMap["control1"].getPersonality().setStat(PersonalityStat.Subby, -1.0)
	RS.setAffection("control1", "pc", -1.0)
	var tries = 0
	while(!RS.hasSpecialRelationship("control1") and tries < 300):
		RS.sendSocialEvent("pc", "control1", SocialEventType.GotRefused)
		tries += 1
	check(RS.hasSpecialRelationshipID("control1", "Nemesis"), "control: GotRefused can start a Nemesis (" + str(tries) + " tries)")

	# ---- Two NPCs or two players: the module does not apply the outcome, old behaviour stays ----
	npcMap["x1"] = addNpc(main, "x1")
	npcMap["x2"] = addNpc(main, "x2")
	var tn = FakeTalking.new()
	tn.involvedPawns = {"starter": "x1", "reacter": "x2"}
	for role in tn.involvedPawns:
		var p = FakePawn.new()
		p.character = npcMap[tn.involvedPawns[role]]
		tn.pawns[role] = p
	tn.offered_sex_do("deny", {}, {})
	check(not tn.oldFormulaCalls.empty() and tn.eventsSent.has(SocialEventType.GotRefused), "npc to npc: the old formula and event still run")
	check(!rel.hasRelationship("x2", "x1") and !rel.hasRelationship("x1", "x2"), "npc to npc: no directed change")
	var both = FakeTalking.new()
	both.involvedPawns = {"starter": "pc", "reacter": "pc"}
	check(both.getSandboxNpcID() == "" and !both.sandboxConversationOutcome("flirt_accepted"), "two players: not handled")

	# ---- Unrelated CharacterPawn callers keep their messages ----
	npcMap["ghost2"] = addNpc(main, "ghost2")
	var pawn = CharacterPawn.new()
	pawn.charID = "ghost2"
	var before = main.messages.size()
	pawn.affectAffection("pc", 0.2)
	pawn.affectLust("pc", 0.1)
	check(main.messages.size() == before + 2, "unrelated pawn calls still show their legacy messages: " + str(main.messages.slice(before, main.messages.size())))
	check(RS.getAffection("ghost2", "pc") > 0.0 and RS.getLust("ghost2", "pc") > 0.0, "and the legacy values update")

	# ---- Friend pacing: one reward per day, about 17 days ----
	npcMap["pace"] = addNpc(main, "pace")
	var paceBase = main.currentDay
	for day in range(1, 17):
		main.currentDay = paceBase + day
		var messagesToday = directedCount(main)
		for _i in range(4):
			module.applyConversationOutcome("shared_interest", "pace", "pc")
		check(directedCount(main) == messagesToday + 1, "day " + str(day) + ": exactly one message")
		check(!RS.hasSpecialRelationship("pace"), "day " + str(day) + ": no Friend yet")
	check(near(rel.getFeeling("pace", "pc", "affection"), 48.0) and near(RS.getAffection("pace", "pc"), 0.48), "16 days: directed 48, legacy 0.48")
	main.currentDay = paceBase + 17
	for _i in range(4):
		module.applyConversationOutcome("shared_interest", "pace", "pc")
	check(near(RS.getAffection("pace", "pc"), 0.51) and RS.hasSpecialRelationshipID("pace", "Friend"), "the 17th day crosses 0.5 and starts the Friend: " + str(RS.getAffection("pace", "pc")))

	# ---- Save and load keep results and cooldowns ----
	var legacyBefore = RS.getAffection("pace", "pc")
	var desireBefore = rel.getFeeling("npc9", "pc", "desire")
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	check(saved["extendersData"]["SandboxGameExtender"]["cooldowns"].has("conv|pace|pc|shared_interest"), "cooldown is in the save")
	SandboxOverhaulModule.getState().cooldowns.clear()
	rel.removeCharacter("pace")
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(near(rel.getFeeling("pace", "pc", "affection"), 51.0) and near(rel.getFeeling("npc9", "pc", "desire"), desireBefore) and !rel.hasRelationship("pc", "pace"), "directed results survive save and load in the same direction")
	var blocked = module.applyConversationOutcome("shared_interest", "pace", "pc")
	check(blocked["blocked"] == true and near(RS.getAffection("pace", "pc"), legacyBefore), "after load the same day is still claimed")

	# ---- Pruning removes cooldowns of deleted characters ----
	module.applyConversationOutcome("flirt_accepted", "ghost3", "pc")
	check(SandboxOverhaulModule.getState().cooldowns.has("conv|ghost3|pc|flirt_accepted"), "setup: unknown character cooldown")
	var _s = GM.GES.saveData()
	check(!SandboxOverhaulModule.getState().cooldowns.has("conv|ghost3|pc|flirt_accepted") and SandboxOverhaulModule.getState().cooldowns.has("conv|pace|pc|shared_interest"), "saving prunes cooldowns of characters that no longer exist")

	# ---- Reset between games ----
	var main2 = load("res://Game/MainScene.gd").new()
	GM.main = main2
	check(!SandboxOverhaulModule.getRelationships().hasRelationship("pace", "pc") and SandboxOverhaulModule.getState().cooldowns.empty(), "new game: relationships and cooldowns reset")

	GM.main = null
	GM.pc = null
	thePlayer.free()
	for n in npcMap:
		npcMap[n].free()
	main.dynamicCharacters.clear()
	main.free()
	main2.free()
	print("ConversationBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

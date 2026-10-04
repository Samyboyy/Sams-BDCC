extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/CombatSceneBootTest.tscn
# Real path: a real FightScene with a real Player and a real DynamicCharacter, real checkEnd, the real Submit and endbattle actions, the real
# WorldScene._react_scene_end and the real GenericAttack / CaughtOffLimits interactions. Only the pawns and the scene-end plumbing are stubbed.
# Exits with code 1 on failure.

var failures = 0

class FakePawn:
	var charID = ""
	var pc = false
	func isPlayer():
		return pc
	func afterWonFight():
		pass
	func afterLostFight():
		pass
	func addExperienceIfPlayer(_amount):
		pass
	func calculatePowerScore():
		return 1.0
	func isInmate():
		return true
	func addRepScore(_stat, _amount):
		pass

class FakeFight extends "res://Scenes/FightScene.gd":
	# The scene normally asks the main scene to remove it here, which needs the UI.
	func endScene(result = []):
		sceneEndedFlag = true
		sceneEndedArgs = result

class FakeWorld extends "res://Scenes/WorldScene.gd":
	var target = null
	func sendStatusToInteraction(_result):
		target.receiveSceneStatusFinal(_result)

class FakeAttack extends "res://Game/InteractionSystem/Interactions/GenericAttack.gd":
	var pawns = {}
	func getRolePawn(role:String):
		return pawns[role]
	func sendSocialEvent(_roleActor:String, _roleTarget:String, _eventID:int, _args:Array = []):
		pass

class FakeCaught extends "res://Game/InteractionSystem/Interactions/CaughtOffLimits.gd":
	var pawns = {}
	func getRolePawn(role:String):
		return pawns[role]
	func sendSocialEvent(_roleActor:String, _roleTarget:String, _eventID:int, _args:Array = []):
		pass

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

var main = null
var thePlayer = null
var spawned = []

func addNpc(npcID):
	var c = DynamicCharacter.new()
	c.id = npcID
	c.name = npcID
	c.npcName = npcID
	add_child(c)
	main.dynamicCharacters[npcID] = c
	spawned.append(c)
	return c

func resetPlayer():
	thePlayer.addPain(-thePlayer.getPain())
	thePlayer.addLust(-thePlayer.getLust())

func makeFight(npc, battleName):
	var fs = FakeFight.new()
	fs.enemyID = npc.id
	fs.enemyCharacter = npc
	fs.battleName = battleName
	return fs

# Plays the scenario with the real scene methods. Returns the ended scene.
func playScene(scenario, npc, battleName):
	resetPlayer()
	var fs = makeFight(npc, battleName)
	if(scenario == "player_submit"):
		fs._react("submit", [])
	elif(scenario == "npc_submit"):
		fs.enemySurrendered = true
		fs.checkEnd()
	elif(scenario == "npc_pain"):
		npc.addPain(npc.painThreshold())
		fs.checkEnd()
	elif(scenario == "player_pain"):
		npc.addPain(40)
		thePlayer.addPain(thePlayer.painThreshold())
		fs.checkEnd()
	elif(scenario == "player_lust"):
		thePlayer.addLust(thePlayer.lustThreshold())
		fs.checkEnd()
	elif(scenario == "npc_lust"):
		npc.addLust(npc.lustThreshold())
		fs.checkEnd()
	fs._react("endbattle", [])
	return fs

func outcomesRecorded(npcID) -> int:
	var record = SandboxOverhaulModule.getState().cooldowns.get("combat|" + npcID)
	return int(record[1]) if (record is Array and record.size() > 1) else 0

func resetSandbox():
	SandboxOverhaulModule.getState().clear()
	main.messages.clear()

func makePawns(inter, npcID, npcIsStarter):
	inter.involvedPawns = {"starter": npcID if npcIsStarter else "pc", "reacter": "pc" if npcIsStarter else npcID}
	for role in inter.involvedPawns:
		var p = FakePawn.new()
		p.charID = inter.involvedPawns[role]
		p.pc = (p.charID == "pc")
		inter.pawns[role] = p

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = load("res://Game/MainScene.gd").new()
	GM.main = main
	thePlayer = load("res://Player/Player.gd").new()
	add_child(thePlayer)
	GM.pc = thePlayer
	yield(get_tree(), "idle_frame")
	var rel = SandboxOverhaulModule.getRelationships()
	var combat = SandboxOverhaulModule.getCombat()

	# ---- Interaction fights: scene -> WorldScene -> interaction -> doFightAftermath ----
	# scenario: [outcome, directed fear, directed respect, combat, defiance, defeat kind]
	var table = {
		"player_submit": ["surrender", 0.0, -3.0, -2.0, -6.0, "surrendered"],
		"npc_submit": ["win", 10.0, 6.0, 6.0, 2.0, ""],
		"npc_pain": ["win", 10.0, 6.0, 6.0, 2.0, ""],
		"player_pain": ["loss", 0.0, -2.0, -4.0, 2.0, "resisted"],
		"player_lust": ["loss", 0.0, -5.0, -4.0, 2.0, "resisted"],
		"npc_lust": ["win", 10.0, 6.0, 6.0, 2.0, ""],
	}
	var n = 0
	for scenario in table:
		for playerStarted in [true, false]:
			n += 1
			resetSandbox()
			var npc = addNpc("foe" + str(n))
			var label = scenario + (" (player started)" if playerStarted else " (npc started)")
			var inter = FakeAttack.new()
			makePawns(inter, npc.id, !playerStarted)
			inter.currentActionArgs["fight"] = ["starter", "reacter"]
			var world = FakeWorld.new()
			world.target = inter
			var fs = playScene(scenario, npc, "")
			world._react_scene_end("interaction_fight_pcstarted" if playerStarted else "interaction_fight_pcdef", fs.sceneEndedArgs)
			var entry = table[scenario]
			check(outcomesRecorded(npc.id) == 1, label + ": exactly one outcome recorded, got " + str(outcomesRecorded(npc.id)))
			check(near(combat.getCombatReputation(), entry[3]) and near(combat.getDefiance(), entry[4]), label + ": combat " + str(combat.getCombatReputation()) + " defiance " + str(combat.getDefiance()))
			check(near(rel.getFeeling(npc.id, "pc", "fear"), entry[1]) and near(rel.getFeeling(npc.id, "pc", "respect"), entry[2]), label + ": npc fear " + str(rel.getFeeling(npc.id, "pc", "fear")) + " respect " + str(rel.getFeeling(npc.id, "pc", "respect")))
			check(rel.getFeeling(npc.id, "pc", "affection") == 0.0 and rel.getFeeling(npc.id, "pc", "trust") == 0.0 and !rel.hasRelationship("pc", npc.id), label + ": no hostility, directed npc -> pc only")
			check(inter.sandboxDefeatKind == entry[5], label + ": defeat kind '" + inter.sandboxDefeatKind + "'")
			var repLines = 0
			for m in main.messages:
				if(m.begins_with("Your reputation changed")):
					repLines += 1
			check(repLines == 1, label + ": one reputation message")

	# An NPC submitting is never the player surrendering
	resetSandbox()
	var npcS = addNpc("subber")
	var interS = FakeAttack.new()
	makePawns(interS, npcS.id, false)
	interS.currentActionArgs["fight"] = ["starter", "reacter"]
	var worldS = FakeWorld.new()
	worldS.target = interS
	var fsS = playScene("npc_submit", npcS, "")
	check(fsS.battleSubmitter == "enemy" and fsS.sceneEndedArgs[1] == "surrendered" and fsS.sceneEndedArgs[3] == "enemy", "FightScene reports that the enemy submitted: " + str(fsS.sceneEndedArgs))
	var fsP = playScene("player_submit", addNpc("subber2"), "")
	check(fsP.battleSubmitter == "pc" and fsP.sceneEndedArgs[1] == "submit" and fsP.sceneEndedArgs[3] == "pc", "FightScene reports that the player submitted: " + str(fsP.sceneEndedArgs))
	var fsW = playScene("npc_pain", addNpc("hurt"), "")
	check(fsW.battleSubmitter == "" and fsW.sceneEndedArgs[1] == "pain", "a pain defeat reports no submitter")

	# Loss margin from the real scene: the winner took 40% damage, a clear loss
	resetSandbox()
	var npcM = addNpc("marginfoe")
	var fsM = playScene("player_pain", npcM, "")
	check(near(fsM.battleMargin, 0.4) and fsM.sceneEndedArgs[1] == "pain", "real scene measures the winner's damage: " + str(fsM.battleMargin))

	# ---- Fight Club: the real arena callback in FightScene (battleName "arenafight") ----
	# scenario: [combat, npc respect]
	var arena = {
		"player_submit": [-2.0, 1.0],
		"npc_submit": [3.0, 4.0],
		"npc_pain": [3.0, 4.0],
		"player_pain": [-2.0, 1.0],
		"player_lust": [-2.0, 1.0],
		"npc_lust": [3.0, 4.0],
	}
	for scenario in arena:
		resetSandbox()
		var npc = addNpc("arena" + scenario)
		var label = "arena " + scenario
		var fs = playScene(scenario, npc, "arenafight")
		fs._react("endbattle", []) # a second press must not count again
		check(outcomesRecorded(npc.id) == 1, label + ": exactly one outcome, got " + str(outcomesRecorded(npc.id)))
		check(near(combat.getCombatReputation(), arena[scenario][0]) and combat.getDefiance() == 0.0, label + ": combat " + str(combat.getCombatReputation()) + ", no defiance")
		check(near(rel.getFeeling(npc.id, "pc", "respect"), arena[scenario][1]), label + ": npc respect " + str(rel.getFeeling(npc.id, "pc", "respect")))
		check(rel.getFeeling(npc.id, "pc", "fear") == 0.0 and rel.getFeeling(npc.id, "pc", "affection") == 0.0 and rel.getFeeling(npc.id, "pc", "trust") == 0.0, label + ": no fear, affection or trust")
		check(fs.sandboxReported == true, label + ": reported once by the scene")
	# Other battle names are not Fight Club
	resetSandbox()
	var npcO = addNpc("bulldog")
	var _fsO = playScene("npc_pain", npcO, "bulldog")
	check(outcomesRecorded(npcO.id) == 0 and combat.getCombatReputation() == 0.0, "a non-arena scene fight is left alone by the scene hook")
	# An interaction fight (battle name empty) is reported only through doFightAftermath, never twice
	resetSandbox()
	var npcD = addNpc("dupfoe")
	var interD = FakeAttack.new()
	makePawns(interD, npcD.id, false)
	interD.currentActionArgs["fight"] = ["starter", "reacter"]
	var worldD = FakeWorld.new()
	worldD.target = interD
	var fsD = playScene("npc_pain", npcD, "")
	check(outcomesRecorded(npcD.id) == 0, "before the interaction receives the result nothing is recorded")
	worldD._react_scene_end("interaction_fight_pcstarted", fsD.sceneEndedArgs)
	check(outcomesRecorded(npcD.id) == 1 and near(combat.getCombatReputation(), 6.0), "the interaction fight is recorded once, as hostile (+6, not the Fight Club +3)")

	# ---- The real player-surrender actions each reach the outcome exactly once ----
	resetSandbox()
	var npcG = addNpc("gafoe")
	var ga = FakeAttack.new()
	makePawns(ga, npcG.id, true)
	ga.init_do("surrender", {}, {})
	check(outcomesRecorded(npcG.id) == 1 and near(combat.getDefiance(), -6.0) and near(combat.getCombatReputation(), -2.0), "GenericAttack Surrender: one surrender outcome")
	resetSandbox()
	var npcC = addNpc("cofoe")
	var co = FakeCaught.new()
	co.involvedPawns = {"inmate": "pc", "guard": npcC.id}
	for role in co.involvedPawns:
		var p = FakePawn.new()
		p.charID = co.involvedPawns[role]
		p.pc = (p.charID == "pc")
		co.pawns[role] = p
	co.init_do("surrender", {}, {})
	check(outcomesRecorded(npcC.id) == 1 and near(combat.getDefiance(), -6.0) and co.sandboxDefeatKind == "surrendered", "CaughtOffLimits Surrender by the player inmate: one surrender outcome")
	resetSandbox()
	var co2 = FakeCaught.new()
	co2.involvedPawns = {"inmate": npcC.id, "guard": "pc"}
	for role in co2.involvedPawns:
		var p2 = FakePawn.new()
		p2.charID = co2.involvedPawns[role]
		p2.pc = (p2.charID == "pc")
		co2.pawns[role] = p2
	co2.init_do("surrender", {}, {})
	check(outcomesRecorded(npcC.id) == 0 and combat.getDefiance() == 0.0, "an NPC inmate surrendering is not a player surrender")

	# ---- Defiance cannot be farmed through the real path ----
	resetSandbox()
	var npcF = addNpc("farmfoe")
	for _i in range(4):
		var interF = FakeAttack.new()
		makePawns(interF, npcF.id, false)
		interF.currentActionArgs["fight"] = ["starter", "reacter"]
		var worldF = FakeWorld.new()
		worldF.target = interF
		var fsF = playScene("npc_pain", npcF, "")
		worldF.target = interF
		worldF._react_scene_end("interaction_fight_pcstarted", fsF.sceneEndedArgs)
	check(near(combat.getDefiance(), 2.0 + 3 * 0.5) and near(combat.getCombatReputation(), 6.0), "four fights against one NPC in a day: defiance +2 then +0.5 each, combat only once")

	GM.main = null
	GM.pc = null
	for c in spawned:
		c.free()
	thePlayer.free()
	main.dynamicCharacters.clear()
	main.free()
	print("CombatSceneBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

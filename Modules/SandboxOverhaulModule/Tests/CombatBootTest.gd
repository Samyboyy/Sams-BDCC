extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/CombatBootTest.tscn
# Drives the real GenericAttack and Talking interactions (with stub pawns), the real doFightAftermath, the real attack and punish
# scoring in PawnInteractionBase, the real RelationshipSystem and the real extender save/load. Exits with code 1 on failure.

var failures = 0

class FakePawn:
	var charID = ""
	var pc = false
	var mean = 0.0
	func isPlayer():
		return pc
	func afterWonFight():
		pass
	func afterLostFight():
		pass
	func afterSocialInteraction():
		pass
	func afterFailedSocialInteraction():
		pass
	func addExperienceIfPlayer(_amount):
		pass
	func calculatePowerScore():
		return 1.0
	func isInmate():
		return true
	func addRepScore(_stat, _amount):
		pass
	func scorePersonalityMax(_stats, _minValue = -999.9):
		return mean
	func getAnger():
		return 0.0
	func getSpecialRelationship():
		return GM.main.RS.getSpecialRelationship(charID)

class FakeAttack extends "res://Game/InteractionSystem/Interactions/GenericAttack.gd":
	var pawns = {}
	var eventsSent = []
	func getRolePawn(role:String):
		return pawns[role]
	func sendSocialEvent(_roleActor:String, _roleTarget:String, _eventID:int, _args:Array = []):
		eventsSent.append(_eventID)

class FakeTalking extends "res://Game/InteractionSystem/Interactions/Talking.gd":
	var pawns = {}
	var oldFormulaCalls = []
	var started = []
	func getRolePawn(role:String):
		return pawns[role]
	func startInteraction(interactionID:String, _involvedPawns:Dictionary, _args:Dictionary = {}):
		started.append(interactionID)
	func affectAffection(role1:String, role2:String, howMuch:float):
		oldFormulaCalls.append(["affection", role1, role2, howMuch])

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

func makePawns(inter, npcID, npcIsStarter):
	inter.involvedPawns = {"starter": npcID if npcIsStarter else "pc", "reacter": "pc" if npcIsStarter else npcID}
	for role in inter.involvedPawns:
		var p = FakePawn.new()
		p.charID = inter.involvedPawns[role]
		p.pc = (p.charID == "pc")
		inter.pawns[role] = p

func makeAttack(npcID, npcIsStarter):
	var a = FakeAttack.new()
	makePawns(a, npcID, npcIsStarter)
	a.currentActionArgs["fight"] = ["starter", "reacter"]
	return a

# The scene tells the interaction who won. won is from the starter's point of view.
func sceneResult(inter, playerWon, how, margin = null):
	var result = {"won": (playerWon == (inter.involvedPawns["starter"] == "pc")), "how": how, "submitter": "pc" if how == "submit" else ("enemy" if how == "surrendered" else "")}
	if(margin != null):
		result["margin"] = margin
	inter.receiveSceneStatusFinal(result)

# Real CharacterPawn objects for the scoring functions (they are typed). mean sets the NPC's Mean personality.
func makeScorer(main, npcID, mean):
	var inter = FakeAttack.new()
	inter.involvedPawns = {"starter": npcID, "reacter": "pc"}
	for role in inter.involvedPawns:
		var p = CharacterPawn.new()
		p.charID = inter.involvedPawns[role]
		inter.pawns[role] = p
	main.dynamicCharacters[npcID].getPersonality().setStat(PersonalityStat.Mean, mean)
	inter.currentPawn = "starter"
	inter.directedToPawn = "reacter"
	return inter

func lastMessages(main, count):
	return main.messages.slice(max(0, main.messages.size() - count), main.messages.size())

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	var main = load("res://Game/MainScene.gd").new()
	GM.main = main
	var RS = main.RS
	var npcMap = {}
	for n in ["mae", "kit", "zed", "rin", "tok", "vex", "bo", "cy", "dax", "eli", "fen", "gus", "hal", "ivy"]:
		npcMap[n] = addNpc(main, n)
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var rel = SandboxOverhaulModule.getRelationships()
	var combat = SandboxOverhaulModule.getCombat()

	# ---- Player victory: the real doFightAftermath, both who-started orientations ----
	var a = makeAttack("mae", false)
	sceneResult(a, true, "pain", 0.0)
	check(near(combat.getCombatReputation(), 6) and near(combat.getDefiance(), 2), "win: combat +6, defiance +2")
	check(near(rel.getFeeling("mae", "pc", "fear"), 10) and near(rel.getFeeling("mae", "pc", "respect"), 6), "win: npc fear +10, respect +6 (directed npc -> pc)")
	check(!rel.hasRelationship("pc", "mae"), "win: nothing stored towards the NPC")
	check(a.sandboxDefeatKind == "", "a win sets no defeat kind")
	check(main.messages.size() == 2 and main.messages[0] == "Your reputation changed: [color=green]Combat +6[/color], [color=cyan]Defiance +2[/color]." and main.messages[1] == "mae now sees you differently: [color=green]Respect +6[/color], [color=yellow]Fear +10[/color].", "win: two combined coloured messages: " + str(main.messages))
	# NPC-initiated attack that the player wins: normal victory effects, no hostility
	var a2 = makeAttack("kit", true)
	sceneResult(a2, true, "pain", 0.0)
	check(near(rel.getFeeling("kit", "pc", "fear"), 10) and near(rel.getFeeling("kit", "pc", "respect"), 6) and rel.getFeeling("kit", "pc", "affection") == 0.0 and rel.getFeeling("kit", "pc", "trust") == 0.0, "NPC attacks and the player wins: victory effects, no affection or trust penalty")
	var repAfterTwo = combat.getCombatReputation()
	check(near(repAfterTwo, 12), "a different npc gives full combat reputation")
	var a3 = makeAttack("mae", false)
	var before = combat.getCombatReputation()
	sceneResult(a3, true, "pain", 0.0)
	check(near(combat.getCombatReputation(), before) and near(rel.getFeeling("mae", "pc", "fear"), 12.5), "second win against the same npc the same day: no combat reputation, personal at 25%")

	# ---- Losses: close, clear, crushing, unknown; lust defeat is a loss ----
	var lossCases = [["zed", 0.7, 2.0], ["rin", 0.4, -2.0], ["tok", 0.1, -5.0], ["vex", null, -2.0]]
	for entry in lossCases:
		var _p = rel.setFeeling(entry[0], "pc", "fear", 10)
		var al = makeAttack(entry[0], false)
		var rep0 = combat.getCombatReputation()
		var def0 = combat.getDefiance()
		sceneResult(al, false, "pain", entry[1])
		check(near(combat.getCombatReputation(), rep0 - 4) and near(combat.getDefiance(), def0 + 2), entry[0] + ": loss combat -4, defiance +2")
		check(near(rel.getFeeling(entry[0], "pc", "fear"), 6) and near(rel.getFeeling(entry[0], "pc", "respect"), entry[2]), entry[0] + ": loss fear -4, respect " + str(entry[2]) + ", got " + str(rel.getFeeling(entry[0], "pc", "respect")))
		check(al.sandboxDefeatKind == "resisted", entry[0] + ": a lost fight is resisted, not surrendered")
	var lust = makeAttack("bo", false)
	var defBefore = combat.getDefiance()
	sceneResult(lust, false, "lust", 0.3)
	check(near(combat.getDefiance(), defBefore + 2) and lust.sandboxDefeatKind == "resisted", "lust defeat counts as a lost fight, not a surrender")

	# ---- Voluntary surrender: in the fight scene, and before any fight ----
	var sub1 = makeAttack("cy", true)
	var rep1 = combat.getCombatReputation()
	var def1 = combat.getDefiance()
	sceneResult(sub1, false, "submit", 0.5)
	check(near(combat.getCombatReputation(), rep1 - 2) and near(combat.getDefiance(), def1 - 6), "submit in a fight: combat -2, defiance -6")
	check(rel.getFeeling("cy", "pc", "fear") == 0.0 and near(rel.getFeeling("cy", "pc", "respect"), -3), "submit: npc fear -5 (clamped) and respect -3")
	check(sub1.sandboxDefeatKind == "surrendered", "submit sets the surrendered kind")
	var sur = makeAttack("dax", true)
	sur.init_do("surrender", {}, {})
	check(near(rel.getFeeling("dax", "pc", "respect"), -3) and sur.sandboxDefeatKind == "surrendered", "player picks Surrender before any fight: surrender outcome")
	var npcSur = makeAttack("eli", false)
	var repN = combat.getCombatReputation()
	npcSur.init_do("surrender", {}, {})
	check(near(combat.getCombatReputation(), repN) and !rel.hasRelationship("eli", "pc") and npcSur.sandboxDefeatKind == "", "an NPC surrendering to the player changes nothing here")
	var def2 = combat.getDefiance()
	var sur2 = makeAttack("dax", true)
	sur2.init_do("surrender", {}, {})
	check(near(combat.getDefiance(), def2 - 1.5) and near(rel.getFeeling("dax", "pc", "respect"), -3.75), "second surrender to the same npc today: defiance at 25%, personal at 25%")

	# ---- Player-initiated attack (Talking) and NPC-initiated attack ----
	var ta = FakeTalking.new()
	makePawns(ta, "fen", false)
	ta.init_do("attack", {}, {})
	check(near(rel.getFeeling("fen", "pc", "affection"), -5) and near(rel.getFeeling("fen", "pc", "trust"), -8) and near(rel.getFeeling("fen", "pc", "fear"), 3), "player attacks: affection -5, trust -8, fear +3")
	check(ta.started.has("GenericAttack") and ta.oldFormulaCalls.size() == 1, "the vanilla attack and its legacy affection change still run")
	var tn = FakeTalking.new()
	makePawns(tn, "gus", true)
	tn.init_do("attack", {}, {})
	check(!rel.hasRelationship("gus", "pc"), "NPC attacks the player: no hostility penalty for defending")

	# ---- Fight Club (consensual) ----
	var repC = combat.getCombatReputation()
	var defC = combat.getDefiance()
	module.onFightSceneEnded("hal", "win", "pain", "arenafight")
	check(near(combat.getCombatReputation(), repC + 3) and near(combat.getDefiance(), defC) and near(rel.getFeeling("hal", "pc", "respect"), 4), "fight club win: combat +3, respect +4, no defiance")
	check(rel.getFeeling("hal", "pc", "fear") == 0.0 and rel.getFeeling("hal", "pc", "affection") == 0.0 and rel.getFeeling("hal", "pc", "trust") == 0.0, "fight club: no fear, affection or trust")
	module.onFightSceneEnded("ivy", "lost", "pain", "arenafight")
	check(near(combat.getCombatReputation(), repC + 1) and near(rel.getFeeling("ivy", "pc", "respect"), 1), "fight club loss: combat -2, respect +1")
	var repX = combat.getCombatReputation()
	module.onFightSceneEnded("hal", "win", "pain", "")
	module.onFightSceneEnded("hal", "win", "pain", "bulldog")
	check(near(combat.getCombatReputation(), repX), "other scene fights are left alone")

	# ---- Attack scoring through the real PawnInteractionBase ----
	npcMap["npcS"] = addNpc(main, "npcS")
	var scorer = makeScorer(main, "npcS", 0.5)
	var base = 0.5
	var _f = rel.setFeeling("npcS", "pc", "fear", 0)
	combat.addRep("combat", -combat.getCombatReputation())
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base), "attack score baseline")
	combat.addRep("combat", -100)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * 1.5), "combat -100: 1.5x, applied once")
	combat.addRep("combat", 200)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * 0.5), "combat +100: 0.5x, applied once")
	combat.addRep("combat", -100)
	_f = rel.setFeeling("npcS", "pc", "fear", 50)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * 0.55), "fear 50: 0.55x")
	_f = rel.setFeeling("npcS", "pc", "fear", 100)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * 0.1), "fear 100: 0.1x")
	check(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}) > 0.0, "never exactly zero")
	_f = rel.setFeeling("npcS", "pc", "fear", 0)
	check(near(scorer.getScoreTypeValueGeneric("attack", scorer.pawns["starter"], scorer.pawns["reacter"]), base), "public scoring path agrees: one multiplier, not two")
	# Other score types and other targets are untouched
	combat.addRep("combat", 100)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "default"}), 1.0), "default score type untouched")
	combat.addRep("combat", -100)

	# ---- Nemesis stays hostile but becomes reluctant after repeated losses ----
	npcMap["nem"] = addNpc(main, "nem")
	RS.startSpecialRelantionship("Nemesis", "nem")
	check(RS.hasSpecialRelationshipID("nem", "Nemesis"), "setup: Nemesis")
	var nemScorer = makeScorer(main, "nem", 0.5)
	var hostile = nemScorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"})
	check(near(hostile, base * 3.0), "a Nemesis who has no reason to be afraid keeps its (x3) interest: " + str(hostile))
	var dayBase = main.currentDay
	for day in range(1, 11):
		main.currentDay = dayBase + day
		sceneResult(makeAttack("nem", true), true, "pain", 0.0)
	check(near(rel.getFeeling("nem", "pc", "fear"), 100.0), "ten daily defeats push the Nemesis's fear to 100")
	var reluctant = nemScorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"})
	check(reluctant < hostile * 0.2 and reluctant > 0.0 and RS.hasSpecialRelationshipID("nem", "Nemesis"), "still a Nemesis, but far less willing to start a fight it keeps losing: " + str(reluctant))

	# ---- Aftermath weighting ----
	npcMap["npcP"] = addNpc(main, "npcP")
	var punishBase = {}
	for kind in ["", "resisted", "surrendered"]:
		var w = makeScorer(main, "npcP", 0.0)
		w.sandboxDefeatKind = kind
		punishBase[kind] = [w.calcFinalActionScore({"score": 1.0, "scoreType": "punish"}), w.calcFinalActionScore({"score": 1.0, "scoreType": "punishMean"}), w.calcFinalActionScore({"score": 1.0, "scoreType": "default"})]
	check(near(punishBase["resisted"][0], punishBase[""][0] * 1.25) and near(punishBase["resisted"][1], punishBase[""][1] * 1.25), "resisted loss: punishments x1.25")
	check(near(punishBase["surrendered"][0], punishBase[""][0] * 0.65) and near(punishBase["surrendered"][1], punishBase[""][1] * 0.65), "surrender: punishments x0.65")
	check(near(punishBase["resisted"][2], 1.0) and near(punishBase["surrendered"][2], 1.0), "Leave and other options are not scaled directly")
	check(punishBase["surrendered"][0] < punishBase[""][0] and punishBase["resisted"][0] > punishBase[""][0], "relative chance of leaving rises after surrender")
	# The real flow sets the kind that the scoring reads
	var flow = makeAttack("npcF", false)
	sceneResult(flow, false, "pain", 0.2)
	check(flow.sandboxDefeatKind == "resisted", "real resisted loss sets the kind")
	var flow2 = makeAttack("npcF2", false)
	sceneResult(flow2, false, "submit", 0.2)
	check(flow2.sandboxDefeatKind == "surrendered", "real submit sets the kind")
	var flow3 = makeAttack("npcF3", false)
	sceneResult(flow3, true, "pain", 0.2)
	check(flow3.sandboxDefeatKind == "", "a win leaves it unset")
	var savedAttack = flow.saveData()
	var loadedAttack = FakeAttack.new()
	loadedAttack.loadData(savedAttack)
	check(loadedAttack.sandboxDefeatKind == "resisted", "the defeat kind survives the interaction's own save and load")

	# ---- Save, load, reset, prune ----
	var repSaved = combat.getCombatReputation()
	var defSaved = combat.getDefiance()
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	check(saved["extendersData"]["SandboxGameExtender"]["reputation"].has("combat") and saved["extendersData"]["SandboxGameExtender"]["cooldowns"].has("combat|mae"), "reputation and daily records are saved")
	SandboxOverhaulModule.getState().cooldowns.clear()
	SandboxOverhaulModule.getState().reputation = {"combat": 0.0, "defiance": 0.0}
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(near(SandboxOverhaulModule.getCombat().getCombatReputation(), repSaved) and near(SandboxOverhaulModule.getCombat().getDefiance(), defSaved), "reputation survives save and load")
	var blocked = module.runCombatOutcome("nem", "win")
	check(blocked["reputation"].get("combat", 0.0) == 0.0, "the daily record survives save and load")
	module.runCombatOutcome("ghost9", "win")
	check(SandboxOverhaulModule.getState().cooldowns.has("combat|ghost9"), "setup: unknown character record")
	var _s = GM.GES.saveData()
	check(!SandboxOverhaulModule.getState().cooldowns.has("combat|ghost9") and SandboxOverhaulModule.getState().cooldowns.has("combat|mae"), "saving prunes records of characters that no longer exist")
	var main2 = load("res://Game/MainScene.gd").new()
	GM.main = main2
	check(SandboxOverhaulModule.getCombat().getCombatReputation() == 0.0 and SandboxOverhaulModule.getCombat().getDefiance() == 0.0 and SandboxOverhaulModule.getState().cooldowns.empty(), "a new game resets reputation and records")

	# ---- UI text ----
	check(module.getReputationText() == "Combat Reputation: 0 — Unproven\nHow capable and dangerous the prison believes you are in a fight.\n\nDefiance: 0 — Unpredictable\nHow willing the prison believes you are to resist coercion.", "reputation screen text: " + module.getReputationText())

	GM.main = null
	for n in npcMap:
		npcMap[n].free()
	main.dynamicCharacters.clear()
	main.free()
	main2.free()
	print("CombatBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

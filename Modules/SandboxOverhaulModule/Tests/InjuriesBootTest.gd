extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/InjuriesBootTest.tscn
# Real path: a real FightScene with a real Player and real DynamicCharacters, the real endbattle action, the real status effects and buff
# calculations, the real hour hook, the real extender save/load and the real medbay scene actions. Exits with code 1 on failure.

var failures = 0

class FakeFight extends "res://Scenes/FightScene.gd":
	func endScene(result = []):
		sceneEndedFlag = true
		sceneEndedArgs = result

# Characters whose injury-free maximum stamina is not 100.
class BigNpc extends DynamicCharacter:
	var baseMax = 100
	func getBaseMaxStamina() -> int:
		return baseMax

class BigPlayer extends "res://Player/Player.gd":
	var baseMax = 100
	func getBaseMaxStamina() -> int:
		return baseMax

class FakeAttack extends "res://Game/InteractionSystem/Interactions/GenericAttack.gd":
	var pawns = {}
	func getRolePawn(role:String):
		return pawns[role]

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

var main = null
var thePlayer = null
var spawned = []
var injuries = null
var module = null

func addNpc(npcID):
	var c = DynamicCharacter.new()
	c.id = npcID
	c.name = npcID
	c.npcName = npcID
	c.lustInterests = LustInterests.new()
	c.personality = Personality.new()
	add_child(c)
	main.dynamicCharacters[npcID] = c
	spawned.append(c)
	return c

func resetPlayer():
	thePlayer.addPain(-thePlayer.getPain())
	thePlayer.addLust(-thePlayer.getLust())

func clearPlayerInjuries():
	for type in ["arm", "leg", "trauma"]:
		injuries.remove("pc", type)
	module.refreshInjuryEffects("pc")

func fightMessages():
	var out = []
	for m in main.messages:
		if(m.find("injured") != -1 or m.find("worsened") != -1 or m.find("healed") != -1 or m.find("aggravated") != -1):
			out.append(m)
	return out

# playerPain / enemyPain are percentages of the threshold. Ends the fight through the real endbattle action.
func runFight(npc, playerPain, enemyPain, battleName, how = ""):
	resetPlayer()
	var fs = FakeFight.new()
	fs.enemyID = npc.id
	fs.enemyCharacter = npc
	fs.battleName = battleName
	thePlayer.addPain(playerPain)
	npc.addPain(enemyPain)
	if(how == "submit"):
		fs._react("submit", [])
	elif(how == "npc_submit"):
		fs.enemySurrendered = true
		fs.checkEnd()
	elif(how == "player_lust"):
		thePlayer.addLust(thePlayer.lustThreshold())
		fs.checkEnd()
	else:
		fs.checkEnd()
	fs._react("endbattle", [])
	return fs

func makeScorer(npcID, mean):
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

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	main = load("res://Game/MainScene.gd").new()
	GM.main = main
	thePlayer = load("res://Player/Player.gd").new()
	add_child(thePlayer)
	GM.pc = thePlayer
	yield(get_tree(), "idle_frame")
	module = GlobalRegistry.getModule("SandboxOverhaulModule")
	injuries = SandboxOverhaulModule.getInjuries()
	var baseStamina = thePlayer.getMaxStamina()
	var baseDodge = thePlayer.getDodgeChance()
	check(baseStamina == 100, "setup: base maximum stamina is 100, got " + str(baseStamina))

	# ---- Injuries from real fights ----
	var foe1 = addNpc("foe1")
	var fs = runFight(foe1, 65, 100, "", "")
	check(injuries.getSeverity("pc", "trauma") == 2 and injuries.getSeverity("foe1", "trauma") == 3, "a close win (65% pain) is moderate, the beaten enemy at 100% is severe: " + str(injuries.getAll("pc")) + " / " + str(injuries.getAll("foe1")))
	check(fightMessages().size() == 1 and fightMessages()[0] == "[color=orange]You were injured: Moderate Body Trauma. Physical damage received +20%.[/color]", "one combined message: " + str(fightMessages()))
	check(thePlayer.hasEffect("SandboxBodyTrauma") and foe1.hasEffect("SandboxBodyTrauma"), "both characters get the status effect")
	fs._react("endbattle", [])
	check(injuries.getSeverity("pc", "trauma") == 2 and fightMessages().size() == 1, "pressing end battle twice does not injure twice")

	# Lust alone, surrender, arena, and below threshold
	clearPlayerInjuries()
	main.messages.clear()
	runFight(addNpc("foe2"), 20, 0, "", "player_lust")
	check(!injuries.has("pc", "trauma") and fightMessages().empty(), "a lust defeat with 20% pain: no injury")
	runFight(addNpc("foe3"), 34, 0, "", "")
	check(!injuries.has("pc", "trauma"), "34% pain: no injury")
	runFight(addNpc("foe4"), 35, 0, "", "")
	check(injuries.getSeverity("pc", "trauma") == 1, "35% pain: minor")
	clearPlayerInjuries()
	runFight(addNpc("foe5"), 70, 0, "", "player_lust")
	check(injuries.getSeverity("pc", "trauma") == 2, "a lust defeat with 70% pain still injures")
	clearPlayerInjuries()
	runFight(addNpc("foe6"), 50, 0, "", "submit")
	check(injuries.getSeverity("pc", "trauma") == 1, "submitting after 50% pain keeps that damage")
	clearPlayerInjuries()
	runFight(addNpc("foe7"), 0, 0, "", "submit")
	check(!injuries.has("pc", "trauma"), "submitting without damage: no injury")
	clearPlayerInjuries()
	var npcSurrender = addNpc("foe8")
	runFight(npcSurrender, 40, 30, "", "npc_submit")
	check(injuries.getSeverity("pc", "trauma") == 1 and !injuries.has("foe8", "trauma"), "NPC submission: the player's own damage still counts, the NPC took 30%")
	clearPlayerInjuries()
	runFight(addNpc("arena1"), 90, 0, "arenafight", "")
	check(injuries.getSeverity("pc", "trauma") == 2, "arena: severe damage becomes a moderate injury")
	clearPlayerInjuries()
	runFight(addNpc("arena2"), 65, 0, "arenafight", "")
	check(injuries.getSeverity("pc", "trauma") == 1, "arena: moderate becomes minor")
	clearPlayerInjuries()
	runFight(addNpc("arena3"), 40, 0, "arenafight", "")
	check(!injuries.has("pc", "trauma"), "arena: minor becomes nothing")

	# Reinjury through real fights, one message each
	clearPlayerInjuries()
	main.messages.clear()
	runFight(addNpc("re1"), 40, 0, "", "")
	runFight(addNpc("re2"), 40, 0, "", "")
	check(injuries.getSeverity("pc", "trauma") == 2 and near(injuries.getRemainingHours("pc", "trauma"), 72.0), "second fight escalates minor to moderate and resets to 72 hours")
	var msgs = fightMessages()
	check(msgs.size() == 2 and msgs[1] == "[color=red]Your Body Trauma worsened from Minor to Moderate.[/color]", "worsened message: " + str(msgs))
	runFight(addNpc("re3"), 40, 0, "", "")
	runFight(addNpc("re4"), 40, 0, "", "")
	check(injuries.getSeverity("pc", "trauma") == 3 and near(injuries.getRemainingHours("pc", "trauma"), 120.0), "severe after two more")

	# ---- Penalties from the real calculations, once each ----
	clearPlayerInjuries()
	var physOut = thePlayer.getDamageMultiplier(DamageType.Physical)
	var lustOut = thePlayer.getDamageMultiplier(DamageType.Lust)
	var physIn = thePlayer.getRecieveDamageMultiplier(DamageType.Physical)
	var lustIn = thePlayer.getRecieveDamageMultiplier(DamageType.Lust)
	injuries.applyInjury("pc", "arm", 2)
	module.refreshInjuryEffects("pc")
	check(near(thePlayer.getDamageMultiplier(DamageType.Physical), physOut - 0.2), "arm injury moderate: physical damage dealt -20% exactly once: " + str(thePlayer.getDamageMultiplier(DamageType.Physical) - physOut))
	check(near(thePlayer.getDamageMultiplier(DamageType.Lust), lustOut) and near(thePlayer.getRecieveDamageMultiplier(DamageType.Physical), physIn) and near(thePlayer.getMaxStamina(), baseStamina), "arm injury changes nothing else")
	module.refreshInjuryEffects("pc")
	module.refreshInjuryEffects("pc")
	check(near(thePlayer.getDamageMultiplier(DamageType.Physical), physOut - 0.2), "refreshing again does not stack it")
	injuries.applyInjury("pc", "trauma", 3)
	module.refreshInjuryEffects("pc")
	check(near(thePlayer.getRecieveDamageMultiplier(DamageType.Physical), physIn + 0.3) and near(thePlayer.getRecieveDamageMultiplier(DamageType.Lust), lustIn), "body trauma severe: physical damage received +30%, lust unaffected")
	check(near(thePlayer.getDamageMultiplier(DamageType.Physical), physOut - 0.2), "the two injuries each apply to their own mechanic")
	var dealt = thePlayer.receiveDamage(DamageType.Physical, 10)
	check(dealt == 13, "10 physical damage becomes 13 with severe body trauma: " + str(dealt))
	thePlayer.addPain(-thePlayer.getPain())
	injuries.remove("pc", "trauma")
	injuries.remove("pc", "arm")
	module.refreshInjuryEffects("pc")
	check(thePlayer.receiveDamage(DamageType.Physical, 10) == 10 and near(thePlayer.getDamageMultiplier(DamageType.Physical), physOut), "healed: penalties gone")
	thePlayer.addPain(-thePlayer.getPain())

	# Leg injury: a percentage of the real injury-free maximum stamina
	thePlayer.addStamina(1000)
	check(thePlayer.getStamina() == baseStamina, "setup: full stamina")
	injuries.applyInjury("pc", "leg", 2)
	module.refreshInjuryEffects("pc")
	check(thePlayer.getMaxStamina() == 80, "leg injury moderate at base 100: maximum stamina 80: " + str(thePlayer.getMaxStamina()))
	check(thePlayer.getStamina() == 80, "current stamina is clamped to the new maximum: " + str(thePlayer.getStamina()))
	module.refreshInjuryEffects("pc")
	module.refreshInjuryEffects("pc")
	check(thePlayer.getMaxStamina() == 80, "refreshing again does not stack it")
	injuries.applyInjury("pc", "leg", 1)
	module.refreshInjuryEffects("pc")
	check(thePlayer.getMaxStamina() == 70, "reinjured to severe at base 100: 70")
	injuries.remove("pc", "leg")
	module.refreshInjuryEffects("pc")
	check(thePlayer.getMaxStamina() == 100 and thePlayer.getStamina() == 70, "healed leg: the maximum is 100 again and current stamina is not changed")
	thePlayer.addStamina(1000)
	check(thePlayer.getStamina() == 100, "and it can fill up to the restored maximum")
	check(thePlayer.getBuffsHolder().getExtraStamina() == 0, "no flat stamina buff is used")

	# Other base maximums, player and npc, every severity
	var bigPlayer = BigPlayer.new()
	add_child(bigPlayer)
	var bigNpc = BigNpc.new()
	bigNpc.id = "bignpc"
	bigNpc.name = "bignpc"
	bigNpc.npcName = "bignpc"
	add_child(bigNpc)
	main.dynamicCharacters["bignpc"] = bigNpc
	spawned.append(bigNpc)
	yield(get_tree(), "idle_frame")
	var staminaCases = [[100, 1, 90], [100, 2, 80], [100, 3, 70], [150, 1, 135], [150, 2, 120], [150, 3, 105], [200, 1, 180], [200, 2, 160], [200, 3, 140], [155, 1, 140]]
	for entry in staminaCases:
		bigPlayer.baseMax = entry[0]
		bigNpc.baseMax = entry[0]
		check(bigPlayer.getMaxStamina() == entry[0] and bigNpc.getMaxStamina() == entry[0], "healthy base " + str(entry[0]))
		injuries.applyInjury("pc", "leg", entry[1])
		injuries.applyInjury("bignpc", "leg", entry[1])
		check(bigPlayer.getMaxStamina() == entry[2], "player base " + str(entry[0]) + " severity " + str(entry[1]) + " -> " + str(entry[2]) + ", got " + str(bigPlayer.getMaxStamina()))
		check(bigNpc.getMaxStamina() == entry[2], "npc base " + str(entry[0]) + " severity " + str(entry[1]) + " -> " + str(entry[2]) + ", got " + str(bigNpc.getMaxStamina()))
		injuries.remove("pc", "leg")
		injuries.remove("bignpc", "leg")
		check(bigPlayer.getMaxStamina() == entry[0] and bigNpc.getMaxStamina() == entry[0], "healing restores base " + str(entry[0]))
	# Escalation, clamping and healing at base 150
	bigPlayer.baseMax = 150
	bigPlayer.addStamina(1000)
	check(bigPlayer.getStamina() == 150, "setup: big player full stamina")
	injuries.applyInjury("pc", "leg", 1)
	check(bigPlayer.getMaxStamina() == 135, "minor at 150: 135")
	bigPlayer.addStamina(0)
	check(bigPlayer.getStamina() == 135, "current stamina clamps when the maximum falls (150 -> 135)")
	injuries.applyInjury("pc", "leg", 1)
	check(bigPlayer.getMaxStamina() == 120, "worsened to moderate at 150: 120")
	injuries.remove("pc", "leg")
	check(bigPlayer.getMaxStamina() == 150 and bigPlayer.getStamina() <= bigPlayer.getMaxStamina(), "healed: maximum back to 150 safely")
	# Treatment restores the right maximum (150 base, through the real scene action)
	injuries.applyInjury("pc", "leg", 2)
	check(bigPlayer.getMaxStamina() == 120, "setup: moderate at 150")
	thePlayer.addCredits(100 - thePlayer.getCredits())
	var treatScene = load("res://Modules/MedicalModule/ElizaTalkScene.gd").new()
	treatScene._react("injuryPay", ["leg"])
	check(!injuries.has("pc", "leg") and bigPlayer.getMaxStamina() == 150 and thePlayer.getCredits() == 97, "treatment removes the injury and restores 150")
	bigPlayer.free()

	# Dodge: a percentage of the final chance, at low, medium and high base chances
	var dodgeCases = [[0.05, 0.9], [0.05, 0.8], [0.05, 0.7], [0.3, 0.9], [0.3, 0.8], [0.3, 0.7], [0.8, 0.9], [0.8, 0.8], [0.8, 0.7]]
	var severityFor = {0.9: 1, 0.8: 2, 0.7: 3}
	for entry in dodgeCases:
		thePlayer.initialDodgeChance = entry[0]
		var healthyDodge = thePlayer.getDodgeChance()
		injuries.applyInjury("pc", "leg", severityFor[entry[1]])
		var injuredDodge = thePlayer.getDodgeChance()
		check(near(injuredDodge, healthyDodge * entry[1]), "dodge " + str(healthyDodge) + " x" + str(entry[1]) + " = " + str(healthyDodge * entry[1]) + ", got " + str(injuredDodge))
		injuries.remove("pc", "leg")
		check(near(thePlayer.getDodgeChance(), healthyDodge), "healed: dodge back to " + str(healthyDodge))
	thePlayer.initialDodgeChance = 0.0
	injuries.applyInjury("pc", "leg", 3)
	check(near(thePlayer.getDodgeChance(), 0.0), "zero dodge stays zero (never negative)")
	injuries.remove("pc", "leg")
	thePlayer.initialDodgeChance = 0.05
	injuries.applyInjury("pc", "leg", 2)
	check(near(thePlayer.getDodgeChance(), baseDodge * 0.8) and thePlayer.getMaxStamina() == 80, "stamina and dodge both apply, each once")
	check(thePlayer.getDodgeChance() > 0.0, "dodge stays positive")
	injuries.remove("pc", "leg")
	module.refreshInjuryEffects("pc")

	# Status text matches the mechanics exactly
	injuries.applyInjury("pc", "leg", 2)
	module.refreshInjuryEffects("pc")
	var legText = thePlayer.getEffect("SandboxLegInjury").getVisisbleDescription()
	check(legText.find("Maximum stamina -20%, dodge chance -20%") != -1 and legText.find("Extra stamina") == -1, "leg status text states the real percentages: " + legText)
	injuries.remove("pc", "leg")
	module.refreshInjuryEffects("pc")

	# NPC parity
	var npc = addNpc("parity")
	var npcMax = npc.getMaxStamina()
	var npcOut = npc.getDamageMultiplier(DamageType.Physical)
	var npcIn = npc.getRecieveDamageMultiplier(DamageType.Physical)
	injuries.applyInjury("parity", "arm", 3)
	injuries.applyInjury("parity", "leg", 1)
	injuries.applyInjury("parity", "trauma", 2)
	module.refreshInjuryEffects("parity")
	check(near(npc.getDamageMultiplier(DamageType.Physical), npcOut - 0.3) and npc.getMaxStamina() == npcMax - 10 and near(npc.getRecieveDamageMultiplier(DamageType.Physical), npcIn + 0.2), "an injured NPC gets the same penalties")

	# ---- Status text ----
	injuries.applyInjury("pc", "trauma", 2)
	injuries.applyInjury("pc", "arm", 2)
	module.refreshInjuryEffects("pc")
	var effect = thePlayer.getEffect("SandboxArmInjury")
	check(effect.getEffectName() == "Moderate Arm Injury", "status name: " + effect.getEffectName())
	var description = effect.getVisisbleDescription()
	check(description.find("about 3 days remaining") != -1 and description.find("Physical damage -20%") != -1, "status text shows the time and the exact penalty: " + description)
	var traumaDescription = thePlayer.getEffect("SandboxBodyTrauma").getVisisbleDescription()
	check(traumaDescription.find("Received physical damage +20%") != -1, "trauma status text: " + traumaDescription)

	# ---- Hourly recovery through the real hooks ----
	clearPlayerInjuries()
	main.messages.clear()
	injuries.applyInjury("pc", "arm", 1)
	injuries.applyInjury("pc", "trauma", 2)
	module.refreshInjuryEffects("pc")
	main.hoursPassed(3)
	check(near(injuries.getRemainingHours("pc", "arm"), 21.0) and near(injuries.getRemainingHours("pc", "trauma"), 69.0), "the real hour processing heals three hours: " + str(injuries.getRemainingHours("pc", "arm")))
	check(near(injuries.getRemainingHours("foe1", "trauma"), 117.0), "npc injuries heal too, even without being simulated")
	main.hoursPassed(21)
	check(!injuries.has("pc", "arm") and !thePlayer.hasEffect("SandboxArmInjury") and thePlayer.hasEffect("SandboxBodyTrauma"), "the minor injury heals at 24 hours and its status effect goes")
	var healed = 0
	for m in main.messages:
		if(m == "[color=green]Your Arm Injury has healed.[/color]"):
			healed += 1
	check(healed == 1, "one healed message")
	main.hoursPassed(60)
	check(!injuries.has("pc", "trauma") and !thePlayer.hasEffect("SandboxBodyTrauma"), "a 60 hour skip finishes the moderate injury (72 hours)")

	# ---- Save, load, prune ----
	injuries.applyInjury("pc", "leg", 3)
	injuries.applyInjury("ghost", "arm", 1)
	main.hoursPassed(5)
	var remaining = injuries.getRemainingHours("pc", "leg")
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	var savedInjuries = saved["extendersData"]["SandboxGameExtender"]["injuries"]
	check(savedInjuries.has("pc") and !savedInjuries.has("ghost") and savedInjuries.has("foe1"), "deleted characters are pruned before saving: " + str(savedInjuries.keys()))
	check(saved["extendersData"]["SandboxGameExtender"]["schema_version"] == 4, "saved with schema 4")
	injuries.remove("pc", "leg")
	GM.GES.loadData(JSON.parse(JSON.print(saved)).result)
	check(injuries.getSeverity("pc", "leg") == 3 and near(injuries.getRemainingHours("pc", "leg"), remaining), "load keeps the exact remaining hours: " + str(injuries.getRemainingHours("pc", "leg")))
	check(thePlayer.getMaxStamina() == 70, "after load the severe leg injury still scales the maximum: " + str(thePlayer.getMaxStamina()))
	injuries.remove("pc", "leg")

	# ---- Medical treatment through the real scene actions ----
	clearPlayerInjuries()
	var scene = load("res://Modules/MedicalModule/ElizaTalkScene.gd").new()
	thePlayer.addCredits(-thePlayer.getCredits())
	check(module.getTreatmentOptions().empty(), "no injuries: nothing to treat")
	scene._react("injuryPay", ["arm"])
	check(scene.state == "injuryResult" and scene.sandboxInjuryResult["reason"] == "none" and thePlayer.getCredits() == 0, "no-injury treatment charges nothing")
	check(module.describeTreatmentResult(scene.sandboxInjuryResult) == "That injury is already gone. Nothing was charged.", "no-injury text")
	injuries.applyInjury("pc", "arm", 2)
	injuries.applyInjury("pc", "trauma", 3)
	injuries.applyInjury("pc", "leg", 1)
	module.refreshInjuryEffects("pc")
	var options = module.getTreatmentOptions()
	check(options.size() == 3 and options[0]["cost"] == 3 and options[1]["cost"] == 2 and options[2]["cost"] == 6, "every injury is listed with its price: " + str(options))
	check(options[0]["text"] == "Moderate Arm Injury - Physical damage -20% - about 3 days remaining. Treatment: 3 credits.", "option text: " + options[0]["text"])
	thePlayer.addCredits(1)
	scene._react("injuryAsk", ["arm"])
	check(scene.state == "injuryConfirm" and scene.sandboxInjuryPick == "arm" and thePlayer.getCredits() == 1, "asking charges nothing and waits for confirmation")
	scene._react("injuryPay", ["arm"])
	check(injuries.has("pc", "arm") and thePlayer.getCredits() == 1 and scene.sandboxInjuryResult["missing"] == 2 and scene.sandboxInjuryResult["cost"] == 3, "cannot afford: nothing charged, nothing removed, missing 2")
	check(module.describeTreatmentResult(scene.sandboxInjuryResult).find("2 short") != -1 and module.describeTreatmentResult(scene.sandboxInjuryResult).find("Nothing was charged") != -1, "the shortfall is explained")
	thePlayer.addCredits(10)
	thePlayer.addStamina(1000)
	scene._react("injuryPay", ["leg"])
	check(!injuries.has("pc", "leg") and injuries.has("pc", "arm") and injuries.has("pc", "trauma") and thePlayer.getCredits() == 9, "treating the leg takes 2 credits and leaves the other injuries")
	check(thePlayer.getMaxStamina() == baseStamina and thePlayer.getStamina() <= thePlayer.getMaxStamina() and !thePlayer.hasEffect("SandboxLegInjury"), "treated leg: stamina back, effect gone")
	check(module.describeTreatmentResult(scene.sandboxInjuryResult) == "[color=green]Your Minor Leg Injury was treated for 2 credits.[/color]", "success text")
	scene._react("injuryPay", ["trauma"])
	check(thePlayer.getCredits() == 3 and !injuries.has("pc", "trauma") and injuries.has("pc", "arm"), "severe body trauma costs 6")
	scene._react("injuryPay", ["trauma"])
	check(thePlayer.getCredits() == 3, "treating an injury that is already gone charges nothing")

	# ---- Targeting through the real attack score ----
	clearPlayerInjuries()
	npcSurrender = addNpc("npcS")
	SandboxOverhaulModule.getCombat().addRep("combat", -SandboxOverhaulModule.getCombat().getCombatReputation())
	var scorer = makeScorer("npcS", 0.5)
	var base = scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"})
	check(near(base, 0.5), "attack score baseline: " + str(base))
	var expected = {1: 1.1, 2: 1.25, 3: 1.4}
	for severity in expected:
		injuries.applyInjury("pc", "arm", severity)
		check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * expected[severity]), "severity " + str(severity) + ": attack interest x" + str(expected[severity]) + ", applied once")
		injuries.remove("pc", "arm")
	injuries.applyInjury("pc", "arm", 3)
	injuries.applyInjury("pc", "leg", 1)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * 1.4), "several injuries use only the highest")
	SandboxOverhaulModule.getCombat().addRep("combat", -100)
	check(near(scorer.calcFinalActionScore({"score": 1.0, "scoreType": "attack"}), base * 1.75), "weak reputation and a severe injury hit the 1.75x cap")
	SandboxOverhaulModule.getCombat().addRep("combat", 100)
	injuries.remove("pc", "arm")
	injuries.remove("pc", "leg")

	# ---- Reset between games ----
	injuries.applyInjury("pc", "arm", 1)
	var main2 = load("res://Game/MainScene.gd").new()
	GM.main = main2
	check(!SandboxOverhaulModule.getInjuries().has("pc", "arm") and SandboxOverhaulModule.getState().injuries.empty(), "a new game starts with no injuries")

	GM.main = null
	GM.pc = null
	for c in spawned:
		c.free()
	thePlayer.free()
	main.dynamicCharacters.clear()
	main.free()
	main2.free()
	print("InjuriesBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/SexAftermathBootTest.tscn
# Drives Module.onSexAftermath, the function PawnInteractionBase.doSexAftermath calls, with the real RelationshipSystem.
# Exits with code 1 on failure.

var failures = 0

class FakeInteraction:
	var id = ""
	var state = ""
	var roles = {}
	func getState():
		return state
	func getRoleID(role):
		return roles.get(role, "")

class FakeResult:
	var domSat = 0.5
	var subSat = 0.5
	func getAverageDomSatisfaction():
		return domSat
	func getAverageSubSatisfaction():
		return subSat

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func makeInteraction(interactionID, stateID, dom, sub):
	var i = FakeInteraction.new()
	i.id = interactionID
	i.state = stateID
	i.roles = {"dom": dom, "sub": sub}
	return i

func makeResult(domSat, subSat):
	var r = FakeResult.new()
	r.domSat = domSat
	r.subSat = subSat
	return r

func addNpc(main, npcID, npcName):
	var c = DynamicCharacter.new()
	c.id = npcID
	c.name = npcName
	main.dynamicCharacters[npcID] = c
	return c

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")

	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var main = load("res://Game/MainScene.gd").new()
	GM.main = main
	var RS = main.RS
	var npcs = []
	for n in ["npcForced", "npcCoerced", "npcFriend", "npcNear", "npcUnknown", "npcGood", "npcPoor", "npcPcVictim", "npcFriend2"]:
		npcs.append(addNpc(main, n, n))
	var rel = SandboxOverhaulModule.getRelationships()
	var sexData = ["dom", "sub"]

	# Forced, very satisfied: legacy affection must go down, never up, and the new axes go negative.
	var runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "grabbed_about_to_fuck", "pc", "npcForced"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false, "forced suppresses the vanilla aftermath")
	check(near(RS.getAffection("npcForced", "pc"), -0.25), "forced legacy affection -0.25: " + str(RS.getAffection("npcForced", "pc")))
	check(near(rel.getFeeling("npcForced", "pc", "affection"), -25) and near(rel.getFeeling("npcForced", "pc", "trust"), -35) and near(rel.getFeeling("npcForced", "pc", "fear"), 20), "forced axes")
	check(rel.getFeeling("pc", "npcForced", "affection") == 0.0, "directional: nothing towards the victim")
	check(!RS.hasSpecialRelationship("npcForced"), "forced created no special relationship")
	check(main.messages.size() == 1, "one message: " + str(main.messages))
	var expectedLine = npcs[0].getName() + "'s feelings changed: [color=red]Affection -25[/color], [color=red]Trust -35[/color], [color=yellow]Fear +20[/color]."
	check(main.messages.size() > 0 and main.messages[0] == expectedLine, "message text: " + str(main.messages))

	# Coerced
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("AskingForKey", "sex_challenge_start", "npcCoerced", "pc"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false and !rel.hasRelationship("npcCoerced", "pc") and near(RS.getAffection("npcCoerced", "pc"), -0.1) and RS.getLust("npcCoerced", "pc") == 0.0, "player victim: vanilla suppressed, legacy lowered, nothing stored")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("AskingForKey", "sex_challenge_start", "pc", "npcCoerced"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false and near(RS.getAffection("npcCoerced", "pc"), -0.2) and near(rel.getFeeling("npcCoerced", "pc", "trust"), -15), "coerced")

	# The old formula on a near-friend would have made a Friend. Forced must not.
	RS.addAffection("npcNear", "pc", 0.45, false, false)
	check(!RS.hasSpecialRelationship("npcNear"), "setup: 0.45 is not yet a friend")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Unconscious", "about_to_fuck", "pc", "npcNear"), sexData, makeResult(1.0, 1.0))
	check(RS.getAffection("npcNear", "pc") < 0.45 and !RS.hasSpecialRelationship("npcNear"), "forced on near-friend lowers affection, no Friend")
	var legacyOld = (min(1.0, 1.0) - 0.5) * 0.4
	check(0.45 + legacyOld >= 0.5, "sanity: the old formula would have crossed the Friend threshold")

	# An existing Friend: forced sex by the player ends it.
	RS.addAffection("npcFriend", "pc", 0.9, false, false)
	check(RS.hasSpecialRelationshipID("npcFriend", "Friend"), "setup: 0.9 starts a Friend")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("PunishInteraction", "about_to_sex", "pc", "npcFriend"), sexData, makeResult(1.0, 1.0))
	check(!RS.hasSpecialRelationshipID("npcFriend", "Friend") and RS.getAffection("npcFriend", "pc") < 0.5, "forced ends the Friend and cannot recreate it")
	RS.addAffection("npcFriend", "pc", 0.0, false, false)
	check(!RS.hasSpecialRelationshipID("npcFriend", "Friend"), "no Friend straight after")

	# NPC forces the player, maximum satisfaction, legacy affection 0.45: the old shared formula must not raise anything.
	RS.addAffection("npcPcVictim", "pc", 0.45, false, false)
	var lustBefore = RS.getLust("npcPcVictim", "pc")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "grabbed_about_to_fuck", "npcPcVictim", "pc"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false, "NPC forces player: vanilla suppressed")
	check(RS.getAffection("npcPcVictim", "pc") < 0.45 and RS.getAffection("npcPcVictim", "pc") <= 0.49, "NPC forces player: legacy affection does not increase")
	check(RS.getLust("npcPcVictim", "pc") <= lustBefore, "NPC forces player: legacy lust does not increase")
	check(!RS.hasSpecialRelationship("npcPcVictim"), "NPC forces player: no Friend")
	check(!rel.hasRelationship("npcPcVictim", "pc") and !rel.hasRelationship("pc", "npcPcVictim"), "NPC forces player: no directed change")

	# NPC forces the player while already being the player's Friend: the Friend ends.
	RS.addAffection("npcFriend2", "pc", 0.9, false, false)
	check(RS.hasSpecialRelationshipID("npcFriend2", "Friend"), "setup: second Friend")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "grabbed_about_to_fuck", "npcFriend2", "pc"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false and !RS.hasSpecialRelationshipID("npcFriend2", "Friend") and RS.getAffection("npcFriend2", "pc") < 0.5, "NPC forcing the player ends their Friend relationship")

	# Unknown: nothing.
	var messagesBefore = main.messages.size()
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("InSlutwall", "about_to_use", "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false and !rel.hasRelationship("npcUnknown", "pc") and RS.getAffection("npcUnknown", "pc") == 0.0 and RS.getLust("npcUnknown", "pc") == 0.0 and main.messages.size() == messagesBefore and !RS.hasSpecialRelationship("npcUnknown"), "unknown: no axes, no legacy affection or lust, no Friend, no message, vanilla suppressed")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "offered_sex_agreed", "pc", "pc"), sexData, makeResult(1.0, 1.0))
	check(runVanilla == false, "same dom and sub: fail closed")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), ["dom"], makeResult(1.0, 1.0))
	check(runVanilla == false, "short sex data: fail closed")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), sexData, null)
	check(runVanilla == false, "null result: fail closed")

	# More malformed input, all fail closed: no vanilla, no axes, no legacy change, no Friend change, no message.
	RS.addAffection("npcUnknown", "pc", 0.3, false, false)
	var legacyAff = RS.getAffection("npcUnknown", "pc")
	var legacyLust = RS.getLust("npcUnknown", "pc")
	var msgs = main.messages.size()
	var bad = []
	bad.append([null, sexData, makeResult(1.0, 1.0), "null interaction"])
	bad.append([makeInteraction("", "offered_sex_agreed", "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0), "empty interaction id"])
	bad.append([makeInteraction(null, "offered_sex_agreed", "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0), "null interaction id"])
	bad.append([makeInteraction("Talking", "", "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0), "empty state id"])
	bad.append([makeInteraction("Talking", null, "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0), "null state id"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "", "npcUnknown"), sexData, makeResult(1.0, 1.0), "empty dom role id"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "pc", ""), sexData, makeResult(1.0, 1.0), "empty sub role id"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), ["missing", "roles"], makeResult(1.0, 1.0), "roles not in the interaction"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), [], makeResult(1.0, 1.0), "empty sex data"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), null, makeResult(1.0, 1.0), "null sex data"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), "dom", makeResult(1.0, 1.0), "non-array sex data"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "npcUnknown", "npcUnknown"), sexData, makeResult(1.0, 1.0), "dom equals sub"])
	bad.append([makeInteraction("Talking", "offered_sex_agreed", "pc", "npcUnknown"), sexData, null, "missing sex result"])
	bad.append([makeInteraction("Nonsense", "about_to_sex", "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0), "unknown interaction"])
	bad.append([makeInteraction("Talking", "nonsense", "pc", "npcUnknown"), sexData, makeResult(1.0, 1.0), "unknown state"])
	for entry in bad:
		var result = module.applySexAftermathAndShouldRunVanilla(entry[0], entry[1], entry[2])
		check(result == false, "fail closed: " + entry[3])
	check(!rel.hasRelationship("npcUnknown", "pc") and !rel.hasRelationship("pc", "npcUnknown"), "malformed input: no directed change")
	check(near(RS.getAffection("npcUnknown", "pc"), legacyAff) and RS.getLust("npcUnknown", "pc") == legacyLust, "malformed input: legacy affection and lust unchanged")
	check(main.messages.size() == msgs and !RS.hasSpecialRelationship("npcUnknown"), "malformed input: no message, no Friend change")

	# Consensual: legacy formula stays, new axes change.
	var before = main.messages.size()
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Talking", "offered_sex_agreed", "pc", "npcGood"), sexData, makeResult(0.9, 0.9))
	check(runVanilla == true, "consensual keeps the vanilla aftermath")
	check(rel.getFeeling("npcGood", "pc", "affection") > 5.0 and rel.getFeeling("npcGood", "pc", "trust") > 4.0 and rel.getFeeling("npcGood", "pc", "desire") > 8.0, "consensual good axes")
	check(RS.getAffection("npcGood", "pc") == 0.0, "consensual leaves legacy to the caller")
	check(main.messages.size() == before + 1 and main.messages[main.messages.size() - 1].find("[color=green]Affection +") != -1, "one green message")
	runVanilla = module.applySexAftermathAndShouldRunVanilla(makeInteraction("Prostitution", "about_to_sex", "npcPoor", "pc"), sexData, makeResult(0.1, 0.1))
	check(runVanilla == true and rel.getFeeling("npcPoor", "pc", "affection") < 0.0 and rel.getFeeling("npcPoor", "pc", "desire") < 0.0, "consensual poor axes")

	# Save and load after the events through the real extender.
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	rel.removeCharacter("npcForced")
	check(!rel.hasRelationship("npcForced", "pc"), "setup: cleared")
	GM.GES.loadData(saved)
	check(near(rel.getFeeling("npcForced", "pc", "trust"), -35) and rel.getFeeling("pc", "npcForced", "trust") == 0.0 and rel.getFeeling("npcGood", "pc", "desire") > 8.0, "aftermath survives save and load")

	# NPC list text and tooltip through the module.
	var shown = module.getFeelingsText("npcForced", "pc")
	check(shown == "Affection -25   Trust -35\nRespect 0   Fear +20\nDesire 0", "feelings text: " + shown)
	check(module.getFeelingsTooltip().find("Trust: belief") != -1, "tooltip")

	GM.main = null
	for c in npcs:
		c.free()
	main.dynamicCharacters.clear()
	main.free()
	print("SexAftermathBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)

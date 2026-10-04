extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/SexAftermathTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const RelScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")
const ConsentScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexConsent.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func _init():
	# Classification
	check(ConsentScript.classify("Talking", "offered_sex_agreed") == ConsentScript.CONSENSUAL, "offer accepted is consensual")
	check(ConsentScript.classify("Talking", "offered_self_agreed") == ConsentScript.CONSENSUAL, "self offer accepted is consensual")
	check(ConsentScript.classify("Prostitution", "about_to_sex") == ConsentScript.CONSENSUAL, "prostitution is consensual")
	check(ConsentScript.classify("Talking", "grabbed_about_to_fuck") == ConsentScript.FORCED, "grab and fuck is forced")
	check(ConsentScript.classify("Unconscious", "about_to_fuck") == ConsentScript.FORCED, "unconscious is forced")
	check(ConsentScript.classify("PunishInteraction", "about_to_sex") == ConsentScript.COERCED, "punishment sex is coerced, not forced")
	check(ConsentScript.classify("AskingForKey", "sex_challenge_start") == ConsentScript.COERCED, "sex challenge is coerced")
	check(ConsentScript.classify("PunishInteraction", "about_to_subsex") == ConsentScript.UNKNOWN, "punisher submits is unknown")
	check(ConsentScript.classify("InSlutwall", "about_to_use") == ConsentScript.UNKNOWN && ConsentScript.classify("HelpLayEggs", "") == ConsentScript.UNKNOWN, "unlisted interactions are unknown")
	check(ConsentScript.classify(null, null) == ConsentScript.UNKNOWN && ConsentScript.classify("Talking", "nonsense") == ConsentScript.UNKNOWN, "garbage is unknown")
	check(ConsentScript.classify("", "") == ConsentScript.UNKNOWN and ConsentScript.classify("Talking", "") == ConsentScript.UNKNOWN and ConsentScript.classify("", "offered_sex_agreed") == ConsentScript.UNKNOWN, "empty interaction or state is unknown")
	check(ConsentScript.classify("Nonsense", "about_to_sex") == ConsentScript.UNKNOWN, "unknown interaction")
	var recognised = 0
	for interactionID in ConsentScript.TABLE:
		for stateID in ConsentScript.TABLE[interactionID]:
			recognised += 1
			check(ConsentScript.classify(interactionID, stateID) == ConsentScript.TABLE[interactionID][stateID] and ConsentScript.classify(interactionID, stateID) != ConsentScript.UNKNOWN, "table pair " + interactionID + "/" + stateID)
	check(recognised == 7, "seven recognised pairs: " + str(recognised))
	check(ConsentScript.isNonConsensual(ConsentScript.COERCED) && ConsentScript.isNonConsensual(ConsentScript.FORCED) && !ConsentScript.isNonConsensual(ConsentScript.CONSENSUAL) && !ConsentScript.isNonConsensual(ConsentScript.UNKNOWN), "isNonConsensual")

	# Effects
	var good = AftermathScript.getEffects(ConsentScript.CONSENSUAL, 0.9, 0.9)
	check(good["affection"] > 5.0 && good["trust"] > 4.0 && good["desire"] > 8.0, "satisfying consensual is positive and scaled up")
	var okay = AftermathScript.getEffects(ConsentScript.CONSENSUAL, 0.5, 0.5)
	check(near(okay["affection"], 5.0 * 1.0) && near(okay["trust"], 4.0) && near(okay["desire"], 8.0), "threshold consensual is the base value")
	var poor = AftermathScript.getEffects(ConsentScript.CONSENSUAL, 0.1, 0.9)
	check(poor["affection"] < -3.0 && poor["trust"] < -1.0 && poor["desire"] < -5.0 && !poor.has("fear"), "poor consensual is negative with no fear")
	var coerced = AftermathScript.getEffects(ConsentScript.COERCED, 1.0, 1.0)
	check(near(coerced["affection"], -10) && near(coerced["trust"], -15) && near(coerced["fear"], 8) && !coerced.has("desire") && !coerced.has("respect"), "coerced values")
	var forced = AftermathScript.getEffects(ConsentScript.FORCED, 1.0, 1.0)
	check(near(forced["affection"], -25) && near(forced["trust"], -35) && near(forced["fear"], 20) && !forced.has("desire") && !forced.has("respect"), "forced values")
	check(AftermathScript.getEffects(ConsentScript.UNKNOWN, 1.0, 1.0).empty(), "unknown has no effects")
	for consent in [ConsentScript.COERCED, ConsentScript.FORCED]:
		for sat in [0.0, 0.25, 0.5, 0.75, 1.0]:
			for subSat in [0.0, 1.0]:
				var e = AftermathScript.getEffects(consent, sat, subSat)
				check(e["affection"] < 0.0 && e["trust"] < 0.0 && e["fear"] > 0.0 && !e.has("desire") && !e.has("respect"), "non-consensual never positive, dom " + str(sat) + " sub " + str(subSat))
				check(JSON.print(e) == JSON.print(AftermathScript.getEffects(consent, 0.0, 0.0)), "satisfaction does not change non-consensual values")

	# Legacy affection change
	check(AftermathScript.getLegacyAffectionChange(ConsentScript.CONSENSUAL, 0.3) == 0.0 && AftermathScript.getLegacyAffectionChange(ConsentScript.UNKNOWN, 0.3) == 0.0, "no legacy change for consensual or unknown")
	check(near(AftermathScript.getLegacyAffectionChange(ConsentScript.FORCED, 0.0), -0.25) && near(AftermathScript.getLegacyAffectionChange(ConsentScript.COERCED, 0.0), -0.1), "legacy change table")
	check(0.45 + AftermathScript.getLegacyAffectionChange(ConsentScript.COERCED, 0.45) <= 0.49 + 0.0001, "legacy result stays below the Friend threshold")
	for start in [-1.0, -0.5, 0.0, 0.4, 0.49, 0.5, 0.9, 1.0]:
		for consent in [ConsentScript.COERCED, ConsentScript.FORCED]:
			var change = AftermathScript.getLegacyAffectionChange(consent, start)
			check(change < 0.0 && start + change < 0.5, "legacy change always negative and below 0.5 from " + str(start))

	# Applying and directionality
	var s = StateScript.new()
	var r = RelScript.new(s)
	var results = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	check(results.size() == 1 and results[0]["observer"] == "npc1" and results[0]["target"] == "pc", "forced: victim towards aggressor")
	check(near(r.getFeeling("npc1", "pc", "affection"), -25) and near(r.getFeeling("npc1", "pc", "trust"), -35) and near(r.getFeeling("npc1", "pc", "fear"), 20), "forced applied to victim")
	check(r.getFeeling("pc", "npc1", "affection") == 0.0 and r.getFeeling("pc", "npc1", "fear") == 0.0 and !r.hasRelationship("pc", "npc1"), "player feelings are never stored")
	check(r.getFeeling("npc1", "pc", "desire") == 0.0 and r.getFeeling("npc1", "pc", "respect") == 0.0, "no desire or respect change when forced")
	var again = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	check(near(again[0]["changes"]["affection"], -25) and near(r.getFeeling("npc1", "pc", "affection"), -50), "repeated aftermath accumulates")
	var capped = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	capped = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	capped = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	capped = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	capped = AftermathScript.apply(r, ConsentScript.FORCED, "pc", "npc1", 1.0, 1.0)
	check(near(r.getFeeling("npc1", "pc", "affection"), -100) and capped[0]["changes"].empty(), "changes report the applied amount after clamping")

	var _npcOnly = AftermathScript.apply(r, ConsentScript.FORCED, "npcA", "npcB", 0.5, 0.5)
	check(near(r.getFeeling("npcB", "npcA", "trust"), -35) and r.getFeeling("npcA", "npcB", "trust") == 0.0, "npc to npc forced is directional")

	var both = AftermathScript.apply(r, ConsentScript.CONSENSUAL, "npcC", "npcD", 0.8, 0.8)
	check(both.size() == 2 and r.getFeeling("npcC", "npcD", "affection") > 5.0 and r.getFeeling("npcD", "npcC", "affection") > 5.0, "consensual changes both npc directions")
	var withPlayer = AftermathScript.apply(r, ConsentScript.CONSENSUAL, "pc", "npcE", 0.8, 0.8)
	check(withPlayer.size() == 1 and withPlayer[0]["observer"] == "npcE" and r.getFeeling("npcE", "pc", "desire") > 8.0 and !r.hasRelationship("pc", "npcE"), "consensual with the player changes only the npc")
	var _poorRun = AftermathScript.apply(r, ConsentScript.CONSENSUAL, "pc", "npcF", 0.1, 0.1)
	check(r.getFeeling("npcF", "pc", "affection") < 0.0 and r.getFeeling("npcF", "pc", "desire") < 0.0 and r.getFeeling("npcF", "pc", "fear") == 0.0, "poor consensual is negative")
	check(AftermathScript.apply(r, ConsentScript.UNKNOWN, "pc", "npcG", 1.0, 1.0).empty() and !r.hasRelationship("npcG", "pc"), "unknown applies nothing")
	check(AftermathScript.apply(r, ConsentScript.FORCED, "npcH", "pc", 1.0, 1.0).size() == 0 and !r.hasRelationship("npcH", "pc"), "player victim stores nothing")
	check(AftermathScript.apply(r, ConsentScript.FORCED, "", "npcI", 1.0, 1.0).empty() and AftermathScript.apply(r, ConsentScript.FORCED, "x", "x", 1.0, 1.0).empty(), "invalid ids apply nothing")

	# Message
	var line = AftermathScript.formatMessage("Alex", {"affection": -25.0, "trust": -35.0, "fear": 20.0})
	var expected = "Alex's feelings changed: [color=red]Affection -25[/color], [color=red]Trust -35[/color], [color=yellow]Fear +20[/color]."
	check(line == expected, "combined message: " + line)
	var happy = AftermathScript.formatMessage("Bo", {"affection": 5.4, "desire": 8.0, "trust": 0.2})
	check(happy == "Bo's feelings changed: [color=green]Affection +5[/color], [color=green]Desire +8[/color].", "positive message rounds and drops zero: " + happy)
	check(AftermathScript.formatMessage("Cy", {}) == "" and AftermathScript.formatMessage("Cy", {"trust": 0.3}) == "", "empty message when nothing visible")
	check(line.count("\n") == 0, "message is one line")

	# Display text
	var s2 = StateScript.new()
	var r2 = RelScript.new(s2)
	var _x = r2.setFeeling("npc1", "pc", "affection", -24.6)
	_x = r2.setFeeling("npc1", "pc", "fear", 20)
	_x = r2.setFeeling("npc1", "pc", "desire", 7.4)
	var shown = AftermathScript.formatFeelings(r2, "npc1", "pc")
	check(shown == "Affection -25   Trust 0\nRespect 0   Fear +20\nDesire +7", "feelings text: " + shown)
	check(AftermathScript.formatSummary(r2, "npc1", "pc") == "Affection -25, Trust 0, Respect 0, Fear +20, Desire +7", "summary line: " + AftermathScript.formatSummary(r2, "npc1", "pc"))
	check(AftermathScript.FEELINGS_TOOLTIP.find("Desire: attraction or aversion") != -1, "tooltip text")

	# Save/load after an aftermath event
	var _y = AftermathScript.apply(r2, ConsentScript.COERCED, "pc", "npc2", 0.9, 0.9)
	var parsed = JSON.parse(JSON.print(s2.saveData())).result
	var s3 = StateScript.new()
	var r3 = RelScript.new(s3)
	s3.loadData(parsed)
	check(near(r3.getFeeling("npc2", "pc", "trust"), -15) and near(r3.getFeeling("npc2", "pc", "fear"), 8) and near(r3.getFeeling("npc1", "pc", "affection"), -24.6), "aftermath survives save and load")
	check(r3.getFeeling("pc", "npc2", "trust") == 0.0, "direction survives save and load")

	print("SexAftermathTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

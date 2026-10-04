extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/ConversationRelationshipsTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const RelScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")
const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")
const ConvScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func run(s, r, outcome, observer, target, day = 0):
	return ConvScript.apply(r, s.cooldowns, outcome, observer, target, day)

func _init():
	# outcome -> [directed axes, legacy affection, legacy lust]
	var expected = {
		"shared_interest": [{"affection": 3.0, "trust": 1.0}, 0.03, 0.0],
		"positive_conversation": [{"affection": 2.0, "trust": 1.0}, 0.02, 0.0],
		"respectful_disagreement": [{"affection": -1.0}, -0.01, 0.0],
		"hostile_response": [{"affection": -3.0, "trust": -2.0, "respect": -1.0}, -0.03, 0.0],
		"flirt_accepted": [{"affection": 2.0, "desire": 4.0}, 0.02, 0.04],
		"flirt_rejected": [{"desire": -2.0}, 0.0, -0.02],
		"sex_request_accepted": [{"desire": 2.0}, 0.0, 0.02],
	}
	for outcome in expected:
		var s = StateScript.new()
		var r = RelScript.new(s)
		var result = run(s, r, outcome, "npc", "pc")
		check(result["blocked"] == false, outcome + " not blocked")
		for axis in AxisScript.ALL:
			var want = expected[outcome][0].get(axis, 0.0)
			check(near(r.getFeeling("npc", "pc", axis), want), outcome + " " + axis + " is " + str(want))
			check(near(result["changes"].get(axis, 0.0), want), outcome + " reports " + axis)
		check(near(result["legacyAffection"], expected[outcome][1]) and near(result["legacyLust"], expected[outcome][2]), outcome + " legacy deltas are the fixed values")
		check(r.getFeeling("pc", "npc", "affection") == 0.0 && !r.hasRelationship("pc", "npc"), outcome + " is directional")
		check(r.getFeeling("npc", "pc", "fear") == 0.0, outcome + " never changes fear")

	# No change outcomes: nothing directed, nothing legacy, no cooldown
	for outcome in ["neutral_exchange", "sex_request_refused"]:
		var s = StateScript.new()
		var r = RelScript.new(s)
		var result = run(s, r, outcome, "npc", "pc")
		check(result["changes"].empty() && result["legacyAffection"] == 0.0 && result["legacyLust"] == 0.0 && result["blocked"] == false, outcome + " changes nothing")
		check(s.directed_relationships.empty() && s.cooldowns.empty(), outcome + " stores nothing")
		check(!ConvScript.isPositive(outcome), outcome + " is not a rewarding outcome")

	# Refusals never touch affection or trust, directed or legacy
	for outcome in ["flirt_rejected", "sex_request_refused"]:
		check(!ConvScript.getEffects(outcome).has("affection") and !ConvScript.getEffects(outcome).has("trust"), outcome + " has no affection or trust effect")
		check(!ConvScript.LEGACY.get(outcome, {}).has("affection"), outcome + " has no legacy affection effect")

	# Invalid input
	var s2 = StateScript.new()
	var r2 = RelScript.new(s2)
	var blank = run(s2, r2, "bogus", "npc", "pc")
	check(blank["changes"].empty() && blank["legacyAffection"] == 0.0 && !blank["blocked"], "unknown outcome")
	check(run(s2, r2, null, "npc", "pc")["changes"].empty(), "null outcome")
	for ids in [["", "pc"], ["npc", ""], ["npc", "npc"], [null, "pc"], ["npc", null]]:
		var bad = run(s2, r2, "shared_interest", ids[0], ids[1])
		check(bad["changes"].empty() && bad["legacyAffection"] == 0.0 && !bad["blocked"], "invalid ids " + str(ids))
	check(s2.directed_relationships.empty() && s2.cooldowns.empty(), "invalid input stores nothing")

	# The player is never the observer: nothing at all applies, not even the legacy delta or the cooldown
	var pcResult = run(s2, r2, "shared_interest", "pc", "npc")
	check(pcResult["changes"].empty() && pcResult["legacyAffection"] == 0.0 && pcResult["legacyLust"] == 0.0 && !pcResult["blocked"] && !r2.hasRelationship("pc", "npc") && s2.cooldowns.empty(), "player observer: no-op")
	
	# NPC to NPC works and stays directional
	check(run(s2, r2, "flirt_accepted", "npcA", "npcB")["changes"].has("desire") && r2.getFeeling("npcB", "npcA", "desire") == 0.0, "npc to npc directional")

	# Repeat protection covers both systems
	var s3 = StateScript.new()
	var r3 = RelScript.new(s3)
	var first = run(s3, r3, "shared_interest", "npc", "pc", 5)
	check(!first["blocked"] && near(first["legacyAffection"], 0.03) && near(first["changes"]["affection"], 3.0), "first reward today")
	var again = run(s3, r3, "shared_interest", "npc", "pc", 5)
	check(again["blocked"] == true && again["changes"].empty() && again["legacyAffection"] == 0.0 && again["legacyLust"] == 0.0, "second reward the same day: blocked in both systems")
	check(near(r3.getFeeling("npc", "pc", "affection"), 3.0), "directed unchanged after the blocked repeat")
	check(!run(s3, r3, "positive_conversation", "npc", "pc", 5)["blocked"], "a different outcome still rewards")
	check(!run(s3, r3, "shared_interest", "other", "pc", 5)["blocked"], "another npc still rewards")
	check(!run(s3, r3, "shared_interest", "npc", "pc", 6)["blocked"] and near(r3.getFeeling("npc", "pc", "affection"), 8.0), "rewards again the next day")
	var negative = []
	for _i in range(3):
		negative.append(run(s3, r3, "respectful_disagreement", "npc", "pc", 6))
	check(near(r3.getFeeling("npc", "pc", "affection"), 5.0), "negative outcomes are never limited (directed)")
	check(!negative[0]["blocked"] and !negative[1]["blocked"] and !negative[2]["blocked"] and near(negative[2]["legacyAffection"], -0.01), "negative outcomes keep their legacy delta")
	var _rej1 = run(s3, r3, "flirt_rejected", "npc", "pc", 6)
	var rej2 = run(s3, r3, "flirt_rejected", "npc", "pc", 6)
	check(!rej2["blocked"] and near(r3.getFeeling("npc", "pc", "desire"), -4.0) and near(rej2["legacyLust"], -0.02), "repeated rejection keeps counting in both systems")

	# A rewarding outcome pays once per day even when the directed axes are capped
	var s4 = StateScript.new()
	var r4 = RelScript.new(s4)
	var _z = r4.setFeeling("npc", "pc", "affection", 100)
	_z = r4.setFeeling("npc", "pc", "trust", 100)
	var capped = run(s4, r4, "shared_interest", "npc", "pc", 1)
	check(capped["changes"].empty() && near(capped["legacyAffection"], 0.03), "capped directed reward still gives the legacy delta once")
	check(run(s4, r4, "shared_interest", "npc", "pc", 1)["blocked"], "and is then blocked for the day")

	# Messages
	var msg = ConvScript.formatMessage("Mae", {"affection": 3.0, "trust": 1.0})
	check(msg == "Mae's feelings changed: [color=green]Affection +3[/color], [color=green]Trust +1[/color].", "positive message: " + msg)
	msg = ConvScript.formatMessage("Mae", {"affection": -3.0, "trust": -2.0, "respect": -1.0})
	check(msg == "Mae's feelings changed: [color=red]Affection -3[/color], [color=red]Trust -2[/color], [color=red]Respect -1[/color].", "hostile message: " + msg)
	check(ConvScript.formatMessage("Mae", {}) == "", "no message without changes")

	# Save and load of cooldown data, and reset
	var parsed = JSON.parse(JSON.print(s3.saveData())).result
	var s5 = StateScript.new()
	var r5 = RelScript.new(s5)
	s5.loadData(parsed)
	check(run(s5, r5, "shared_interest", "npc", "pc", 6)["blocked"], "cooldown survives save and load (JSON floats)")
	check(!run(s5, r5, "shared_interest", "npc", "pc", 7)["blocked"], "and expires the next day")
	s5.clear()
	check(s5.cooldowns.empty() && !run(s5, r5, "shared_interest", "npc", "pc", 6)["blocked"], "reset clears cooldowns")

	# Cooldown pruning helpers
	var cd = {"conv|a|pc|shared_interest": 1, "conv|pc|b|flirt_accepted": 1, "other": 5, "conv|c|d|x": 2}
	var ids = ConvScript.getCooldownCharacterIDs(cd)
	check(ids.has("a") && ids.has("pc") && ids.has("b") && ids.has("c") && ids.has("d") && ids.size() == 5, "cooldown character ids: " + str(ids))
	ConvScript.removeCooldownsOf(cd, "a")
	check(!cd.has("conv|a|pc|shared_interest") && cd.has("conv|pc|b|flirt_accepted") && cd.has("other"), "removeCooldownsOf removes only that character")

	print("ConversationRelationshipsTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

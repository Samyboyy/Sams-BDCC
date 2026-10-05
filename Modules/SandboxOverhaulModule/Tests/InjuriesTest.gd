extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/InjuriesTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const RelScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func make():
	var s = StateScript.new()
	return [s, InjuriesScript.new(s)]

func _init():
	# Defaults
	var m = make()
	var s = m[0]
	var inj = m[1]
	check(s.injuries.empty() and inj.getAll("pc").empty() and !inj.has("pc", "arm") and inj.highestSeverity("pc") == 0 and inj.getSeverity("pc", "arm") == 0 and inj.getRemainingHours("pc", "arm") == 0.0, "defaults")
	check(inj.getAll(null).empty() and !inj.has(null, "arm"), "safe getters with bad ids")
	check(JSON.print(InjuriesScript.DURATION_HOURS) == JSON.print({1: 24.0, 2: 72.0, 3: 120.0}), "durations are 24, 72 and 120 hours")
	check(JSON.print(InjuriesScript.PENALTY_PERCENT) == JSON.print({1: 10, 2: 20, 3: 30}), "penalties are 10, 20 and 30 percent")

	# Acquisition thresholds
	var cases = [[0.0, 0], [0.3499, 0], [0.35, 1], [0.5, 1], [0.5999, 1], [0.60, 2], [0.8499, 2], [0.85, 3], [1.0, 3], [2.5, 3], [-1.0, 0], ["x", 0], [null, 0]]
	for entry in cases:
		check(InjuriesScript.severityFromDamage(entry[0]) == entry[1], "damage " + str(entry[0]) + " is severity " + str(entry[1]))

	# Type selection never random
	check(InjuriesScript.pickType(null) == "trauma" and InjuriesScript.pickType({}) == "trauma" and InjuriesScript.pickType("x") == "trauma", "no region history: body trauma")
	check(InjuriesScript.pickType({"arm": 10, "leg": 4, "torso": 2}) == "arm", "most damaged region arm")
	check(InjuriesScript.pickType({"arm": 1, "leg": 9, "torso": 2}) == "leg", "most damaged region leg")
	check(InjuriesScript.pickType({"arm": 1, "leg": 2, "torso": 9, "head": 3}) == "trauma", "torso is body trauma")
	check(InjuriesScript.pickType({"head": 5, "arm": 2}) == "trauma", "head is body trauma")
	check(InjuriesScript.pickType({"arm": 0, "leg": 0}) == "trauma" and InjuriesScript.pickType({"arm": "x"}) == "trauma", "no usable damage: body trauma")
	for _i in range(20):
		check(InjuriesScript.pickType({}) == "trauma", "empty history is deterministic")

	# Evaluating fights: each participant on their own
	m = make()
	s = m[0]
	inj = m[1]
	var rp = inj.evaluateFight("pc", 0.9)
	var re = inj.evaluateFight("foe", 0.4)
	check(rp["result"] == "new" and rp["type"] == "trauma" and rp["to"] == 3 and inj.getSeverity("pc", "trauma") == 3, "player at 90% pain: severe body trauma")
	check(re["result"] == "new" and inj.getSeverity("foe", "trauma") == 1, "enemy at 40% pain: minor body trauma, judged separately")
	check(inj.evaluateFight("winner", 0.65)["to"] == 2, "a winner who barely survived (65% pain) is moderately injured")
	check(inj.evaluateFight("fine", 0.1)["result"] == "none" and !inj.has("fine", "trauma"), "10% pain: no injury")
	check(inj.evaluateFight("surrenderer", 0.5)["to"] == 1, "surrender after taking damage keeps the damage it took")
	check(inj.evaluateFight("surrenderer2", 0.0)["result"] == "none", "surrender with no damage: no injury")
	check(inj.evaluateFight("lustonly", 0.0)["result"] == "none", "lust alone never injures (only pain is measured)")
	check(inj.evaluateFight("lustplus", 0.7)["to"] == 2, "a lust defeat with 70% pain still injures")
	check(inj.evaluateFight("armguy", 0.7, false, {"arm": 5, "leg": 1})["type"] == "arm" and inj.has("armguy", "arm") and !inj.has("armguy", "trauma"), "recorded region history picks the arm")

	# Fight Club: one level lower
	m = make()
	inj = m[1]
	check(inj.evaluateFight("a", 0.9, true)["to"] == 2, "arena severe becomes moderate")
	check(inj.evaluateFight("b", 0.65, true)["to"] == 1, "arena moderate becomes minor")
	check(inj.evaluateFight("c", 0.4, true)["result"] == "none" and !inj.has("c", "trauma"), "arena minor becomes no lasting injury")

	# Reinjury
	m = make()
	s = m[0]
	inj = m[1]
	inj.applyInjury("pc", "arm", 1)
	var _h = inj.processHours(10)
	check(near(inj.getRemainingHours("pc", "arm"), 14.0), "setup: 10 hours elapsed")
	var again = inj.applyInjury("pc", "arm", 1)
	check(again["result"] == "worsened" and again["from"] == 1 and again["to"] == 2 and near(inj.getRemainingHours("pc", "arm"), 72.0), "minor reinjured becomes moderate and resets to 72 hours")
	again = inj.applyInjury("pc", "arm", 1)
	check(again["to"] == 3 and near(inj.getRemainingHours("pc", "arm"), 120.0), "moderate reinjured becomes severe and resets to 120 hours")
	_h = inj.processHours(50)
	again = inj.applyInjury("pc", "arm", 1)
	check(again["result"] == "refreshed" and again["to"] == 3 and near(inj.getRemainingHours("pc", "arm"), 120.0), "severe stays severe and resets its time")
	check(s.injuries["pc"].size() == 1, "no duplicate entries")
	again = inj.applyInjury("pc", "arm", 3)
	check(again["to"] == 3 and inj.getSeverity("pc", "arm") == 3, "a severe new hit on an active injury still just escalates one level")

	# Coexisting types
	m = make()
	inj = m[1]
	inj.applyInjury("pc", "arm", 1)
	inj.applyInjury("pc", "leg", 3)
	inj.applyInjury("pc", "trauma", 2)
	check(inj.getAll("pc").size() == 3 and inj.highestSeverity("pc") == 3, "different injuries coexist; highest severity is 3")
	inj.remove("pc", "leg")
	check(inj.has("pc", "arm") and inj.has("pc", "trauma") and !inj.has("pc", "leg") and inj.highestSeverity("pc") == 2, "removing one leaves the others")
	inj.remove("pc", "arm")
	inj.remove("pc", "trauma")
	check(m[0].injuries.empty(), "empty character entry is removed")

	# Invalid input
	m = make()
	inj = m[1]
	check(inj.applyInjury("", "arm", 1)["result"] == "none" and inj.applyInjury("pc", "bogus", 1)["result"] == "none" and inj.applyInjury("pc", "arm", 0)["result"] == "none" and inj.applyInjury("pc", "arm", 4)["result"] == "none" and inj.applyInjury("pc", "arm", "x")["result"] == "none" and inj.applyInjury(null, "arm", 1)["result"] == "none", "invalid injuries are ignored")
	check(m[0].injuries.empty(), "invalid input stores nothing")

	# Hourly recovery and time skips
	m = make()
	inj = m[1]
	inj.applyInjury("pc", "arm", 1)
	inj.applyInjury("pc", "leg", 2)
	inj.applyInjury("pc", "trauma", 3)
	inj.applyInjury("npc", "trauma", 1)
	var rec = inj.processHours(1)
	check(rec.empty() and near(inj.getRemainingHours("pc", "arm"), 23.0) and near(inj.getRemainingHours("pc", "leg"), 71.0) and near(inj.getRemainingHours("pc", "trauma"), 119.0), "each injury loses one hour per hour")
	rec = inj.processHours(23)
	check(rec.size() == 2 and !inj.has("pc", "arm") and !inj.has("npc", "trauma") and inj.has("pc", "leg"), "minor injuries heal after 24 hours (player's and npc's)")
	rec = inj.processHours(47)
	check(rec.size() == 0 and near(inj.getRemainingHours("pc", "leg"), 1.0), "multi-hour skip: 1 hour left on the moderate injury")
	rec = inj.processHours(48)
	check(rec.size() == 1 and rec[0]["characterID"] == "pc" and rec[0]["type"] == "leg" and !inj.has("pc", "leg") and !inj.has("pc", "leg"), "moderate heals after 72 hours total")
	check(near(inj.getRemainingHours("pc", "trauma"), 120.0 - 1.0 - 23.0 - 47.0 - 48.0), "severe has 1 hour left after 119 hours")
	rec = inj.processHours(1)
	check(rec.size() == 1 and inj.getAll("pc").empty() and m[0].injuries.empty(), "severe heals after 120 hours")
	check(inj.processHours(0).empty() and inj.processHours(-5).empty() and inj.processHours("x").empty(), "bad hour values do nothing")
	m = make()
	m[1].applyInjury("pc", "arm", 2)
	var _r = m[1].processHours(500)
	check(m[0].injuries.empty(), "a very long skip heals everything and leaves no negative time")

	# Exact save and load
	m = make()
	s = m[0]
	inj = m[1]
	inj.applyInjury("pc", "arm", 2)
	inj.applyInjury("foe", "trauma", 3)
	_h = inj.processHours(17.5)
	var saved = JSON.parse(JSON.print(s.saveData())).result
	var t = StateScript.new()
	var ti = InjuriesScript.new(t)
	t.loadData(saved)
	check(t.schema_version == 8 and ti.getSeverity("pc", "arm") == 2 and near(ti.getRemainingHours("pc", "arm"), 54.5) and ti.getSeverity("foe", "trauma") == 3 and near(ti.getRemainingHours("foe", "trauma"), 102.5), "save and load keep severity and exact remaining hours")
	saved["injuries"]["pc"]["arm"]["remainingHours"] = 1.0
	check(near(ti.getRemainingHours("pc", "arm"), 54.5), "no aliasing with the save")
	t.clear()
	check(t.injuries.empty() and ti.highestSeverity("pc") == 0, "reset clears injuries")

	# Migration from the previous schema
	t.loadData({"schema_version": 1, "cooldowns": {"k": 1}, "reputation": {"combat": 12, "defiance": 3}, "injuries": {"pc": {"arm": {"severity": 3, "remainingHours": 100}}}})
	check(t.schema_version == 8 and t.injuries.empty() and t.cooldowns.has("k") and near(t.reputation["combat"], 12.0), "version 1 loads with no injuries, other data kept, stamped 3")
	t.loadData({"cooldowns": {"k": 1}})
	check(t.schema_version == 8 and t.injuries.empty(), "a save with no version and no injuries loads clean")
	t.loadData({"schema_version": 2, "injuries": {"pc": {"arm": {"severity": 2, "remainingHours": 10}}}})
	check(t.schema_version == 8 and t.injuries["pc"]["arm"]["severity"] == 2, "version 2 keeps its injuries")
	t.loadData({"schema_version": 99, "injuries": {"pc": {"arm": {"severity": 2, "remainingHours": 10}}}})
	check(t.schema_version == 99 and t.injuries.has("pc"), "a newer schema is kept with its injuries")

	# Malformed and unknown data
	t.loadData({"schema_version": 2, "injuries": "bad"})
	check(t.injuries.empty(), "non-dictionary injuries")
	t.loadData({"schema_version": 2, "injuries": {
		"": {"arm": {"severity": 1, "remainingHours": 5}},
		"a": "x",
		"b": {"nonsense": {"severity": 1, "remainingHours": 5}, "arm": "x", "leg": {"severity": "hi", "remainingHours": 5}, "trauma": {"severity": 2, "remainingHours": "soon"}},
		"c": {"arm": {"severity": 1, "remainingHours": 0}, "leg": {"severity": 2, "remainingHours": -4}},
		"d": {"arm": {"severity": 9, "remainingHours": 12.5, "futureField": {"deep": [1]}}, "leg": {"severity": 0.4, "remainingHours": 1}},
	}})
	check(t.injuries.keys() == ["d"], "only valid entries survive: " + str(t.injuries.keys()))
	check(t.injuries["d"]["arm"]["severity"] == 3 and near(t.injuries["d"]["arm"]["remainingHours"], 12.5) and t.injuries["d"]["arm"].has("futureField"), "severity clamped, unknown field kept")
	check(t.injuries["d"]["leg"]["severity"] == 1, "severity rounds into range")

	# Pruning helpers
	m = make()
	inj = m[1]
	inj.applyInjury("pc", "arm", 1)
	inj.applyInjury("ghost", "arm", 1)
	check(inj.getCharacterIDs().has("ghost"), "ids are listed for pruning")
	inj.removeCharacter("ghost")
	check(!inj.has("ghost", "arm") and inj.has("pc", "arm"), "removeCharacter drops only that character")
	inj.removeCharacter(null)

	# Attack targeting
	m = make()
	s = m[0]
	inj = m[1]
	var rel = RelScript.new(s)
	var combat = CombatScript.new(s, rel)
	check(near(combat.attackMultiplier("npc"), 1.0), "no injury: 1.0x")
	inj.applyInjury("pc", "arm", 1)
	check(near(combat.attackMultiplier("npc"), 1.10), "minor: 1.10x")
	inj.applyInjury("pc", "leg", 2)
	check(near(combat.attackMultiplier("npc"), 1.25), "highest of minor and moderate: 1.25x, not multiplied together")
	inj.applyInjury("pc", "trauma", 3)
	check(near(combat.attackMultiplier("npc"), 1.40), "severe: 1.40x")
	inj.applyInjury("npc", "trauma", 3)
	check(near(combat.attackMultiplier("npc"), 1.40), "the attacker's own injuries do not matter")
	combat.addRep("combat", -100)
	check(near(combat.attackMultiplier("npc"), 1.75), "weak reputation 1.5x times severe 1.4x is capped at 1.75x")
	combat.addRep("combat", 100)
	check(near(combat.attackMultiplier("npc"), 1.40), "reputation 0 with a severe injury: 1.4x")
	combat.addRep("combat", 100)
	check(near(combat.attackMultiplier("npc"), 0.7), "formidable fighter with a severe injury: 0.5 x 1.4")
	var _f = rel.setFeeling("npc", "pc", "fear", 100)
	check(near(combat.attackMultiplier("npc"), 0.07), "fear 100 times the rest: 0.1 x 0.5 x 1.4")
	combat.addRep("combat", 100)
	inj.remove("pc", "arm")
	inj.remove("pc", "leg")
	inj.remove("pc", "trauma")
	check(near(combat.attackMultiplier("npc"), 0.05), "uninjured, feared and formidable: the 0.05 floor")

	# Text
	check(InjuriesScript.fullName("arm", 2) == "Moderate Arm Injury" and InjuriesScript.fullName("leg", 1) == "Minor Leg Injury" and InjuriesScript.fullName("trauma", 3) == "Severe Body Trauma", "names")
	check(InjuriesScript.penaltyText("arm", 2) == "Physical damage -20%" and InjuriesScript.penaltyText("trauma", 3) == "Physical damage received +30%" and InjuriesScript.penaltyText("leg", 1) == "Maximum stamina -10%, dodge chance -10%", "penalty text")
	check(InjuriesScript.remainingText(120) == "5 days" and InjuriesScript.remainingText(72) == "3 days" and InjuriesScript.remainingText(24) == "1 day" and InjuriesScript.remainingText(23) == "23 hours" and InjuriesScript.remainingText(1) == "1 hour" and InjuriesScript.remainingText(0.5) == "less than an hour" and InjuriesScript.remainingText(47) == "2 days", "remaining text")
	check(JSON.print(InjuriesScript.TREATMENT_COST) == JSON.print({1: 2, 2: 3, 3: 6}), "treatment prices")

	print("InjuriesTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

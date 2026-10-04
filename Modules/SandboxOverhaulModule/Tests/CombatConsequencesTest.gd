extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/CombatConsequencesTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const RelScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func make():
	var s = StateScript.new()
	var r = RelScript.new(s)
	var c = CombatScript.new(s, r)
	return [s, r, c]

func fight(c, npc, outcome, day = 0, margin = -1.0):
	return c.applyCombatOutcome({"npcID": npc, "outcome": outcome, "day": day, "margin": margin})

func _init():
	# Defaults, clamping, save/load/reset
	var m = make()
	var s = m[0]
	var r = m[1]
	var c = m[2]
	check(c.getCombatReputation() == 0.0 && c.getDefiance() == 0.0 && s.reputation["combat"] == 0.0 && s.reputation["defiance"] == 0.0, "defaults are 0")
	check(near(c.addRep("combat", 500), 100.0) && near(c.getCombatReputation(), 100.0), "combat clamps at +100")
	check(near(c.addRep("combat", -500), -200.0) && near(c.getCombatReputation(), -100.0), "combat clamps at -100 and reports the applied change")
	check(near(c.addRep("defiance", 150), 100.0) && near(c.addRep("defiance", 10), 0.0), "defiance clamps")
	var json = JSON.print(s.saveData())
	var t = StateScript.new()
	var rt = RelScript.new(t)
	var ct = CombatScript.new(t, rt)
	t.loadData(JSON.parse(json).result)
	check(near(ct.getCombatReputation(), -100.0) && near(ct.getDefiance(), 100.0), "round trip through JSON")
	t.clear()
	check(ct.getCombatReputation() == 0.0 && ct.getDefiance() == 0.0, "reset on clear")
	t.loadData({"reputation": {"combat": 500, "defiance": "x", "extra": 5}})
	check(near(ct.getCombatReputation(), 100.0) && ct.getDefiance() == 0.0 && !t.reputation.has("extra"), "load clamps, ignores non-numbers and unknown keys")
	t.loadData({"reputation": "bad"})
	check(ct.getCombatReputation() == 0.0 && ct.getDefiance() == 0.0, "non-dictionary reputation")
	t.loadData({})
	check(ct.getCombatReputation() == 0.0 && t.schema_version == 5, "old save without reputation, schema migrates to 5")
	var input = {"reputation": {"combat": 5, "defiance": 6}}
	t.loadData(input)
	input["reputation"]["combat"] = 99
	check(near(ct.getCombatReputation(), 5.0), "no aliasing with input")

	# Player victory
	m = make()
	s = m[0]
	r = m[1]
	c = m[2]
	var res = fight(c, "mae", "win")
	check(near(c.getCombatReputation(), 6) && near(c.getDefiance(), 2), "win: combat +6, defiance +2")
	check(near(r.getFeeling("mae", "pc", "fear"), 10) && near(r.getFeeling("mae", "pc", "respect"), 6), "win: npc fear +10, respect +6")
	check(r.getFeeling("mae", "pc", "affection") == 0.0 && r.getFeeling("mae", "pc", "trust") == 0.0 && !r.hasRelationship("pc", "mae"), "win: no affection or trust, directed npc -> pc only")
	check(near(res["reputation"]["combat"], 6) && near(res["personal"]["fear"], 10), "win: result reports what was applied")

	# Losses
	var cases = [["close", 0.7, 2.0], ["clear", 0.4, -2.0], ["crushing", 0.1, -5.0], ["unknown", -1.0, -2.0], ["boundary close", 0.6, 2.0], ["boundary clear", 0.25, -2.0]]
	for entry in cases:
		var mm = make()
		var _p = mm[1].setFeeling("npc", "pc", "fear", 10)
		var _rr = fight(mm[2], "npc", "loss", 0, entry[1])
		check(near(mm[2].getCombatReputation(), -4) && near(mm[2].getDefiance(), 2), entry[0] + " loss: combat -4, defiance +2")
		check(near(mm[1].getFeeling("npc", "pc", "fear"), 6) && near(mm[1].getFeeling("npc", "pc", "respect"), entry[2]), entry[0] + " loss: fear -4, respect " + str(entry[2]) + ", got " + str(mm[1].getFeeling("npc", "pc", "respect")))
	check(near(CombatScript.classifyLoss(null), -2.0) && near(CombatScript.classifyLoss("x"), -2.0), "unmeasured loss uses the fixed value")

	# Surrender is distinct from a loss
	m = make()
	c = m[2]
	r = m[1]
	res = fight(c, "mae", "surrender")
	check(near(c.getCombatReputation(), -2) && near(c.getDefiance(), -6), "surrender: combat -2, defiance -6")
	check(r.getFeeling("mae", "pc", "fear") == 0.0 && near(r.getFeeling("mae", "pc", "respect"), -3), "surrender: fear -5 (clamped at 0) and respect -3")
	var lossRes = fight(make()[2], "mae", "loss", 0, 0.1)
	check(res["reputation"].get("defiance", 0.0) < 0.0 && lossRes["reputation"].get("defiance", 0.0) > 0.0, "surrender lowers defiance while a lost fight raises it")

	# Unprovoked attack
	m = make()
	c = m[2]
	r = m[1]
	res = fight(c, "mae", "unprovoked")
	check(near(r.getFeeling("mae", "pc", "affection"), -5) && near(r.getFeeling("mae", "pc", "trust"), -8) && near(r.getFeeling("mae", "pc", "fear"), 3), "unprovoked: affection -5, trust -8, fear +3")
	check(c.getCombatReputation() == 0.0 && c.getDefiance() == 0.0 && res["reputation"].empty(), "unprovoked: no prison-wide change")
	res = fight(c, "mae", "unprovoked")
	check(near(r.getFeeling("mae", "pc", "affection"), -10), "unprovoked attacks are not limited by the daily rule")

	# Consensual
	m = make()
	c = m[2]
	r = m[1]
	fight(c, "avy", "consensual_win")
	check(near(c.getCombatReputation(), 3) && near(r.getFeeling("avy", "pc", "respect"), 4), "consensual win: combat +3, respect +4")
	check(c.getDefiance() == 0.0 && r.getFeeling("avy", "pc", "fear") == 0.0 && r.getFeeling("avy", "pc", "affection") == 0.0 && r.getFeeling("avy", "pc", "trust") == 0.0, "consensual win: no defiance, fear, affection or trust")
	m = make()
	fight(m[2], "avy", "consensual_loss")
	check(near(m[2].getCombatReputation(), -2) && near(m[1].getFeeling("avy", "pc", "respect"), 1) && m[2].getDefiance() == 0.0 && m[1].getFeeling("avy", "pc", "fear") == 0.0, "consensual loss: combat -2, respect +1, nothing else")

	# Repeated opponent, daily
	m = make()
	c = m[2]
	r = m[1]
	fight(c, "mae", "win", 4)
	var second = fight(c, "mae", "win", 4)
	check(near(c.getCombatReputation(), 6) && second["reputation"].get("combat", 0.0) == 0.0, "second win the same day: no more combat reputation")
	check(near(c.getDefiance(), 2.5), "repeat win the same day: defiance at 25% (+0.5, not +2)")
	check(near(r.getFeeling("mae", "pc", "fear"), 12.5) && near(r.getFeeling("mae", "pc", "respect"), 7.5), "second win: personal change at 25%")
	fight(c, "mae", "win", 4)
	check(near(c.getCombatReputation(), 6) && near(r.getFeeling("mae", "pc", "fear"), 15.0), "third win: still 25% and no reputation")
	fight(c, "kit", "win", 4)
	check(near(c.getCombatReputation(), 12), "another npc still gives the full reputation")
	fight(c, "mae", "win", 5)
	check(near(c.getCombatReputation(), 18) && near(r.getFeeling("mae", "pc", "fear"), 25.0), "next day: full effect again")

	# Defiance cannot be farmed by fighting the same NPC repeatedly
	m = make()
	c = m[2]
	for _i in range(5):
		var _d = fight(c, "mae", "loss", 8, 0.1)
	check(near(c.getDefiance(), 2.0 + 4 * 0.5), "five losses to one npc in a day: +2 then +0.5 each")
	var _e = fight(c, "mae", "loss", 9, 0.1)
	check(near(c.getDefiance(), 4.0 + 2.0), "next day the first fight is full again")

	# Surrender repeats
	m = make()
	c = m[2]
	fight(c, "mae", "surrender", 1)
	check(near(c.getDefiance(), -6) && near(c.getCombatReputation(), -2), "first surrender")
	fight(c, "mae", "surrender", 1)
	check(near(c.getDefiance(), -7.5) and near(c.getCombatReputation(), -2), "repeat surrender: defiance at 25%, no more combat reputation")
	fight(c, "mae", "surrender", 2)
	check(near(c.getDefiance(), -13.5), "next day: full defiance loss again")
	m = make()
	fight(m[2], "mae", "win", 1)
	fight(m[2], "mae", "surrender", 1)
	check(near(m[2].getCombatReputation(), 6) and near(m[2].getDefiance(), 2 - 1.5), "surrender after a win the same day counts as a repeat: defiance -1.5, combat unchanged")

	# Invalid input
	m = make()
	c = m[2]
	check(c.applyCombatOutcome(null).empty() and c.applyCombatOutcome({}).empty() and fight(c, "", "win").empty() and fight(c, "pc", "win").empty() and fight(c, "mae", "bogus").empty() and c.applyCombatOutcome({"npcID": "mae", "outcome": "win", "day": "x"}).empty(), "invalid input is ignored")
	check(c.getCombatReputation() == 0.0 and m[0].cooldowns.empty() and m[0].directed_relationships.empty(), "invalid input stores nothing")

	# Cooldown storage, save/load, prune helpers
	m = make()
	c = m[2]
	fight(c, "mae", "win", 3)
	fight(c, "kit", "win", 3)
	var saved = JSON.parse(JSON.print(m[0].saveData())).result
	var t2 = StateScript.new()
	var r2 = RelScript.new(t2)
	var c2 = CombatScript.new(t2, r2)
	t2.loadData(saved)
	var again = fight(c2, "mae", "win", 3)
	check(again["reputation"].get("combat", 0.0) == 0.0 and near(c2.getCombatReputation(), 12), "daily record survives save and load (JSON floats)")
	var ids = CombatScript.getCooldownCharacterIDs(t2.cooldowns)
	check(ids.size() == 2 and ids.has("mae") and ids.has("kit"), "cooldown character ids: " + str(ids))
	CombatScript.removeCooldownsOf(t2.cooldowns, "mae")
	check(!t2.cooldowns.has("combat|mae") and t2.cooldowns.has("combat|kit"), "removeCooldownsOf")
	var again2 = fight(c2, "mae", "win", 3)
	check(again2["reputation"].has("combat"), "a pruned npc starts fresh")
	t2.clear()
	check(t2.cooldowns.empty() and c2.getCombatReputation() == 0.0, "reset clears cooldowns and reputation")

	# Attack multiplier: combat reputation
	m = make()
	c = m[2]
	r = m[1]
	check(near(c.attackMultiplier("npc"), 1.0), "multiplier is 1.0 at 0 reputation and 0 fear")
	c.addRep("combat", -100)
	check(near(c.attackMultiplier("npc"), 1.5), "combat -100: 1.5x")
	c.addRep("combat", 100)
	c.addRep("combat", 100)
	check(near(c.attackMultiplier("npc"), 0.5), "combat +100: 0.5x")
	c.addRep("combat", -100)
	check(near(c.attackMultiplier("npc"), 1.0), "combat 0 again: 1.0x")
	c.addRep("combat", 50)
	check(near(c.attackMultiplier("npc"), 0.75), "combat +50: 0.75x")
	c.addRep("combat", -50)
	# Fear
	var _f = r.setFeeling("npc", "pc", "fear", 50)
	check(near(c.attackMultiplier("npc"), 0.55), "fear 50: 0.55x")
	_f = r.setFeeling("npc", "pc", "fear", 100)
	check(near(c.attackMultiplier("npc"), 0.1), "fear 100: 0.1x")
	check(near(c.attackMultiplier("other"), 1.0), "another npc is unaffected by this npc's fear")
	c.addRep("combat", 100)
	check(near(c.attackMultiplier("npc"), 0.05), "both extremes multiply to 0.05, the floor")
	c.addRep("combat", 100)
	check(c.attackMultiplier("npc") >= 0.05 and c.attackMultiplier("npc") > 0.0, "never fully immune")
	check(near(c.attackMultiplier(null), 0.5) and near(c.attackMultiplier("pc"), 0.5), "invalid npc id uses reputation only")
	# Weak-looking player is more attractive than a feared one
	var weak = make()
	weak[2].addRep("combat", -80)
	var strong = make()
	strong[2].addRep("combat", 80)
	check(weak[2].attackMultiplier("npc") > 1.0 and strong[2].attackMultiplier("npc") < 1.0 and weak[2].attackMultiplier("npc") > strong[2].attackMultiplier("npc"), "weak looks like a better target than formidable")

	# Defeat weighting
	check(near(CombatScript.defeatPunishMultiplier("resisted"), 1.25) and near(CombatScript.defeatPunishMultiplier("surrendered"), 0.65) and near(CombatScript.defeatPunishMultiplier(""), 1.0) and near(CombatScript.defeatPunishMultiplier(null), 1.0), "defeat punish multipliers")

	# Bands and text
	var combatBands = [[-100, "Easy target"], [-61, "Easy target"], [-60, "Weak reputation"], [-21, "Weak reputation"], [-20, "Unproven"], [0, "Unproven"], [20, "Unproven"], [21, "Capable fighter"], [60, "Capable fighter"], [61, "Formidable"], [100, "Formidable"]]
	for entry in combatBands:
		check(CombatScript.getCombatBand(entry[0]) == entry[1], "combat band " + str(entry[0]))
	var defianceBands = [[-100, "Highly compliant"], [-61, "Highly compliant"], [-60, "Often compliant"], [-21, "Often compliant"], [-20, "Unpredictable"], [20, "Unpredictable"], [21, "Defiant"], [60, "Defiant"], [61, "Unbreakable"], [100, "Unbreakable"]]
	for entry in defianceBands:
		check(CombatScript.getDefianceBand(entry[0]) == entry[1], "defiance band " + str(entry[0]))
	m = make()
	m[2].addRep("combat", 6)
	m[2].addRep("defiance", -62.4)
	check(m[2].describeReputation() == "Combat Reputation: +6 — Unproven\nHow capable and dangerous the prison believes you are in a fight.\n\nDefiance: -62 — Highly compliant\nHow willing the prison believes you are to resist coercion.", "describeReputation: " + m[2].describeReputation())

	# Independence: high defiance with poor combat reputation, and the reverse
	m = make()
	for i in range(5):
		var _x = fight(m[2], "npc" + str(i), "loss", 0, 0.1)
	check(m[2].getDefiance() > 0.0 and m[2].getCombatReputation() < 0.0, "always resisting and losing: defiant but easy to beat")
	m = make()
	for i in range(5):
		var _y = fight(m[2], "npc" + str(i), "win", 0)
		var _z = fight(m[2], "other" + str(i), "surrender", 0)
	check(m[2].getCombatReputation() > 0.0 and m[2].getDefiance() < 0.0, "capable but often submits: separate values")

	# Messages
	var msg = CombatScript.formatReputationMessage({"combat": 6.0, "defiance": 2.0})
	check(msg == "Your reputation changed: [color=green]Combat +6[/color], [color=cyan]Defiance +2[/color].", "reputation message: " + msg)
	msg = CombatScript.formatReputationMessage({"combat": -4.0, "defiance": -6.0})
	check(msg == "Your reputation changed: [color=red]Combat -4[/color], [color=cyan]Defiance -6[/color].", "negative reputation message: " + msg)
	msg = CombatScript.formatPersonalMessage("Mae", {"fear": 10.0, "respect": 6.0})
	check(msg == "Mae now sees you differently: [color=green]Respect +6[/color], [color=yellow]Fear +10[/color].", "personal message: " + msg)
	msg = CombatScript.formatPersonalMessage("Mae", {"affection": -5.0, "trust": -8.0, "fear": 3.0})
	check(msg == "Mae now sees you differently: [color=red]Affection -5[/color], [color=red]Trust -8[/color], [color=yellow]Fear +3[/color].", "hostility message: " + msg)
	msg = CombatScript.formatPersonalMessage("Mae", {"fear": -4.0, "respect": -2.0})
	check(msg == "Mae now sees you differently: [color=red]Respect -2[/color], [color=yellow]Fear -4[/color].", "loss message: " + msg)
	check(CombatScript.formatReputationMessage({}) == "" and CombatScript.formatPersonalMessage("Mae", {"fear": 0.2}) == "", "no message when nothing is visible")

	print("CombatConsequencesTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

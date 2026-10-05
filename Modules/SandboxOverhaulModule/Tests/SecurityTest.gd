extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/SecurityTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const SecurityScript = preload("res://Modules/SandboxOverhaulModule/Security/Security.gd")
const SearchesScript = preload("res://Modules/SandboxOverhaulModule/Security/Searches.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func make():
	var s = StateScript.new()
	return [s, SecurityScript.new(s)]

func at(day:int, hour:float = 12.0) -> int:
	return SecurityScript.stamp(day, int(hour * 3600))

func ctx(day:int, hour:float, extra:Dictionary = {}) -> Dictionary:
	var c = {"now": at(day, hour), "day": day, "guard": "g1", "attitude": "standard", "leniency": 0.0, "fear": 0.0, "backup": false, "exposed": false, "canDress": true, "exemptPlace": false}
	for key in extra:
		c[key] = extra[key]
	return c

func entry(key:String, illegal:bool, protectedItem:bool = false, name:String = "thing", amount:int = 1) -> Dictionary:
	return {"key": key, "name": name, "amount": amount, "illegal": illegal, "protected": protectedItem}

func _init():
	# ---- Defaults, bands, clamping ----
	var m = make()
	var s = m[0]
	var sec = m[1]
	check(sec.getAttention() == 0.0 and JSON.print(s.security) == JSON.print(SecurityScript.defaults()) and !sec.isActive(), "attention defaults to 0")
	check(SecurityScript.label(0) == "Routine" and SecurityScript.label(19.9) == "Routine" and SecurityScript.label(20) == "Noticed" and SecurityScript.label(39) == "Noticed" and SecurityScript.label(40) == "Watched" and SecurityScript.label(59.9) == "Watched" and SecurityScript.label(60) == "High alert" and SecurityScript.label(79) == "High alert" and SecurityScript.label(80) == "Priority target" and SecurityScript.label(100) == "Priority target", "the five labels and their boundaries")
	check(SecurityScript.label(-50) == "Routine" and SecurityScript.label(500) == "Priority target", "labels clamp")
	var texts = {}
	for band in SecurityScript.BANDS:
		texts[band["text"]] = true
	check(texts.size() == 5, "every band has its own one-line explanation")
	check(near(sec.addAttention(30), 30.0) and near(sec.addAttention(500), 70.0) and near(sec.getAttention(), 100.0), "attention clamps at 100 and reports the real change")
	check(near(sec.addAttention(-500), -100.0) and near(sec.getAttention(), 0.0) and near(sec.addAttention(-5), 0.0), "and at 0")
	sec.setAttention("junk")
	check(sec.getAttention() == 0.0 or sec.getAttention() >= 0.0, "setAttention keeps a number")

	# ---- Offences ----
	m = make()
	s = m[0]
	sec = m[1]
	check(near(sec.recordOffence("minor", 1), 4.0) and near(sec.getAttention(), 4.0), "minor: +4")
	check(near(sec.recordOffence("violent", 1), 20.0) and near(sec.recordOffence("severe", 1), 30.0), "violent +20, severe +30")
	check(sec.recordOffence("nonsense", 1) == 0.0 and near(sec.getAttention(), 54.0), "unknown offences change nothing")
	m = make()
	sec = m[1]
	check(near(sec.recordOffence("contraband", 5), 10.0) and near(sec.recordOffence("contraband", 5), 15.0) and near(sec.recordOffence("contraband", 6), 20.0) and near(sec.recordOffence("contraband", 6), 20.0), "repeated contraband finds escalate (10, 15, 20, never more than 20)")
	m = make()
	sec = m[1]
	var _o = sec.recordOffence("contraband", 5)
	check(sec.recentContrabandCount(5) == 1 and sec.recentContrabandCount(8) == 1 and sec.recentContrabandCount(9) == 0 and sec.recentContrabandCount(2) == 0, "repeat finds are remembered for three days, then forgotten")
	check(near(sec.recordOffence("contraband", 20), 10.0), "a find after that is a first find again")
	m = make()
	sec = m[1]
	check(sec.recordGuardAttack(3) == 1 and sec.recordGuardAttack(4) == 2 and sec.recordGuardAttack(4) == 3 and sec.recordGuardAttack(9) == 1, "attacks on guards are counted for two days")
	m = make()
	sec = m[1]
	check(near(sec.recordResistance(2), 15.0) and near(sec.recordWonAgainstGuard(2), 25.0) and near(sec.getAttention(), 40.0), "resisting +15, beating a guard +25")
	sec.setAttention(70)
	check(near(sec.recordWonAgainstGuard(2), 15.0) and near(sec.getAttention(), 85.0), "winning is capped at 85: never pinned at the maximum")
	sec.setAttention(95)
	check(near(sec.recordWonAgainstGuard(2), 0.0) and near(sec.getAttention(), 95.0), "and never lowers a higher value")
	m = make()
	sec = m[1]
	var before = JSON.print(m[0].security)
	var _d = sec.decide(ctx(1, 12, {"exposed": true}), [0.0, 0.0])
	check(JSON.print(m[0].security) == before, "deciding never changes anything: unseen or unnoticed conduct adds no attention")

	# ---- Decay ----
	m = make()
	s = m[0]
	sec = m[1]
	sec.setAttention(50)
	check(near(sec.advanceDay(10), 0.0) and s.security["last_decay_day"] == 10 and near(sec.getAttention(), 50.0), "the first day only sets the baseline")
	var _i = sec.recordOffence("minor", 10)
	check(near(sec.getAttention(), 54.0), "setup: 54 after an incident on day 10")
	check(near(sec.advanceDay(10), 0.0), "no decay twice on the same day")
	check(near(sec.advanceDay(11), -4.0) and near(sec.getAttention(), 50.0), "a day with a recent incident: -4")
	check(near(sec.advanceDay(12), -4.0) and near(sec.getAttention(), 46.0), "day 12: -4")
	check(near(sec.advanceDay(13), -12.0) and near(sec.getAttention(), 34.0), "after three incident-free days the decay is -4 and -8 more")
	check(near(sec.advanceDay(20), -34.0) and near(sec.getAttention(), 0.0), "it reaches 0 and stops there")
	sec.setAttention(60)
	s.security["active"] = true
	check(near(sec.advanceDay(25), 0.0) and near(sec.getAttention(), 60.0), "no decay while a confrontation is unresolved")
	s.security["active"] = false
	check(near(sec.advanceDay(26), -12.0), "decay resumes once it is over")
	sec.setAttention(100)
	var _x = sec.advanceDay(100000)
	check(near(sec.getAttention(), 0.0), "an enormous gap cannot hang or leave it stuck")
	sec.setAttention(100)
	var _y = sec.advanceDay(3)
	check(near(sec.getAttention(), 100.0) and s.security["last_decay_day"] == 3, "a day number that went backwards (a foreign save) changes nothing and re-baselines")
	m = make()
	sec = m[1]
	sec.setAttention(100)
	var _b = sec.advanceDay(1)
	var daysToZero = 0
	for d in range(2, 40):
		var _z = sec.advanceDay(d)
		if(sec.getAttention() > 0.0):
			daysToZero += 1
	check(sec.getAttention() == 0.0 and daysToZero <= 12, "a quiet player at 100 is back to routine within about ten days: " + str(daysToZero))

	# ---- Ready ----
	check(SecurityScript.isReady(-1, 100, 50) and SecurityScript.isReady(10, 100, 200) and !SecurityScript.isReady(10, 100, 50) and SecurityScript.isReady(500, 100, 50), "a cooldown is ready when unset, over, or in the future")

	# ---- Warning ----
	m = make()
	s = m[0]
	sec = m[1]
	check(sec.getWarning(at(1)).empty(), "no warning at the start")
	sec.issueNudityWarning("g1", at(1, 10))
	check(sec.getWarning(at(1, 10.5))["guard"] == "g1" and !sec.getWarning(at(1, 10.5))["ignored"] and s.security["nudity_stamp"] == at(1, 10), "a warning names the guard")
	sec.markWarningIgnored()
	check(sec.getWarning(at(1, 11))["ignored"], "it can be marked ignored")
	check(sec.getWarning(at(1, 13.1)).empty() and sec.getWarning(at(1, 12.9)).size() > 0, "warnings expire after three hours")
	check(sec.getWarning(at(0, 10)).empty(), "a warning stamped in the future does not count")
	sec.clearWarning()
	check(sec.getWarning(at(1, 10.5)).empty(), "clearing works")
	sec.markWarningIgnored()
	check(!s.security["warning"]["ignored"], "nothing to ignore without a warning")

	# ---- Pending report ----
	m = make()
	sec = m[1]
	check(!sec.setPending("minor", "g1", 5) and !sec.setPending("violent", "", 5) and sec.getPending(6).empty(), "only violent or severe reports with a guard")
	check(sec.setPending("violent", "g1", at(1, 10)) and sec.getPending(at(1, 11))["kind"] == "violent", "a report is kept")
	check(sec.setPending("severe", "g2", at(1, 10)) and sec.getPending(at(1, 11))["guard"] == "g2" and !sec.setPending("violent", "g3", at(1, 10)) and sec.getPending(at(1, 11))["kind"] == "severe", "a worse report replaces a milder one, never the reverse")
	check(sec.getPending(at(1, 16.1)).empty() and !sec.getPending(at(1, 15.9)).empty(), "reports lapse after six hours")
	sec.clearPending()
	check(sec.getPending(at(1, 11)).empty(), "and can be cleared")

	# ---- Enforcement state, grace, stale ----
	m = make()
	s = m[0]
	sec = m[1]
	sec.beginEnforcement(at(2, 10))
	check(sec.isActive() and s.security["enforce_stamp"] == at(2, 10), "a confrontation is active")
	sec.setPending("violent", "g1", at(2, 10))
	sec.endEnforcement(at(2, 10.5), false)
	check(!sec.isActive() and sec.getPending(at(2, 11)).empty() and sec.inGrace(at(2, 12)) and !sec.inGrace(at(2, 13.6)), "complying: three hours of grace, the report is spent")
	sec.beginEnforcement(at(2, 14))
	sec.endEnforcement(at(2, 14.5), true)
	check(sec.inGrace(at(2, 20)) and !sec.inGrace(at(2, 21)), "resisting: six hours of grace")
	s.security["grace_until"] = at(2, 14) + 40 * 3600
	check(!sec.inGrace(at(2, 15)), "a grace longer than any real one (corrupt data) is ignored")
	sec.beginEnforcement(at(3, 10))
	check(!sec.dropStaleEnforcement(at(3, 10.5), true) and sec.isActive(), "a live confrontation is kept")
	check(sec.dropStaleEnforcement(at(3, 10.5), false) and !sec.isActive(), "one that no longer exists is dropped")
	sec.beginEnforcement(at(3, 10))
	check(sec.dropStaleEnforcement(at(3, 12.1), true) and !sec.isActive(), "one that is too old is dropped")
	sec.beginEnforcement(at(9, 10))
	check(sec.dropStaleEnforcement(at(3, 10), true) and !sec.isActive(), "one stamped in the future is dropped")
	check(!sec.dropStaleEnforcement(at(3, 10), false), "nothing to drop when none is active")

	# ---- Attitudes ----
	var again = true
	for i in range(100):
		if(SecurityScript.attitudeFor("guard" + str(i), 0.2) != SecurityScript.attitudeFor("guard" + str(i), 0.2)):
			again = false
	check(again, "an attitude is stable for the same guard and personality")
	var laxCount = 0
	var strictCount = 0
	var standardCount = 0
	for i in range(300):
		match SecurityScript.attitudeFor("guard" + str(i), 0.0):
			"lax":
				laxCount += 1
			"strict":
				strictCount += 1
			_:
				standardCount += 1
	check(standardCount >= 290 and laxCount + strictCount <= 10, "with an average personality guards are standard")
	var strictMean = 0
	var laxMean = 0
	for i in range(200):
		if(SecurityScript.attitudeFor("guard" + str(i), 0.9) == "strict"):
			strictMean += 1
		if(SecurityScript.attitudeFor("guard" + str(i), -0.9) == "lax"):
			laxMean += 1
	check(strictMean == 200 and laxMean == 200, "a very mean guard is strict and a very kind one lax")
	var mixed = {}
	for i in range(200):
		mixed[SecurityScript.attitudeFor("guard" + str(i), 0.4)] = true
	check(mixed.has("strict") and mixed.has("standard") and !mixed.has("lax"), "a mean guard is strict or standard, never lax")
	check(SecurityScript.attitudeFor("g", null) == SecurityScript.attitudeFor("g", 0.0) and SecurityScript.attitudeFor("g", "x") == SecurityScript.attitudeFor("g", 0.0) and SecurityScript.attitudeFor("g", 99.0) == SecurityScript.attitudeFor("g", 1.0), "an unknown or out-of-range personality value is safe")

	# ---- Leniency, fear ----
	var worst = 0.0
	var best = 0.0
	for level in [-5, -1, 0, 1, 2, 3, 4, 9]:
		for trust in [-500, -100, 0, 100, 500]:
			for respect in [-500, -100, 0, 100, 500]:
				var value = SecurityScript.leniency(level, trust, respect)
				worst = max(worst, value)
				best = min(best, value)
	check(worst <= 0.10 + 0.00001 and best >= -0.10 - 0.00001, "leniency never leaves +-0.10: " + str([best, worst]))
	check(SecurityScript.leniency(3, 0, 0) < 0.0 and SecurityScript.leniency(1, 0, 0) > 0.0 and SecurityScript.leniency(4, 0, 0) > SecurityScript.leniency(1, 0, 0) and near(SecurityScript.leniency(0, 0, 0), 0.0) and near(SecurityScript.leniency(2, 0, 0), 0.0), "Respected is lenient, Troublemaker and Prison Menace draw scrutiny, the rest are neutral")
	check(SecurityScript.leniency(2, 100, 100) < SecurityScript.leniency(2, 0, 0) and SecurityScript.leniency(2, -100, -100) > SecurityScript.leniency(2, 0, 0), "trust and respect soften, distrust and disrespect harden")
	check(near(SecurityScript.leniency("x", "y", null), 0.0), "junk leniency input is neutral")
	check(!SecurityScript.fearAvoidsAlone(59.9) and SecurityScript.fearAvoidsAlone(60) and !SecurityScript.fearAvoidsAlone(null) and !SecurityScript.fearAvoidsAlone("x"), "only a really afraid guard avoids facing the player alone")

	# ---- Chances ----
	var lax = SecurityScript.enforceChance("lax", 0, 0.0)
	var standard = SecurityScript.enforceChance("standard", 0, 0.0)
	var strict = SecurityScript.enforceChance("strict", 0, 0.0)
	check(lax < standard and standard < strict and near(lax, 0.10) and near(standard, 0.35) and near(strict, 0.65), "enforcement: lax 10%, standard 35%, strict 65% at attention 0")
	check(SecurityScript.enforceChance("standard", 100, 0.0) > standard and SecurityScript.enforceChance("strict", 100, 0.10) <= SecurityScript.ENFORCE_CHANCE_MAX and SecurityScript.enforceChance("lax", 0, -0.10) >= SecurityScript.ENFORCE_CHANCE_MIN and SecurityScript.enforceChance("strict", 100, 9.0) <= SecurityScript.ENFORCE_CHANCE_MAX, "attention raises it, bounds hold (3% to 90%), a bad leniency value is clamped")
	check(SecurityScript.enforceChance("standard", 0, -0.08) < standard and SecurityScript.enforceChance("standard", 0, 0.08) > standard, "leniency moves it by a few points")
	var sLax = SecurityScript.personalSearchChance("lax", 0, 0.0)
	var sStd = SecurityScript.personalSearchChance("standard", 0, 0.0)
	var sStrict = SecurityScript.personalSearchChance("strict", 0, 0.0)
	check(sLax < sStd and sStd < sStrict and sStd <= 0.011 and sStrict <= 0.03 and sLax <= 0.004, "routine search chance per encounter is tiny at attention 0: " + str([sLax, sStd, sStrict]))
	check(SecurityScript.personalSearchChance("standard", 50, 0.0) > SecurityScript.personalSearchChance("standard", 20, 0.0) and SecurityScript.personalSearchChance("standard", 100, 0.0) < 0.06 and SecurityScript.personalSearchChance("strict", 100, 0.10) <= SecurityScript.SEARCH_CHANCE_CAP and SecurityScript.personalSearchChance("strict", 100, 9.0) <= SecurityScript.SEARCH_CHANCE_CAP, "attention raises it but it stays far from certain")
	check(SecurityScript.cellSearchChance(0, 0.0) <= 0.021 and SecurityScript.cellSearchChance(100, 0.0) <= 0.16 and SecurityScript.cellSearchChance(100, 9.0) <= SecurityScript.CELL_SEARCH_CAP and SecurityScript.cellSearchChance(60, 0.0) > SecurityScript.cellSearchChance(0, 0.0), "a cell search is exceptional at low attention")

	# ---- Decisions: low attention, ordinary guard encounters ----
	m = make()
	s = m[0]
	sec = m[1]
	var stopped = 0
	for i in range(30):
		if(sec.decide(ctx(1, 8 + i % 10, {"attitude": ["lax", "standard", "strict"][i % 3]}), [0.5, 0.5])["action"] != "none"):
			stopped += 1
	check(stopped == 0, "a player at attention 0 can pass 30 ordinary guard encounters without being stopped")
	check(sec.decide(ctx(1, 12), [0.5, 0.005])["action"] == "search", "a very lucky roll is a routine search")
	check(sec.decide(ctx(1, 12), [0.5, 0.9])["action"] == "none" and sec.decide(ctx(1, 12), [])["action"] == "none", "an ordinary or missing roll is not")
	sec.markSearch(1, at(1, 12), true)
	check(sec.decide(ctx(1, 14), [0.5, 0.0])["action"] == "none" and sec.decide(ctx(2, 9), [0.5, 0.0])["action"] == "none", "after a routine search: no second one that day, nor the next (two-day cooldown)")
	check(sec.decide(ctx(3, 13), [0.5, 0.0])["action"] == "search", "but possible again after two days")
	m = make()
	s = m[0]
	sec = m[1]
	sec.setAttention(65)
	check(sec.decide(ctx(5, 12), [0.5, 0.9])["action"] == "none" and sec.decide(ctx(5, 12), [0.5, 0.03])["action"] == "search", "high attention: likelier, not certain")
	sec.markSearch(5, at(5, 12), true)
	check(sec.decide(ctx(5, 13), [0.5, 0.0])["action"] == "none" and sec.decide(ctx(6, 11), [0.5, 0.0])["action"] == "none", "even at High alert: one routine search a day, never closer than a day apart")
	check(sec.decide(ctx(6, 13), [0.5, 0.0])["action"] == "search", "at High alert the cooldown is a day")
	# Statistics with a seeded generator
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	m = make()
	s = m[0]
	sec = m[1]
	var searches = 0
	var longest = 0
	var streak = 0
	for day in range(1, 1001):
		var searchedToday = false
		for encounter in range(8):
			var decision = sec.decide(ctx(day, 8 + encounter), [rng.randf(), rng.randf()])
			if(decision["action"] == "search"):
				sec.markSearch(day, at(day, 8 + encounter), true)
				searches += 1
				searchedToday = true
		if(searchedToday):
			streak = 0
		else:
			streak += 1
			longest = max(longest, streak)
	check(searches > 0 and searches <= 130, "attention 0, eight guard encounters a day for 1000 days: " + str(searches) + " routine searches (roughly one in 12 days)")
	check(longest >= 10, "and runs of ten or more search-free days happen: " + str(longest))
	m = make()
	sec = m[1]
	sec.setAttention(100)
	var alertSearches = 0
	for day in range(1, 1001):
		for encounter in range(8):
			if(sec.decide(ctx(day, 8 + encounter), [rng.randf(), rng.randf()])["action"] == "search"):
				sec.markSearch(day, at(day, 8 + encounter), true)
				alertSearches += 1
	check(alertSearches > searches and alertSearches <= 1000, "at attention 100 searches are more frequent but never more than one a day: " + str(alertSearches))

	# ---- Decisions: nudity ----
	m = make()
	s = m[0]
	sec = m[1]
	var exposed = {"exposed": true}
	check(sec.decide(ctx(1, 10, exposed), [0.1, 0.9])["action"] == "warn_nudity" and sec.decide(ctx(1, 10, exposed), [0.9, 0.9])["action"] == "none", "a naked player in a public place may get a warning (standard guard: 35%)")
	check(sec.decide(ctx(1, 10, {"exposed": true, "exemptPlace": true}), [0.0, 0.9])["action"] == "none", "not in the showers, the medbay or their own cell")
	check(sec.decide(ctx(1, 10, {"exposed": true, "canDress": false}), [0.0, 0.9])["action"] == "none", "never someone who cannot dress")
	check(sec.decide(ctx(1, 10, {"exposed": false}), [0.0, 0.9])["action"] == "none", "never someone who is covered")
	check(sec.decide(ctx(1, 10, {"exposed": true, "attitude": "lax"}), [0.2, 0.9])["action"] == "none" and sec.decide(ctx(1, 10, {"exposed": true, "attitude": "lax"}), [0.05, 0.9])["action"] == "warn_nudity", "a lax guard usually ignores it")
	check(sec.decide(ctx(1, 10, {"exposed": true, "attitude": "strict"}), [0.6, 0.9])["action"] == "warn_nudity", "a strict guard warns more readily")
	sec.issueNudityWarning("g1", at(1, 10))
	check(sec.decide(ctx(1, 10.2, exposed), [0.0, 0.9])["action"] == "none", "no repeat warning inside the cooldown, and nothing to escalate yet")
	check(sec.decide(ctx(1, 10 + 25.0 / 60.0, exposed), [0.0, 0.9])["action"] == "escalate_nudity", "after the time to comply, still exposed: escalation")
	check(sec.decide(ctx(1, 10 + 25.0 / 60.0, {"exposed": true, "attitude": "lax"}), [0.0, 0.9])["action"] == "none", "a lax guard lets it go")
	check(sec.decide(ctx(1, 10 + 25.0 / 60.0, {"exposed": false}), [0.0, 0.9])["action"] == "none" and sec.decide(ctx(1, 10 + 25.0 / 60.0, {"exposed": true, "canDress": false}), [0.0, 0.9])["action"] == "none" and sec.decide(ctx(1, 10 + 25.0 / 60.0, {"exposed": true, "exemptPlace": true}), [0.0, 0.9])["action"] == "none", "never for someone who covered up, cannot dress or is somewhere it is allowed")
	check(sec.decide(ctx(1, 13.2, exposed), [0.0, 0.9])["action"] == "none", "an expired warning cannot be escalated, and a new one waits out the six-hour cooldown")
	check(sec.decide(ctx(1, 16.2, exposed), [0.0, 0.9])["action"] == "warn_nudity", "after the cooldown a new warning is possible")
	sec.clearWarning()
	check(sec.decide(ctx(1, 10 + 25.0 / 60.0, exposed), [0.0, 0.9])["action"] == "none", "escalation needs a live warning")

	# ---- Decisions: pending reports, grace, fear, unsafe ----
	m = make()
	s = m[0]
	sec = m[1]
	var _p = sec.setPending("violent", "g1", at(2, 9))
	check(sec.decide(ctx(2, 10), [0.9, 0.9])["action"] == "confront" and sec.decide(ctx(2, 10), [0.9, 0.9])["kind"] == "violent", "the guard who saw it confronts the player")
	check(sec.decide(ctx(2, 10, {"guard": "g2"}), [0.9, 0.9])["action"] == "none", "another guard who did not see it does nothing")
	check(sec.decide(ctx(2, 10, {"fear": 80.0}), [0.9, 0.9])["action"] == "none" and sec.decide(ctx(2, 10, {"fear": 80.0, "backup": true}), [0.9, 0.9])["action"] == "confront", "a terrified guard will not face the player alone, but will with backup")
	s.security["enforce_stamp"] = at(2, 9.9)
	check(sec.decide(ctx(2, 10), [0.9, 0.9])["action"] == "none", "never two confrontations within half an hour")
	s.security["enforce_stamp"] = -1
	s.security["grace_until"] = at(2, 14)
	check(sec.decide(ctx(2, 10), [0.9, 0.9])["action"] == "confront", "a serious witnessed offence is not forgiven by grace")
	sec.clearPending()
	check(sec.decide(ctx(2, 10, exposed), [0.0, 0.0])["action"] == "none", "during grace nothing routine happens: no warning, no search")
	check(sec.decide(ctx(2, 14.1, exposed), [0.0, 0.0])["action"] == "warn_nudity", "grace ends")
	s.security["active"] = true
	check(sec.decide(ctx(3, 10, exposed), [0.0, 0.0])["action"] == "none", "never while a confrontation is already running")
	s.security["active"] = false
	s.security["enforce_stamp"] = -1
	check(sec.decide(ctx(3, 10, {"exposed": true, "fear": 90.0}), [0.0, 0.0])["action"] == "none", "an afraid guard alone does not even warn")

	# ---- Cell searches ----
	m = make()
	s = m[0]
	sec = m[1]
	check(!sec.decideCellSearch(4, at(4, 7), 0.0, 0.99)["search"] and s.security["cell_check_day"] == 4, "an ordinary roll: no cell search")
	check(!sec.decideCellSearch(4, at(4, 9), 0.0, 0.0)["search"], "considered once a day")
	var cell = sec.decideCellSearch(5, at(5, 7), 0.0, 0.0)
	check(cell["search"] and !cell["targeted"], "a lucky roll at low attention: a routine cell search")
	sec.markCellSearch(at(5, 7))
	check(!sec.decideCellSearch(6, at(6, 7), 0.0, 0.0)["search"] and !sec.decideCellSearch(8, at(8, 7), 0.0, 0.0)["search"], "four-day cooldown")
	check(sec.decideCellSearch(9, at(9, 7), 0.0, 0.0)["search"], "and possible again after it")
	m = make()
	sec = m[1]
	sec.setAttention(70)
	cell = sec.decideCellSearch(12, at(12, 7), 0.0, 0.0)
	check(cell["search"] and cell["targeted"], "at High alert a cell search is targeted")
	m = make()
	sec = m[1]
	sec.setAttention(100)
	var cellCount = 0
	for day in range(1, 1001):
		var result = sec.decideCellSearch(day, at(day, 7), 0.0, rng.randf())
		if(result["search"]):
			cellCount += 1
			sec.markCellSearch(at(day, 7))
	check(cellCount > 0 and cellCount <= 250, "even at attention 100 cell searches are spread out: " + str(cellCount) + " in 1000 days")

	# ---- Searches: contraband selection ----
	var items = [entry("a", true, false, "Shiv"), entry("b", false, false, "Apple"), entry("c", true, true, "Important thing"), entry("a", true, false, "Shiv duplicate"), entry("d", true, false, "Baton", 2)]
	var taken = SearchesScript.selectConfiscations(items)
	check(taken.size() == 2 and taken[0]["key"] == "a" and taken[1]["key"] == "d", "only illegal, unprotected items, each once")
	check(SearchesScript.selectConfiscations([]).empty() and SearchesScript.selectConfiscations([entry("x", false), entry("y", false)]).empty(), "an empty search takes nothing")
	check(SearchesScript.selectConfiscations([{"key": "", "illegal": true}, {"illegal": true}, null, "x", {"key": 5, "illegal": true}]).empty(), "malformed entries are ignored")
	check(SearchesScript.describe(taken) == "Shiv, Baton x2", "one combined list: " + SearchesScript.describe(taken))
	check(items.size() == 5 and items[2]["protected"], "the input is not modified")
	var stashEntries = [entry("s1", true, false, "Key"), entry("s2", false, false, "Bread")]
	var hiddenEntries = [entry("h1", true, false, "Pill"), entry("h2", false, false, "Note")]
	var routine = SearchesScript.cellSearch(stashEntries, hiddenEntries, false, 0.0)
	check(routine["stash"].size() == 1 and routine["stash"][0]["key"] == "s1" and routine["hidden"].empty() and !routine["foundHidden"], "a routine cell search takes contraband from the stash and never finds the hidden compartment, whatever the roll")
	var missed = SearchesScript.cellSearch(stashEntries, hiddenEntries, true, 0.5)
	check(missed["hidden"].empty() and !missed["foundHidden"] and missed["stash"].size() == 1, "a targeted search that fails its roll reveals nothing hidden")
	var found = SearchesScript.cellSearch(stashEntries, hiddenEntries, true, 0.05)
	check(found["foundHidden"] and found["hidden"].size() == 1 and found["hidden"][0]["key"] == "h1", "a lucky targeted search takes only the contraband from it")
	check(SecurityScript.HIDDEN_DISCOVERY_CHANCE <= 0.15 and SecurityScript.HIDDEN_DISCOVERY_CHANCE > 0.0, "the discovery chance is small")
	var hits = 0
	for _n1 in range(10000):
		if(SearchesScript.cellSearch([], [entry("h", true)], true, rng.randf())["foundHidden"]):
			hits += 1
	check(hits > 800 and hits < 1600, "about 12% of targeted searches find it: " + str(hits) + " in 10000")
	var hitsRoutine = 0
	for _n2 in range(2000):
		if(SearchesScript.cellSearch([], [entry("h", true)], false, rng.randf())["foundHidden"]):
			hitsRoutine += 1
	check(hitsRoutine == 0, "routine searches never find it")
	var protectedSearch = SearchesScript.cellSearch([entry("p", true, true)], [entry("q", true, true)], true, 0.0)
	check(protectedSearch["stash"].empty() and protectedSearch["hidden"].empty(), "protected items are safe in both places")

	# ---- Fines ----
	check(SecurityScript.fineFor(1, 0, 0, 50) == 1 and SecurityScript.fineFor(1, 1, 0, 50) == 2 and SecurityScript.fineFor(3, 0, 0, 50) == 2 and SecurityScript.fineFor(3, 2, 0, 50) == 3 and SecurityScript.fineFor(9, 9, 2, 50) == 3, "fines run from 1 to 3 credits")
	check(SecurityScript.fineFor(3, 2, 2, 2) == 2 and SecurityScript.fineFor(3, 2, 2, 1) == 1 and SecurityScript.fineFor(3, 2, 2, 0) == 0 and SecurityScript.fineFor(3, 2, 2, -5) == 0, "a fine never exceeds the credits, so the balance never goes negative")
	check(SecurityScript.fineFor(1, 0, 2, 50) == 2, "being beaten adds a credit")

	# ---- Messages ----
	var empty = SearchesScript.personalSearchMessage("Guard Sam", [], 0, "")
	check(empty.find("green") != -1 and empty.find("found nothing") != -1 and empty.find("credit") == -1 and empty.find("red") == -1, "an empty search is green, with no fine")
	var full = SearchesScript.personalSearchMessage("Guard Sam", taken, 2, "ATT")
	check(full.find("[color=red]Guard Sam searched you and confiscated: Shiv, Baton x2.[/color]") != -1 and full.find("[color=red]2 credits taken as a fine.[/color]") != -1 and full.find("ATT") != -1, "a find is one red message listing the items, the fine and the attention: " + full)
	check(SearchesScript.personalSearchMessage("G", taken, 1, "").find("1 credit taken") != -1 and SearchesScript.personalSearchMessage("G", taken, 0, "").find("credit") == -1, "the fine is stated exactly, and not mentioned when zero")
	var cellMsg = SearchesScript.cellSearchMessage(found, 1, "ATT")
	check(cellMsg.find("While you were out") != -1 and cellMsg.find("Key, Pill") != -1 and cellMsg.find("hidden compartment") != -1 and cellMsg.find("1 credit") != -1, "a cell report lists everything and mentions the hidden compartment only when it was found")
	check(SearchesScript.cellSearchMessage(routine, 0, "").find("hidden") == -1 and SearchesScript.cellSearchMessage({"stash": [], "hidden": [], "foundHidden": false}, 0, "").find("found nothing") != -1, "an empty cell search says so")
	check(SecurityScript.attentionChangeText(10, 30).find("yellow") != -1 and SecurityScript.attentionChangeText(10, 30).find("rises by 10") != -1 and SecurityScript.attentionChangeText(10, 30).find("Noticed") != -1, "a rise is yellow")
	check(SecurityScript.attentionChangeText(-8, 12).find("cyan") != -1 and SecurityScript.attentionChangeText(-8, 12).find("falls by 8") != -1 and SecurityScript.attentionChangeText(0, 12) == "" and SecurityScript.attentionChangeText(0.2, 12) == "", "a fall is cyan, nothing changed prints nothing")

	# ---- Screen text ----
	m = make()
	s = m[0]
	sec = m[1]
	var screen = sec.getScreenText(at(3, 12))
	check(screen.find("0 / 100") != -1 and screen.find("Routine") != -1 and screen.find("no special attention") != -1 and screen.find("not been searched") != -1 and screen.find("warning") == -1 and screen.find("Last report") == -1, "the Security screen at the start: routine, not searched, no warning: " + screen)
	sec.setAttention(65)
	sec.markSearch(3, at(3, 11), false)
	sec.issueNudityWarning("g1", at(3, 11.5))
	sec.setReport("A guard searched you and found nothing.")
	screen = sec.getScreenText(at(3, 12))
	check(screen.find("65 / 100") != -1 and screen.find("High alert") != -1 and screen.find("searched recently") != -1 and screen.find("Active warning") != -1 and screen.find("Last report: A guard searched you") != -1, "high alert, recent search, active warning and the last report all show: " + screen)
	check(sec.getScreenText(at(8, 12)).find("not been searched") != -1 and sec.getScreenText(at(8, 12)).find("Active warning") == -1, "a search two days old is no longer recent, and the warning has expired")
	check(screen.find("roll") == -1 and screen.find("%") == -1 and screen.find("chance") == -1, "no probabilities are shown")

	# ---- Save, load, sanitise ----
	m = make()
	s = m[0]
	sec = m[1]
	sec.setAttention(42.5)
	var _r = sec.recordOffence("contraband", 7)
	sec.issueNudityWarning("g9", at(7, 9))
	var _ps = sec.setPending("violent", "g9", at(7, 9))
	sec.markSearch(7, at(7, 10), true)
	sec.markCellSearch(at(6, 7))
	sec.beginEnforcement(at(7, 11))
	sec.setReport("report")
	var saved = JSON.parse(JSON.print(s.saveData())).result
	var t = StateScript.new()
	t.loadData(saved)
	check(JSON.print(t.security) == JSON.print(s.security) and t.schema_version == StateScript.CURRENT_SCHEMA_VERSION and StateScript.CURRENT_SCHEMA_VERSION == 8, "security survives a JSON round trip at schema 5")
	check(typeof(t.security["search_stamp"]) == TYPE_INT and typeof(t.security["contraband_count"]) == TYPE_INT and typeof(t.security["attention"]) == TYPE_REAL and t.security["active"] == true, "stamps and counts load back as integers, the flag as a bool")
	var alias = s.saveData()
	alias["security"]["attention"] = 99.0
	alias["security"]["warning"]["guard"] = "evil"
	check(near(s.security["attention"], 52.5) and s.security["warning"]["guard"] == "g9", "saveData does not alias the live state")
	t.security["warning"]["guard"] = "changed"
	var u = StateScript.new()
	u.loadData(saved)
	check(u.security["warning"]["guard"] == "g9", "loading does not alias the saved data")
	check(JSON.print(SecurityScript.sanitize(null)) == JSON.print(SecurityScript.defaults()) and JSON.print(SecurityScript.sanitize("x")) == JSON.print(SecurityScript.defaults()) and JSON.print(SecurityScript.sanitize({})) == JSON.print(SecurityScript.defaults()), "garbage becomes the defaults")
	var dirty = SecurityScript.sanitize({"attention": 500, "search_stamp": "x", "cell_stamp": -80, "grace_until": 1e30, "active": "yes", "contraband_count": -4, "attack_count": 1000, "warning": {"kind": "weird", "guard": "g", "stamp": 5}, "pending": {"kind": "violent", "guard": 7, "stamp": 5}, "last_report": 5})
	check(near(dirty["attention"], 100.0) and dirty["search_stamp"] == -1 and dirty["cell_stamp"] == -1 and dirty["active"] == false and dirty["contraband_count"] == 0 and dirty["attack_count"] == 99 and dirty["warning"]["kind"] == "" and dirty["pending"]["kind"] == "" and dirty["last_report"] == "", "bad fields are repaired")
	var typed = SecurityScript.sanitize({"warning": {"kind": 5, "guard": "g", "stamp": 5}, "pending": {"kind": 7, "guard": "g", "stamp": 5}})
	check(typed["warning"]["kind"] == "" and typed["pending"]["kind"] == "", "a warning or report whose kind is not even text is dropped without an error")
	check(near(SecurityScript.sanitize({"attention": -7})["attention"], 0.0) and SecurityScript.sanitize({"attention": "50"})["attention"] == 0.0, "attention is clamped and must be a number")
	var longText = ""
	for _n3 in range(100):
		longText += "0123456789"
	var longReport = SecurityScript.sanitize({"last_report": longText})
	check(longReport["last_report"].length() == 400, "a report is capped")
	var stuck = StateScript.new()
	stuck.loadData({"schema_version": 5, "security": {"enforce_stamp": at(900, 0), "grace_until": at(900, 0), "nudity_stamp": at(900, 0), "search_stamp": at(900, 0), "cell_stamp": at(900, 0), "active": true, "active_stamp": at(900, 0)}})
	var stuckSec = SecurityScript.new(stuck)
	var stuckNow = at(5, 12)
	check(SecurityScript.isReady(stuck.security["search_stamp"], SecurityScript.PERSONAL_SEARCH_COOLDOWN, stuckNow) and SecurityScript.isReady(stuck.security["cell_stamp"], SecurityScript.CELL_SEARCH_COOLDOWN, stuckNow) and SecurityScript.isReady(stuck.security["nudity_stamp"], SecurityScript.NUDITY_COOLDOWN, stuckNow) and SecurityScript.isReady(stuck.security["enforce_stamp"], SecurityScript.ENFORCE_MIN_GAP, stuckNow) and !stuckSec.inGrace(stuckNow), "cooldowns from the future (a corrupt or foreign save) cannot stay stuck")
	check(stuckSec.dropStaleEnforcement(stuckNow, true) and !stuckSec.isActive(), "and neither can an active flag")
	var old = StateScript.new()
	old.loadData({"schema_version": 4, "security": {"attention": 80}, "reputation": {"combat": 5.0, "defiance": 0.0}})
	check(old.schema_version == 8 and old.security["attention"] == 0.0 and JSON.print(old.security) == JSON.print(SecurityScript.defaults()), "a version 4 save starts at attention 0 with no cooldowns, even with a stray field")
	check(old.reputation["combat"] == 5.0, "and keeps what it had")
	old.loadData({"schema_version": 1})
	check(old.schema_version == 8 and old.security["attention"] == 0.0, "a version 1 save migrates all the way")
	old.loadData({"schema_version": 99, "security": {"attention": 33}})
	check(old.schema_version == 99, "a newer save keeps its version")
	old.loadData({"schema_version": 5, "security": "junk"})
	check(JSON.print(old.security) == JSON.print(SecurityScript.defaults()), "a malformed security block loads clean")
	var kept = StateScript.new()
	kept.loadData({"schema_version": 5, "work": {"job": "mining"}, "upgrades": {"storage": true}, "cell_assignments": {"pc": {"block": "orange", "cell": 1}}, "reputation": {"combat": 12.0, "defiance": -3.0}, "security": {"attention": 30}})
	check(kept.work["job"] == "mining" and kept.upgrades["storage"] == true and kept.cell_assignments.has("pc") and kept.reputation["combat"] == 12.0 and near(kept.security["attention"], 30.0), "jobs, upgrades, cells and reputation load unchanged next to security")
	kept.clear()
	check(near(kept.security["attention"], 0.0) and JSON.print(kept.security) == JSON.print(SecurityScript.defaults()), "a new game resets enforcement state")

	# ---- Real guard values: the range BDCC really produces ----
	# Measured on 600 guards from BDCC's own GuardGenerator (SecurityBootTest repeats the measurement live): the Mean stat runs from about -0.89 to 1.0
	# (the stat itself is clamped to -1..1), 10% of guards are below -0.32, half below 0.08, 10% above 0.68, average 0.12. This table interpolates that shape.
	var table = [[0.0, -0.89], [0.1, -0.32], [0.5, 0.08], [0.9, 0.68], [1.0, 1.0]]
	var realCounts = {"lax": 0, "standard": 0, "strict": 0}
	var samples = 600
	for n in range(samples):
		var q = float(n) / float(samples - 1)
		var mean = 1.0
		for k in range(table.size() - 1):
			if(q >= table[k][0] and q <= table[k + 1][0]):
				var span = table[k + 1][0] - table[k][0]
				mean = table[k][1] + (table[k + 1][1] - table[k][1]) * ((q - table[k][0]) / span)
				break
		realCounts[SecurityScript.attitudeFor("dynamicnpc" + str(n + 1), mean)] += 1
	check(realCounts["lax"] + realCounts["standard"] + realCounts["strict"] == samples, "every guard can be classified")
	check(realCounts["standard"] > realCounts["strict"] and realCounts["standard"] > realCounts["lax"], "standard is the most common attitude with real values: " + str(realCounts))
	check(realCounts["strict"] <= samples * 0.40 and realCounts["strict"] >= samples * 0.10 and realCounts["lax"] >= samples * 0.10 and realCounts["lax"] <= samples * 0.40, "most guards are not strict, and both lax and strict guards exist: " + str(realCounts))
	check(SecurityScript.attitudeFor("dynamicnpc1", 0.0) == "standard" and SecurityScript.attitudeFor("cp_guard", 0.0) == "standard" and SecurityScript.attitudeFor("mirri", 0.7) == "strict", "the static guards (Mean 0, except Mirri at 0.7) classify as standard and strict")

	print("SecurityTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

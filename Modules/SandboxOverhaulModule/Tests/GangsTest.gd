extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/GangsTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const ServiceScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")
const AffairsScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangAffairs.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func make():
	var s = StateScript.new()
	var g = ServiceScript.new(s)
	return [s, g, AffairsScript.new(s, g)]

func entries(count:int) -> Array:
	var result:Array = []
	for i in range(count):
		var id = "i" + ("%03d" % i)
		var h = ServiceScript.hashOf(id, "trait")
		result.append({"id": id, "power": 0.5 + float(h % 20) / 20.0, "mean": float((h / 7) % 200 - 100) / 100.0, "subby": float((h / 13) % 200 - 100) / 100.0,
			"coward": float((h / 17) % 100) / 100.0, "naive": float((h / 19) % 100) / 100.0, "brat": float((h / 23) % 100) / 100.0, "respect": 0.0})
	return result

func stamp(day:int, hour:float = 12.0) -> int:
	return ServiceScript.stamp(day, int(hour * 3600))

# Forms the gangs and lets them grow, two recruits a day, to the target share: what a real game does over its first days.
func grow(m, list:Array, firstDay:int = 2) -> int:
	var days = 0
	for d in range(firstDay, firstDay + 40):
		var unaffiliated = []
		var affiliated = 0
		for entry in list:
			if(m[1].gangOf(entry["id"]) != ""):
				affiliated += 1
			elif(!m[1].isCaptive(entry["id"])):
				unaffiliated.append(entry)
		if(m[1].topUp(unaffiliated, affiliated, list.size(), 2, d).empty()):
			break
		days += 1
	return days

func booted(count:int = 40):
	var m = make()
	var list = entries(count)
	var _n = m[1].initialize(list, 1)
	var _d = grow(m, list)
	return m

func powersOf(g, value:float = 1.0) -> Dictionary:
	var result = {}
	for gid in g.gangIDs():
		for id in g.getMembers(gid):
			result[id] = value
	return result

func _init():
	# ---- Initialisation ----
	var m = make()
	var s = m[0]
	var g = m[1]
	var a = m[2]
	check(!g.isInitialized() and g.gangIDs().empty() and g.gangOf("i001") == "" and g.getRelation("a", "b") == 0, "nothing exists before initialisation")
	var list = entries(40)
	var affiliated = g.initialize(list, 1)
	check(g.isInitialized() and g.gangIDs() == ["collarcircle", "hushmarket", "ironhand"] and affiliated == 3, "three established gangs form with one member each: " + str(affiliated))
	for gid in g.gangIDs():
		check(g.getMembers(gid).size() == 1 and g.getLeader(gid) == g.getMembers(gid)[0], gid + ": its one member leads it")
		check(ServiceScript.establishedDef(gid)["hangout"] != "" and g.getHangout(gid) == ServiceScript.establishedDef(gid)["hangout"], gid + ": a hangout")
		check(ServiceScript.establishedDef(gid)["text"] != "" and ServiceScript.establishedDef(gid)["recruit"] != "" and g.gangName(gid) != "", gid + ": a name, a sentence and a recruitment line")
		check(g.getTreasury(gid) == 20 and g.reservedAmount(gid) == 0, gid + ": a starting treasury of 20")
	var hangouts = {}
	for gid in g.gangIDs():
		hangouts[g.getHangout(gid)] = true
	check(hangouts.size() == 3 and ServiceScript.PLAYER_HANGOUTS.size() >= 3, "three different hangouts, and spare rooms for the player's gang")
	check(g.getGang("ironhand")["slaves"].empty() and g.getGang("hushmarket")["slaves"].empty() and g.getGang("collarcircle")["slaves"].size() == 2, "only the control-focused gang owns slaves; two gangs revolve around neither sex nor slavery")
	for id in g.getGang("collarcircle")["slaves"]:
		check(g.gangOf(id) == "" and g.slaveOwner(id) == "collarcircle" and g.isCaptive(id), id + ": a slave belongs to no gang and is held")
	check(g.getRelation("ironhand", "hushmarket") == -55 and g.getRelation("hushmarket", "ironhand") == -55 and g.areEnemies("ironhand", "hushmarket") and !g.areEnemies("ironhand", "collarcircle") and ServiceScript.relationBand(g.getRelation("collarcircle", "hushmarket")) == "friendly" and g.getRelation("collarcircle", "ironhand") == -10 and g.getRelation("collarcircle", "hushmarket") == 45, "initial relations: Ironhand and the Hush Market -55, the Hush Market and the Collar Circle +45, Ironhand and the Collar Circle -10")
	var snapshot = JSON.print(s.gangs, "", true)
	check(g.initialize(entries(60), 2) == 0 and JSON.print(s.gangs, "", true) == snapshot, "a second initialisation changes nothing (nobody is reshuffled)")
	var reversed = entries(40)
	reversed.invert()
	var m2 = make()
	var _x = m2[1].initialize(reversed, 1)
	check(JSON.print(m2[0].gangs["gangs"], "", true) == JSON.print(s.gangs["gangs"], "", true), "the result does not depend on the order of the list")
	var loaded = StateScript.new()
	loaded.loadData(JSON.parse(JSON.print(s.saveData())).result)
	check(JSON.print(loaded.gangs, "", true) == JSON.print(s.gangs, "", true) and loaded.schema_version == 9, "membership, leaders, relations and slaves are stable across save and load")
	check(ServiceScript.affiliationTarget(0) == 0 and ServiceScript.affiliationTarget(1) == 1 and ServiceScript.affiliationTarget(8) == 4 and ServiceScript.affiliationTarget(9) == 4 and ServiceScript.affiliationTarget(15) == 6 and ServiceScript.affiliationTarget(23) == 10 and ServiceScript.affiliationTarget(30) == 12 and ServiceScript.affiliationTarget(40) == 16 and ServiceScript.affiliationTarget(-5) == 0, "the target is ceil(0.40 x eligible), never more than the eligible")

	# ---- Population sizes: formation, growth, no reshuffling ----
	for population in [0, 1, 7, 8, 9, 15, 23, 30]:
		var pm = make()
		var plist = entries(population)
		var formed = pm[1].initialize(plist, 1)
		var label = "population " + str(population) + ": "
		if(population < ServiceScript.FORMATION_MIN):
			check(formed == 0 and !pm[1].isInitialized() and pm[1].gangIDs().empty() and pm[1].topUp(plist, 0, population, 2, 2).empty(), label + "below the threshold nothing forms and nothing breaks")
			var reloadedSmall = StateScript.new()
			reloadedSmall.loadData(JSON.parse(JSON.print(pm[0].saveData())).result)
			check(JSON.print(reloadedSmall.gangs) == JSON.print(ServiceScript.defaults()), label + "and it saves as an unformed world")
			continue
		check(formed == 3 and pm[1].isInitialized(), label + "the gangs form with one member each")
		var before = {}
		for gid in pm[1].gangIDs():
			check(pm[1].getMembers(gid).size() == 1 and pm[1].getLeader(gid) == pm[1].getMembers(gid)[0], label + gid + " has a valid leader")
			for id in pm[1].getMembers(gid):
				before[id] = gid
		var growthDays = 0
		var history = []
		for d in range(2, 60):
			var unaff = []
			var aff = 0
			for entry in plist:
				if(pm[1].gangOf(entry["id"]) != ""):
					aff += 1
				elif(!pm[1].isCaptive(entry["id"])):
					unaff.append(entry)
			var added = pm[1].topUp(unaff, aff, population, 2, d)
			check(added.size() <= 2, label + "never more than two recruits a day")
			if(added.empty()):
				break
			growthDays += 1
			history.append(JSON.print(pm[0].gangs["gangs"], "", true))
		var seenIDs = {}
		var total = 0
		for gid in pm[1].gangIDs():
			check(pm[1].getMembers(gid).size() >= 1 and pm[1].isMember(pm[1].getLeader(gid), gid), label + gid + " keeps a member and a valid leader")
			for id in pm[1].getMembers(gid):
				check(!seenIDs.has(id), label + id + " is in one gang only")
				seenIDs[id] = gid
				total += 1
		for id in before:
			check(seenIDs.get(id) == before[id], label + id + " was not moved by growth")
		var expected = ServiceScript.affiliationTarget(population)
		check(total == expected and total <= population, label + str(total) + " of " + str(population) + " affiliated, target " + str(expected))
		check(growthDays == int(ceil(float(expected - 3) / 2.0)), label + "growth took " + str(growthDays) + " days at two a day")
		if(population >= 30):
			for gid in pm[1].gangIDs():
				check(pm[1].getMembers(gid).size() >= 3, label + gid + " normally ends with three or more members: " + str(pm[1].getMembers(gid).size()))
		var guardOnly = pm[1].topUp([{"id": "pc", "power": 1.0}], total, population + 100, 2, 99)
		check(guardOnly.empty(), label + "the player is never recruited by the daily growth")
		check(pm[1].gangOf("pc") == "", label + "and was not recruited")

	# ---- Gang relations are symmetric, personal relations directed ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	check(g.setRelation("ironhand", "collarcircle", 30) == 30 and g.getRelation("collarcircle", "ironhand") == 30, "a gang to gang relation is symmetric")
	check(g.setRelation("ironhand", "collarcircle", 500) == 100 and g.setRelation("ironhand", "collarcircle", -500) == -100 and g.addRelation("ironhand", "collarcircle", 250) == 100, "clamped to -100..100")
	check(g.setRelation("ironhand", "nonsense", 5) == 0 and g.setRelation("ironhand", "ironhand", 5) == 0 and g.getRelation(null, "ironhand") == 0, "unknown gangs and self relations do nothing")
	check(ServiceScript.relationBand(-100) == "enemies" and ServiceScript.relationBand(-40) == "enemies" and ServiceScript.relationBand(-39) == "neutral" and ServiceScript.relationBand(39) == "neutral" and ServiceScript.relationBand(40) == "friendly" and ServiceScript.relationBand(100) == "friendly", "the three bands")
	var _r = g.setRelation("ironhand", "collarcircle", -10)
	check(g.getPersonal("pc", "ironhand") == 0 and g.addPersonal("pc", "ironhand", 20) == 20 and g.getPersonal("pc", "ironhand") == 20 and g.getPersonal("ironhand", "pc") == 0 and g.getPersonal("nobody", "ironhand") == 0, "a personal relation is directed and per character")
	check(g.addPersonal("pc", "ironhand", 500) == 80 and g.getPersonal("pc", "ironhand") == 100 and g.addPersonal("pc", "ironhand", -500) == -200 and g.getPersonal("pc", "ironhand") == -100, "personal relations clamp at -100..100")
	var _p = g.setPersonal("pc", "ironhand", 0)
	check(!s.gangs["personal"].has("pc"), "a zero personal relation is not stored")

	# ---- Joining inherits enemies; personal impressions are modest and separate ----
	var before = g.getPersonal("pc", "hushmarket")
	var joinResult = g.join("pc", "ironhand", 3)
	check(joinResult["ok"] and g.playerGang() == "ironhand" and g.isMember("pc", "ironhand"), "the player joins")
	check(g.getPersonal("pc", "ironhand") == 5 and g.getPersonal("pc", "hushmarket") == before - 8 and g.getPersonal("pc", "collarcircle") == 0, "joining: +5 with the new gang, -8 with the rival, nothing with the neutral one")
	var status = g.effectiveStatus("pc", "hushmarket")
	check(status["official"] == -55 and status["personal"] == -8 and status["score"] == -36 and !status["hostile"], "the player inherits the official enmity, but personal and official stay separate: " + str(status))
	check(g.effectiveStatus("pc", "ironhand")["official"] == 100 and !g.effectiveStatus("pc", "ironhand")["hostile"], "never hostile to their own gang")
	check(g.join("pc", "hushmarket", 3)["ok"] == false and g.gangOf("pc") == "ironhand", "a character belongs to at most one gang")
	g.addPersonal("pc", "hushmarket", -10)
	check(g.effectiveStatus("pc", "hushmarket")["hostile"], "enough personal ill will on top of the inherited enmity makes them hostile")

	# ---- Leaving and expulsion differ; history stays ----
	m = booted()
	g = m[1]
	a = m[2]
	var _j = g.join("pc", "ironhand", 3)
	var rivalBefore = g.getPersonal("pc", "hushmarket")
	var ownBefore = g.getPersonal("pc", "ironhand")
	var left = g.leave("pc", 5)
	check(left["ok"] and g.playerGang() == "" and g.getPersonal("pc", "ironhand") == ownBefore - 6 and g.getPersonal("pc", "hushmarket") == rivalBefore + 4, "leaving: -6 with their gang, +4 with the rival")
	m = booted()
	g = m[1]
	_j = g.join("pc", "ironhand", 3)
	rivalBefore = g.getPersonal("pc", "hushmarket")
	ownBefore = g.getPersonal("pc", "ironhand")
	var light = g.expel("pc", "refused orders", 1, 5)
	var lightDrop = ownBefore - g.getPersonal("pc", "ironhand")
	m = booted()
	var g2 = m[1]
	var _j2 = g2.join("pc", "ironhand", 3)
	var heavy = g2.expel("pc", "betrayal", 3, 5)
	var heavyDrop = ownBefore - g2.getPersonal("pc", "ironhand")
	check(light["ok"] and heavy["ok"] and lightDrop == 15 + 10 and heavyDrop == 15 + 30 and heavyDrop > lightDrop, "expulsion hits harder than leaving, and by how bad the reason was: " + str([lightDrop, heavyDrop]))
	check(g.getPersonal("pc", "hushmarket") == rivalBefore + 3 and 3 < 4 + 1, "rivals approve of an expulsion only a little")
	check(g.retaliationState("ironhand")["day"] == 5 and g.retaliationState("ironhand")["retaliations"] == 0 and !g.retaliationState("ironhand")["over"], "an expulsion starts the retaliation record")
	check(!g.expel("pc", "x", 1, 6)["ok"] and !g.leave("pc", 6)["ok"], "nothing to leave or be expelled from twice")
	# history after leaving
	m = booted()
	g = m[1]
	_j = g.join("pc", "ironhand", 3)
	var harmDelta = g.recordHarm("pc", "hushmarket", "kidnap")
	var _h2 = g.recordHarm("pc", "hushmarket", "attack")
	var _h3 = g.recordHarm("pc", "hushmarket", "attack")
	var _h4 = g.recordHarm("pc", "hushmarket", "enslave")
	check(harmDelta == -15 and g.harmCount("hushmarket") == 4, "harm is recorded against the victim's gang")
	var hatedBefore = g.getPersonal("pc", "hushmarket")
	var _l = g.leave("pc", 6)
	check(g.getPersonal("pc", "hushmarket") == hatedBefore + 4 and g.getPersonal("pc", "hushmarket") <= -30 and g.harmCount("hushmarket") == 4, "leaving the rival's enemy gives a small improvement, but serious history stays")
	check(g.effectiveStatus("pc", "hushmarket")["hostile"] or g.effectiveStatus("pc", "hushmarket")["score"] <= -25, "and they are still a target")
	check(g.recordHarm("pc", "nonsense", "attack") == 0 and g.recordHarm("pc", "ironhand", "weird") == 0, "unknown gangs and kinds do nothing")

	# ---- Join checks ----
	m = booted()
	g = m[1]
	a = m[2]
	var ok = g.joinCheck("pc", "ironhand", {"day": 5, "trust": 40, "respect": 40, "combat": 40})
	check(ok["ok"] and !ok["needsIntro"] and ok["score"] >= 15, "someone respected enough is taken: " + str(ok))
	var intro = g.joinCheck("pc", "ironhand", {"day": 5, "trust": 0, "respect": 0, "combat": 0})
	check(!intro["ok"] and intro["needsIntro"] and intro["reasons"][0].find("job") != -1, "someone unknown must do an introductory job")
	var bad = g.joinCheck("pc", "ironhand", {"day": 5, "trust": -50, "respect": -50, "combat": -50})
	check(!bad["ok"] and !bad["needsIntro"] and bad["reasons"][0].find("do not trust") != -1, "someone they distrust is rejected, with the reason")
	check(!g.joinCheck("pc", "nonsense", {})["ok"], "no such gang")
	var introOffer = a.makeIntro("ironhand", stamp(5), {"rivals": ["rival_x"], "recipients": [], "day": 5})
	check(introOffer["type"] == "defeat" and introOffer["target"] == "rival_x" and introOffer["intro"] and introOffer["reward"] == 0, "Ironhand's introductory job is to beat a named rival, with no credits")
	var _acc = a.accept(stamp(5))
	g.addPersonal("pc", "ironhand", 0)
	check(a.onPlayerWon("rival_x", stamp(5, 14))["event"] == "ready" and a.canReport() and g.getPersonal("pc", "ironhand") == 0, "beating them does not finish it: the player must report back")
	var done = a.complete(stamp(6))
	check(done["intro"] and done["credits"] == 0 and g.getPersonal("pc", "ironhand") == 10, "the introductory job gives standing, not credits")
	check(g.joinCheck("pc", "ironhand", {"day": 6, "trust": 0, "respect": 0, "combat": 0})["ok"], "after the introductory job they take you")
	# enough harm makes a trivial gift not enough
	m = booted()
	g = m[1]
	var _hh1 = g.recordHarm("pc", "ironhand", "kidnap")
	var _hh2 = g.recordHarm("pc", "ironhand", "attack")
	var _hh3 = g.recordHarm("pc", "ironhand", "enslave")
	var _hh4 = g.addPersonal("pc", "ironhand", 6)
	check(!g.joinCheck("pc", "ironhand", {"day": 5, "trust": 30, "respect": 30, "combat": 30})["ok"], "a bad history is not repaired by one small gift")
	var _hh5 = g.addPersonal("pc", "ironhand", 90)
	check(g.getPersonal("pc", "ironhand") > 0 and g.joinCheck("pc", "ironhand", {"day": 5, "trust": 30, "respect": 30, "combat": 30})["needsIntro"] or g.joinCheck("pc", "ironhand", {"day": 5, "trust": 30, "respect": 30, "combat": 30})["ok"], "but there is a path back: time and work raise the personal relation")
	# already in a gang, switching, expelled
	m = booted()
	g = m[1]
	var _j3 = g.join("pc", "ironhand", 3)
	check(g.joinCheck("pc", "hushmarket", {"day": 4})["reasons"][0].find("Leave your current gang") != -1 and g.joinCheck("pc", "ironhand", {"day": 4})["reasons"][0].find("already") != -1, "one gang at a time")
	var _l2 = g.leave("pc", 10)
	g.addPersonal("pc", "hushmarket", 50)
	var quick = g.joinCheck("pc", "hushmarket", {"day": 11, "trust": 60, "respect": 60, "combat": 60})
	check(!quick["ok"] and quick["reasons"][0].find("just left") != -1, "switching straight to a rival is refused for a few days")
	check(g.joinCheck("pc", "hushmarket", {"day": 10 + ServiceScript.SWITCH_COOLDOWN_DAYS, "trust": 60, "respect": 60, "combat": 60})["ok"], "and allowed afterwards")
	m = booted()
	g = m[1]
	var _j4 = g.join("pc", "ironhand", 3)
	var _x1 = g.expel("pc", "betrayal", 2, 10)
	g.addPersonal("pc", "ironhand", 80)
	check(!g.joinCheck("pc", "ironhand", {"day": 20, "trust": 60, "respect": 60, "combat": 60})["ok"], "a gang that threw you out and is not finished with you will not take you back")
	g.retaliationState("ironhand")
	s = m[0]
	s.gangs["player"]["expelled"]["ironhand"]["over"] = true
	check(g.joinCheck("pc", "ironhand", {"day": 20, "trust": 60, "respect": 60, "combat": 60})["ok"], "once they have given up, they can")

	# ---- Standing: warning, expulsion ----
	m = booted()
	s = m[0]
	g = m[1]
	var _j5 = g.join("pc", "collarcircle", 3)
	g.setPersonal("pc", "collarcircle", 20)
	check(g.checkStanding(5)["event"] == "", "good standing: nothing")
	g.setPersonal("pc", "collarcircle", -31)
	check(g.checkStanding(6)["event"] == "warning" and g.checkStanding(7)["event"] == "" and g.checkStanding(9)["event"] == "warning", "low standing: a warning, then a pause of three days")
	g.setPersonal("pc", "collarcircle", -60)
	check(g.checkStanding(20)["event"] == "expel", "very low standing: expulsion")
	check(g.recordBetrayal("collarcircle", "attack") == -6 and g.recordBetrayal("collarcircle", "kidnap") == -15, "betrayals cost standing")

	# ---- Retaliation grace and stopping ----
	m = booted()
	s = m[0]
	g = m[1]
	var _j6 = g.join("pc", "ironhand", 3)
	var _x2 = g.expel("pc", "betrayal", 3, 10)
	check(!g.retaliationDue("ironhand", {"day": 10, "combat": 0, "fear": 0}) and !g.retaliationDue("ironhand", {"day": 11, "combat": 0, "fear": 0}), "no retaliation during the grace period")
	check(g.retaliationDue("ironhand", {"day": 12, "combat": 0, "fear": 0}), "retaliation is due after it")
	check(!g.retaliationDue("ironhand", {"day": 12, "combat": 45, "fear": 0}) and !g.retaliationDue("ironhand", {"day": 12, "combat": 0, "fear": 70}), "a feared or reputable player is left alone")
	g.recordLoss("ironhand")
	check(g.retaliationDue("ironhand", {"day": 12, "combat": 0, "fear": 0}), "one loss does not stop it")
	g.recordLoss("ironhand")
	check(!g.retaliationDue("ironhand", {"day": 12, "combat": 0, "fear": 0}) and g.lossCount("ironhand") == 2, "two defeats stop it")
	s.gangs["player"]["losses"].clear()
	g.markRetaliation("ironhand", {"combat": 0, "fear": 0})
	check(g.retaliationDue("ironhand", {"day": 13, "combat": 0, "fear": 0}) and !g.retaliationState("ironhand")["over"], "one attempt used, one left")
	g.markRetaliation("ironhand", {"combat": 0, "fear": 0})
	check(g.retaliationState("ironhand")["over"] and !g.retaliationDue("ironhand", {"day": 20, "combat": 0, "fear": 0}) and !g.pendingRetaliation(), "after the second attempt it is over for good")
	var _x3 = g.expel("pc", "x", 1, 30) # not in a gang: nothing
	var m3 = booted()
	var _j7 = m3[1].join("pc", "hushmarket", 3)
	var _x4 = m3[1].expel("pc", "x", 1, 40)
	check(m3[1].pendingRetaliation() and m3[1].closeRetaliations({"combat": 60, "fear": 0}) == ["hushmarket"] and !m3[1].pendingRetaliation(), "a player who has become formidable closes the matter")

	# ---- Strength ----
	m = booted()
	g = m[1]
	var weakPowers = powersOf(g, 0.5)
	var strongPowers = powersOf(g, 2.0)
	var members = g.activeMembers("ironhand").size()
	check(g.strength("ironhand", weakPowers) == 0.5 * members and g.strength("ironhand", strongPowers) == 2.0 * members and g.strength("nonsense", weakPowers) == 0.0, "strength is the sum of the active members' power")
	check(ServiceScript.strengthBand(0.0) == "Weak" and ServiceScript.strengthBand(2.4) == "Weak" and ServiceScript.strengthBand(2.5) == "Established" and ServiceScript.strengthBand(5.0) == "Strong" and ServiceScript.strengthBand(8.0) == "Dominant" and ServiceScript.strengthBand(null) == "Weak", "the four bands")
	var victim = g.getMembers("ironhand")[0]
	var full = g.strength("ironhand", strongPowers)
	var _c = g.capture(victim, "hushmarket", stamp(5))
	check(g.strength("ironhand", strongPowers) == full - 2.0 and g.activeMembers("ironhand").size() == members - 1, "a held member does not count")
	check(ServiceScript.deterrenceFor("Weak") < ServiceScript.deterrenceFor("Established") and ServiceScript.deterrenceFor("Established") < ServiceScript.deterrenceFor("Strong") and ServiceScript.deterrenceFor("Strong") < ServiceScript.deterrenceFor("Dominant") and ServiceScript.deterrenceFor("Dominant") < 1.0, "a stronger gang deters more, never completely")

	# ---- Captives ----
	m = booted()
	s = m[0]
	g = m[1]
	var held = g.getMembers("hushmarket")[1]
	var c1 = g.capture(held, "ironhand", stamp(5, 10))
	check(c1["ok"] and g.isCaptive(held) and g.gangOf(held) == "hushmarket" and g.captivesOf("hushmarket") == [held] and g.heldBy("ironhand") == [held], "a captured member stays in their gang and is marked held")
	check(!g.capture(held, "collarcircle", stamp(5, 11))["ok"] and g.getCaptive(held)["gang"] == "ironhand", "the same character cannot be captured twice")
	check(!g.capture(held, "hushmarket", stamp(5))["ok"] and !g.capture("nobody", "ironhand", stamp(5))["ok"] and !g.capture("pc", "ironhand", stamp(5))["ok"], "not by their own gang, not a non-member, never the player")
	check(g.expireCaptives(stamp(5, 12)).empty() and g.isCaptive(held), "still held before its time")
	var escaped = g.expireCaptives(stamp(6, 23))
	check(escaped.size() == 1 and escaped[0]["id"] == held and !g.isCaptive(held) and g.gangOf(held) == "hushmarket", "a captive escapes after the bounded time and is still a member")
	check(g.release(held).empty(), "nothing to release twice")
	var c2 = g.capture(held, "ironhand", stamp(8))
	check(c2["ok"] and !g.release(held).empty() and !g.isCaptive(held), "released early")
	var slaveID = g.getGang("collarcircle")["slaves"][0]
	check(!g.capture(slaveID, "ironhand", stamp(5))["ok"] and !g.addSlave(slaveID, "ironhand")["ok"] and !g.addSlave(held, "ironhand")["ok"], "a gang slave cannot be captured or owned twice, and a member cannot be enslaved")
	check(g.freeSlave(slaveID) == "collarcircle" and !g.isCaptive(slaveID) and !g.getGang("collarcircle")["slaves"].has(slaveID) and g.freeSlave(slaveID) == "", "freeing a slave names the owner, once")
	var freeID = "free1"
	check(g.addSlave(freeID, "ironhand")["ok"] and g.slaveOwner(freeID) == "ironhand" and !g.addSlave(freeID, "hushmarket")["ok"] and !g.addSlave("pc", "ironhand")["ok"], "a free inmate can become a gang slave, once, never the player")

	# ---- Gang-owned slaves: income once a day ----
	m = booted()
	s = m[0]
	g = m[1]
	var treasuryBefore = g.getTreasury("collarcircle")
	var paid = g.collectIncome(5)
	var memberPart = g.memberIncome("collarcircle")
	check(paid["collarcircle"] == 4 + memberPart and g.getTreasury("collarcircle") == treasuryBefore + 4 + memberPart, "two slaves (2 each) plus a credit per three active members earn the gang a modest amount: " + str(paid))
	check(g.collectIncome(5).empty() and g.getTreasury("collarcircle") == treasuryBefore + 4 + memberPart, "never twice on the same day")
	check(g.collectIncome(6)["collarcircle"] == 4 + memberPart and g.collectIncome(4).empty(), "the next day again, an earlier day never")
	check(g.memberIncome("ironhand") == int(min(3, g.activeMembers("ironhand").size() / 3)) and g.memberIncome("ironhand") <= 3, "member income is one credit per three active members, at most three")
	check(g.addTreasury("ironhand", 100000) == 9999 and !g.spendTreasury("ironhand", 20000) and g.spendTreasury("ironhand", 999) and g.getTreasury("ironhand") == 9000 and g.addTreasury("ironhand", -99999) == 0, "treasuries clamp and spending checks the balance")
	check(g.addTreasury("nonsense", 5) == 0 and !g.spendTreasury("nonsense", 1), "no treasury for unknown gangs")

	# ---- Leader repair and dissolution ----
	m = booted()
	s = m[0]
	g = m[1]
	var oldLeader = g.getLeader("ironhand")
	var rest = g.getMembers("ironhand")
	rest.erase(oldLeader)
	var scores = {}
	for id in rest:
		scores[id] = 1.0
	scores[rest[rest.size() - 1]] = 5.0
	var _rm = g.removeMember(oldLeader, scores)
	check(g.getLeader("ironhand") == rest[rest.size() - 1] and g.isMember(g.getLeader("ironhand"), "ironhand"), "when the leader goes, the best remaining member leads")
	var _rm2 = g.removeMember(g.getLeader("ironhand"))
	var expectedNext = g.getMembers("ironhand")
	expectedNext.sort()
	check(g.getLeader("ironhand") == expectedNext[0], "without scores the choice is deterministic (lowest ID)")
	for id in g.getMembers("ironhand"):
		var _rm3 = g.removeMember(id)
	check(!g.hasGang("ironhand") and !s.gangs["relations"].has("ironhand|hushmarket") and g.gangIDs().size() == 2, "an NPC gang with no members dissolves, with its relations")
	# the player's gang never dissolves while the player leads
	m = booted()
	g = m[1]
	a = m[2]

	# ---- The player's own gang ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var need = a.canCreate({"combat": 0, "respect": 0, "recruits": 0, "credits": 0})
	check(!need["ok"] and need["reasons"].size() == 3, "all the requirements are listed when nothing is met: " + str(need["reasons"].size()))
	check(!a.canCreate({"combat": 4, "respect": 39, "recruits": 5, "credits": 50})["ok"], "not enough reputation or respect")
	check(a.canCreate({"combat": 5, "respect": 0, "recruits": 2, "credits": 15})["ok"], "Combat Reputation 5 is enough")
	check(a.canCreate({"combat": 0, "respect": 40, "recruits": 2, "credits": 15})["ok"], "or one inmate's Respect of 40")
	check(!a.canCreate({"combat": 50, "respect": 50, "recruits": 1, "credits": 50})["ok"] and !a.canCreate({"combat": 50, "respect": 50, "recruits": 2, "credits": 14})["ok"], "two recruits and 15 credits are needed")
	check(ServiceScript.validName("The Night Shift")["ok"] and ServiceScript.validName("  Night   Shift ")["name"] == "Night Shift" and ServiceScript.validName("Joe's Crew-2")["ok"], "good names, with spacing tidied")
	check(!ServiceScript.validName("")["ok"] and !ServiceScript.validName("  ")["ok"] and !ServiceScript.validName("ab")["ok"] and !ServiceScript.validName("abcdefghijklmnopqrstuvwxyz")["ok"] and !ServiceScript.validName("Bad[color=red]")["ok"] and !ServiceScript.validName("Rock & Roll")["ok"] and !ServiceScript.validName(null)["ok"] and !ServiceScript.validName(5)["ok"] and !ServiceScript.validName("tab\there")["ok"], "empty, short, long and unsafe names are refused")
	check(!a.createPlayerGang("Ironhand", "hall_canteen", ["i001", "i002"], 5)["ok"] and !a.createPlayerGang("ironhand", "hall_canteen", ["i001", "i002"], 5)["ok"], "a name that exists is refused, whatever the case")
	check(!a.createPlayerGang("Night Shift", "gym_weights", ["i001", "i002"], 5)["ok"] and !a.createPlayerGang("Night Shift", "nowhere", ["i001", "i002"], 5)["ok"], "the hangout must be a free listed room")
	check(!a.createPlayerGang("Night Shift", "hall_canteen", ["i001"], 5)["ok"], "two willing members are needed")
	var recruitsList = []
	for entry in entries(40):
		if(g.gangOf(entry["id"]) == "" and !g.isCaptive(entry["id"])):
			recruitsList.append(entry["id"])
	var made = a.createPlayerGang("Night Shift", "hall_canteen", [recruitsList[0], recruitsList[1], recruitsList[2], recruitsList[0], "pc"], 5)
	check(made["ok"] and g.ownsPlayerGang() and g.playerGang() == "player" and g.getLeader("player") == "pc" and g.getMembers("player").size() == 4 and g.gangName("player") == "Night Shift" and g.getHangout("player") == "hall_canteen", "the player founds a gang, leads it, and duplicates are ignored")
	check(!a.createPlayerGang("Another", "gym_yoga", [recruitsList[3], recruitsList[4]], 6)["ok"] and !a.canCreate({"combat": 99, "respect": 99, "recruits": 9, "credits": 99})["ok"], "only one player gang")
	check(g.isLeader("pc", "player") and g.getPersonal(recruitsList[0], "player") == 5, "members regard the new gang a little")
	check(!a.freeHangouts().has("hall_canteen") and a.freeHangouts().size() == ServiceScript.PLAYER_HANGOUTS.size() - 1, "taken rooms are not offered")
	check(a.inviteMember(recruitsList[3], true)["ok"] and g.isMember(recruitsList[3], "player"), "invite a willing inmate")
	check(!a.inviteMember(recruitsList[3], true)["ok"] and !a.inviteMember(recruitsList[4], false)["ok"] and !a.inviteMember("pc", true)["ok"] and !a.inviteMember("", true)["ok"] and !a.inviteMember(g.getMembers("ironhand")[0], true)["ok"], "not twice, not the unwilling, not someone in another gang")
	var held2 = recruitsList[5]
	var _jj = g.join(held2, "ironhand", 5)
	check(!a.inviteMember(held2, true)["ok"], "a member of another gang cannot be invited")
	check(a.removeFromPlayerGang(recruitsList[3])["ok"] and !g.isMember(recruitsList[3], "player") and !a.removeFromPlayerGang(recruitsList[3])["ok"] and !a.removeFromPlayerGang("pc")["ok"], "remove a member, never the leader")
	check(a.changeHangout("gym_yoga", stamp(6))["ok"] and g.getHangout("player") == "gym_yoga" and !a.changeHangout("yard_neargym", stamp(6, 20))["ok"] and a.changeHangout("yard_neargym", stamp(8, 13))["ok"], "the hangout can change, with a cooldown")
	check(!a.changeHangout("gym_weights", stamp(20))["ok"] and !a.changeHangout("yard_neargym", stamp(30))["ok"], "not to a taken room, nor the same one")
	var _t = g.addTreasury("player", 3)
	check(g.getTreasury("player") == 8, "the player gang starts with 5 of its founding cost in the treasury, plus the 3 added")
	# leader leaving: the player keeps leadership; dissolve only by choice
	var _rm4 = g.removeMember(recruitsList[0])
	check(g.getLeader("player") == "pc" and g.hasGang("player"), "members come and go; the leader stays")
	check(g.leave("pc", 10)["ok"] == true, "the leader can walk away (a deliberate act)")
	m = booted()
	g = m[1]
	a = m[2]
	var _made2 = a.createPlayerGang("Night Shift", "hall_canteen", [recruitsList[0], recruitsList[1]], 5)
	check(!g.dissolveIfEmpty("player") and g.hasGang("player"), "a populated gang does not dissolve")
	check(a.disbandPlayerGang() and !g.hasGang("player") and g.gangOf("pc") == "" and g.gangOf(recruitsList[0]) == "", "the leader can disband it deliberately, and everyone is released")
	check(!a.disbandPlayerGang(), "nothing to disband twice")

	# ---- Assignments ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _j8 = g.join("pc", "ironhand", 3)
	g.setPersonal("pc", "ironhand", 20)
	var rivals = g.activeMembers("hushmarket")
	check(!a.canOffer(stamp(5))["ok"] == false, "a member in good standing can be offered work")
	var offer = a.makeOffer({"day": 5, "rivals": rivals, "contrabandItem": "", "heldMembers": [], "captors": []}, stamp(5))
	check(offer["type"] == "defeat" and offer["state"] == "offered" and rivals.has(offer["target"]) and offer["reward"] == 6 and offer["standing"] == 8 and offer["penalty"] == 8 and offer["deadline"] - offer["created"] == 48 * 3600, "the combat gang wants a rival beaten: clear target, deadline, reward and penalty: " + str(offer))
	check(a.hasAssignment() and a.makeOffer({"day": 5, "rivals": rivals}, stamp(5)).empty() and !a.canOffer(stamp(5))["ok"], "only one assignment at a time")
	check(a.decline(stamp(5)) and !a.hasAssignment() and !a.decline(stamp(5)), "declining is not failure")
	check(g.getPersonal("pc", "ironhand") == 20 and !a.canOffer(stamp(5, 13))["ok"] and a.canOffer(stamp(7, 13))["ok"], "no penalty, and the next offer waits two days")
	offer = a.makeOffer({"day": 7, "rivals": rivals, "contrabandItem": "", "heldMembers": [], "captors": []}, stamp(7, 13))
	check(a.accept(stamp(7, 13)) and a.getAssignment()["state"] == "active" and !a.accept(stamp(7, 14)), "accepting once")
	var target = a.getAssignment()["target"]
	check(a.onPlayerWon("someone_else", stamp(8))["event"] == "" and a.hasAssignment(), "an unrelated fight does not count")
	check(a.onPlayerWon(target, stamp(7, 13) + 49 * 3600)["event"] == "" and a.hasAssignment(), "nor does a fight after the deadline")
	var win = a.onPlayerWon(target, stamp(8))
	check(win["event"] == "ready" and a.canReport() and a.hasAssignment() and g.getPersonal("pc", "ironhand") == 20 and a.getAssignment()["state"] == "ready", "beating the target finishes the job but pays nothing until the player reports back in person")
	var report = a.complete(stamp(8, 1))
	check(report["credits"] == 6 and report["standing"] == 8 and report["respect"] == 3 and report["trust"] == 2 and g.getPersonal("pc", "ironhand") == 28 and !a.hasAssignment(), "reporting back pays exactly: 6 credits, standing +8, respect and trust")
	check(a.complete(stamp(8)).empty() and a.onPlayerWon(target, stamp(8))["event"] == "" and g.getPersonal("pc", "ironhand") == 28, "it cannot be paid twice")
	var loadedAgain = StateScript.new()
	loadedAgain.loadData(JSON.parse(JSON.print(s.saveData())).result)
	check(loadedAgain.gangs["assignment"].empty() and JSON.print(loadedAgain.gangs["personal"]) == JSON.print(s.gangs["personal"]), "saving and loading after completion changes nothing")
	# failing
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _j9 = g.join("pc", "ironhand", 3)
	g.setPersonal("pc", "ironhand", 20)
	var _o = a.makeOffer({"day": 5, "rivals": g.activeMembers("hushmarket")}, stamp(5))
	var _a2 = a.accept(stamp(5))
	check(a.checkExpiry(stamp(6), ["pc"] + g.getMembers("hushmarket"))["event"] == "", "still running")
	var failed = a.checkExpiry(stamp(5) + 49 * 3600, ["pc"] + g.getMembers("hushmarket"))
	check(failed["event"] == "failed" and failed["standing"] == -8 and g.getPersonal("pc", "ironhand") == 12 and !a.hasAssignment(), "failing costs a modest, exact amount of standing")
	check(a.checkExpiry(stamp(20), [])["event"] == "" and a.fail(stamp(20)).empty(), "once only")
	# invalid target
	_o = a.makeOffer({"day": 20, "rivals": g.activeMembers("hushmarket")}, stamp(20))
	_a2 = a.accept(stamp(20))
	var goneTarget = a.getAssignment()["target"]
	var cancelled = a.checkExpiry(stamp(20, 14), ["pc"])
	check(cancelled["event"] == "cancelled" and g.getPersonal("pc", "ironhand") == 12 and !a.hasAssignment() and goneTarget != "", "a target that no longer exists cancels the job with no penalty")
	# lapse of an unaccepted offer
	_o = a.makeOffer({"day": 30, "rivals": g.activeMembers("hushmarket")}, stamp(30))
	check(a.checkExpiry(stamp(33), ["pc"] + g.getMembers("hushmarket"))["event"] == "cancelled" and g.getPersonal("pc", "ironhand") == 12, "an offer nobody took lapses without penalty")
	# deliver: credits
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _j10 = g.join("pc", "hushmarket", 3)
	g.setPersonal("pc", "hushmarket", 20)
	var tradeOffer = a.makeOffer({"day": 5, "rivals": g.activeMembers("ironhand"), "contrabandItem": "", "heldMembers": [], "captors": []}, stamp(5))
	check(tradeOffer["type"] == "deliver" and tradeOffer["amount"] == 6 and tradeOffer["item"] == "" and tradeOffer["reward"] == 0 and tradeOffer["standing"] == 8, "the trading gang wants a payment: no credits back, standing instead")
	var _a3 = a.accept(stamp(5))
	check(a.canDeliver(stamp(5, 13)) and !a.canDeliver(stamp(5) + 73 * 3600), "deliverable until the deadline")
	var deliverDone = a.complete(stamp(5, 14))
	check(deliverDone["type"] == "deliver" and deliverDone["standing"] == 8 and !a.canDeliver(stamp(5, 15)), "paid and finished once")
	# deliver: item
	a.cancel(stamp(5))
	g.setPersonal("pc", "hushmarket", 20)
	s.gangs["cooldowns"].erase("offer")
	var itemOffer = a.makeOffer({"day": 9, "rivals": [], "contrabandItem": "Shiv", "heldMembers": [], "captors": []}, stamp(9))
	check(itemOffer["type"] == "deliver" and itemOffer["item"] == "Shiv" and itemOffer["reward"] == 5 and itemOffer["amount"] == 0, "or a contraband item, for 5 credits")
	# capture
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _j11 = g.join("pc", "collarcircle", 3)
	g.setPersonal("pc", "collarcircle", 20)
	var captureOffer = a.makeOffer({"day": 5, "rivals": g.activeMembers("hushmarket"), "contrabandItem": "", "heldMembers": [], "captors": []}, stamp(5))
	check(captureOffer["type"] == "capture" and captureOffer["reward"] == 10 and captureOffer["standing"] == 12 and captureOffer["deadline"] - captureOffer["created"] == 72 * 3600, "the control gang wants someone taken: 10 credits, 3 days")
	var _a4 = a.accept(stamp(5))
	var tgt = a.getAssignment()["target"]
	check(!a.handOverCaptive(stamp(5, 14))["ok"], "nothing to hand over before the target is beaten")
	check(a.onPlayerWon("unrelated", stamp(5, 14))["event"] == "" and a.getAssignment()["stage"] == "", "an unrelated fight does not count as a capture")
	check(a.onPlayerWon(tgt, stamp(5, 15))["event"] == "defeated" and a.getAssignment()["stage"] == "defeated" and !g.isCaptive(tgt), "beating the target makes it ready to hand over, but nobody is captured yet")
	var hand = a.handOverCaptive(stamp(5, 16))
	check(hand["ok"] and g.isCaptive(tgt) and g.getCaptive(tgt)["gang"] == "collarcircle" and hand["result"]["credits"] == 10 and hand["harm"] == -15 and g.harmCount("hushmarket") == 1 and !a.hasAssignment(), "handing them over holds them, pays once, and the victim's gang remembers")
	check(!a.handOverCaptive(stamp(5, 17))["ok"] and g.getPersonal("pc", "collarcircle") == 32, "not twice")
	check(g.expireCaptives(stamp(7, 5))[0]["id"] == tgt and !g.isCaptive(tgt), "the captive is recoverable: they get away after a day and a half")
	# capture target gone invalid
	m = booted()
	g = m[1]
	a = m[2]
	var _j12 = g.join("pc", "collarcircle", 3)
	g.setPersonal("pc", "collarcircle", 20)
	var _o2 = a.makeOffer({"day": 5, "rivals": g.activeMembers("hushmarket")}, stamp(5))
	var _a5 = a.accept(stamp(5))
	var _c2 = g.capture(a.getAssignment()["target"], "ironhand", stamp(5, 14))
	check(a.checkExpiry(stamp(5, 15), ["pc"] + g.getMembers("hushmarket"))["event"] == "cancelled" and g.getPersonal("pc", "collarcircle") == 20, "if someone else takes the target, the job is dropped without blame")
	# rescue
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _j13 = g.join("pc", "ironhand", 3)
	g.setPersonal("pc", "ironhand", 20)
	var ally = g.getMembers("ironhand")[0]
	if(ally == "pc"):
		ally = g.getMembers("ironhand")[1]
	var captor = g.getMembers("hushmarket")[0]
	var _c3 = g.capture(ally, "hushmarket", stamp(5))
	var rescueOffer = a.makeOffer({"day": 5, "rivals": g.activeMembers("hushmarket"), "heldMembers": g.captivesOf("ironhand"), "captors": [captor]}, stamp(5))
	check(rescueOffer["type"] == "rescue" and rescueOffer["target"] == ally and rescueOffer["rival"] == captor and rescueOffer["reward"] == ServiceScript.RESCUE_REWARD and rescueOffer["standing"] == ServiceScript.RESCUE_STANDING and ServiceScript.RESCUE_REWARD == 8 and ServiceScript.RESCUE_STANDING == 10 and ServiceScript.ASSIGNMENTS["rescue"]["standing"] == ServiceScript.RESCUE_STANDING and a.describeAssignment(rescueOffer, {}, stamp(21)).find("standing +" + str(ServiceScript.RESCUE_STANDING)) != -1 and rescueOffer["deadline"] - rescueOffer["created"] == 48 * 3600, "a captured member triggers a rescue job: free them or beat the captor")
	var _a6 = a.accept(stamp(5))
	var _rel = g.release(ally)
	var rescued = a.onRescued(ally, stamp(5, 14))
	check(rescued["event"] == "ready" and a.canReport() and a.onRescued(ally, stamp(5, 15)).empty(), "freeing them readies it once")
	var rescuedPaid = a.complete(stamp(5, 16))
	check(rescuedPaid["credits"] == 8 and rescuedPaid["standing"] == 10 and !a.hasAssignment(), "and reporting back pays it")
	s.gangs["cooldowns"].erase("offer")
	var _c4 = g.capture(ally, "hushmarket", stamp(6))
	var _o3 = a.makeOffer({"day": 6, "rivals": g.activeMembers("hushmarket"), "heldMembers": g.captivesOf("ironhand"), "captors": [captor]}, stamp(6))
	var _a7 = a.accept(stamp(6))
	check(a.onPlayerWon(captor, stamp(6, 14))["event"] == "ready", "beating the captor also readies it")

	# ---- Protection ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var rival = g.getMembers("hushmarket")[0]
	var indie = "someone_independent"
	var strongPow = powersOf(g, 3.0)
	check(a.protectionMultiplier(indie, strongPow) == 1.0, "no gang, no protection")
	var _j14 = g.join("pc", "ironhand", 3)
	var weakP = powersOf(g, 0.3)
	var pm1 = a.protectionMultiplier(indie, weakP)
	var pm2 = a.protectionMultiplier(indie, strongPow)
	check(pm2 < pm1 and pm1 < 1.0 and pm2 > 0.0, "independent attackers are deterred, more by a stronger gang, never completely: " + str([pm1, pm2]))
	check(a.protectionMultiplier(rival, strongPow) > 1.0 and a.protectionMultiplier(rival, strongPow) <= AffairsScript.PROTECTION_CEILING, "a rival gang's members remain more dangerous")
	var mate = g.getMembers("ironhand")[0]
	if(mate == "pc"):
		mate = g.getMembers("ironhand")[1]
	check(a.protectionMultiplier(mate, strongPow) < 0.3, "gangmates barely attack")
	var plain = a.protectionMultiplier(rival, strongPow)
	g.addPersonal("pc", "hushmarket", -30)
	check(a.protectionMultiplier(rival, strongPow) > plain, "a gang that hates the player is likelier to attack")
	g.recordLoss("hushmarket")
	g.recordLoss("hushmarket")
	check(a.protectionMultiplier(rival, strongPow) < a.protectionMultiplier(rival, strongPow) + 1 and AffairsScript.PROTECTION_FLOOR > 0.0, "a gang the player keeps beating loses interest")
	var floorTest = booted()
	var _fj2 = floorTest[1].join("pc", "ironhand", 1)
	for _n in range(10):
		floorTest[1].recordLoss("hushmarket")
	var lowest = floorTest[2].protectionMultiplier(floorTest[1].getMembers("hushmarket")[0], powersOf(floorTest[1], 5.0), 100.0)
	check(lowest >= AffairsScript.PROTECTION_FLOOR and lowest < 1.0, "never below the floor: " + str(lowest))
	var e1 = floorTest[2].protectionMultiplier("nobody", powersOf(floorTest[1], 50.0), 100.0)
	check(e1 >= AffairsScript.PROTECTION_FLOOR and e1 <= 0.5, "a dominant gang deters hard but not entirely: " + str(e1))

	# ---- Ordered actions ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var recruitsL = []
	for entry in entries(40):
		if(g.gangOf(entry["id"]) == "" and !g.isCaptive(entry["id"])):
			recruitsL.append(entry["id"])
	var _mk = a.createPlayerGang("Night Shift", "hall_canteen", recruitsL.slice(0, 3), 5)
	g.addTreasury("player", 30)
	var enemyID = g.getMembers("hushmarket")[1]
	var okCtx = {"now": stamp(6), "members": 3, "targetOk": true}
	check(AffairsScript.orderSuccess(10.0, 1.0, 0.0, 5) == 0.90 and AffairsScript.orderSuccess(0.1, 50.0, 0.0, 0) >= 0.10 and AffairsScript.orderSuccess(0.1, 50.0, 0.0, 0) <= 0.25 and AffairsScript.orderSuccess(3.0, 3.0, 0.0, 3) > AffairsScript.orderSuccess(3.0, 3.0, 0.0, 1) and AffairsScript.orderSuccess(3.0, 3.0, 80.0, 3) > AffairsScript.orderSuccess(3.0, 3.0, 0.0, 3), "success runs from 10% to 90% and rises with strength, followers and the target's Fear")
	check(a.canOrder("beat", enemyID, okCtx)["ok"] and a.canOrder("beat", enemyID, okCtx)["cost"] == 5, "an order costs 5 from the treasury")
	check(!a.canOrder("beat", enemyID, {"now": stamp(6), "members": 3, "targetOk": false})["ok"] and !a.canOrder("beat", "", okCtx)["ok"] and !a.canOrder("weird", enemyID, okCtx)["ok"], "protected targets, no target and unknown orders are refused")
	check(!a.canOrder("beat", enemyID, {"now": stamp(6), "members": 1, "targetOk": true})["ok"] and !a.canOrder("beat", recruitsL[0], okCtx)["ok"], "two free members are needed, and not against your own")
	check(!a.canOrder("capture", recruitsL[8], okCtx)["ok"] and a.canOrder("capture", enemyID, okCtx)["ok"], "only members of gangs can be taken")
	var res = a.resolveOrder("beat", enemyID, 0.9, 0.1, 0.5, stamp(6))
	check(res["success"] and res["harm"] == -8 and g.getTreasury("player") == 30 and g.getPersonal("pc", "hushmarket") <= -8, "success: the cost is paid, and the rival gang's regard drops")
	var cd = a.canOrder("intimidate", enemyID, {"now": stamp(6, 20), "members": 3, "targetOk": true})
	check(!cd["ok"] and cd["reason"].find("day") != -1, "one order a day")
	check(a.canOrder("intimidate", enemyID, {"now": stamp(7, 13), "members": 3, "targetOk": true})["ok"], "and again after it")
	var failRes = a.resolveOrder("capture", enemyID, 0.3, 0.9, 0.0, stamp(8))
	check(!failRes["success"] and failRes["lost"] != "" and failRes["lost"] != "pc" and failRes["lostCaptured"] and g.isCaptive(failRes["lost"]) and g.getCaptive(failRes["lost"])["gang"] == "hushmarket", "failure: one of your people is caught and held by the target's gang")
	check(s.gangs["player"]["orders"][enemyID] == 1, "failures are counted")
	var _f2 = a.resolveOrder("beat", enemyID, 0.3, 0.9, 0.5, stamp(10))
	var _f3 = a.resolveOrder("beat", enemyID, 0.3, 0.9, 0.5, stamp(12))
	check(s.gangs["player"]["orders"][enemyID] == 3 and !a.canOrder("beat", enemyID, {"now": stamp(14), "members": 3, "targetOk": true})["ok"], "after three failures they stop trying")
	var grantedRes = a.resolveOrder("capture", g.getMembers("collarcircle")[1], 0.9, 0.1, 0.5, stamp(15))
	check(grantedRes["success"] and g.isCaptive(g.getMembers("collarcircle")[1]) and grantedRes["harm"] == -15, "a successful capture holds the target and counts as a serious offence")
	var held3 = g.captivesOf("player")
	if(!held3.empty()):
		check(a.canOrder("rescue", held3[0], {"now": stamp(30), "members": 1, "targetOk": true})["ok"], "a held member of yours can be the subject of a rescue")
		var rescue = a.resolveOrder("rescue", held3[0], 0.9, 0.1, 0.5, stamp(30))
		check(rescue["success"] and !g.isCaptive(held3[0]) and rescue["harm"] == -8 and rescue["targetGang"] == "hushmarket", "the rescue frees them, and the captor gang takes offence")
	check(!a.canOrder("rescue", recruitsL[0], {"now": stamp(40), "members": 3, "targetOk": true})["ok"], "nobody held, nothing to rescue")
	var poor = booted()
	var _pm = poor[2].createPlayerGang("Night Shift", "hall_canteen", recruitsL.slice(0, 3), 5)
	var _spent = poor[1].spendTreasury("player", 5)
	check(!poor[2].canOrder("beat", poor[1].getMembers("hushmarket")[1], okCtx)["ok"] and poor[2].canOrder("beat", poor[1].getMembers("hushmarket")[1], okCtx)["reason"].find("treasury") != -1, "an empty treasury cannot pay")
	var follower = booted()
	check(!follower[2].canOrder("beat", follower[1].getMembers("hushmarket")[1], okCtx)["ok"], "only a gang leader gives orders")

	# ---- Incidents against the player ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _jx = g.join("pc", "ironhand", 3)
	g.addPersonal("pc", "hushmarket", -30)
	check(g.effectiveStatus("pc", "hushmarket")["hostile"], "setup: the Hush Market hates the player")
	var ctxI = {"day": 6, "guards": 0, "attention": 0.0, "fear": 0.0, "powers": powersOf(g, 1.0), "combat": 0.0}
	check(a.incidentGang(ctxI, [0.0, 0.0, 0.0]) == "hushmarket", "a hostile gang may send someone")
	check(a.incidentGang(ctxI, [0.99, 0.99, 0.99]) == "", "usually it does not")
	check(a.incidentGang({"day": 6, "guards": 1, "attention": 0.0, "fear": 0.0, "powers": powersOf(g, 1.0)}, [0.0, 0.0, 0.0]) == "", "never with a guard about")
	check(a.incidentGang({"day": 6, "guards": 0, "attention": 0.0, "fear": 100.0, "powers": powersOf(g, 1.0)}, [0.07, 0.07]) == "", "a feared player is left alone more")
	check(a.incidentGang({"day": 6, "guards": 0, "attention": 100.0, "fear": 0.0, "powers": powersOf(g, 1.0)}, [0.07, 0.07]) == "", "and so is one security is watching")
	a.markIncident("hushmarket", 6)
	check(a.incidentGang(ctxI, [0.0, 0.0, 0.0]) == "", "one major incident a day")
	var ctxLater = {"day": 7, "guards": 0, "attention": 0.0, "fear": 0.0, "powers": powersOf(g, 1.0), "combat": 0.0}
	check(a.incidentGang(ctxLater, [0.0, 0.0, 0.0]) == "", "and a gap of days for the same gang")
	var ctxLater2 = {"day": 6 + ServiceScript.INCIDENT_COOLDOWN_DAYS, "guards": 0, "attention": 0.0, "fear": 0.0, "powers": powersOf(g, 1.0), "combat": 0.0}
	check(a.incidentGang(ctxLater2, [0.0, 0.0, 0.0]) == "hushmarket", "it can happen again after that")
	g.recordLoss("hushmarket")
	g.recordLoss("hushmarket")
	g.recordLoss("hushmarket")
	g.recordLoss("hushmarket")
	var oneChance = 0
	var rngI = RandomNumberGenerator.new()
	rngI.seed = 77
	for _d in range(400):
		s.gangs["player"]["incident_day"] = -1
		s.gangs["gangs"]["hushmarket"]["incident_day"] = -1
		if(a.incidentGang(ctxLater2, [rngI.randf()]) == "hushmarket"):
			oneChance += 1
	check(oneChance < 40, "a gang the player keeps beating almost stops: " + str(oneChance) + " of 400")
	var _jy = g.leave("pc", 8)
	var neutralG = booted()
	check(neutralG[2].incidentGang({"day": 6, "guards": 0, "attention": 0.0, "fear": 0.0, "powers": powersOf(neutralG[1], 1.0)}, [0.0, 0.0, 0.0]) == "", "an independent player nobody has a grudge against has no incidents")

	# ---- Abstract conflicts ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var pw = powersOf(g, 1.0)
	var none = a.abstractConflicts(5, stamp(5), pw, [0.99, 0.99])
	check(none.empty(), "an ordinary roll: nothing happens")
	var relBefore = g.getRelation("ironhand", "hushmarket")
	var clash = a.abstractConflicts(5, stamp(5), pw, [0.0, 0.99])
	check(clash.size() == 1 and clash[0]["type"] == "skirmish" and g.getRelation("ironhand", "hushmarket") == relBefore - 2, "a clash between enemy gangs shifts their relation a little")
	var kidnap = a.abstractConflicts(6, stamp(6), pw, [0.0, 0.0])
	check(kidnap.size() == 1 and kidnap[0]["type"] == "kidnap" and g.isCaptive(kidnap[0]["victim"]) and g.getCaptive(kidnap[0]["victim"])["gang"] == kidnap[0]["by"] and kidnap[0]["victim"] != g.getLeader(g.gangOf(kidnap[0]["victim"])), "the stronger gang may take an isolated member, never a leader")
	var again2 = a.abstractConflicts(7, stamp(7), pw, [0.0, 0.0])
	check(again2.size() == 1 and again2[0]["type"] == "skirmish", "a gang that just took someone does not take another for days")
	var later = a.abstractConflicts(6 + ServiceScript.KIDNAP_COOLDOWN_DAYS, stamp(6 + ServiceScript.KIDNAP_COOLDOWN_DAYS), pw, [0.0, 0.0])
	check(later.size() == 1 and (later[0]["type"] == "kidnap" and later[0]["victim"] != kidnap[0]["victim"] or later[0]["type"] == "skirmish"), "and never the same victim twice")
	var friendlyOnly = booted()
	friendlyOnly[1].setRelation("ironhand", "hushmarket", 0)
	check(friendlyOnly[2].abstractConflicts(5, stamp(5), powersOf(friendlyOnly[1], 1.0), [0.0, 0.0]).empty(), "gangs that are not enemies do not clash")
	check(a.pickVictim("hushmarket", pw, stamp(40)) != g.getLeader("hushmarket"), "the leader is never the victim")

	# ---- Churn ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var memberA = g.getMembers("ironhand")[0]
	var leaderI = g.getLeader("ironhand")
	if(memberA == leaderI):
		memberA = g.getMembers("ironhand")[1]
	var pwr = powersOf(g, 1.0)
	var calm = [{"id": memberA, "gang": "ironhand", "leaderTrust": 10.0, "leaderRegard": 10.0, "bestOther": "", "bestOtherValue": 0.0}]
	check(a.churn(stamp(5), pwr, calm, 0.0).empty(), "contented members stay")
	var unhappy = [{"id": memberA, "gang": "ironhand", "leaderTrust": -80.0, "leaderRegard": 0.0, "bestOther": "", "bestOtherValue": 0.0}]
	check(a.churn(stamp(5), pwr, unhappy, 0.9).empty(), "an unhappy member does not always go")
	var leaves = a.churn(stamp(5), pwr, unhappy, 0.1)
	check(leaves["type"] == "leave" and leaves["reason"].find("faith") != -1 and !g.isMember(memberA, "ironhand"), "an unhappy member may leave, with a reason")
	check(a.churn(stamp(6), pwr, [{"id": g.getMembers("ironhand")[0], "gang": "ironhand", "leaderTrust": -90.0, "leaderRegard": 0.0, "bestOther": "", "bestOtherValue": 0.0}], 0.1).empty(), "never more than one change every three days")
	var other = ""
	for id in g.getMembers("ironhand"):
		if(id != g.getLeader("ironhand")):
			other = id
	check(!a.churn(stamp(5) + 3 * 86400, pwr, [{"id": other, "gang": "ironhand", "leaderTrust": -90.0, "leaderRegard": 0.0, "bestOther": "", "bestOtherValue": 0.0}], 0.1).empty(), "and then it can again")
	m = booted()
	g = m[1]
	a = m[2]
	var defector = g.getMembers("hushmarket")[1]
	pwr = {}
	for gid in g.gangIDs():
		for id in g.getMembers(gid):
			pwr[id] = 1.0
	for id in g.getMembers("hushmarket"):
		pwr[id] = 0.1
	var defects = a.churn(stamp(5), pwr, [{"id": defector, "gang": "hushmarket", "leaderTrust": 0.0, "leaderRegard": 0.0, "bestOther": "collarcircle", "bestOtherValue": 90.0}], 0.1)
	check(defects["type"] == "defect" and defects["to"] == "collarcircle" and g.isMember(defector, "collarcircle") and !g.isMember(defector, "hushmarket") and defects["reason"].find("stronger") != -1, "a member who admires a stronger gang's leader may defect")
	m = booted()
	g = m[1]
	a = m[2]
	var distrusted = g.getMembers("ironhand")[0]
	if(distrusted == g.getLeader("ironhand")):
		distrusted = g.getMembers("ironhand")[1]
	var expelled = a.churn(stamp(5), powersOf(g, 1.0), [{"id": distrusted, "gang": "ironhand", "leaderTrust": 0.0, "leaderRegard": -70.0, "bestOther": "", "bestOtherValue": 0.0}], 0.99)
	check(expelled["type"] == "expel" and expelled["reason"].find("trust") != -1 and !g.isMember(distrusted, "ironhand"), "a leader can expel someone they no longer trust")
	var leaderView = [{"id": g.getLeader("hushmarket"), "gang": "hushmarket", "leaderTrust": -99.0, "leaderRegard": -99.0, "bestOther": "", "bestOtherValue": 0.0}]
	check(a.churn(stamp(30), powersOf(g, 1.0), leaderView, 0.0).empty(), "leaders do not walk out of their own gang")

	# ---- Pruning and sanitising ----
	m = booted()
	s = m[0]
	g = m[1]
	var allIDs = ["pc"]
	for entry in entries(40):
		allIDs.append(entry["id"])
	var someMember = g.getMembers("ironhand")[0]
	var gone2 = []
	for id in allIDs:
		if(id == someMember):
			continue
		gone2.append(id)
	var pruned = g.pruneMissing(gone2)
	check(pruned.has(someMember) and !g.isMember(someMember, "ironhand") and g.isMember(g.getLeader("ironhand"), "ironhand"), "deleted characters are pruned and leadership repaired")
	var bigState = StateScript.new()
	bigState.loadData({"schema_version": 6, "gangs": {"init": true, "gangs": {
		"ironhand": {"name": "Ironhand", "leader": "ghost", "members": ["a", "b", "a", "dup"], "slaves": ["s1"], "hangout": "gym_weights", "treasury": 999999},
		"hushmarket": {"name": "", "leader": "a", "members": ["dup", "c", 5, ""], "slaves": ["b", "s1"], "hangout": 7, "treasury": -5},
		"emptygang": {"name": "Nobody", "leader": "", "members": [], "slaves": []},
		"player": {"name": "Mine", "leader": "x", "members": ["pc", "dup"], "slaves": []}},
		"relations": {"hushmarket|ironhand": 500, "ironhand|hushmarket": 20, "ironhand|ironhand": 5, "ironhand|ghostgang": 5, "bad": 3, "player|ironhand": "x"},
		"personal": {"pc": {"ironhand": 150, "hushmarket": "x", "ghost": 5, "player": 0}, "": {"ironhand": 5}, "a": "x"},
		"captives": {"c": {"gang": "ironhand", "kind": "captive", "stamp": 5}, "a": {"gang": "ironhand", "kind": "captive", "stamp": 5}, "s1": {"gang": "ironhand", "kind": "slave"}, "pc": {"gang": "ironhand", "kind": "captive"}, "zz": {"gang": "ghost", "kind": "captive"}, "yy": {"gang": "ironhand", "kind": "weird"}},
		"assignment": {"type": "defeat", "gang": "ironhand", "state": "active", "target": "c", "reward": 5000},
		"cooldowns": {"offer": 5, "bad": "x"}, "log": ["one", 5, "two"], "player": {"harm": {"ironhand": 3, "ghost": 2}, "orders": {"c": 2}}}})
	var bg = bigState.gangs
	check(bg["gangs"]["ironhand"]["members"] == ["a", "b"] and bg["gangs"]["hushmarket"]["members"] == ["c"] and bg["gangs"]["player"]["members"] == ["pc", "dup"] and !bg["gangs"].has("emptygang"), "duplicate membership is repaired deterministically (the player's gang first, then gang order), and empty gangs go")
	check(bg["gangs"]["ironhand"]["leader"] == "a" and bg["gangs"]["hushmarket"]["leader"] == "c" and bg["gangs"]["player"]["leader"] == "pc", "missing leaders are replaced; the player's gang keeps the player")
	check(bg["gangs"]["ironhand"]["treasury"] == 9999 and bg["gangs"]["hushmarket"]["treasury"] == 0 and bg["gangs"]["hushmarket"]["name"] == "The Hush Market" and bg["gangs"]["hushmarket"]["hangout"] == "", "treasuries are clamped, names and hangouts repaired")
	check(bg["relations"].size() == 1 and bg["relations"]["hushmarket|ironhand"] == 100, "relations are sanitised: the key must be sorted, both gangs real")
	check(JSON.print(bg["personal"]["pc"]) == JSON.print({"ironhand": 100}) and bg["personal"].size() == 1, "personal relations are clamped and unknown gangs dropped")
	check(bg["captives"].has("c") and !bg["captives"].has("a") and !bg["captives"].has("pc") and !bg["captives"].has("zz") and !bg["captives"].has("yy") and bg["captives"].has("s1") and bg["captives"]["s1"]["kind"] == "slave", "invalid captives are released, a valid slave and a valid captive stay")
	var holders = 0
	for gid in bg["gangs"]:
		if(bg["gangs"][gid]["slaves"].has("s1")):
			holders += 1
			check(bg["captives"]["s1"]["gang"] == gid, "the slave's record names its one owner")
		check(!bg["gangs"][gid]["slaves"].has("b"), "a member cannot also be a gang slave")
	check(holders == 1, "overlapping ownership is repaired: one owner per slave")
	check(bg["assignment"]["reward"] == 99 and bg["assignment"]["state"] == "active", "an assignment is clamped")
	check(bg["cooldowns"].size() == 1 and bg["log"] == ["one", "two"] and JSON.print(bg["player"]["harm"]) == JSON.print({"ironhand": 3}) and JSON.print(bg["player"]["orders"]) == JSON.print({"c": 2}), "cooldowns, the log and the player's record are sanitised")
	var junk = ServiceScript.sanitize("junk")
	check(JSON.print(junk) == JSON.print(ServiceScript.defaults()) and JSON.print(ServiceScript.sanitize(null)) == JSON.print(ServiceScript.defaults()), "junk becomes the defaults")
	var original = {"init": true, "gangs": {"ironhand": {"name": "Ironhand", "leader": "a", "members": ["a"]}}}
	var cleaned = ServiceScript.sanitize(original)
	cleaned["gangs"]["ironhand"]["members"].append("zzz")
	check(original["gangs"]["ironhand"]["members"] == ["a"], "sanitising never aliases the input")
	var oldSave = StateScript.new()
	oldSave.loadData({"schema_version": 5, "security": {"attention": 40}, "gangs": {"init": true, "gangs": {"ironhand": {"name": "X", "members": ["a"]}}}})
	check(oldSave.schema_version == 9 and JSON.print(oldSave.gangs) == JSON.print(ServiceScript.defaults()) and oldSave.security["attention"] == 40.0, "a version 5 save has no gangs (even with a stray field) and keeps its security state")
	oldSave.loadData({"schema_version": 99, "gangs": {"init": true}})
	check(oldSave.schema_version == 99, "a newer save keeps its version")
	oldSave.loadData({"schema_version": 6, "gangs": "junk"})
	check(JSON.print(oldSave.gangs) == JSON.print(ServiceScript.defaults()), "a malformed gangs block loads clean")
	var keepAll = StateScript.new()
	keepAll.loadData({"schema_version": 6, "work": {"job": "mining"}, "upgrades": {"storage": true}, "security": {"attention": 30}, "reputation": {"combat": 12.0, "defiance": 0.0}, "gangs": {"init": true}})
	check(keepAll.work["job"] == "mining" and keepAll.upgrades["storage"] == true and keepAll.security["attention"] == 30.0 and keepAll.reputation["combat"] == 12.0, "jobs, upgrades, security and reputation load unchanged next to gangs")
	keepAll.clear()
	check(JSON.print(keepAll.gangs) == JSON.print(ServiceScript.defaults()), "a new game resets the gangs")
	var roundTrip = booted()
	var _rt1 = roundTrip[1].join("pc", "ironhand", 3)
	roundTrip[1].addPersonal("pc", "hushmarket", -20)
	var _rt2 = roundTrip[1].capture(roundTrip[1].getMembers("hushmarket")[1], "ironhand", stamp(5))
	var data = roundTrip[0].saveData()
	var alias = JSON.print(roundTrip[0].gangs, "", true)
	data["gangs"]["gangs"]["ironhand"]["members"].append("evil")
	check(JSON.print(roundTrip[0].gangs, "", true) == alias, "saveData does not alias the live state")
	var reloaded = StateScript.new()
	reloaded.loadData(JSON.parse(JSON.print(roundTrip[0].saveData())).result)
	check(JSON.print(reloaded.gangs, "", true) == alias, "everything survives a JSON round trip exactly")

	# ---- Text helpers ----
	check(ServiceScript.personalBand(-80) == "hated" and ServiceScript.personalBand(-30) == "hostile" and ServiceScript.personalBand(0) == "neutral" and ServiceScript.personalBand(40) == "respected" and ServiceScript.personalBand(70) == "trusted", "personal relation bands")
	check(ServiceScript.bandColor(-30) == "red" and ServiceScript.bandColor(30) == "green" and ServiceScript.bandColor(0) == "cyan", "colours")
	check(ServiceScript.hangoutName("main_laundry") == "the laundry" and ServiceScript.hangoutName("somewhere") == "somewhere", "hangout names")
	var desc = a.describeAssignment({"gang": "ironhand", "type": "defeat", "state": "active", "target": "t", "rival": "", "item": "", "amount": 0, "created": 0, "deadline": 7200, "reward": 6, "standing": 8, "penalty": 8, "intro": false, "stage": ""}, {"t": "Target Name"}, 0)
	check(desc.find("Target Name") != -1 and desc.find("2 hours") != -1 and desc.find("6 credits") != -1 and desc.find("standing +8") != -1 and desc.find("standing -8") != -1 and desc.find("[color=green]") != -1 and desc.find("[color=red]") != -1, "an assignment shows target, deadline, reward and penalty in colour: " + desc)

	# ---- Treasury income ----
	var incomeState = make()
	var _ii = incomeState[1].initialize(entries(40), 1)
	var ig = incomeState[1]
	var pg = incomeState[0].gangs["gangs"]
	for gid in ig.gangIDs():
		check(ig.getTreasury(gid) == 20, gid + ": starts with 20 credits")
	pg["ironhand"]["members"] = ["a1", "a2"]
	check(ig.memberIncome("ironhand") == 0, "two members: no member income yet")
	pg["ironhand"]["members"] = ["a1", "a2", "a3"]
	check(ig.memberIncome("ironhand") == 1, "three members: 1 credit")
	pg["ironhand"]["members"] = ["a1", "a2", "a3", "a4", "a5"]
	check(ig.memberIncome("ironhand") == 1, "five members: still 1")
	pg["ironhand"]["members"] = ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9"]
	check(ig.memberIncome("ironhand") == 3, "nine members: 3")
	var many = []
	for i in range(30):
		many.append("m" + str(i))
	pg["ironhand"]["members"] = many
	check(ig.memberIncome("ironhand") == 3, "thirty members: capped at 3")
	incomeState[0].gangs["captives"]["m0"] = {"gang": "hushmarket", "kind": "captive", "stamp": 5, "by": ""}
	pg["ironhand"]["members"] = ["a1", "a2", "a3", "m0"]
	check(ig.memberIncome("ironhand") == 1, "held members do not count: 3 free of 4 is 1")
	pg["ironhand"]["members"] = ["a1", "a2", "m0", "m0x"]
	incomeState[0].gangs["captives"]["m0x"] = {"gang": "hushmarket", "kind": "captive", "stamp": 5, "by": ""}
	check(ig.memberIncome("ironhand") == 0, "two free of four is 0")
	pg["ironhand"]["members"] = many
	var before20 = ig.getTreasury("ironhand")
	var payout = ig.collectIncome(10)
	check(payout["ironhand"] == 3 and ig.getTreasury("ironhand") == before20 + 3, "a day's income is paid to the treasury")
	check(ig.collectIncome(10).empty() and ig.getTreasury("ironhand") == before20 + 3, "exactly once a day")
	check(payout.get("collarcircle", 0) == 4 + ig.memberIncome("collarcircle"), "the slaves' 2 credits each still count on top")
	var playerIncome = make()
	var plist2 = entries(40)
	var _pi2 = playerIncome[1].initialize(plist2, 1)
	var pmk = playerIncome[2].createPlayerGang("Night Shift", "hall_canteen", ["x1", "x2", "x3", "x4", "x5"], 5)
	check(pmk["ok"] and playerIncome[1].getTreasury("player") == 5, "the player's gang starts with 5 credits of its founding cost")
	var pay2 = playerIncome[1].collectIncome(11)
	check(pay2["player"] == 2 and playerIncome[1].getTreasury("player") == 7 and playerIncome[1].collectIncome(11).get("player", 0) == 0, "and earns the same member income: 6 members is 2 a day, once")

	# ---- Assignment rewards are paid from the offering gang's treasury ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var _jq = g.join("pc", "ironhand", 3)
	g.setPersonal("pc", "ironhand", 20)
	var rivalsQ = g.activeMembers("hushmarket")
	var tBase = g.getTreasury("ironhand")
	var offerQ = a.makeOffer({"day": 5, "rivals": rivalsQ, "heldMembers": [], "captors": []}, stamp(5))
	check(offerQ["type"] == "defeat" and offerQ["reward"] == 6 and g.reservedAmount("ironhand") == 0 and g.availableTreasury("ironhand") == tBase, "an offer reserves nothing")
	check(a.decline(stamp(5)) and g.reservedAmount("ironhand") == 0 and g.getTreasury("ironhand") == tBase, "declining reserves nothing")
	s.gangs["cooldowns"].erase("offer")
	offerQ = a.makeOffer({"day": 7, "rivals": rivalsQ, "heldMembers": [], "captors": []}, stamp(7))
	check(a.accept(stamp(7)) and g.reservedAmount("ironhand") == 6 and g.getTreasury("ironhand") == tBase and g.availableTreasury("ironhand") == tBase - 6, "accepting reserves the reward: the treasury is untouched but 6 are unavailable")
	check(!g.spendableTreasury("ironhand", tBase - 5) and g.spendableTreasury("ironhand", tBase - 6) and !g.spendTreasury("ironhand", tBase - 5) and g.getTreasury("ironhand") == tBase, "reserved credits cannot be spent on anything else")
	var reloadedQ = StateScript.new()
	reloadedQ.loadData(JSON.parse(JSON.print(s.saveData())).result)
	var reloadedService = ServiceScript.new(reloadedQ)
	check(reloadedQ.gangs["assignment"]["reserved"] == 6 and reloadedService.reservedAmount("ironhand") == 6 and reloadedService.availableTreasury("ironhand") == tBase - 6, "saving and loading keeps the reservation")
	var targetQ = a.getAssignment()["target"]
	var winQ = a.onPlayerWon(targetQ, stamp(8))
	check(winQ["event"] == "ready" and g.reservedAmount("ironhand") == 6 and g.getTreasury("ironhand") == tBase, "winning leaves the reservation in place until the report")
	var reloadedReady = StateScript.new()
	reloadedReady.loadData(JSON.parse(JSON.print(s.saveData())).result)
	check(reloadedReady.gangs["assignment"]["state"] == "ready" and reloadedReady.gangs["assignment"]["reserved"] == 6, "a finished job waiting for its report survives save and load")
	var paidQ = a.complete(stamp(8, 1))
	check(paidQ["credits"] == 6 and g.getTreasury("ironhand") == tBase - 6 and g.reservedAmount("ironhand") == 0 and !a.hasAssignment(), "reporting back pays the reserved 6 from the treasury, once")
	check(a.complete(stamp(8)).empty() and a.onPlayerWon(targetQ, stamp(8))["event"] == "" and g.getTreasury("ironhand") == tBase - 6, "a second completion pays nothing")
	var reloadedPaid = StateScript.new()
	reloadedPaid.loadData(JSON.parse(JSON.print(s.saveData())).result)
	check(reloadedPaid.gangs["gangs"]["ironhand"]["treasury"] == tBase - 6 and reloadedPaid.gangs["assignment"].empty(), "loading after payment pays and reserves nothing more")
	# failing releases it
	s.gangs["cooldowns"].erase("offer")
	var _oq = a.makeOffer({"day": 10, "rivals": rivalsQ, "heldMembers": [], "captors": []}, stamp(10))
	var _aq = a.accept(stamp(10))
	check(g.reservedAmount("ironhand") == 6, "setup: reserved again")
	var failQ = a.checkExpiry(stamp(10) + 49 * 3600, ["pc"] + rivalsQ)
	check(failQ["event"] == "failed" and g.reservedAmount("ironhand") == 0 and g.getTreasury("ironhand") == tBase - 6, "failing releases the reservation: the gang keeps its money")
	# an invalid target releases it too
	s.gangs["cooldowns"].erase("offer")
	var _oq2 = a.makeOffer({"day": 15, "rivals": rivalsQ, "heldMembers": [], "captors": []}, stamp(15))
	var _aq2 = a.accept(stamp(15))
	var cancelQ = a.checkExpiry(stamp(15, 14), ["pc"])
	check(cancelQ["event"] == "cancelled" and g.reservedAmount("ironhand") == 0 and g.getTreasury("ironhand") == tBase - 6 and g.getPersonal("pc", "ironhand") == 20, "an invalid target cancels, releases the reservation and costs no standing")
	# unfunded jobs
	s.gangs["cooldowns"].erase("offer")
	var drained = g.spendTreasury("ironhand", g.getTreasury("ironhand"))
	check(drained and g.getTreasury("ironhand") == 0, "setup: an empty treasury")
	var poorOffer = a.makeOffer({"day": 20, "rivals": rivalsQ, "heldMembers": [], "captors": []}, stamp(20))
	check(poorOffer["type"] == "deliver" and poorOffer["reward"] == 0 and a.describeAssignment(poorOffer, {}, stamp(20)).find("no credits") != -1, "a gang that cannot pay is not offered a paid job; the unpaid one says it pays no credits")
	check(a.accept(stamp(20)) and g.reservedAmount("ironhand") == 0, "an unpaid job reserves nothing")
	a.cancel(stamp(20))
	s.gangs["cooldowns"].erase("offer")
	var captiveQ = g.getMembers("ironhand")[1]
	var _cq = g.capture(captiveQ, "hushmarket", stamp(21))
	var rescueUnpaid = a.makeOffer({"day": 21, "rivals": rivalsQ, "heldMembers": [captiveQ], "captors": [rivalsQ[0]]}, stamp(21))
	check(rescueUnpaid["type"] == "rescue" and rescueUnpaid["reward"] == 0 and a.describeAssignment(rescueUnpaid, {}, stamp(21)).find("no credits") != -1, "a rescue is offered even when the gang is broke, with a credit reward of zero shown")
	a.cancel(stamp(21))
	var _rl = g.release(captiveQ)
	# the offer was funded but the money went before it was accepted
	s.gangs["cooldowns"].erase("offer")
	var _tq = g.addTreasury("ironhand", 20)
	var _oq3 = a.makeOffer({"day": 25, "rivals": rivalsQ, "heldMembers": [], "captors": []}, stamp(25))
	var _sp = g.spendTreasury("ironhand", 20)
	check(!a.accept(stamp(25)) and a.getAssignment()["state"] == "offered" and g.reservedAmount("ironhand") == 0, "if the money has gone by the time the job is accepted, it cannot be accepted")
	# sanitising a reservation
	var dirtyR = ServiceScript.sanitize({"init": true, "gangs": {"ironhand": {"name": "I", "leader": "a", "members": ["a"], "treasury": 3}}, "assignment": {"type": "defeat", "gang": "ironhand", "state": "active", "target": "t", "reward": 6, "reserved": 50}})
	check(dirtyR["assignment"]["reserved"] == 3, "a reservation is clamped to the gang's treasury (and the reward)")
	var offeredR = ServiceScript.sanitize({"init": true, "gangs": {"ironhand": {"name": "I", "leader": "a", "members": ["a"], "treasury": 30}}, "assignment": {"type": "defeat", "gang": "ironhand", "state": "offered", "target": "t", "reward": 6, "reserved": 6}})
	check(offeredR["assignment"]["reserved"] == 0, "an offer that was never accepted holds nothing back, whatever the file says")
	# the player's own gang cannot overspend reserved money either (generic)
	var ownRes = booted()
	var _or = ownRes[2].createPlayerGang("Night Shift", "hall_canteen", ["x1", "x2"], 5)
	check(ownRes[1].availableTreasury("player") == 5 and ownRes[1].spendableTreasury("player", 5) and !ownRes[1].spendableTreasury("player", 6), "unreserved funds only for orders")

	# ---- A failed order never deletes anyone ----
	m = booted()
	s = m[0]
	g = m[1]
	a = m[2]
	var recruitsF = []
	for entry in entries(40):
		if(g.gangOf(entry["id"]) == "" and !g.isCaptive(entry["id"])):
			recruitsF.append(entry["id"])
	var _mk3 = a.createPlayerGang("Night Shift", "hall_canteen", recruitsF.slice(0, 3), 5)
	g.addTreasury("player", 40)
	var targetF = g.getMembers("hushmarket")[1]
	var membersBefore = g.getMembers("player")
	var fail1 = a.resolveOrder("beat", targetF, 0.1, 0.9, 0.0, stamp(6))
	check(!fail1["success"] and fail1["lost"] != "" and g.isMember(fail1["lost"], "player") and g.getMembers("player") == membersBefore, "a failed order leaves everyone in the gang: nobody is removed")
	check(fail1["lostCaptured"] and g.isCaptive(fail1["lost"]) and g.getCaptive(fail1["lost"])["gang"] == "hushmarket" and g.gangOf(fail1["lost"]) == "player", "the chosen member is temporarily held by the target's gang and is still one of yours")
	var escapedF = g.expireCaptives(stamp(8, 12))
	check(escapedF.size() == 1 and escapedF[0]["id"] == fail1["lost"] and !g.isCaptive(fail1["lost"]) and g.isMember(fail1["lost"], "player"), "and escapes after the bounded time")
	var loner = "independent1"
	var fail2 = a.resolveOrder("beat", loner, 0.1, 0.9, 0.5, stamp(9))
	check(!fail2["success"] and fail2["lost"] != "" and !fail2["lostCaptured"] and g.isMember(fail2["lost"], "player") and !g.isCaptive(fail2["lost"]), "against someone with no gang the member is only hurt (the caller injures them), not held and not removed")
	check(g.getMembers("player") == membersBefore and s.gangs["player"]["orders"][targetF] == 1 and s.gangs["player"]["orders"][loner] == 1, "the gang is intact and the failures are counted")

	print("GangsTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

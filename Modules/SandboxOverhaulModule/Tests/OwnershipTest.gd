extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/OwnershipTest.gd --quit
# The ownership rules on their own (no game): the three styles, the nightly check-in, demands, compliance and escalation, protection, ways out, the player's slaves and their roles, escapes,
# the saved shape and its repair. The same rules are run again on the real game in OwnershipBootTest.

const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")
const TextScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipText.gd")
const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func makeService(styleName:String = "controlling", day:int = 10, voluntary:bool = false, axisNow:int = 8 * 3600):
	var state = StateScript.new()
	var svc = OwnershipScript.new(state)
	var _ok = svc.begin("owner1", day, voluntary, styleName, axisNow)
	return svc

func _init():
	# ---- Styles ----
	check(StyleScript.styleOf({"mean": 0.9, "subby": -0.5, "naive": 0.0, "power": 1.2}) == "harsh", "a hard, dominant, strong character is harsh")
	check(StyleScript.styleOf({"mean": -0.8, "subby": 0.5, "naive": 0.4, "power": 0.6}) == "lenient", "a kind, soft, naive character is lenient")
	check(StyleScript.styleOf({"mean": 0.0, "subby": 0.0, "naive": 0.0, "power": 0.9}) == "controlling", "everybody else is controlling")
	check(StyleScript.styleOf({"mean": 0.9, "subby": -0.5, "naive": 0.0, "power": 1.2}) == StyleScript.styleOf({"mean": 0.9, "subby": -0.5, "naive": 0.0, "power": 1.2}), "the style only depends on the personality: same values, same style")
	check(StyleScript.checkinText("lenient") == "about every third night" and StyleScript.checkinText("controlling") == "about every other night" and StyleScript.checkinText("harsh") == "every night", "check-in frequency in words")
	for styleName in StyleScript.STYLES:
		var p = StyleScript.params(styleName)
		check(int(p["demand_gap"]) >= 2 and StyleScript.describe(styleName).begins_with(StyleScript.nameOf(styleName)), styleName + ": demands never closer than two days, and the description names the style")
	check(StyleScript.params("lenient")["checkin_every"] == 3 and StyleScript.params("controlling")["checkin_every"] == 2 and StyleScript.params("harsh")["checkin_every"] == 1, "check-ins every 3 / 2 / 1 nights")
	check(StyleScript.params("lenient")["willingness"] > StyleScript.params("controlling")["willingness"] and StyleScript.params("controlling")["willingness"] > StyleScript.params("harsh")["willingness"], "lenient owners negotiate, harsh ones hardly do")
	check(StyleScript.params("lenient")["punish"] < StyleScript.params("controlling")["punish"] and StyleScript.params("controlling")["punish"] < StyleScript.params("harsh")["punish"], "punishment severity grows with the style")
	check(StyleScript.params("lenient")["protection"] < StyleScript.params("harsh")["protection"] and StyleScript.params("lenient")["escalation"] < StyleScript.params("harsh")["escalation"], "protection and escalation speed grow with the style")

	# ---- The check-in: creation, reminder, completion, lateness ----
	for styleName in ["lenient", "controlling", "harsh"]:
		var svc = makeService(styleName, 10)
		var interval = int(StyleScript.params(styleName)["checkin_every"])
		check(svc.record()["next_checkin"] == 10, styleName + ": started in the morning, tonight is the first check-in")
		check(svc.startCheckin(10, 12 * 3600) and svc.isCheckinPending(10) and !svc.startCheckin(10, 12 * 3600), styleName + ": tonight's check-in is created once")
		check(!svc.shouldRemind(10, 12 * 3600) and svc.shouldRemind(10, OwnershipScript.REMINDER_AT), styleName + ": one reminder when the window approaches")
		svc.markReminded()
		check(!svc.shouldRemind(10, OwnershipScript.REMINDER_AT + 600), styleName + ": and only one")
		var tooSoon = svc.reportIn(10, 18 * 3600, true)
		check(!tooSoon["ok"] and tooSoon["reason"] == "too_soon", styleName + ": reporting at 18:00 is too soon")
		var nowhere = svc.reportIn(10, 21 * 3600 + 600, false)
		check(!nowhere["ok"] and nowhere["reason"] == "not_there", styleName + ": it has to be done in their cell, with them there")
		var done = svc.reportIn(10, 21 * 3600 + 600, true)
		check(done["ok"] and done["timing"] == "on_time" and svc.checkin()["state"] == "done", styleName + ": on time")
		check(svc.record()["next_checkin"] == 10 + interval, styleName + ": the next check-in is " + str(interval) + " night(s) later")
		check(!svc.reportIn(10, 21 * 3600 + 900, true)["ok"] and svc.recentFulfilled(10) == 1, styleName + ": it counts once")
		check(!svc.startCheckin(10 + interval - 1, 12 * 3600) or interval == 1, styleName + ": nothing is created before the night it is due")
	var early = makeService("controlling")
	var _s1 = early.startCheckin(10, 12 * 3600)
	check(early.reportIn(10, 20 * 3600 + 35 * 60, true)["timing"] == "early", "20:35 is early")
	var late = makeService("controlling")
	var _s2 = late.startCheckin(10, 12 * 3600)
	var lateResult = late.reportIn(10, 23 * 3600 + 20 * 60, true)
	check(lateResult["ok"] and lateResult["timing"] == "late" and late.checkin()["state"] == "late", "23:20 is late but still counts")
	var closedLate = makeService("controlling")
	var _s3 = closedLate.startCheckin(10, 12 * 3600)
	check(!closedLate.reportIn(10, 25 * 3600, true)["ok"], "after 00:30 it is closed")
	check(OwnershipScript.windowState(18 * 3600) == "before" and OwnershipScript.windowState(21 * 3600 + 10) == "open" and OwnershipScript.windowState(23 * 3600 + 600) == "late" and OwnershipScript.windowState(26 * 3600) == "closed", "window states")

	# ---- Missing a check-in: missed, excused, and the escalation that follows ----
	var missed = makeService("controlling")
	var _s4 = missed.startCheckin(10, 12 * 3600)
	check(missed.closeCheckin(10, 20 * 3600, "") == "", "an open window is not closed early")
	check(missed.closeCheckin(10, 25 * 3600, "") == "missed" and missed.checkin()["state"] == "missed", "a check-in nobody came to is missed")
	check(missed.recordMiss(10, "did not come") == 1 and missed.recentMisses(10) == 1 and missed.pendingConfront()["level"] == 1, "the first miss is a verbal warning, waiting for the next meeting")
	var excused = makeService("harsh")
	var _s5 = excused.startCheckin(10, 12 * 3600)
	excused.noteBlock(10, "locked in the stocks")
	check(excused.closeCheckin(10, 25 * 3600, "") == "excused" and excused.checkin()["state"] == "excused" and excused.recentMisses(10) == 0 and excused.pendingConfront().empty(), "a sighting of a real obstacle excuses the night: no warning, no penalty")
	var excusedNow = makeService("harsh")
	var _s6 = excusedNow.startCheckin(10, 12 * 3600)
	check(excusedNow.closeCheckin(10, 25 * 3600, "unconscious") == "excused", "an excuse at closing time works too")
	var stale = makeService("controlling")
	var _s7 = stale.startCheckin(10, 12 * 3600)
	check(stale.closeCheckin(11, 8 * 3600, "") == "missed", "a check-in left over from yesterday is closed when the day changes")
	for pair in [["lenient", [1, 1, 2]], ["controlling", [1, 2, 3]], ["harsh", [2, 3, 3]]]:
		var esc = makeService(pair[0])
		var levels = []
		for n in range(3):
			levels.append(esc.recordMiss(10 + n, "did not come"))
		check(levels == pair[1], pair[0] + ": escalation " + str(levels))
	var lenientSlow = makeService("lenient")
	var _a = lenientSlow.recordMiss(10, "x")
	var _b = lenientSlow.recordMiss(11, "x")
	check(int(lenientSlow.pendingConfront()["level"]) == 1, "a lenient owner needs more misses to escalate")
	var harshFast = makeService("harsh")
	var _c = harshFast.recordMiss(10, "x")
	var _d = harshFast.recordMiss(11, "x")
	check(int(harshFast.pendingConfront()["level"]) == 3, "a harsh owner starts at compensation and escalates to punishment on the second miss")
	var old = makeService("controlling")
	var _e = old.recordMiss(10, "x")
	var _f = old.recordMiss(20, "x")
	check(old.recentMisses(20) == 1 and int(old.pendingConfront()["level"]) == 1, "old misses are forgotten after six days")
	check(OwnershipScript.hesitates(70.0, 10.0, true) and !OwnershipScript.hesitates(70.0, 50.0, true) and !OwnershipScript.hesitates(70.0, 10.0, false) and !OwnershipScript.hesitates(20.0, 10.0, true), "an owner who fears the player and has no trust to lean on hesitates, but only when alone")

	# ---- Enforcement results: winning, losing ----
	var fight = makeService("harsh")
	var _g = fight.recordMiss(10, "x")
	fight.recordOwnerDefeat(10)
	check(fight.pendingConfront().empty() and fight.inGrace(11) and fight.inGrace(12) and !fight.inGrace(13) and fight.distinctWins() == 1 and fight.hasOwner(), "winning ends the consequence, buys two days of grace and does not end ownership")
	fight.recordOwnerDefeat(10)
	check(fight.distinctWins() == 1, "two wins on the same day count once")
	fight.recordOwnerDefeat(12)
	check(fight.distinctWins() == 2, "wins on separate days add up")
	check(!fight.canIssueDemand(OwnershipScript.clockOf(11, 8 * 3600), 11), "no demand during the grace period")
	var effects = {}
	for choice in ["apologise", "submit", "pay", "negotiate", "take", "backdown"]:
		effects[choice] = OwnershipScript.confrontEffect(choice, 2, "controlling", 0.3, 20)
	check(effects["pay"]["clear"] and effects["pay"]["credits"] == -4 and effects["backdown"]["clear"] and effects["backdown"]["credits"] == -4 and !effects["backdown"]["punish"], "paying and backing down both cost the compensation, and back-down is no punishment")
	check(effects["take"]["punish"] and effects["take"]["clear"], "taking it means the existing punishment")
	check(OwnershipScript.confrontEffect("pay", 2, "controlling", 0.3, 2)["refused"], "you cannot pay what you do not have (credits never go below zero)")
	check(OwnershipScript.confrontEffect("backdown", 2, "harsh", 0.0, 2)["credits"] == -2, "backing down takes what you have, never more")
	check(OwnershipScript.confrontEffect("apologise", 1, "harsh", -0.5, 5)["clear"], "a first warning is always settled by an apology")
	check(OwnershipScript.confrontEffect("apologise", 2, "harsh", -0.5, 5)["refused"] and OwnershipScript.confrontEffect("apologise", 2, "lenient", 0.4, 5)["clear"], "an apology for compensation is believed only by someone open to it")
	check(OwnershipScript.confrontEffect("apologise", 3, "lenient", 0.3, 5)["refused"] and OwnershipScript.confrontEffect("apologise", 3, "lenient", 0.5, 5)["clear"], "a punishment is only softened by someone who really trusts you")
	check(OwnershipScript.confrontEffect("negotiate", 2, "controlling", 0.3, 20)["credits"] == -2 and OwnershipScript.confrontEffect("negotiate", 2, "harsh", 0.0, 20)["refused"], "easier terms halve the compensation for someone open to it")
	check(OwnershipScript.compensationFor("lenient") < OwnershipScript.compensationFor("controlling") and OwnershipScript.compensationFor("controlling") < OwnershipScript.compensationFor("harsh"), "compensation grows with the style")

	# ---- Demands ----
	var d1 = makeService("controlling")
	var clock = OwnershipScript.clockOf(10, 10 * 3600)
	check(d1.canIssueDemand(clock, 10), "a demand can be made on a quiet day")
	var facts = {"credits": 20, "ordinaryItem": "bandage", "contraband": "shiv", "canShift": true, "targets": ["a", "b"], "axisNow": 10 * 3600}
	check(!d1.demandPool({"credits": 2, "ordinaryItem": "", "contraband": "", "canShift": false, "targets": []}).has("credits") and d1.demandPool({"credits": 2, "ordinaryItem": "", "contraband": "", "canShift": false, "targets": []}) == ["report"], "with no money, no item, no job and nobody to hit, the only thing they can ask is a report")
	check(!d1.demandPool(facts).has("contraband") and d1.demandPool(facts).has("defeat") and d1.demandPool(facts).has("item"), "a controlling owner asks for goods and a beating, not contraband")
	check(!makeService("lenient").demandPool(facts).has("defeat") and !makeService("lenient").demandPool(facts).has("item") and !makeService("lenient").demandPool(facts).has("contraband"), "a lenient owner asks only small, ordinary things")
	check(makeService("harsh").demandPool(facts).has("contraband"), "a harsh owner may ask for contraband (only when the player really holds some)")
	check(!makeService("harsh").demandPool({"credits": 20, "ordinaryItem": "", "contraband": "", "canShift": false, "targets": []}).has("contraband"), "never an item that cannot be obtained")
	var made = d1.makeDemand(clock, 10, facts)
	check(!made.empty() and made["state"] == "offered" and d1.hasDemand(), "the owner has a demand in mind")
	check(d1.makeDemand(clock + 99999, 11, facts).empty(), "never a second demand while one is active")
	check(same(d1.makeDemand(clock, 10, facts), {}), "and no duplicates")
	for pair in [["lenient", 4], ["controlling", 3], ["harsh", 2]]:
		var gapper = makeService(pair[0])
		var _m = gapper.makeDemand(clock, 10, facts)
		gapper.state.ownership["owner"]["demand"] = {}
		check(!gapper.canIssueDemand(clock + (pair[1] * 86400) - 1, 13) and gapper.canIssueDemand(clock + pair[1] * 86400, 14 + int(pair[1])), pair[0] + ": " + str(pair[1]) + " days between demands")
	var det1 = makeService("controlling").makeDemand(clock, 10, facts)
	var det2 = makeService("controlling").makeDemand(clock, 10, facts)
	check(same(det1, det2), "the same situation makes the same demand")
	# the kinds, one by one
	var credits = makeService("controlling")
	credits.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 1, "type": "credits", "state": "offered", "amount": 4, "created": clock, "deadline": clock + 36 * 3600})
	check(credits.acceptDemand() and credits.demand()["state"] == "active" and !credits.acceptDemand(), "accepting makes it active, once")
	check(!credits.markDemandReady(), "a payment is not a task to report")
	var reward = credits.completeDemand(10)
	check(!reward.empty() and reward["trust"] > 0 and reward["respect"] > 0 and !credits.hasDemand() and credits.completeDemand(10).empty() and credits.recentFulfilled(10) == 1, "completing rewards once and clears it")
	var shift = makeService("controlling")
	shift.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 2, "type": "shift", "state": "active", "created": clock, "deadline": clock + 48 * 3600})
	check(shift.markDemandReady() and shift.demand()["state"] == "ready" and !shift.completeDemand(10).empty(), "a shift is ready when done, then reported")
	# negotiation
	var neg = makeService("controlling")
	neg.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 3, "type": "credits", "state": "offered", "amount": 6, "created": clock, "deadline": clock + 36 * 3600})
	var open = neg.openness(80.0, 60.0, 40.0, 10)
	check(open >= 0.35 and OwnershipScript.opennessWord(open) == "open to it", "a trusted, respected player finds the owner open")
	check(OwnershipScript.opennessWord(neg.openness(-20.0, -10.0, -10.0, 10)) == "not in the mood" and neg.openness(0.0, 0.0, 0.0, 10) < OwnershipScript.OPEN_ENOUGH, "a stranger finds no give")
	check(makeService("lenient").openness(0.0, 0.0, 0.0, 10) > makeService("harsh").openness(0.0, 0.0, 0.0, 10), "lenient owners are more open than harsh ones, other things equal")
	var good = neg.negotiateDemand(0.4, 10)
	check(good["result"] == "eased" and good["amount"] == 3 and neg.demand()["deadline"] == clock + 60 * 3600, "negotiating eases a payment by half and adds a day")
	check(neg.negotiateDemand(0.4, 10)["result"] == "already", "one try per demand")
	var bad = makeService("harsh")
	bad.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 4, "type": "credits", "state": "offered", "amount": 6, "created": clock, "deadline": clock + 36 * 3600})
	check(bad.negotiateDemand(0.0, 10)["result"] == "refused" and bad.demand()["amount"] == 6, "a refusal changes nothing")
	var swap = makeService("harsh")
	swap.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 5, "type": "defeat", "state": "offered", "target": "x", "created": clock, "deadline": clock + 48 * 3600})
	check(swap.negotiateDemand(0.5, 10)["result"] == "replaced" and swap.demand()["type"] == "credits" and swap.demand()["amount"] == 3 and swap.demand()["target"] == "", "an unsuitable task can be swapped for a small payment")
	var ext = makeService("controlling")
	ext.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 6, "type": "shift", "state": "offered", "created": clock, "deadline": clock + 48 * 3600})
	check(ext.negotiateDemand(0.5, 10)["result"] == "extended" and ext.demand()["deadline"] == clock + 72 * 3600, "a task's deadline can be extended")
	# refusal and expiry
	var refuse = makeService("controlling")
	refuse.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 7, "type": "credits", "state": "offered", "amount": 3, "created": clock, "deadline": clock + 36 * 3600})
	check(refuse.refuseDemand(10) == 1 and !refuse.hasDemand() and refuse.pendingConfront()["level"] == 1, "refusing is a miss, and a warning first")
	var lapse = makeService("controlling")
	lapse.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 8, "type": "credits", "state": "active", "amount": 3, "created": clock, "deadline": clock + 36 * 3600})
	check(lapse.expireDemand(clock + 10 * 3600, 10, "") == "" and lapse.hasDemand(), "before the deadline nothing happens")
	check(lapse.expireDemand(clock + 40 * 3600, 11, "") == "missed" and lapse.recentMisses(11) == 1 and !lapse.hasDemand(), "past the deadline an accepted demand is a miss")
	var blocked = makeService("controlling")
	blocked.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 9, "type": "credits", "state": "active", "amount": 3, "created": clock, "deadline": clock + 36 * 3600})
	blocked.noteDemandBlock("locked in the stocks")
	check(blocked.expireDemand(clock + 40 * 3600, 11, "") == "excused" and blocked.recentMisses(11) == 0, "something that kept the player away excuses it")
	var unheard = makeService("controlling")
	unheard.state.ownership["owner"]["demand"] = OwnershipScript.sanitizeDemand({"id": 10, "type": "credits", "state": "offered", "amount": 3, "created": clock, "deadline": clock + 36 * 3600})
	check(unheard.expireDemand(clock + 40 * 3600, 11, "") == "excused" and unheard.recentMisses(11) == 0, "an offer the owner never got to make is never held against the player")
	var report = makeService("controlling")
	var reportDemand = report.makeDemand(clock, 10, {"credits": 0, "ordinaryItem": "", "contraband": "", "canShift": false, "targets": [], "axisNow": 10 * 3600})
	check(reportDemand["type"] == "report" and int(reportDemand["at"]) >= 19 * 3600 and int(reportDemand["day"]) >= 10 and int(reportDemand["deadline"]) > clock, "a 'be at my cell' demand has a time and a day")

	# ---- Protection ----
	var base = {"hasOwner": true, "style": "controlling", "ownerPower": 1.4, "attackerPower": 0.8, "attackerFear": 30.0, "gangStrength": 0.0, "retaliated": false, "available": true, "recentLosses": 0}
	check(OwnershipScript.protection({"hasOwner": false})["multiplier"] == 1.0 and OwnershipScript.protection({"hasOwner": false})["band"] == "None", "nobody owns you: no protection")
	var weak = OwnershipScript.protection({"hasOwner": true, "style": "lenient", "ownerPower": 0.3, "attackerPower": 1.2, "attackerFear": 0.0, "gangStrength": 0.0, "retaliated": false, "available": true, "recentLosses": 0})
	check(weak["band"] == "Weak" and weak["multiplier"] > 0.8, "a feeble, unfeared, lone, lenient owner protects little: " + str(weak["multiplier"]))
	var moderate = OwnershipScript.protection(base)
	check(moderate["band"] != "Weak" and moderate["multiplier"] < weak["multiplier"], "a credible owner means something: " + str(moderate["multiplier"]))
	var strong = OwnershipScript.protection({"hasOwner": true, "style": "harsh", "ownerPower": 1.5, "attackerPower": 0.8, "attackerFear": 80.0, "gangStrength": 6.0, "retaliated": true, "available": true, "recentLosses": 0})
	check(strong["band"] == "Strong" and strong["multiplier"] >= OwnershipScript.PROTECTION_FLOOR and strong["multiplier"] < moderate["multiplier"], "a powerful, feared, gang-backed owner who has hit back is strong, but never immune: " + str(strong["multiplier"]))
	var maxed = OwnershipScript.protection({"hasOwner": true, "style": "harsh", "ownerPower": 99.0, "attackerPower": 0.1, "attackerFear": 100.0, "gangStrength": 99.0, "retaliated": true, "available": true, "recentLosses": 0})
	check(maxed["multiplier"] >= OwnershipScript.PROTECTION_FLOOR, "no inputs can push it below the floor")
	var away = OwnershipScript.protection({"hasOwner": true, "style": "harsh", "ownerPower": 1.5, "attackerPower": 0.8, "attackerFear": 80.0, "gangStrength": 6.0, "retaliated": true, "available": false, "recentLosses": 0})
	check(away["multiplier"] > strong["multiplier"], "an owner who is not around protects less")
	var beaten = OwnershipScript.protection({"hasOwner": true, "style": "harsh", "ownerPower": 1.5, "attackerPower": 0.8, "attackerFear": 80.0, "gangStrength": 6.0, "retaliated": true, "available": true, "recentLosses": 3})
	check(beaten["multiplier"] > strong["multiplier"] and !beaten["reasons"].empty(), "an owner who keeps losing protects less, and the reasons say so")
	var lenientBase = base.duplicate()
	lenientBase["style"] = "lenient"
	check(OwnershipScript.protection(lenientBase)["multiplier"] > OwnershipScript.protection(base)["multiplier"], "a lenient owner shields less than a controlling one")
	for line in strong["reasons"]:
		check(line.find("0.") == -1, "no raw numbers in the reasons")
	var lossy = makeService("controlling")
	lossy.recordOwnerLoss(10)
	lossy.recordOwnerLoss(11)
	check(lossy.recentOwnerLosses(12) == 2 and lossy.recentOwnerLosses(30) == 0, "recent losses are counted, and forgotten")

	# ---- Retaliation ----
	var ret = makeService("harsh")
	ret.noteAggressor("thug", 10)
	ret.noteAggressor("owner1", 10)
	ret.noteAggressor("pc", 10)
	check(ret.isAggressor("thug") and !ret.isAggressor("owner1") and !ret.isAggressor("pc"), "the owner remembers who hurt the player (never themselves or the player)")
	check(ret.retaliationTarget(11, ["thug"]) == "thug" and ret.retaliationTarget(11, ["somebody"]) == "", "they go after a remembered aggressor who can be found")
	ret.recordRetaliation("thug", 11)
	check(ret.retaliationTarget(12, ["thug"]) == "" and ret.retaliationTarget(15, ["thug"]) == "thug", "one attempt per aggressor every few days")
	ret.recordRetaliationResult("thug", false, 15)
	ret.recordRetaliation("thug", 15)
	ret.recordRetaliationResult("thug", false, 19)
	ret.recordRetaliation("thug", 19)
	check(ret.retaliationTarget(40, ["thug"]) == "" or ret.record()["aggressors"]["thug"]["failed"] >= OwnershipScript.RETALIATION_GIVE_UP, "after repeated failures the owner gives up for good")
	var winRet = makeService("harsh")
	winRet.noteAggressor("thug", 10)
	winRet.recordRetaliationResult("thug", true, 11)
	check(winRet.hasRetaliatedAgainst("thug") and winRet.record()["aggressors"]["thug"]["failed"] == 0, "a win is remembered")
	var timid = makeService("harsh")
	timid.noteAggressor("thug", 10)
	timid.recordOwnerLoss(10)
	timid.recordOwnerLoss(10)
	check(timid.retaliationTarget(11, ["thug"]) == "", "an owner who just lost twice stays home")
	var many = makeService("harsh")
	for n in range(30):
		many.noteAggressor("a" + str(n), 10)
	check(many.record()["aggressors"].size() <= 12, "the list of aggressors stays small")

	# ---- Ways out ----
	var rel = makeService("controlling", 10, true)
	var goodFacts = {"day": 10, "trust": 60.0, "respect": 40.0, "affection": 10.0, "fear": 0.0, "credits": 100, "protection": "Moderate", "gangHelp": false, "hostile": false}
	var routes = {}
	for route in rel.releaseRoutes(goodFacts):
		routes[route["id"]] = route
	check(routes.size() == 5 and routes.has("negotiate") and routes.has("buyout") and routes.has("defy") and routes.has("gang") and routes.has("owner"), "five routes are listed")
	check(!routes["negotiate"]["available"] and !routes["buyout"]["available"], "right after volunteering neither negotiation nor a buyout is possible (minimum term)")
	check(routes["negotiate"]["text"].find("day 13") != -1, "and the player is told when")
	goodFacts["day"] = 13
	var routes2 = {}
	for route in rel.releaseRoutes(goodFacts):
		routes2[route["id"]] = route
	check(routes2["negotiate"]["available"] and routes2["buyout"]["available"], "after the term, with trust and respect, both open up")
	check(int(routes2["buyout"]["cost"]) >= 30 and int(routes2["buyout"]["cost"]) <= 60, "the buyout is 30 to 60 credits")
	goodFacts["trust"] = 0.0
	goodFacts["respect"] = 0.0
	var plain = {}
	for route in rel.releaseRoutes(goodFacts):
		plain[route["id"]] = route
	check(!plain["negotiate"]["available"] and plain["buyout"]["available"], "without trust and respect only the money works")
	goodFacts["hostile"] = true
	var angry = {}
	for route in rel.releaseRoutes(goodFacts):
		angry[route["id"]] = route
	check(!angry["buyout"]["available"] and angry["buyout"]["text"].find("angry") != -1, "an owner who loathes the player will not take money")
	goodFacts["hostile"] = false
	goodFacts["credits"] = 5
	var poor = {}
	for route in rel.releaseRoutes(goodFacts):
		poor[route["id"]] = route
	check(!poor["buyout"]["available"] and poor["buyout"]["text"].find("cannot afford") != -1, "and you need the credits")
	goodFacts["trust"] = 20.0
	goodFacts["affection"] = 60.0
	var fond = {}
	for route in rel.releaseRoutes(goodFacts):
		fond[route["id"]] = route
	check(fond["negotiate"]["available"], "high affection alone also opens a negotiated release")
	var costs = {}
	for styleName in StyleScript.STYLES:
		costs[styleName] = makeService(styleName).buyoutCost(0.0, 0.0, 0.0, "Moderate")
	check(costs["lenient"] == 30 and costs["controlling"] == 45 and costs["harsh"] == 60, "buyout by style: " + str(costs))
	check(makeService("controlling").buyoutCost(100.0, 100.0, 100.0, "Weak") >= 30 and makeService("controlling").buyoutCost(-100.0, -100.0, -100.0, "Strong") <= 60, "never outside 30 to 60")
	check(makeService("controlling").buyoutCost(50.0, 50.0, 50.0, "Moderate") < makeService("controlling").buyoutCost(-50.0, -50.0, -50.0, "Moderate"), "a good relationship makes it cheaper")
	check(makeService("controlling").buyoutCost(0.0, 0.0, 0.0, "Strong") > makeService("controlling").buyoutCost(0.0, 0.0, 0.0, "Weak"), "a strong protector costs more to leave")
	# defiance
	for pair in [["lenient", 2], ["controlling", 2], ["harsh", 3]]:
		var defy = makeService(pair[0], 10)
		defy.recordOwnerDefeat(10)
		var one = {}
		for route in defy.releaseRoutes({"day": 20, "trust": 0.0, "respect": 0.0, "affection": 0.0, "credits": 0, "protection": "Moderate", "gangHelp": false, "hostile": false}):
			one[route["id"]] = route
		check(!one["defy"]["available"] and one["defy"]["text"].find("One win is not enough") != -1, pair[0] + ": one victory is not enough")
		for day in range(11, 10 + pair[1]):
			defy.recordOwnerDefeat(day)
		var many2 = {}
		for route in defy.releaseRoutes({"day": 20, "trust": 0.0, "respect": 0.0, "affection": 0.0, "credits": 0, "protection": "Moderate", "gangHelp": false, "hostile": false}):
			many2[route["id"]] = route
		check(many2["defy"]["available"], pair[0] + ": after " + str(pair[1]) + " wins on separate days the player can demand release")
	var helpMe = makeService("controlling")
	var helpRoutes = {}
	for route in helpMe.releaseRoutes({"day": 20, "trust": 0.0, "respect": 0.0, "affection": 0.0, "credits": 0, "protection": "Moderate", "gangHelp": true, "hostile": false}):
		helpRoutes[route["id"]] = route
	check(helpRoutes["gang"]["available"], "a gang that can help opens the outside route")
	# the owner lets go
	var lose = makeService("controlling", 10)
	check(lose.ownerLosesInterest(12, 80.0, 0.0, 0.0) == "" and lose.ownerLosesInterest(12, 10.0, 0.0, 0.0) == "", "an owner who is merely afraid, with no defeat behind it, holds on")
	lose.recordOwnerDefeat(11)
	check(lose.ownerLosesInterest(12, 80.0, 10.0, 0.0) == "afraid" and lose.ownerLosesInterest(12, 80.0, 60.0, 0.0) == "", "afraid, beaten and without trust to lean on: they let go. With trust they do not.")
	check(lose.ownerLosesInterest(25, 0.0, 70.0, 80.0) == "fond" and lose.ownerLosesInterest(12, 0.0, 70.0, 80.0) == "", "an owner who truly cares, after a long time, may let go")
	var gone = lose.end(14, "buyout")
	check(!lose.hasOwner() and gone["how"] == "buyout" and lose.data()["last_release"]["id"] == "owner1", "ending records how")

	# ---- The player's slaves ----
	var sl = makeService()
	check(sl.addSlave("s1", 10) and !sl.addSlave("s1", 10) and !sl.addSlave("pc", 10) and !sl.addSlave("", 10) and sl.hasSlave("s1"), "a slave is recorded once")
	check(sl.slaveRecord("s1")["role"] == "free" and sl.canChangeRole("s1", 10), "everybody starts on a free routine")
	check(sl.setRole("s1", "earner", 10) and !sl.setRole("s1", "rest", 10) and !sl.canChangeRole("s1", 10) and sl.slaveRecord("s1")["role"] == "earner", "one role change per day")
	check(!sl.setRole("s1", "dancer", 11) and sl.setRole("s1", "attendant", 11) and sl.setRole("s1", "rest", 12), "only the four roles exist; one role at a time")
	var earner = makeService()
	var _e1 = earner.addSlave("s2", 10)
	var _e2 = earner.setRole("s2", "earner", 10)
	check(earner.creditEarnings("s2", 11, false) == 0 and earner.slaveRecord("s2")["uncollected"] == 0, "no income if they did not work")
	var amount = earner.creditEarnings("s2", 11, true)
	check(amount >= 2 and amount <= 4 and earner.slaveRecord("s2")["uncollected"] == amount, "2 to 4 credits for a day worked")
	check(earner.creditEarnings("s2", 11, true) == 0, "never twice for the same day (so saving and loading cannot duplicate it)")
	var second = earner.creditEarnings("s2", 12, true)
	check(second >= 2 and earner.slaveRecord("s2")["uncollected"] == amount + second, "the next day pays again")
	var collected = earner.collectEarnings("s2")
	check(collected == amount + second and earner.collectEarnings("s2") == 0 and earner.slaveRecord("s2")["uncollected"] == 0, "collecting hands over what is waiting, once")
	var free = makeService()
	var _f1 = free.addSlave("s3", 10)
	check(free.creditEarnings("s3", 11, true) == 0, "only earners earn")
	check(OwnershipScript.earningFor("s2", 11) == OwnershipScript.earningFor("s2", 11), "the same person and day always pay the same")
	# several earners share the customers: 2-4, then 1-3, then 1 each, and 8 a day at the most in all
	var incomes = {}
	for count in [1, 2, 3, 5, 10, 20]:
		var group = makeService()
		var ids = []
		for n in range(count):
			ids.append("e" + str(n))
			var _ga = group.addSlave(ids[n], 10)
			var _gr = group.setRole(ids[n], "earner", 10)
		var total = 0
		var worst_day = 0
		for day in range(11, 18):
			var day_total = 0
			for id in ids:
				day_total += group.creditEarnings(id, day, true)
			total += day_total
			worst_day = max(worst_day, day_total)
		incomes[count] = total
		check(worst_day <= OwnershipScript.EARN_DAY_CAP, str(count) + " earners never bring in more than the daily cap (worst day " + str(worst_day) + ")")
		print("  seven days, " + str(count) + " earner(s): " + str(total) + " credits (worst day " + str(worst_day) + ")")
	check(incomes[1] >= 14 and incomes[1] <= 28, "one earner: 2-4 a day")
	check(incomes[2] > incomes[1] and incomes[3] >= incomes[2] and incomes[5] >= incomes[3] and incomes[20] <= 56, "more earners earn more, with diminishing returns, and 56 credits a week at most")
	check(incomes[2] < incomes[1] * 2 and incomes[3] < incomes[1] * 3 and incomes[5] < incomes[1] * 5, "never proportional to the number of earners")
	check(OwnershipScript.earningFor("x", 3, 1) >= 1 and OwnershipScript.earningFor("x", 3, 1) <= 3 and OwnershipScript.earningFor("x", 3, 2) == 1 and OwnershipScript.earningFor("x", 3, 9) == 1, "second earner 1-3, the rest 1")
	var capped = makeService()
	for n in range(12):
		var _cc = capped.addSlave("c" + str(n), 10)
		var _cd = capped.setRole("c" + str(n), "earner", 10)
	var paid_first = 0
	for n in range(12):
		paid_first += capped.creditEarnings("c" + str(n), 20, true)
	var reloaded = StateScript.new()
	reloaded.loadData(JSON.parse(JSON.print(capped.state.saveData())).result)
	var after_load = OwnershipScript.new(reloaded)
	var paid_again = 0
	for n in range(12):
		paid_again += after_load.creditEarnings("c" + str(n), 20, true)
	check(paid_first <= 8 and paid_again == 0, "saving and loading in the middle of a day never pays twice or resets the cap")
	var half = makeService()
	for n in range(3):
		var _h1 = half.addSlave("h" + str(n), 10)
		var _h2 = half.setRole("h" + str(n), "earner", 10)
	var first_two = half.creditEarnings("h0", 30, true) + half.creditEarnings("h1", 30, true)
	var half_loaded_state = StateScript.new()
	half_loaded_state.loadData(JSON.parse(JSON.print(half.state.saveData())).result)
	var half_loaded = OwnershipScript.new(half_loaded_state)
	var third = half_loaded.creditEarnings("h2", 30, true)
	check(third == 1 and half_loaded.creditEarnings("h0", 30, true) == 0 and first_two <= 7, "the third earner after a reload still earns 1 (the order survives a save), nobody is paid twice")
	var report2 = makeService()
	var _r1 = report2.addSlave("s4", 10)
	check(report2.askReport("s4", 10) and !report2.askReport("s4", 10) and report2.askReport("s4", 11), "asking a slave to report is once a day")
	# disposition and willingness
	check(OwnershipScript.disposition(50.0, 20.0, 5.0, 30.0, false) == "loyal", "trust, affection, respect: loyal")
	check(OwnershipScript.disposition(5.0, 0.0, 60.0, -5.0, false) == "intimidated", "fear without trust: intimidated")
	check(OwnershipScript.disposition(-30.0, -5.0, 5.0, -20.0, false) == "defiant", "no trust, no fear, no respect: defiant")
	check(OwnershipScript.disposition(-20.0, 20.0, 10.0, -30.0, false) == "resentful", "dislike without fear: resentful")
	check(OwnershipScript.disposition(-5.0, 10.0, 10.0, 0.0, true) == "recovering" and OwnershipScript.disposition(0.0, 0.0, 0.0, 0.0, false) == "uncertain", "recovering and uncertain")
	check(OwnershipScript.willDo("earner", "loyal") and OwnershipScript.willDo("earner", "intimidated") and !OwnershipScript.willDo("earner", "resentful") and !OwnershipScript.willDo("earner", "defiant"), "intimidated slaves comply; resentful and defiant ones refuse the hard duties")
	check(OwnershipScript.willDo("attendant", "resentful") and !OwnershipScript.willDo("attendant", "defiant") and OwnershipScript.willDo("rest", "defiant") and OwnershipScript.willDo("free", "defiant"), "rest and a free routine are never refused")
	for key in OwnershipScript.DISPOSITION_TEXT:
		check(OwnershipScript.DISPOSITION_TEXT[key].begins_with(key.capitalize()), "a plain description for " + key)
	# escape: always telegraphed
	var esc = makeService()
	var _x1 = esc.addSlave("runner", 10)
	var _x2 = esc.giveInstructions("runner", "free", "own", 10)
	check(!esc.escapeStarts("runner", 20, "loyal", true) and !esc.escapeStarts("runner", 20, "intimidated", false), "a loyal slave, or a well-treated one, does not plan to run")
	var starts = 0
	for day in range(20, 120):
		if(esc.escapeStarts("runner", day, "defiant", true)):
			starts += 1
	check(starts >= 40 and starts <= 80, "a neglected defiant slave plans to run on about 60 days in 100: " + str(starts))
	var startDay = -1
	for day in range(20, 120):
		if(esc.escapeStarts("runner", day, "defiant", true)):
			startDay = day
			break
	check(startDay > 0 and same(esc.escapeStarts("runner", startDay, "defiant", true), true), "the same day, the same answer")
	esc.startEscape("runner", startDay, "feeling defiant")
	check(esc.slaveRecord("runner")["escape"]["stage"] == "warning" and esc.escapeAdvance("runner", startDay) == "", "stage one is a warning, and nothing else happens that day")
	check(esc.escapeAdvance("runner", startDay + 1) == "attempt" and esc.slaveRecord("runner")["escape"]["stage"] == "attempt", "the next day is a visible attempt")
	check(esc.escapeAdvance("runner", startDay + 1) == "", "and not a step further the same day")
	check(esc.escapeAdvance("runner", startDay + 2) == "gone", "only if nothing is done is the third day the escape")
	var stopped = makeService()
	var _y1 = stopped.addSlave("runner", 10)
	stopped.startEscape("runner", 20, "x")
	var _y2 = stopped.escapeAdvance("runner", 21)
	stopped.stopEscape("runner", 21)
	check(stopped.slaveRecord("runner")["escape"].empty() and stopped.escapeAdvance("runner", 23) == "" and !stopped.escapeStarts("runner", 23, "defiant", true), "the player stopping it ends it, and they do not try again for a while")
	var restingEscape = makeService()
	var _z1 = restingEscape.addSlave("runner", 10)
	var _z2 = restingEscape.setRole("runner", "rest", 10)
	var plans = 0
	for day in range(20, 120):
		if(restingEscape.escapeStarts("runner", day, "defiant", true)):
			plans += 1
	check(plans == 0, "a slave who is resting does not plan to run")
	check(!esc.removeSlave("nobody") and esc.removeSlave("runner") and !esc.hasSlave("runner"), "a slave can be dropped from the record")
	check(TextScript.telegraphWarning("Ann", "x").find("Ann") != -1 and TextScript.telegraphAttempt("Ann").find("Find them") != -1 and TextScript.telegraphGone("Ann").find("remember") != -1, "the warnings say who and what to do")

	# ---- The saved shape ----
	var saved = makeService("harsh", 10, true)
	var _t1 = saved.startCheckin(10, 12 * 3600)
	var _t2 = saved.makeDemand(OwnershipScript.clockOf(10, 10 * 3600), 10, {"credits": 20, "ordinaryItem": "bandage", "contraband": "shiv", "canShift": true, "targets": ["a"], "axisNow": 10 * 3600})
	saved.recordMiss(10, "x")
	saved.recordOwnerDefeat(11)
	saved.noteAggressor("thug", 10)
	var _t3 = saved.addSlave("s9", 10)
	var _t4 = saved.setRole("s9", "earner", 10)
	var _t5 = saved.creditEarnings("s9", 11, true)
	saved.startEscape("s9", 12, "why")
	var copy = OwnershipScript.sanitize(JSON.parse(JSON.print(saved.data())).result)
	check(same(copy, saved.data()), "everything survives a save as JSON, unchanged")
	var loadedState = StateScript.new()
	loadedState.loadData(JSON.parse(JSON.print(StateScript.new().saveData())).result)
	check(loadedState.schema_version == 9 and same(loadedState.ownership, OwnershipScript.defaults()), "a new save is schema 9 with an empty record")
	var fromState = StateScript.new()
	fromState.ownership = saved.data().duplicate(true)
	var again = StateScript.new()
	again.loadData(JSON.parse(JSON.print(fromState.saveData())).result)
	check(same(again.ownership, saved.data()), "the state saves and loads the record whole")
	var v8 = fromState.saveData()
	v8["schema_version"] = 8
	v8.erase("ownership")
	var migrated = StateScript.new()
	migrated.loadData(JSON.parse(JSON.print(v8)).result)
	check(migrated.schema_version == 9 and same(migrated.ownership, OwnershipScript.defaults()), "an old save has no record and gets an empty one (BDCC's own owner and slaves are picked up when the game next runs)")
	var newer = fromState.saveData()
	newer["schema_version"] = 99
	var future = StateScript.new()
	future.loadData(JSON.parse(JSON.print(newer)).result)
	check(future.schema_version == 99 or future.schema_version >= 9, "a newer save is not downgraded")
	# malformed
	var junk = OwnershipScript.sanitize({"owner": {"id": "o", "since": -5, "style": "terrifying", "next_checkin": "soon", "checkin": {"day": 1e12, "state": "weird", "reminded": "yes"}, "demand": {"type": "poison", "state": "active"},
		"fulfilled": "many", "misses": [1, "x", null, 2], "warnings": 500, "confront": {"level": 99, "reason": 5}, "wins": [3, 3, 3], "aggressors": {"a": 7, "pc": {}, "": {}, "b": {"day": "x", "failed": 99}}, "final": 12},
		"slaves": {"s": {"role": "emperor", "uncollected": 99999, "escape": {"stage": "teleport"}, "report": {"day": "x"}}, "pc": {}, "": {}, "t": 5}, "last_release": {"id": 5}, "tick_day": "x"})
	var o = junk["owner"]
	check(o["id"] == "o" and o["since"] == 0 and o["style"] == "controlling" and o["next_checkin"] == 0 and o["checkin"]["state"] == "" and o["checkin"]["reminded"] == false and o["checkin"]["day"] <= 1000000, "malformed owner fields are repaired")
	check(o["demand"].empty() and o["fulfilled"].empty() and o["misses"] == [1, 2] and o["warnings"] <= 20 and o["confront"]["level"] == 3 and o["wins"] == [3, 3, 3] and !o["aggressors"].has("pc") and !o["aggressors"].has("") and o["aggressors"]["b"]["failed"] <= 20 and o["final"].empty(), "lists, counters and nested records too")
	check(junk["slaves"].size() == 1 and junk["slaves"]["s"]["role"] == "free" and junk["slaves"]["s"]["uncollected"] <= 99 and junk["slaves"]["s"]["escape"].empty() and junk["slaves"]["s"]["report"].empty() and junk["tick_day"] == -1 and junk["last_release"].empty(), "slaves, and the bookkeeping")
	check(same(OwnershipScript.sanitize(null), OwnershipScript.defaults()) and same(OwnershipScript.sanitize("garbage"), OwnershipScript.defaults()) and same(OwnershipScript.sanitize({"owner": {"id": "pc"}}), OwnershipScript.defaults()), "nothing at all, or an owner who is the player, gives an empty record")
	check(OwnershipScript.sanitizeDemand({"type": "credits", "state": "active", "amount": -4, "deadline": "x"})["amount"] == 0, "a demand's numbers are clamped")


	# ---- A new slave waits for instructions ----
	var z_nb = makeService()
	var _n1 = z_nb.addSlave("newbie", 10)
	check(z_nb.isAwaiting("newbie") and z_nb.slaveRecord("newbie")["role"] == "free" and z_nb.slaveRecord("newbie")["night"] == "own" and !z_nb.slaveRecord("newbie")["wait_cell"], "a new slave awaits instructions with nothing assigned")
	var z_awaitingRuns = 0
	for day in range(11, 80):
		if(z_nb.escapeStarts("newbie", day, "defiant", true)):
			z_awaitingRuns += 1
	check(z_awaitingRuns == 0, "a slave who is still waiting never starts planning to run")
	check(!z_nb.giveInstructions("newbie", "emperor", "own", 10) and !z_nb.giveInstructions("newbie", "free", "never", 10) and !z_nb.giveInstructions("ghost", "free", "own", 10) and z_nb.isAwaiting("newbie"), "nonsense instructions change nothing")
	check(z_nb.giveInstructions("newbie", "earner", "player", 10, 1000) and !z_nb.isAwaiting("newbie") and z_nb.slaveRecord("newbie")["role"] == "earner" and z_nb.slaveRecord("newbie")["night"] == "player", "giving instructions sets role and night and ends the waiting")
	check(!z_nb.roleActive("newbie", 1000) and !z_nb.roleActive("newbie", 1000 + OwnershipScript.ROLE_TRANSITION_SECONDS - 1) and z_nb.roleActive("newbie", 1000 + OwnershipScript.ROLE_TRANSITION_SECONDS), "a role takes over half an hour later, not on the spot")
	check(!z_nb.escapeStarts("newbie", 11, "defiant", true), "and in the first days after being enslaved nobody starts planning to run")
	var z_graceOver = 0
	for day in range(12, 120):
		if(z_nb.escapeStarts("newbie", day, "defiant", true)):
			z_graceOver += 1
	check(z_graceOver > 0, "after the grace period the usual rules apply")
	check(z_nb.setNight("newbie", "own") and z_nb.slaveRecord("newbie")["night"] == "own" and !z_nb.setNight("newbie", "elsewhere") and !z_nb.setNight("ghost", "own"), "the night arrangement can be changed to a known value")
	var z_nbState = StateScript.new()
	z_nbState.ownership = z_nb.state.ownership.duplicate(true)
	var z_nbAgain = StateScript.new()
	z_nbAgain.loadData(JSON.parse(JSON.print(z_nbState.saveData())).result)
	check(same(z_nbAgain.ownership, z_nb.state.ownership), "the new slave fields save and load whole")
	var z_oldSlave = OwnershipScript.sanitizeSlave({"role": "earner", "since": 4})
	check(z_oldSlave["setup"] == "set" and z_oldSlave["night"] == "own" and z_oldSlave["role_from"] == -1 and !z_oldSlave["wait_cell"] and z_oldSlave["aftermath"].empty(), "a slave from an older save is not suddenly waiting for instructions")
	var z_oddSlave = OwnershipScript.sanitizeSlave({"setup": "maybe", "night": "weird", "role_from": "later", "wait_cell": "yes", "aftermath": {"kind": "nonsense"}})
	check(z_oddSlave["setup"] == "set" and z_oddSlave["night"] == "own" and z_oddSlave["role_from"] == -1 and !z_oddSlave["wait_cell"] and z_oddSlave["aftermath"].empty(), "malformed arrangement fields are repaired")
	var z_oddDefeats = OwnershipScript.sanitize({"defeated": {"a": {"day": 3, "kind": "surrender"}, "pc": {"day": 1}, "": {}, "b": {"day": "x", "kind": "zzz"}, "c": 5}})
	check(z_oddDefeats["defeated"].size() == 2 and z_oddDefeats["defeated"]["a"]["kind"] == "surrender" and z_oddDefeats["defeated"]["b"]["kind"] == "fight" and z_oddDefeats["defeated"]["b"]["day"] == 0, "remembered defeats are repaired")
	check(z_nb.noteDefeat("ghost", 5, "fight") == null and z_nb.state.ownership["defeated"]["ghost"]["day"] == 5 and z_nb.lastDefeat("ghost")["kind"] == "fight", "a defeat is remembered")
	z_nb.noteDefeat("ghost", 6, "weird")
	check(z_nb.lastDefeat("ghost")["day"] == 5, "an unknown kind of defeat is ignored")
	check(OwnershipScript.NIGHTS.size() == 3 and OwnershipScript.ROLE_TEXT["free"].find("ordinary prison routine") != -1 and OwnershipScript.ROLE_TEXT["earner"].find("prostitution") != -1 and OwnershipScript.ROLE_TEXT["attendant"].find("help me if trouble starts") != -1 and OwnershipScript.ROLE_TEXT["rest"] == "Avoid duties and recover.", "the role instructions say what is actually expected")
	check(OwnershipScript.NIGHT_TEXT["player"] == "Sleep in my cell each night." and OwnershipScript.NIGHT_TEXT["own"] == "Sleep in your own cell." and OwnershipScript.NIGHT_TEXT["order"] == "Keep your own cell and report only when ordered.", "and so do the night arrangements")

	# ---- How enslaving leaves the slave feeling ----
	check(OwnershipScript.aftermathKind(true, "kidnap", "fight", 0.0, 0.0) == "forced" and OwnershipScript.aftermathKind(true, "kidnap", "", 0.0, 0.0) == "forced", "breaking tasks after a defeat are forced enslavement")
	check(OwnershipScript.aftermathKind(true, "kidnap", "surrender", 0.0, 0.0) == "submission", "a surrender accepted before the breaking is submission")
	check(OwnershipScript.aftermathKind(false, "free", "", 5.0, 0.0) == "submission" and OwnershipScript.aftermathKind(false, "free", "", 30.0, 20.0) == "voluntary" and OwnershipScript.aftermathKind(false, "free", "", 30.0, 5.0) == "submission", "the talk option is voluntary only for somebody already warm and trusting")
	check(OwnershipScript.aftermathKind(false, "kidnap", "", 0.0, 0.0) == "unknown" and OwnershipScript.aftermathKind(false, "", "", 0.0, 0.0) == "unknown", "anything else is unknown")
	var z_blank = {"trust": 0.0, "affection": 0.0, "respect": 0.0, "fear": 0.0, "desire": 0.0}
	var z_forced = OwnershipScript.aftermathDeltas("forced", "fight", z_blank)
	check(z_forced["trust"] == -25.0 and z_forced["affection"] == -12.0 and z_forced["fear"] == 22.0 and z_forced["respect"] == 4.0 and z_forced["desire"] == 0.0, "forced after a fight: trust -25, affection -12, fear +22, respect +4, desire unchanged")
	var z_forcedNoFight = OwnershipScript.aftermathDeltas("forced", "", z_blank)
	check(z_forcedNoFight["respect"] == -6.0 and OwnershipScript.aftermathDeltas("forced", "surrender", z_blank)["respect"] == 1.0, "respect reflects how they were beaten")
	var z_submission = OwnershipScript.aftermathDeltas("submission", "fight", z_blank)
	var z_submissionSurrender = OwnershipScript.aftermathDeltas("submission", "surrender", z_blank)
	check(z_submission["trust"] == -12.0 and z_submission["fear"] == 12.0 and z_submission["affection"] == -4.0 and z_submission["respect"] == 4.0 and z_submissionSurrender["respect"] == 1.0, "submission is milder than a forced outcome and respect depends on the fight")
	var z_voluntary = OwnershipScript.aftermathDeltas("voluntary", "", z_blank)
	check(z_voluntary["trust"] == 3.0 and z_voluntary["affection"] == 3.0 and z_voluntary["respect"] == 2.0 and z_voluntary["fear"] == 0.0 and z_voluntary["desire"] == 0.0, "voluntary: a little more trust, affection and respect, no fear, no desire")
	var z_unknownBlank = OwnershipScript.aftermathDeltas("unknown", "", z_blank)
	var z_unknownKnown = OwnershipScript.aftermathDeltas("unknown", "", {"trust": 12.0, "affection": 0.0, "respect": 0.0, "fear": 0.0, "desire": 0.0})
	check(z_unknownBlank["trust"] == -10.0 and z_unknownBlank["affection"] == -5.0 and z_unknownBlank["fear"] == 8.0 and z_unknownBlank["respect"] == -2.0 and z_unknownBlank["desire"] == 0.0, "a debug conversion of a blank slate gets a cautious negative baseline")
	check(z_unknownKnown["trust"] == 0.0 and z_unknownKnown["fear"] == 0.0 and z_unknownKnown["affection"] == 0.0 and z_unknownKnown["respect"] == 0.0, "but existing feelings are kept as they are")
	for z_kind in ["forced", "submission"]:
		for z_defeat in ["fight", "surrender", ""]:
			var z_d = OwnershipScript.aftermathDeltas(z_kind, z_defeat, z_blank)
			check(z_d["trust"] < 0.0 and z_d["affection"] < 0.0 and z_d["fear"] > 0.0 and z_d["desire"] == 0.0, z_kind + " after " + z_defeat + " never makes them friendlier")
	var z_marked = makeService()
	var _m1 = z_marked.addSlave("m1", 10)
	check(z_marked.markAftermath("m1", "forced", 10) and !z_marked.markAftermath("m1", "voluntary", 11) and z_marked.slaveRecord("m1")["aftermath"]["kind"] == "forced" and !z_marked.markAftermath("m1", "nonsense", 10) and !z_marked.markAftermath("ghost", "forced", 10), "the aftermath is recorded once, so a load can never apply it again")

	# ---- Who would look after the player: capability and willingness ----
	var z_neutralBase = {"powerRank": 0.5, "gangBacking": 0.0, "isLeader": false, "subby": 0.0, "trust": 0.0, "respect": 0.0, "affection": 0.0, "fear": 0.0, "desire": 0.0, "injury": 0, "captive": false,
		"ownGangLeader": false, "ownGangMember": false, "ownGangWarm": true, "gangHostile": false, "gangEnemy": false, "playerBacked": false}
	var z_pf
	z_pf = z_neutralBase.duplicate()
	var z_neutral = OwnershipScript.protectorDecision(z_pf)
	check(!z_neutral["accepts"] and z_neutral["capability"] >= OwnershipScript.CAPABLE_AT and z_neutral["reasons"].size() >= 1 and z_neutral["reasons"].size() <= 2 and z_neutral["hint"] != "", "an average, neutral stranger is capable but needs a reason, and says so")
	z_pf = z_neutralBase.duplicate()
	z_pf["subby"] = -0.5
	check(OwnershipScript.protectorDecision(z_pf)["accepts"], "a capable, dominant inmate would do it even as a stranger")
	z_pf = z_neutralBase.duplicate()
	z_pf["respect"] = 25.0
	check(OwnershipScript.protectorDecision(z_pf)["accepts"], "and so would an average one who respects the player a little: no best friend needed")
	z_pf = z_neutralBase.duplicate()
	z_pf["subby"] = 0.3
	z_pf["respect"] = 50.0
	check(OwnershipScript.protectorDecision(z_pf)["accepts"], "a mildly submissive one is still possible")
	z_pf = z_neutralBase.duplicate()
	z_pf["subby"] = 0.7
	z_pf["respect"] = 80.0
	z_pf["trust"] = 60.0
	var z_submissive = OwnershipScript.protectorDecision(z_pf)
	check(!z_submissive["accepts"] and z_submissive["reasons"][0] == "I'd rather be the one receiving protection.", "only a strongly submissive one prefers being protected, whatever they feel")
	z_pf = z_neutralBase.duplicate()
	z_pf["powerRank"] = 0.1
	z_pf["respect"] = 60.0
	var z_weak = OwnershipScript.protectorDecision(z_pf)
	check(!z_weak["accepts"] and z_weak["reasons"][0] == "I'm not strong enough to keep anyone off you." and z_weak["capability"] < OwnershipScript.CAPABLE_AT, "a weak one is willing but not capable, and says so")
	z_pf = z_neutralBase.duplicate()
	z_pf["powerRank"] = 0.1
	z_pf["gangBacking"] = 0.9
	z_pf["isLeader"] = true
	z_pf["respect"] = 40.0
	var z_leader = OwnershipScript.protectorDecision(z_pf)
	check(z_leader["accepts"] and z_leader["capability"] > 0.6, "a gang leader is judged on the gang behind them, not only on their own fists")
	z_pf["isLeader"] = false
	check(OwnershipScript.protectorCapability(z_pf) < z_leader["capability"], "a member gets less of that than the leader")
	z_pf = z_neutralBase.duplicate()
	z_pf["respect"] = 40.0
	z_pf["injury"] = 3
	var z_hurt = OwnershipScript.protectorDecision(z_pf)
	check(!z_hurt["accepts"] and z_hurt["reasons"][0] == "Not while I'm this badly injured." and z_hurt["hint"].find("recover") != -1, "a badly injured one waits until they are well, and says what to do")
	z_pf["injury"] = 2
	check(OwnershipScript.protectorCapability(z_pf) < OwnershipScript.protectorCapability(z_neutralBase), "a moderate injury only weakens them")
	z_pf = z_neutralBase.duplicate()
	z_pf["affection"] = -50.0
	z_pf["subby"] = -0.8
	var z_hateful = OwnershipScript.protectorDecision(z_pf)
	check(!z_hateful["accepts"] and z_hateful["reasons"][0] == "After what you've done to me, I'm not helping you.", "somebody with a hostile history refuses first of all")
	z_pf = z_neutralBase.duplicate()
	z_pf["respect"] = 40.0
	z_pf["gangHostile"] = true
	var z_hostileGang = OwnershipScript.protectorDecision(z_pf)
	check(!z_hostileGang["accepts"] and z_hostileGang["reasons"][0] == "My gang wouldn't accept that while you stand with our enemies." and z_hostileGang["hint"].find("standing") != -1, "a member of a hostile gang is blocked by their gang")
	z_pf = z_neutralBase.duplicate()
	z_pf["gangBacking"] = 0.5
	z_pf["ownGangLeader"] = true
	z_pf["isLeader"] = true
	var z_ownLeader = OwnershipScript.protectorDecision(z_pf)
	check(z_ownLeader["accepts"] and z_ownLeader["willingness"] >= z_neutralBase["respect"] + 0.6, "the leader of the player's own gang is willing even to a stranger")
	z_pf["trust"] = -40.0
	check(!OwnershipScript.protectorDecision(z_pf)["accepts"], "unless they hate the player")
	z_pf = z_neutralBase.duplicate()
	z_pf["ownGangLeader"] = true
	z_pf["ownGangWarm"] = false
	check(OwnershipScript.protectorWillingness(z_pf) < OwnershipScript.protectorWillingness(z_neutralBase) + 0.3, "a cold leader gets no bonus")
	z_pf = z_neutralBase.duplicate()
	z_pf["fear"] = 70.0
	var z_afraid = OwnershipScript.protectorDecision(z_pf)
	check(!z_afraid["accepts"] and z_afraid["reasons"][0] == "You scare me too much for that.", "somebody who fears the player and does not trust them refuses")
	z_pf = z_neutralBase.duplicate()
	z_pf["captive"] = true
	z_pf["respect"] = 60.0
	check(!OwnershipScript.protectorDecision(z_pf)["accepts"] and OwnershipScript.protectorDecision(z_pf)["reasons"][0].find("no position") != -1, "somebody who is held cannot")
	z_pf = z_neutralBase.duplicate()
	z_pf["playerBacked"] = true
	var z_backed = OwnershipScript.protectorDecision(z_pf)
	check(!z_backed["accepts"] and z_backed["reasons"].has("You already have protection behind you."), "somebody who sees that the player already has a strong gang behind them says so")
	var z_manyReasons = true
	for z_subby in [-0.8, 0.0, 0.8]:
		for z_inj in [0, 3]:
			for z_hostile in [false, true]:
				for z_gang in [false, true]:
					z_pf = z_neutralBase.duplicate()
					z_pf["subby"] = z_subby
					z_pf["injury"] = z_inj
					z_pf["affection"] = -50.0 if z_hostile else 0.0
					z_pf["gangHostile"] = z_gang
					z_pf["powerRank"] = 0.05
					var z_d2 = OwnershipScript.protectorDecision(z_pf)
					if(!z_d2["accepts"] and (z_d2["reasons"].size() < 1 or z_d2["reasons"].size() > 2 or z_d2["hint"] == "")):
						z_manyReasons = false
					if(z_d2["accepts"] and !z_d2["reasons"].empty()):
						z_manyReasons = false
	check(z_manyReasons, "a refusal always gives one primary reason, at most one more, and a direction; an acceptance gives none")


	# ---- Rival claims: who wins, who backs down, who cannot answer ----
	var q_facts = {"ownerAble": true, "claimantAble": true, "ownerPower": 1.0, "claimantPower": 1.0, "ownerGang": 0.0, "claimantGang": 0.0, "ownerInjury": 0, "claimantInjury": 0, "style": "controlling", "claimantCoward": 0.0, "support": "none"}
	var q_outcome = OwnershipScript.contestOutcome(q_facts, 0.0)
	check(q_outcome["result"] == "owner_wins" and OwnershipScript.contestOutcome(q_facts, 0.999)["result"] == "claimant_wins", "an even match is decided by the roll: low roll the owner, high roll the claimant")
	check(q_outcome["ownerChance"] > 0.5, "a controlling owner defending their claim has the edge: " + str(q_outcome["ownerChance"]))
	var q_a = q_facts.duplicate()
	q_a["ownerAble"] = false
	check(OwnershipScript.contestOutcome(q_a, 0.0)["result"] == "postponed", "an owner who is held, knocked out, badly hurt or away cannot contest: postponed")
	q_a = q_facts.duplicate()
	q_a["claimantAble"] = false
	check(OwnershipScript.contestOutcome(q_a, 0.999)["result"] == "claimant_unable", "a claimant who cannot back it up gives up")
	q_a = q_facts.duplicate()
	q_a["claimantPower"] = 0.3
	check(OwnershipScript.contestOutcome(q_a, 0.999)["result"] == "backs_down", "a much weaker claimant backs down whatever the roll")
	q_a = q_facts.duplicate()
	q_a["claimantCoward"] = 0.8
	check(OwnershipScript.contestOutcome(q_a, 0.999)["result"] == "backs_down", "so does a timid one")
	q_a = q_facts.duplicate()
	q_a["style"] = "lenient"
	q_a["claimantPower"] = 1.3
	check(OwnershipScript.contestOutcome(q_a, 0.0)["result"] == "owner_yields", "a lenient owner gives way to somebody stronger")
	q_a["support"] = "owner"
	check(OwnershipScript.contestOutcome(q_a, 0.0)["result"] != "owner_yields", "unless the player stands with them")
	q_a = q_facts.duplicate()
	q_a["support"] = "owner"
	var q_backed = OwnershipScript.contestOutcome(q_a, 0.5)["ownerChance"]
	q_a["support"] = "claimant"
	var q_against = OwnershipScript.contestOutcome(q_a, 0.5)["ownerChance"]
	check(q_backed > q_outcome["ownerChance"] and q_against < q_outcome["ownerChance"], "the player's side changes the odds")
	q_a = q_facts.duplicate()
	q_a["claimantGang"] = 1.0
	q_a["ownerInjury"] = 2
	check(OwnershipScript.contestOutcome(q_a, 0.5)["ownerChance"] < q_outcome["ownerChance"], "a gang behind the claimant, or an injured owner, shifts it")
	check(OwnershipScript.contestOutcome(q_facts, 0.3)["result"] == OwnershipScript.contestOutcome(q_facts, 0.3)["result"], "the same facts and roll always give the same result")
	var q_svc = makeService()
	check(q_svc.disputeAllowed("c1", 10), "the first dispute is allowed")
	q_svc.noteDispute("c1", 10, "owner_wins")
	check(!q_svc.disputeAllowed("c1", 11) and !q_svc.disputeAllowed("c2", 11) and q_svc.disputeAllowed("c2", 12) and !q_svc.disputeAllowed("c1", 12) and q_svc.disputeAllowed("c1", 13), "at most one dispute every two days, the same claimant not again for three")
	q_svc.noteDispute("c9", 20, "nonsense")
	check(!q_svc.state.ownership["disputes"].has("c9"), "an unknown result is not recorded")
	for q_i in range(30):
		q_svc.noteDispute("x" + str(q_i), 20 + q_i, "backs_down")
	check(q_svc.state.ownership["disputes"].size() <= 20, "the record is bounded")
	var q_junk = OwnershipScript.sanitize({"disputes": {"a": {"day": 3, "result": "claimant_wins"}, "pc": {}, "": {}, "b": {"day": "x", "result": "zzz"}, "c": 4}, "last_dispute": "soon"})
	check(q_junk["disputes"].size() == 2 and q_junk["disputes"]["a"]["result"] == "claimant_wins" and q_junk["disputes"]["b"]["result"] == "owner_wins" and q_junk["last_dispute"] == -100, "malformed dispute records are repaired")
	# ---- The owner coming running ----
	check(OwnershipScript.INTERVENTION_GAP_DAYS == 1, "the owner's protection is once per in-game day, with no chance roll")
	var q_own = makeService()
	check(q_own.interventionReadyOn() == 8 or q_own.interventionReadyOn() <= 0 or q_own.interventionReadyOn() < 10, "a new owner is ready to help at once")
	q_own.noteIntervention(12)
	check(q_own.interventionReadyOn() == 12 + OwnershipScript.INTERVENTION_GAP_DAYS and q_own.record()["last_help"] == 12, "after stepping in they are ready again the next day")
	var q_state = StateScript.new()
	q_state.ownership = q_own.state.ownership.duplicate(true)
	var q_again = StateScript.new()
	q_again.loadData(JSON.parse(JSON.print(q_state.saveData())).result)
	check(q_again.ownership["owner"]["last_help"] == 12, "and that survives saving and loading")
	check(OwnershipScript.sanitizeOwner({"id": "o", "last_help": "never"})["last_help"] == -100, "a malformed record is repaired")

	# ---- Reports, meetings, nights, rescue ----
	var m_svc = makeService()
	check(!m_svc.hasMeeting() and m_svc.startMeeting(5, "task") and m_svc.hasMeeting() and !m_svc.startMeeting(5, "check"), "one meeting at a time")
	check(!m_svc.meetingDue(4) and m_svc.meetingDue(5) and m_svc.markMeetingTold() and !m_svc.markMeetingTold(), "a meeting is due on its day and is told once")
	check(m_svc.postponeMeeting(6) and !m_svc.postponeMeeting(6) and m_svc.meeting()["day"] == 6 and m_svc.hasMeeting(), "a blocked meeting moves to the next day, with one notice")
	var m_state = StateScript.new()
	m_state.ownership = m_svc.state.ownership.duplicate(true)
	var m_again = StateScript.new()
	m_again.loadData(JSON.parse(JSON.print(m_state.saveData())).result)
	check(m_again.ownership["owner"]["meeting"]["day"] == 6 and m_again.ownership["owner"]["meeting"]["told"], "a pending meeting survives saving and loading")
	check(m_svc.finishMeeting() and !m_svc.hasMeeting() and !m_svc.finishMeeting(), "a meeting ends once")
	check(OwnershipScript.nightMode("harsh", "a1") == OwnershipScript.nightMode("harsh", "a1"), "the night mode is deterministic")
	var n_modes:Dictionary = {}
	for n_i in range(200):
		n_modes[OwnershipScript.nightMode("lenient", "s" + str(n_i))] = true
	check(n_modes.has("require") and n_modes.has("invite") and n_modes.has("allow"), "every night mode can happen")
	m_svc.noteIntimacy(10)
	check(!m_svc.canHaveIntimacy(11) and m_svc.canHaveIntimacy(12), "intimacy at most once in two nights")
	check(OwnershipScript.intimacyIntent("lenient", 0.0, 0.0) == "ask" and OwnershipScript.intimacyIntent("harsh", 0.0, -5.0) == "force" and OwnershipScript.intimacyIntent("controlling", 0.0, 0.0) == "demand" and OwnershipScript.intimacyIntent("harsh", 30.0, 30.0) == "ask", "style and relationship decide ask, demand or force")
	check(OwnershipScript.intimacyChance("harsh", 1.0, 100.0, 50.0) <= 0.70 and OwnershipScript.intimacyChance("lenient", -1.0, 0.0, -50.0) >= 0.05, "intimacy chance is bounded")
	var d_svc = makeService()
	d_svc.notePlayerDefeat(1000, "npcA")
	check(d_svc.rescueDue(2000) and !d_svc.rescueDue(1000 + OwnershipScript.RESCUE_WINDOW_SECONDS + 1), "a rescue is due soon after a defeat")
	d_svc.markRescueStarted(2000)
	check(!d_svc.rescueDue(2100), "and only once")
	var d_state = StateScript.new()
	d_state.ownership = d_svc.state.ownership.duplicate(true)
	var d_again = StateScript.new()
	d_again.loadData(JSON.parse(JSON.print(d_state.saveData())).result)
	check(d_again.ownership["pc_defeat"]["handled"] == true, "the rescue record survives saving and loading")

	check(OwnershipScript.choosePurpose({"confront": 1}, "x") == "warning" and OwnershipScript.choosePurpose({"confront": 2}, "x") == "compensation" and OwnershipScript.choosePurpose({"confront": 3, "demand": "ready"}, "x") == "punishment", "a meeting's purpose follows what is owed, worst first")
	check(OwnershipScript.choosePurpose({"demand": "ready", "notable": true}, "x") == "review" and OwnershipScript.choosePurpose({"notable": true}, "x") == "reward" and OwnershipScript.choosePurpose({"intimacyOk": true, "intimacyChance": 0.7}, "x") == OwnershipScript.choosePurpose({"intimacyOk": true, "intimacyChance": 0.7}, "x"), "review, then reward, and the same facts always give the same purpose")
	check(OwnershipScript.checkinOutcomeKind({"confront": 1, "notable": true}, 0.0) == "warning" and OwnershipScript.checkinOutcomeKind({"notable": true, "intimacyOk": true, "intimacyChance": 1.0}, 0.0) == "praise" and OwnershipScript.checkinOutcomeKind({"intimacyOk": true, "intimacyChance": 0.5}, 0.4) == "intimacy" and OwnershipScript.checkinOutcomeKind({"intimacyOk": true, "intimacyChance": 0.5}, 0.6) == "stay" and OwnershipScript.checkinOutcomeKind({}, 0.0) == "stay", "a check-in turns into a warning, then praise, then intimacy, otherwise the stay")
	var u_legacy = OwnershipScript.sanitizeOwner({"id": "o", "meeting": {"day": 3, "purpose": "task"}})
	check(u_legacy["meeting"]["purpose"] == "demand" and OwnershipScript.sanitizeOwner({"id": "o", "meeting": {"day": 3, "purpose": "zzz"}})["meeting"]["purpose"] == "attention", "older or malformed meeting purposes are repaired")
	var u_svc = makeService()
	check(!u_svc.notableCompliance(10), "nothing notable at the start")
	u_svc.record()["fulfilled"] = [8, 9, 10]
	check(u_svc.notableCompliance(10), "a good run is notable")
	u_svc.notePraise(10)
	check(!u_svc.notableCompliance(11) and !u_svc.notableCompliance(12) and u_svc.notableCompliance(13), "and is acknowledged at most once in three days")
	u_svc.setCheckinOutcome("praise", "")
	check(u_svc.checkinOutcome() == "praise", "the check-in outcome is stored")
	print("OwnershipTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

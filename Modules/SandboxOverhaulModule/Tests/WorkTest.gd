extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/WorkTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const UpgradesScript = preload("res://Modules/SandboxOverhaulModule/Cells/CellUpgrades.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func make():
	var s = StateScript.new()
	return [s, EmploymentScript.new(s), UpgradesScript.new(s)]

func hours(h:float) -> int:
	return int(h * 3600)

func record(id:String, uniqueID:String, amount:int = 1) -> Dictionary:
	return {"id": id, "uniqueID": uniqueID, "data": {"amount": amount, "note": {"deep": [1, 2]}}}

func _init():
	# ---- Jobs ----
	check(EmploymentScript.JOB_ORDER.size() == 3 and EmploymentScript.JOBS.size() == 3, "three jobs")
	for jobID in EmploymentScript.JOB_ORDER:
		var job = EmploymentScript.JOBS[jobID]
		check(job["close"] - job["open"] == 2 and job["hours"] == 2, jobID + ": two-hour window and shift")
		check(job["wage"] >= 2 and job["wage"] <= 4, jobID + ": wage 2 to 4")
		check(job["name"] != "" and job["workplace"] != "" and job["room"] != "" and job["stamina"] > 0, jobID + ": complete definition")
	check(EmploymentScript.jobAtRoom("mining_shafts_entering") == "mining" and EmploymentScript.jobAtRoom("eng_workshop") == "workshop" and EmploymentScript.jobAtRoom("main_laundry") == "laundry" and EmploymentScript.jobAtRoom("elsewhere") == "", "workplaces are real rooms")

	# ---- Defaults, windows ----
	var m = make()
	var s = m[0]
	var emp = m[1]
	check(!emp.isEmployed() and emp.getJobID() == "" and emp.getWarnings() == 0 and !emp.isDismissed(1) and emp.getShiftStatus(1) == "not started" and !emp.isShiftCompleteToday(1), "new characters are unemployed")
	check(EmploymentScript.isWindowOpen("mining", hours(8)) and EmploymentScript.isWindowOpen("mining", hours(9.99)) and !EmploymentScript.isWindowOpen("mining", hours(10)) and !EmploymentScript.isWindowOpen("mining", hours(7.99)), "window is [open, close)")
	check(EmploymentScript.isWindowClosed("mining", hours(10)) and !EmploymentScript.isWindowClosed("mining", hours(9)), "window closes at the end hour")
	check(!emp.canStartShift("mining", 1, hours(9))["ok"], "no shift without a job")

	# ---- Accepting and leaving ----
	check(!emp.canApply("nope", 1)["ok"] and !emp.accept("nope", 1, hours(7))["ok"] and !emp.isEmployed(), "unknown jobs are refused")
	check(emp.accept("mining", 1, hours(7))["ok"] and emp.getJobID() == "mining", "take a job")
	check(!emp.accept("laundry", 1, hours(7))["ok"] and emp.getJobID() == "mining" and !emp.accept("mining", 1, hours(7))["ok"], "only one job at a time")
	check(emp.hasOpenShift(1) and emp.getShiftStatus(1) == "not started", "a shift is expected today")
	check(emp.leave(1) and !emp.isEmployed() and !emp.hasOpenShift(1) and !emp.leave(1), "leave the job")
	check(emp.getHistory()["missed"] == 0 and emp.getWarnings() == 0, "leaving before the shift costs nothing")

	# ---- A paid shift ----
	check(emp.accept("mining", 1, hours(7))["ok"], "rehired")
	check(emp.tick(1, hours(7), "").empty(), "nothing before the window opens")
	var events = emp.tick(1, hours(8), "")
	check(events.size() == 1 and events[0]["type"] == "reminder" and events[0]["job"] == "mining", "reminder when the window opens")
	check(emp.tick(1, hours(8.5), "").empty() and emp.tick(1, hours(9), "").empty(), "only one reminder")
	check(!emp.canStartShift("mining", 1, hours(7))["ok"] and emp.canStartShift("mining", 1, hours(8))["ok"] and !emp.canStartShift("laundry", 1, hours(8))["ok"], "start only in the window and only at your workplace")
	check(emp.completeShift("laundry", 1, hours(8)) == 0 and emp.getHistory()["completed"] == 0, "the wrong workplace pays nothing")
	var wage = emp.completeShift("mining", 1, hours(8.5))
	check(wage == 3 and emp.getShiftStatus(1) == "completed" and emp.isShiftCompleteToday(1) and emp.getHistory()["completed"] == 1 and emp.getHistory()["wages"] == 3, "the shift pays its wage once and is recorded")
	check(emp.completeShift("mining", 1, hours(8.6)) == 0 and emp.getHistory()["wages"] == 3 and !emp.canStartShift("mining", 1, hours(8.6))["ok"], "no second payment the same day")
	check(emp.tick(1, hours(12), "").empty() and emp.getShiftStatus(1) == "completed" and emp.getWarnings() == 0, "a completed shift is never missed")

	# ---- One paid shift a day across all jobs ----
	check(emp.leave(1) and emp.accept("workshop", 1, hours(10.5))["ok"] and emp.getJobID() == "workshop", "switch jobs the same day")
	check(emp.getShiftStatus(1) == "completed" and !emp.canStartShift("workshop", 1, hours(10.5))["ok"] and emp.completeShift("workshop", 1, hours(10.5)) == 0, "switching jobs gives no second paid shift")
	check(emp.tick(1, hours(13), "").empty() and emp.getWarnings() == 0, "and no penalty")
	events = emp.tick(2, hours(6), "")
	check(events.empty() and emp.getShiftStatus(2) == "not started" and emp.hasOpenShift(2), "the next day brings a new shift")
	check(emp.completeShift("workshop", 2, hours(10)) == 4 and emp.getHistory()["wages"] == 7, "the new job pays its own wage on the new day")

	# ---- Missed shifts, warnings and dismissal ----
	m = make()
	s = m[0]
	emp = m[1]
	var _r = emp.accept("laundry", 5, hours(7))
	events = emp.tick(5, hours(12), "")
	check(events.size() == 1 and events[0]["type"] == "reminder", "laundry reminder at 12:00")
	events = emp.tick(5, hours(14), "")
	check(events.size() == 1 and events[0]["type"] == "missed" and events[0]["warnings"] == 1 and emp.getWarnings() == 1 and emp.getShiftStatus(5) == "missed" and emp.getHistory()["missed"] == 1 and emp.isEmployed(), "an unexcused miss adds a warning")
	check(emp.tick(5, hours(15), "").empty() and emp.getWarnings() == 1, "it is only counted once")
	check(!emp.canStartShift("laundry", 5, hours(13))["ok"], "no shift after a miss")
	events = emp.tick(6, hours(14.5), "")
	check(emp.getWarnings() == 2 and events.size() == 1 and events[0]["type"] == "missed" and events[0]["warnings"] == 2, "a shift missed entirely is found overdue later: warning two")
	check(false == emp.isDismissed(6) and emp.isEmployed(), "two warnings keep the job")
	# a completed shift clears one
	events = emp.tick(7, hours(6), "")
	check(emp.getWarnings() == 2 and events.empty(), "a new day, a fresh shift")
	check(emp.completeShift("laundry", 7, hours(13)) == 2 and emp.getWarnings() == 1, "a completed shift clears one warning")
	events = emp.tick(8, hours(14), "")
	check(emp.getWarnings() == 2 and emp.isEmployed(), "back to two")
	events = emp.tick(9, hours(15), "")
	check(emp.getWarnings() == 0 and !emp.isEmployed() and emp.isDismissed(9) and emp.getReapplyDay() == 12 and emp.getHistory()["dismissals"] == 1, "three warnings dismiss and start the wait")
	check(events.size() == 2 and events[0]["type"] == "missed" and events[0]["warnings"] == 3 and events[1]["type"] == "dismissed" and events[1]["reapplyDay"] == 12, "the miss and the dismissal are reported")
	check(emp.getHistory()["completed"] == 1 and emp.getHistory()["missed"] == 4, "the history is kept")
	check(!emp.canApply("mining", 9)["ok"] and !emp.canApply("mining", 11)["ok"] and !emp.accept("mining", 11, hours(7))["ok"] and !emp.isEmployed(), "no job until the wait is over")
	check(emp.canApply("mining", 12)["ok"], "applying is open again on day 12")
	events = emp.tick(12, hours(6), "")
	check(events.size() == 1 and events[0]["type"] == "reapply" and !emp.isDismissed(12) and emp.getReapplyDay() == -1, "told when you can reapply")
	check(emp.tick(12, hours(7), "").empty(), "told once")
	check(emp.accept("mining", 12, hours(7))["ok"] and emp.isEmployed() and emp.getWarnings() == 0, "rehired with no warnings")

	# ---- Excused absences ----
	m = make()
	s = m[0]
	emp = m[1]
	_r = emp.accept("mining", 20, hours(7))
	events = emp.tick(20, hours(10), "locked in the stocks")
	check(events.size() == 1 and events[0]["type"] == "excused" and events[0]["reason"] == "locked in the stocks" and emp.getWarnings() == 0 and emp.getShiftStatus(20) == "excused" and emp.getHistory()["excused"] == 1 and emp.getHistory()["wages"] == 0 and emp.getHistory()["missed"] == 0, "a blocked player is excused: no wage, no warning")
	check(emp.tick(20, hours(11), "").empty() and !emp.canStartShift("mining", 20, hours(9))["ok"] and emp.completeShift("mining", 20, hours(9)) == 0, "an excused shift is over for the day")
	events = emp.tick(21, hours(6), "")
	check(events.empty() and emp.hasOpenShift(21), "the next day is a fresh shift")
	events = emp.tick(21, hours(10), "held by a guard")
	check(events.size() == 1 and events[0]["type"] == "excused" and emp.getWarnings() == 0, "and being blocked excuses that one too")
	m = make()
	s = m[0]
	emp = m[1]
	_r = emp.accept("mining", 30, hours(7))
	check(emp.recordExcused(30) and emp.getShiftStatus(30) == "excused" and emp.getHistory()["excused"] == 1 and !emp.recordExcused(30), "an external excused absence counts once")
	check(emp.getWarnings() == 0 and emp.tick(30, hours(11), "").empty(), "and has no warning")
	m = make()
	emp = m[1]
	check(!emp.recordExcused(30), "nothing to excuse without a job")
	_r = emp.accept("mining", 31, hours(11))
	check(!emp.hasOpenShift(31) and !emp.recordExcused(31) and emp.tick(31, hours(13), "").empty() and emp.getWarnings() == 0, "a job taken after the window has no shift today and no penalty")
	events = emp.tick(32, hours(6), "")
	check(emp.hasOpenShift(32) and events.empty(), "the first shift is the next day")
	# the shift found overdue on a new day with a blocker is excused too
	m = make()
	emp = m[1]
	_r = emp.accept("mining", 40, hours(7))
	events = emp.tick(41, hours(6), "serving as a slave")
	check(events.size() == 1 and events[0]["type"] == "excused" and emp.getWarnings() == 0, "an overdue shift found while blocked is excused")

	# ---- Pay timing and the clock cannot eat a started shift ----
	m = make()
	emp = m[1]
	_r = emp.accept("mining", 50, hours(7))
	wage = emp.completeShift("mining", 50, hours(9.99))
	events = emp.tick(50, hours(12), "")
	check(wage == 3 and events.empty() and emp.getHistory()["missed"] == 0, "a shift started at the end of the window and finished after it is not missed")

	# ---- Informal mining ----
	m = make()
	emp = m[1]
	check(emp.claimInformalMiningPay(1) and !emp.claimInformalMiningPay(1) and !emp.claimInformalMiningPay(1) and emp.claimInformalMiningPay(2), "informal mining pays once a day")
	_r = emp.accept("mining", 2, hours(7))
	check(emp.completeShift("mining", 2, hours(8)) == 3 and !emp.claimInformalMiningPay(2), "informal pay does not use up the shift, and the shift does not reopen informal pay")

	# ---- Text ----
	m = make()
	s = m[0]
	emp = m[1]
	check(emp.getStatusText(1, hours(9)).find("board") != -1, "unemployed status points at the job board")
	_r = emp.accept("mining", 1, hours(7))
	check(emp.getStatusText(1, hours(7)).find("Mine worker") != -1 and emp.getStatusText(1, hours(9)).find("ready to start") != -1, "employed status shows the job and the ready shift")
	var _w = emp.completeShift("mining", 1, hours(9))
	check(emp.getStatusText(1, hours(9)).find("completed") != -1, "status shows completion")
	var texts = {}
	for type in ["reminder", "missed", "excused", "dismissed", "reapply"]:
		texts[EmploymentScript.eventText({"type": type, "job": "mining", "warnings": 2, "reason": "x", "reapplyDay": 9})] = type
	check(texts.size() == 5, "completed, missed, excused, dismissed and reapply messages are all different")
	check(EmploymentScript.eventText({"type": "missed", "job": "mining", "warnings": 2}).find("2 of 3") != -1 and EmploymentScript.eventText({"type": "dismissed", "job": "mining", "reapplyDay": 9}).find("day 9") != -1, "messages carry the warning count and the reapply day")

	# ---- Sanitising ----
	check(JSON.print(EmploymentScript.sanitize(null)) == JSON.print(EmploymentScript.defaults()) and JSON.print(EmploymentScript.sanitize("x")) == JSON.print(EmploymentScript.defaults()) and JSON.print(EmploymentScript.sanitize({})) == JSON.print(EmploymentScript.defaults()), "garbage becomes the defaults")
	var dirty = {"job": "pirate", "shift": {"day": "x", "job": "mining", "state": "weird", "eligible": "yes", "reminded": 1}, "warnings": 9, "dismissed_until": "later", "last_mining_pay_day": -50, "history": {"completed": -4, "missed": "x", "excused": 2.6, "dismissals": null, "wages": 7, "last_job": "pirate"}}
	var clean = EmploymentScript.sanitize(dirty)
	check(clean["job"] == "" and JSON.print(clean["shift"]) == JSON.print(EmploymentScript.defaultShift()) and clean["warnings"] == 2 and clean["dismissed_until"] == -1 and clean["last_mining_pay_day"] == -1, "bad fields are repaired")
	check(clean["history"]["completed"] == 0 and clean["history"]["missed"] == 0 and clean["history"]["excused"] == 3 and clean["history"]["wages"] == 7 and clean["history"]["last_job"] == "", "history counts are clamped and cleaned")
	var good = {"job": "laundry", "shift": {"day": 4, "job": "laundry", "state": "missed", "eligible": true, "reminded": true}, "warnings": 1, "dismissed_until": -1, "last_mining_pay_day": 3, "history": {"completed": 5, "missed": 2, "excused": 1, "dismissals": 1, "wages": 31, "last_job": "mining"}}
	clean = EmploymentScript.sanitize(good)
	check(JSON.print(clean) == JSON.print(good), "a valid record survives unchanged")
	clean["history"]["completed"] = 99
	clean["shift"]["day"] = 99
	check(good["history"]["completed"] == 5 and good["shift"]["day"] == 4, "sanitising never aliases the input")
	check(EmploymentScript.sanitize({"job": "mining", "dismissed_until": 8})["job"] == "", "a dismissal pending means no job")

	# ---- Upgrades ----
	m = make()
	s = m[0]
	var up = m[2]
	check(!up.owns("storage") and !up.owns("hidden") and !up.owns("comfort") and !up.owns("zzz") and !up.owns(null) and JSON.print(up.getOwned()) == JSON.print(UpgradesScript.defaults()), "nothing owned at the start")
	var prices = [UpgradesScript.price("storage"), UpgradesScript.price("hidden"), UpgradesScript.price("comfort")]
	check(prices == [9, 12, 12], "prices: " + str(prices))
	check(UpgradesScript.price("storage") >= 2 * 3 and UpgradesScript.price("storage") <= 4 * 3 and UpgradesScript.price("hidden") >= 3 * 3 and UpgradesScript.price("hidden") <= 5 * 3 and UpgradesScript.price("comfort") >= 3 * 3 and UpgradesScript.price("comfort") <= 5 * 3, "prices are 2-4, 3-5 and 3-5 shifts of a 3 credit wage")
	check(UpgradesScript.STASH_BASE_SLOTS == 4 and UpgradesScript.UPGRADES["storage"]["slots"] == 12 and UpgradesScript.HIDDEN_SLOTS == 3, "capacities: stash 4, locker 12, hidden 3")
	check(!up.canBuy("storage", 8)["ok"] and up.canBuy("storage", 9)["ok"] and !up.canBuy("zzz", 99)["ok"] and !up.canBuy(null, 99)["ok"], "credits decide whether it can be bought")
	check(!up.owns("storage") and up.markOwned("storage") and up.owns("storage") and !up.markOwned("storage") and !up.canBuy("storage", 99)["ok"], "owned once, never bought twice")
	check(!up.markOwned("zzz") and !up.owns("zzz"), "unknown upgrades are refused")
	check(up.canStore(record("a", "u1")) == "You do not have this upgrade." and up.store(record("a", "u1")) != "" and up.getRecords().empty(), "no hidden compartment, no hidden storage")
	check(up.restBonus(40.0) == 0, "no comfort, no bonus")
	_r = up.markOwned("comfort")
	check(up.restBonus(40.0) == 20 and up.restBonus(25.0) == 12 and up.restBonus(0.0) == 0 and up.restBonus(-5.0) == 0, "comfort gives half again, rounded down")

	# ---- The cell stash capacity rule (the stash itself is the vanilla one) ----
	m = make()
	s = m[0]
	up = m[2]
	check(up.getStashCapacity() == 4, "the free stash holds 4 stacks")
	check(up.stashRefusal(0, true) == "" and up.stashRefusal(3, true) == "" and up.stashRefusal(4, true).find("full") != -1 and up.stashRefusal(4, true).find("locker") != -1, "the fifth new stack is refused, with the locker as the way out")
	check(up.stashRefusal(4, false) == "" and up.stashRefusal(9, false) == "", "a stack that merges into an existing one needs no room")
	var over = up.stashRefusal(6, true)
	check(over.find("more than it fits") != -1 and over.find("6 of 4") != -1 and over.find("Take something out") != -1, "over capacity says so: " + over)
	check(up.stashStatusText(2).find("2 of 4") != -1 and up.stashStatusText(2).find("12") != -1 and up.stashStatusText(6).find("over capacity") != -1 and up.stashStatusText(6).find("take things out") != -1, "the status text shows the use, the locker and the over-capacity case")
	_r = up.markOwned("storage")
	check(up.getStashCapacity() == 12 and up.stashRefusal(4, true) == "" and up.stashRefusal(11, true) == "" and up.stashRefusal(12, true).find("full") != -1, "the locker raises the same capacity to 12")
	check(up.stashRefusal(14, true).find("more than it fits") != -1 and up.stashRefusal(14, true).find("locker") == -1 and up.stashStatusText(5).find("locker raises") == -1, "still over capacity with the locker: refused, no locker advice")
	check(UpgradesScript.UPGRADES["storage"]["text"].find("12") != -1 and UpgradesScript.UPGRADES["storage"]["text"].find("instead of 4") != -1 and UpgradesScript.UPGRADES["storage"]["text"].find("does not hide") != -1, "the description states the increase and that it is not secure")

	# ---- Hidden compartment records ----
	m = make()
	s = m[0]
	up = m[2]
	_r = up.markOwned("hidden")
	var rec = record("Flashlight", "item1", 3)
	check(up.store(rec) == "" and up.getRecords().size() == 1 and up.getFreeSlots() == 2, "store an item")
	check(JSON.print(up.getRecords()[0]) == JSON.print(rec), "all of the item's data is kept")
	rec["data"]["note"]["deep"].append(9)
	check(up.getRecords()[0]["data"]["note"]["deep"].size() == 2, "the stored copy is not aliased")
	var copy = up.getRecords()
	copy[0]["data"]["amount"] = 77
	check(up.getRecords()[0]["data"]["amount"] == 3, "records handed out are copies")
	check(up.store(record("Flashlight", "item1")) == "That item is already in there." and up.getRecords().size() == 1, "the same item cannot go in twice")
	check(up.store({"id": "", "uniqueID": "x", "data": {}}) != "" and up.store(null) != "" and up.store({"id": "a", "uniqueID": 5, "data": {}}) != "" and up.store({"id": "a", "uniqueID": "x", "data": []}) != "", "malformed records are refused")
	check(up.store(record("Thing", "t1")) == "" and up.store(record("Thing", "t2")) == "" and up.getFreeSlots() == 0 and up.store(record("Thing", "t3")) == "It is full." and up.getRecords().size() == 3, "the hidden compartment holds three")
	check(up.take("nope").empty() and up.getRecords().size() == 3, "taking something that is not there changes nothing")
	var taken = up.take("item1")
	check(taken["id"] == "Flashlight" and taken["data"]["amount"] == 3 and up.getRecords().size() == 2 and !up.hasRecord("item1") and up.getFreeSlots() == 1, "take it back with its data")
	check(s.upgrades["hidden"] and !s.upgrades["storage"], "the hidden compartment and the locker are separate purchases")

	# ---- State: schema 4, save and load ----
	check(s.schema_version == 5 and StateScript.CURRENT_SCHEMA_VERSION == 5, "schema 5")
	var saved = JSON.parse(JSON.print(s.saveData())).result
	var t = StateScript.new()
	t.loadData(saved)
	check(JSON.print(t.upgrades) == JSON.print(s.upgrades) and JSON.print(t.hidden_storage) == JSON.print(s.hidden_storage) and t.hidden_storage.size() == 2, "upgrades and the hidden compartment survive a JSON round trip")
	check(t.hidden_storage[0]["data"]["amount"] == 1 or t.hidden_storage[0]["data"]["amount"] == 1.0, "item data survives")
	check(!s.saveData().has("storage") and !("storage" in s), "the ordinary stash is not duplicated into the sandbox state")
	m = make()
	s = m[0]
	emp = m[1]
	_r = emp.accept("mining", 3, hours(7))
	_w = emp.completeShift("mining", 3, hours(8))
	var _x = emp.claimInformalMiningPay(3)
	_r = emp.tick(4, hours(11), "")
	saved = JSON.parse(JSON.print(s.saveData())).result
	t = StateScript.new()
	t.loadData(saved)
	check(JSON.print(t.work) == JSON.print(s.work) and t.work["job"] == "mining" and t.work["history"]["completed"] == 1 and t.work["history"]["wages"] == 3, "employment survives a JSON round trip")
	check(typeof(t.work["warnings"]) == TYPE_INT and typeof(t.work["shift"]["day"]) == TYPE_INT and typeof(t.work["history"]["wages"]) == TYPE_INT, "counts load back as integers")
	var saved2 = s.saveData()
	saved2["work"]["history"]["wages"] = 999
	check(s.work["history"]["wages"] == 3, "saveData does not alias the live state")
	t.work["history"]["wages"] = 1234
	var again = StateScript.new()
	again.loadData(saved)
	check(again.work["history"]["wages"] == 3, "loading does not alias the saved data")

	# Older saves: unemployed, nothing bought, nothing stored
	var oldState = StateScript.new()
	oldState.loadData({"schema_version": 3, "work": {"job": "mining"}, "upgrades": {"storage": true}, "hidden_storage": [record("a", "y")], "reputation": {"combat": 5.0, "defiance": 0.0}})
	check(oldState.schema_version == 5 and oldState.work["job"] == "" and !oldState.upgrades["storage"] and oldState.hidden_storage.empty(), "a version 3 save is unemployed with no upgrades, even if it has stray fields")
	oldState.loadData({"schema_version": 1})
	check(oldState.schema_version == 5 and JSON.print(oldState.work) == JSON.print(EmploymentScript.defaults()) and !oldState.upgrades["comfort"], "a version 1 save migrates")
	oldState.loadData({"schema_version": 99, "work": {"job": "mining"}})
	check(oldState.schema_version == 99, "a newer save keeps its version")
	oldState.loadData({"schema_version": 4, "work": "junk", "upgrades": [1], "hidden_storage": {"a": 1}})
	check(JSON.print(oldState.work) == JSON.print(EmploymentScript.defaults()) and JSON.print(oldState.upgrades) == JSON.print(UpgradesScript.defaults()) and oldState.hidden_storage.empty(), "malformed current fields load clean")
	var bad = [record("ok", "k1"), {"id": "x"}, record("ok", "k1"), 5, record("ok2", "k2")]
	var sanitized = UpgradesScript.sanitizeRecords(bad, 8)
	check(sanitized.size() == 2 and sanitized[0]["uniqueID"] == "k1" and sanitized[1]["uniqueID"] == "k2", "bad and duplicate records are dropped")
	var many = []
	for i in range(12):
		many.append(record("a", "m" + str(i)))
	check(UpgradesScript.sanitizeRecords(many, 8).size() == 8 and UpgradesScript.sanitizeRecords(many, 3).size() == 3 and UpgradesScript.sanitizeRecords(null, 3).empty(), "stored items never exceed the capacity")
	check(JSON.print(UpgradesScript.sanitizeUpgrades({"storage": true, "hidden": "yes", "comfort": 1, "extra": true})) == JSON.print({"storage": true, "hidden": false, "comfort": false}), "only real booleans for known upgrades count")
	s.clear()
	check(s.work["job"] == "" and s.upgrades["storage"] == false and s.hidden_storage.empty() and s.work["history"]["wages"] == 0, "clear resets everything (new game)")

	print("WorkTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

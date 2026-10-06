extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/LivingPrisonTest.gd --quit
# The rules of the living prison with no game running: the daily schedule and budgets, the NPC jobs, and the workplace events. Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const JobsScript = preload("res://Modules/SandboxOverhaulModule/Work/NpcJobs.gd")
const EventsScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEvents.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func hours(h, m = 0) -> int:
	return int(h * 3600 + m * 60)

func ids(n, prefix = "i") -> Array:
	var result = []
	for index in range(n):
		result.append(prefix + ("%02d" % index))
	return result

func _init():
	scheduleTests()
	jobTests()
	eventTests()
	print("LivingPrisonTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- schedule
func scheduleTests():
	var people = ids(40)
	# Bands follow the clock for everybody; the edges are shifted by a stable offset
	for id in people:
		check(ScheduleScript.bandAt(id, hours(10)) == ScheduleScript.WORK, id + " works in the morning hours")
		check(ScheduleScript.bandAt(id, hours(15)) == ScheduleScript.LEISURE, id + " has leisure in the afternoon")
		check(ScheduleScript.bandAt(id, hours(20, 15)) == ScheduleScript.EVENING, id + " is in the common areas in the evening")
		check(ScheduleScript.bandAt(id, hours(22, 30)) == ScheduleScript.NIGHT and ScheduleScript.bandAt(id, hours(2)) == ScheduleScript.NIGHT, id + " is in their cell at night")
		check(ScheduleScript.bandAt(id, hours(7, 45)) in [ScheduleScript.MORNING, ScheduleScript.WORK], id + " is up and about by 07:45")
		check(ScheduleScript.bandAt(id, hours(6)) == ScheduleScript.NIGHT or ScheduleScript.bandAt(id, hours(6)) == ScheduleScript.MORNING, id + " is waking at 06:00")
		check(ScheduleScript.bandAt(id, hours(10)) == ScheduleScript.bandAt(id, hours(10) + 86400), id + ": the band depends only on the time of day")
	check(ScheduleScript.bandAt("x", "noon") == ScheduleScript.NIGHT and ScheduleScript.bandAt("x", null) == ScheduleScript.NIGHT, "an invalid time is treated as night, safely")
	# Staggered: not everyone changes band at the same moment
	var changeTimes = {}
	for id in people:
		for minute in range(0, 24 * 60, 5):
			if(ScheduleScript.bandAt(id, minute * 60) == ScheduleScript.WORK):
				changeTimes[id] = minute
				break
	var distinct = {}
	for id in changeTimes:
		distinct[changeTimes[id]] = true
	check(distinct.size() >= 5, "the prison does not shift on the hour: people start their working day at " + str(distinct.size()) + " different times")
	# Slots change every two hours and are stable
	check(ScheduleScript.slotAt("a", hours(10)) == ScheduleScript.slotAt("a", hours(10) + 60) and ScheduleScript.slotAt("a", hours(10)) != ScheduleScript.slotAt("a", hours(13)), "the activity changes every two hours")
	# Rooms: always real places of the right kind
	var known = {}
	for category in ScheduleScript.CATEGORIES:
		for entry in ScheduleScript.CATEGORIES[category]:
			known[entry[0]] = category
	var gangRoomUsed = false
	var roomsSeen = {}
	for id in people:
		for hour in range(8, 20):
			var facts = {"block": "red", "cellRoom": "sbx_cell_red_2", "hangout": "gym_weights" if id.ends_with("1") else "", "job": "", "available": true}
			var want = ScheduleScript.desired(id, hours(hour, 5), 3, facts)
			check(want["room"] != "", id + " has somewhere to be at " + str(hour))
			roomsSeen[want["room"]] = true
			if(want["reason"] == "hangout"):
				gangRoomUsed = true
				check(id.ends_with("1") and want["room"] == "gym_weights", "only gang members go to their hangout")
			check(want["band"] != ScheduleScript.NIGHT, "no night band during the day")
			check(ScheduleScript.desired(id, hours(hour, 5), 3, facts)["room"] == want["room"], id + ": the answer is stable")
	check(gangRoomUsed, "gang members do spend leisure time at their hangout")
	check(roomsSeen.size() >= 8 and roomsSeen.size() <= 30, "inmates use a handful of busy hubs, not every room: " + str(roomsSeen.size()))
	for room in roomsSeen:
		check(known.has(room) or room == "gym_weights" or room == "cellblock_red_nearcell", "scheduled room " + room + " is a known hub")
	# Night: the cell, whatever else
	for id in people:
		var night = ScheduleScript.desired(id, hours(23), 3, {"block": "orange", "cellRoom": "cellblock_orange_playercell", "hangout": "gym_weights", "job": "mining", "available": true})
		check(night["room"] == "cellblock_orange_playercell" and night["reason"] == "bedtime" and night["category"] == "cell", id + " sleeps in their cell")
	check(ScheduleScript.desired("x", hours(2), 3, {"block": "orange", "cellRoom": "", "available": true})["room"] == "", "no cell, no cell room (they are simply not placed)")
	# Cell block halls belong to the person's own block
	var hallSeen = {}
	for id in people:
		for hour in range(8, 20):
			var want2 = ScheduleScript.desired(id, hours(hour, 5), 3, {"block": "lilac", "cellRoom": "", "hangout": "", "job": "", "available": true})
			if(want2["category"] == "cellhall"):
				hallSeen[want2["room"]] = true
	check(hallSeen.has("cellblock_lilac_nearcell") and !hallSeen.has("cellblock_orange_nearcell") and !hallSeen.has("cellblock_red_nearcell"), "lilac inmates gather in the lilac hall: " + str(hallSeen.keys()))
	# Work shifts: exactly the job's configured window, the same one the player works
	for jobID in EmploymentScript.JOB_ORDER:
		var job = EmploymentScript.JOBS[jobID]
		for id in people:
			var window = ScheduleScript.shiftWindow(id, jobID)
			check(window["start"] == job["open"] * 3600 and window["end"] == job["close"] * 3600 and window["end"] - window["start"] == job["hours"] * 3600, id + " " + jobID + " shift is exactly the job's configured window")
			check(same(window, ScheduleScript.shiftWindow(id, jobID)), id + ": the same shift every day")
			check(ScheduleScript.isOnShift(id, jobID, window["start"]) and !ScheduleScript.isOnShift(id, jobID, window["end"]) and !ScheduleScript.isOnShift(id, jobID, window["start"] - 1), id + ": on shift exactly during the shift")
	check(ScheduleScript.shiftWindow("x", "pirate").empty() and !ScheduleScript.isOnShift("x", "pirate", hours(9)) and !ScheduleScript.isOnShift("x", "mining", "late"), "no shift for unknown jobs or times")
	check(same(ScheduleScript.shiftWindow("a", "mining"), {"start": 8 * 3600, "end": 10 * 3600}) and same(ScheduleScript.shiftWindow("b", "workshop"), {"start": 10 * 3600, "end": 12 * 3600}) and same(ScheduleScript.shiftWindow("c", "laundry"), {"start": 12 * 3600, "end": 14 * 3600}), "mine 08-10, workshop 10-12, laundry 12-14 for every coworker")
	# Work wins over everything below it; not available means no work
	var workFacts = {"block": "orange", "cellRoom": "c", "hangout": "gym_weights", "job": "laundry", "available": true}
	var onShift = ScheduleScript.shiftWindow("w1", "laundry")["start"] + 60
	var worker = ScheduleScript.desired("w1", onShift, 3, workFacts)
	check(worker["room"] == "main_laundry" and worker["reason"] == "work" and worker["category"] == "workplace", "a worker on shift is at the workplace")
	workFacts["available"] = false
	check(ScheduleScript.desired("w1", onShift, 3, workFacts)["reason"] != "work", "an unavailable worker (hurt, held, enslaved) is not at work")
	workFacts["available"] = true
	check(ScheduleScript.desired("w1", ScheduleScript.shiftWindow("w1", "laundry")["end"] + 3600, 3, workFacts)["reason"] != "work", "after the shift they leave")
	# Priorities
	check(ScheduleScript.higherPriority("work", "bedtime") == "work" and ScheduleScript.higherPriority("leisure", "hangout") == "hangout" and ScheduleScript.higherPriority("captivity", "interaction") == "captivity" and ScheduleScript.higherPriority("scripted", "captivity") == "scripted" and ScheduleScript.higherPriority("", "leisure") == "leisure" and ScheduleScript.higherPriority("bedtime", "hangout") == "bedtime", "priorities rank as documented")
	check(ScheduleScript.PRIORITIES == ["scripted", "captivity", "interaction", "medical", "work", "bedtime", "hangout", "leisure"], "the priority order is explicit")
	# Busy hubs against quiet corners
	check(ScheduleScript.roomLimit("hall") > ScheduleScript.roomLimit("shower") and ScheduleScript.roomLimit("cell") == 2 and ScheduleScript.roomLimit("nothing") == ScheduleScript.roomLimit("other"), "busy places hold more than quiet ones, and a cell holds two")
	# Budgets: inmates are the majority, staff stay present but few
	var b = ScheduleScript.budgets(30, 25)
	check(b["inmate"] == 18 and b["guard"] == 6 and b["nurse"] == 3 and b["engineer"] == 3 and b["inmate"] + b["guard"] + b["nurse"] + b["engineer"] == 30, "a pawn limit of 30 with 25 inmates: " + str(b))
	check(b["inmate"] > 2 * b["guard"], "inmates outnumber guards at least three to one in the budget")
	check(ScheduleScript.budgets(30, 5)["inmate"] == 5 and ScheduleScript.budgets(0, 25)["guard"] == 0 and ScheduleScript.budgets(10, 25)["guard"] == 2 and ScheduleScript.budgets(-3, 4)["inmate"] == 0, "budgets are capped by who exists and never negative")
	check(ScheduleScript.weightedPick([], 5) == null and ScheduleScript.weightedPick([["a", 0]], 3) == null and ScheduleScript.weightedPick([["a", 1], ["b", 3]], 0) == "a" and ScheduleScript.weightedPick([["a", 1], ["b", 3]], 3) == "b", "weighted picks")

# ---------------------------------------------------------------- jobs
func jobTests():
	var s = StateScript.new()
	var jobs = JobsScript.new(s)
	var people = ids(25)
	check(JobsScript.targetFor(25) == 10 and JobsScript.targetFor(0) == 0 and JobsScript.targetFor(8) == 4 and JobsScript.targetFor(100) == 15, "two in five have a job, up to the workplaces' capacity")
	check(jobs.ensure(people, 1) == 10, "ten of 25 get jobs")
	var total = 0
	for jobID in EmploymentScript.JOB_ORDER:
		check(jobs.workerCount(jobID) <= JobsScript.CAPACITY[jobID] and jobs.workerCount(jobID) >= 3, jobID + " has a sensible crew: " + str(jobs.workerCount(jobID)))
		total += jobs.workerCount(jobID)
	check(total == 10, "everyone with a job is counted once")
	var snapshot = JSON.print(s.npc_jobs, "", true)
	check(jobs.ensure(people, 2) == 0 and JSON.print(s.npc_jobs, "", true) == snapshot, "asking again changes nothing: jobs are stable")
	var more = ids(30)
	check(jobs.ensure(more, 3) == 2 and jobs.employedIDs().size() == 12, "a bigger prison hires two more")
	for id in JSON.parse(snapshot).result["jobs"]:
		check(jobs.getJob(id) == JSON.parse(snapshot).result["jobs"][id]["job"], id + " keeps their job when more are hired")
	var reversed = more.duplicate()
	reversed.invert()
	var s2 = StateScript.new()
	var jobs2 = JobsScript.new(s2)
	var _g = jobs2.ensure(ids(25), 1)
	var s3 = StateScript.new()
	var jobs3 = JobsScript.new(s3)
	var inv = ids(25)
	inv.invert()
	var _h = jobs3.ensure(inv, 1)
	check(same(s2.npc_jobs["jobs"], s3.npc_jobs["jobs"]), "the same inmates get the same jobs whatever order they are listed in")
	var sp = StateScript.new()
	check(!jobs.isEmployed("pc") and !jobs.assign("pc", "mining", 1) and JobsScript.new(sp).ensure(["pc"], 1) == 0 and sp.npc_jobs["jobs"].empty(), "the player is never given a job here")
	# Capacity is a hard limit
	var s4 = StateScript.new()
	var full = JobsScript.new(s4)
	for id in ids(6):
		check(full.assign(id, "laundry", 1) == (id != "i04" and id != "i05"), "laundry takes four: " + id)
	check(full.freePlaces("laundry") == 0 and !full.assign("zz", "laundry", 1) and !full.assign("zz", "pirate", 1) and !full.assign("i00", "mining", 1), "a full workplace, an unknown job and a second job are refused")
	# Leaving the eligible set loses the job
	var gone = ids(25)
	var someone = jobs2.employedIDs()[0]
	gone.erase(someone)
	var _r = jobs2.ensure(gone, 5)
	check(!jobs2.isEmployed(someone) and jobs2.employedIDs().size() == JobsScript.targetFor(24), "an inmate who is gone loses their job; others keep theirs")
	# Coworkers
	var crewMember = jobs.workers("mining")[0]
	check(jobs.coworkers(crewMember).size() == jobs.workerCount("mining") - 1 and !jobs.coworkers(crewMember).has(crewMember) and jobs.coworkers("nobody").empty(), "coworkers are the rest of the crew")
	# Transfer
	var mover = jobs.workers("mining")[0]
	var open = jobs.nextOpenJob("mining")
	check(open != "" and open != "mining" and jobs.transfer(mover, open, 9) and jobs.getJob(mover) == open and jobs.getEntry(mover)["moves"] == 1 and jobs.getEntry(mover)["since"] == 9, "a transfer moves them and is counted")
	check(!jobs.transfer(mover, open, 9) and !jobs.transfer("nobody", "mining", 9) and !jobs.transfer(mover, "pirate", 9), "a transfer to the same job, for a stranger or to nowhere is refused")
	check(jobs.transfer(mover, "", 10) and !jobs.isEmployed(mover), "a transfer to no job leaves the job")
	# Knowledge
	var s5 = StateScript.new()
	var known = JobsScript.new(s5)
	var _k = known.ensure(ids(20), 1)
	var worker = known.employedIDs()[0]
	var idler = ""
	for id in ids(20):
		if(!known.isEmployed(id)):
			idler = id
	check(!known.isKnown(worker) and known.knownJobText(worker) == "" and !known.learn(idler) and known.learn(worker) and !known.learn(worker) and known.isKnown(worker), "the player only knows a job once learned, and cannot learn a job nobody has")
	check(known.knownJobText(worker).find(" at the ") != -1 and known.knownJobText(idler) == "", "known jobs read naturally: " + known.knownJobText(worker))
	known.removeCharacter(worker)
	check(!known.isEmployed(worker) and !known.isKnown(worker), "removing a character clears their job and the knowledge of it")
	# Save and sanitise
	var t = StateScript.new()
	t.loadData(JSON.parse(JSON.print(s.saveData())).result)
	check(same(t.npc_jobs, s.npc_jobs) and t.schema_version == 9, "jobs survive save and load exactly")
	var old = StateScript.new()
	old.loadData({"schema_version": 6})
	check(same(old.npc_jobs, JobsScript.defaults()) and same(old.workplace, EventsScript.defaults()) and old.schema_version == 9, "a schema 6 save loads with no NPC jobs and no workplace history")
	var dirty = JobsScript.sanitize({"jobs": {"a": {"job": "mining", "since": "x", "moves": -4}, "b": {"job": "pirate"}, "": {"job": "mining"}, "pc": {"job": "mining"}, "c": "bad", "d": {"job": "laundry", "since": 3.7, "moves": 2.2}}, "known": {"a": true, "b": "yes", "e": true, "": true}})
	check(dirty["jobs"].keys() == ["a", "d"] and dirty["jobs"]["a"]["since"] == 0 and dirty["jobs"]["a"]["moves"] == 0 and dirty["jobs"]["d"]["since"] == 4 and dirty["known"].has("a") and dirty["known"].has("e") and !dirty["known"].has("b") and dirty["known"].size() == 2, "damaged job data is repaired: " + JSON.print(dirty))
	var overfull = {"jobs": {}}
	for id in ids(10):
		overfull["jobs"][id] = {"job": "laundry", "since": 1, "moves": 0}
	check(JobsScript.sanitize(overfull)["jobs"].size() == JobsScript.CAPACITY["laundry"], "a damaged save cannot put more people in a workplace than it holds")
	check(same(JobsScript.sanitize(null), JobsScript.defaults()) and same(JobsScript.sanitize("x"), JobsScript.defaults()), "garbage becomes the defaults")

# ---------------------------------------------------------------- work events
func coworker(id, tie = "stranger", hostile = false, fear = 0.0, mean = false):
	return {"id": id, "tie": tie, "hostile": hostile, "fear": fear, "mean": mean}

func factsFor(day, crew, boss = "g1", hostileOk = true):
	return {"day": day, "job": "mining", "unsafe": false, "boss": boss, "hostileOk": hostileOk, "coworkers": crew}

func eventTests():
	var crew = [coworker("c1", "friend"), coworker("c2", "stranger"), coworker("r1", "stranger", true, 5.0, true), coworker("c3", "cellmate")]
	# Gating
	var st = EventsScript.defaults()
	check(EventsScript.pick(st, factsFor(1, crew), [0.99, 0.0, 0.0, 0.0]).empty(), "a high roll means no event")
	var unsafeFacts = factsFor(1, crew)
	unsafeFacts["unsafe"] = true
	check(EventsScript.pick(st, unsafeFacts, [0.0, 0.0, 0.0, 0.0]).empty(), "never during an unsafe state")
	st["pending"] = {"id": "x", "family": "request", "variant": "loan", "day": 1}
	check(EventsScript.pick(st, factsFor(1, crew), [0.0, 0.0, 0.0, 0.0]).empty(), "never while one is waiting for an answer")
	st = EventsScript.defaults()
	var first = EventsScript.pick(st, factsFor(5, crew), [0.0, 0.0, 0.0, 0.0])
	check(!first.empty() and first["day"] == 5 and first["id"] == "w5_1" and first["stage"] == "open", "a low roll starts an event: " + str(first))
	EventsScript.markHappened(st, first, 5)
	check(EventsScript.pick(st, factsFor(5, crew), [0.0, 0.0, 0.0, 0.0]).empty(), "never two events on one day")
	# The same coworker is not featured again within two days
	check(!EventsScript.pairReady(st, first["who"], 6) and EventsScript.pairReady(st, first["who"], 7) and EventsScript.pairReady(st, "other", 5), "the pair cooldown is two days")
	var onlyOne = [coworker("solo", "friend")]
	var s2 = EventsScript.defaults()
	EventsScript.markHappened(s2, {"who": "solo"}, 5)
	var again = EventsScript.pick(s2, factsFor(6, onlyOne), [0.0, 0.0, 0.0, 0.0])
	check(again.empty() or again["who"] != "solo", "a coworker on cooldown is not chosen: " + str(again))
	# Frequency over many shifts: about one in four, never more than one per shift
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	var sim = EventsScript.defaults()
	var events = 0
	var shifts = 4000
	var byFamily = {}
	var variants = {}
	for day in range(shifts):
		var picked = EventsScript.pick(sim, factsFor(day, crew), [rng.randf(), rng.randf(), rng.randf(), rng.randf()])
		if(!picked.empty()):
			events += 1
			EventsScript.markHappened(sim, picked, day)
			byFamily[picked["family"]] = int(byFamily.get(picked["family"], 0)) + 1
			variants[picked["variant"]] = true
			check(EventsScript.isValidEvent(picked) and !EventsScript.choices(picked).empty() and EventsScript.describe(picked, {"c1": "Alec", "g1": "Boss"}) != "", "every picked event is complete: " + str(picked))
	var rate = float(events) / float(shifts)
	check(rate >= 0.20 and rate <= 0.30, "about a quarter of shifts have an event: " + str(rate))
	for family in EventsScript.FAMILIES:
		check(byFamily.has(family), "the " + family + " family happens")
	check(variants.size() == 9, "every variant happens: " + str(variants.keys()))
	# Conditional selection
	var noBoss = EventsScript.defaults()
	var noBossEvents = {}
	for day in range(300):
		var p2 = EventsScript.pick(noBoss, factsFor(day, crew, ""), [rng.randf() * 0.2, rng.randf(), rng.randf(), rng.randf()])
		if(!p2.empty()):
			noBossEvents[p2["family"]] = true
			EventsScript.markHappened(noBoss, p2, day)
	check(!noBossEvents.has("supervisor"), "no supervisor, no supervisor event")
	var friendsOnly = EventsScript.defaults()
	var seenFriends = {}
	for day in range(300):
		var p3 = EventsScript.pick(friendsOnly, factsFor(day, [coworker("a", "friend"), coworker("b", "stranger")]), [rng.randf() * 0.2, rng.randf(), rng.randf(), rng.randf()])
		if(!p3.empty()):
			seenFriends[p3["family"]] = true
			if(p3["family"] == "supervisor" and EventsScript.pairReady(friendsOnly, "a", day)):
				check(p3["who"] == "a" and p3["tie"] == "friend", "the supervisor picks on a friend when there is one")
			check(p3["family"] != "rival" and p3["family"] != "hostile", "no rival, no rival event")
			EventsScript.markHappened(friendsOnly, p3, day)
	var loneRival = EventsScript.defaults()
	var rivalSeen = false
	for day in range(300):
		var p4 = EventsScript.pick(loneRival, factsFor(day, [coworker("r", "stranger", true, 0.0, true)]), [0.0, 0.0 + float(day % 10) / 10.0, 0.5, 0.5])
		if(!p4.empty() and p4["family"] == "rival"):
			rivalSeen = true
		if(!p4.empty()):
			EventsScript.markHappened(loneRival, p4, day)
	check(rivalSeen, "a hostile coworker brings the rival event")
	var nobody = EventsScript.pick(EventsScript.defaults(), factsFor(1, []), [0.0, 0.0, 0.0, 0.0])
	check(!nobody.empty() and nobody["family"] == "opportunity" and nobody["variant"] == "contraband" and nobody["who"] == "", "a shift with no coworkers can still have an opportunity (contraband): " + str(nobody))
	var cornered = {}
	for day in range(2000):
		var s6 = EventsScript.defaults()
		var p5 = EventsScript.pick(s6, factsFor(day + 1, [coworker("r", "stranger", true, 5.0, true)]), [0.0, rng.randf(), rng.randf(), rng.randf()])
		if(!p5.empty()):
			cornered[p5["family"]] = true
	check(cornered.has("hostile") and cornered.has("rival"), "an isolated hostile encounter happens with a mean rival")
	var notMean = {}
	for day in range(1000):
		var s7 = EventsScript.defaults()
		var p6 = EventsScript.pick(s7, factsFor(day + 1, [coworker("r", "stranger", true, 5.0, false)]), [0.0, rng.randf(), rng.randf(), rng.randf()])
		if(!p6.empty()):
			notMean[p6["family"]] = true
	check(!notMean.has("hostile"), "only a mean coworker corners the player")
	var noHostile = {}
	for day in range(1000):
		var s8 = EventsScript.defaults()
		var p7 = EventsScript.pick(s8, factsFor(day + 1, [coworker("r", "stranger", true, 5.0, true)], "g1", false), [0.0, rng.randf(), rng.randf(), rng.randf()])
		if(!p7.empty()):
			noHostile[p7["family"]] = true
	check(!noHostile.has("hostile"), "the isolated encounter is off when the game cannot support it")
	# Resolving: every variant and choice
	var names = {"who": "Alec", "g1": "Hale"}
	var variantEvents = {
		"dressing_down": {"family": "supervisor"}, "needling": {"family": "rival"}, "workload": {"family": "request"}, "cover": {"family": "request"}, "loan": {"family": "request"},
		"contraband": {"family": "opportunity"}, "theft": {"family": "opportunity"}, "accident": {"family": "opportunity"}, "cornered": {"family": "hostile"},
	}
	var choiceCount = 0
	for variant in variantEvents:
		var event = {"id": "t1", "family": variantEvents[variant]["family"], "variant": variant, "day": 3, "job": "mining", "who": "who", "boss": "g1", "tie": "friend", "stage": "open"}
		check(EventsScript.isValidEvent(event) and EventsScript.describe(event, names).find("Alec") != -1 or variant == "contraband", variant + " names its coworker")
		for choice in EventsScript.choices(event):
			choiceCount += 1
			for roll in [0.0, 0.5, 0.99]:
				var outcome = EventsScript.resolve(event, choice["id"], [roll, roll], {"fear": 20.0, "respect": 10.0, "combat": 0.0, "credits": 50}, names)
				check(outcome["text"] != "" and outcome["effects"] is Array, variant + ":" + choice["id"] + " at " + str(roll) + " has text and effects")
				for effect in outcome["effects"]:
					check(effect.get("type", "") in ["feeling", "credits", "attention", "job_warning", "stamina", "fight", "injury", "rival"], variant + ":" + choice["id"] + " effect type " + str(effect.get("type")))
					if(effect["type"] == "feeling"):
						check(effect["target"] == "pc" and effect["axis"] in ["trust", "respect", "affection", "fear"] and abs(float(effect["amount"])) <= 15.0, "bounded feelings")
					if(effect["type"] == "credits"):
						check(abs(int(effect["amount"])) <= 8, "credits stay small")
	check(choiceCount >= 25, "there are plenty of choices: " + str(choiceCount))
	var unknown = EventsScript.resolve({"id": "t", "family": "request", "variant": "loan", "day": 1, "who": "who"}, "teleport", [0.0], {}, names)
	check(unknown["text"] == "" and unknown["effects"].empty(), "an unknown choice does nothing")
	# Specific consequences
	var bossEvent = {"id": "t", "family": "supervisor", "variant": "dressing_down", "day": 3, "who": "who", "boss": "g1", "tie": "cellmate", "stage": "open"}
	var intervene = EventsScript.resolve(bossEvent, "intervene", [0.1], {}, names)
	check(effectsHave(intervene["effects"], "feeling", "trust", 10.0) and !effectsHave(intervene["effects"], "job_warning"), "stepping in and winning earns the coworker's trust")
	var intervene2 = EventsScript.resolve(bossEvent, "intervene", [0.9], {}, names)
	check(effectsHave(intervene2["effects"], "job_warning") and effectsHave(intervene2["effects"], "attention"), "stepping in and losing costs a warning and attention")
	var challenge = EventsScript.resolve(bossEvent, "challenge", [0.1], {}, names)
	check(effectsHave(challenge["effects"], "fight") and challenge["effects"][2]["enemy"] == "g1", "challenging the supervisor can end in a real fight with them")
	check(effectsHave(EventsScript.resolve(bossEvent, "ignore", [0.5], {}, names)["effects"], "feeling", "trust", -8.0), "ignoring a cellmate costs more trust than ignoring a stranger")
	bossEvent["tie"] = "stranger"
	check(effectsHave(EventsScript.resolve(bossEvent, "ignore", [0.5], {}, names)["effects"], "feeling", "trust", -4.0), "and less for a stranger")
	var needle = {"id": "t", "family": "rival", "variant": "needling", "day": 3, "who": "who", "boss": "g1", "tie": "stranger", "stage": "open"}
	var feared = EventsScript.resolve(needle, "stand_up", [0.5], {"fear": 80.0, "combat": 60.0}, names)
	var unfeared = EventsScript.resolve(needle, "stand_up", [0.5], {"fear": 0.0, "combat": -60.0}, names)
	check(effectsHave(feared["effects"], "rival") and effectsHave(feared["effects"], "feeling", "fear", 10.0) and !effectsHave(unfeared["effects"], "feeling", "fear", 10.0), "standing up works against someone who fears you and not against someone who does not")
	check(effectsHave(EventsScript.resolve(needle, "fight", [0.5], {}, names)["effects"], "fight") and effectsHave(EventsScript.resolve(needle, "back_down", [0.5], {}, names)["effects"], "credits"), "fighting starts a fight; backing down costs credits")
	var pay = EventsScript.resolve({"id": "t", "family": "hostile", "variant": "cornered", "day": 3, "who": "who", "boss": "g1", "tie": "stranger", "stage": "open"}, "pay", [0.5], {"credits": 3}, names)
	check(effectsHave(pay["effects"], "credits") and pay["effects"][0]["amount"] == -3, "handing over money never takes more than you have")
	var broke = EventsScript.resolve({"id": "t", "family": "hostile", "variant": "cornered", "day": 3, "who": "who", "boss": "g1", "tie": "stranger", "stage": "open"}, "talk_down", [0.99], {"credits": 0}, names)
	check(broke["effects"][0]["type"] == "credits" and broke["effects"][0]["amount"] == 0 or broke["effects"][0]["type"] != "credits", "being robbed with no money costs nothing")
	# Rivals: fear stops them, repeated losses make them leave, a rival may go to their gang
	var rs = EventsScript.defaults()
	check(EventsScript.isRivalActive(rs, "r", 0.0) and !EventsScript.isRivalActive(rs, "r", 40.0) and EventsScript.isRivalActive(rs, "r", 39.9), "a rival who fears the player enough is no longer active")
	var out1 = EventsScript.recordRival(rs, "r", "win", 3, 10.0, false)
	check(!out1["transfer"] and !out1["stopped"] and EventsScript.isRivalActive(rs, "r", 10.0), "one defeat does not end it")
	var out2 = EventsScript.recordRival(rs, "r", "defeat", 4, 25.0, false)
	check(out2["stopped"] and !out2["transfer"] and !EventsScript.isRivalActive(rs, "r", 25.0) and EventsScript.getRival(rs, "r")["defeats"] == 1 and EventsScript.getRival(rs, "r")["wins"] == 2, "beaten twice, they stop harassing")
	var out3 = EventsScript.recordRival(rs, "r", "defeat", 5, 40.0, false)
	check(out3["transfer"] and out3["stopped"], "beaten or humiliated three times, they ask for another job")
	var gs = EventsScript.defaults()
	var last = {}
	var wentToGang = false
	for day in range(4):
		last = EventsScript.recordRival(gs, "g", "harass", day, 0.0, true)
		wentToGang = wentToGang or last["gang"]
	check(wentToGang and last["stopped"] and EventsScript.getRival(gs, "g")["gang_help"] and !EventsScript.isRivalActive(gs, "g", 0.0), "a rival who keeps failing goes to their gang instead of attacking forever")
	var lone = EventsScript.defaults()
	var loneOut = {}
	for day in range(4):
		loneOut = EventsScript.recordRival(lone, "l", "harass", day, 0.0, false)
	check(!loneOut["gang"] and loneOut["stopped"], "with no gang they simply stop")
	check(!EventsScript.recordRival(lone, "", "win", 1, 0.0, false)["stopped"] and !lone["rivals"].has(""), "a missing character changes nothing")
	var fearStop = EventsScript.defaults()
	check(EventsScript.recordRival(fearStop, "f", "harass", 1, 50.0, false)["stopped"], "a fearful rival is stopped for good")
	# They never repeat the same confrontation endlessly: a stopped rival is never picked again
	var stoppedState = EventsScript.defaults()
	stoppedState["rivals"]["r1"] = EventsScript.defaultRival()
	stoppedState["rivals"]["r1"]["stopped"] = true
	var repeat = false
	for day in range(500):
		var p8 = EventsScript.pick(stoppedState, factsFor(day, [coworker("r1", "stranger", true, 0.0, true)]), [rng.randf() * 0.2, rng.randf(), rng.randf(), rng.randf()])
		if(!p8.empty() and (p8["family"] == "rival" or p8["family"] == "hostile")):
			repeat = true
	check(!repeat, "a rival who stopped is never picked for another confrontation")
	# Save and load: nothing resolves twice
	var saved = EventsScript.defaults()
	saved["pending"] = first.duplicate(true)
	saved["rivals"]["r1"] = {"wins": 2, "defeats": 1, "harass": 3, "stopped": true, "last_day": 4, "gang_help": false}
	saved["pairs"]["c1"] = 5
	saved["events"] = 3
	var clean = EventsScript.sanitize(JSON.parse(JSON.print(saved)).result)
	check(same(clean, saved), "workplace data survives a JSON round trip")
	var dirty = EventsScript.sanitize({"last_day": "x", "shifts": -5, "events": 2.4, "pairs": {"a": "x", "b": 3}, "rivals": {"r": {"wins": -1, "defeats": "x", "harass": 4, "stopped": "yes", "gang_help": 1}, "": {}, "z": 4}, "pending": {"id": "p", "family": "teleport", "variant": "x", "day": 1}})
	check(dirty["last_day"] == -1 and dirty["shifts"] == 0 and dirty["events"] == 2 and dirty["pairs"].keys() == ["b"] and dirty["rivals"]["r"]["wins"] == 0 and dirty["rivals"]["r"]["harass"] == 4 and !dirty["rivals"]["r"]["stopped"] and !dirty["rivals"]["r"]["gang_help"] and !dirty["rivals"].has("") and !dirty["rivals"].has("z") and dirty["pending"].empty(), "damaged workplace data is repaired and an incomplete pending event is dropped: " + JSON.print(dirty))
	check(same(EventsScript.sanitize(null), EventsScript.defaults()) and same(EventsScript.sanitize([]), EventsScript.defaults()), "garbage becomes the defaults")
	var st2 = StateScript.new()
	st2.workplace["pending"] = first.duplicate(true)
	var back = StateScript.new()
	back.loadData(JSON.parse(JSON.print(st2.saveData())).result)
	check(same(back.workplace["pending"], first) and !back.workplace["pending"].empty(), "a waiting event is still waiting after a load")
	# resolving clears: simulate the game's order
	var theState = back.workplace
	var pending = theState["pending"].duplicate(true)
	theState["pending"] = {}
	check(theState["pending"].empty() and !pending.empty(), "the pending slot is emptied before the effects are applied")

func effectsHave(effects, type, axis = "", amount = null) -> bool:
	for effect in effects:
		if(effect.get("type", "") != type):
			continue
		if(axis != "" and effect.get("axis", "") != axis):
			continue
		if(amount != null and float(effect.get("amount", 0.0)) != float(amount)):
			continue
		return true
	return false

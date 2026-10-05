extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/PersistentLivesTest.gd --quit
# The rules of persistent lives with no game running: daily routines, presence records and their save data. Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const PresenceScript = preload("res://Modules/SandboxOverhaulModule/Prison/PresenceState.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
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

func facts(overrides = {}) -> Dictionary:
	var result = {"block": "orange", "cellRoom": "sbx_cell_orange_3", "hangout": "", "leader": false, "anchor": false, "job": "", "available": true, "avoid": [], "visitable": []}
	for key in overrides:
		result[key] = overrides[key]
	return result

func _init():
	planTests()
	stateTests()
	print("PersistentLivesTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

func planTests():
	var people = ids(40)
	# Shape of every plan
	for id in people:
		for day in range(1, 6):
			var plan = RoutineScript.planFor(id, day, facts())
			check(RoutineScript.isValidPlan(plan), id + " day " + str(day) + " has a valid plan: " + str(plan))
			check(plan[0][2] == "sleep" and plan[0][3] == "sbx_cell_orange_3" and plan[plan.size() - 1][2] == "sleep" and plan[plan.size() - 1][3] == "sbx_cell_orange_3", id + ": the day starts and ends asleep in the exact cell")
			check(plan[0][1] == CellsScript.wakeSeconds(id) and plan[plan.size() - 1][0] == CellsScript.bedtimeSeconds(id), id + ": sleep runs until waking and from bedtime")
			var sleeping = 0
			for segment in plan:
				if(segment[2] == "sleep"):
					sleeping += 1
					check(segment[3] == "sbx_cell_orange_3", "sleep is always in the cell")
				else:
					check(segment[3] != "", "every waking segment has a room: " + str(segment))
			check(sleeping == 2, id + ": exactly two sleep segments")
			check(same(plan, RoutineScript.planFor(id, day, facts())), id + ": the same plan every time it is asked")
	# Different days differ
	var differing = 0
	for id in people:
		if(!same(RoutineScript.planFor(id, 1, facts()), RoutineScript.planFor(id, 2, facts()))):
			differing += 1
	check(differing >= 38, "the next day's plan differs for almost everybody: " + str(differing) + " of 40")
	var leisureDay1 = {}
	var leisureDay2 = {}
	for id in people:
		leisureDay1[id] = leisureKinds(RoutineScript.planFor(id, 1, facts()))
		leisureDay2[id] = leisureKinds(RoutineScript.planFor(id, 2, facts()))
	var lessThan = 0
	for id in people:
		if(leisureDay1[id] != leisureDay2[id]):
			lessThan += 1
	check(lessThan >= 35, "leisure choices change from day to day: " + str(lessThan))
	# Not everyone goes to the same place
	var rooms = {}
	var atNoon = {}
	for id in people:
		var plan2 = RoutineScript.planFor(id, 3, facts())
		var seg = RoutineScript.segmentAt(plan2, hours(15, 30))
		atNoon[seg[3]] = int(atNoon.get(seg[3], 0)) + 1
		for segment in plan2:
			rooms[segment[3]] = true
	var biggest = 0
	for room in atNoon:
		biggest = int(max(biggest, atNoon[room]))
	check(atNoon.size() >= 5 and biggest <= 16, "at 15:30 the prison is spread over " + str(atNoon.size()) + " places, the busiest holds " + str(biggest))
	# Activities last 60 to 150 minutes (a stretch may be cut short by an obligation)
	var longOnes = 0
	var total = 0
	for id in people:
		for segment in RoutineScript.planFor(id, 4, facts()):
			if(segment[2] in ["gym", "yard", "underground", "hall", "social", "cellhall", "cellrest"]):
				total += 1
				if(segment[1] - segment[0] > 200 * 60):
					longOnes += 1
	check(total > 100 and longOnes == 0, "free-time activities never run past about three hours: " + str(longOnes) + " of " + str(total))
	# Work: the shift is a fixed obligation, at the workplace, whatever else changes
	for id in people:
		for day in range(1, 5):
			var workPlan = RoutineScript.planFor(id, day, facts({"job": "laundry"}))
			var window = ScheduleScript.shiftWindow(id, "laundry")
			var found = false
			for segment in workPlan:
				if(segment[2] == "work"):
					found = true
					check(segment[3] == "main_laundry" and segment[0] == window["start"] and segment[1] == window["end"], id + ": the work segment is exactly the shift at the laundry")
			check(found and RoutineScript.segmentAt(workPlan, window["start"] + 600)[2] == "work", id + ": at work during the shift")
			var offPlan = RoutineScript.planFor(id, day, facts({"job": "laundry", "available": false}))
			var anyWork = false
			for segment in offPlan:
				anyWork = anyWork or segment[2] == "work"
			check(!anyWork and RoutineScript.isValidPlan(offPlan), id + ": a worker who cannot work has no work segment but still a valid day")
	# The obligations stay the same on every day
	var stable = people[0]
	var sleepRooms = {}
	for day in range(1, 8):
		var p = RoutineScript.planFor(stable, day, facts({"job": "mining"}))
		sleepRooms[p[0][3]] = true
		sleepRooms[p[p.size() - 1][3]] = true
	check(sleepRooms.keys() == ["sbx_cell_orange_3"], "the bed never changes")
	# Gang: leaders and anchors are at the hangout in the afternoon window; others are drawn to it; outsiders avoid it
	var hangout = "gym_weights"
	var allHangouts = ["gym_weights", "main_laundry", "eng_workshop"]
	var leaderAt = 0
	var anchorAt = 0
	var memberAtHangout = 0
	var outsiderAtHangout = 0
	for id in people:
		for day in range(1, 11):
			var leaderPlan = RoutineScript.planFor(id, day, facts({"hangout": hangout, "leader": true}))
			var s1 = RoutineScript.segmentAt(leaderPlan, hours(16))
			if(s1[2] == "hangout" and s1[3] == hangout):
				leaderAt += 1
			var anchorPlan = RoutineScript.planFor(id, day, facts({"hangout": hangout, "anchor": true}))
			var s2 = RoutineScript.segmentAt(anchorPlan, hours(16))
			if(s2[2] == "hangout" and s2[3] == hangout):
				anchorAt += 1
			var memberPlan = RoutineScript.planFor(id, day, facts({"hangout": hangout}))
			for segment in memberPlan:
				if(segment[2] == "hangout"):
					memberAtHangout += 1
					break
			var outsiderPlan = RoutineScript.planFor(id, day, facts({"avoid": allHangouts}))
			for segment in outsiderPlan:
				if(allHangouts.has(segment[3])):
					outsiderAtHangout += 1
	check(leaderAt == 400, "an unemployed gang leader is at their hangout at 16:00 every day: " + str(leaderAt) + " of 400")
	check(anchorAt == 400, "and so is the member chosen to keep them company: " + str(anchorAt) + " of 400")
	check(memberAtHangout >= 250, "ordinary members usually spend some time there: " + str(memberAtHangout) + " of 400 days")
	check(outsiderAtHangout == 0, "outsiders who avoid the hangouts never choose one: " + str(outsiderAtHangout))
	var leaderWorking = 0
	for id in people:
		var workingLeader = RoutineScript.planFor(id, 2, facts({"hangout": hangout, "leader": true, "job": "workshop"}))
		for segment in workingLeader:
			if(segment[2] == "work"):
				leaderWorking += 1
		check(RoutineScript.isValidPlan(workingLeader), "a working leader still has a valid day")
	check(leaderWorking == 40, "work still beats the gang window for a leader with a job")
	# Neutral outsiders may drop by another gang's hangout, rarely
	var visits = 0
	for id in people:
		for day in range(1, 11):
			for segment in RoutineScript.planFor(id, day, facts({"visitable": ["main_laundry"], "avoid": ["gym_weights"]})):
				if(segment[2] == "visit"):
					visits += 1
					check(segment[3] == "main_laundry", "a visit goes to a visitable hangout")
	check(visits >= 5 and visits <= 200, "neutral outsiders occasionally visit: " + str(visits) + " in 400 days")
	var gangVisits = 0
	for id in people:
		for segment in RoutineScript.planFor(id, 3, facts({"hangout": hangout, "visitable": ["main_laundry"]})):
			if(segment[2] == "visit"):
				gangVisits += 1
	check(gangVisits == 0, "gang members do not drop in on other gangs")
	# Lookup
	var plan3 = RoutineScript.planFor("i00", 2, facts())
	check(RoutineScript.segmentAt(plan3, hours(3))[2] == "sleep" and RoutineScript.segmentAt(plan3, hours(23, 59))[2] == "sleep" and RoutineScript.segmentAt(plan3, hours(5, 59))[2] == "sleep", "small hours, midnight and 05:59 are all the night before")
	check(RoutineScript.axis(hours(3)) == hours(27) and RoutineScript.axis(hours(6)) == hours(6) and RoutineScript.axis(hours(23)) == hours(23), "the day axis runs 06:00 to 06:00")
	check(RoutineScript.segmentIndex([], 5) == -1 and RoutineScript.segmentAt([], 5).empty(), "no plan, no segment")
	# Validation
	check(!RoutineScript.isValidPlan(null) and !RoutineScript.isValidPlan([]) and !RoutineScript.isValidPlan("x") and !RoutineScript.isValidPlan([[0, 5, "sleep", "r"], [5, 9, "sleep", "r"]]) and !RoutineScript.isValidPlan([[RoutineScript.DAY_START, 30000, "dance", "r"], [30000, RoutineScript.DAY_END, "sleep", "r"]]) and !RoutineScript.isValidPlan([[RoutineScript.DAY_START, 30000, "sleep", "r"], [30001, RoutineScript.DAY_END, "sleep", "r"]]), "damaged plans are rejected")
	check(RoutineScript.isValidPlan([[RoutineScript.DAY_START, 30000, "sleep", "r"], [30000, RoutineScript.DAY_END, "sleep", "r"]]), "a minimal valid plan is accepted")
	# Words come from the activity, not the clock
	check(RoutineScript.describe("sleep", "sbx_cell_orange_3", "sbx_cell_orange_3", "", 3) == "{main.name} is sleeping in {main.his} cell." and RoutineScript.describe("sleep", "hall", "sbx_cell_orange_3", "", 3) == "{main.name} is heading back to Cell 3.", "sleeping needs to have arrived; before that they are heading back")
	check(RoutineScript.describe("cellrest", "c", "c", "", 3) == "{main.name} is relaxing in {main.his} cell." and RoutineScript.describe("cellrest", "h", "c", "", 3).find("heading to Cell 3") != -1, "a daytime rest in the cell")
	check(RoutineScript.describe("work", "mining_shafts_entering", "mining_shafts_entering", "the mines") == "{main.name} is working in the mines." and RoutineScript.describe("work", "x", "mining_shafts_entering", "the mines").find("heading to work") != -1, "working")
	check(RoutineScript.describe("gym", "x", "y").find("heading to the gym") != -1 and RoutineScript.describe("gym", "y", "y").find("working out") != -1 and RoutineScript.describe("hangout", "y", "y", "", 0, "Ironhand") == "{main.name} is hanging out with Ironhand.", "other activities")
	check(RoutineScript.placeName("work", "main_laundry") == "the laundry" and RoutineScript.placeName("gym", "x") == "the gym" and RoutineScript.placeName("zzz", "x", "Odd Room") == "Odd Room", "place names")
	for kind in RoutineScript.KINDS:
		check(RoutineScript.describe(kind, "a", "b", "the place", 2, "Gang").find("{main.name}") != -1 and RoutineScript.describe(kind, "b", "b", "the place", 2, "Gang").find("{main.name}") != -1, "every kind has text: " + kind)
	check(RoutineScript.describe("dance", "a", "a") == "{main.name} is hanging out!", "an unknown kind falls back")

func leisureKinds(plan) -> Array:
	var kinds = []
	for segment in plan:
		if(segment[2] != "sleep" and segment[2] != "meal" and segment[2] != "shower"):
			kinds.append(segment[2] + ":" + segment[3])
	return kinds

func stateTests():
	var s = StateScript.new()
	check(s.schema_version == 8 and s.presence.empty() and same(s.routines, PresenceScript.defaultRoutines()), "a new game has the schema 8 fields, empty")
	var plan = RoutineScript.planFor("i01", 3, facts())
	s.routines = {"day": 3, "plans": {"i01": plan}}
	s.presence = {"i01": {"room": "hall_canteen", "kind": "meal", "act": "do", "dest": "hall_canteen", "since": 300000, "seg": 4}}
	var t = StateScript.new()
	t.loadData(JSON.parse(JSON.print(s.saveData())).result)
	check(same(t.routines, s.routines) and same(t.presence, s.presence) and t.schema_version == 8, "routines and presence survive save and load exactly, so loading never rerolls the day")
	var old = StateScript.new()
	old.loadData({"schema_version": 7})
	check(old.schema_version == 8 and old.routines["day"] == -1 and old.presence.empty(), "a schema 7 save loads with no routines and no presence")
	var future = StateScript.new()
	future.loadData({"schema_version": 9, "routines": {"day": 5, "plans": {}}, "presence": {"i01": {"room": "x"}}})
	check(future.schema_version == 9 and future.routines["day"] == 5 and future.presence.has("i01"), "a newer save keeps its data and its version")
	var dirty = PresenceScript.sanitizePresence({"i01": {"room": 5, "kind": "dance", "act": "fly", "dest": null, "since": "x", "seg": 9999}, "": {}, "pc": {}, "i02": "bad", "i03": {"room": "hall_canteen", "kind": "gym", "act": "travel", "dest": "gym_weights", "since": 12.6, "seg": 2.2}})
	check(dirty.keys() == ["i01", "i03"] and dirty["i01"]["room"] == "" and dirty["i01"]["kind"] == "" and dirty["i01"]["act"] == "" and dirty["i01"]["seg"] == 60 and dirty["i03"]["since"] == 13 and dirty["i03"]["seg"] == 2 and dirty["i03"]["act"] == "travel", "damaged presence records are repaired: " + JSON.print(dirty))
	var dirtyRoutines = PresenceScript.sanitizeRoutines({"day": "x", "plans": {"i01": [[0, 5, "sleep", "r"]], "i02": plan, "pc": plan, "": plan}})
	check(dirtyRoutines["day"] == -1 and dirtyRoutines["plans"].keys() == ["i02"] and same(dirtyRoutines["plans"]["i02"], plan), "invalid plans are dropped, valid ones kept, the player never has one")
	check(same(PresenceScript.sanitizeRoutines(null), PresenceScript.defaultRoutines()) and PresenceScript.sanitizePresence([]).empty() and PresenceScript.sanitizeRoutines("x")["plans"].empty(), "garbage becomes the defaults")
	var big = StateScript.new()
	for id in ids(60):
		big.routines["plans"][id] = RoutineScript.planFor(id, 3, facts())
		big.presence[id] = {"room": "hall_canteen", "kind": "meal", "act": "do", "dest": "hall_canteen", "since": 300000, "seg": 3}
	var bytes = JSON.print(big.saveData()).length()
	check(bytes < 120000, "the whole saved state for 60 inmates stays small: " + str(bytes) + " bytes")
	print("OBSERVED saved routines and presence for 60 inmates: " + str(JSON.print(big.routines).length() + JSON.print(big.presence).length()) + " bytes")

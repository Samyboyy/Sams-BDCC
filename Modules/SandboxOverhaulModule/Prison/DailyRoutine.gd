extends Reference
class_name DailyRoutine

# One lightweight plan per inmate per day. No game access, so it can be tested on its own.
#
# The plan is a list of consecutive segments [start, end, kind, room] covering the whole prison day, in "axis seconds": BDCC's day number changes at 06:00, so a day runs from
# 06:00 to 06:00 and the small hours after midnight (axis 24h-30h) belong to the day that began the evening before.
#
#   fixed obligations:  sleep in the exact cell (06:00 until waking, and from bedtime), the job's shift at the workplace, an anchor member's time at their gang's hangout
#   variable activity:  breakfast, a shower, lunch, dinner, the gym, the yard, the underground, the halls, a social stretch, resting in the cell, the gang hangout
#
# The plan comes from the character, the day and a few facts only (stable seeded variation), so asking again gives the same plan, a new day gives a different one, and nothing about
# the player (where they stand, what they have seen) enters into it. It is generated once per day and stored; see SandboxState.routines. Activities last 60 to 150 minutes.

const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")

const DAY_START = 6 * 3600
const DAY_END = 30 * 3600
const MIN_SEGMENT = 20 * 60
const KINDS = ["sleep", "work", "finish", "meal", "shower", "gym", "yard", "underground", "hall", "cellhall", "cellrest", "hangout", "social", "visit", "held", "enslaved"]
const FINISH_SECONDS = 10 * 60 # after a shift the workers pack up for ten minutes at the workplace, then leave for their next activity
const GANG_WINDOW_START = 15 * 3600
const GANG_WINDOW_END = 17 * 3600 + 30 * 60

# What can fill a stretch of free time, by time of day: [kind, weight]. "hangout" counts for gang members only, "visit" is a neutral outsider dropping by another gang's hangout.
const MORNING = [["cellhall", 3], ["shower", 2], ["hall", 3], ["cellrest", 2], ["social", 2]]
const LATE_MORNING = [["hall", 3], ["yard", 2], ["gym", 2], ["social", 2], ["cellrest", 1], ["underground", 1], ["hangout", 2]]
const MIDDAY = [["meal", 4], ["hall", 2], ["yard", 2], ["social", 1]]
const AFTERNOON = [["gym", 3], ["yard", 2], ["underground", 2], ["shower", 1], ["hangout", 6], ["social", 2], ["cellrest", 2], ["hall", 1], ["visit", 1]]
const EVENING = [["hall", 3], ["cellhall", 3], ["social", 2], ["cellrest", 2], ["meal", 1]]

# "15:00 to 17:30", the window in which a gang's leader is at the hangout.
static func formatWindow() -> String:
	return "%02d:%02d to %02d:%02d" % [int(floor(GANG_WINDOW_START / 3600.0)), int(floor((GANG_WINDOW_START % 3600) / 60.0)), int(floor(GANG_WINDOW_END / 3600.0)), int(floor((GANG_WINDOW_END % 3600) / 60.0))]

static func axis(timeOfDay) -> int:
	var t:int = posmod(int(timeOfDay), 86400)
	return t if t >= DAY_START else t + 86400

static func isNumberValue(value) -> bool:
	return (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) && !is_nan(float(value)) && !is_inf(float(value))

static func pool(at:int) -> Array:
	if(at < 8 * 3600):
		return MORNING
	if(at < 12 * 3600):
		return LATE_MORNING
	if(at < 14 * 3600):
		return MIDDAY
	if(at < 19 * 3600):
		return AFTERNOON
	return EVENING

# The category of rooms a kind uses in PrisonSchedule.CATEGORIES ("" for kinds with a fixed room).
static func categoryOf(kind:String) -> String:
	match(kind):
		"meal":
			return "canteen"
		"social":
			return "hall"
		"gym", "yard", "underground", "hall", "cellhall", "shower":
			return kind
	return ""

static func roomFor(kind:String, characterID, day:int, salt:int, facts:Dictionary) -> String:
	if(kind == "cellrest" || kind == "sleep"):
		return str(facts.get("cellRoom", ""))
	if(kind == "hangout"):
		return str(facts.get("hangout", ""))
	if(kind == "visit"):
		var visitable:Array = facts.get("visitable", [])
		if(visitable.empty()):
			return ""
		return str(visitable[ScheduleScript.hashOf(characterID, "visit" + str(day) + "_" + str(salt)) % visitable.size()])
	if(kind == "work"):
		return str(EmploymentScript.JOBS[facts["job"]]["room"]) if EmploymentScript.isValidJob(facts.get("job")) else ""
	var category:String = categoryOf(kind)
	if(category == ""):
		return ""
	var context:Dictionary = {"block": facts.get("block", "orange"), "hangout": facts.get("hangout", ""), "avoid": facts.get("avoid", [])}
	return ScheduleScript.roomForCategory(category, characterID, day, salt, context)

# A free-time activity for the stretch starting at `at`: weighted by the time of day, never a kind that has no room for this person.
static func pickKind(characterID, day:int, salt:int, at:int, facts:Dictionary) -> String:
	var options:Array = []
	var hasHangout:bool = str(facts.get("hangout", "")) != ""
	for entry in pool(at):
		var kind:String = entry[0]
		if(kind == "hangout" && !hasHangout):
			continue
		if(kind == "visit" && (hasHangout || facts.get("visitable", []).empty())):
			continue
		if(kind == "cellrest" && str(facts.get("cellRoom", "")) == ""):
			continue
		var weight:int = int(entry[1])
		if(kind == "hangout" && at >= GANG_WINDOW_START && at < GANG_WINDOW_END):
			weight += 6 # members strongly prefer their hangout during the afternoon window
		options.append([kind, weight])
	var picked = ScheduleScript.weightedPick(options, ScheduleScript.hashOf(characterID, "kind" + str(day) + "_" + str(salt)))
	return str(picked) if picked != null else "hall"

static func duration(characterID, day:int, salt:int) -> int:
	return 60 * (60 + ScheduleScript.hashOf(characterID, "len" + str(day) + "_" + str(salt)) % 91)

# Whether two intervals overlap.
static func overlaps(a:Array, b:Array) -> bool:
	return a[0] < b[1] && b[0] < a[1]

# The plan. facts: {"block", "cellRoom", "hangout", "leader" (bool), "anchor" (bool: always at the hangout in the afternoon window), "job", "available", "avoid": [rooms],
# "visitable": [rooms]}. Returns [[start, end, kind, room], ...] covering DAY_START to DAY_END without gaps or overlaps.
static func planFor(characterID, day:int, facts:Dictionary) -> Array:
	var cell:String = str(facts.get("cellRoom", ""))
	var wake:int = int(clamp(CellsScript.wakeSeconds(characterID), DAY_START + 600, 9 * 3600))
	var bed:int = int(clamp(CellsScript.bedtimeSeconds(characterID), 19 * 3600, DAY_END - 600))
	# Obligations first
	var fixed:Array = []
	var job = facts.get("job", "")
	if(job is String && EmploymentScript.isValidJob(job) && bool(facts.get("available", true))):
		var window:Dictionary = ScheduleScript.shiftWindow(characterID, job)
		if(!window.empty()):
			var workRoom:String = str(EmploymentScript.JOBS[job]["room"])
			var workEnd:int = int(min(window["end"], bed))
			fixed.append([max(window["start"], wake), workEnd, "work", workRoom])
			if(workEnd + FINISH_SECONDS <= bed):
				fixed.append([workEnd, workEnd + FINISH_SECONDS, "finish", workRoom])
	if(str(facts.get("hangout", "")) != "" && (bool(facts.get("leader", false)) || bool(facts.get("anchor", false)))):
		var start:int = GANG_WINDOW_START + ScheduleScript.hashOf(characterID, "gangstart" + str(day)) % (20 * 60)
		var gang:Array = [start, GANG_WINDOW_END, "hangout", str(facts["hangout"])]
		var blocked:bool = false
		for entry in fixed:
			blocked = blocked or overlaps(gang, entry)
		if(!blocked):
			fixed.append(gang)
	# Meals sit in the gaps they fit in
	var meals:Array = [[wake + 10 * 60, 30 + ScheduleScript.hashOf(characterID, "b" + str(day)) % 21, 80, "b"], [12 * 3600 + ScheduleScript.hashOf(characterID, "lunchat" + str(day)) % 3600, 35, 55, "l"], [18 * 3600 + ScheduleScript.hashOf(characterID, "dinnerat" + str(day)) % 3000, 40, 70, "d"]]
	for meal in meals:
		if(ScheduleScript.hashOf(characterID, "meal" + str(meal[3]) + str(day)) % 100 >= int(meal[2])):
			continue
		var interval:Array = [meal[0], meal[0] + int(meal[1]) * 60, "meal", roomFor("meal", characterID, day, 100, facts)]
		var fits:bool = interval[0] >= wake && interval[1] <= bed
		for entry in fixed:
			fits = fits and !overlaps(interval, entry)
		if(fits):
			fixed.append(interval)
	# A shower in the morning or the afternoon, about half of the days
	if(ScheduleScript.hashOf(characterID, "shower" + str(day)) % 100 < 45):
		var showerAt:int = (wake + 40 * 60) if ScheduleScript.hashOf(characterID, "showerwhen" + str(day)) % 2 == 0 else (16 * 3600 + ScheduleScript.hashOf(characterID, "showerlate" + str(day)) % 5400)
		var shower:Array = [showerAt, showerAt + (15 + ScheduleScript.hashOf(characterID, "showerlen" + str(day)) % 11) * 60, "shower", roomFor("shower", characterID, day, 101, facts)]
		var showerFits:bool = shower[0] >= wake && shower[1] <= bed
		for entry in fixed:
			showerFits = showerFits and !overlaps(shower, entry)
		if(showerFits):
			fixed.append(shower)
	fixed.sort_custom(IntervalSorter, "byStart")
	# Walk the day: sleep, then free time and fixed segments in order, then sleep
	var plan:Array = [[DAY_START, wake, "sleep", cell]]
	var cursor:int = wake
	var salt:int = 0
	for segment in fixed:
		if(int(segment[0]) > cursor):
			salt = fillFree(plan, characterID, day, salt, cursor, int(segment[0]), facts)
		plan.append([int(segment[0]), int(segment[1]), segment[2], segment[3]])
		cursor = int(segment[1])
	if(cursor < bed):
		salt = fillFree(plan, characterID, day, salt, cursor, bed, facts)
	plan.append([bed, DAY_END, "sleep", cell])
	return merge(plan)

# Free time from `from` to `to`: activity after activity of 60 to 150 minutes (the last one takes whatever is left). Returns the next salt.
static func fillFree(plan:Array, characterID, day:int, salt:int, from:int, to:int, facts:Dictionary) -> int:
	var cursor:int = from
	while(cursor < to):
		var kind:String = pickKind(characterID, day, salt, cursor, facts)
		var previous:String = str(plan[plan.size() - 1][2]) if !plan.empty() else ""
		var retry:int = 0
		while(kind == previous && retry < 4): # the same thing twice running is one long stretch, not a new plan
			retry += 1
			kind = pickKind(characterID, day, salt + 1000 * retry, cursor, facts)
		var room:String = roomFor(kind, characterID, day, salt, facts)
		if(room == ""):
			kind = "hall"
			room = roomFor("hall", characterID, day, salt, facts)
		var end:int = cursor + duration(characterID, day, salt)
		if(to - end < MIN_SEGMENT):
			end = to
		plan.append([cursor, end, kind, room])
		cursor = end
		salt += 1
	return salt

class IntervalSorter:
	static func byStart(a, b) -> bool:
		return a[0] < b[0]

# Joins neighbouring segments of the same kind and room, drops empty ones and closes any gap, so the plan always covers the whole day.
static func merge(plan:Array) -> Array:
	var result:Array = []
	for segment in plan:
		if(int(segment[1]) <= int(segment[0])):
			continue
		if(!result.empty() && result[result.size() - 1][2] == segment[2] && result[result.size() - 1][3] == segment[3] && result[result.size() - 1][1] == segment[0]):
			result[result.size() - 1][1] = segment[1]
		else:
			result.append([int(segment[0]), int(segment[1]), str(segment[2]), str(segment[3])])
	if(!result.empty()):
		result[0][0] = DAY_START
		result[result.size() - 1][1] = DAY_END
		for index in range(1, result.size()):
			result[index][0] = result[index - 1][1]
	return result

# Index of the segment a time falls in, or -1 for an empty plan.
static func segmentIndex(plan:Array, timeOfDay) -> int:
	if(plan.empty()):
		return -1
	var at:int = axis(timeOfDay)
	for index in range(plan.size()):
		if(at >= plan[index][0] && at < plan[index][1]):
			return index
	return plan.size() - 1

static func segmentAt(plan:Array, timeOfDay) -> Array:
	var index:int = segmentIndex(plan, timeOfDay)
	return plan[index] if index >= 0 else []

# Whether a stored plan is usable: consecutive, covering the day, known kinds, text rooms. Used when loading.
static func isValidPlan(plan) -> bool:
	if(!(plan is Array) || plan.size() < 2 || plan.size() > 40):
		return false
	var cursor:int = DAY_START
	for segment in plan:
		if(!(segment is Array) || segment.size() != 4 || !isNumberValue(segment[0]) || !isNumberValue(segment[1]) || !(segment[2] is String) || !KINDS.has(segment[2]) || !(segment[3] is String)):
			return false
		if(int(segment[0]) != cursor || int(segment[1]) <= cursor):
			return false
		cursor = int(segment[1])
	return cursor == DAY_END

# ---- Words ----
const WORK_PLACES = {"mining": "the mine", "workshop": "the workshop", "laundry": "the laundry"}
const KIND_PLACES = {"meal": "the canteen", "shower": "the showers", "gym": "the gym", "yard": "the yard", "underground": "the Underground", "hall": "the main hall", "social": "the main hall", "cellhall": "the cell block hall"}

# Short name of the place for text like "heading to the gym".
static func placeName(kind:String, room:String, roomName:String = "") -> String:
	if(kind == "work" && EmploymentScript.jobAtRoom(room) != ""):
		var jobID:String = EmploymentScript.jobAtRoom(room)
		return str(WORK_PLACES.get(jobID, "the " + str(EmploymentScript.JOBS[jobID]["workplace"]).to_lower()))
	if(kind == "finish" && EmploymentScript.jobAtRoom(room) != ""):
		return str(WORK_PLACES.get(EmploymentScript.jobAtRoom(room), "work"))
	if(KIND_PLACES.has(kind)):
		return str(KIND_PLACES[kind])
	return roomName if roomName != "" else "somewhere"

# What a person is doing, written with BDCC's name placeholders ({main.name}, {main.his}). here: where they are; target: where they are going.
# This is derived from the activity state the pawn really has (its goal's kind and whether it has arrived), never from the clock.
static func describe(kind:String, here:String, target:String, placeText:String = "", cellNumber:int = 0, hangoutName:String = "") -> String:
	var arrived:bool = here == target
	match(kind):
		"sleep":
			if(arrived):
				return "{main.name} is sleeping in {main.his} cell."
			return "{main.name} is heading back to " + ("Cell " + str(cellNumber) if cellNumber > 0 else "{main.his} cell") + "."
		"cellrest":
			if(arrived):
				return "{main.name} is relaxing in {main.his} cell."
			return "{main.name} is heading to " + ("Cell " + str(cellNumber) if cellNumber > 0 else "{main.his} cell") + "."
		"work":
			return ("{main.name} is working in " + placeText + ".") if arrived else ("{main.name} is heading to work in " + placeText + ".")
		"finish":
			return "{main.name} is finishing {main.his} shift in " + placeText + "." if arrived else "{main.name} is heading back to " + placeText + " to finish up."
		"meal":
			return "{main.name} is having a meal in the canteen." if arrived else "{main.name} is heading to the canteen."
		"shower":
			return "{main.name} is washing up in the showers." if arrived else "{main.name} is heading to the showers."
		"gym":
			return "{main.name} is working out." if arrived else "{main.name} is heading to the gym."
		"yard":
			return "{main.name} is out in the yard." if arrived else "{main.name} is heading out to the yard."
		"underground":
			return "{main.name} is watching what goes on in the Underground." if arrived else "{main.name} is heading down to the Underground."
		"hangout":
			return ("{main.name} is hanging out with " + hangoutName + ".") if arrived else ("{main.name} is heading to meet " + hangoutName + ".")
		"visit":
			return "{main.name} is looking around a gang's hangout." if arrived else "{main.name} is on the way to a gang's hangout."
		"held":
			return ("{main.name} is being held by " + hangoutName + ".") if arrived else ("{main.name} is being taken to " + hangoutName + ".")
		"enslaved":
			return ("{main.name} is kept as a slave by " + hangoutName + ".") if arrived else ("{main.name} is being taken to " + hangoutName + " as a slave.")
		"social":
			return "{main.name} is looking for someone to talk to." if arrived else "{main.name} is heading over to find company."
		"cellhall", "hall":
			return "{main.name} is hanging around " + placeText + "." if arrived else "{main.name} is heading to " + placeText + "."
	return "{main.name} is hanging out!"

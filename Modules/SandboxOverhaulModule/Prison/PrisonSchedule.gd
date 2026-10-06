extends Reference
class_name PrisonSchedule

# The daily rhythm of the inmates and where they are meant to be, plus the population budgets. No game access, so it can be tested on its own.
#
# Nothing here simulates anything. Given a character, the time and a few facts about them, it answers "where should this inmate be right now and why", the same
# way every time, with a small stable per-person offset so the prison shifts gradually instead of everyone moving on the hour. The population director (PopulationDirector)
# asks this for the inmates near the player and makes it visible; inmates far away stay abstract.
#
# Bands of the day (BDCC time, seconds since the day clock started; hours below are the nominal ones, everyone is shifted by up to 30 minutes either way):
#   night    from bedtime (21:00) to waking (07:00)   in their own cell
#   morning  waking to 08:00                           cell block halls, showers, the canteen
#   work     08:00-14:00                               their workplace during their shift, otherwise halls, canteen, yard, gym
#   leisure  14:00-19:00                               gym, canteen, showers, the yard, the underground, their gang's hangout
#   evening  19:00-bedtime                             common areas and the cell block halls
# Within a band the choice changes every two hours (a "slot"), so a person drifts from room to room over the day.

const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

const NIGHT = "night"
const MORNING = "morning"
const WORK = "work"
const LEISURE = "leisure"
const EVENING = "evening"
const BANDS = [NIGHT, MORNING, WORK, LEISURE, EVENING]

const MORNING_END = 8 * 3600
const WORK_END = 14 * 3600
const LEISURE_END = 19 * 3600
const SLOT_SECONDS = 2 * 3600
const BAND_OFFSET_MINUTES = 30

# Why someone is where they are, most important first. A higher reason always wins over a lower one.
const PRIORITIES = ["scripted", "captivity", "interaction", "medical", "work", "bedtime", "hangout", "leisure"]

# Places inmates gather, grouped by what they do there. Each entry is [roomID, weight]. Hubs are few on purpose: a prison has busy places and quiet ones.
const CATEGORIES = {
	"hall": [["hall_mainentrance", 3], ["main_bench1", 2], ["main_bench2", 2], ["main_hallroom6", 2], ["main_bench3", 1], ["main_bench4", 1]],
	"cellhall": [["{hall}", 4], ["cellblock_nearcells", 1]],
	"shower": [["main_shower1", 2], ["main_shower2", 1]],
	"canteen": [["hall_canteen", 1]],
	"gym": [["gym_weights", 3], ["gym_yoga", 3], ["gym_entrance", 2]],
	"yard": [["yard_firstroom", 3], ["yard_nearstairs", 2], ["yard_waterfall", 2], ["yard_neargym", 1]],
	"underground": [["fight_nearentrance", 2], ["fight_neararena", 2], ["fight_corner_sw", 1]],
}

# What each band does: [category, weight]. "hangout" is the person's gang hangout and only counts for gang members; "work" is their workplace.
const BAND_ACTIVITIES = {
	MORNING: [["cellhall", 4], ["shower", 2], ["canteen", 3], ["hall", 3]],
	WORK: [["hall", 3], ["canteen", 2], ["yard", 2], ["gym", 2], ["cellhall", 1]],
	LEISURE: [["gym", 3], ["canteen", 2], ["shower", 1], ["underground", 2], ["yard", 2], ["hall", 1], ["hangout", 4]],
	EVENING: [["hall", 3], ["cellhall", 4], ["canteen", 1]],
}

# Soft limits on how many inmates one room should hold at once: a busy hub fills up, a corner stays quiet.
const ROOM_LIMITS = {"hall": 7, "cellhall": 6, "shower": 3, "canteen": 7, "gym": 5, "yard": 5, "underground": 4, "workplace": 6, "cell": 2, "other": 4}

# Population budgets as a share of the pawn limit.
const SHARE_INMATES = 0.6
const SHARE_GUARDS = 0.2
const SHARE_NURSES = 0.1
const SHARE_ENGINEERS = 0.1

# The most dynamic staff of each kind (the share of the pawn limit still applies below these). BDCC's own morning wave and spawner create a new character every time nobody is free to pick, and in a prison where
# everybody stays on the map that is every time, so without these a prison filled up within days (45 inmates, 18 guards, 11 nurses and 8 engineers by day 14 were measured). Existing characters are never removed.
const MAX_GUARDS = 10
const MAX_NURSES = 5
const MAX_ENGINEERS = 5

# New prisoners arrive on a schedule, not whenever the spawner asks: the first ones at once (INMATE_START), then fewer and fewer as the soft target is approached, and never beyond the hard cap.
const INMATE_SOFT_TARGET = 26
const INMATE_HARD_CAP = 30
const INMATE_START = 10
const ADMISSION_DECAY = 0.93 # each day closes this share of what is left of the gap to the soft target

# How many inmates the prison holds by this day (0 is the first day): 10, 11, ... about 20 on day 14, 24 on day 30, and never more than the soft target.
static func inmateLimit(day:int) -> int:
	var gap:float = float(INMATE_SOFT_TARGET - INMATE_START) * pow(ADMISSION_DECAY, float(max(0, day)))
	return int(min(INMATE_SOFT_TARGET, INMATE_SOFT_TARGET - int(floor(gap))))

# Whether one more inmate may be admitted now: below the schedule, and never past the hard cap (an overcrowded old save simply admits nobody).
static func mayAdmitInmate(current:int, day:int) -> bool:
	return current < inmateLimit(day) && current < INMATE_HARD_CAP

# ---- Time ----
# Stable offset (seconds) of one person's band changes, -30..+30 minutes.
static func bandOffset(characterID) -> int:
	return CellsScript.offsetSeconds(characterID, "band")

static func isNumberValue(value) -> bool:
	return (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) && !is_nan(float(value)) && !is_inf(float(value))

# The band this person is in. Night follows their own bedtime and waking times (see Cells); the others follow the clock shifted by their offset.
static func bandAt(characterID, timeOfDay) -> String:
	if(!isNumberValue(timeOfDay)):
		return NIGHT
	var t:int = posmod(int(timeOfDay), 86400)
	if(CellsScript.isNight(characterID, t)):
		return NIGHT
	var shifted:int = t - bandOffset(characterID)
	if(shifted < MORNING_END):
		return MORNING
	if(shifted < WORK_END):
		return WORK
	if(shifted < LEISURE_END):
		return LEISURE
	return EVENING

# The index of the two-hour slot inside the day for this person; changes when they move on.
static func slotAt(characterID, timeOfDay) -> int:
	var t:int = posmod(int(timeOfDay), 86400)
	return int(floor(float(t - bandOffset(characterID)) / float(SLOT_SECONDS)))

static func hashOf(characterID, salt:String) -> int:
	return CellsScript.mix((salt + str(characterID)).hash())

# ---- Choosing ----
# Picks from [[value, weight], ...] by a stable number, so the same person in the same slot always gets the same answer.
static func weightedPick(options:Array, number:int):
	var total:int = 0
	for entry in options:
		total += int(entry[1])
	if(total <= 0):
		return null
	var roll:int = number % total
	for entry in options:
		roll -= int(entry[1])
		if(roll < 0):
			return entry[0]
	return options[options.size() - 1][0]

# Room of a category for one person. context: {"block": "orange"|..., "hangout": roomID or ""}. "{hall}" in a category means the person's cell block hall.
static func roomForCategory(category:String, characterID, day:int, slot:int, context:Dictionary) -> String:
	if(category == "hangout"):
		return str(context.get("hangout", ""))
	if(!CATEGORIES.has(category)):
		return ""
	var options:Array = []
	for entry in CATEGORIES[category]:
		var roomID:String = entry[0]
		if(roomID == "{hall}"):
			roomID = LayoutScript.HALL_ROOMS.get(context.get("block", "orange"), "")
		options.append([roomID, entry[1]])
	# Places this person avoids (another gang's hangout) are left out, unless that would leave nothing
	var avoid:Array = context.get("avoid", [])
	if(!avoid.empty()):
		var kept:Array = []
		for option in options:
			if(!avoid.has(option[0])):
				kept.append(option)
		if(!kept.empty()):
			options = kept
	var picked = weightedPick(options, hashOf(characterID, "room" + category + str(day) + "_" + str(slot)))
	return str(picked) if picked != null else ""

# Which category of activity someone does in a band and slot. A gang hangout is only an option for gang members.
static func categoryFor(characterID, band:String, day:int, slot:int, hasHangout:bool) -> String:
	if(!BAND_ACTIVITIES.has(band)):
		return ""
	var options:Array = []
	for entry in BAND_ACTIVITIES[band]:
		if(entry[0] == "hangout" && !hasHangout):
			continue
		options.append(entry)
	var picked = weightedPick(options, hashOf(characterID, "cat" + band + str(day) + "_" + str(slot)))
	return str(picked) if picked != null else ""

# ---- Work shifts of NPCs ----
# When this person's shift runs: the job's own configured window, the same one the player's job uses (the mine is 08:00-10:00, so a coworker is at the mine from 08:00 to 10:00).
# {"start", "end"} in seconds since the day began. The character is not used: every coworker works the same shift.
static func shiftWindow(_characterID, jobID) -> Dictionary:
	if(!EmploymentScript.isValidJob(jobID)):
		return {}
	var job:Dictionary = EmploymentScript.JOBS[jobID]
	var start:int = int(job["open"]) * 3600
	return {"start": start, "end": start + int(job["hours"]) * 3600}

static func isOnShift(characterID, jobID, timeOfDay) -> bool:
	var window:Dictionary = shiftWindow(characterID, jobID)
	if(window.empty() || !isNumberValue(timeOfDay)):
		return false
	var t:int = posmod(int(timeOfDay), 86400)
	return t >= window["start"] && t < window["end"]

# ---- The answer ----
# Where this inmate should be and why. facts: {"block", "cellRoom", "hangout" (room or ""), "job" (job id or ""), "available" (false when something stops them working)}.
# Returns {"room", "reason", "band", "slot", "category"}; reason is one of PRIORITIES ("work", "bedtime", "hangout", "leisure" are decided here).
static func desired(characterID, timeOfDay, day:int, facts:Dictionary) -> Dictionary:
	var band:String = bandAt(characterID, timeOfDay)
	var slot:int = slotAt(characterID, timeOfDay)
	var result:Dictionary = {"room": "", "reason": "leisure", "band": band, "slot": slot, "category": ""}
	var job = facts.get("job", "")
	if(job is String && job != "" && bool(facts.get("available", true)) && isOnShift(characterID, job, timeOfDay)):
		result["room"] = str(EmploymentScript.JOBS[job]["room"])
		result["reason"] = "work"
		result["category"] = "workplace"
		return result
	if(band == NIGHT):
		result["room"] = str(facts.get("cellRoom", ""))
		result["reason"] = "bedtime"
		result["category"] = "cell"
		return result
	var hasHangout:bool = str(facts.get("hangout", "")) != ""
	var category:String = categoryFor(characterID, band, day, slot, hasHangout)
	result["category"] = category
	result["room"] = roomForCategory(category, characterID, day, slot, facts)
	if(category == "hangout"):
		result["reason"] = "hangout"
	return result

# The more important of two reasons ("" counts as the least).
static func higherPriority(a:String, b:String) -> String:
	var indexA:int = PRIORITIES.find(a)
	var indexB:int = PRIORITIES.find(b)
	if(indexA == -1):
		return b
	if(indexB == -1):
		return a
	return a if indexA <= indexB else b

# How many inmates one room should hold at most. kind: the category of the room (see ROOM_LIMITS).
static func roomLimit(kind:String) -> int:
	return int(ROOM_LIMITS.get(kind, ROOM_LIMITS["other"]))

# ---- Budgets ----
# How many pawns of each kind the prison should keep in play at once, from the pawn limit BDCC allows. inmatesAvailable: how many inmates exist to be shown.
static func budgets(pawnCap:int, inmatesAvailable:int) -> Dictionary:
	var cap:int = int(max(0, pawnCap))
	return {
		"inmate": int(min(max(0, inmatesAvailable), int(round(float(cap) * SHARE_INMATES)))),
		"guard": int(min(MAX_GUARDS, max(2, int(round(float(cap) * SHARE_GUARDS))))) if cap > 0 else 0,
		"nurse": int(min(MAX_NURSES, max(1, int(round(float(cap) * SHARE_NURSES))))) if cap > 0 else 0,
		"engineer": int(min(MAX_ENGINEERS, max(1, int(round(float(cap) * SHARE_ENGINEERS))))) if cap > 0 else 0,
	}

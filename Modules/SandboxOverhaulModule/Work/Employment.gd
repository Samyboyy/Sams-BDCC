extends Reference
class_name Employment

# Prison jobs, daily shifts, wages and attendance. No game access here, so it can be tested on its own: callers pass the day number and the time of day.
#
# SandboxState.work = {
#   "job": "" | job id,                      the current job
#   "shift": {"day", "job", "state", "eligible", "reminded"}   today's shift: state is "" (not started), "completed", "missed" or "excused"
#   "warnings": int,                         consecutive warnings; a completed shift clears one, an unexcused miss adds one
#   "dismissed_until": int,                  -1, or the first day the player may apply again
#   "last_mining_pay_day": int,              the day the informal (no job) mining credit was last paid
#   "history": {"completed", "missed", "excused", "dismissals", "wages", "last_job"}   kept when leaving or being dismissed
# }
# One paid shift per day across all jobs: there is one shift record, and a job change keeps the day's result.

const WARNINGS_TO_DISMISS = 3
const DISMISS_DAYS = 3 # dismissed on day D: may apply again on day D + 3
const STATES = ["", "completed", "missed", "excused"]

# open and close are hours of the day (the arrival window), hours is how long the shift takes, stamina is the existing mining cost.
const JOBS = {
	"mining": {"name": "Mine worker", "workplace": "Mining shafts", "room": "mining_shafts_entering", "open": 8, "close": 10, "hours": 2, "wage": 3, "stamina": 40,
		"text": "You grab a pickaxe and spend the shift pushing minecarts and breaking rocks."},
	"workshop": {"name": "Workshop hand", "workplace": "Workshop", "room": "eng_workshop", "open": 10, "close": 12, "hours": 2, "wage": 4, "stamina": 40,
		"text": "You sort crates, bins and scrap in the workshop until the shift horn goes."},
	"laundry": {"name": "Laundry hand", "workplace": "Laundry", "room": "main_laundry", "open": 12, "close": 14, "hours": 2, "wage": 2, "stamina": 30,
		"text": "You feed the washing machines and fold uniforms for the whole shift."},
}
const JOB_ORDER = ["mining", "workshop", "laundry"]

var state

func _init(_state):
	state = _state

# ---- Pure helpers ----
static func isValidJob(jobID) -> bool:
	return (jobID is String) && JOBS.has(jobID)

static func jobName(jobID) -> String:
	return JOBS[jobID]["name"] if isValidJob(jobID) else "no job"

static func formatHour(hour:int) -> String:
	return "%02d:00" % hour

static func windowText(jobID:String) -> String:
	return formatHour(JOBS[jobID]["open"]) + "-" + formatHour(JOBS[jobID]["close"])

# Seconds since midnight, as BDCC reports them.
static func isWindowOpen(jobID:String, timeOfDay) -> bool:
	var t:int = posmod(int(timeOfDay), 86400)
	return t >= int(JOBS[jobID]["open"]) * 3600 && t < int(JOBS[jobID]["close"]) * 3600

static func isWindowClosed(jobID:String, timeOfDay) -> bool:
	return posmod(int(timeOfDay), 86400) >= int(JOBS[jobID]["close"]) * 3600

static func isNumberValue(value) -> bool:
	return (value is int || value is float) && !is_nan(float(value)) && !is_inf(float(value))

static func defaultShift() -> Dictionary:
	return {"day": -1, "job": "", "state": "", "eligible": false, "reminded": false}

static func defaults() -> Dictionary:
	return {"job": "", "shift": defaultShift(), "warnings": 0, "dismissed_until": -1, "last_mining_pay_day": -1,
		"history": {"completed": 0, "missed": 0, "excused": 0, "dismissals": 0, "wages": 0, "last_job": ""}}

static func sanitizeCount(value, default:int = 0) -> int:
	return int(max(0, round(float(value)))) if isNumberValue(value) else default

# Clean copy of a saved work dictionary: unknown jobs and states are dropped, numbers are clamped, nothing is aliased. Old saves have none.
static func sanitize(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(!(raw is Dictionary)):
		return result
	if(isValidJob(raw.get("job"))):
		result["job"] = raw["job"]
	var shift = raw.get("shift")
	if(shift is Dictionary):
		if(isNumberValue(shift.get("day"))):
			result["shift"]["day"] = int(round(float(shift["day"])))
		if(isValidJob(shift.get("job"))):
			result["shift"]["job"] = shift["job"]
		if((shift.get("state") is String) && STATES.has(shift["state"])):
			result["shift"]["state"] = shift["state"]
		result["shift"]["eligible"] = typeof(shift.get("eligible")) == TYPE_BOOL && shift["eligible"]
		result["shift"]["reminded"] = typeof(shift.get("reminded")) == TYPE_BOOL && shift["reminded"]
		if(result["shift"]["job"] == "" || result["shift"]["day"] < 0):
			result["shift"] = defaultShift()
	result["warnings"] = int(min(WARNINGS_TO_DISMISS - 1, sanitizeCount(raw.get("warnings"))))
	if(isNumberValue(raw.get("dismissed_until"))):
		result["dismissed_until"] = int(max(-1, round(float(raw["dismissed_until"]))))
	if(isNumberValue(raw.get("last_mining_pay_day"))):
		result["last_mining_pay_day"] = int(max(-1, round(float(raw["last_mining_pay_day"]))))
	var history = raw.get("history")
	if(history is Dictionary):
		for key in ["completed", "missed", "excused", "dismissals", "wages"]:
			result["history"][key] = sanitizeCount(history.get(key))
		if(isValidJob(history.get("last_job"))):
			result["history"]["last_job"] = history["last_job"]
	# A job with a dismissal pending is contradictory: being dismissed ends the job.
	if(result["dismissed_until"] >= 0):
		result["job"] = ""
	return result

# ---- Reading ----
func getJobID() -> String:
	return state.work["job"]

func isEmployed() -> bool:
	return state.work["job"] != ""

# The job whose workplace is this room, "" for any other room.
static func jobAtRoom(roomID) -> String:
	for jobID in JOB_ORDER:
		if(JOBS[jobID]["room"] == roomID):
			return jobID
	return ""

func isEmployedAt(roomID) -> bool:
	return isEmployed() && JOBS[getJobID()]["room"] == roomID

func getWarnings() -> int:
	return int(state.work["warnings"])

func getHistory() -> Dictionary:
	return state.work["history"].duplicate(true)

func getShift() -> Dictionary:
	return state.work["shift"].duplicate(true)

func isDismissed(day:int) -> bool:
	return state.work["dismissed_until"] >= 0 && day < state.work["dismissed_until"]

func getReapplyDay() -> int:
	return int(state.work["dismissed_until"])

# Today's result across all jobs: "not started", "completed", "missed" or "excused". Only meaningful for the day it is asked on.
func getShiftStatus(day:int) -> String:
	var shift:Dictionary = state.work["shift"]
	if(shift["day"] != day || shift["state"] == ""):
		return "not started"
	return shift["state"]

func isShiftCompleteToday(day:int) -> bool:
	return getShiftStatus(day) == "completed"

# Today's shift is still there to do: employed, eligible, not yet resolved.
func hasOpenShift(day:int) -> bool:
	var shift:Dictionary = state.work["shift"]
	return isEmployed() && shift["day"] == day && shift["state"] == "" && shift["eligible"] && shift["job"] == getJobID()

# ---- Applying and leaving ----
func canApply(jobID, day:int) -> Dictionary:
	if(!isValidJob(jobID)):
		return {"ok": false, "reason": "There is no such job."}
	if(isDismissed(day)):
		return {"ok": false, "reason": "You were dismissed. You can apply again on day " + str(getReapplyDay()) + "."}
	if(getJobID() == jobID):
		return {"ok": false, "reason": "You already have this job."}
	if(isEmployed()):
		return {"ok": false, "reason": "You already have a job. Leave it first."}
	return {"ok": true, "reason": ""}

# Takes the job. Today's shift is kept if it already has a result, so changing jobs never gives a second paid shift; otherwise a new shift
# is expected today only if the arrival window has not closed yet.
func accept(jobID, day:int, timeOfDay) -> Dictionary:
	var check:Dictionary = canApply(jobID, day)
	if(!check["ok"]):
		return check
	state.work["job"] = jobID
	var shift:Dictionary = state.work["shift"]
	if(shift["day"] == day && shift["state"] != ""):
		shift["job"] = jobID
		shift["eligible"] = false
	else:
		state.work["shift"] = {"day": day, "job": jobID, "state": "", "eligible": !isWindowClosed(jobID, timeOfDay), "reminded": false}
	return check

# Leaving keeps the history and the warnings. A shift not yet done today is dropped without any penalty.
func leave(_day:int) -> bool:
	if(!isEmployed()):
		return false
	state.work["job"] = ""
	var shift:Dictionary = state.work["shift"]
	if(shift["state"] == ""):
		state.work["shift"] = defaultShift()
	return true

# ---- Shifts ----
func canStartShift(jobID, day:int, timeOfDay) -> Dictionary:
	if(!isValidJob(jobID) || getJobID() != jobID):
		return {"ok": false, "reason": "This is not your workplace."}
	if(isShiftCompleteToday(day)):
		return {"ok": false, "reason": "You already finished your shift today."}
	var status:String = getShiftStatus(day)
	if(status == "missed" || status == "excused"):
		return {"ok": false, "reason": "Today's shift is over (" + status + ")."}
	if(!hasOpenShift(day)):
		return {"ok": false, "reason": "You have no shift to do today."}
	if(!isWindowOpen(jobID, timeOfDay)):
		return {"ok": false, "reason": "The arrival window has closed for today." if isWindowClosed(jobID, timeOfDay) else "Your shift starts between " + windowText(jobID) + ". Come back then."}
	return {"ok": true, "reason": ""}

# Records the finished shift and returns the wage to pay, or 0 when there is nothing to pay. The caller pays it, so a shift is paid exactly once.
func completeShift(jobID, day:int, timeOfDay) -> int:
	if(!canStartShift(jobID, day, timeOfDay)["ok"]):
		return 0
	var wage:int = int(JOBS[jobID]["wage"])
	state.work["shift"]["state"] = "completed"
	state.work["warnings"] = int(max(0, state.work["warnings"] - 1))
	var history:Dictionary = state.work["history"]
	history["completed"] += 1
	history["wages"] += wage
	history["last_job"] = jobID
	return wage

# An absence the player could not help (stocks, unconscious, captivity...). No wage, no warning. Does nothing without a pending shift today.
func recordExcused(day:int) -> bool:
	if(!hasOpenShift(day)):
		return false
	state.work["shift"]["state"] = "excused"
	state.work["history"]["excused"] += 1
	return true

# Informal mining pay: the vanilla credit is paid once per day. The ore is still mined afterwards, there is just no more pay.
func claimInformalMiningPay(day:int) -> bool:
	if(state.work["last_mining_pay_day"] == day):
		return false
	state.work["last_mining_pay_day"] = day
	return true

# ---- Time ----
# The shift is overdue when its window has closed (or the day has passed) and it never got a result.
func isShiftOverdue(day:int, timeOfDay) -> bool:
	var shift:Dictionary = state.work["shift"]
	if(!isEmployed() || shift["state"] != "" || !shift["eligible"] || shift["job"] != getJobID()):
		return false
	return shift["day"] < day || (shift["day"] == day && isWindowClosed(shift["job"], timeOfDay))

# Advances the work state to the given moment and returns what happened, in order, as dictionaries with a "type":
# "reminder" (the window just opened), "missed" (warnings), "excused", "dismissed" (reapplyDay), "reapply" (the dismissal is over).
# blockedReason is why the player cannot be at work right now ("" when nothing blocks them); it only matters when a shift is overdue.
func tick(day:int, timeOfDay, blockedReason:String) -> Array:
	var events:Array = []
	var work:Dictionary = state.work
	if(work["dismissed_until"] >= 0 && day >= work["dismissed_until"]):
		work["dismissed_until"] = -1
		events.append({"type": "reapply"})
	if(!isEmployed()):
		return events
	var shift:Dictionary = work["shift"]
	if(shift["day"] != day):
		if(shift["day"] < day && isShiftOverdue(day, timeOfDay)):
			events.append_array(resolve(blockedReason, day))
			if(!isEmployed()):
				return events
		work["shift"] = {"day": day, "job": work["job"], "state": "", "eligible": true, "reminded": false}
		shift = work["shift"]
	if(shift["state"] == "" && shift["eligible"]):
		var jobID:String = shift["job"]
		if(isWindowClosed(jobID, timeOfDay)):
			events.append_array(resolve(blockedReason, day))
		elif(isWindowOpen(jobID, timeOfDay) && !shift["reminded"]):
			shift["reminded"] = true
			events.append({"type": "reminder", "job": jobID})
	return events

# Gives the overdue shift its result. Excused when something blocked the player, otherwise missed: a warning, and a dismissal at three.
func resolve(blockedReason:String, day:int) -> Array:
	var work:Dictionary = state.work
	var jobID:String = work["shift"]["job"]
	if(blockedReason != ""):
		work["shift"]["state"] = "excused"
		work["history"]["excused"] += 1
		return [{"type": "excused", "job": jobID, "reason": blockedReason}]
	work["shift"]["state"] = "missed"
	work["history"]["missed"] += 1
	work["warnings"] += 1
	if(work["warnings"] < WARNINGS_TO_DISMISS):
		return [{"type": "missed", "job": jobID, "warnings": work["warnings"]}]
	work["job"] = ""
	work["warnings"] = 0
	work["dismissed_until"] = day + DISMISS_DAYS
	work["history"]["dismissals"] += 1
	return [{"type": "missed", "job": jobID, "warnings": WARNINGS_TO_DISMISS}, {"type": "dismissed", "job": jobID, "reapplyDay": work["dismissed_until"]}]

# ---- Text ----
static func eventText(event:Dictionary) -> String:
	var jobID:String = event.get("job", "")
	var name:String = jobName(jobID)
	match event["type"]:
		"reminder":
			return "[color=yellow]Work:[/color] Your " + name + " shift can start now. Be at the " + JOBS[jobID]["workplace"] + " before " + formatHour(JOBS[jobID]["close"]) + "."
		"missed":
			return "[color=red]Work:[/color] You missed your " + name + " shift. Warning " + str(event["warnings"]) + " of " + str(WARNINGS_TO_DISMISS) + "."
		"excused":
			return "[color=yellow]Work:[/color] You could not make your " + name + " shift (" + str(event["reason"]) + "). It is excused: no wage, no warning."
		"dismissed":
			return "[color=red]Work:[/color] You were dismissed from your job. You can apply again on day " + str(event["reapplyDay"]) + "."
		"reapply":
			return "[color=green]Work:[/color] You can apply for a job again."
	return ""

# Compact status for the Me screen and the job board.
func getStatusText(day:int, timeOfDay) -> String:
	var lines:Array = []
	if(isEmployed()):
		var jobID:String = getJobID()
		var job:Dictionary = JOBS[jobID]
		lines.append("Job: [b]" + job["name"] + "[/b] at the " + job["workplace"] + ". Shifts start " + windowText(jobID) + ", last about " + str(job["hours"]) + " hours, pay " + str(job["wage"]) + " credits.")
		var status:String = getShiftStatus(day)
		if(status == "completed"):
			lines.append("Today: [color=green]shift completed[/color].")
		elif(status == "missed"):
			lines.append("Today: [color=red]shift missed[/color].")
		elif(status == "excused"):
			lines.append("Today: [color=yellow]shift excused[/color].")
		elif(!hasOpenShift(day)):
			lines.append("Today: no shift (your next one is tomorrow).")
		elif(isWindowOpen(jobID, timeOfDay)):
			lines.append("Today: [color=yellow]ready to start[/color]. Go to the " + job["workplace"] + " and start your shift.")
		else:
			lines.append("Today: not started. Your window is " + windowText(jobID) + ".")
	elif(isDismissed(day)):
		lines.append("Job: none. You were dismissed and can apply again on day " + str(getReapplyDay()) + ".")
	else:
		lines.append("Job: none. The job board in the canteen lists what is open.")
	var warnings:int = getWarnings()
	if(warnings > 0):
		lines.append("[color=red]Warnings: " + str(warnings) + " of " + str(WARNINGS_TO_DISMISS) + "[/color] (a finished shift clears one; " + str(WARNINGS_TO_DISMISS) + " in a row means dismissal).")
	var history:Dictionary = state.work["history"]
	lines.append("Record: " + str(history["completed"]) + " shifts done, " + str(history["missed"]) + " missed, " + str(history["excused"]) + " excused. Earned " + str(history["wages"]) + " credits.")
	return PoolStringArray(lines).join("\n")

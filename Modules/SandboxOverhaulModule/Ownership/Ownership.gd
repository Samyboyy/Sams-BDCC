extends Reference

# The rules of ownership, on the saved state (SandboxState.ownership), with no game access so they can be tested on their own. It extends BDCC's own SoftSlavery (the player owned by an NPC)
# and the NPC slavery module (the player owning NPCs) instead of replacing them: the owner relationship, its levels and influence, the slaves and their skills all stay where they are. What
# this adds is a small layer of obligations, consequences, protection, ways out, and a few roles for the player's own slaves.
#
# Saved shape (all small, all sanitised on load):
#   "owner": {} when nobody owns the player, else {"id", "since" (day), "voluntary", "term_end" (day), "style", "next_checkin" (day),
#             "checkin": {"day", "state": pending|done|late|missed|excused, "reminded", "block"}, "demand": {} or one demand, "demand_clock": clock of the last demand,
#             "fulfilled": [days], "misses": [days], "warnings", "consequence", "consequence_day", "grace_until" (day), "confront": {} or {"level", "reason", "day"},
#             "wins": [separate days the player beat the owner], "owner_losses": [days the owner lost a fight], "aggressors": {id: {"day", "retaliated", "failed"}}, "final": {}}
#   "slaves": {characterID: {"role", "role_day", "since", "earn_day", "uncollected", "attended_day", "report": {}, "escape": {}, "last_treat", "last_attempt"}}
#   "last_release": {} or {"id", "day", "how"}
#
# Days are BDCC's day numbers (they change at 06:00). A "clock" is days * 86400 + seconds into the prison day (06:00 to 06:00, see DailyRoutine.axis), so it only ever grows.

const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")

const DAY = 86400
const HOUR = 3600
const DAY_START = 6 * 3600

# The nightly check-in, in "axis" seconds (21:00 is 75600; the small hours count as the evening before).
const REMINDER_AT = 20 * 3600 + 30 * 60
const WINDOW_START = 21 * 3600
const WINDOW_END = 23 * 3600
const LATE_UNTIL = 24 * 3600 + 30 * 60

const MISS_MEMORY_DAYS = 6
const GRACE_AFTER_DEFEAT = 2
const MIN_TERM_DAYS = 3
const HISTORY_MAX = 8
const RETALIATION_GAP_DAYS = 4
const RETALIATION_GIVE_UP = 2
const OWNER_LOSS_MEMORY_DAYS = 5
const BUYOUT_MIN = 30
const BUYOUT_MAX = 60
const PROTECTION_FLOOR = 0.35

const ROLES = ["free", "earner", "attendant", "rest"]
const ROLE_NAMES = {"free": "Free routine", "earner": "Earner", "attendant": "Attendant", "rest": "Rest"}
const ROLE_TEXT = {
	"free": "You may follow your ordinary prison routine. Report only when summoned.",
	"earner": "Work the afternoon prostitution locations and keep the agreed earnings for collection.",
	"attendant": "Stay around my cellblock during your free periods and help me if trouble starts.",
	"rest": "Avoid duties and recover.",
}
const ROLE_EFFECT = {
	"free": "Their trust slowly recovers.",
	"earner": "About 2 to 4 credits a day (less when several earn at once), and it wears their trust down.",
	"attendant": "They wait in your cell block's common hall in the morning and evening, and may help if you are attacked while they are there.",
	"rest": "Their injuries, stamina and trust recover.",
}
const ROLE_TRANSITION_SECONDS = 1800 # a new role takes over half an hour after it is given, so nobody changes rooms on the spot

const NIGHTS = ["own", "player", "order"]
const NIGHT_NAMES = {"own": "Sleep in their own cell", "player": "Sleep in your cell each night", "order": "Keep their own cell, report only when ordered"}
const NIGHT_TEXT = {
	"own": "Sleep in your own cell.",
	"player": "Sleep in my cell each night.",
	"order": "Keep your own cell and report only when ordered.",
}
const NIGHT_START = 20 * 3600 + 1800 # they start walking over at 20:30
const NIGHT_END = 7 * 3600 # and leave for their day at 07:00
const ESCAPE_GRACE_DAYS = 2 # nobody is judged neglected or starts planning to leave in their first days
const EARN_MIN = 2
const EARN_MAX = 4
const EARN_SECOND_MIN = 1 # the second earner of a day competes with the first for the same customers: 1 to 3
const EARN_SECOND_MAX = 3
const EARN_FURTHER = 1 # every further earner: 1
const EARN_DAY_CAP = 8 # all earners together, per day

const DEMAND_TYPES = ["credits", "item", "contraband", "shift", "report", "defeat"]

var state

func _init(_state):
	state = _state

# ---- Shape ----
static func defaultOwner() -> Dictionary:
	return {"id": "", "since": 0, "voluntary": false, "term_end": 0, "style": StyleScript.CONTROLLING, "next_checkin": 0,
		"checkin": {"day": -1, "state": "", "reminded": false, "block": "", "outcome": "", "intent": ""}, "demand": {}, "demand_id": 0, "demand_clock": -1000000, "fulfilled": [], "misses": [], "warnings": 0,
		"consequence": "", "consequence_day": -1, "grace_until": -1, "confront": {}, "wins": [], "owner_losses": [], "aggressors": {}, "final": {}, "last_help": -100, "meeting": {}, "last_intimacy": -100, "last_done": {}, "last_praise": -100, "pregnancy": ""}

static func defaultSlave() -> Dictionary:
	return {"role": "free", "role_day": -1, "role_from": -1, "since": 0, "earn_day": -1, "uncollected": 0, "attended_day": -1, "report": {}, "escape": {}, "last_treat": -1, "last_attempt": -100,
		"setup": "set", "night": "own", "aftermath": {}, "wait_cell": false}

static func defaults() -> Dictionary:
	return {"owner": {}, "slaves": {}, "last_release": {}, "tick_day": -1, "defeated": {}, "disputes": {}, "last_dispute": -100, "pc_defeat": {}, "earn_pool": {"day": -1, "count": 0, "paid": 0}}

static func isNumberValue(value) -> bool:
	return (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) && !is_nan(float(value)) && !is_inf(float(value))

static func sanitizeInt(value, minimum:int, maximum:int, default:int) -> int:
	return int(clamp(round(float(value)), minimum, maximum)) if isNumberValue(value) else default

static func sanitizeString(value, allowed:Array, default:String) -> String:
	return str(value) if ((value is String) && allowed.has(value)) else default

static func sanitizeDays(value, limit:int = HISTORY_MAX) -> Array:
	var result:Array = []
	if(value is Array):
		for entry in value:
			if(isNumberValue(entry) && result.size() < limit):
				result.append(sanitizeInt(entry, -1, 1000000, -1))
	return result

static func sanitizeDemand(raw) -> Dictionary:
	if(!(raw is Dictionary) || !(raw.get("type") is String) || !DEMAND_TYPES.has(raw["type"])):
		return {}
	var phase:String = sanitizeString(raw.get("state"), ["offered", "active", "ready"], "")
	if(phase == ""):
		return {}
	return {"id": sanitizeInt(raw.get("id"), 0, 1000000000, 0), "type": raw["type"], "state": phase, "amount": sanitizeInt(raw.get("amount"), 0, 99, 0),
		"item": str(raw.get("item")) if (raw.get("item") is String) else "", "target": str(raw.get("target")) if (raw.get("target") is String) else "",
		"created": sanitizeInt(raw.get("created"), -1000000, 1000000000, 0), "deadline": sanitizeInt(raw.get("deadline"), -1000000, 1000000000, 0),
		"negotiated": typeof(raw.get("negotiated")) == TYPE_BOOL && raw["negotiated"], "at": sanitizeInt(raw.get("at"), 0, 200000, 0), "day": sanitizeInt(raw.get("day"), 0, 1000000, 0), "block": str(raw.get("block")) if (raw.get("block") is String) else ""}

static func sanitizeOwner(raw) -> Dictionary:
	if(!(raw is Dictionary) || !(raw.get("id") is String) || raw["id"] == "" || raw["id"] == "pc"):
		return {}
	var result:Dictionary = defaultOwner()
	result["id"] = raw["id"]
	result["since"] = sanitizeInt(raw.get("since"), 0, 1000000, 0)
	result["voluntary"] = typeof(raw.get("voluntary")) == TYPE_BOOL && raw["voluntary"]
	result["term_end"] = sanitizeInt(raw.get("term_end"), 0, 1000000, result["since"])
	result["style"] = sanitizeString(raw.get("style"), StyleScript.STYLES, StyleScript.CONTROLLING)
	result["next_checkin"] = sanitizeInt(raw.get("next_checkin"), 0, 1000000, result["since"])
	result["last_help"] = sanitizeInt(raw.get("last_help"), -100, 1000000, -100)
	result["last_intimacy"] = sanitizeInt(raw.get("last_intimacy"), -100, 1000000, -100)
	result["last_praise"] = sanitizeInt(raw.get("last_praise"), -100, 1000000, -100)
	result["pregnancy"] = sanitizeString(raw.get("pregnancy"), ["", "noticed", "birth"], "")
	var lastDone = raw.get("last_done")
	if(lastDone is Dictionary && isNumberValue(lastDone.get("day"))):
		result["last_done"] = {"day": sanitizeInt(lastDone.get("day"), 0, 1000000, 0), "type": str(lastDone.get("type")).substr(0, 20) if (lastDone.get("type") is String) else ""}
	var meeting = raw.get("meeting")
	if(meeting is Dictionary && isNumberValue(meeting.get("day"))):
		result["meeting"] = {"day": sanitizeInt(meeting.get("day"), 0, 1000000, 0), "state": sanitizeString(meeting.get("state"), ["pending", "postponed"], "pending"), "purpose": sanitizeString(MEETING_LEGACY.get(meeting.get("purpose"), meeting.get("purpose")), MEETING_PURPOSES, "attention"), "told": typeof(meeting.get("told")) == TYPE_BOOL && meeting["told"], "postponed": sanitizeInt(meeting.get("postponed"), 0, 20, 0)}
	var checkin = raw.get("checkin")
	if(checkin is Dictionary):
		result["checkin"] = {"day": sanitizeInt(checkin.get("day"), -1, 1000000, -1), "state": sanitizeString(checkin.get("state"), ["pending", "done", "late", "missed", "excused"], ""),
			"reminded": typeof(checkin.get("reminded")) == TYPE_BOOL && checkin["reminded"], "block": str(checkin.get("block")) if (checkin.get("block") is String) else ""}
		if(checkin.has("outcome") || checkin.has("intent")):
			result["checkin"]["outcome"] = sanitizeString(checkin.get("outcome"), CHECKIN_OUTCOMES, "")
			result["checkin"]["intent"] = sanitizeString(checkin.get("intent"), ["ask", "demand", "force"], "")
	result["demand"] = sanitizeDemand(raw.get("demand"))
	result["demand_id"] = sanitizeInt(raw.get("demand_id"), 0, 1000000000, 0)
	result["demand_clock"] = sanitizeInt(raw.get("demand_clock"), -1000000, 1000000000, -1000000)
	result["fulfilled"] = sanitizeDays(raw.get("fulfilled"))
	result["misses"] = sanitizeDays(raw.get("misses"))
	result["warnings"] = sanitizeInt(raw.get("warnings"), 0, 20, 0)
	result["consequence"] = str(raw.get("consequence")).substr(0, 120) if (raw.get("consequence") is String) else ""
	result["consequence_day"] = sanitizeInt(raw.get("consequence_day"), -1, 1000000, -1)
	result["grace_until"] = sanitizeInt(raw.get("grace_until"), -1, 1000000, -1)
	var confront = raw.get("confront")
	if(confront is Dictionary && isNumberValue(confront.get("level"))):
		result["confront"] = {"level": sanitizeInt(confront.get("level"), 1, 3, 1), "reason": str(confront.get("reason")).substr(0, 120) if (confront.get("reason") is String) else "", "day": sanitizeInt(confront.get("day"), -1, 1000000, -1)}
	result["wins"] = sanitizeDays(raw.get("wins"))
	result["owner_losses"] = sanitizeDays(raw.get("owner_losses"))
	var aggressors = raw.get("aggressors")
	if(aggressors is Dictionary):
		for id in aggressors:
			if((id is String) && id != "" && id != "pc" && aggressors[id] is Dictionary && result["aggressors"].size() < 12):
				result["aggressors"][id] = {"day": sanitizeInt(aggressors[id].get("day"), -1, 1000000, -1), "retaliated": sanitizeInt(aggressors[id].get("retaliated"), -1000, 1000000, -1000), "failed": sanitizeInt(aggressors[id].get("failed"), 0, 20, 0)}
	var final = raw.get("final")
	if(final is Dictionary && (final.get("type") is String) && DEMAND_TYPES.has(final["type"])):
		result["final"] = sanitizeDemand(final)
	return result

static func sanitizeSlave(raw) -> Dictionary:
	if(!(raw is Dictionary)):
		return {}
	var result:Dictionary = defaultSlave()
	result["role"] = sanitizeString(raw.get("role"), ROLES, "free")
	result["role_day"] = sanitizeInt(raw.get("role_day"), -1, 1000000, -1)
	result["role_from"] = sanitizeInt(raw.get("role_from"), -1, 100000000, -1)
	result["setup"] = sanitizeString(raw.get("setup"), ["awaiting", "set"], "set")
	result["night"] = sanitizeString(raw.get("night"), NIGHTS, "own")
	result["wait_cell"] = typeof(raw.get("wait_cell")) == TYPE_BOOL && raw["wait_cell"]
	var after = raw.get("aftermath")
	if(after is Dictionary && AFTERMATH_KINDS.has(after.get("kind"))):
		result["aftermath"] = {"kind": after["kind"], "day": sanitizeInt(after.get("day"), 0, 1000000, 0)}
	result["since"] = sanitizeInt(raw.get("since"), 0, 1000000, 0)
	result["earn_day"] = sanitizeInt(raw.get("earn_day"), -1, 1000000, -1)
	result["uncollected"] = sanitizeInt(raw.get("uncollected"), 0, 99, 0)
	result["attended_day"] = sanitizeInt(raw.get("attended_day"), -1, 1000000, -1)
	result["last_treat"] = sanitizeInt(raw.get("last_treat"), -1, 1000000, -1)
	result["last_attempt"] = sanitizeInt(raw.get("last_attempt"), -100, 1000000, -100)
	var report = raw.get("report")
	if(report is Dictionary && isNumberValue(report.get("day"))):
		result["report"] = {"day": sanitizeInt(report.get("day"), 0, 1000000, 0), "state": sanitizeString(report.get("state"), ["pending", "done", "missed", "cancelled"], "pending"), "refused": typeof(report.get("refused")) == TYPE_BOOL && report["refused"], "delayed": typeof(report.get("delayed")) == TYPE_BOOL && report["delayed"]}
	var escape = raw.get("escape")
	if(escape is Dictionary && escape.get("stage") is String && ["warning", "attempt"].has(escape["stage"])):
		result["escape"] = {"stage": escape["stage"], "day": sanitizeInt(escape.get("day"), 0, 1000000, 0), "why": str(escape.get("why")).substr(0, 60) if (escape.get("why") is String) else ""}
	return result

static func sanitize(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(!(raw is Dictionary)):
		return result
	result["owner"] = sanitizeOwner(raw.get("owner"))
	var slaves = raw.get("slaves")
	if(slaves is Dictionary):
		for id in slaves:
			if((id is String) && id != "" && id != "pc" && result["slaves"].size() < 60):
				var entry:Dictionary = sanitizeSlave(slaves[id])
				if(!entry.empty()):
					result["slaves"][id] = entry
	result["tick_day"] = sanitizeInt(raw.get("tick_day"), -1, 1000000, -1)
	result["last_dispute"] = sanitizeInt(raw.get("last_dispute"), -100, 1000000, -100)
	var pcDefeat = raw.get("pc_defeat")
	if(pcDefeat is Dictionary && isNumberValue(pcDefeat.get("clock")) && (pcDefeat.get("by") is String)):
		result["pc_defeat"] = {"clock": sanitizeInt(pcDefeat.get("clock"), 0, 100000000, 0), "by": str(pcDefeat["by"]).substr(0, 60), "handled": typeof(pcDefeat.get("handled")) == TYPE_BOOL && pcDefeat["handled"], "started": sanitizeInt(pcDefeat.get("started"), -1, 100000000, -1)}
	var disputes = raw.get("disputes")
	if(disputes is Dictionary):
		for id in disputes:
			if((id is String) && id != "" && id != "pc" && disputes[id] is Dictionary && result["disputes"].size() < 20):
				result["disputes"][id] = {"day": sanitizeInt(disputes[id].get("day"), -100, 1000000, -100), "result": sanitizeString(disputes[id].get("result"), DISPUTE_RESULTS, "owner_wins")}
	var defeated = raw.get("defeated")
	if(defeated is Dictionary):
		for id in defeated:
			if((id is String) && id != "" && id != "pc" && defeated[id] is Dictionary && result["defeated"].size() < 30):
				result["defeated"][id] = {"day": sanitizeInt(defeated[id].get("day"), 0, 1000000, 0), "kind": sanitizeString(defeated[id].get("kind"), ["fight", "surrender"], "fight")}
	var pool = raw.get("earn_pool")
	if(pool is Dictionary):
		result["earn_pool"] = {"day": sanitizeInt(pool.get("day"), -1, 1000000, -1), "count": sanitizeInt(pool.get("count"), 0, 1000, 0), "paid": sanitizeInt(pool.get("paid"), 0, EARN_DAY_CAP, 0)}
	var last = raw.get("last_release")
	if(last is Dictionary && (last.get("id") is String)):
		result["last_release"] = {"id": last["id"], "day": sanitizeInt(last.get("day"), -1, 1000000, -1), "how": str(last.get("how")).substr(0, 40) if (last.get("how") is String) else ""}
	return result

# ---- Time ----
static func clockOf(day:int, axisNow:int) -> int:
	return day * DAY + axisNow - DAY_START

# ---- Reading ----
func data() -> Dictionary:
	return state.ownership

func record() -> Dictionary:
	return state.ownership["owner"]

func hasOwner() -> bool:
	return !state.ownership["owner"].empty()

func ownerID() -> String:
	return str(state.ownership["owner"].get("id", ""))

func style() -> String:
	return str(state.ownership["owner"].get("style", StyleScript.CONTROLLING))

func styleParams() -> Dictionary:
	return StyleScript.params(style())

func isOwner(characterID) -> bool:
	return hasOwner() && ownerID() == characterID

# ---- Beginning and ending ----
# The player is owned by this character from now on. next_checkin: the first night the owner expects the player (tonight if it is still early, else tomorrow).
func begin(characterID:String, day:int, voluntary:bool, ownerStyle:String, axisNow:int) -> bool:
	if(characterID == "" || characterID == "pc"):
		return false
	var rec:Dictionary = defaultOwner()
	rec["id"] = characterID
	rec["since"] = day
	rec["voluntary"] = voluntary
	rec["term_end"] = day + MIN_TERM_DAYS
	rec["style"] = ownerStyle if StyleScript.isStyle(ownerStyle) else StyleScript.CONTROLLING
	rec["next_checkin"] = day if axisNow < REMINDER_AT else day + 1
	state.ownership["owner"] = rec
	return true

# Ownership ends (released, bought out, escaped, fought free, or BDCC ended it). The reason is kept for display.
func end(day:int, how:String) -> Dictionary:
	var rec:Dictionary = state.ownership["owner"]
	var gone:Dictionary = {"id": str(rec.get("id", "")), "day": day, "how": how}
	state.ownership["owner"] = {}
	state.ownership["last_release"] = gone
	return gone

# ---- The nightly check-in ----
func checkin() -> Dictionary:
	return state.ownership["owner"].get("checkin", {})

func isCheckinPending(day:int) -> bool:
	var c:Dictionary = checkin()
	return hasOwner() && int(c.get("day", -1)) == day && str(c.get("state", "")) == "pending"

# Creates tonight's check-in if the owner expects one. Returns true when it was just created.
func startCheckin(day:int, axisNow:int) -> bool:
	if(!hasOwner()):
		return false
	var rec:Dictionary = state.ownership["owner"]
	if(day < int(rec["next_checkin"]) || int(rec["checkin"].get("day", -1)) == day || axisNow > LATE_UNTIL):
		return false
	rec["checkin"] = {"day": day, "state": "pending", "reminded": false, "block": "", "outcome": "", "intent": ""}
	return true

func shouldRemind(day:int, axisNow:int) -> bool:
	return isCheckinPending(day) && !bool(checkin().get("reminded", false)) && axisNow >= REMINDER_AT && axisNow <= LATE_UNTIL

func markReminded() -> void:
	if(hasOwner()):
		state.ownership["owner"]["checkin"]["reminded"] = true

# Something physically kept the player from going (stocks, unconsciousness, ...) while the check-in was open. One sighting is enough to excuse the night.
func noteBlock(day:int, reason:String) -> void:
	if(reason != "" && isCheckinPending(day) && str(checkin().get("block", "")) == ""):
		state.ownership["owner"]["checkin"]["block"] = reason

# "before" (nothing yet), "early" (from the reminder until 21:00), "open" (21:00 to 23:00), "late" (until 00:30), "closed".
static func windowState(axisNow:int) -> String:
	if(axisNow < REMINDER_AT):
		return "before"
	if(axisNow < WINDOW_START):
		return "early"
	if(axisNow <= WINDOW_END):
		return "open"
	if(axisNow <= LATE_UNTIL):
		return "late"
	return "closed"

func nextCheckinAfter(day:int) -> int:
	return day + int(styleParams()["checkin_every"])

# The player stands in the owner's cell and speaks to them. Returns {"ok", "timing": "early|on_time|late", "reason"}.
func reportIn(day:int, axisNow:int, inCellWithOwner:bool) -> Dictionary:
	if(!isCheckinPending(day)):
		return {"ok": false, "timing": "", "reason": "none"}
	if(!inCellWithOwner):
		return {"ok": false, "timing": "", "reason": "not_there"}
	var window:String = windowState(axisNow)
	if(window == "before"):
		return {"ok": false, "timing": "", "reason": "too_soon"}
	if(window == "closed"):
		return {"ok": false, "timing": "", "reason": "closed"}
	var timing:String = "early" if window == "early" else ("on_time" if window == "open" else "late")
	var rec:Dictionary = state.ownership["owner"]
	rec["checkin"]["state"] = "late" if timing == "late" else "done"
	rec["next_checkin"] = nextCheckinAfter(day)
	recordFulfilled(day)
	return {"ok": true, "timing": timing, "reason": ""}

# Required nights that have no record at all (the clock jumped over them): the next required night is in the past. Every such night is moved past once (so none is ever counted twice); the latest three are returned.
func skippedNights(day:int) -> Array:
	var result:Array = []
	if(!hasOwner()):
		return result
	var rec:Dictionary = state.ownership["owner"]
	var guard:int = 0
	while(int(rec["next_checkin"]) < day && guard < 500):
		result.append(int(rec["next_checkin"]))
		rec["next_checkin"] = int(rec["next_checkin"]) + int(styleParams()["checkin_every"])
		guard += 1
	return result.slice(int(max(0, result.size() - 3)), result.size()) # (every night is passed once; only the latest three are held against the player)

# Closes an open check-in that is over (the window passed, or the day changed). Returns "" (nothing to close), "excused" or "missed".
func closeCheckin(day:int, axisNow:int, excuse:String) -> String:
	if(!hasOwner()):
		return ""
	var rec:Dictionary = state.ownership["owner"]
	var c:Dictionary = rec["checkin"]
	if(str(c.get("state", "")) != "pending"):
		return ""
	var over:bool = int(c.get("day", -1)) < day || axisNow > LATE_UNTIL
	if(!over):
		return ""
	var reason:String = excuse if excuse != "" else str(c.get("block", ""))
	rec["next_checkin"] = max(int(rec["next_checkin"]), nextCheckinAfter(int(c.get("day", day))))
	if(reason != ""):
		c["state"] = "excused"
		c["block"] = reason
		return "excused"
	c["state"] = "missed"
	return "missed"

# ---- Compliance ----
func recordFulfilled(day:int) -> void:
	var list:Array = state.ownership["owner"]["fulfilled"]
	list.append(day)
	while(list.size() > HISTORY_MAX):
		list.pop_front()

func recentFulfilled(day:int) -> int:
	var count:int = 0
	for entry in state.ownership["owner"].get("fulfilled", []):
		if(day - int(entry) <= MISS_MEMORY_DAYS):
			count += 1
	return count

func recentMisses(day:int) -> int:
	var count:int = 0
	for entry in state.ownership["owner"].get("misses", []):
		if(day - int(entry) <= MISS_MEMORY_DAYS):
			count += 1
	return count

# A missed obligation: a warning first, then a bigger step as they pile up (how fast depends on the style). The owner deals with it only the next time they meet the player.
# Returns the level (1 verbal warning, 2 compensation, 3 punishment) now waiting.
func recordMiss(day:int, reason:String) -> int:
	var rec:Dictionary = state.ownership["owner"]
	var misses:Array = []
	for entry in rec["misses"]:
		if(day - int(entry) <= MISS_MEMORY_DAYS):
			misses.append(entry)
	misses.append(day)
	while(misses.size() > HISTORY_MAX):
		misses.pop_front()
	rec["misses"] = misses
	rec["warnings"] = misses.size()
	var level:int = int(clamp(int(styleParams().get("first_level", 1)) + int(floor(float(misses.size() - 1) * float(styleParams()["escalation"]))), 1, 3))
	var waiting:Dictionary = rec["confront"]
	var finalLevel:int = int(max(level, int(waiting.get("level", 1)))) if !waiting.empty() else level
	rec["confront"] = {"level": finalLevel, "reason": reason, "day": day}
	return int(rec["confront"]["level"])

# The owner is grateful: one recent minor warning is forgiven (a verbal warning still waiting, or the latest miss), and when there is nothing to forgive the next ordinary demand comes a day later.
# Returns "warning" or "demand" (what changed), or "" when nothing did.
func showGratitude(clock:int, day:int) -> String:
	if(!hasOwner()):
		return ""
	var rec:Dictionary = state.ownership["owner"]
	var misses:Array = rec["misses"]
	var waiting:Dictionary = rec["confront"]
	if(!waiting.empty() && int(waiting.get("level", 1)) == 1):
		rec["confront"] = {}
		if(!misses.empty()):
			misses.pop_back()
			rec["warnings"] = misses.size()
		return "warning"
	if(waiting.empty() && recentMisses(day) > 0):
		misses.pop_back()
		rec["warnings"] = misses.size()
		return "warning"
	var gap:int = int(max(2, int(styleParams()["demand_gap"])))
	rec["demand_clock"] = int(max(int(rec["demand_clock"]), clock - (gap - 1) * DAY))
	return "demand"

func pendingConfront() -> Dictionary:
	return state.ownership["owner"].get("confront", {}) if hasOwner() else {}

func inGrace(day:int) -> bool:
	return hasOwner() && day <= int(state.ownership["owner"]["grace_until"])

func setConsequence(text:String, day:int) -> void:
	if(hasOwner()):
		state.ownership["owner"]["consequence"] = text.substr(0, 120)
		state.ownership["owner"]["consequence_day"] = day

func clearConfront(text:String, day:int) -> void:
	if(!hasOwner()):
		return
	state.ownership["owner"]["confront"] = {}
	setConsequence(text, day)

# The owner may hold back from a confrontation they do not dare to start alone: they are afraid of the player and nothing makes up for it (no trust to lean on).
static func hesitates(ownerFear:float, ownerTrust:float, ownerAlone:bool) -> bool:
	return ownerAlone && ownerFear >= 60.0 && ownerTrust < 30.0

# The player beat the owner while the owner was enforcing something. The consequence ends, the owner backs off for two days, the win counts towards a release (once per day).
func recordOwnerDefeat(day:int) -> void:
	if(!hasOwner()):
		return
	var rec:Dictionary = state.ownership["owner"]
	rec["confront"] = {}
	rec["grace_until"] = max(int(rec["grace_until"]), day + GRACE_AFTER_DEFEAT)
	if(!rec["wins"].has(day)):
		rec["wins"].append(day)
	while(rec["wins"].size() > HISTORY_MAX):
		rec["wins"].pop_front()
	setConsequence("The owner was beaten and is keeping their distance.", day)

func distinctWins() -> int:
	var seen:Dictionary = {}
	for entry in state.ownership["owner"].get("wins", []):
		seen[int(entry)] = true
	return seen.size()

func recordOwnerLoss(day:int) -> void:
	if(!hasOwner()):
		return
	var list:Array = state.ownership["owner"]["owner_losses"]
	list.append(day)
	while(list.size() > HISTORY_MAX):
		list.pop_front()

func recentOwnerLosses(day:int) -> int:
	var count:int = 0
	for entry in state.ownership["owner"].get("owner_losses", []):
		if(day - int(entry) <= OWNER_LOSS_MEMORY_DAYS):
			count += 1
	return count

# ---- Negotiation (how open the owner is to easing something) ----
# Directed feelings of the owner towards the player (-100..100 each, fear 0..100), the owner's style, and how the player has behaved lately. No dice: the same facts give the same answer.
func openness(trust:float, respect:float, affection:float, day:int) -> float:
	var score:float = 0.3 * trust / 100.0 + 0.25 * respect / 100.0 + 0.2 * affection / 100.0 + float(styleParams()["willingness"])
	score += 0.05 * float(min(recentFulfilled(day), 4)) - 0.08 * float(min(recentMisses(day), 4))
	return score

static func opennessWord(score:float) -> String:
	if(score >= 0.35):
		return "open to it"
	if(score >= 0.2):
		return "might hear you out"
	return "not in the mood"

const OPEN_ENOUGH = 0.2

# ---- Demands ----
func demand() -> Dictionary:
	return state.ownership["owner"].get("demand", {}) if hasOwner() else {}

func hasDemand() -> bool:
	return !demand().empty()

func nextDemandID() -> int:
	var id:int = int(state.ownership["owner"].get("demand_id", 0)) + 1
	state.ownership["owner"]["demand_id"] = id
	return id

# At most one demand at a time, a style-dependent gap (never under two days) since the last, never while a confrontation waits or during a grace period.
func canIssueDemand(clock:int, day:int) -> bool:
	if(!hasOwner() || hasDemand() || !pendingConfront().empty() || inGrace(day)):
		return false
	var gap:int = int(max(2, int(styleParams()["demand_gap"])))
	return clock - int(state.ownership["owner"]["demand_clock"]) >= gap * DAY

# Which demand kinds this owner may ask for given what is actually possible right now.
# facts: {"credits", "ordinaryItem" (item ID or ""), "contraband" (item ID or ""), "canShift", "targets": [valid characterIDs], "axisNow"}
func demandPool(facts:Dictionary) -> Array:
	var ownerStyle:String = style()
	var pool:Array = []
	if(int(facts.get("credits", 0)) >= 3):
		pool.append("credits")
	if(ownerStyle != StyleScript.LENIENT && str(facts.get("ordinaryItem", "")) != ""):
		pool.append("item")
	if(ownerStyle == StyleScript.HARSH && str(facts.get("contraband", "")) != ""):
		pool.append("contraband")
	if(bool(facts.get("canShift", false))):
		pool.append("shift")
	pool.append("report")
	var targetList:Array = facts.get("targets", [])
	if(ownerStyle != StyleScript.LENIENT && !targetList.empty()):
		pool.append("defeat")
	return pool

static func pickIndex(seedText:String, count:int) -> int:
	if(count <= 0):
		return 0
	var h:int = seedText.hash()
	h = h ^ (h >> 16)
	h = h * 73244475
	h = h ^ (h >> 16)
	return posmod(h, count)

# Creates the owner's next demand (state "offered": the owner has it in mind and will say it when they meet the player). Returns it, or {} when nothing is possible or allowed.
func makeDemand(clock:int, day:int, facts:Dictionary) -> Dictionary:
	if(!canIssueDemand(clock, day)):
		return {}
	var pool:Array = demandPool(facts)
	if(pool.empty()):
		return {}
	var ownerStyle:String = style()
	var type:String = str(pool[pickIndex(str(day) + state.ownership["owner"]["id"] + "demand", pool.size())])
	var d:Dictionary = {"id": nextDemandID(), "type": type, "state": "offered", "amount": 0, "item": "", "target": "", "created": clock, "deadline": clock + 36 * HOUR, "negotiated": false, "at": 0, "day": 0, "block": ""}
	match(type):
		"credits":
			var low:int = 3 if ownerStyle != StyleScript.HARSH else 5
			var high:int = 4 if ownerStyle == StyleScript.LENIENT else 6
			d["amount"] = int(min(low + pickIndex(str(day) + "amount", int(max(1, high - low + 1))), int(facts.get("credits", 3))))
		"item":
			d["item"] = str(facts["ordinaryItem"])
		"contraband":
			d["item"] = str(facts["contraband"])
		"shift":
			d["deadline"] = clock + 48 * HOUR
		"report":
			var starts:Array = [19 * 3600, 20 * 3600, 21 * 3600]
			d["at"] = int(starts[pickIndex(str(day) + "report", starts.size())])
			var axisNow:int = int(facts.get("axisNow", 0))
			var targetDay:int = day if axisNow + HOUR < d["at"] else day + 1
			d["deadline"] = clockOf(targetDay, int(d["at"])) + 90 * 60
			d["day"] = targetDay
		"defeat":
			var targets:Array = facts.get("targets", [])
			d["target"] = str(targets[pickIndex(str(day) + "target", targets.size())])
			d["deadline"] = clock + 48 * HOUR
	state.ownership["owner"]["demand"] = sanitizeDemand(d)
	state.ownership["owner"]["demand_clock"] = clock
	return state.ownership["owner"]["demand"].duplicate(true)

func acceptDemand() -> bool:
	if(!hasDemand() || demand()["state"] != "offered"):
		return false
	state.ownership["owner"]["demand"]["state"] = "active"
	return true

# Asks for easier terms. One try per demand. Returns {"result": "eased|extended|replaced|refused|already", "amount", "type"}.
func negotiateDemand(score:float, day:int) -> Dictionary:
	if(!hasDemand() || demand()["state"] != "offered"):
		return {"result": "none"}
	var d:Dictionary = state.ownership["owner"]["demand"]
	if(d["negotiated"]):
		return {"result": "already"}
	d["negotiated"] = true
	if(score < OPEN_ENOUGH):
		return {"result": "refused"}
	match(str(d["type"])):
		"credits":
			d["amount"] = int(max(3, int(ceil(float(d["amount"]) / 2.0))))
			d["deadline"] += 24 * HOUR
			return {"result": "eased", "amount": d["amount"], "type": d["type"]}
		"item", "contraband", "shift", "defeat":
			if(str(d["type"]) in ["contraband", "defeat"]):
				# an unsuitable task is swapped for something plainer: a small payment
				d["type"] = "credits"
				d["amount"] = 3
				d["item"] = ""
				d["target"] = ""
				d["deadline"] += 12 * HOUR
				return {"result": "replaced", "amount": 3, "type": "credits"}
			d["deadline"] += 24 * HOUR
			return {"result": "extended", "type": d["type"]}
		"report":
			d["deadline"] += 24 * HOUR
			d["day"] = int(d.get("day", day)) + 1
			return {"result": "extended", "type": "report"}
	return {"result": "refused"}

# The player says no. It counts as a miss (a warning first), and the demand is gone.
func refuseDemand(day:int) -> int:
	if(!hasDemand()):
		return 0
	state.ownership["owner"]["demand"] = {}
	return recordMiss(day, "refused a demand")

# A finished task (a shift, a beaten target) waits to be reported in person.
func markDemandReady() -> bool:
	if(!hasDemand() || demand()["state"] != "active" || !(str(demand()["type"]) in ["shift", "defeat"])):
		return false
	state.ownership["owner"]["demand"]["state"] = "ready"
	return true

# The demand is done (the caller took the payment or item first). Rewards once, and clears the demand. Returns {"type", "trust", "respect"} or {} when there was nothing to complete.
func completeDemand(day:int) -> Dictionary:
	if(!hasDemand() || !(demand()["state"] in ["active", "ready"])):
		return {}
	var d:Dictionary = state.ownership["owner"]["demand"]
	var type:String = str(d["type"])
	state.ownership["owner"]["demand"] = {}
	state.ownership["owner"]["last_done"] = {"day": day, "type": type}
	recordFulfilled(day)
	# One modest reward for every kind of demand: Trust +3, Respect +2, Affection +1, and one more Respect for a hard or dangerous one (beating somebody, carrying contraband).
	return {"type": type, "trust": 3.0, "respect": 2.0 + (1.0 if type in ["defeat", "contraband"] else 0.0), "affection": 1.0}

# Time passes. A demand past its deadline is a miss (a warning), or is dropped without blame if something kept the player from it. Returns "" / "excused" / "missed".
func expireDemand(clock:int, day:int, excuse:String) -> String:
	if(!hasDemand()):
		return ""
	var d:Dictionary = demand()
	if(clock <= int(d["deadline"])):
		return ""
	var reason:String = excuse if excuse != "" else str(d.get("block", ""))
	var wasOffered:bool = d["state"] == "offered"
	state.ownership["owner"]["demand"] = {}
	if(reason != "" || wasOffered):
		return "excused" # an offer the owner never got to make is never held against the player
	recordMiss(day, "did not do what was asked")
	return "missed"

func noteDemandBlock(reason:String) -> void:
	if(reason != "" && hasDemand() && str(demand().get("block", "")) == ""):
		state.ownership["owner"]["demand"]["block"] = reason

# ---- Confrontations ----
static func compensationFor(styleName:String) -> int:
	return {"lenient": 3, "controlling": 4, "harsh": 6}.get(styleName, 4)

# What each choice in a confrontation does. Pure given the facts: effect = {"clear", "credits" (negative: the player pays), "trust", "respect", "fear", "defiance", "punish", "refused", "text"}.
static func confrontEffect(choice:String, level:int, styleName:String, forgive:float, credits:int) -> Dictionary:
	var owed:int = compensationFor(styleName)
	var effect:Dictionary = {"clear": false, "credits": 0, "trust": 0.0, "respect": 0.0, "fear": 0.0, "defiance": 0.0, "punish": false, "refused": false, "text": ""}
	match(choice):
		"apologise":
			var needed:float = -1000.0 if level == 1 else (OPEN_ENOUGH - 0.05 if level == 2 else 0.45)
			if(forgive >= needed):
				effect["clear"] = true
				effect["trust"] = 0.5
				effect["text"] = "accepted"
				if(level == 3):
					effect["credits"] = -int(min(credits, 3))
			else:
				effect["refused"] = true
				effect["text"] = "refused"
		"submit":
			effect["clear"] = true
			effect["trust"] = 1.0
			effect["defiance"] = -1.0
			effect["text"] = "accepted"
		"pay":
			if(credits < owed):
				effect["refused"] = true
				effect["text"] = "cannot_pay"
			else:
				effect["clear"] = true
				effect["credits"] = -owed
				effect["trust"] = 1.0
				effect["text"] = "paid"
		"negotiate":
			if(forgive >= OPEN_ENOUGH):
				effect["clear"] = true
				effect["credits"] = -int(min(credits, int(ceil(float(owed) / 2.0))))
				effect["respect"] = 1.0
				effect["text"] = "eased"
			else:
				effect["refused"] = true
				effect["text"] = "refused"
		"take":
			effect["clear"] = true
			effect["punish"] = true
			effect["trust"] = -1.0
			effect["defiance"] = -2.0
			effect["text"] = "punished"
		"backdown":
			effect["clear"] = true
			effect["credits"] = -int(min(credits, owed))
			effect["text"] = "backed_down"
	return effect

# ---- Protection ----
# How much the player's owner shields them from attackers. facts: {"hasOwner", "style", "ownerPower", "attackerPower", "attackerFear" (0..100), "gangStrength", "retaliated", "available", "recentLosses"}.
# Returns {"multiplier" (what an attacker's interest is multiplied by, never below PROTECTION_FLOOR), "band": Weak|Moderate|Strong, "credibility", "reasons": [plain text]}.
static func protection(facts:Dictionary) -> Dictionary:
	if(!bool(facts.get("hasOwner", false))):
		return {"multiplier": 1.0, "band": "None", "credibility": 0.0, "reasons": ["Nobody owns you."]}
	var ownerPower:float = float(facts.get("ownerPower", 0.5))
	var attackerPower:float = max(0.1, float(facts.get("attackerPower", 0.9)))
	var ratio:float = clamp(ownerPower / attackerPower, 0.0, 2.0) / 2.0
	var fear:float = clamp(float(facts.get("attackerFear", 0.0)) / 100.0, 0.0, 1.0)
	var gang:float = clamp(float(facts.get("gangStrength", 0.0)) / 6.0, 0.0, 1.0)
	var retaliated:float = 1.0 if bool(facts.get("retaliated", false)) else 0.0
	var credibility:float = clamp(0.35 * ratio + 0.25 * fear + 0.25 * gang + 0.15 * retaliated, 0.0, 1.0)
	credibility -= 0.2 * clamp(float(facts.get("attackerGang", 0.0)) / 6.0, 0.0, 1.0) # a strong gang behind the attacker
	if(bool(facts.get("attackerHostile", false))):
		credibility *= 0.5 # somebody who hates the owner, or whose gang is their enemy, is not put off by them
	credibility = clamp(credibility, 0.0, 1.0)
	var styleFactor:float = float(StyleScript.params(facts.get("style", StyleScript.CONTROLLING))["protection"])
	var available:float = 1.0 if bool(facts.get("available", true)) else 0.5
	var losses:int = int(clamp(int(facts.get("recentLosses", 0)), 0, 3))
	var weaken:float = 1.0 - 0.15 * float(losses)
	var reduction:float = 0.6 * credibility * styleFactor * available * weaken
	var multiplier:float = max(PROTECTION_FLOOR, 1.0 - reduction)
	var band:String = "Weak" if multiplier > 0.8 else ("Moderate" if multiplier > 0.6 else "Strong")
	var reasons:Array = []
	reasons.append("They are " + ("a match for most inmates." if ratio >= 0.45 else "not much of a fighter."))
	if(gang >= 0.4):
		reasons.append("Their gang backs them up.")
	if(retaliated >= 1.0):
		reasons.append("They have hit back before.")
	if(!bool(facts.get("available", true))):
		reasons.append("They are not around right now, so they cannot be counted on.")
	if(losses > 0):
		reasons.append("They have lost fights lately, which weakens their word.")
	if(styleFactor < 0.8):
		reasons.append("They do not push hard on your behalf.")
	if(fear >= 0.4):
		reasons.append("Many fear them.")
	return {"multiplier": multiplier, "band": band, "credibility": credibility, "reasons": reasons}

# ---- The owner asks to meet ----
# "My owner wants to meet today" is always a real pending meeting: one record on the owner (day, purpose, whether the player was told), kept until the owner's event has started, or the meeting is postponed or cancelled.
# Why the owner asks to meet, chosen once when the meeting is made and saved (never rerolled): to give a new demand, to discuss a completed demand, a warning, compensation, punishment, a reward, intimacy, or just possessive attention.
const MEETING_PURPOSES = ["demand", "review", "warning", "compensation", "punishment", "reward", "intimacy", "attention"]
const MEETING_LEGACY = {"check": "attention", "task": "demand", "report": "review"} # (older saves)
const CHECKIN_OUTCOMES = ["", "birth", "warning", "praise", "intimacy", "stay"]
const MEETING_LATE_AXIS = 20 * 3600 # an owner who has not got to the player by evening, and could have, finds them directly

func meeting() -> Dictionary:
	return state.ownership["owner"].get("meeting", {}) if hasOwner() else {}

func hasMeeting() -> bool:
	return !meeting().empty()

func meetingDue(day:int) -> bool:
	var m:Dictionary = meeting()
	return !m.empty() && int(m["day"]) <= day

func startMeeting(day:int, purpose:String) -> bool:
	if(!hasOwner() || hasMeeting()):
		return false
	state.ownership["owner"]["meeting"] = {"day": day, "state": "pending", "purpose": purpose if MEETING_PURPOSES.has(purpose) else "attention", "told": false, "postponed": 0}
	return true

# The purpose of a meeting, from what is outstanding (facts: confront level 0 to 3, demand state "", "offered", "ready" or "active", demandDue, notable, intimacyOk, intimacyChance).
# A warning, compensation or punishment when something is owed; a review of a finished demand; a new demand; a reward for notable compliance; sometimes intimacy; otherwise attention. Deterministic from the seed.
static func choosePurpose(facts:Dictionary, seedText:String) -> String:
	var level:int = int(facts.get("confront", 0))
	if(level >= 3):
		return "punishment"
	if(level == 2):
		return "compensation"
	if(level == 1):
		return "warning"
	if(str(facts.get("demand", "")) == "ready"):
		return "review"
	if(str(facts.get("demand", "")) == "offered" || bool(facts.get("demandDue", false))):
		return "demand"
	if(bool(facts.get("notable", false))):
		return "reward"
	if(bool(facts.get("intimacyOk", false)) && pickIndex(seedText + "meet", 100) < int(round(60.0 * float(facts.get("intimacyChance", 0.0))))):
		return "intimacy"
	return "attention"

# What the evening check-in turns into, once, in this order: a warning is dealt with, notable compliance is acknowledged, the owner may want intimacy, otherwise the stay is offered.
static func checkinOutcomeKind(facts:Dictionary, intimacyRoll:float) -> String:
	if(bool(facts.get("birth", false))):
		return "birth" # an imminent birth comes before everything, and before sleeping or intimacy
	if(int(facts.get("confront", 0)) > 0):
		return "warning"
	if(bool(facts.get("notable", false))):
		return "praise"
	if(bool(facts.get("intimacyOk", false)) && intimacyRoll < float(facts.get("intimacyChance", 0.0))):
		return "intimacy"
	return "stay"

# A hard demand finished lately, or a good run: the owner may say so (a small thing: it never repeats the task's own reward). Not more than once in three days.
func notableCompliance(day:int) -> bool:
	if(!hasOwner() || day - int(state.ownership["owner"].get("last_praise", -100)) < 3):
		return false
	var done:Dictionary = state.ownership["owner"].get("last_done", {})
	var hard:bool = !done.empty() && day - int(done["day"]) <= 1 && str(done["type"]) in ["defeat", "contraband"]
	return hard || recentFulfilled(day) >= 3

# What the owner already knows about the player's pregnancy: "" (nothing yet), "noticed" (they saw the belly and reacted) or "birth" (they were told it is time). The record belongs to one pregnancy.
func pregnancyStage() -> String:
	return str(state.ownership["owner"].get("pregnancy", "")) if hasOwner() else ""

func setPregnancyStage(stage:String) -> void:
	if(hasOwner() && stage in ["", "noticed", "birth"]):
		state.ownership["owner"]["pregnancy"] = stage

# An owed matter outranks everything a pending meeting could be about. A meeting that was made for something lighter becomes the owed matter when it appears (it is still one meeting, told once).
const MEETING_RANK = {"attention": 0, "intimacy": 1, "reward": 2, "demand": 3, "review": 4, "warning": 5, "compensation": 6, "punishment": 7}
const OWED_PURPOSES = ["warning", "compensation", "punishment"]

func upgradePurpose(newPurpose:String) -> bool:
	if(!hasMeeting() || !MEETING_RANK.has(newPurpose)):
		return false
	var m:Dictionary = state.ownership["owner"]["meeting"]
	if(int(MEETING_RANK[newPurpose]) <= int(MEETING_RANK.get(str(m["purpose"]), 0))):
		return false
	m["purpose"] = newPurpose
	return true

# The owner's own punishment puts the player somewhere for the night (stocks, slutwall, medical, sold on...): that night's check-in is covered by it, whether it was already open or not yet made. Never a miss.
func coverNight(day:int) -> void:
	if(!hasOwner()):
		return
	var rec:Dictionary = state.ownership["owner"]
	if(isCheckinPending(day)):
		rec["checkin"]["state"] = "excused"
		rec["checkin"]["block"] = "your owner's punishment"
	rec["next_checkin"] = int(max(int(rec["next_checkin"]), nextCheckinAfter(day)))

func notePraise(day:int) -> void:
	if(hasOwner()):
		state.ownership["owner"]["last_praise"] = day

# The outcome chosen for tonight's check-in, stored so that opening the scene again (or loading) neither rerolls nor repeats it.
func checkinOutcome() -> String:
	return str(checkin().get("outcome", "")) if hasOwner() else ""

func checkinIntent() -> String:
	return str(checkin().get("intent", "")) if hasOwner() else ""

func setCheckinOutcome(kind:String, intent:String) -> void:
	if(hasOwner() && CHECKIN_OUTCOMES.has(kind)):
		state.ownership["owner"]["checkin"]["outcome"] = kind
		state.ownership["owner"]["checkin"]["intent"] = intent

func markMeetingTold() -> bool:
	if(!hasMeeting() || bool(meeting()["told"])):
		return false
	state.ownership["owner"]["meeting"]["told"] = true
	return true

# Something real (a hard blocker) keeps the owner away today: the meeting moves to the next day. Returns true the first time per meeting (the player is told once).
func postponeMeeting(newDay:int) -> bool:
	if(!hasMeeting()):
		return false
	var m:Dictionary = state.ownership["owner"]["meeting"]
	var first:bool = int(m["postponed"]) == 0 || int(m["day"]) != newDay
	m["day"] = newDay
	m["state"] = "postponed"
	m["postponed"] = int(min(20, int(m["postponed"]) + 1))
	return first

func finishMeeting() -> bool:
	if(!hasMeeting()):
		return false
	state.ownership["owner"]["meeting"] = {}
	return true

# ---- The nights at the owner's, and the owner's rescue ----
const NIGHT_MODES = ["require", "invite", "allow"]
const NIGHT_MODE_ODDS = {"harsh": [75, 20, 5], "controlling": [55, 35, 10], "lenient": [10, 70, 20]} # percent: they require it, ask for it, let the player go
const INTIMACY_GAP_NIGHTS = 2 # at most one intimate night in two
const RESCUE_WINDOW_SECONDS = 6 * 3600 # being restrained counts as a hostile encounter for this long after the player lost to somebody

# What the owner does when the evening check-in is done: "require" (you stay), "invite" (stay if you like) or "allow" (you may go). Fixed for the same style, day and owner.
static func nightMode(styleName:String, seedText:String) -> String:
	var odds:Array = NIGHT_MODE_ODDS.get(styleName, NIGHT_MODE_ODDS[StyleScript.CONTROLLING])
	var roll:int = pickIndex(seedText + "night", 100)
	if(roll < int(odds[0])):
		return "require"
	if(roll < int(odds[0]) + int(odds[1])):
		return "invite"
	return "allow"

# How likely the stay turns intimate (when the two-night gap allows): the style, the owner's lust for the player, how much they like and trust them. Never certain, never hopeless.
static func intimacyChance(styleName:String, lust:float, affection:float, trust:float) -> float:
	var base:float = 0.40 if styleName == StyleScript.HARSH else (0.35 if styleName == StyleScript.CONTROLLING else 0.25)
	return clamp(base + 0.25 * clamp(lust, -1.0, 1.0) + 0.15 * affection / 100.0 + (0.05 if trust >= 20.0 else (-0.10 if trust < 0.0 else 0.0)), 0.05, 0.70)

# How the owner goes about it: "ask" (they ask and take no for an answer), "demand" (they expect it, and can be talked out of it) or "force" (they take it).
static func intimacyIntent(styleName:String, affection:float, trust:float) -> String:
	if(styleName == StyleScript.HARSH && (affection < 10.0 || trust < 0.0)):
		return "force"
	if(styleName == StyleScript.LENIENT || (affection >= 20.0 && trust >= 10.0)):
		return "ask"
	return "demand"

func canHaveIntimacy(day:int) -> bool:
	return hasOwner() && day - int(state.ownership["owner"].get("last_intimacy", -100)) >= INTIMACY_GAP_NIGHTS

func noteIntimacy(day:int) -> void:
	if(hasOwner()):
		state.ownership["owner"]["last_intimacy"] = day

func notePlayerDefeat(clock:int, byID:String) -> void:
	if(!(byID is String) || byID == "" || byID == "pc"):
		return
	state.ownership["pc_defeat"] = {"clock": clock, "by": byID, "handled": false, "started": -1}

func playerDefeat() -> Dictionary:
	return state.ownership["pc_defeat"]

# A hostile encounter the owner has not yet dealt with: the player lost to somebody recently and the owner has not yet come for it.
func rescueDue(clock:int) -> bool:
	var d:Dictionary = state.ownership["pc_defeat"]
	return hasOwner() && !d.empty() && !bool(d["handled"]) && clock - int(d["clock"]) <= RESCUE_WINDOW_SECONDS

func markRescueStarted(clock:int) -> void:
	if(!state.ownership["pc_defeat"].empty()):
		state.ownership["pc_defeat"]["handled"] = true
		state.ownership["pc_defeat"]["started"] = clock

func markRescueDone() -> void:
	if(!state.ownership["pc_defeat"].empty()):
		state.ownership["pc_defeat"]["started"] = -1

# ---- Rival claims ----
# Somebody else tries to own a player who already has an owner. There is never a second owner: the claim is a dispute that ends with exactly one owner.
# Facts: "ownerAble" / "claimantAble" (free, awake, not badly hurt, not held, able to get there), "ownerPower" / "claimantPower" (the same strength score BDCC's own quick fights use), "ownerGang" / "claimantGang" (0 to 1),
# "ownerInjury" / "claimantInjury" (0 to 3), "style" (the owner's), "claimantCoward" (-1 to 1), "support" ("owner", "claimant" or "none": the player's side).
const DISPUTE_RESULTS = ["postponed", "claimant_unable", "backs_down", "owner_yields", "owner_wins", "claimant_wins", "cooldown"]
const DISPUTE_GAP_DAYS = 2 # at most one dispute every two days, and the same claimant not again for three
const CLAIMANT_GAP_DAYS = 3
const INJURY_FACTOR = {0: 1.0, 1: 0.9, 2: 0.7, 3: 0.4}

static func contestStrength(power:float, gang:float, injury:int, bonus:float) -> float:
	return max(0.05, power) * (1.0 + 0.3 * clamp(gang, 0.0, 1.0)) * float(INJURY_FACTOR.get(int(clamp(injury, 0, 3)), 0.4)) * bonus

# {"result", "ownerChance"}: the result is one of DISPUTE_RESULTS (without "cooldown"). roll (0 to 1) decides a real fight and is passed in so the outcome is repeatable.
static func contestOutcome(facts:Dictionary, roll:float) -> Dictionary:
	if(!bool(facts.get("ownerAble", false))):
		return {"result": "postponed", "ownerChance": 0.0} # a held, knocked out, badly hurt or absent owner cannot answer a challenge right now
	if(!bool(facts.get("claimantAble", false))):
		return {"result": "claimant_unable", "ownerChance": 1.0}
	var style:String = str(facts.get("style", StyleScript.CONTROLLING))
	var support:String = str(facts.get("support", "none"))
	var defender:float = 1.10 if style == StyleScript.HARSH else (1.05 if style == StyleScript.CONTROLLING else 1.0)
	var ownerStrength:float = contestStrength(float(facts.get("ownerPower", 0.5)), float(facts.get("ownerGang", 0.0)), int(facts.get("ownerInjury", 0)), defender * (1.15 if support == "owner" else 1.0))
	var claimantStrength:float = contestStrength(float(facts.get("claimantPower", 0.5)), float(facts.get("claimantGang", 0.0)), int(facts.get("claimantInjury", 0)), 1.15 if support == "claimant" else 1.0)
	var chance:float = ownerStrength * ownerStrength / (ownerStrength * ownerStrength + claimantStrength * claimantStrength)
	var daunted:float = 0.45 if support == "claimant" else 0.6
	if(claimantStrength < daunted * ownerStrength || float(facts.get("claimantCoward", 0.0)) >= 0.5):
		return {"result": "backs_down", "ownerChance": chance}
	if(style == StyleScript.LENIENT && claimantStrength > ownerStrength && support != "owner"):
		return {"result": "owner_yields", "ownerChance": chance} # a lenient owner does not fight somebody stronger over this
	return {"result": "owner_wins" if roll < chance else "claimant_wins", "ownerChance": chance}

func disputeAllowed(claimantID, day:int) -> bool:
	if(day - int(state.ownership["last_dispute"]) < DISPUTE_GAP_DAYS):
		return false
	var before:Dictionary = state.ownership["disputes"].get(claimantID, {})
	return before.empty() || day - int(before["day"]) >= CLAIMANT_GAP_DAYS

func noteDispute(claimantID, day:int, result:String) -> void:
	if(!(claimantID is String) || claimantID == "" || !DISPUTE_RESULTS.has(result)):
		return
	if(!state.ownership["disputes"].has(claimantID) && state.ownership["disputes"].size() >= 20):
		var oldest:String = ""
		for id in state.ownership["disputes"]:
			if(oldest == "" || int(state.ownership["disputes"][id]["day"]) < int(state.ownership["disputes"][oldest]["day"])):
				oldest = id
		var _gone:bool = state.ownership["disputes"].erase(oldest)
	state.ownership["disputes"][claimantID] = {"day": day, "result": result}
	state.ownership["last_dispute"] = day

# ---- When the owner steps in from elsewhere ----
const INTERVENTION_GAP_DAYS = 1 # the owner's protection can be used once per in-game day, from anywhere in the prison

func interventionReadyOn() -> int:
	return int(state.ownership["owner"].get("last_help", -100)) + INTERVENTION_GAP_DAYS if hasOwner() else 0

func noteIntervention(day:int) -> void:
	if(hasOwner()):
		state.ownership["owner"]["last_help"] = day

# ---- Who would look after the player ----
# Two separate questions. CAPABILITY: could they keep people off the player (their fighting strength compared with the other inmates, their gang's strength, with more weight on the gang for its leader,
# less if they are injured)? WILLINGNESS: would they take the responsibility (temperament, how they feel about the player, their gang's standing with the player)? Both must hold.
# Facts (all plain numbers): "powerRank" (0 to 1: how they rank among the inmates in strength), "gangBacking" (0 to 1), "isLeader", "subby" (-1 to 1), "trust", "respect", "affection", "fear" (axes),
# "desire" (-1 to 1), "injury" (0 none, 1 minor, 2 moderate, 3 severe), "captive", "ownGangLeader" (the leader of the gang the player belongs to), "ownGangMember", "ownGangWarm" (the leader is not cold to the player),
# "gangHostile" (their gang is hostile to the player), "gangEnemy" (their gang is an enemy of the player's gang), "playerBacked" (the player's own gang is strong).
const CAPABLE_AT = 0.35
const WILLING_AT = 0.40
const STRONGLY_SUBMISSIVE = 0.55 # only somebody this submissive prefers being protected to protecting

static func protectorCapability(facts:Dictionary) -> float:
	var personal:float = clamp(float(facts.get("powerRank", 0.5)), 0.0, 1.0)
	var backing:float = clamp(float(facts.get("gangBacking", 0.0)), 0.0, 1.0)
	var weight:float = 0.7 if bool(facts.get("isLeader", false)) else 0.4
	var capability:float = personal if backing <= 0.0 else clamp(0.6 * personal + weight * backing, 0.0, 1.0)
	var injury:int = int(facts.get("injury", 0))
	if(injury >= 3):
		capability *= 0.3
	elif(injury == 2):
		capability *= 0.7
	return capability

static func protectorWillingness(facts:Dictionary) -> float:
	var score:float = 0.36 - 0.20 * clamp(float(facts.get("subby", 0.0)), -1.0, 1.0)
	score += 0.30 * float(facts.get("respect", 0.0)) / 100.0 + 0.20 * float(facts.get("trust", 0.0)) / 100.0 + 0.15 * float(facts.get("affection", 0.0)) / 100.0 + 0.10 * clamp(float(facts.get("desire", 0.0)), -1.0, 1.0)
	if(float(facts.get("fear", 0.0)) >= 50.0 && float(facts.get("trust", 0.0)) < 20.0):
		score -= 0.4
	if(float(facts.get("affection", 0.0)) <= -30.0 || float(facts.get("trust", 0.0)) <= -30.0 || float(facts.get("respect", 0.0)) <= -40.0):
		score -= 0.6
	if(bool(facts.get("ownGangLeader", false)) && bool(facts.get("ownGangWarm", true))):
		score += 0.30 # the leader of the player's own gang: a real reason to look after one of their own
	elif(bool(facts.get("ownGangMember", false))):
		score += 0.12
	if(bool(facts.get("gangHostile", false))):
		score -= 0.5
	elif(bool(facts.get("gangEnemy", false))):
		score -= 0.3
	if(bool(facts.get("playerBacked", false)) && !bool(facts.get("ownGangLeader", false))):
		score -= 0.2
	return score

# {"accepts", "score", "capability", "willingness", "reasons": [one primary reason and at most one short secondary one, in their own words], "hint": what could change it}
static func protectorDecision(facts:Dictionary) -> Dictionary:
	var capability:float = protectorCapability(facts)
	var willingness:float = protectorWillingness(facts)
	var captive:bool = bool(facts.get("captive", false))
	var injury:int = int(facts.get("injury", 0))
	var subby:float = float(facts.get("subby", 0.0))
	var trust:float = float(facts.get("trust", 0.0))
	var fear:float = float(facts.get("fear", 0.0))
	var hostileHistory:bool = float(facts.get("affection", 0.0)) <= -30.0 || trust <= -30.0 || float(facts.get("respect", 0.0)) <= -40.0
	var capable:bool = capability >= CAPABLE_AT && !captive
	var willing:bool = willingness >= WILLING_AT && subby < STRONGLY_SUBMISSIVE
	var accepts:bool = capable && willing
	# every obstacle that applies, most telling first
	var found:Array = []
	if(injury >= 3):
		found.append(["Not while I'm this badly injured.", "Let them recover first."])
	if(hostileHistory):
		found.append(["After what you've done to me, I'm not helping you.", "Settle things with them before you ask."])
	if(bool(facts.get("gangHostile", false)) || bool(facts.get("gangEnemy", false))):
		found.append(["My gang wouldn't accept that while you stand with our enemies.", "Improve your standing with their gang."])
	if(subby >= STRONGLY_SUBMISSIVE):
		found.append(["I'd rather be the one receiving protection.", "Ask someone who is not so happy to follow."])
	if(capability < CAPABLE_AT && injury < 3):
		found.append(["I'm not strong enough to keep anyone off you.", "Find somebody tougher, or somebody with a gang behind them."])
	if(fear >= 50.0 && trust < 20.0):
		found.append(["You scare me too much for that.", "Build trust."])
	elif(capable && willingness < WILLING_AT && trust < 10.0):
		found.append(["I could protect you, but I don't trust you yet.", "Build trust."])
	if(bool(facts.get("playerBacked", false)) && !bool(facts.get("ownGangLeader", false)) && willingness < WILLING_AT):
		found.append(["You already have protection behind you.", "They do not see why you need them."])
	if(willingness < WILLING_AT && found.empty()):
		found.append(["You haven't given me a reason to take responsibility for you.", "Earn their respect or build affection."])
	if(captive):
		found.insert(0, ["I'm in no position to look after anyone.", "They are held right now."])
	var reasons:Array = []
	var hint:String = ""
	if(!accepts && !found.empty()):
		reasons.append(found[0][0])
		hint = str(found[0][1])
		if(found.size() > 1):
			reasons.append(found[1][0])
	return {"accepts": accepts, "score": willingness + 0.5 * capability, "capability": capability, "willingness": willingness, "reasons": reasons, "hint": hint}

# ---- Aggressors and retaliation ----
func noteAggressor(characterID:String, day:int) -> void:
	if(!hasOwner() || characterID == "" || characterID == "pc" || characterID == ownerID()):
		return
	var list:Dictionary = state.ownership["owner"]["aggressors"]
	if(!list.has(characterID) && list.size() >= 12):
		return
	var entry:Dictionary = list.get(characterID, {"day": day, "retaliated": -1000, "failed": 0})
	entry["day"] = day
	list[characterID] = entry

func isAggressor(characterID) -> bool:
	return hasOwner() && state.ownership["owner"]["aggressors"].has(characterID)

# Whether the owner has already retaliated against this attacker at some point.
func hasRetaliatedAgainst(characterID) -> bool:
	return isAggressor(characterID) && int(state.ownership["owner"]["aggressors"][characterID]["retaliated"]) > -1000

# The aggressor the owner would go after now (one attempt per few days, gives up after repeated failures), or "".
func retaliationTarget(day:int, candidates:Array) -> String:
	if(!hasOwner() || inGrace(day) || recentOwnerLosses(day) >= 2):
		return ""
	var list:Dictionary = state.ownership["owner"]["aggressors"]
	var ids:Array = list.keys()
	ids.sort()
	for id in ids:
		var entry:Dictionary = list[id]
		if(int(entry["failed"]) >= RETALIATION_GIVE_UP || day - int(entry["retaliated"]) < RETALIATION_GAP_DAYS || day - int(entry["day"]) > 10):
			continue
		if(candidates.has(id)):
			return id
	return ""

func recordRetaliation(characterID:String, day:int) -> void:
	if(isAggressor(characterID)):
		state.ownership["owner"]["aggressors"][characterID]["retaliated"] = day

# The result of the owner's fight with the aggressor. A win settles it; a loss counts as a failed attempt (two and the owner gives up) and weakens the protection.
func recordRetaliationResult(characterID:String, ownerWon:bool, day:int) -> void:
	if(!isAggressor(characterID)):
		return
	var entry:Dictionary = state.ownership["owner"]["aggressors"][characterID]
	if(ownerWon):
		entry["failed"] = 0
		entry["retaliated"] = day
	else:
		entry["failed"] = int(entry["failed"]) + 1
		recordOwnerLoss(day)

# ---- Leaving ----
# The ways out. facts: {"day", "trust", "respect", "affection", "fear" (the owner's feelings towards the player), "credits", "protection": band word, "gangHelp": bool (a gang that could help),
# "ownerBeaten": distinct wins needed met by the player, "hostile": bool}. Each route: {"id", "name", "available", "text"}; costs are in the text and in "cost".
func buyoutCost(trust:float, respect:float, affection:float, protectionBand:String) -> int:
	var base:int = int(styleParams()["buyout"])
	var adjust:float = -(trust + respect + affection) / 30.0 # a good relationship shaves off a few credits, a bad one adds
	if(protectionBand == "Strong"):
		adjust += 4.0
	elif(protectionBand == "Weak"):
		adjust -= 3.0
	return int(clamp(base + int(round(adjust)), BUYOUT_MIN, BUYOUT_MAX))

func termEnded(day:int) -> bool:
	return !hasOwner() || day >= int(state.ownership["owner"]["term_end"])

func releaseRoutes(facts:Dictionary) -> Array:
	var routes:Array = []
	if(!hasOwner()):
		return routes
	var rec:Dictionary = state.ownership["owner"]
	var day:int = int(facts.get("day", 0))
	var trust:float = float(facts.get("trust", 0.0))
	var respect:float = float(facts.get("respect", 0.0))
	var affection:float = float(facts.get("affection", 0.0))
	var ended:bool = termEnded(day)
	var term:String = "Not before day " + str(rec["term_end"]) + (": you agreed to a few days at least." if rec["voluntary"] else ".")
	# A: negotiated
	var score:float = float(styleParams()["willingness"]) + trust / 100.0 * 0.4 + respect / 100.0 * 0.3 + affection / 100.0 * 0.3
	var goodEnough:bool = (trust >= 30.0 && respect >= 15.0) || affection >= 55.0
	var negotiated:Dictionary = {"id": "negotiate", "name": "Ask to be released", "available": ended && goodEnough, "score": score}
	negotiated["text"] = (term if !ended else ("They would listen: they trust and respect you enough." if goodEnough else "They do not trust or respect you enough yet. Keep your word and do what they ask.")) + (" A " + StyleScript.nameOf(rec["style"]).to_lower() + " owner is " + ("receptive." if rec["style"] == StyleScript.LENIENT else ("hard to move." if rec["style"] == StyleScript.HARSH else "fair if you have earned it.")))
	routes.append(negotiated)
	# B: buyout
	var cost:int = buyoutCost(trust, respect, affection, str(facts.get("protection", "Moderate")))
	var hostile:bool = bool(facts.get("hostile", false))
	var affordable:bool = int(facts.get("credits", 0)) >= cost
	var buy:Dictionary = {"id": "buyout", "name": "Buy your freedom", "available": ended && !hostile && affordable, "cost": cost}
	if(!ended):
		buy["text"] = term
	elif(hostile):
		buy["text"] = "They are too angry to take money from you. Talk first."
	else:
		buy["text"] = "It costs " + str(cost) + " credits, several days of ordinary work." + ("" if affordable else " You cannot afford it yet.")
	routes.append(buy)
	# C: defiance
	var needed:int = int(styleParams()["release_wins"])
	var have:int = distinctWins()
	var defy:Dictionary = {"id": "defy", "name": "Beat them into letting you go", "available": have >= needed}
	defy["text"] = ("You have beaten them on " + str(have) + " separate days. You can demand to be let go." if have >= needed else "Beat them in a fight on " + str(needed) + " separate days (" + str(have) + " so far). One win is not enough.")
	routes.append(defy)
	# D: outside help
	var help:Dictionary = {"id": "gang", "name": "Ask your gang for help", "available": bool(facts.get("gangHelp", false))}
	help["text"] = "Your gang's leader can step in. It costs standing, some of their treasury, and the owner will not forgive it." if help["available"] else "Only a gang member in good standing, in a gang strong enough to face them, can ask."
	routes.append(help)
	# E: the owner lets go on their own
	routes.append({"id": "owner", "name": "They lose interest", "available": false, "text": "An owner who is afraid of you, or who has come to care for you, may let you go without being asked."})
	return routes

# The owner may drop the claim by themselves: they are afraid of the player and have been beaten, or they truly care and the relationship has run long.
func ownerLosesInterest(day:int, fear:float, trust:float, affection:float) -> String:
	if(!hasOwner()):
		return ""
	var rec:Dictionary = state.ownership["owner"]
	if(fear >= 70.0 && distinctWins() >= 1 && trust < 30.0):
		return "afraid"
	if(affection >= 70.0 && trust >= 60.0 && day - int(rec["since"]) >= 10):
		return "fond"
	return ""

# ---- The player's slaves ----
func slaveRecord(characterID) -> Dictionary:
	return state.ownership["slaves"].get(characterID, {})

func hasSlave(characterID) -> bool:
	return state.ownership["slaves"].has(characterID)

func slaveIDs() -> Array:
	var ids:Array = state.ownership["slaves"].keys()
	ids.sort()
	return ids

func addSlave(characterID:String, day:int) -> bool:
	if(characterID == "" || characterID == "pc" || state.ownership["slaves"].has(characterID)):
		return false
	var entry:Dictionary = defaultSlave()
	entry["since"] = day
	entry["setup"] = "awaiting" # a new slave waits for instructions
	state.ownership["slaves"][characterID] = entry
	return true

func isAwaiting(characterID) -> bool:
	return hasSlave(characterID) && state.ownership["slaves"][characterID]["setup"] == "awaiting"

# The instructions have been given: role and the night arrangement, and the slave is no longer waiting. Returns false for somebody who is not a slave or an unknown value.
func giveInstructions(characterID, role:String, night:String, day:int, clock:int = -1) -> bool:
	if(!hasSlave(characterID) || !ROLES.has(role) || !NIGHTS.has(night)):
		return false
	var entry:Dictionary = state.ownership["slaves"][characterID]
	entry["role"] = role
	entry["role_day"] = day
	entry["role_from"] = clock + ROLE_TRANSITION_SECONDS if clock >= 0 else -1
	entry["night"] = night
	entry["setup"] = "set"
	return true

func setNight(characterID, night:String) -> bool:
	if(!hasSlave(characterID) || !NIGHTS.has(night)):
		return false
	state.ownership["slaves"][characterID]["night"] = night
	return true

# Whether a role's routine may begin now: a freshly given role starts half an hour later, not on the spot.
func roleActive(characterID, clock:int) -> bool:
	return hasSlave(characterID) && int(state.ownership["slaves"][characterID]["role_from"]) <= clock

func noteDefeat(characterID, day:int, kind:String) -> void:
	if(!(characterID is String) || characterID == "" || characterID == "pc" || !(kind in ["fight", "surrender"])):
		return
	if(!state.ownership["defeated"].has(characterID) && state.ownership["defeated"].size() >= 30):
		return
	state.ownership["defeated"][characterID] = {"day": day, "kind": kind}

func lastDefeat(characterID) -> Dictionary:
	return state.ownership["defeated"].get(characterID, {}).duplicate(true)

# ---- How a slave feels about being enslaved ----
# Applied once, when the slave is taken (the record it leaves on the slave is what stops it repeating on load). Classified from what really happened:
# "voluntary": the player offered, they were already warm to the player and agreed (the game's "Enslave!" talk option with an affectionate, trusting NPC);
# "submission": they gave in without the full breaking (the same talk option from anybody else), or after a defeat where they surrendered;
# "forced": the game's own route, breaking tasks after a defeat, and kidnapping;
# "unknown": anything else (console and debug conversions): feelings that exist are kept, a blank slate gets a cautious negative baseline.
const AFTERMATH_KINDS = ["voluntary", "submission", "forced", "unknown"]

static func aftermathKind(hadQuest:bool, route:String, defeatKind:String, affection:float, trust:float) -> String:
	if(route == "free"):
		return "voluntary" if (affection >= 20.0 && trust >= 15.0) else "submission"
	if(hadQuest):
		return "submission" if defeatKind == "surrender" else "forced"
	return "unknown"

# {"trust", "affection", "respect", "fear", "desire"} changes. defeatKind: "fight", "surrender" or "" (no recent defeat). feelings: the current axes, to see whether they are all blank.
static func aftermathDeltas(kind:String, defeatKind:String, feelings:Dictionary) -> Dictionary:
	match(kind):
		"voluntary":
			return {"trust": 3.0, "affection": 3.0, "respect": 2.0, "fear": 0.0, "desire": 0.0}
		"submission":
			var respect:float = 4.0 if defeatKind == "fight" else (1.0 if defeatKind == "surrender" else 2.0)
			return {"trust": -12.0, "affection": -4.0, "respect": respect, "fear": 12.0, "desire": 0.0}
		"forced":
			var forcedRespect:float = 4.0 if defeatKind == "fight" else (1.0 if defeatKind == "surrender" else -6.0)
			return {"trust": -25.0, "affection": -12.0, "respect": forcedRespect, "fear": 22.0, "desire": 0.0}
	var blank:bool = true
	for axis in ["trust", "affection", "respect", "fear", "desire"]:
		if(abs(float(feelings.get(axis, 0.0))) > 0.001):
			blank = false
	if(blank):
		return {"trust": -10.0, "affection": -5.0, "respect": -2.0, "fear": 8.0, "desire": 0.0}
	return {"trust": 0.0, "affection": 0.0, "respect": 0.0, "fear": 0.0, "desire": 0.0}

func markAftermath(characterID, kind:String, day:int) -> bool:
	if(!hasSlave(characterID) || !AFTERMATH_KINDS.has(kind) || !state.ownership["slaves"][characterID]["aftermath"].empty()):
		return false
	state.ownership["slaves"][characterID]["aftermath"] = {"kind": kind, "day": day}
	return true

func removeSlave(characterID) -> bool:
	return state.ownership["slaves"].erase(characterID)

func canChangeRole(characterID, day:int) -> bool:
	return hasSlave(characterID) && int(state.ownership["slaves"][characterID]["role_day"]) != day

func setRole(characterID, role:String, day:int, clock:int = -1) -> bool:
	if(!canChangeRole(characterID, day) || !ROLES.has(role)):
		return false
	var entry:Dictionary = state.ownership["slaves"][characterID]
	entry["role"] = role
	entry["role_day"] = day
	entry["role_from"] = clock + ROLE_TRANSITION_SECONDS if clock >= 0 else -1
	return true

# A broad description of how an owned character stands towards the player, from their directed feelings. It is derived every time and never stored.
static func disposition(trust:float, respect:float, fear:float, affection:float, recovering:bool) -> String:
	if(recovering && trust > -20.0):
		return "recovering"
	if(trust >= 30.0 && affection >= 10.0 && respect >= -10.0):
		return "loyal"
	if(trust < 0.0 && fear < 25.0 && respect < 0.0):
		return "defiant"
	if(fear >= 40.0 && trust < 20.0):
		return "intimidated"
	if((affection < -10.0 || trust < -10.0) && fear < 40.0):
		return "resentful"
	return "uncertain"

const DISPOSITION_TEXT = {
	"loyal": "Loyal: trusts you, likes you, and cooperates willingly.",
	"intimidated": "Intimidated: does as told out of fear, not loyalty, and would run if they saw a chance.",
	"resentful": "Resentful: does not like how they are treated and may refuse duties.",
	"defiant": "Defiant: does not trust or fear you and will refuse most things.",
	"recovering": "Recovering: resting, or recently treated well.",
	"uncertain": "Uncertain: still working out where they stand with you.",
}

# Whether an owned character goes along with a duty ("earner", "report", "attendant", "free", "rest").
static func willDo(role:String, disposition:String) -> bool:
	if(role == "free" || role == "rest"):
		return true
	match(disposition):
		"defiant":
			return false
		"resentful":
			return role == "attendant"
	return true

# The income of an earner: 2 to 4 credits, the same for the same person and day.
# What an earner brings in on a day, by how many earners were paid before them that day (rank 0 is the first): the customers are shared, so more earners means less each.
static func earningFor(characterID, day:int, rank:int = 0) -> int:
	if(rank <= 0):
		return EARN_MIN + pickIndex(str(characterID) + str(day) + "earn", EARN_MAX - EARN_MIN + 1)
	if(rank == 1):
		return EARN_SECOND_MIN + pickIndex(str(characterID) + str(day) + "earn", EARN_SECOND_MAX - EARN_SECOND_MIN + 1)
	return EARN_FURTHER

# Income is credited once a day, and only if they actually worked their stretch today. Returns the credits added to what is waiting (0 when nothing was due).
func creditEarnings(characterID, day:int, attended:bool) -> int:
	if(!hasSlave(characterID)):
		return 0
	var entry:Dictionary = state.ownership["slaves"][characterID]
	if(entry["role"] != "earner" || !attended || int(entry["earn_day"]) == day):
		return 0
	var pool:Dictionary = state.ownership["earn_pool"]
	if(int(pool["day"]) != day):
		pool["day"] = day
		pool["count"] = 0
		pool["paid"] = 0
	var amount:int = int(min(earningFor(characterID, day, int(pool["count"])), EARN_DAY_CAP - int(pool["paid"])))
	pool["count"] = int(pool["count"]) + 1
	pool["paid"] = int(pool["paid"]) + amount
	entry["earn_day"] = day
	entry["uncollected"] = int(min(99, int(entry["uncollected"]) + amount))
	return amount

# The player collects what is waiting. Returns the credits to hand over (the caller adds them to the player once).
func collectEarnings(characterID) -> int:
	if(!hasSlave(characterID)):
		return 0
	var entry:Dictionary = state.ownership["slaves"][characterID]
	var amount:int = int(entry["uncollected"])
	entry["uncollected"] = 0
	return amount

# "Report to my cell": a temporary evening duty for one slave.
func askReport(characterID, day:int) -> bool:
	if(!hasSlave(characterID)):
		return false
	var entry:Dictionary = state.ownership["slaves"][characterID]
	if(!entry["report"].empty() && int(entry["report"].get("day", -1)) == day && entry["report"].get("state", "") == "pending"):
		return false
	entry["report"] = {"day": day, "state": "pending", "refused": false, "delayed": false}
	return true

# ---- Escape (always telegraphed) ----
# Whether this slave starts planning to leave: they feel intimidated, resentful or defiant, and something is wrong (neglect, a missed report, being worked hard), with the odds depending on
# the feeling. The same facts on the same day always give the same answer. Returns true when a warning stage should begin.
func escapeStarts(characterID, day:int, disposition:String, neglected:bool) -> bool:
	if(!hasSlave(characterID)):
		return false
	var entry:Dictionary = state.ownership["slaves"][characterID]
	if(!entry["escape"].empty() || day - int(entry["last_attempt"]) < 5 || entry["role"] == "rest" || entry["setup"] == "awaiting" || day - int(entry["since"]) < ESCAPE_GRACE_DAYS):
		return false
	if(!(disposition in ["intimidated", "resentful", "defiant"]) || !neglected):
		return false
	var chance:int = 60 if disposition == "defiant" else (35 if disposition == "resentful" else 20)
	return pickIndex(str(characterID) + str(day) + "escape", 100) < chance

func startEscape(characterID, day:int, why:String) -> void:
	if(hasSlave(characterID)):
		state.ownership["slaves"][characterID]["escape"] = {"stage": "warning", "day": day, "why": why}

# The day after the warning, they make a visible attempt; one more day and they are gone unless the player stopped it. Returns "" / "attempt" / "gone".
func escapeAdvance(characterID, day:int) -> String:
	if(!hasSlave(characterID)):
		return ""
	var entry:Dictionary = state.ownership["slaves"][characterID]
	var escape:Dictionary = entry["escape"]
	if(escape.empty()):
		return ""
	if(escape["stage"] == "warning" && day > int(escape["day"])):
		escape["stage"] = "attempt"
		escape["day"] = day
		return "attempt"
	if(escape["stage"] == "attempt" && day > int(escape["day"])):
		return "gone"
	return ""

# The player dealt with it (talked them round, intimidated them, beat them, treated them better). The attempt is over and they will not try again for a while.
func stopEscape(characterID, day:int) -> void:
	if(hasSlave(characterID)):
		var entry:Dictionary = state.ownership["slaves"][characterID]
		entry["escape"] = {}
		entry["last_attempt"] = day

func markTreated(characterID, day:int) -> void:
	if(hasSlave(characterID)):
		state.ownership["slaves"][characterID]["last_treat"] = day

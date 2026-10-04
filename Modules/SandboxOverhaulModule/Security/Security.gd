extends Reference
class_name GuardSecurity

# Security Attention, guard attitudes, offence levels and every anti-annoyance cooldown. No game access here: callers pass the time, the facts
# about the guard and the player, and the random rolls (floats 0..1), so everything can be tested on its own.
#
# SandboxState.security = {
#   "attention": 0..100,                      how much attention security is paying to the player right now (not a reputation)
#   "last_incident_day": int, "last_decay_day": int,
#   "warning": {"kind": "" | "nudity", "guard": String, "stamp": int, "ignored": bool}
#   "nudity_stamp": int,                      last nudity warning (cooldown)
#   "search_stamp": int, "search_day": int,   last personal search (any kind) and last routine one (one a day at most)
#   "cell_stamp": int, "cell_check_day": int, last cell search and the last day the random cell search was considered
#   "enforce_stamp": int,                     last time a guard confronted the player (minimum gap between any two)
#   "grace_until": int,                       after a resolved confrontation nobody confronts the player routinely until then
#   "active": bool, "active_stamp": int,      a guard confrontation is in progress (attention does not decay meanwhile)
#   "pending": {"kind": "" | "violent" | "severe", "guard": String, "stamp": int}   a witnessed offence waiting for the guard to act
#   "contraband_day": int, "contraband_count": int,   recent discoveries (repeated finds escalate)
#   "attack_day": int, "attack_count": int,   recent attacks on guards
#   "last_report": String                     the last search report, shown in the Security screen
# }
# A stamp is day * 86400 + seconds of day. It is monotonic in BDCC (sleeping moves to 06:00 of the next day). A stamp in the future (a corrupt or
# foreign save) counts as already over, so no cooldown can stay stuck.

const ATTENTION_MIN = 0.0
const ATTENTION_MAX = 100.0
const DAY = 86400
const HOUR = 3600

# ---- Attention bands ----
const BANDS = [
	{"min": 80, "label": "Priority target", "text": "Security is actively looking for a reason to deal with you."},
	{"min": 60, "label": "High alert", "text": "Guards are on edge around you and searches are a real threat."},
	{"min": 40, "label": "Watched", "text": "Guards pay you extra attention and are quicker to act."},
	{"min": 20, "label": "Noticed", "text": "Security has heard your name, but nothing more."},
	{"min": 0, "label": "Routine", "text": "Security pays you no special attention."},
]

# ---- What each detected offence adds ----
const OFFENCE_ATTENTION = {"minor": 4.0, "contraband": 10.0, "violent": 20.0, "severe": 30.0}
const OFFENCES = ["minor", "contraband", "violent", "severe"]
const REPEAT_CONTRABAND_EXTRA = 5.0 # per earlier discovery in the last 3 days, at most twice
const RESIST_ATTENTION = 15.0
const WON_AGAINST_GUARD_ATTENTION = 25.0
const WON_AGAINST_GUARD_CAP = 85.0 # winning never pins the value at the maximum

# ---- Decay ----
const DAILY_DECAY = 4.0
const QUIET_DAYS = 3 # incident-free days before the faster decay starts
const QUIET_EXTRA_DECAY = 8.0
const MAX_DECAY_DAYS = 30

# ---- Pacing (seconds) ----
const NUDITY_COOLDOWN = 6 * HOUR
const WARNING_COMPLY_TIME = 20 * 60 # the warned player has this long before ignoring it can count
const WARNING_LIFETIME = 3 * HOUR
const PERSONAL_SEARCH_COOLDOWN = 2 * DAY # one routine search a day at most, and in practice rarely
const PERSONAL_SEARCH_COOLDOWN_ALERT = 1 * DAY # at High alert
const CELL_SEARCH_COOLDOWN = 4 * DAY
const ENFORCE_MIN_GAP = 30 * 60 # no two confrontations closer than this
const GRACE_AFTER_COMPLY = 3 * HOUR
const GRACE_AFTER_RESIST = 6 * HOUR
const PENDING_LIFETIME = 6 * HOUR
const ACTIVE_LIFETIME = 2 * HOUR # an unresolved confrontation older than this is treated as gone (a lost save, say)
const CONTRABAND_MEMORY_DAYS = 3
const ATTACK_MEMORY_DAYS = 2

# ---- Attitudes ----
const LAX = "lax"
const STANDARD = "standard"
const STRICT = "strict"
const ATTITUDE_BASE_ENFORCE = {"lax": 0.10, "standard": 0.35, "strict": 0.65} # chance to act on a visible minor offence
const ATTITUDE_BASE_SEARCH = {"lax": 0.003, "standard": 0.010, "strict": 0.025} # chance per guard encounter of a routine personal search
const SEARCH_ATTENTION_DIVISOR = 25.0 # chance times (1 + attention / 25)
const SEARCH_CHANCE_CAP = 0.25
const ENFORCE_CHANCE_MIN = 0.03
const ENFORCE_CHANCE_MAX = 0.90
const FEAR_AVOIDS_ALONE = 60.0 # a guard this afraid of the player will not confront them without backup
const LENIENCY_LIMIT = 0.10
const STAFF_LEVEL_LENIENCY = {-1: 0.0, 0: 0.0, 1: 0.04, 2: 0.0, 3: -0.08, 4: 0.08} # Staff Reputation levels: Respected is lenient, Troublemaker and Prison Menace draw scrutiny

# ---- Cell searches ----
const CELL_SEARCH_BASE = 0.02
const CELL_SEARCH_PER_ATTENTION = 0.0013 # about 15% at attention 100
const CELL_SEARCH_CAP = 0.20
const TARGETED_ATTENTION = 60 # only a targeted search (High alert or above) can find the hidden compartment
const HIDDEN_DISCOVERY_CHANCE = 0.12

# ---- Fines (credits) ----
const FINE_MIN = 1
const FINE_MAX = 3

var state

func _init(_state):
	state = _state

# ---- Pure helpers ----
static func isNumberValue(value) -> bool:
	return (value is int || value is float) && !is_nan(float(value)) && !is_inf(float(value))

static func stamp(day:int, timeOfDay) -> int:
	return day * DAY + posmod(int(timeOfDay), DAY)

static func defaults() -> Dictionary:
	return {"attention": 0.0, "last_incident_day": -1, "last_decay_day": -1,
		"warning": {"kind": "", "guard": "", "stamp": -1, "ignored": false},
		"nudity_stamp": -1, "search_stamp": -1, "search_day": -1, "cell_stamp": -1, "cell_check_day": -1,
		"enforce_stamp": -1, "grace_until": -1, "active": false, "active_stamp": -1,
		"pending": {"kind": "", "guard": "", "stamp": -1},
		"contraband_day": -1, "contraband_count": 0, "attack_day": -1, "attack_count": 0, "last_report": ""}

static func sanitizeInt(value, minimum:int = -1) -> int:
	return int(clamp(round(float(value)), minimum, 1.0e12)) if isNumberValue(value) else minimum

# Clean copy of a saved security dictionary. Malformed fields become their defaults, numbers are clamped, nothing is aliased.
static func sanitize(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(!(raw is Dictionary)):
		return result
	if(isNumberValue(raw.get("attention"))):
		result["attention"] = clamp(float(raw["attention"]), ATTENTION_MIN, ATTENTION_MAX)
	for key in ["last_incident_day", "last_decay_day", "nudity_stamp", "search_stamp", "search_day", "cell_stamp", "cell_check_day", "enforce_stamp", "grace_until", "active_stamp", "contraband_day", "attack_day"]:
		result[key] = sanitizeInt(raw.get(key))
	for key in ["contraband_count", "attack_count"]:
		result[key] = int(min(99, sanitizeInt(raw.get(key), 0)))
	result["active"] = typeof(raw.get("active")) == TYPE_BOOL && raw["active"]
	var warning = raw.get("warning")
	if(warning is Dictionary && (warning.get("kind") is String) && warning["kind"] == "nudity" && (warning.get("guard") is String) && warning["guard"] != "" && isNumberValue(warning.get("stamp"))):
		result["warning"] = {"kind": "nudity", "guard": warning["guard"], "stamp": sanitizeInt(warning["stamp"]), "ignored": typeof(warning.get("ignored")) == TYPE_BOOL && warning["ignored"]}
	var pending = raw.get("pending")
	if(pending is Dictionary && ["violent", "severe"].has(pending.get("kind")) && (pending.get("guard") is String) && pending["guard"] != "" && isNumberValue(pending.get("stamp"))):
		result["pending"] = {"kind": pending["kind"], "guard": pending["guard"], "stamp": sanitizeInt(pending["stamp"])}
	if(raw.get("last_report") is String):
		result["last_report"] = String(raw["last_report"]).left(400)
	return result

static func bandFor(attention) -> Dictionary:
	var value:float = clamp(float(attention), ATTENTION_MIN, ATTENTION_MAX)
	for band in BANDS:
		if(value >= band["min"]):
			return band
	return BANDS[BANDS.size() - 1]

static func label(attention) -> String:
	return bandFor(attention)["label"]

static func labelColor(attention) -> String:
	var value:float = float(attention)
	if(value >= 60.0):
		return "red"
	if(value >= 20.0):
		return "yellow"
	return "green"

# A time is ready when it was never set, is in the future (corrupt or foreign data), or the cooldown is over.
static func isReady(last:int, cooldown:int, now:int) -> bool:
	return last < 0 || last > now || now - last >= cooldown

# A deterministic attitude from the guard's Mean personality stat (-1..1, 0 when unknown) plus a stable per-character offset, so it never changes on reload.
static func attitudeFor(characterID, meanStat) -> String:
	var mean:float = clamp(float(meanStat), -1.0, 1.0) if isNumberValue(meanStat) else 0.0
	var offset:float = (float(posmod(("attitude" + str(characterID)).hash(), 1000)) / 999.0 - 0.5) * 0.6 # -0.3..0.3
	var score:float = mean + offset
	if(score >= 0.3):
		return STRICT
	if(score <= -0.3):
		return LAX
	return STANDARD

# How lenient (negative) or strict (positive) this guard is towards this player beyond their attitude, at most +-0.10. Staff Reputation level, Trust and Respect.
static func leniency(staffLevel, trust, respect) -> float:
	var level:int = int(clamp(int(staffLevel) if isNumberValue(staffLevel) else 0, -1, 4))
	var value:float = float(STAFF_LEVEL_LENIENCY.get(level, 0.0))
	var t:float = clamp(float(trust), -100.0, 100.0) if isNumberValue(trust) else 0.0
	var r:float = clamp(float(respect), -100.0, 100.0) if isNumberValue(respect) else 0.0
	value -= (t + r) / 200.0 * 0.06 # up to -0.06 for a guard who trusts and respects the player, +0.06 for the opposite
	return clamp(value, -LENIENCY_LIMIT, LENIENCY_LIMIT)

static func fearAvoidsAlone(fear) -> bool:
	return isNumberValue(fear) && float(fear) >= FEAR_AVOIDS_ALONE

# Chance that this guard acts on a visible minor offence (a nudity warning, say). Always between 3% and 90%.
static func enforceChance(attitude:String, attention, leniencyValue:float) -> float:
	var chance:float = float(ATTITUDE_BASE_ENFORCE.get(attitude, ATTITUDE_BASE_ENFORCE[STANDARD]))
	chance += clamp(float(attention), 0.0, 100.0) / 100.0 * 0.35
	chance += clamp(leniencyValue, -LENIENCY_LIMIT, LENIENCY_LIMIT)
	return clamp(chance, ENFORCE_CHANCE_MIN, ENFORCE_CHANCE_MAX)

# Chance per guard encounter of a routine personal search. Under 1.1% for a standard guard at attention 0, never above 25%.
static func personalSearchChance(attitude:String, attention, leniencyValue:float) -> float:
	var base:float = float(ATTITUDE_BASE_SEARCH.get(attitude, ATTITUDE_BASE_SEARCH[STANDARD]))
	var chance:float = base * (1.0 + clamp(float(attention), 0.0, 100.0) / SEARCH_ATTENTION_DIVISOR)
	chance += clamp(leniencyValue, -LENIENCY_LIMIT, LENIENCY_LIMIT) * 0.05
	return clamp(chance, 0.0, SEARCH_CHANCE_CAP)

# Chance, per day, of a search of the player's cell.
static func cellSearchChance(attention, leniencyValue:float) -> float:
	var chance:float = CELL_SEARCH_BASE + clamp(float(attention), 0.0, 100.0) * CELL_SEARCH_PER_ATTENTION
	chance *= 1.0 + clamp(leniencyValue, -LENIENCY_LIMIT, LENIENCY_LIMIT)
	return clamp(chance, 0.0, CELL_SEARCH_CAP)

# The fine for a search that found contraband: 1 credit, plus 1 for a repeat find and 1 for three or more items, at most 3. Never more than the player has.
static func fineFor(itemCount:int, repeatCount:int, harshness:int, credits:int) -> int:
	var fine:int = FINE_MIN
	if(repeatCount > 0):
		fine += 1
	if(itemCount >= 3 || harshness >= 2):
		fine += 1
	return int(clamp(min(fine, FINE_MAX), 0, max(0, credits)))

# ---- Attention ----
func getAttention() -> float:
	return float(state.security["attention"])

func setAttention(value) -> void:
	state.security["attention"] = clamp(float(value), ATTENTION_MIN, ATTENTION_MAX)

# Adds (or removes) attention and returns the change that really happened after clamping.
func addAttention(amount:float) -> float:
	var before:float = getAttention()
	setAttention(before + amount)
	return getAttention() - before

# A detected offence of this level on this day. Returns the attention that was added. Repeated contraband finds and repeated attacks on guards escalate.
func recordOffence(level:String, day:int, extraAttention:float = 0.0) -> float:
	if(!OFFENCE_ATTENTION.has(level)):
		return 0.0
	var amount:float = float(OFFENCE_ATTENTION[level]) + extraAttention
	if(level == "contraband"):
		var recent:int = recentContrabandCount(day)
		amount += REPEAT_CONTRABAND_EXTRA * min(2, recent)
		state.security["contraband_count"] = recent + 1
		state.security["contraband_day"] = day
	state.security["last_incident_day"] = day
	return addAttention(amount)

func recentContrabandCount(day:int) -> int:
	var last:int = int(state.security["contraband_day"])
	if(last < 0 || last > day || day - last > CONTRABAND_MEMORY_DAYS):
		return 0
	return int(state.security["contraband_count"])

# Counts an attack on a guard and returns how many happened recently, including this one.
func recordGuardAttack(day:int) -> int:
	var last:int = int(state.security["attack_day"])
	var count:int = int(state.security["attack_count"]) if (last >= 0 && last <= day && day - last <= ATTACK_MEMORY_DAYS) else 0
	count += 1
	state.security["attack_count"] = count
	state.security["attack_day"] = day
	return count

# The player resisted a guard. Returns the attention added.
func recordResistance(day:int) -> float:
	state.security["last_incident_day"] = day
	return addAttention(RESIST_ATTENTION)

# The player beat a guard. A big rise, but never pinned at the maximum. Returns the change.
func recordWonAgainstGuard(day:int) -> float:
	state.security["last_incident_day"] = day
	var before:float = getAttention()
	var target:float = max(before, min(before + WON_AGAINST_GUARD_ATTENTION, WON_AGAINST_GUARD_CAP))
	setAttention(target)
	return getAttention() - before

# Daily decay for every day since the last one: 4 a day, and 8 more after three incident-free days. None while a confrontation is unresolved.
# Returns the (negative) change.
func advanceDay(day:int) -> float:
	var before:float = getAttention()
	var last:int = int(state.security["last_decay_day"])
	state.security["last_decay_day"] = day
	if(last < 0 || last >= day || state.security["active"]):
		return 0.0
	var incident:int = int(state.security["last_incident_day"])
	var days:int = int(min(day - last, MAX_DECAY_DAYS))
	for i in range(days):
		var d:int = last + 1 + i
		var decay:float = DAILY_DECAY
		if(incident < 0 || d - incident >= QUIET_DAYS):
			decay += QUIET_EXTRA_DECAY
		setAttention(getAttention() - decay)
	return getAttention() - before

# ---- Warning, pending report, enforcement state ----
func getWarning(now:int) -> Dictionary:
	var warning:Dictionary = state.security["warning"]
	if(warning["kind"] == "" || warning["stamp"] > now || now - warning["stamp"] > WARNING_LIFETIME):
		return {}
	return warning.duplicate(true)

func issueNudityWarning(guardID:String, now:int) -> void:
	state.security["warning"] = {"kind": "nudity", "guard": guardID, "stamp": now, "ignored": false}
	state.security["nudity_stamp"] = now

func clearWarning() -> void:
	state.security["warning"] = {"kind": "", "guard": "", "stamp": -1, "ignored": false}

func markWarningIgnored() -> void:
	if(state.security["warning"]["kind"] != ""):
		state.security["warning"]["ignored"] = true

# A witnessed serious offence waits for the guard to act. A worse report replaces a milder one.
func setPending(kind:String, guardID:String, now:int) -> bool:
	if(!["violent", "severe"].has(kind) || guardID == ""):
		return false
	var current:Dictionary = getPending(now)
	if(!current.empty() && current["kind"] == "severe" && kind == "violent"):
		return false
	state.security["pending"] = {"kind": kind, "guard": guardID, "stamp": now}
	return true

func getPending(now:int) -> Dictionary:
	var pending:Dictionary = state.security["pending"]
	if(pending["kind"] == "" || pending["stamp"] > now || now - pending["stamp"] > PENDING_LIFETIME):
		return {}
	return pending.duplicate(true)

func clearPending() -> void:
	state.security["pending"] = {"kind": "", "guard": "", "stamp": -1}

func isActive() -> bool:
	return state.security["active"]

func beginEnforcement(now:int) -> void:
	state.security["active"] = true
	state.security["active_stamp"] = now
	state.security["enforce_stamp"] = now

# The confrontation is over: attention may decay again and nobody confronts the player routinely for a while.
func endEnforcement(now:int, resisted:bool) -> void:
	state.security["active"] = false
	state.security["active_stamp"] = -1
	state.security["enforce_stamp"] = now
	state.security["grace_until"] = now + (GRACE_AFTER_RESIST if resisted else GRACE_AFTER_COMPLY)
	clearPending()

# A confrontation that is older than it can be, or that no longer exists in the game, is dropped so the flag can never stay stuck.
func dropStaleEnforcement(now:int, interactionExists:bool) -> bool:
	if(!state.security["active"]):
		return false
	var started:int = int(state.security["active_stamp"])
	if(!interactionExists || started < 0 || started > now || now - started > ACTIVE_LIFETIME):
		state.security["active"] = false
		state.security["active_stamp"] = -1
		return true
	return false

func inGrace(now:int) -> bool:
	var until:int = int(state.security["grace_until"])
	return until >= 0 && now < until && until - now <= GRACE_AFTER_RESIST

func markSearch(day:int, now:int, routine:bool) -> void:
	state.security["search_stamp"] = now
	if(routine):
		state.security["search_day"] = day

func markCellSearch(now:int) -> void:
	state.security["cell_stamp"] = now

func wasSearchedRecently(now:int) -> bool:
	var last:int = int(state.security["search_stamp"])
	return last >= 0 && last <= now && now - last < PERSONAL_SEARCH_COOLDOWN

func setReport(text:String) -> void:
	state.security["last_report"] = text.left(400)

# ---- Decisions ----
# What a guard standing in the player's room should do right now. Nothing here changes the state: the caller starts the confrontation and records it.
# ctx: now, day, guard (ID), attitude, leniency, fear, backup (another free guard in the room), exposed, canDress, exemptPlace
# rolls: floats 0..1: [0] the warning roll, [1] the search roll; missing rolls count as 1.0 (nothing happens)
# Returns {"action": "none" | "confront" | "warn_nudity" | "escalate_nudity" | "search", "kind": ...}
func decide(ctx:Dictionary, rolls:Array) -> Dictionary:
	var none:Dictionary = {"action": "none"}
	var now:int = int(ctx["now"])
	var day:int = int(ctx["day"])
	var attention:float = getAttention()
	if(isActive()):
		return none
	if(!isReady(int(state.security["enforce_stamp"]), ENFORCE_MIN_GAP, now)):
		return none
	var afraid:bool = fearAvoidsAlone(ctx.get("fear", 0.0)) && !ctx.get("backup", false)
	var pending:Dictionary = getPending(now)
	if(!pending.empty() && pending["guard"] == ctx["guard"]):
		# Only the guard who saw it acts on it
		if(afraid):
			return none
		return {"action": "confront", "kind": pending["kind"], "guard": pending["guard"]}
	if(inGrace(now) || afraid):
		return none
	var attitude:String = ctx.get("attitude", STANDARD)
	var leniencyValue:float = float(ctx.get("leniency", 0.0))
	# Nudity: one warning, time to comply, then escalation only for someone who stayed exposed
	if(ctx.get("exposed", false) && ctx.get("canDress", false) && !ctx.get("exemptPlace", false)):
		var warning:Dictionary = getWarning(now)
		if(!warning.empty()):
			if(now - warning["stamp"] >= WARNING_COMPLY_TIME && attitude != LAX):
				return {"action": "escalate_nudity", "guard": ctx["guard"]}
		elif(isReady(int(state.security["nudity_stamp"]), NUDITY_COOLDOWN, now)):
			var roll:float = float(rolls[0]) if rolls.size() > 0 else 1.0
			if(roll < enforceChance(attitude, attention, leniencyValue)):
				return {"action": "warn_nudity", "guard": ctx["guard"]}
	# Routine personal search: at most one a day, with a cooldown, and rare
	if(int(state.security["search_day"]) != day):
		var cooldown:int = PERSONAL_SEARCH_COOLDOWN_ALERT if attention >= 60.0 else PERSONAL_SEARCH_COOLDOWN
		if(isReady(int(state.security["search_stamp"]), cooldown, now)):
			var searchRoll:float = float(rolls[1]) if rolls.size() > 1 else 1.0
			if(searchRoll < personalSearchChance(attitude, attention, leniencyValue)):
				return {"action": "search", "guard": ctx["guard"]}
	return none

# Whether the random cell search happens today, and whether it is a targeted one (High alert or above, the only kind that can find the hidden compartment).
# Considered at most once a day. Returns {"search": bool, "targeted": bool}.
func decideCellSearch(day:int, now:int, leniencyValue:float, roll:float) -> Dictionary:
	var result:Dictionary = {"search": false, "targeted": false}
	if(int(state.security["cell_check_day"]) == day):
		return result
	state.security["cell_check_day"] = day
	if(!isReady(int(state.security["cell_stamp"]), CELL_SEARCH_COOLDOWN, now)):
		return result
	if(roll < cellSearchChance(getAttention(), leniencyValue)):
		result["search"] = true
		result["targeted"] = getAttention() >= TARGETED_ATTENTION
	return result

# ---- Text ----
static func colored(text:String, color:String) -> String:
	return "[color=" + color + "]" + text + "[/color]"

static func attentionChangeText(delta:float, newValue:float) -> String:
	var rounded:int = int(round(abs(delta)))
	if(rounded <= 0):
		return ""
	if(delta > 0.0):
		return colored("Security attention rises by " + str(rounded) + " (" + label(newValue) + ").", "yellow")
	return colored("Security attention falls by " + str(rounded) + " (" + label(newValue) + ").", "cyan")

func getScreenText(now:int) -> String:
	var attention:float = getAttention()
	var band:Dictionary = bandFor(attention)
	var lines:Array = []
	lines.append("Security attention: " + colored(str(int(round(attention))) + " / 100 - " + band["label"], labelColor(attention)))
	lines.append(band["text"])
	if(wasSearchedRecently(now)):
		lines.append(colored("You were searched recently.", "yellow"))
	else:
		lines.append("You have not been searched recently.")
	var warning:Dictionary = getWarning(now)
	if(!warning.empty()):
		lines.append(colored("Active warning: a guard told you to put some clothes on.", "yellow"))
	var report:String = state.security["last_report"]
	if(report != ""):
		lines.append("Last report: " + report)
	return PoolStringArray(lines).join("\n")

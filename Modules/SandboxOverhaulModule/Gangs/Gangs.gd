extends Reference
class_name GangService

# Prison gangs: membership, two relationship layers, assignments, captives, gang-owned slaves, treasuries and the rules that keep it all paced.
# No game access here: callers pass the facts (traits, feelings, powers, time, dice) so every rule can be tested on its own.
#
# SandboxState.gangs = {
#   "init": bool,                                     the established gangs were created
#   "gangs": {gangID: {"name", "leader", "members": [...], "hangout", "treasury", "created", "player": bool, "slaves": [...],
#                      "income_day", "offer_day", "kidnap_day", "incident_day", "hangout_stamp"}},
#   "relations": {"a|b": -100..100},                  gang to gang, symmetric (key is the two IDs sorted)
#   "personal": {characterID: {gangID: -100..100}},   how that gang regards that character (not Affection, Trust, Respect or Fear)
#   "captives": {characterID: {"gang": captor gang, "kind": "captive" | "slave", "stamp": int, "by": String}}
#   "player": {"intro": {gangID: true}, "expelled": {gangID: {...}}, "harm": {gangID: n}, "losses": {gangID: n}, "warning_day": int, "left_day": int, "left_from": gangID,
#              "orders": {targetID: failed attempts}, "order_stamp": int, "incident_day": int}
#   "assignment": {} or the player's one assignment (see makeOffer),
#   "cooldowns": {key: stamp},
#   "log": [recent events, newest last]
# }
# A stamp is day * 86400 + seconds of day (monotonic). A stamp in the future (a corrupt save) counts as already over, so nothing can stay stuck.

const DAY = 86400
const HOUR = 3600
const REL_MIN = -100
const REL_MAX = 100
const ENEMY_AT = -40
const FRIEND_AT = 40
const TREASURY_MAX = 9999
const LOG_MAX = 12
const PLAYER_GANG_ID = "player"

# ---- The established gangs (hangouts are existing rooms; prefs are weights on the character traits that fit) ----
const ESTABLISHED = [
	{"id": "ironhand", "name": "Ironhand", "emphasis": "combat", "hangout": "gym_weights", "slaves": 0,
		"tag": "Fighters who respect only those who can take a hit.",
		"text": "Fighters who settle things with their fists and respect only those who can take a hit.",
		"recruit": "Wants proven fighters: a good Combat Reputation counts for more.",
		"prefs": {"power": 1.0, "mean": 0.6, "coward": -0.8}},
	{"id": "hushmarket", "name": "The Hush Market", "emphasis": "trade", "hangout": "main_laundry", "slaves": 0,
		"tag": "Quiet dealers in contraband, favours and rumours.",
		"text": "Quiet dealers who move contraband, favours and rumours and avoid a fair fight.",
		"recruit": "Wants people who can be trusted with goods: Trust counts for more.",
		"prefs": {"brat": 0.6, "naive": -0.7, "mean": -0.2, "subby": -0.3}},
	{"id": "collarcircle", "name": "The Collar Circle", "emphasis": "control", "hangout": "eng_workshop", "slaves": 2,
		"tag": "Dominant inmates who expect obedience.",
		"text": "Dominant inmates who keep a few enslaved inmates of their own and expect obedience.",
		"recruit": "Wants people who can command: Respect counts for more.",
		"prefs": {"subby": -1.0, "mean": 0.5, "power": 0.4}},
]
const INITIAL_RELATIONS = {"ironhand|hushmarket": -55, "collarcircle|hushmarket": 45, "collarcircle|ironhand": -10}
const AFFILIATED_SHARE = 0.40 # target share of eligible inmates in a gang: ceil(0.40 * eligible), never more than the eligible
const FORMATION_MIN = 8 # the established gangs form once this many inmates are eligible
const STARTING_TREASURY = 20
const PLAYER_START_TREASURY = 5 # of the 15 credits it costs to found a player gang
const PLAYER_HANGOUTS = ["hall_canteen", "gym_yoga", "mining_shafts_entering", "yard_neargym"]
const ROOM_NAMES = {"gym_weights": "the gym weights room", "main_laundry": "the laundry", "eng_workshop": "the workshop", "hall_canteen": "the canteen", "gym_yoga": "the yoga room", "mining_shafts_entering": "the mine entrance", "yard_neargym": "the yard by the gym"}

# ---- Joining, leaving, standing ----
const JOIN_STANDING = 15.0 # joining needs this much combined regard; below it (but not bad) an introductory job is needed
const JOIN_REJECT_BELOW = -10.0
const IMPRESSION_JOIN_OWN = 5.0
const IMPRESSION_JOIN_RIVAL = -8.0 # the rival gang's modest dislike of someone who picked its enemy
const LEAVE_OWN = -6.0
const LEAVE_RIVAL = 4.0
const EXPEL_OWN = -15.0
const EXPEL_PER_SEVERITY = -10.0
const EXPEL_RIVAL = 3.0
const SWITCH_COOLDOWN_DAYS = 5
const WARNING_AT = -30.0
const EXPEL_AT = -60.0
const WARNING_COOLDOWN_DAYS = 3
const HARM = {"attack": 6.0, "defeat": 4.0, "kidnap": 15.0, "enslave": 25.0, "free_slave": 15.0, "ordered": 8.0}
const RETALIATION_GRACE_DAYS = 2
const RETALIATION_MAX = 2
const RETALIATION_STOP_LOSSES = 2
const RETALIATION_STOP_COMBAT = 40.0
const RETALIATION_STOP_FEAR = 60.0

# ---- Player gang ----
const CREATE_COST = 15
const CREATE_MIN_RESPECT = 40.0
const CREATE_MIN_COMBAT = 5.0
const CREATE_MIN_RECRUITS = 2
const NAME_MIN = 3
const NAME_MAX = 24
const HANGOUT_COOLDOWN = 2 * DAY

# ---- Strength ----
const STRENGTH_BANDS = [[8.0, "Dominant"], [5.0, "Strong"], [2.5, "Established"], [0.0, "Weak"]]
const DETERRENCE = {"Weak": 0.10, "Established": 0.25, "Strong": 0.40, "Dominant": 0.55}

# ---- Assignments ----
const OFFER_COOLDOWN = 2 * DAY
# The rescue job's numbers are named so the code, the screens, the tests and the documentation all use the same ones.
const RESCUE_REWARD = 8
const RESCUE_STANDING = 10
const ASSIGNMENTS = {
	"defeat": {"hours": 48, "reward": 6, "standing": 8, "penalty": 8},
	"deliver": {"hours": 72, "reward": 5, "standing": 8, "penalty": 8},
	"capture": {"hours": 72, "reward": 10, "standing": 12, "penalty": 8},
	"rescue": {"hours": 48, "reward": RESCUE_REWARD, "standing": RESCUE_STANDING, "penalty": 8},
	"courier": {"hours": 72, "reward": 0, "standing": 8, "penalty": 8},
}
const READY_DAYS = 4 # a finished job waits this long for the player to report back before the leader moves on (no penalty)
const COURIER_CREDITS = 8 # what the Hush Market's introductory courier job carries to its recipient
const DELIVER_CREDITS = 6
const INTRO_STANDING = 10.0
const EMPHASIS_ORDER = {"combat": ["defeat", "deliver", "capture"], "trade": ["deliver", "defeat", "capture"], "control": ["capture", "defeat", "deliver"]}

# ---- Captives, slaves, income ----
const CAPTIVE_HOURS = 36
const SLAVE_INCOME = 2
const MEMBER_INCOME_DIVISOR = 3 # one credit a day per three active members...
const MEMBER_INCOME_CAP = 3 # ...at most three
const KIDNAP_COOLDOWN_DAYS = 3
const INCIDENT_COOLDOWN_DAYS = 3

# ---- Player-led actions ----
const ORDER_COST = 5
const ORDER_COOLDOWN = 1 * DAY
const ORDER_MAX_FAILURES = 3
const ORDER_KINDS = ["intimidate", "beat", "capture", "rescue"]

# ---- Membership churn ----
const CHURN_COOLDOWN = 3 * DAY

var state

func _init(_state):
	state = _state

# ---- Pure helpers ----
static func isNumberValue(value) -> bool:
	return (value is int || value is float) && !is_nan(float(value)) && !is_inf(float(value))

static func stamp(day:int, timeOfDay) -> int:
	return day * DAY + posmod(int(timeOfDay), DAY)

static func clampRel(value) -> int:
	return int(clamp(round(float(value)), REL_MIN, REL_MAX)) if isNumberValue(value) else 0

static func relKey(a:String, b:String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

static func relationBand(value) -> String:
	var v:int = clampRel(value)
	if(v <= ENEMY_AT):
		return "enemies"
	if(v >= FRIEND_AT):
		return "friendly"
	return "neutral"

static func personalBand(value) -> String:
	var v:int = clampRel(value)
	if(v <= -60):
		return "hated"
	if(v <= -25):
		return "hostile"
	if(v < 25):
		return "neutral"
	if(v < 60):
		return "respected"
	return "trusted"

static func bandColor(value) -> String:
	var v:int = clampRel(value)
	if(v <= -25):
		return "red"
	if(v >= 25):
		return "green"
	return "cyan"

static func strengthBand(score) -> String:
	var v:float = float(score) if isNumberValue(score) else 0.0
	for entry in STRENGTH_BANDS:
		if(v >= entry[0]):
			return entry[1]
	return "Weak"

static func deterrenceFor(band:String) -> float:
	return float(DETERRENCE.get(band, 0.0))

static func establishedDef(gid:String) -> Dictionary:
	for def in ESTABLISHED:
		if(def["id"] == gid):
			return def
	return {}

static func hangoutName(roomID) -> String:
	return str(ROOM_NAMES.get(roomID, str(roomID)))

const TYPICAL = {"power": 0.9, "mean": 0.0, "subby": 0.0, "coward": 0.5, "naive": 0.5, "brat": 0.5}

# How much better these traits fit a gang than a typical inmate does, so a gang whose preferences happen to add up large does not take everyone.
static func relativeFit(def:Dictionary, traits:Dictionary) -> float:
	return fitScore(def["prefs"], traits) - fitScore(def["prefs"], TYPICAL)

static func fitScore(prefs:Dictionary, traits:Dictionary) -> float:
	var total:float = 0.0
	for key in prefs:
		total += float(prefs[key]) * float(traits.get(key, 0.0))
	return total

# Who would lead: fighters and dominant, mean characters.
static func leaderScore(traits:Dictionary) -> float:
	return float(traits.get("power", 0.0)) + 0.5 * float(traits.get("mean", 0.0)) - 0.5 * float(traits.get("subby", 0.0)) + 0.3 * float(traits.get("respect", 0.0))

static func hashOf(characterID, salt:String) -> int:
	return posmod((salt + str(characterID)).hash(), 1000000)

# Validates a gang name: 3-24 characters of letters, digits, spaces, apostrophes and hyphens. Returns {"ok", "reason", "name"}.
static func validName(rawName) -> Dictionary:
	if(!(rawName is String)):
		return {"ok": false, "reason": "A gang needs a name.", "name": ""}
	var name:String = String(rawName).strip_edges()
	while(name.find("  ") != -1):
		name = name.replace("  ", " ")
	if(name.length() < NAME_MIN):
		return {"ok": false, "reason": "The name needs at least " + str(NAME_MIN) + " characters.", "name": name}
	if(name.length() > NAME_MAX):
		return {"ok": false, "reason": "The name can have at most " + str(NAME_MAX) + " characters.", "name": name}
	for i in range(name.length()):
		var c:String = name.substr(i, 1)
		var code:int = c.ord_at(0)
		var okChar:bool = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || c == " " || c == "'" || c == "-"
		if(!okChar):
			return {"ok": false, "reason": "Use only letters, numbers, spaces, apostrophes and hyphens.", "name": name}
	return {"ok": true, "reason": "", "name": name}

static func defaults() -> Dictionary:
	return {"init": false, "gangs": {}, "relations": {}, "personal": {}, "captives": {},
		"player": {"intro": {}, "known": {}, "refusals": {}, "last_job": {}, "expelled": {}, "harm": {}, "losses": {}, "warning_day": -1, "left_day": -1, "left_from": "", "orders": {}, "order_stamp": -1, "incident_day": -1},
		"assignment": {}, "cooldowns": {}, "log": []}

static func sanitizeInt(value, minimum:int, maximum:int, default:int) -> int:
	return int(clamp(round(float(value)), minimum, maximum)) if isNumberValue(value) else default

static func sanitizeIDList(raw) -> Array:
	var result:Array = []
	if(raw is Array):
		for id in raw:
			if((id is String) && id != "" && !result.has(id)):
				result.append(id)
	return result

# Clean copy of a saved gangs dictionary. Duplicate membership is repaired (the lowest gang ID keeps the character, the player's gang never loses the player),
# a missing leader is replaced, captives and slaves are checked, numbers are clamped, nothing is aliased. Old saves have none.
static func sanitize(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(!(raw is Dictionary)):
		return result
	result["init"] = typeof(raw.get("init")) == TYPE_BOOL && raw["init"]
	var rawGangs = raw.get("gangs")
	var gangIDs:Array = []
	if(rawGangs is Dictionary):
		for gid in rawGangs:
			if((gid is String) && gid != "" && (rawGangs[gid] is Dictionary)):
				gangIDs.append(gid)
	gangIDs.sort()
	var claimed:Dictionary = {}
	var ordered:Array = []
	if(gangIDs.has(PLAYER_GANG_ID)):
		ordered.append(PLAYER_GANG_ID)
	for gid in gangIDs:
		if(gid != PLAYER_GANG_ID):
			ordered.append(gid)
	var slaveOwners:Dictionary = {}
	var memberLists:Dictionary = {}
	for gid in ordered:
		var list:Array = []
		for id in sanitizeIDList(rawGangs[gid].get("members")):
			if(claimed.has(id)):
				continue
			claimed[id] = gid
			list.append(id)
		memberLists[gid] = list
	for gid in ordered:
		var g:Dictionary = rawGangs[gid]
		var isPlayerGang:bool = gid == PLAYER_GANG_ID
		var members:Array = memberLists[gid]
		var slaves:Array = []
		for id in sanitizeIDList(g.get("slaves")):
			if(!claimed.has(id) && !slaveOwners.has(id) && id != "pc"):
				slaveOwners[id] = gid
				slaves.append(id)
		var leader:String = str(g.get("leader")) if (g.get("leader") is String) else ""
		if(members.empty()):
			continue
		if(!members.has(leader)):
			leader = "pc" if (isPlayerGang && members.has("pc")) else members[0]
		var name:String = str(g.get("name")) if (g.get("name") is String) else ""
		name = name.strip_edges().left(NAME_MAX * 2)
		if(name == ""):
			name = str(establishedDef(gid).get("name", gid))
		result["gangs"][gid] = {"name": name, "leader": leader, "members": members, "slaves": slaves,
			"hangout": str(g.get("hangout")) if (g.get("hangout") is String) else "",
			"treasury": sanitizeInt(g.get("treasury"), 0, TREASURY_MAX, 0), "created": sanitizeInt(g.get("created"), -1, 1000000, -1),
			"player": isPlayerGang, "income_day": sanitizeInt(g.get("income_day"), -1, 1000000, -1), "offer_day": sanitizeInt(g.get("offer_day"), -1, 1000000, -1),
			"kidnap_day": sanitizeInt(g.get("kidnap_day"), -1, 1000000, -1), "incident_day": sanitizeInt(g.get("incident_day"), -1, 1000000, -1),
			"hangout_stamp": sanitizeInt(g.get("hangout_stamp"), -1, 1000000000, -1)}
	var relations = raw.get("relations")
	if(relations is Dictionary):
		for key in relations:
			if(!(key is String) || !isNumberValue(relations[key])):
				continue
			var parts:PoolStringArray = String(key).split("|")
			if(parts.size() != 2 || parts[0] == parts[1] || relKey(parts[0], parts[1]) != key):
				continue
			if(result["gangs"].has(parts[0]) && result["gangs"].has(parts[1])):
				result["relations"][key] = clampRel(relations[key])
	var personal = raw.get("personal")
	if(personal is Dictionary):
		for id in personal:
			if(!(id is String) || id == "" || !(personal[id] is Dictionary)):
				continue
			for gid in personal[id]:
				if((gid is String) && result["gangs"].has(gid) && isNumberValue(personal[id][gid]) && clampRel(personal[id][gid]) != 0):
					if(!result["personal"].has(id)):
						result["personal"][id] = {}
					result["personal"][id][gid] = clampRel(personal[id][gid])
	var captives = raw.get("captives")
	if(captives is Dictionary):
		for id in captives:
			var entry = captives[id]
			if(!(id is String) || id == "" || id == "pc" || !(entry is Dictionary)):
				continue
			var kind:String = str(entry.get("kind")) if (entry.get("kind") is String) else ""
			var owner:String = str(entry.get("gang")) if (entry.get("gang") is String) else ""
			if(!["captive", "slave"].has(kind) || !result["gangs"].has(owner)):
				continue
			if(kind == "slave" && slaveOwners.get(id, "") != owner):
				continue
			if(kind == "captive" && (!claimed.has(id) || claimed[id] == owner)):
				continue
			result["captives"][id] = {"gang": owner, "kind": kind, "stamp": sanitizeInt(entry.get("stamp"), -1, 1000000000, -1), "by": str(entry.get("by")) if (entry.get("by") is String) else ""}
	for gid in result["gangs"]:
		var kept:Array = []
		for id in result["gangs"][gid]["slaves"]:
			if(result["captives"].has(id) && result["captives"][id]["kind"] == "slave" && result["captives"][id]["gang"] == gid):
				kept.append(id)
			elif(!result["captives"].has(id)):
				result["captives"][id] = {"gang": gid, "kind": "slave", "stamp": -1, "by": ""}
				kept.append(id)
		result["gangs"][gid]["slaves"] = kept
	var player = raw.get("player")
	if(player is Dictionary):
		var p:Dictionary = result["player"]
		for key in ["intro"]:
			if(player.get(key) is Dictionary):
				for gid in player[key]:
					if((gid is String) && result["gangs"].has(gid) && typeof(player[key][gid]) == TYPE_BOOL && player[key][gid]):
						p[key][gid] = true
		if(player.get("last_job") is Dictionary):
			var last:Dictionary = player["last_job"]
			if((last.get("gang") is String) && result["gangs"].has(last["gang"]) && (last.get("type") is String) && ASSIGNMENTS.has(last["type"])):
				p["last_job"] = {"gang": last["gang"], "type": last["type"], "intro": typeof(last.get("intro")) == TYPE_BOOL && last["intro"], "target": str(last.get("target")) if (last.get("target") is String) else "", "day": sanitizeInt(last.get("day"), -1, 1000000, -1)}
		if(player.get("refusals") is Dictionary):
			for key in player["refusals"]:
				if((key is String) && key != "" && isNumberValue(player["refusals"][key]) && int(player["refusals"][key]) > 0 && p["refusals"].size() < 200):
					p["refusals"][key] = sanitizeInt(player["refusals"][key], 0, 99, 0)
		if(player.get("known") is Dictionary):
			for id in player["known"]:
				if((id is String) && id != "" && id != "pc" && typeof(player["known"][id]) == TYPE_BOOL && player["known"][id] && p["known"].size() < 400):
					p["known"][id] = true
		for key in ["harm", "losses", "orders"]:
			if(player.get(key) is Dictionary):
				for id in player[key]:
					if((id is String) && isNumberValue(player[key][id]) && int(player[key][id]) > 0 && (key == "orders" || result["gangs"].has(id))):
						p[key][id] = sanitizeInt(player[key][id], 0, 999, 0)
		if(player.get("expelled") is Dictionary):
			for gid in player["expelled"]:
				var e = player["expelled"][gid]
				if((gid is String) && result["gangs"].has(gid) && (e is Dictionary)):
					p["expelled"][gid] = {"day": sanitizeInt(e.get("day"), -1, 1000000, -1), "retaliations": sanitizeInt(e.get("retaliations"), 0, 99, 0),
						"over": typeof(e.get("over")) == TYPE_BOOL && e["over"], "reason": str(e.get("reason")).left(120) if (e.get("reason") is String) else ""}
		for key in ["warning_day", "left_day", "incident_day"]:
			p[key] = sanitizeInt(player.get(key), -1, 1000000, -1)
		p["order_stamp"] = sanitizeInt(player.get("order_stamp"), -1, 1000000000, -1)
		if((player.get("left_from") is String) && result["gangs"].has(player["left_from"])):
			p["left_from"] = player["left_from"]
	var assignment = raw.get("assignment")
	if(assignment is Dictionary && !assignment.empty()):
		var a:Dictionary = sanitizeAssignment(assignment, result["gangs"])
		if(!a.empty()):
			# Only an accepted job holds credits back, never more than its reward or what the gang has
			a["reserved"] = int(min(a["reserved"], min(a["reward"], result["gangs"][a["gang"]]["treasury"]))) if (a["state"] == "active" || a["state"] == "ready") else 0
			result["assignment"] = a
	var cooldowns = raw.get("cooldowns")
	if(cooldowns is Dictionary):
		for key in cooldowns:
			if((key is String) && isNumberValue(cooldowns[key])):
				result["cooldowns"][key] = sanitizeInt(cooldowns[key], -1, 1000000000, -1)
	var logRaw = raw.get("log")
	if(logRaw is Array):
		for line in logRaw:
			if(line is String):
				result["log"].append(String(line).left(200))
		while(result["log"].size() > LOG_MAX):
			result["log"].pop_front()
	return result

static func sanitizeAssignment(a:Dictionary, gangs:Dictionary) -> Dictionary:
	var type:String = str(a.get("type")) if (a.get("type") is String) else ""
	var gid:String = str(a.get("gang")) if (a.get("gang") is String) else ""
	var phase:String = str(a.get("state")) if (a.get("state") is String) else ""
	if(!ASSIGNMENTS.has(type) || !gangs.has(gid) || !["offered", "active", "ready"].has(phase)):
		return {}
	return {"id": sanitizeInt(a.get("id"), 0, 1000000000, 0), "gang": gid, "type": type, "state": phase,
		"target": str(a.get("target")) if (a.get("target") is String) else "", "rival": str(a.get("rival")) if (a.get("rival") is String) else "",
		"item": str(a.get("item")) if (a.get("item") is String) else "", "amount": sanitizeInt(a.get("amount"), 0, 999, 0),
		"created": sanitizeInt(a.get("created"), -1, 1000000000, -1), "deadline": sanitizeInt(a.get("deadline"), -1, 1000000000, -1),
		"reward": sanitizeInt(a.get("reward"), 0, 99, 0), "reserved": sanitizeInt(a.get("reserved"), 0, 99, 0), "standing": sanitizeInt(a.get("standing"), 0, 99, 0), "penalty": sanitizeInt(a.get("penalty"), 0, 99, 0),
		"intro": typeof(a.get("intro")) == TYPE_BOOL && a["intro"], "stage": str(a.get("stage")) if (a.get("stage") is String) else ""}

# ---- Reading ----
func data() -> Dictionary:
	return state.gangs

func isInitialized() -> bool:
	return state.gangs["init"]

func gangIDs() -> Array:
	var ids:Array = state.gangs["gangs"].keys()
	ids.sort()
	return ids

func hasGang(gid) -> bool:
	return (gid is String) && state.gangs["gangs"].has(gid)

func gangName(gid) -> String:
	return state.gangs["gangs"][gid]["name"] if hasGang(gid) else "no gang"

func getGang(gid) -> Dictionary:
	return state.gangs["gangs"][gid].duplicate(true) if hasGang(gid) else {}

func getLeader(gid) -> String:
	return state.gangs["gangs"][gid]["leader"] if hasGang(gid) else ""

func getMembers(gid) -> Array:
	return state.gangs["gangs"][gid]["members"].duplicate() if hasGang(gid) else []

func getHangout(gid) -> String:
	return state.gangs["gangs"][gid]["hangout"] if hasGang(gid) else ""

func gangOf(characterID) -> String:
	for gid in state.gangs["gangs"]:
		if(state.gangs["gangs"][gid]["members"].has(characterID)):
			return gid
	return ""

func isMember(characterID, gid) -> bool:
	return hasGang(gid) && state.gangs["gangs"][gid]["members"].has(characterID)

func isLeader(characterID, gid) -> bool:
	return hasGang(gid) && state.gangs["gangs"][gid]["leader"] == characterID

func playerGang() -> String:
	return gangOf("pc")

func ownsPlayerGang() -> bool:
	return hasGang(PLAYER_GANG_ID)

func slaveOwner(characterID) -> String:
	var entry:Dictionary = state.gangs["captives"].get(characterID, {})
	return entry["gang"] if (!entry.empty() && entry["kind"] == "slave") else ""

func isInAnyGang(characterID) -> bool:
	return gangOf(characterID) != ""

# ---- Log ----
func addLog(text:String) -> void:
	state.gangs["log"].append(text.left(200))
	while(state.gangs["log"].size() > LOG_MAX):
		state.gangs["log"].pop_front()

func getLog() -> Array:
	return state.gangs["log"].duplicate()

# ---- Cooldowns ----
func isReady(key:String, cooldown:int, now:int) -> bool:
	var last:int = int(state.gangs["cooldowns"].get(key, -1))
	return last < 0 || last > now || now - last >= cooldown

func markCooldown(key:String, now:int) -> void:
	state.gangs["cooldowns"][key] = now

# ---- Gang to gang relations (symmetric) ----
func getRelation(a, b) -> int:
	if(!(a is String) || !(b is String) || a == b || !hasGang(a) || !hasGang(b)):
		return 0
	return clampRel(state.gangs["relations"].get(relKey(a, b), 0))

func setRelation(a, b, value) -> int:
	if(!(a is String) || !(b is String) || a == b || !hasGang(a) || !hasGang(b)):
		return 0
	var v:int = clampRel(value)
	if(v == 0):
		state.gangs["relations"].erase(relKey(a, b))
	else:
		state.gangs["relations"][relKey(a, b)] = v
	return v

func addRelation(a, b, amount) -> int:
	return setRelation(a, b, getRelation(a, b) + float(amount))

func areEnemies(a, b) -> bool:
	return a != b && getRelation(a, b) <= ENEMY_AT

func enemiesOf(gid) -> Array:
	var result:Array = []
	for other in gangIDs():
		if(other != gid && areEnemies(gid, other)):
			result.append(other)
	return result

# ---- Personal relation (how the gang regards the character; directed, separate from the gang to gang relation) ----
func getPersonal(characterID, gid) -> int:
	if(!(characterID is String) || !hasGang(gid)):
		return 0
	return clampRel(state.gangs["personal"].get(characterID, {}).get(gid, 0))

func setPersonal(characterID, gid, value) -> int:
	if(!(characterID is String) || characterID == "" || !hasGang(gid)):
		return 0
	var v:int = clampRel(value)
	if(v == 0):
		if(state.gangs["personal"].has(characterID)):
			state.gangs["personal"][characterID].erase(gid)
			if(state.gangs["personal"][characterID].empty()):
				state.gangs["personal"].erase(characterID)
	else:
		if(!state.gangs["personal"].has(characterID)):
			state.gangs["personal"][characterID] = {}
		state.gangs["personal"][characterID][gid] = v
	return v

# Adds to the personal relation and returns the change that really happened.
func addPersonal(characterID, gid, amount) -> int:
	var before:int = getPersonal(characterID, gid)
	return setPersonal(characterID, gid, before + float(amount)) - before

# The one answer AI decisions ask: what a gang thinks of a character overall. The two parts stay separate so both can be shown.
# official = the relation between the gang and the character's own gang (100 for their own gang); score = personal + half of official.
func effectiveStatus(characterID, gid) -> Dictionary:
	var personal:int = getPersonal(characterID, gid)
	var own:String = gangOf(characterID)
	var official:int = 0
	if(own != "" && own == gid):
		official = 100
	elif(own != "" && hasGang(gid)):
		official = getRelation(own, gid)
	var score:int = int(clamp(round(float(personal) + 0.5 * float(official)), REL_MIN, REL_MAX))
	var hostile:bool = own != gid && score <= ENEMY_AT
	return {"personal": personal, "official": official, "score": score, "hostile": hostile, "label": personalBand(score)}

# ---- Harm history (kept after leaving: personal relations are never reset) ----
func recordHarm(characterID, victimGid, kind:String) -> int:
	if(!hasGang(victimGid) || !HARM.has(kind)):
		return 0
	var delta:int = addPersonal(characterID, victimGid, -float(HARM[kind]))
	if(characterID == "pc" && kind != "defeat"):
		state.gangs["player"]["harm"][victimGid] = int(state.gangs["player"]["harm"].get(victimGid, 0)) + 1
	return delta

func harmCount(gid) -> int:
	return int(state.gangs["player"]["harm"].get(gid, 0))

func recordLoss(gid) -> void:
	state.gangs["player"]["losses"][gid] = int(state.gangs["player"]["losses"].get(gid, 0)) + 1

func lossCount(gid) -> int:
	return int(state.gangs["player"]["losses"].get(gid, 0))

# ---- Membership ----
# Can this character join this gang, and what is missing? ctx: trust, respect (the leader's, or the NPC's, towards the character), combat (Combat Reputation), day.
# Returns {"ok", "needsIntro", "reasons": [...], "score"}. A character already in a gang must leave it first.
func joinCheck(characterID, gid, ctx:Dictionary) -> Dictionary:
	var reasons:Array = []
	if(!hasGang(gid)):
		return {"ok": false, "needsIntro": false, "reasons": ["There is no such gang."], "score": 0.0}
	var own:String = gangOf(characterID)
	if(own == gid):
		return {"ok": false, "needsIntro": false, "reasons": ["You are already in this gang."], "score": 0.0}
	if(own != ""):
		return {"ok": false, "needsIntro": false, "reasons": ["Leave your current gang first."], "score": 0.0}
	if(getLeader(gid) == "" || state.gangs["gangs"][gid]["player"] && characterID == "pc"):
		return {"ok": false, "needsIntro": false, "reasons": ["There is no one to talk to there."], "score": 0.0}
	var today:int = int(ctx.get("day", 0))
	var p:Dictionary = state.gangs["player"]
	if(characterID == "pc" && p["left_from"] != "" && p["left_day"] >= 0 && p["left_day"] <= today && today - p["left_day"] < SWITCH_COOLDOWN_DAYS && (areEnemies(p["left_from"], gid) || p["left_from"] == gid)):
		reasons.append("You only just left " + gangName(p["left_from"]) + ". Give it a few days before joining " + ("them again." if p["left_from"] == gid else "their enemies."))
	var expelled:Dictionary = p["expelled"].get(gid, {}) if characterID == "pc" else {}
	if(!expelled.empty() && !expelled.get("over", false)):
		reasons.append("They threw you out and have not finished with you.")
	var personal:int = getPersonal(characterID, gid)
	var trust:float = clamp(float(ctx.get("trust", 0.0)), -100.0, 100.0)
	var respect:float = clamp(float(ctx.get("respect", 0.0)), -100.0, 100.0)
	var combat:float = clamp(float(ctx.get("combat", 0.0)), -100.0, 100.0)
	var emphasis:String = str(establishedDef(gid).get("emphasis", ""))
	var combatWeight:float = 0.3 if emphasis == "combat" else 0.15
	var trustWeight:float = 0.4 if emphasis == "trade" else 0.25
	var respectWeight:float = 0.4 if emphasis == "control" else 0.25
	var score:float = float(personal) + trust * trustWeight + respect * respectWeight + combat * combatWeight
	var harm:int = harmCount(gid) if characterID == "pc" else 0
	score -= 6.0 * min(harm, 5)
	if(characterID == "pc"):
		# Being hated by a gang's friends counts a little against you
		for friend in gangIDs():
			if(friend != gid && getRelation(friend, gid) >= FRIEND_AT):
				score += min(0.0, float(getPersonal(characterID, friend))) * 0.15
	var needsIntro:bool = false
	if(!reasons.empty()):
		return {"ok": false, "needsIntro": false, "reasons": reasons, "score": score}
	if(personal <= JOIN_REJECT_BELOW || score < JOIN_REJECT_BELOW):
		reasons.append("They do not trust you: " + (str(harm) + " of their people were hurt on your account. " if harm > 0 else "your history with them is bad. ") + "Earn it back with favours, time or by helping their people.")
		return {"ok": false, "needsIntro": false, "reasons": reasons, "score": score}
	if(score < JOIN_STANDING):
		if(characterID == "pc" && p["intro"].get(gid, false)):
			needsIntro = false
		else:
			needsIntro = true
			reasons.append("They want to see what you can do first: do a job for them.")
	return {"ok": !needsIntro, "needsIntro": needsIntro, "reasons": reasons, "score": score}

# Joins the gang. The new member inherits the gang's enemies (that is just the relations table) and the rival gangs take a modest dislike to them.
# Returns {"ok", "impressions": {gangID: change}}.
func join(characterID, gid, _day:int) -> Dictionary:
	if(!hasGang(gid) || gangOf(characterID) != "" || !(characterID is String) || characterID == ""):
		return {"ok": false, "impressions": {}}
	var g:Dictionary = state.gangs["gangs"][gid]
	g["members"].append(characterID)
	if(g["leader"] == "" || !g["members"].has(g["leader"])):
		g["leader"] = characterID
	var impressions:Dictionary = {}
	impressions[gid] = addPersonal(characterID, gid, IMPRESSION_JOIN_OWN)
	for rival in enemiesOf(gid):
		impressions[rival] = addPersonal(characterID, rival, IMPRESSION_JOIN_RIVAL)
	if(characterID == "pc"):
		state.gangs["player"]["left_day"] = -1
		state.gangs["player"]["left_from"] = ""
	return {"ok": true, "impressions": impressions}

# Removes a member (no personal relation changes). Returns the gang they were in. A leader leaving passes leadership on; an empty NPC gang dissolves.
func removeMember(characterID, leaderScores:Dictionary = {}) -> String:
	var gid:String = gangOf(characterID)
	if(gid == ""):
		return ""
	var g:Dictionary = state.gangs["gangs"][gid]
	g["members"].erase(characterID)
	state.gangs["captives"].erase(characterID)
	repairLeader(gid, leaderScores)
	return gid

# Leadership is repaired deterministically: the best leader score, ties by character ID. The player's own gang keeps the player while they are in it.
func repairLeader(gid, leaderScores:Dictionary = {}) -> void:
	if(!hasGang(gid)):
		return
	var g:Dictionary = state.gangs["gangs"][gid]
	if(g["members"].empty()):
		g["leader"] = ""
		dissolveIfEmpty(gid)
		return
	if(g["members"].has(g["leader"])):
		return
	if(g["player"] && g["members"].has("pc")):
		g["leader"] = "pc"
		return
	var best:String = ""
	var bestScore:float = -1.0e9
	var members:Array = g["members"].duplicate()
	members.sort()
	for id in members:
		var s:float = float(leaderScores.get(id, 0.0))
		if(best == "" || s > bestScore):
			best = id
			bestScore = s
	g["leader"] = best

# Empty NPC gangs dissolve (with their slaves freed); the player's gang never dissolves while the player leads it. Returns true when it did.
func dissolveIfEmpty(gid) -> bool:
	if(!hasGang(gid)):
		return false
	var g:Dictionary = state.gangs["gangs"][gid]
	if(!g["members"].empty()):
		return false
	if(g["player"] && (g["leader"] == "pc" || playerGang() == gid)):
		return false
	for id in g["slaves"]:
		state.gangs["captives"].erase(id)
	for id in state.gangs["captives"].keys():
		if(state.gangs["captives"][id]["gang"] == gid):
			state.gangs["captives"].erase(id)
	state.gangs["gangs"].erase(gid)
	for key in state.gangs["relations"].keys():
		if(key.split("|").has(gid)):
			state.gangs["relations"].erase(key)
	for id in state.gangs["personal"].keys():
		state.gangs["personal"][id].erase(gid)
		if(state.gangs["personal"][id].empty()):
			state.gangs["personal"].erase(id)
	if(!state.gangs["assignment"].empty() && state.gangs["assignment"]["gang"] == gid):
		state.gangs["assignment"] = {}
	return true

# Voluntary leaving: the old gang regards you a little less, its enemies a little more. Serious history with the rivals is left alone.
func leave(characterID, day:int, leaderScores:Dictionary = {}) -> Dictionary:
	var gid:String = gangOf(characterID)
	if(gid == ""):
		return {"ok": false, "gang": "", "impressions": {}}
	var enemies:Array = enemiesOf(gid)
	var impressions:Dictionary = {}
	impressions[gid] = addPersonal(characterID, gid, LEAVE_OWN)
	for rival in enemies:
		impressions[rival] = addPersonal(characterID, rival, LEAVE_RIVAL)
	var _removed:String = removeMember(characterID, leaderScores)
	if(characterID == "pc"):
		state.gangs["player"]["left_day"] = day
		state.gangs["player"]["left_from"] = gid
		if(state.gangs["assignment"].get("gang", "") == gid):
			state.gangs["assignment"] = {}
	return {"ok": true, "gang": gid, "impressions": impressions}

# Expulsion hits harder, by how bad the reason was (severity 1-3), and the rivals approve only a little. For the player it starts a retaliation grace period.
func expel(characterID, reason:String, severity:int, day:int, leaderScores:Dictionary = {}) -> Dictionary:
	var gid:String = gangOf(characterID)
	if(gid == ""):
		return {"ok": false, "gang": "", "impressions": {}}
	var level:int = int(clamp(severity, 1, 3))
	var enemies:Array = enemiesOf(gid)
	var impressions:Dictionary = {}
	impressions[gid] = addPersonal(characterID, gid, EXPEL_OWN + EXPEL_PER_SEVERITY * level)
	for rival in enemies:
		impressions[rival] = addPersonal(characterID, rival, EXPEL_RIVAL)
	var _removed:String = removeMember(characterID, leaderScores)
	if(characterID == "pc"):
		var p:Dictionary = state.gangs["player"]
		p["left_day"] = day
		p["left_from"] = gid
		p["expelled"][gid] = {"day": day, "retaliations": 0, "over": false, "reason": reason.left(120)}
		if(state.gangs["assignment"].get("gang", "") == gid):
			state.gangs["assignment"] = {}
	return {"ok": true, "gang": gid, "impressions": impressions, "reason": reason}

# Standing is the player's personal relation with their own gang. Returns {"event": "" | "warning" | "expel", "reason"}.
func checkStanding(day:int) -> Dictionary:
	var gid:String = playerGang()
	if(gid == "" || state.gangs["gangs"][gid]["player"]):
		return {"event": "", "reason": ""}
	var standing:int = getPersonal("pc", gid)
	if(standing <= EXPEL_AT):
		return {"event": "expel", "reason": "your standing with them collapsed"}
	var last:int = int(state.gangs["player"]["warning_day"])
	if(standing <= WARNING_AT && (last < 0 || last > day || day - last >= WARNING_COOLDOWN_DAYS)):
		state.gangs["player"]["warning_day"] = day
		return {"event": "warning", "reason": "your standing is low"}
	return {"event": "", "reason": ""}

# Betrayals that skip the warning: attacking or kidnapping a member, enslaving one, helping a rival. Returns the standing lost.
func recordBetrayal(gid, kind:String) -> int:
	if(!hasGang(gid)):
		return 0
	var amount:float = float(HARM.get(kind, 8.0))
	return addPersonal("pc", gid, -amount)

# ---- Retaliation after an expulsion: one beating attempt, then it stops if the player keeps winning, is feared or has a reputation ----
func retaliationState(gid) -> Dictionary:
	return state.gangs["player"]["expelled"].get(gid, {}).duplicate(true)

# ctx: day, combat (Combat Reputation), fear (the retaliating members' Fear of the player, highest). Returns true when the gang should come for the player now.
func retaliationDue(gid, ctx:Dictionary) -> bool:
	var e:Dictionary = state.gangs["player"]["expelled"].get(gid, {})
	if(e.empty() || e["over"] || !hasGang(gid)):
		return false
	var day:int = int(ctx.get("day", 0))
	if(e["day"] < 0 || day < e["day"] + RETALIATION_GRACE_DAYS || e["retaliations"] >= RETALIATION_MAX):
		return false
	if(stopsRetaliation(gid, ctx)):
		return false
	return true

func stopsRetaliation(gid, ctx:Dictionary) -> bool:
	return lossCount(gid) >= RETALIATION_STOP_LOSSES || float(ctx.get("combat", 0.0)) >= RETALIATION_STOP_COMBAT || float(ctx.get("fear", 0.0)) >= RETALIATION_STOP_FEAR

# Marks one retaliation attempt; after the last one, or once it should stop, the matter is over.
func markRetaliation(gid, ctx:Dictionary) -> void:
	var e:Dictionary = state.gangs["player"]["expelled"].get(gid, {})
	if(e.empty()):
		return
	e["retaliations"] += 1
	if(e["retaliations"] >= RETALIATION_MAX || stopsRetaliation(gid, ctx)):
		e["over"] = true

func closeRetaliations(ctx:Dictionary) -> Array:
	var closed:Array = []
	for gid in state.gangs["player"]["expelled"].keys():
		var e:Dictionary = state.gangs["player"]["expelled"][gid]
		if(!e["over"] && stopsRetaliation(gid, ctx)):
			e["over"] = true
			closed.append(gid)
	return closed

func pendingRetaliation() -> bool:
	for gid in state.gangs["player"]["expelled"]:
		if(!state.gangs["player"]["expelled"][gid]["over"]):
			return true
	return false

# ---- Pruning ----
# Removes characters that no longer exist from every list; captives whose captor gang or data went missing are simply released. Returns what was removed.
func pruneMissing(validIDs:Array) -> Array:
	var removed:Array = []
	var seen:Dictionary = {}
	for id in validIDs:
		seen[id] = true
	for gid in gangIDs():
		if(!hasGang(gid)):
			continue
		var g:Dictionary = state.gangs["gangs"][gid]
		for id in g["members"].duplicate():
			if(id != "pc" && !seen.has(id)):
				var _r:String = removeMember(id)
				removed.append(id)
		if(!hasGang(gid)):
			continue
		for id in g["slaves"].duplicate():
			if(!seen.has(id)):
				g["slaves"].erase(id)
				state.gangs["captives"].erase(id)
				removed.append(id)
	for id in state.gangs["captives"].keys():
		if(!seen.has(id) || !hasGang(state.gangs["captives"][id]["gang"])):
			state.gangs["captives"].erase(id)
	for id in state.gangs["personal"].keys():
		if(id != "pc" && !seen.has(id)):
			state.gangs["personal"].erase(id)
	var assignment:Dictionary = state.gangs["assignment"]
	if(!assignment.empty()):
		for key in ["target", "rival"]:
			if(assignment[key] != "" && !seen.has(assignment[key]) && assignment[key] != "pc" && key == "target"):
				state.gangs["assignment"] = {}
				break
	for id in state.gangs["player"]["orders"].keys():
		if(!seen.has(id)):
			state.gangs["player"]["orders"].erase(id)
	return removed

# ---- Strength ----
# Sum over active (free) members of 0.5 + level / 20, a leader bonus and a small bonus for the player's Combat Reputation in their own gang. powers: id -> level-based power.
func strength(gid, powers:Dictionary, combatReputation:float = 0.0) -> float:
	if(!hasGang(gid)):
		return 0.0
	var g:Dictionary = state.gangs["gangs"][gid]
	var total:float = 0.0
	for id in g["members"]:
		if(state.gangs["captives"].has(id)):
			continue
		total += float(powers.get(id, 0.5))
		if(id == "pc" && combatReputation > 0.0):
			total += combatReputation / 50.0
	return total

func strengthBandOf(gid, powers:Dictionary, combatReputation:float = 0.0) -> String:
	return strengthBand(strength(gid, powers, combatReputation))

func activeMembers(gid) -> Array:
	var result:Array = []
	for id in getMembers(gid):
		if(!state.gangs["captives"].has(id)):
			result.append(id)
	return result

# ---- Captives and gang-owned slaves ----
# The player has learned which gang this character belongs to (by asking, by a job, by a fight, or because they are in the player's own gang).
func learnGang(characterID) -> bool:
	if(!(characterID is String) || characterID == "" || characterID == "pc" || gangOf(characterID) == "" || state.gangs["player"]["known"].has(characterID)):
		return false
	state.gangs["player"]["known"][characterID] = true
	return true

func knowsGang(characterID) -> bool:
	if(!(characterID is String) || characterID == "pc" || gangOf(characterID) == ""):
		return false
	var own:String = playerGang()
	if(own != "" && gangOf(characterID) == own):
		return true
	return state.gangs["player"]["known"].has(characterID)

# How often the player has refused a call for help from this gang's members or from this character (an owner). Kept for later systems to react to.
func addRefusal(key) -> int:
	if(!(key is String) || key == ""):
		return 0
	state.gangs["player"]["refusals"][key] = int(min(99, int(state.gangs["player"]["refusals"].get(key, 0)) + 1))
	return int(state.gangs["player"]["refusals"][key])

func refusalCount(key) -> int:
	return int(state.gangs["player"]["refusals"].get(key, 0))

func isCaptive(characterID) -> bool:
	return state.gangs["captives"].has(characterID)

# Held against their will right now (a captured member). A gang's slaves are in the same table but are not "detained": they keep their routine.
func isDetained(characterID) -> bool:
	return state.gangs["captives"].get(characterID, {}).get("kind", "") == "captive"

func getCaptive(characterID) -> Dictionary:
	return state.gangs["captives"].get(characterID, {}).duplicate(true)

func captivesOf(gid) -> Array:
	var result:Array = []
	for id in state.gangs["captives"]:
		if(state.gangs["captives"][id]["kind"] == "captive" && gangOf(id) == gid):
			result.append(id)
	result.sort()
	return result

func heldBy(gid) -> Array:
	var result:Array = []
	for id in state.gangs["captives"]:
		if(state.gangs["captives"][id]["gang"] == gid):
			result.append(id)
	result.sort()
	return result

# A gang member is taken by another gang for a bounded time. Returns {"ok", "reason"}.
func capture(characterID, byGid, now:int, capturedBy:String = "") -> Dictionary:
	if(!(characterID is String) || characterID == "pc" || !hasGang(byGid)):
		return {"ok": false, "reason": "invalid"}
	var own:String = gangOf(characterID)
	if(own == ""):
		return {"ok": false, "reason": "They belong to no gang."}
	if(own == byGid):
		return {"ok": false, "reason": "They are in the same gang."}
	if(isCaptive(characterID) || slaveOwner(characterID) != ""):
		return {"ok": false, "reason": "They are already held."}
	state.gangs["captives"][characterID] = {"gang": byGid, "kind": "captive", "stamp": now, "by": capturedBy}
	return {"ok": true, "reason": ""}

func release(characterID) -> Dictionary:
	var entry:Dictionary = state.gangs["captives"].get(characterID, {})
	if(entry.empty()):
		return {}
	state.gangs["captives"].erase(characterID)
	if(entry["kind"] == "slave" && hasGang(entry["gang"])):
		state.gangs["gangs"][entry["gang"]]["slaves"].erase(characterID)
	return entry

# Captives that have been held for their time escape. Returns [{"id", "gang"}].
func expireCaptives(now:int) -> Array:
	var escaped:Array = []
	for id in state.gangs["captives"].keys():
		var entry:Dictionary = state.gangs["captives"][id]
		if(entry["kind"] != "captive"):
			continue
		var expired:bool = entry["stamp"] < 0 || entry["stamp"] > now || now - entry["stamp"] >= CAPTIVE_HOURS * HOUR
		if(expired):
			state.gangs["captives"].erase(id)
			escaped.append({"id": id, "gang": entry["gang"]})
	return escaped

# A character becomes a gang-owned slave: not a member of anything, not already held, never the player.
func addSlave(characterID, gid) -> Dictionary:
	if(!(characterID is String) || characterID == "" || characterID == "pc" || !hasGang(gid)):
		return {"ok": false, "reason": "invalid"}
	if(isCaptive(characterID) || gangOf(characterID) != ""):
		return {"ok": false, "reason": "They are held or in a gang."}
	state.gangs["gangs"][gid]["slaves"].append(characterID)
	state.gangs["captives"][characterID] = {"gang": gid, "kind": "slave", "stamp": -1, "by": ""}
	return {"ok": true, "reason": ""}

# Frees a gang-owned slave. Returns the owning gang (or "").
func freeSlave(characterID) -> String:
	var owner:String = slaveOwner(characterID)
	if(owner == ""):
		return ""
	var _r:Dictionary = release(characterID)
	return owner

# Once a day each gang's treasury receives one credit per three active (free) members, at most 3, plus 2 per slave. Returns {gangID: amount}.
# A gang is paid once per day; running it again the same day pays nothing.
func collectIncome(day:int) -> Dictionary:
	var paid:Dictionary = {}
	for gid in gangIDs():
		var g:Dictionary = state.gangs["gangs"][gid]
		if(g["income_day"] >= 0 && g["income_day"] >= day):
			continue
		g["income_day"] = day
		var amount:int = memberIncome(gid) + SLAVE_INCOME * g["slaves"].size()
		if(amount <= 0):
			continue
		g["treasury"] = int(clamp(g["treasury"] + amount, 0, TREASURY_MAX))
		paid[gid] = amount
	return paid

func memberIncome(gid) -> int:
	return int(min(MEMBER_INCOME_CAP, floor(float(activeMembers(gid).size()) / float(MEMBER_INCOME_DIVISOR))))

# ---- Treasury ----
# The credits promised for the player's accepted assignment are held back inside the assignment itself, so they cannot be spent on anything else and cannot be paid twice.
func getTreasury(gid) -> int:
	return int(state.gangs["gangs"][gid]["treasury"]) if hasGang(gid) else 0

func reservedAmount(gid) -> int:
	var a:Dictionary = state.gangs["assignment"]
	if(!a.empty() && a["gang"] == gid && (a["state"] == "active" || a["state"] == "ready")):
		return int(a["reserved"])
	return 0

# What the gang can spend or promise: the treasury minus what is reserved.
func availableTreasury(gid) -> int:
	return int(max(0, getTreasury(gid) - reservedAmount(gid)))

func addTreasury(gid, amount:int) -> int:
	if(!hasGang(gid)):
		return 0
	var g:Dictionary = state.gangs["gangs"][gid]
	g["treasury"] = int(clamp(g["treasury"] + amount, 0, TREASURY_MAX))
	return g["treasury"]

func spendableTreasury(gid, amount:int) -> bool:
	return hasGang(gid) && availableTreasury(gid) >= amount

func pendingRetaliationFrom(gid) -> bool:
	var e:Dictionary = state.gangs["player"]["expelled"].get(gid, {})
	return !e.empty() && !e["over"]

# Spends unreserved credits. Reserved ones are never touched.
func spendTreasury(gid, amount:int) -> bool:
	if(!hasGang(gid) || amount < 0 || availableTreasury(gid) < amount):
		return false
	state.gangs["gangs"][gid]["treasury"] -= amount
	return true

# ---- Initialisation of the established gangs (deterministic) ----
# entries: eligible inmates as {"id", "power", "mean", "subby", "coward", "naive", "brat", "respect"}. Nothing happens below FORMATION_MIN (8) eligible inmates.
# From 8 up each gang forms with exactly one member, who leads it: for each gang in turn the unclaimed inmate with the best fit for the gang plus half the leader score
# (ties by ID). Control-focused gangs also take the most submissive unclaimed inmates as slaves when there are at least ten. Everyone else is recruited later, two a day,
# by topUp, until about 40% belong to a gang. Nothing is reshuffled once it has run. Returns the number of affiliated inmates (0 when it did not form).
func initialize(entries:Array, day:int) -> int:
	if(state.gangs["init"]):
		return 0
	var pool:Array = []
	for entry in entries:
		if((entry is Dictionary) && (entry.get("id") is String) && entry["id"] != "" && entry["id"] != "pc"):
			pool.append(entry)
	if(pool.size() < FORMATION_MIN):
		return 0
	pool.sort_custom(self, "_byHash")
	for def in ESTABLISHED:
		state.gangs["gangs"][def["id"]] = {"name": def["name"], "leader": "", "members": [], "slaves": [], "hangout": def["hangout"], "treasury": STARTING_TREASURY, "created": day,
			"player": false, "income_day": -1, "offer_day": -1, "kidnap_day": -1, "incident_day": -1, "hangout_stamp": -1}
	for key in INITIAL_RELATIONS:
		var parts:PoolStringArray = String(key).split("|")
		var _v:int = setRelation(parts[0], parts[1], INITIAL_RELATIONS[key])
	var taken:Dictionary = {}
	for def in ESTABLISHED:
		var best:String = ""
		var bestScore:float = -1.0e9
		for entry in pool:
			if(taken.has(entry["id"])):
				continue
			var score:float = relativeFit(def, entry) + 0.5 * leaderScore(entry)
			if(best == "" || score > bestScore || (score == bestScore && entry["id"] < best)):
				best = entry["id"]
				bestScore = score
		var g:Dictionary = state.gangs["gangs"][def["id"]]
		g["members"].append(best)
		g["leader"] = best
		taken[best] = true
	var rest:Array = []
	for entry in pool:
		if(!taken.has(entry["id"])):
			rest.append(entry)
	rest.sort_custom(self, "_bySubmissive")
	var slaveCursor:int = 0
	for def in ESTABLISHED:
		var wanted:int = int(def["slaves"]) if pool.size() >= 10 else 0
		for _n in range(wanted):
			if(slaveCursor < rest.size()):
				var _s:Dictionary = addSlave(rest[slaveCursor]["id"], def["id"])
				slaveCursor += 1
	state.gangs["init"] = true
	addLog("The prison's gangs settle into their places.")
	return taken.size()

# How many of this many eligible inmates should belong to a gang: ceil(0.40 * eligible), never more than the eligible themselves.
static func affiliationTarget(total:int) -> int:
	return int(min(max(0, total), ceil(AFFILIATED_SHARE * float(max(0, total)))))

# The established gang whose preferences fit these traits best among the gangs that are not already bigger than the smallest by more than one (ties by gang order). "" when none exists.
func bestGangFor(traits:Dictionary) -> String:
	var best:String = ""
	var bestFit:float = -1.0e9
	var smallest:int = 1000000
	for def in ESTABLISHED:
		if(hasGang(def["id"])):
			smallest = int(min(smallest, getMembers(def["id"]).size()))
	for def in ESTABLISHED:
		# Only gangs no more than one member bigger than the smallest are candidates, so growth keeps the gangs about the same size
		if(!hasGang(def["id"]) || getMembers(def["id"]).size() > smallest + 1):
			continue
		var fit:float = relativeFit(def, traits)
		if(fit > bestFit):
			bestFit = fit
			best = def["id"]
	return best

# Growth: while fewer than affiliationTarget(total) eligible inmates belong to a gang, recruit the unaffiliated ones with the lowest stable hash into their best-fitting gang,
# at most maxJoins at a time (the caller runs it once a day, with 2). Never removes anyone. unaffiliated: entries of eligible inmates without a gang. Returns [{"id", "gang"}].
func topUp(unaffiliated:Array, affiliated:int, total:int, maxJoins:int, day:int) -> Array:
	var joined:Array = []
	var pool:Array = unaffiliated.duplicate()
	pool.sort_custom(self, "_byHash")
	var count:int = affiliated
	var target:int = affiliationTarget(total)
	for entry in pool:
		if(joined.size() >= maxJoins || count >= target):
			break
		var gid:String = bestGangFor(entry)
		if(gid == "" || entry["id"] == "pc" || gangOf(entry["id"]) != "" || isCaptive(entry["id"])):
			continue
		var result:Dictionary = join(entry["id"], gid, day)
		if(result["ok"]):
			joined.append({"id": entry["id"], "gang": gid})
			count += 1
	return joined

func _byHash(a, b) -> bool:
	var ha:int = hashOf(a["id"], "gang")
	var hb:int = hashOf(b["id"], "gang")
	return ha < hb || (ha == hb && a["id"] < b["id"])

func _bySubmissive(a, b) -> bool:
	var sa:float = float(a.get("subby", 0.0))
	var sb:float = float(b.get("subby", 0.0))
	return sa > sb || (sa == sb && a["id"] < b["id"])

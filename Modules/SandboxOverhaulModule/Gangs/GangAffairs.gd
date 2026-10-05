extends Reference
class_name GangAffairs

# What the gangs do and what the player can ask of them: the player's own gang, assignments, ordered actions, incidents, abstract conflicts, membership churn and
# protection. Pure like GangService: callers pass the facts and the dice (floats 0..1), the rules live here.

const ServiceScript = preload("res://Modules/SandboxOverhaulModule/Gangs/Gangs.gd")

const PLAYER_GANG_MAX_MEMBERS = 12
const INCIDENT_BASE = 0.06 # per day per hostile gang with someone around, before the factors below
const INCIDENT_CAP = 0.30
const ABSTRACT_CONFLICT_CHANCE = 0.20
const ABSTRACT_KIDNAP_CHANCE = 0.30
const VICTIM_MEMORY = 3 * ServiceScript.DAY
const CHURN_LEAVE_BELOW = -60.0 # a member's Trust plus Respect towards their leader
const CHURN_DEFECT_ABOVE = 80.0 # towards another gang's leader
const CHURN_LEAVE_CHANCE = 0.5
const CHURN_DEFECT_CHANCE = 0.3
const LEADER_EXPELS_BELOW = -50.0 # the leader's own Trust in a member
const PROTECTION_FLOOR = 0.2
const PROTECTION_CEILING = 1.6

var state
var gangs # the GangService

func _init(_state, _gangs):
	state = _state
	gangs = _gangs

# ---- The player's own gang ----
# ctx: combat (Combat Reputation), respect (the best individual Respect towards the player among inmates), recruits (how many eligible inmates are willing), credits.
# Requires positive Combat Reputation (5 or more) OR strong Respect (40 or more), two willing inmates, 15 credits, no gang of their own and no unfinished retaliation.
func canCreate(ctx:Dictionary) -> Dictionary:
	var reasons:Array = []
	if(gangs.playerGang() != ""):
		reasons.append("You are already in a gang.")
	if(gangs.ownsPlayerGang()):
		reasons.append("You already lead a gang.")
	if(gangs.pendingRetaliation()):
		reasons.append("A gang you were thrown out of is still after you.")
	if(float(ctx.get("combat", 0.0)) < ServiceScript.CREATE_MIN_COMBAT && float(ctx.get("respect", 0.0)) < ServiceScript.CREATE_MIN_RESPECT):
		reasons.append("Nobody follows someone they do not respect: you need a Combat Reputation of at least " + str(int(ServiceScript.CREATE_MIN_COMBAT)) + ", or an inmate with a lot of respect for you.")
	if(int(ctx.get("recruits", 0)) < ServiceScript.CREATE_MIN_RECRUITS):
		reasons.append("At least " + str(ServiceScript.CREATE_MIN_RECRUITS) + " inmates must be willing to follow you.")
	if(int(ctx.get("credits", 0)) < ServiceScript.CREATE_COST):
		reasons.append("Setting up costs " + str(ServiceScript.CREATE_COST) + " credits.")
	return {"ok": reasons.empty(), "reasons": reasons}

func freeHangouts() -> Array:
	var used:Dictionary = {}
	for gid in gangs.gangIDs():
		used[gangs.getHangout(gid)] = true
	var result:Array = []
	for room in ServiceScript.PLAYER_HANGOUTS:
		if(!used.has(room)):
			result.append(room)
	return result

# Creates the player's gang. The player leads it. The cost is paid by the caller. Returns {"ok", "reason"}.
func createPlayerGang(rawName, hangout, memberIDs:Array, day:int) -> Dictionary:
	var named:Dictionary = ServiceScript.validName(rawName)
	if(!named["ok"]):
		return {"ok": false, "reason": named["reason"]}
	if(gangs.playerGang() != "" || gangs.ownsPlayerGang()):
		return {"ok": false, "reason": "You already have a gang."}
	for gid in gangs.gangIDs():
		if(gangs.gangName(gid).to_lower() == named["name"].to_lower()):
			return {"ok": false, "reason": "A gang with that name exists."}
	if(!freeHangouts().has(hangout)):
		return {"ok": false, "reason": "That place is not available."}
	var members:Array = ["pc"]
	for id in memberIDs:
		if((id is String) && id != "pc" && !members.has(id) && gangs.gangOf(id) == "" && !gangs.isCaptive(id) && members.size() < PLAYER_GANG_MAX_MEMBERS):
			members.append(id)
	if(members.size() < 1 + ServiceScript.CREATE_MIN_RECRUITS):
		return {"ok": false, "reason": "Not enough willing members."}
	state.gangs["gangs"][ServiceScript.PLAYER_GANG_ID] = {"name": named["name"], "leader": "pc", "members": members, "slaves": [], "hangout": hangout, "treasury": ServiceScript.PLAYER_START_TREASURY, "created": day,
		"player": true, "income_day": -1, "offer_day": -1, "kidnap_day": -1, "incident_day": -1, "hangout_stamp": -1}
	for id in members:
		var _a:int = gangs.addPersonal(id, ServiceScript.PLAYER_GANG_ID, 5.0)
	gangs.addLog(named["name"] + " is founded.")
	return {"ok": true, "reason": ""}

func inviteMember(characterID, willing:bool) -> Dictionary:
	var gid:String = ServiceScript.PLAYER_GANG_ID
	if(!gangs.isLeader("pc", gid)):
		return {"ok": false, "reason": "Only the leader can invite."}
	if(!(characterID is String) || characterID == "" || characterID == "pc"):
		return {"ok": false, "reason": "Nobody to invite."}
	if(gangs.gangOf(characterID) != "" || gangs.isCaptive(characterID)):
		return {"ok": false, "reason": "They already belong somewhere or are held."}
	if(gangs.getMembers(gid).size() >= PLAYER_GANG_MAX_MEMBERS):
		return {"ok": false, "reason": "The gang is full."}
	if(!willing):
		return {"ok": false, "reason": "They do not want to follow you."}
	state.gangs["gangs"][gid]["members"].append(characterID)
	var _a:int = gangs.addPersonal(characterID, gid, 5.0)
	return {"ok": true, "reason": ""}

func removeFromPlayerGang(characterID) -> Dictionary:
	var gid:String = ServiceScript.PLAYER_GANG_ID
	if(!gangs.isLeader("pc", gid)):
		return {"ok": false, "reason": "Only the leader can do that."}
	if(characterID == "pc" || !gangs.isMember(characterID, gid)):
		return {"ok": false, "reason": "They are not a member."}
	var _r:String = gangs.removeMember(characterID)
	return {"ok": true, "reason": ""}

func changeHangout(room, now:int) -> Dictionary:
	var gid:String = ServiceScript.PLAYER_GANG_ID
	if(!gangs.isLeader("pc", gid)):
		return {"ok": false, "reason": "Only the leader can do that."}
	var g:Dictionary = state.gangs["gangs"][gid]
	if(g["hangout_stamp"] >= 0 && g["hangout_stamp"] <= now && now - g["hangout_stamp"] < ServiceScript.HANGOUT_COOLDOWN):
		return {"ok": false, "reason": "You moved recently. Wait a day or two."}
	if(room == g["hangout"] || !freeHangouts().has(room)):
		return {"ok": false, "reason": "That place is not available."}
	g["hangout"] = room
	g["hangout_stamp"] = now
	return {"ok": true, "reason": ""}

# The leader disbands the gang (the only way the player's gang ends while they lead it). Members are released without penalty.
func disbandPlayerGang() -> bool:
	var gid:String = ServiceScript.PLAYER_GANG_ID
	if(!gangs.isLeader("pc", gid)):
		return false
	for id in gangs.getMembers(gid):
		var _r:String = gangs.removeMember(id)
	var _d:bool = gangs.dissolveIfEmpty(gid)
	return !gangs.hasGang(gid)

# ---- Assignments ----
func getAssignment() -> Dictionary:
	return state.gangs["assignment"].duplicate(true)

func hasAssignment() -> bool:
	return !state.gangs["assignment"].empty()

func nextAssignmentID() -> int:
	var id:int = int(state.gangs["cooldowns"].get("assignment_id", 0)) + 1
	state.gangs["cooldowns"]["assignment_id"] = id
	return id

# Whether the player has finished this gang's introductory job (they are eligible to join it).
func hasIntroDone(gid) -> bool:
	return bool(state.gangs["player"]["intro"].get(gid, false))

# Whether the leader of the player's NPC gang can offer something now: a member in good standing, nothing active, a two-day gap since the last offer.
func canOffer(now:int) -> Dictionary:
	var gid:String = gangs.playerGang()
	if(gid == "" || state.gangs["gangs"][gid]["player"]):
		return {"ok": false, "reason": "You are not in a gang with a leader to give you work."}
	if(hasAssignment()):
		return {"ok": false, "reason": "You already have a job from them."}
	if(gangs.getPersonal("pc", gid) < 0):
		return {"ok": false, "reason": "They do not trust you with work right now."}
	if(!gangs.isReady("offer", ServiceScript.OFFER_COOLDOWN, now)):
		return {"ok": false, "reason": "They have nothing new for you yet."}
	return {"ok": true, "reason": ""}

func buildAssignment(gid:String, type:String, now:int, target:String, rival:String, item:String, amount:int, intro:bool) -> Dictionary:
	var rules:Dictionary = ServiceScript.ASSIGNMENTS[type]
	var credits:int = int(rules["reward"])
	var standing:int = int(rules["standing"])
	if(type == "deliver" && item == ""):
		credits = 0
	if(intro):
		credits = 0
		standing = int(ServiceScript.INTRO_STANDING)
	return {"id": nextAssignmentID(), "gang": gid, "type": type, "state": "offered", "target": target, "rival": rival, "item": item, "amount": amount, "created": now,
		"deadline": now + int(rules["hours"]) * ServiceScript.HOUR, "reward": credits, "reserved": 0, "standing": standing, "penalty": int(rules["penalty"]), "intro": intro, "stage": ""}

# The leader's offer. ctx: rivals (free members of gangs hostile to this one), heldMembers (this gang's captured members), captors (a member of the gang holding each, same order),
# contrabandItem (an item ID the player carries that is safe to hand over, or ""), day. The gang's emphasis decides what it prefers. Returns the offer or {}.
func makeOffer(ctx:Dictionary, now:int) -> Dictionary:
	var check:Dictionary = canOffer(now)
	if(!check["ok"]):
		return {}
	var gid:String = gangs.playerGang()
	var emphasis:String = str(ServiceScript.establishedDef(gid).get("emphasis", "combat"))
	var held:Array = ctx.get("heldMembers", [])
	var rivals:Array = ctx.get("rivals", [])
	var offer:Dictionary = {}
	if(!held.empty()):
		var captors:Array = ctx.get("captors", [])
		offer = buildAssignment(gid, "rescue", now, held[0], str(captors[0]) if !captors.empty() else "", "", 0, false)
	else:
		for type in ServiceScript.EMPHASIS_ORDER.get(emphasis, ["defeat"]):
			var candidate:Dictionary = {}
			if(type == "deliver"):
				var item:String = str(ctx.get("contrabandItem", ""))
				candidate = buildAssignment(gid, "deliver", now, "", "", item, 0 if item != "" else ServiceScript.DELIVER_CREDITS, false)
			elif(!rivals.empty()):
				var index:int = int(posmod(ServiceScript.hashOf(str(ctx.get("day", 0)) + gid, "offer"), rivals.size()))
				candidate = buildAssignment(gid, type, now, rivals[index], "", "", 0, false)
			# A paid job the gang cannot fund is not offered; the next kind is tried
			if(!candidate.empty() && candidate["reward"] <= gangs.availableTreasury(gid)):
				offer = candidate
				break
	# A rescue is the one job that may be offered unpaid, and says so
	if(!offer.empty() && offer["reward"] > gangs.availableTreasury(gid)):
		if(offer["type"] == "rescue"):
			offer["reward"] = 0
		else:
			offer = {}
	if(offer.empty()):
		return {}
	state.gangs["assignment"] = offer
	state.gangs["cooldowns"]["offer"] = now
	return offer.duplicate(true)

# The introductory job a leader gives someone who is not respected enough yet. It shows what the gang is about: Ironhand wants a rival beaten, the Hush Market wants a package taken to a
# friend of the market, the Collar Circle wants a rival beaten and brought in. ctx: rivals (valid members of gangs this one is not friends with), recipients (valid members of gangs
# friendly or at least not hostile to this one), day. Returns the offer, or {} when there is nobody to name (the leader says to come back later).
func makeIntro(gid:String, now:int, ctx:Dictionary = {}) -> Dictionary:
	if(!gangs.hasGang(gid) || hasAssignment() || gangs.playerGang() != ""):
		return {}
	var emphasis:String = str(ServiceScript.establishedDef(gid).get("emphasis", "combat"))
	var rivals:Array = ctx.get("rivals", [])
	var recipients:Array = ctx.get("recipients", [])
	var day:int = int(ctx.get("day", 0))
	var offer:Dictionary = {}
	if(emphasis == "trade"):
		if(recipients.empty()):
			return {}
		var pick:String = str(recipients[int(posmod(ServiceScript.hashOf(str(day) + gid, "courier"), recipients.size()))])
		offer = buildAssignment(gid, "courier", now, pick, "", "", ServiceScript.COURIER_CREDITS, true)
	else:
		if(rivals.empty()):
			return {}
		var target:String = str(rivals[int(posmod(ServiceScript.hashOf(str(day) + gid, "intro"), rivals.size()))])
		offer = buildAssignment(gid, "capture" if emphasis == "control" else "defeat", now, target, "", "", 0, true)
	state.gangs["assignment"] = offer
	return offer.duplicate(true)

# A finished job (a defeat, a courier delivery, a rescue) is not paid until the player reports back to the leader in person.
func markReady(now:int) -> bool:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || a["state"] != "active"):
		return false
	a["state"] = "ready"
	a["stage"] = "done"
	a["deadline"] = now + ServiceScript.READY_DAYS * ServiceScript.DAY
	return true

func canReport() -> bool:
	return !state.gangs["assignment"].empty() && state.gangs["assignment"]["state"] == "ready"

# Whether this character is the recipient of the player's active courier job.
func canCourier(recipientID, now:int) -> bool:
	var a:Dictionary = state.gangs["assignment"]
	return !a.empty() && a["state"] == "active" && a["type"] == "courier" && a["stage"] == "" && a["target"] == recipientID && now <= a["deadline"]

func completeCourier(now:int) -> bool:
	if(!canCourier(state.gangs["assignment"].get("target", ""), now)):
		return false
	return markReady(now)

# Accepting reserves the job's credit reward from the offering gang's treasury (it is not paid yet). If the gang can no longer fund it, nothing is accepted.
func accept(now:int) -> bool:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || a["state"] != "offered"):
		return false
	if(a["reward"] > gangs.availableTreasury(a["gang"])):
		return false
	a["state"] = "active"
	a["reserved"] = a["reward"]
	a["deadline"] = now + int(ServiceScript.ASSIGNMENTS[a["type"]]["hours"]) * ServiceScript.HOUR
	return true

# Declining is not failure: no penalty, just a gap before the next offer.
func decline(now:int) -> bool:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || a["state"] != "offered"):
		return false
	state.gangs["assignment"] = {}
	state.gangs["cooldowns"]["offer"] = now
	return true

# Applies the reward once and clears the assignment, so loading cannot pay twice. Returns {"credits", "standing", "gang", "intro", "respect"} or {}.
func complete(now:int) -> Dictionary:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || (a["state"] != "active" && a["state"] != "ready")):
		return {}
	var gid:String = a["gang"]
	var standing:int = gangs.addPersonal("pc", gid, a["standing"])
	if(a["intro"]):
		state.gangs["player"]["intro"][gid] = true
	# The reserved credits leave the treasury here, once: the assignment is cleared below, so a second completion finds nothing to pay
	var paid:int = int(min(a["reserved"], gangs.getTreasury(gid)))
	state.gangs["gangs"][gid]["treasury"] -= paid
	var result:Dictionary = {"credits": paid, "standing": standing, "gang": gid, "intro": a["intro"], "respect": 6 if a["intro"] else 3, "trust": 6 if a["intro"] else 2, "type": a["type"], "amount": a["amount"], "target": a["target"]}
	state.gangs["player"]["last_job"] = {"gang": gid, "type": a["type"], "intro": a["intro"], "target": a["target"], "day": int(now / ServiceScript.DAY)} # the Side Tasks list keeps the latest finished job
	state.gangs["assignment"] = {}
	state.gangs["cooldowns"]["offer"] = now
	return result

# The player failed an accepted job: a modest standing loss, once.
func fail(now:int) -> Dictionary:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || a["state"] != "active"):
		return {}
	var gid:String = a["gang"]
	var lost:int = gangs.addPersonal("pc", gid, -float(a["penalty"]))
	state.gangs["assignment"] = {}
	state.gangs["cooldowns"]["offer"] = now
	return {"gang": gid, "standing": lost, "type": a["type"]}

func cancel(now:int) -> void:
	state.gangs["assignment"] = {}
	state.gangs["cooldowns"]["offer"] = now

# A fight the player won (or an NPC surrendered). Only a defeat of the assigned target within the deadline counts: a defeat job is done, a capture job is ready to hand over,
# and a rescue job can also be settled by beating the captor. Returns {"event": "" | "completed" | "defeated" | "rival_beaten", "result": {...}}.
func onPlayerWon(lostID:String, now:int) -> Dictionary:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || a["state"] != "active" || now > a["deadline"]):
		return {"event": "", "result": {}}
	if(a["type"] == "defeat" && a["target"] == lostID):
		var _ready:bool = markReady(now)
		return {"event": "ready", "result": {}}
	if(a["type"] == "capture" && a["target"] == lostID && a["stage"] == ""):
		a["stage"] = "defeated"
		return {"event": "defeated", "result": {}}
	if(a["type"] == "rescue" && a["rival"] != "" && a["rival"] == lostID):
		var _ready2:bool = markReady(now)
		return {"event": "ready", "result": {}}
	return {"event": "", "result": {}}

# Whether a deliver job can be handed over (the caller then removes the item or credits atomically and calls complete).
func canDeliver(now:int) -> bool:
	var a:Dictionary = state.gangs["assignment"]
	return !a.empty() && a["state"] == "active" && a["type"] == "deliver" && now <= a["deadline"]

# Hands the defeated capture target over: the target becomes the gang's captive. Returns {"ok", "reason", "result"}.
func handOverCaptive(now:int) -> Dictionary:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty() || a["state"] != "active" || a["type"] != "capture" || a["stage"] != "defeated" || now > a["deadline"]):
		return {"ok": false, "reason": "There is nobody to hand over.", "result": {}}
	var held:Dictionary = gangs.capture(a["target"], a["gang"], now, "pc")
	if(!held["ok"]):
		cancel(now)
		return {"ok": false, "reason": "That is no longer possible, so the job is dropped.", "result": {}}
	var gid:String = gangs.gangOf(a["target"])
	var harm:int = gangs.recordHarm("pc", gid, "kidnap")
	return {"ok": true, "reason": "", "result": complete(now), "harm": harm, "victimGang": gid}

# A captive was freed by the player. Settles a rescue job for that captive.
func onRescued(captiveID:String, now:int) -> Dictionary:
	var a:Dictionary = state.gangs["assignment"]
	if(!a.empty() && a["state"] == "active" && a["type"] == "rescue" && a["target"] == captiveID):
		return {"event": "ready"} if markReady(now) else {}
	return {}

# Time passing. validIDs are the characters that still exist. An unfinished job past its deadline fails (once); a job whose target is gone or no longer valid is cancelled with no penalty.
# Returns {"event": "" | "failed" | "cancelled", ...}.
func checkExpiry(now:int, validIDs:Array) -> Dictionary:
	var a:Dictionary = state.gangs["assignment"]
	if(a.empty()):
		return {"event": ""}
	if(a["target"] != "" && !validIDs.has(a["target"])):
		cancel(now)
		return {"event": "cancelled", "reason": "the target is gone"}
	if(a["state"] == "ready"):
		if(now > a["deadline"]):
			cancel(now)
			return {"event": "cancelled", "reason": "the leader has moved on and no longer needs the report"}
		return {"event": ""}
	if(a["type"] == "rescue" && !gangs.isCaptive(a["target"])):
		cancel(now)
		return {"event": "cancelled", "reason": "they are free already"}
	if(a["type"] == "courier" && (a["target"] == "" || gangs.gangOf(a["target"]) == "")):
		cancel(now)
		return {"event": "cancelled", "reason": "the person it was for is not around any more"}
	if(a["type"] == "defeat" && a["target"] != "" && a["stage"] == "" && (gangs.gangOf(a["target"]) == "" || gangs.gangOf(a["target"]) == a["gang"])):
		cancel(now)
		return {"event": "cancelled", "reason": "the target is no longer in a rival gang"}
	if(a["type"] == "capture" && a["target"] != "" && (gangs.isCaptive(a["target"]) || gangs.gangOf(a["target"]) == "")):
		cancel(now)
		return {"event": "cancelled", "reason": "the target is no longer available"}
	if(a["state"] == "offered" && now - a["created"] > 2 * ServiceScript.DAY):
		cancel(now)
		return {"event": "cancelled", "reason": "the offer lapsed"}
	if(a["state"] == "active" && now > a["deadline"]):
		var failed:Dictionary = fail(now)
		failed["event"] = "failed"
		return failed
	return {"event": ""}

# ---- Ordered actions ----
# Chance of success: the gang's strength against the target's power, the target's Fear of the player, and how many members are free. Between 10% and 90%.
static func orderSuccess(gangStrength:float, targetPower:float, targetFear:float, members:int) -> float:
	var ratio:float = gangStrength / max(0.5, targetPower)
	var chance:float = 0.35 + 0.15 * (ratio - 1.0) + clamp(targetFear, 0.0, 100.0) / 400.0 + 0.04 * min(members, 5)
	return clamp(chance, 0.10, 0.90)

# ctx: day, now, members (free members available), targetOk (false for guards, staff, story characters, own members, enslaved...), targetGang, captiveOwner.
func canOrder(kind:String, targetID, ctx:Dictionary) -> Dictionary:
	var gid:String = ServiceScript.PLAYER_GANG_ID
	if(!gangs.isLeader("pc", gid)):
		return {"ok": false, "reason": "Only a gang leader can give orders."}
	if(!ServiceScript.ORDER_KINDS.has(kind)):
		return {"ok": false, "reason": "Unknown order."}
	var now:int = int(ctx.get("now", 0))
	var last:int = int(state.gangs["player"]["order_stamp"])
	if(last >= 0 && last <= now && now - last < ServiceScript.ORDER_COOLDOWN):
		return {"ok": false, "reason": "Your people need a day before the next order."}
	if(!(targetID is String) || targetID == "" || !ctx.get("targetOk", false)):
		return {"ok": false, "reason": "You cannot send your people after that one."}
	if(int(state.gangs["player"]["orders"].get(targetID, 0)) >= ServiceScript.ORDER_MAX_FAILURES):
		return {"ok": false, "reason": "Your people have failed against them too often to try again."}
	if(!gangs.spendableTreasury(gid, ServiceScript.ORDER_COST)):
		return {"ok": false, "reason": "The treasury has less than " + str(ServiceScript.ORDER_COST) + " credits."}
	if(kind == "rescue"):
		if(!gangs.isCaptive(targetID) || gangs.gangOf(targetID) != gid):
			return {"ok": false, "reason": "That person is not one of your held members."}
		if(int(ctx.get("members", 0)) < 1):
			return {"ok": false, "reason": "You have nobody free to send."}
	else:
		if(int(ctx.get("members", 0)) < 2):
			return {"ok": false, "reason": "You need at least two free members for that."}
		if(gangs.gangOf(targetID) == gid):
			return {"ok": false, "reason": "They are one of yours."}
		if(kind == "capture" && gangs.gangOf(targetID) == ""):
			return {"ok": false, "reason": "Only members of other gangs can be taken."}
		if(gangs.isCaptive(targetID)):
			return {"ok": false, "reason": "They are already held."}
	return {"ok": true, "reason": "", "cost": ServiceScript.ORDER_COST}

# Carries the order out. The treasury is charged, the cooldown starts, failures are counted. roll: 0..1 for success, pick: 0..1 to choose which member is hurt or held on failure.
# Nobody is ever deleted: the chosen member stays in the gang and either becomes a temporary captive of the target's gang ("lostCaptured") or, when the target has no gang,
# is left to the caller to injure.
# Returns {"success", "chance", "kind", "target", "targetGang", "lost": id or "", "lostCaptured": bool, "harm": change}.
func resolveOrder(kind:String, targetID:String, successChance:float, roll:float, pick:float, now:int) -> Dictionary:
	var gid:String = ServiceScript.PLAYER_GANG_ID
	var _spent:bool = gangs.spendTreasury(gid, ServiceScript.ORDER_COST)
	state.gangs["player"]["order_stamp"] = now
	var victimGang:String = gangs.gangOf(targetID)
	var success:bool = roll < successChance
	var result:Dictionary = {"success": success, "chance": successChance, "kind": kind, "target": targetID, "targetGang": victimGang, "lost": "", "lostCaptured": false, "harm": 0}
	if(success):
		state.gangs["player"]["orders"].erase(targetID)
		if(kind == "capture"):
			var held:Dictionary = gangs.capture(targetID, gid, now, "pc")
			result["success"] = held["ok"]
			if(held["ok"] && victimGang != ""):
				result["harm"] = gangs.recordHarm("pc", victimGang, "kidnap")
		elif(kind == "rescue"):
			var captor:String = str(gangs.getCaptive(targetID).get("gang", ""))
			var _r:Dictionary = gangs.release(targetID)
			if(captor != ""):
				result["targetGang"] = captor
				result["harm"] = gangs.recordHarm("pc", captor, "ordered")
		elif(victimGang != ""):
			result["harm"] = gangs.recordHarm("pc", victimGang, "ordered")
	else:
		state.gangs["player"]["orders"][targetID] = int(state.gangs["player"]["orders"].get(targetID, 0)) + 1
		var pool:Array = gangs.activeMembers(gid)
		pool.erase("pc")
		pool.erase(gangs.getLeader(gid))
		pool.sort()
		if(!pool.empty()):
			var lost:String = pool[int(clamp(int(pick * pool.size()), 0, pool.size() - 1))]
			result["lost"] = lost
			if(victimGang != "" && kind != "rescue"):
				var held2:Dictionary = gangs.capture(lost, victimGang, now, targetID)
				result["lostCaptured"] = held2["ok"]
	return result

# ---- Incidents against the player ----
# One major gang incident a day at most, a three-day gap per gang. A gang that regards the player as hostile may send someone, less so if the player is feared,
# the gang is weak, guards are about or security attention is high. ctx: day, guards (free guards in the player's room), attention (0-100), fear (best Fear any of that
# gang's members has of the player), powers, combat. Returns the gang ID that attacks, or "".
func incidentGang(ctx:Dictionary, rolls:Array) -> String:
	var day:int = int(ctx.get("day", 0))
	if(int(ctx.get("guards", 0)) > 0 || state.gangs["player"]["incident_day"] == day):
		return ""
	var index:int = 0
	var own:String = gangs.playerGang()
	for gid in gangs.gangIDs():
		if(gid == own):
			continue
		var status:Dictionary = gangs.effectiveStatus("pc", gid)
		if(!status["hostile"] || gangs.activeMembers(gid).empty()):
			continue
		var g:Dictionary = state.gangs["gangs"][gid]
		if(g["incident_day"] >= 0 && g["incident_day"] <= day && day - g["incident_day"] < ServiceScript.INCIDENT_COOLDOWN_DAYS):
			continue
		if(gangs.pendingRetaliationFrom(gid)):
			continue
		var power:float = gangs.strength(gid, ctx.get("powers", {}))
		var chance:float = INCIDENT_BASE * (1.0 + float(-status["score"] - 40) / 60.0) * clamp(power / 4.0, 0.4, 1.6)
		chance *= 1.0 - clamp(float(ctx.get("fear", 0.0)), 0.0, 100.0) / 150.0
		chance *= 1.0 - clamp(float(ctx.get("attention", 0.0)), 0.0, 100.0) / 150.0
		chance *= pow(0.7, min(gangs.lossCount(gid), 4))
		chance = clamp(chance, 0.0, INCIDENT_CAP)
		var roll:float = float(rolls[index]) if rolls.size() > index else 1.0
		index += 1
		if(roll < chance):
			return gid
	return ""

func markIncident(gid:String, day:int) -> void:
	state.gangs["player"]["incident_day"] = day
	if(gangs.hasGang(gid)):
		state.gangs["gangs"][gid]["incident_day"] = day

# ---- Gangs acting on their own ----
# Once a day each pair of enemy gangs may clash, abstractly. The stronger one may take an isolated member of the weaker one (a three-day gap per gang, never the same
# victim twice in three days, never a leader). Returns [{"type": "skirmish" | "kidnap", "gangs": [a, b], "victim": id, "by": gid}]. rolls are used in pairs.
func abstractConflicts(day:int, now:int, powers:Dictionary, rolls:Array) -> Array:
	var events:Array = []
	var ids:Array = gangs.gangIDs()
	var index:int = 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a:String = ids[i]
			var b:String = ids[j]
			if(!gangs.areEnemies(a, b)):
				continue
			var r1:float = float(rolls[index]) if rolls.size() > index else 1.0
			var r2:float = float(rolls[index + 1]) if rolls.size() > index + 1 else 1.0
			index += 2
			if(r1 >= ABSTRACT_CONFLICT_CHANCE):
				continue
			var strong:String = a if gangs.strength(a, powers) >= gangs.strength(b, powers) else b
			var weak:String = b if strong == a else a
			var _d:int = gangs.addRelation(a, b, -2)
			var event:Dictionary = {"type": "skirmish", "gangs": [a, b], "victim": "", "by": strong}
			var g:Dictionary = state.gangs["gangs"][strong]
			var ready:bool = g["kidnap_day"] < 0 || g["kidnap_day"] > day || day - g["kidnap_day"] >= ServiceScript.KIDNAP_COOLDOWN_DAYS
			if(r2 < ABSTRACT_KIDNAP_CHANCE && ready):
				var victim:String = pickVictim(weak, powers, now)
				if(victim != ""):
					var held:Dictionary = gangs.capture(victim, strong, now, "")
					if(held["ok"]):
						g["kidnap_day"] = day
						state.gangs["cooldowns"]["victim|" + victim] = now
						event = {"type": "kidnap", "gangs": [a, b], "victim": victim, "by": strong}
			events.append(event)
	return events

# The weakest free member who is not the leader and was not taken recently.
func pickVictim(gid:String, powers:Dictionary, now:int) -> String:
	var best:String = ""
	var bestPower:float = 1.0e9
	var members:Array = gangs.activeMembers(gid)
	members.sort()
	for id in members:
		if(id == "pc" || id == gangs.getLeader(gid) || !gangs.isReady("victim|" + id, VICTIM_MEMORY, now)):
			continue
		var power:float = float(powers.get(id, 0.5))
		if(best == "" || power < bestPower):
			best = id
			bestPower = power
	return best

# Occasionally someone leaves, defects or is expelled, for a stated reason, at most one change every three days.
# views: [{"id", "gang", "leaderTrust" (their Trust plus Respect towards their leader), "leaderRegard" (the leader's Trust in them), "bestOther" (gang ID), "bestOtherValue"}]
# Returns {} or {"type": "leave" | "defect" | "expel", "id", "from", "to", "reason"}. The change is applied.
func churn(now:int, powers:Dictionary, views:Array, roll:float) -> Dictionary:
	if(!gangs.isReady("churn", ServiceScript.CHURN_COOLDOWN, now)):
		return {}
	for view in views:
		var id:String = view["id"]
		var gid:String = view["gang"]
		if(id == "pc" || !gangs.isMember(id, gid) || gangs.isLeader(id, gid) || gangs.isCaptive(id) || state.gangs["gangs"][gid]["player"]):
			continue
		var change:Dictionary = {}
		if(float(view.get("leaderRegard", 0.0)) <= LEADER_EXPELS_BELOW):
			change = {"type": "expel", "id": id, "from": gid, "to": "", "reason": "the leader no longer trusts them"}
		elif(float(view.get("leaderTrust", 0.0)) <= CHURN_LEAVE_BELOW && roll < CHURN_LEAVE_CHANCE):
			change = {"type": "leave", "id": id, "from": gid, "to": "", "reason": "they lost faith in their leader"}
		elif(str(view.get("bestOther", "")) != "" && float(view.get("bestOtherValue", 0.0)) >= CHURN_DEFECT_ABOVE && roll < CHURN_DEFECT_CHANCE && gangs.strength(view["bestOther"], powers) >= gangs.strength(gid, powers)):
			change = {"type": "defect", "id": id, "from": gid, "to": view["bestOther"], "reason": "they admire the leader of a stronger gang"}
		if(change.empty()):
			continue
		var _removed:String = gangs.removeMember(id)
		if(change["type"] == "defect"):
			var _j:Dictionary = gangs.join(id, change["to"], 0)
		gangs.markCooldown("churn", now)
		return change
	return {}

# ---- Protection ----
# Multiplier for how keen an NPC is to attack the player. Members' gangs deter independents (by their strength), rivals stay dangerous, gangmates barely attack, and a gang the
# player keeps beating loses interest. Never immunity: between 0.2 and 1.6. powers: id -> power.
func protectionMultiplier(attackerID, powers:Dictionary, combatReputation:float = 0.0) -> float:
	var own:String = gangs.playerGang()
	var theirs:String = gangs.gangOf(attackerID)
	var m:float = 1.0
	if(own != ""):
		var band:String = gangs.strengthBandOf(own, powers, combatReputation)
		if(theirs == own):
			m *= 0.2
		elif(theirs != "" && gangs.areEnemies(theirs, own)):
			m *= 1.25
		else:
			m *= 1.0 - ServiceScript.deterrenceFor(band)
	if(theirs != "" && theirs != own):
		var status:Dictionary = gangs.effectiveStatus("pc", theirs)
		if(status["hostile"]):
			m *= 1.2
		m *= pow(0.85, min(gangs.lossCount(theirs), 4))
	return clamp(m, PROTECTION_FLOOR, PROTECTION_CEILING)

# ---- Text ----
static func colored(text:String, color:String) -> String:
	return "[color=" + color + "]" + text + "[/color]"

func describeAssignment(a:Dictionary, names:Dictionary, now:int) -> String:
	if(a.empty()):
		return "No current job."
	var gang:String = gangs.gangName(a["gang"])
	var hours:int = int(max(0, ceil(float(a["deadline"] - now) / float(ServiceScript.HOUR))))
	if(a["state"] == "ready"):
		return "[color=green]Done.[/color] Report back to " + str(names.get("leader", "the leader")) + " in person to be paid and thanked."
	var timeText:String = ("about " + str(hours) + " hours left") if a["state"] == "active" else "offered, not yet accepted"
	var target:String = str(names.get(a["target"], a["target"]))
	var line:String = ""
	match a["type"]:
		"defeat":
			line = "Defeat " + target + " (a rival of " + gang + ") in a fight."
		"deliver":
			line = "Bring " + gang + (str(a["amount"]) + " credits." if a["item"] == "" else " the item they asked for.")
		"capture":
			line = "Beat " + target + (", then hand them over to " + gang + "." if a["stage"] == "defeated" else " and hand them over.")
		"rescue":
			line = "Free " + target + ", held by a rival, or beat the rival " + str(names.get(a["rival"], "who took them")) + "."
		"courier":
			line = "Take " + str(a["amount"]) + " credits from " + gang + " to " + target + " of " + gangs.gangName(gangs.gangOf(a["target"])) + " and report back." if a["stage"] == "" else "You delivered it."
	var reward:String = (colored(str(a["reward"]) + " credits", "green") + " (from " + gang + "'s treasury) and " if a["reward"] > 0 else colored("no credits", "yellow") + ", only ") + colored("standing +" + str(a["standing"]), "green")
	return line + " (" + timeText + "). Reward: " + reward + ". Failing: " + colored("standing -" + str(a["penalty"]), "red") + "." + (" Completing this could earn you a place in " + gang + "." if a["intro"] else "")

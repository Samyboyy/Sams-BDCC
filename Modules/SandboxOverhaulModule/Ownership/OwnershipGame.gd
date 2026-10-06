extends Reference

# Static glue between the ownership rules (Ownership.gd) and the running game: BDCC's own SoftSlavery (the player owned by an NPC) and NPC slavery (the player owning NPCs) stay exactly where they
# are, and this reads them, adds the obligations and consequences on top, and keeps the characters involved as ordinary persistent inmates with real cells, real routines and real places on the map.

const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const StyleScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnerStyle.gd")
const AftermathScript = preload("res://Modules/SandboxOverhaulModule/Relationships/SexAftermath.gd")
const TextScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipText.gd")
const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")

const PopulationScript = preload("res://Modules/SandboxOverhaulModule/Prison/PopulationDirector.gd")

const COLOR_GOOD = "green"
const COLOR_BAD = "red"
const COLOR_INFO = "cyan"
const COLOR_WARN = "yellow"

const EARN_WINDOW = [16 * 3600, 18 * 3600]
const ATTEND_WINDOWS = [[10 * 3600, 12 * 3600], [17 * 3600 + 1800, 20 * 3600]]
const REPORT_WINDOW = [19 * 3600 + 1800, 21 * 3600 + 1800]
const REST_WINDOW = [8 * 3600, 20 * 3600]
const EXIT_ROOM = "hall_mainentrance"
const EARN_ROOMS = ["fight_wall_east", "main_hallroom5", "main_hallroom4"]
const DEMAND_HOURS = [8 * 3600, 20 * 3600] # owners make demands in the daytime
const PROTECTION_FLOOR_TOTAL = 0.1 # the lowest an attacker's interest can be pushed by everything together (gang, fear, reputation, owner)
const TREAT_COST = 3
const REWARD_COST = 3

# ---- Access ----
static func module():
	return GlobalRegistry.getModule("SandboxOverhaulModule")

static func isReady() -> bool:
	var m = module()
	return m != null && m.isMainReady() && GM.main.IS != null

static func svc():
	return module().getOwnership()

static func rel():
	return module().getRelationships()

static func nameOf(characterID) -> String:
	return module().characterName(characterID)

static func today() -> int:
	return GM.main.getDays()

static func axisNow() -> int:
	return RoutineScript.axis(GM.main.getTime())

static func clockNow() -> int:
	return OwnershipScript.clockOf(today(), axisNow())

static func feeling(observerID, targetID, axis:String) -> float:
	return rel().getFeeling(observerID, targetID, axis)

static func say(text:String, color:String = COLOR_INFO) -> void:
	if(GM.main != null && is_instance_valid(GM.main)):
		GM.main.addMessage("[color=" + color + "]" + text + "[/color]")

static func pawnOf(characterID):
	return GM.main.IS.getPawn(characterID) if (GM.main != null && GM.main.IS != null) else null

static func roomName(roomID:String) -> String:
	if(GM.world != null && is_instance_valid(GM.world)):
		var room = GM.world.getRoomByID(roomID)
		if(room != null):
			return str(room.roomName)
	return roomID

static func hasRoom(roomID:String) -> bool:
	return roomID != "" && GM.world != null && is_instance_valid(GM.world) && GM.world.hasRoomID(roomID)

# ---- Style ----
static func traitsOf(characterID) -> Dictionary:
	var entry:Dictionary = GangGameScript.traitEntry(characterID)
	return {"mean": float(entry["mean"]), "subby": float(entry["subby"]), "naive": float(entry["naive"]), "power": float(entry["power"])}

static func styleFor(characterID) -> String:
	return StyleScript.styleOf(traitsOf(characterID))

# ---- Keeping the module's record in step with BDCC's own ----
static func vanillaOwnerID() -> String:
	if(GM.main == null || GM.main.RS == null):
		return ""
	var ids:Array = GM.main.RS.getAllCharIDsWithSpecialRelationship("SoftSlavery")
	ids.sort()
	for id in ids:
		if(GM.main.getCharacter(id) != null):
			return str(id) # (a relationship whose character no longer exists is ignored)
	return ""

static func ownerCellRoom(ownerID) -> String:
	return module().homeRoomOf(ownerID)

# Reads BDCC's owner and slaves and brings the record up to date. Never ends or starts anything in BDCC: it only follows. A new owner or slave BDCC created is picked up with fresh schedules and
# no warnings; one BDCC ended is closed in the record; characters that no longer exist are dropped.
static func reconcile(fresh:Array = []) -> void:
	if(!isReady()):
		return
	var _repaired:bool = repairOwners()
	var s = svc()
	var day:int = today()
	var vid:String = vanillaOwnerID()
	if(vid != "" && !s.isOwner(vid)):
		if(s.hasOwner()):
			var _gone:Dictionary = s.end(day, "replaced")
		var _begun:bool = s.begin(vid, day, false, styleFor(vid), axisNow())
	elif(vid == "" && s.hasOwner()):
		var _ended:Dictionary = s.end(day, "ended")
	var pool:Array = GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Slaves)
	for id in pool:
		var theChar = GM.main.getCharacter(id)
		if(theChar != null && theChar.isSlaveToPlayer() && !s.hasSlave(id)):
			var _added:bool = s.addSlave(id, day)
			if(!fresh.has(id)):
				s.data()["slaves"][id]["setup"] = "set" # a slave from before this module (or an old save) just carries on: only somebody enslaved now waits for instructions
			module().getNpcJobs().removeCharacter(id) # a slave has no inmate job
	for id in s.slaveIDs():
		var slaveChar = GM.main.getCharacter(id)
		if(slaveChar == null):
			var _pruned:bool = s.removeSlave(id)
		elif(!slaveChar.isSlaveToPlayer()):
			onSlaveGone(id)

# A slave BDCC no longer lists (released by the player, sold, or freed by something else). Releasing them is kindness the character remembers.
static func onSlaveGone(characterID) -> void:
	var s = svc()
	var wasEscaping:bool = !s.slaveRecord(characterID).empty() && !s.slaveRecord(characterID).get("escape", {}).empty()
	var _removed:bool = s.removeSlave(characterID)
	if(wasEscaping):
		return
	var _t:float = rel().adjustFeeling(characterID, "pc", "trust", 15.0)
	var _a:float = rel().adjustFeeling(characterID, "pc", "affection", 8.0)
	var _r:float = rel().adjustFeeling(characterID, "pc", "respect", 4.0)
	var _f:float = rel().adjustFeeling(characterID, "pc", "fear", -20.0)

# ---- Who is where ----
# Whether the owner could be at their cell and deal with the player right now. {"ok", "why"}.
static func ownerAvailability(ownerID) -> Dictionary:
	if(ownerID == "" || GM.main == null):
		return {"ok": false, "why": "nobody"}
	var theChar = GM.main.getCharacter(ownerID)
	if(theChar == null):
		return {"ok": false, "why": "they are gone"}
	if(theChar.isStaff() || ownerCellRoom(ownerID) == ""):
		return {"ok": false, "why": "they have no cell of their own"}
	if(module().getGangs().isCaptive(ownerID) || module().getGangs().isDetained(ownerID)):
		return {"ok": false, "why": "they are being held"}
	var pawn = pawnOf(ownerID)
	if(pawn == null):
		return {"ok": false, "why": "they are not around"}
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.id != "AloneInteraction" && interaction.id != "InNpcOwnerEvent"):
		return {"ok": false, "why": "they are busy"} # (an owner event is the owner dealing with the player, so it does not count as busy)
	return {"ok": true, "why": ""}

# Why the owner cannot walk over to the player right now ("" when they can): not around, held, badly hurt, busy with something else (that includes being knocked out), or no way to the player.
static func ownerApproachBlock(ownerID) -> String:
	var pawn = pawnOf(ownerID)
	if(pawn == null):
		return "not around"
	if(module().getGangs().isCaptive(ownerID) || module().getGangs().isDetained(ownerID)):
		return "held"
	if(module().getInjuries().highestSeverity(ownerID) >= InjuriesScript.SEVERE):
		return "badly hurt"
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.id != "AloneInteraction" && interaction.id != "InNpcOwnerEvent"):
		return "busy"
	if(!routeExists(pawn.getLocation(), str(GM.pc.getLocation()))):
		return "no route"
	return ""

static func playerExcuse() -> String:
	return module().getBlockedReason()

# The player stands in the owner's cell and the owner is there and free.
static func playerInOwnerCell() -> bool:
	var s = svc()
	if(!s.hasOwner()):
		return false
	var cell:String = ownerCellRoom(s.ownerID())
	if(cell == "" || GM.pc.getLocation() != cell):
		return false
	var pawn = pawnOf(s.ownerID())
	return pawn != null && pawn.getLocation() == cell && bool(ownerAvailability(s.ownerID())["ok"])

# ---- The nightly check-in and the owner's daily affairs ----
static func cellLabelOf(characterID) -> String:
	var entry:Dictionary = module().getCells().getCell(characterID)
	if(entry.empty()):
		return ""
	return LayoutScript.label(entry["block"], entry["cell"])

static func blockNameOf(characterID) -> String:
	var entry:Dictionary = module().getCells().getCell(characterID)
	return LayoutScript.blockName(entry["block"]) + " cell block" if !entry.empty() else ""

# Runs the owner's side of things: the check-in (created, reminded, closed), demands (expired, issued), the owner losing interest, the owner's retaliation. Called every time the clock moves.
static func ownerTick(_force:bool = false) -> void:
	var s = svc()
	if(!s.hasOwner()):
		return
	var day:int = today()
	var axis:int = axisNow()
	var clock:int = clockNow()
	var ownerID:String = s.ownerID()
	var ownerName:String = nameOf(ownerID)
	var availability:Dictionary = ownerAvailability(ownerID)
	var excuse:String = playerExcuse()
	if(excuse == "" && s.isCheckinPending(day) && GM.world != null && is_instance_valid(GM.world) && ownerCellRoom(ownerID) != "" && GM.world.calculatePath(GM.pc.getLocation(), ownerCellRoom(ownerID)).empty()):
		excuse = "there is no way through to their cell"
	if(excuse != ""):
		s.noteBlock(day, excuse)
		s.noteDemandBlock(excuse)
	if(!bool(availability["ok"]) && axis >= OwnershipScript.REMINDER_AT - 1800):
		s.noteBlock(day, "your owner was not available (" + str(availability["why"]) + ")")
		s.noteDemandBlock("your owner was not available")
	# the owner may let go by themselves
	var why:String = s.ownerLosesInterest(day, feeling(ownerID, "pc", "fear"), feeling(ownerID, "pc", "trust"), feeling(ownerID, "pc", "affection"))
	if(why != ""):
		releasePlayer("afraid" if why == "afraid" else "fond", true)
		return
	# The check-in that is over is judged first, before tonight's record replaces it (sleeping through the night used to start the next one over the top of it, so a skipped night was never counted)
	var excusedBlock:String = str(s.checkin().get("block", "something kept you"))
	var closed:String = s.closeCheckin(day, axis, "")
	var skipped:Array = s.skippedNights(day) # nights the clock jumped over without any record: required, so missed
	var missedNights:int = (1 if closed == "missed" else 0) + skipped.size()
	if(missedNights > 0):
		var level:int = 1
		if(closed == "missed"):
			level = s.recordMiss(int(s.checkin().get("day", day)), "did not come to the check-in")
		for night in skipped:
			level = s.recordMiss(int(night), "did not come to the check-in")
		say("You failed to report to " + ownerName + (" last night" if missedNights == 1 else " on " + str(missedNights) + " nights") + ". They will deal with it when you next meet (" + TextScript.confrontLevelName(level) + ").", COLOR_BAD)
	elif(closed == "excused"):
		say("You were excused from the last check-in (" + excusedBlock + "). No warning, no penalty.", COLOR_INFO)
	# tonight's check-in
	if(s.startCheckin(day, axis)):
		var _learned:bool = module().learnCell(ownerID) # the obligation itself teaches the cell
	if(s.shouldRemind(day, axis)):
		s.markReminded()
		say(ownerName + " expects you at " + cellLabelOf(ownerID) + " tonight, between " + TextScript.windowText() + ".", COLOR_WARN)
	# demands
	var expired:String = s.expireDemand(clock, day, "")
	if(expired == "missed"):
		say("You did not do what " + ownerName + " asked in time. They will deal with it when you next meet.", COLOR_BAD)
	elif(expired == "excused"):
		say("What " + ownerName + " asked of you lapsed without blame.", COLOR_INFO)
	if(!s.hasDemand() && s.hasMeeting() && str(s.meeting()["purpose"]) == "demand"):
		var _lapsed:bool = s.finishMeeting() # the offer is gone, and so is the promise to tell it
	if(s.canIssueDemand(clock, day) && bool(availability["ok"]) && axis >= DEMAND_HOURS[0] && axis <= DEMAND_HOURS[1]):
		var made:Dictionary = s.makeDemand(clock, day, demandFacts())
		if(!made.empty()):
			say(ownerName + " has something they want you to do. They will find you, or you can talk to them to hear it.", COLOR_INFO)
			var _meeting:bool = s.startMeeting(day, "demand")
			var _told:bool = s.markMeetingTold() # (that is a promise to meet: it is a real pending meeting)
	pregnancyTick()
	meetingTick()
	rescueTick()

static func demandFacts() -> Dictionary:
	var s = svc()
	var targets:Array = []
	for id in module().getDirectedInmateIDs():
		if(id != s.ownerID() && !GangGameScript.isProtectedTarget(id) && !module().getGangs().isCaptive(id) && !module().isKeptElsewhere(id) && pawnOf(id) != null && !svc().hasSlave(id)):
			var theChar = GM.main.getCharacter(id)
			if(theChar != null && !theChar.isSlaveToPlayer()):
				targets.append(id)
	var employment = module().getEmployment()
	var canShift:bool = employment.isEmployed() && employment.hasOpenShift(today()) && !employment.isWindowClosed(employment.getJobID(), GM.main.getTime())
	return {"credits": GM.pc.getCredits(), "ordinaryItem": ordinaryItemID(), "contraband": GangGameScript.contrabandItemID(), "canShift": canShift, "targets": targets, "axisNow": axisNow()}

# A plain item the player carries that could be handed over without harm: not contraband, not important, not persistent, not a restraint. The cheapest one.
static func ordinaryItem():
	var best = null
	var bestPrice:int = 1000000
	for item in GM.pc.getInventory().getItems():
		if(item.hasTag(ItemTag.Illegal) || item.isImportant() || item.isPersistent() || item.isRestraint()):
			continue
		var price:int = int(item.getPrice()) if item.has_method("getPrice") else 1
		if(best == null || price < bestPrice):
			best = item
			bestPrice = price
	return best

static func ordinaryItemID() -> String:
	var item = ordinaryItem()
	return str(item.id) if item != null else ""

static func itemNameFor(itemID:String) -> String:
	for item in GM.pc.getInventory().getItems():
		if(str(item.id) == itemID):
			return str(item.getVisibleName()).to_lower()
	return "item"

static func demandContext() -> Dictionary:
	var s = svc()
	var d:Dictionary = s.demand()
	var ctx:Dictionary = {"owner": nameOf(s.ownerID()), "itemName": itemNameFor(str(d.get("item", ""))) if str(d.get("item", "")) != "" else "item"}
	if(str(d.get("target", "")) != ""):
		ctx["targetName"] = nameOf(str(d["target"]))
	if(str(d.get("type", "")) == "report"):
		var at:int = int(d.get("at", 0))
		ctx["timeText"] = "%02d:%02d" % [int(floor((at % 86400) / 3600.0)), int(floor((at % 3600) / 60.0))]
	return ctx

static func hoursLeft(deadline:int) -> int:
	return int(max(1, ceil(float(deadline - clockNow()) / 3600.0)))

# ---- Reporting in ----
# The player speaks to the owner in their cell. Returns {"ok", "text", "reason"}; the effects are applied here, once.
static func reportIn() -> Dictionary:
	var s = svc()
	if(!s.hasOwner()):
		return {"ok": false, "text": "", "reason": "none"}
	var day:int = today()
	var res:Dictionary = s.reportIn(day, axisNow(), playerInOwnerCell())
	var style:String = s.style()
	if(!res["ok"]):
		var reasons:Dictionary = {"none": "There is nothing to report tonight.", "not_there": "You need to be in their cell, and they need to be there.", "too_soon": TextScript.tooSoonNote(), "closed": "It is too late: the check-in has closed."}
		return {"ok": false, "text": str(reasons.get(res["reason"], "You cannot report in right now.")), "reason": res["reason"]}
	var fx:Dictionary = TextScript.checkinEffects(str(res["timing"]))
	var ownerID:String = s.ownerID()
	var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", float(fx["trust"]))
	var _r:float = rel().adjustFeeling(ownerID, "pc", "respect", float(fx["respect"]))
	var _d:float = module().getCombat().addRep("defiance", float(fx["defiance"]))
	var outcome:Dictionary = selectCheckinOutcome()
	return {"ok": true, "text": TextScript.say(ownerID, TextScript.checkinSpeech(style, str(res["timing"]))) + "\n\n" + TextScript.checkinNote(str(res["timing"])), "reason": "", "timing": res["timing"], "outcome": outcome["kind"], "intent": outcome["intent"], "note": outcome["note"]}

# ---- Confrontation ----
# Whether the owner should walk up to the player now: something is waiting (a warning, a demand to make), they can, nothing keeps them, and it is daytime (at night they are in their cell and the
# player comes to them).
static func ownerWantsToSeePlayer() -> bool:
	if(!isReady()):
		return false
	var s = svc()
	if(!s.hasOwner()):
		return false
	var axis:int = axisNow()
	if(s.meetingDue(today()) && axis >= DEMAND_HOURS[0] && axis <= 22 * 3600 && bool(ownerAvailability(s.ownerID())["ok"])):
		return true # a meeting they asked for: they come to the player
	if(axis < DEMAND_HOURS[0] || axis > DEMAND_HOURS[1]):
		return false
	var waiting:bool = !s.pendingConfront().empty() || (s.hasDemand() && s.demand()["state"] == "offered")
	if(!waiting || s.inGrace(today()) || !bool(ownerAvailability(s.ownerID())["ok"])):
		return false
	if(!s.pendingConfront().empty() && OwnershipScript.hesitates(feeling(s.ownerID(), "pc", "fear"), feeling(s.ownerID(), "pc", "trust"), true)):
		return false
	return true

static func forgiveness() -> float:
	var s = svc()
	var ownerID:String = s.ownerID()
	return s.openness(feeling(ownerID, "pc", "trust"), feeling(ownerID, "pc", "respect"), feeling(ownerID, "pc", "affection"), today())

static func compensationFor(styleName:String) -> int:
	return OwnershipScript.compensationFor(styleName)

# What each choice in a confrontation does (see Ownership.confrontEffect).
static func confrontEffect(choice:String, level:int, styleName:String, forgive:float, credits:int) -> Dictionary:
	return OwnershipScript.confrontEffect(choice, level, styleName, forgive, credits)

# Applies a confrontation choice (not fights, which are decided by the fight and applied through confrontFight). Returns the effect so the caller can show it and start a punishment if asked.
static func applyConfront(choice:String, level:int) -> Dictionary:
	var s = svc()
	var ownerID:String = s.ownerID()
	var effect:Dictionary = confrontEffect(choice, level, s.style(), forgiveness(), GM.pc.getCredits())
	if(effect["refused"]):
		return effect
	if(int(effect["credits"]) != 0):
		GM.pc.addCredits(int(effect["credits"]))
	var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", float(effect["trust"]))
	var _r:float = rel().adjustFeeling(ownerID, "pc", "respect", float(effect["respect"]))
	if(float(effect["defiance"]) != 0.0):
		var _d:float = module().getCombat().addRep("defiance", float(effect["defiance"]))
	if(effect["clear"]):
		s.clearConfront("Settled: " + str(effect["text"]), today())
	return effect

# The player backs down before the fight: the milder way out (Milestone 2's surrender), costing a payment and some standing.
static func confrontBackDown(level:int) -> Dictionary:
	var ownerID:String = svc().ownerID()
	var _c:Dictionary = module().runCombatOutcome(ownerID, "surrender")
	return applyConfront("backdown", level)

# The fight with the owner is over. Winning ends the consequence and makes the owner back off for two days; losing means the punishment. Either way the ownership itself is unchanged.
static func confrontFight(playerWon:bool) -> Dictionary:
	var s = svc()
	var ownerID:String = s.ownerID()
	var day:int = today()
	var _c:Dictionary = module().runCombatOutcome(ownerID, "win" if playerWon else "loss")
	if(playerWon):
		s.recordOwnerDefeat(day)
		var _f:float = rel().adjustFeeling(ownerID, "pc", "fear", 15.0)
		var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", -3.0)
		return {"won": true, "punish": false, "wins": s.distinctWins()}
	s.clearConfront("Punished after resisting.", day)
	var _t2:float = rel().adjustFeeling(ownerID, "pc", "trust", -2.0)
	return {"won": false, "punish": true, "wins": s.distinctWins()}

# ---- Demands in person ----
static func demandNegotiate() -> Dictionary:
	var s = svc()
	var res:Dictionary = s.negotiateDemand(forgiveness(), today())
	if(res.get("result", "") in ["eased", "extended", "replaced"]):
		var _r:float = rel().adjustFeeling(s.ownerID(), "pc", "respect", 1.0)
	return res

static func demandAccept() -> bool:
	return svc().acceptDemand()

static func demandRefuse() -> int:
	var s = svc()
	var ownerID:String = s.ownerID()
	var level:int = s.refuseDemand(today())
	var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", -2.0)
	var _d:float = module().getCombat().addRep("defiance", 2.0)
	return level

# Hands over what was asked (credits or the item), or reports a finished task. Returns {"ok", "text"} and rewards once.
static func demandHandOver() -> Dictionary:
	var s = svc()
	if(!s.hasDemand()):
		return {"ok": false, "text": "There is nothing to hand over."}
	var d:Dictionary = s.demand()
	var ownerID:String = s.ownerID()
	var type:String = str(d["type"])
	if(d["state"] == "offered"):
		return {"ok": false, "text": "You have not agreed to it yet."}
	match(type):
		"credits":
			if(GM.pc.getCredits() < int(d["amount"])):
				return {"ok": false, "text": "You do not have " + str(d["amount"]) + " credits."}
			GM.pc.addCredits(-int(d["amount"]))
		"item", "contraband":
			var found = null
			for item in GM.pc.getInventory().getItems():
				if(str(item.id) == str(d["item"]) && (type == "item" || item.hasTag(ItemTag.Illegal)) && !item.isImportant() && !item.isPersistent()):
					found = item
					break
			if(found == null):
				return {"ok": false, "text": "You are not carrying it."}
			var _removed = GM.pc.getInventory().removeItem(found)
		"shift", "defeat":
			if(d["state"] != "ready"):
				return {"ok": false, "text": "You have not done it yet."}
		"report":
			return {"ok": false, "text": "This is done by showing up in their cell at the time, and reporting in."}
	var reward:Dictionary = s.completeDemand(today())
	if(reward.empty()):
		return {"ok": false, "text": "There is nothing to hand over."}
	var _applied:Dictionary = applyDemandReward(ownerID, reward)
	# (a private favour for the owner changes nobody's public Combat Reputation or Defiance; that belongs to Milestone 9, with gossip)
	return {"ok": true, "text": TextScript.say(ownerID, TextScript.demandDoneSpeech(s.style(), type))}

# The reward for a finished demand, stored where every screen reads it (the owner's feelings towards the player: owner -> "pc"), applied once, and shown as one combined coloured message.
# Fear and Desire do not change for an ordinary task. Returns the changes actually applied (after clamping).
static func applyDemandReward(ownerID:String, reward:Dictionary) -> Dictionary:
	var changes:Dictionary = {}
	for axis in ["trust", "respect", "affection"]:
		var applied:float = rel().adjustFeeling(ownerID, "pc", axis, float(reward[axis]))
		if(applied != 0.0):
			changes[axis] = applied
	var line:String = AftermathScript.formatMessage(nameOf(ownerID), changes)
	if(line != "" && GM.main != null):
		GM.main.addMessage(line)
	return changes

# The check-in demand ("be at my cell at ...") is finished by reporting in during its window.
static func demandReportIn() -> bool:
	var s = svc()
	if(!s.hasDemand() || str(s.demand()["type"]) != "report" || s.demand()["state"] != "active"):
		return false
	var d:Dictionary = s.demand()
	var day:int = today()
	if(int(d["day"]) != day || !playerInOwnerCell()):
		return false
	var axis:int = axisNow()
	if(axis < int(d["at"]) - 900 || axis > int(d["at"]) + 5400):
		return false
	var reward:Dictionary = s.completeDemand(day)
	if(reward.empty()):
		return false
	var _applied:Dictionary = applyDemandReward(s.ownerID(), reward)
	return true

# Hooks the game calls when something relevant happens.
static func onShiftCompleted() -> void:
	if(!isReady()):
		return
	var s = svc()
	if(s.hasDemand() && str(s.demand()["type"]) == "shift" && s.demand()["state"] == "active"):
		var _ready:bool = s.markDemandReady()
		say("You finished your shift. Report back to " + nameOf(s.ownerID()) + " in person.", COLOR_GOOD)

# The player won a fight against someone (including an NPC giving up before it began). A beaten named target readies a "defeat" demand.
static func onPlayerWon(lostID, kind:String = "fight") -> void:
	if(!isReady()):
		return
	var s = svc()
	s.noteDefeat(lostID, today(), kind) # how they were beaten matters if the player then enslaves them
	if(s.hasDemand() && str(s.demand()["type"]) == "defeat" && s.demand()["state"] == "active" && str(s.demand()["target"]) == lostID):
		var _ready:bool = s.markDemandReady()
		say(nameOf(lostID) + " has been dealt with. Report back to " + nameOf(s.ownerID()) + " in person.", COLOR_GOOD)
	if(s.hasSlave(lostID) && !s.slaveRecord(lostID).get("escape", {}).empty()):
		stopEscapeByForce(lostID)

# ---- Protection ----
static func protectionFacts(attackerID) -> Dictionary:
	var s = svc()
	var ownerID:String = s.ownerID()
	var gid:String = module().getGangs().gangOf(ownerID)
	var gangStrength:float = GangGameScript.gangStrength(gid) if gid != "" && module().getGangs().hasGang(gid) else 0.0
	var attackerPower:float = GangGameScript.power(attackerID) if attackerID != "" else 0.9
	var fear:float = feeling(attackerID, ownerID, "fear") if attackerID != "" else 0.0
	var attackerGid:String = module().getGangs().gangOf(attackerID) if attackerID != "" else ""
	var hostile:bool = attackerID != "" && (feeling(attackerID, ownerID, "affection") <= -30.0 || feeling(attackerID, ownerID, "respect") <= -30.0 || (attackerGid != "" && gid != "" && attackerGid != gid && module().getGangs().areEnemies(attackerGid, gid)))
	return {"hasOwner": s.hasOwner(), "style": s.style(), "ownerPower": GangGameScript.power(ownerID), "attackerPower": attackerPower, "attackerFear": fear, "gangStrength": gangStrength,
		"attackerGang": GangGameScript.gangStrength(attackerGid) if attackerGid != "" else 0.0, "attackerHostile": hostile,
		"retaliated": s.hasRetaliatedAgainst(attackerID), "available": bool(ownerAvailability(ownerID)["ok"]), "recentLosses": s.recentOwnerLosses(today())}

static func protectionFor(attackerID) -> Dictionary:
	if(!isReady() || !svc().hasOwner()):
		return {"multiplier": 1.0, "band": "None", "credibility": 0.0, "reasons": ["Nobody owns you."]}
	return OwnershipScript.protection(protectionFacts(attackerID))

# What the Ownership screen shows: the protection against a typical inmate.
static func protectionSummary() -> Dictionary:
	return protectionFor("")

# Multiplier on how interested an attacker is in the player (used by Module.getAttackMultiplier).
static func protectionMultiplier(attackerID) -> float:
	if(!isReady() || !svc().hasOwner()):
		return 1.0
	return float(protectionFor(attackerID)["multiplier"])

# Someone attacked the player. The owner remembers; if the owner is standing right there, willing and not outmatched, they step in. Returns the character that stepped in, or "".
static func onPlayerAttacked(fight, attackerID:String) -> String:
	if(!isReady() || attackerID == "" || attackerID == "pc"):
		return ""
	var s = svc()
	var day:int = today()
	if(s.hasOwner() && attackerID != s.ownerID()):
		s.noteAggressor(attackerID, day)
	var helpers:Array = []
	for id in s.slaveIDs():
		if(id != attackerID && (s.slaveRecord(id)["role"] == "attendant" || slaveDisposition(id) == "loyal")): # attendants, and loyal slaves who happen to be right there
			helpers.append(id)
	var owned:String = tryRemoteIntervention(fight, attackerID) # the owner first: ready protection, from anywhere
	if(owned != ""):
		return owned
	for helperID in helpers:
		if(willIntervene(helperID, attackerID)):
			return intervene(fight, helperID, attackerID)
	return ""

# ---- The owner protects the player, from anywhere ----
# A deliberate abstraction that makes ownership worth having: when the player is attacked and the owner's protection is ready, the owner arrives from wherever they are in the prison. Only hard blockers stop it
# (below); distance, their routine, sleeping, working, walking or an ordinary conversation never do. It is available once per in-game day. The owner may still lose the fight: how strong their protection is
# decides how likely they win and how many attackers think twice, not whether they come.
const INCOMPATIBLE = ["GenericAttack", "InSex", "InScene", "PunishInteraction", "NemesisAmbush", "CaughtOffLimits", "InStocks", "InSlutwall", "HelpLayEggs", "NurseSave"] # a fight or a scene of their own

# Why the owner's protection cannot be used right now ("" when it can): "used today", or a hard blocker: not around, held, unconscious, badly hurt, in a fight or scene of their own.
static func protectionBlock() -> String:
	var s = svc()
	if(!isReady() || !s.hasOwner()):
		return "no owner"
	if(today() < s.interventionReadyOn()):
		return "used today"
	return hardBlock()

# The hard blockers on their own (no cooldown): the owner cannot act at all right now.
static func hardBlock() -> String:
	var s = svc()
	if(!isReady() || !s.hasOwner()):
		return "no owner"
	var ownerID:String = s.ownerID()
	var pawn = pawnOf(ownerID)
	if(pawn == null || GM.main.getCharacter(ownerID) == null):
		return "not around"
	if(module().getGangs().isCaptive(ownerID) || module().getGangs().isDetained(ownerID)):
		return "held"
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.id == "Unconscious"):
		return "unconscious"
	if(module().getInjuries().highestSeverity(ownerID) >= InjuriesScript.SEVERE):
		return "badly hurt"
	if(interaction != null && INCOMPATIBLE.has(interaction.id)):
		return "busy"
	return ""

# Brings the owner to the player's room for an incident: their own interactions end, they are put in the room once (never duplicated), and their routine walks them back afterwards. Returns whether they are there.
static func ownerArrives(announce:bool = true) -> bool:
	var s = svc()
	var ownerID:String = s.ownerID()
	var pawn = pawnOf(ownerID)
	if(pawn == null):
		return false
	if(pawn.getLocation() != GM.pc.getLocation()):
		GM.main.IS.stopInteractionsForPawnID(ownerID)
		pawn.setLocation(GM.pc.getLocation())
		if(announce):
			GM.main.addMessage(nameOf(ownerID) + " hears you are in trouble and comes straight to you.")
	return true

# The player is attacked: the owner remembers the attacker, and arrives to fight them if their protection is ready. Returns the owner's id when they stepped in, otherwise "".
static func tryRemoteIntervention(fight, attackerID:String) -> String:
	var s = svc()
	if(!s.hasOwner() || attackerID == s.ownerID() || attackerID == ""):
		return ""
	var attackerPawn = pawnOf(attackerID)
	if(attackerPawn == null || attackerPawn.getLocation() != GM.pc.getLocation()):
		return ""
	var block:String = protectionBlock()
	if(block != ""):
		var words:Dictionary = {"used today": "Your owner has already stepped in for you today.", "held": "Your owner cannot come to your aid: they are being held.", "unconscious": "Your owner cannot come to your aid: they are unconscious.", "badly hurt": "Your owner cannot come to your aid: they are too badly hurt."}
		if(words.has(block)):
			GM.main.addMessage(str(words[block]))
		return "" # (nothing is used up: the owner remembers the attacker and may go after them later)
	var ownerID:String = s.ownerID()
	s.noteIntervention(today())
	var _here:bool = ownerArrives()
	return intervene(fight, ownerID, attackerID)

# What the Ownership screen says about it: {"state": "ready" | "used" | "unavailable", "text"}.
static func interventionStatus() -> Dictionary:
	var block:String = protectionBlock()
	if(block == "no owner"):
		return {"state": "unavailable", "text": "Protection unavailable: you have no owner."}
	if(block == "used today"):
		return {"state": "used", "text": "Protection used today. It is ready again tomorrow."}
	if(block != ""):
		var words:Dictionary = {"not around": "they are not around", "held": "they are being held", "unconscious": "they are unconscious", "badly hurt": "they are too badly hurt", "busy": "they are in a fight or scene of their own"}
		return {"state": "unavailable", "text": "Protection unavailable: " + str(words.get(block, block)) + "."}
	return {"state": "ready", "text": "Protection ready: if you are attacked, your owner comes, from anywhere in the prison."}

# ---- Pregnancy: the owner's reaction, and help giving birth (BDCC's own pregnancy and nursery systems; nothing here is a second pregnancy system) ----
# {"pregnant", "visible", "ready", "parentage": "owner" | "other" | "unknown"} read from the player's menstrual cycle: isPregnant, isVisiblyPregnant, isReadyToGiveBirth and the eggs' father IDs.
static func pregnancyFacts() -> Dictionary:
	var result:Dictionary = {"pregnant": false, "visible": false, "ready": false, "parentage": "unknown"}
	if(GM.pc == null || GM.pc.getMenstrualCycle() == null || !GM.pc.isPregnant(true, false)):
		return result
	result["pregnant"] = true
	result["visible"] = GM.pc.isVisiblyPregnant()
	result["ready"] = GM.pc.isReadyToGiveBirth()
	var ownerID:String = svc().ownerID()
	var known:Array = []
	for egg in GM.pc.getMenstrualCycle().impregnatedEggCells:
		var fatherID:String = str(egg.getFatherID())
		if(fatherID != "" && fatherID != "pc" && GM.main.getCharacter(fatherID) != null):
			known.append(fatherID)
	if(known.has(ownerID)):
		result["parentage"] = "owner"
	elif(!known.empty()):
		result["parentage"] = "other"
	return result

static func birthImminent() -> bool:
	return isReady() && svc().hasOwner() && bool(pregnancyFacts()["ready"])

# What the owner has yet to say about the pregnancy: "" (nothing), "notice" (they have just seen it) or "birth" (it is time and they have not been told).
static func pregnancyPending() -> String:
	var s = svc()
	if(!isReady() || !s.hasOwner()):
		return ""
	var facts:Dictionary = pregnancyFacts()
	if(!bool(facts["pregnant"])):
		return ""
	if(bool(facts["ready"]) && s.pregnancyStage() != "birth"):
		return "birth"
	if(bool(facts["visible"]) && s.pregnancyStage() == ""):
		return "notice"
	return ""

# The owner's reaction to a pregnancy they have just noticed, once (the stage is recorded for this pregnancy).
static func pregnancyNoticeText() -> String:
	var s = svc()
	var ownerID:String = s.ownerID()
	s.setPregnancyStage("noticed")
	var parentage:String = str(pregnancyFacts()["parentage"])
	return TextScript.say(ownerID, TextScript.pregnancyNotice(s.style(), parentage, feeling(ownerID, "pc", "affection"), feeling(ownerID, "pc", "desire")))

# The owner takes the player to the nursery and stays with them: both are put there once, a little time passes, and the game's own nursery conversation takes over (where giving birth is the nurse's and the pregnancy system's business).
static func takeToNursery() -> void:
	var s = svc()
	s.setPregnancyStage("birth")
	var room:String = "medical_nursery"
	var pawn = pawnOf(s.ownerID())
	GM.main.IS.stopInteractionsForPawnID(s.ownerID())
	if(pawn != null):
		pawn.setLocation(room)
	GM.pc.setLocation(room)
	var playerPawn = pawnOf("pc")
	if(playerPawn != null):
		playerPawn.setLocation(room)
	GM.main.processTime(15 * 60)
	GM.main.runScene("NurseryTalkScene")

# Called every few minutes: when the pregnancy is over, what the owner knew about it is forgotten.
static func pregnancyTick() -> void:
	var s = svc()
	if(s.hasOwner() && s.pregnancyStage() != "" && !bool(pregnancyFacts()["pregnant"])):
		s.setPregnancyStage("")

# ---- The one ownership action in the owner's talk menu ----
# Several obligations can exist at once, but the talk menu shows one, by priority: 1. a finished demand (or something to hand over), 2. a meeting the owner asked for, 3. tonight's check-in (or the report their task asked for), 4. the ordinary options.
# Returns {"id": "sbxHandover" | "sbxMeeting" | "sbxCheckin" | "sbxReportDemand" | "", "label", "tooltip", "mark", "ok", "reason"}; the next one appears once this one is done.
static func ownerAction() -> Dictionary:
	var s = svc()
	var none:Dictionary = {"id": "", "label": "", "tooltip": "", "mark": "", "ok": true, "reason": ""}
	if(!isReady() || !s.hasOwner()):
		return none
	var day:int = today()
	var d:Dictionary = s.demand()
	if(!d.empty() && d["state"] == "ready"):
		return {"id": "sbxHandover", "label": "Report completed demand", "tooltip": "Tell your owner it is done. This works at any time of day: it is not the nightly check-in.", "mark": "Report to {owner}", "ok": true, "reason": ""}
	if(!d.empty() && d["state"] == "active" && str(d["type"]) in ["credits", "item", "contraband"]):
		return {"id": "sbxHandover", "label": "Hand it over", "tooltip": "Give them what they asked for.", "mark": "Hand it over to {owner}", "ok": true, "reason": ""}
	if(s.meetingDue(day) && str(s.meeting()["purpose"]) in OwnershipScript.OWED_PURPOSES):
		return {"id": "sbxMeeting", "label": "Meet with owner", "tooltip": "They asked to see you today.", "mark": "Meet {owner} (" + TextScript.meetingShort(str(s.meeting()["purpose"])) + ")", "ok": true, "reason": ""}
	var pending:String = pregnancyPending()
	if(pending != ""):
		return {"id": "sbxPregnancy", "label": "Talk about the pregnancy" if pending == "notice" else "Tell them it is time", "tooltip": "Your owner has noticed.", "mark": "Talk to {owner} about the pregnancy" if pending == "notice" else "Tell {owner} it is time", "ok": true, "reason": ""}
	if(!d.empty() && d["state"] == "offered"):
		return {"id": "sbxDemand", "label": "Hear about the job", "tooltip": "They have a task for you. They explain what they want, what you get and what happens if you do not.", "mark": "Hear about the job from {owner}", "ok": true, "reason": ""}
	if(s.meetingDue(day)):
		return {"id": "sbxMeeting", "label": "Meet with owner", "tooltip": "They asked to see you today.", "mark": "Meet {owner} (" + TextScript.meetingShort(str(s.meeting()["purpose"])) + ")", "ok": true, "reason": ""}
	var reportDemand:bool = !d.empty() && d["state"] == "active" && str(d["type"]) == "report"
	if(s.isCheckinPending(day)):
		if(playerInOwnerCell()):
			return {"id": "sbxCheckin", "label": "Report in for the night", "tooltip": "Tell your owner you are here, as they expect tonight.", "mark": "Check in with {owner}", "ok": true, "reason": ""}
		return {"id": "sbxCheckin", "label": "Report in for the night", "tooltip": "Your check-in is done in their own cell: go into " + cellLabelOf(s.ownerID()) + " and speak to them there.", "mark": "Check in with {owner}", "ok": false, "reason": "not in their cell"}
	if(reportDemand):
		return {"id": "sbxReportDemand", "label": "Report as ordered", "tooltip": "Tell them you are here, as they asked.", "mark": "Report in to {owner}", "ok": true, "reason": ""}
	return none

# ---- The owner asks to meet ----
static func meetingFacts() -> Dictionary:
	var s = svc()
	var day:int = today()
	var ownerID:String = s.ownerID()
	var pending:Dictionary = s.pendingConfront()
	var d:Dictionary = s.demand()
	var lust:float = clamp(GM.main.RS.getLust(ownerID, "pc"), -1.0, 1.0)
	var birth:bool = bool(pregnancyFacts()["ready"])
	return {"confront": int(pending.get("level", 1)) if !pending.empty() else 0, "demand": str(d.get("state", "")) if !d.empty() else "", "demandDue": false, "notable": s.notableCompliance(day), "intimacyOk": s.canHaveIntimacy(day) && !birth, "birth": birth,
		"intimacyChance": OwnershipScript.intimacyChance(s.style(), lust, feeling(ownerID, "pc", "affection"), feeling(ownerID, "pc", "trust"))}

# Why the owner asks to meet: chosen once when the meeting is made (see Ownership.choosePurpose) and saved with it.
static func chooseMeetingPurpose() -> String:
	return OwnershipScript.choosePurpose(meetingFacts(), nightSeed())

static func meetingPurposeText(purpose:String) -> String:
	return TextScript.meetingHint(purpose)

# The game's own notice that the owner will approach today (NpcOwnerBase.onNewDay) is now always a real pending meeting. Said once.
static func onOwnerMeetingDay(characterID) -> void:
	if(!isReady()):
		return
	reconcile()
	var s = svc()
	if(!s.isOwner(characterID)):
		return
	var _made:bool = s.startMeeting(today(), chooseMeetingPurpose())
	if(s.markMeetingTold()):
		GM.main.addMessage(nameOf(characterID) + ", your owner, " + meetingPurposeText(str(s.meeting()["purpose"])) + " today. They will come to you.")

# Called every few minutes. A pending meeting is kept: a hard blocker postpones it (once told, to the next day), the owner reaches the player on their own during the day, and by evening they find the player directly.
static func meetingTick() -> void:
	var s = svc()
	if(!s.hasOwner()):
		return
	var day:int = today()
	var ownerID:String = s.ownerID()
	var ownerName:String = nameOf(ownerID)
	if(!s.hasMeeting() && (ownerWantsToSeePlayer() || (s.hasDemand() && s.demand()["state"] == "offered"))):
		var _made:bool = s.startMeeting(day, chooseMeetingPurpose())
		if(s.markMeetingTold()):
			say(ownerName + " " + meetingPurposeText(str(s.meeting()["purpose"])) + " today. They will come to you.", COLOR_INFO)
	if(s.hasMeeting() && !s.pendingConfront().empty()):
		var _up:bool = s.upgradePurpose(chooseMeetingPurpose()) # a warning, compensation or punishment that is owed outranks a lighter meeting (still one meeting, told once)
	if(!s.hasMeeting() || int(s.meeting()["day"]) > day):
		return
	if(GM.main.getCharacter(ownerID) == null):
		var _gone:bool = s.finishMeeting()
		say("The meeting with your owner is off: they are not here any more.", COLOR_WARN)
		return
	var block:String = hardBlock()
	if(block != ""):
		if(s.postponeMeeting(day + 1)):
			var words:Dictionary = {"not around": "they are not around", "held": "they are being held", "unconscious": "they are unconscious", "badly hurt": "they are too badly hurt", "busy": "they are in a fight or scene of their own"}
			say(ownerName + " cannot meet you today (" + str(words.get(block, block)) + "). They will try again tomorrow.", COLOR_WARN)
		var slavery = GM.main.RS.getSpecialRelationship(ownerID)
		if(slavery != null && slavery.get("npcOwner") != null):
			slavery.npcOwner.nextApproachDay = int(max(int(slavery.npcOwner.nextApproachDay), day + 1))
		return
	var pawn = pawnOf(ownerID)
	var axis:int = axisNow()
	if(pawn != null && pawn.getLocation() == GM.pc.getLocation() && axis >= DEMAND_HOURS[0] && axis <= 22 * 3600 && playerFreeForEvent()):
		startOwnerEvent() # already here: they begin the conversation themselves, shortly
		return
	if(axis >= OwnershipScript.MEETING_LATE_AXIS && pawn != null && pawn.getLocation() != GM.pc.getLocation() && playerFreeForEvent()):
		var _there:bool = ownerArrives(false)
		say(ownerName + " has been looking for you all day, and finds you.", COLOR_INFO)
		startOwnerEvent()

# The owner's own punishment keeps the player somewhere for the night: it covers that night's check-in.
static func punishmentCoversNight() -> void:
	if(!isReady() || !svc().hasOwner()):
		return
	svc().coverNight(today())
	if(GM.main != null):
		GM.main.addMessage(TextScript.punishReplaces(svc().style()))

# The player can be taken into an owner event right now: no scene, not in an interaction of their own.
static func playerFreeForEvent() -> bool:
	if(GM.main == null || GM.pc == null || !GM.main.playerCanBeInterrupted()):
		return false
	var pawn = GM.main.IS.getPawn("pc")
	return pawn != null && pawn.canBeInterrupted() && (pawn.currentInteraction == null || pawn.currentInteraction.id == "AloneInteraction")

# Starts the owner's next event with the player (the module's own, or BDCC's approach event), as the approach goal does.
static func startOwnerEvent() -> void:
	var s = svc()
	var slavery = GM.main.RS.getSpecialRelationship(s.ownerID())
	if(slavery == null || slavery.get("npcOwner") == null):
		return
	var info:Array = slavery.npcOwner.getApproachEvent()
	if(!info.empty()):
		GM.main.runScene("NpcOwnerEventRunnerScene", [s.ownerID(), info[0], info[1]])

# The meeting is held (and finished) by the owner event itself, when it opens (OwnerOpsEvent.openMeeting): a different owner event never counts as the meeting.
static func meetingGiveDemand() -> bool:
	var s = svc()
	if(s.hasDemand()):
		return s.demand()["state"] == "offered"
	return !s.makeDemand(clockNow(), today(), demandFacts()).empty()

# The small reward promised for good behaviour: a few credits by style and a little trust and affection. Counts as the thanks for the stretch of compliance (no second one at night).
static func meetingReward() -> Dictionary:
	var s = svc()
	var ownerID:String = s.ownerID()
	var credits:int = 3 if s.style() == StyleScript.HARSH else (4 if s.style() == StyleScript.CONTROLLING else 6)
	GM.pc.addCredits(credits)
	var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", 1.0)
	var _a:float = rel().adjustFeeling(ownerID, "pc", "affection", 1.0)
	s.notePraise(today())
	return {"credits": credits}

# Ordinary possessive attention: dialogue and one small, style-shaped change.
static func meetingAttention() -> void:
	var s = svc()
	var ownerID:String = s.ownerID()
	var axis:String = "affection" if s.style() == StyleScript.LENIENT else ("trust" if s.style() == StyleScript.CONTROLLING else "respect")
	var _r:float = rel().adjustFeeling(ownerID, "pc", axis, 1.0)

# ---- What tonight's check-in turns into (stored, never rerolled) ----
static func selectCheckinOutcome() -> Dictionary:
	var s = svc()
	var existing:String = s.checkinOutcome()
	if(existing != ""):
		return {"kind": existing, "intent": s.checkinIntent(), "note": ""}
	var facts:Dictionary = meetingFacts()
	var roll:float = module().nextRoll() if bool(facts["intimacyOk"]) else 1.0
	var kind:String = OwnershipScript.checkinOutcomeKind(facts, roll)
	var ownerID:String = s.ownerID()
	var intent:String = ""
	if(kind == "intimacy"):
		intent = OwnershipScript.intimacyIntent(s.style(), feeling(ownerID, "pc", "affection"), feeling(ownerID, "pc", "trust"))
	s.setCheckinOutcome(kind, intent)
	var note:String = ""
	if(kind == "praise"):
		# General acknowledgement only: the task's own reward was given when it was reported
		var _r:float = rel().adjustFeeling(ownerID, "pc", "respect", 1.0)
		var _a:float = rel().adjustFeeling(ownerID, "pc", "affection", 1.0)
		s.notePraise(today())
		note = TextScript.praiseNote(s.showGratitude(clockNow(), today()))
	return {"kind": kind, "intent": intent, "note": note}

# What the Ownership page and Side Tasks say about the meeting.
static func meetingText() -> String:
	var s = svc()
	var m:Dictionary = s.meeting()
	if(m.empty()):
		return ""
	var ownerName:String = nameOf(s.ownerID())
	if(int(m["day"]) > today()):
		return ownerName + " could not meet you earlier. They will try again on day " + str(m["day"]) + ": they " + meetingPurposeText(str(m["purpose"])).replace("wants", "want").replace("expects", "expect").replace("has ", "have ") + "."
	var pawn = pawnOf(s.ownerID())
	var status:String = "They are on their way to you."
	if(pawn != null && pawn.getLocation() == GM.pc.getLocation()):
		status = "They are right here."
	elif(hardBlock() != ""):
		status = "They are held up (" + hardBlock() + ")."
	return ownerName + " " + meetingPurposeText(str(m["purpose"])) + " today. " + status

# ---- The evening at the owner's ----
# The player stays the night at the owner's: the game's own sleeping (as in the player's cell), once.
# The real vanilla scene follows (NpcOwnerSleepTogetherScene: the Sleeping animation with the owner, as BDCC shows it when an owner makes the player sleep beside them).
static func sleepAtOwners() -> void:
	var ownerID:String = svc().ownerID()
	GM.main.startNewDay()
	GM.pc.afterSleepingInBed()
	GM.main.runScene("NpcOwnerSleepTogetherScene", [ownerID])

static func nightSeed() -> String:
	return str(today()) + str(svc().ownerID())

# Whether the stay turns intimate tonight, and how the owner goes about it: "" (it does not), "ask", "demand" or "force". At most once in two nights.
static func decideIntimacy() -> String:
	var s = svc()
	var day:int = today()
	if(!s.canHaveIntimacy(day)):
		return ""
	var ownerID:String = s.ownerID()
	var lust:float = clamp(GM.main.RS.getLust(ownerID, "pc"), -1.0, 1.0)
	var chance:float = OwnershipScript.intimacyChance(s.style(), lust, feeling(ownerID, "pc", "affection"), feeling(ownerID, "pc", "trust"))
	if(module().nextRoll() >= chance):
		return ""
	return OwnershipScript.intimacyIntent(s.style(), feeling(ownerID, "pc", "affection"), feeling(ownerID, "pc", "trust"))

# Whether the owner's talking-round works on "not tonight": their openness to the player (trust, respect, affection, how the player has behaved).
static func intimacyNegotiationWorks() -> bool:
	var s = svc()
	var ownerID:String = s.ownerID()
	return s.openness(feeling(ownerID, "pc", "trust"), feeling(ownerID, "pc", "respect"), feeling(ownerID, "pc", "affection"), today()) >= OwnershipScript.OPEN_ENOUGH

# ---- The owner rescues the restrained player ----
static func playerIsRestrained() -> bool:
	if(GM.pc == null):
		return false
	for item in GM.pc.getInventory().getEquppedRestraints():
		if(!item.isImportant()):
			return true # something that can come off
	return false

# Takes the player's restraints off with the game's own inventory calls (what cannot be removed, such as important items, stays). Returns how many came off.
static func removePlayerRestraints() -> int:
	var removed:int = 0
	for item in GM.pc.getInventory().getEquppedRestraints():
		if(item.isImportant()):
			continue
		if(GM.pc.getInventory().unequipItem(item)):
			removed += 1
	return removed

# The player lost a fight to somebody who is not staff: if they are left restrained, the owner may come for them (see rescueTick).
static func onPlayerLost(winnerID) -> void:
	if(!isReady() || !svc().hasOwner() || !(winnerID is String) || winnerID == "" || winnerID == "pc"):
		return
	var theChar = GM.main.getCharacter(winnerID)
	if(theChar == null || theChar.isStaff() || winnerID == svc().ownerID()):
		return # a guard's restraints are the prison's business, and the owner's own are their own
	svc().notePlayerDefeat(clockNow(), winnerID)

static func rescueTick() -> void:
	var s = svc()
	if(!s.hasOwner()):
		return
	var clock:int = clockNow()
	var d:Dictionary = s.playerDefeat()
	if(!d.empty() && int(d["started"]) >= 0 && clock - int(d["started"]) > 600):
		# the rescue was started and never finished (the scene was left): the owner finishes what they promised
		if(playerIsRestrained()):
			var count:int = removePlayerRestraints()
			if(count > 0):
				say(nameOf(s.ownerID()) + " gets the rest of your restraints off.", COLOR_INFO)
		s.markRescueDone()
		return
	if(!s.rescueDue(clock) || !playerIsRestrained() || protectionBlock() != "" || !playerFreeForEvent()):
		return
	s.noteIntervention(today())
	s.markRescueStarted(clock)
	var _there:bool = ownerArrives(true)
	GM.main.runScene("NpcOwnerEventRunnerScene", [s.ownerID(), "SandboxOwnerOps", ["rescue"]])

# ---- Only one owner ----
static func ownerIDs() -> Array:
	var ids:Array = GM.main.RS.getAllCharIDsWithSpecialRelationship("SoftSlavery")
	ids.sort()
	return ids

# More than one character is the player's owner (an old save, or some route that did not check): the recorded owner stays if there is a valid one, otherwise the lowest character id; the others lose the status
# and nothing else (no character or other relationship data is touched). Told to the player once.
static func repairOwners() -> bool:
	if(!isReady()):
		return false
	var ids:Array = ownerIDs()
	if(ids.size() <= 1):
		return false
	var keep:String = str(ids[0])
	var s = svc()
	if(s.hasOwner() && ids.has(s.ownerID())):
		keep = s.ownerID()
	var removed:Array = []
	for id in ids:
		if(id != keep):
			GM.main.RS.stopSpecialRelationship(id, false, false)
			removed.append(nameOf(id))
	say("Conflicting ownership records were repaired: " + nameOf(keep) + " is your owner; " + PoolStringArray(removed).join(", ") + " no longer " + ("is" if removed.size() == 1 else "are") + ".", COLOR_WARN)
	return true

static func hasOtherOwner(claimantID) -> bool:
	if(!isReady()):
		return false
	for id in ownerIDs():
		if(id != claimantID):
			return true
	return false

# ---- A rival claims the player ----
static func claimFacts(ownerID, claimantID, support:String) -> Dictionary:
	var gangs = module().getGangs()
	var ownerPawn = pawnOf(ownerID)
	var claimantPawn = pawnOf(claimantID)
	var ownerGang:String = gangs.gangOf(ownerID)
	var claimantGang:String = gangs.gangOf(claimantID)
	return {
		"ownerAble": ownerApproachBlock(ownerID) == "",
		"claimantAble": claimantPawn != null && !gangs.isCaptive(claimantID) && module().getInjuries().highestSeverity(claimantID) < InjuriesScript.SEVERE,
		"ownerPower": ownerPawn.calculatePowerScore() if ownerPawn != null else GangGameScript.power(ownerID),
		"claimantPower": claimantPawn.calculatePowerScore() if claimantPawn != null else GangGameScript.power(claimantID),
		"ownerGang": clamp(GangGameScript.gangStrength(ownerGang) / 6.0, 0.0, 1.0) if ownerGang != "" else 0.0,
		"claimantGang": clamp(GangGameScript.gangStrength(claimantGang) / 6.0, 0.0, 1.0) if claimantGang != "" else 0.0,
		"ownerInjury": module().getInjuries().highestSeverity(ownerID),
		"claimantInjury": module().getInjuries().highestSeverity(claimantID),
		"style": svc().style(),
		"claimantCoward": float(GangGameScript.traitEntry(claimantID)["coward"]),
		"support": support,
	}

# Settles a claim on the player once: exactly one owner afterwards. Returns {"result", "text", "claimantOwns"}. When the claimant wins (or the owner gives way) the old owner has already lost the status and the caller
# starts the new relationship; in every other case nothing about the owner changes. A dispute never repeats daily: one every two days, the same claimant not again for three.
static func resolveClaim(claimantID, support:String = "none") -> Dictionary:
	var s = svc()
	if(!isReady() || !s.hasOwner() || s.ownerID() == claimantID):
		return {"result": "none", "text": "", "claimantOwns": true}
	var day:int = today()
	var ownerID:String = s.ownerID()
	var ownerName:String = nameOf(ownerID)
	var claimantName:String = nameOf(claimantID)
	if(!s.disputeAllowed(claimantID, day)):
		return {"result": "cooldown", "text": claimantName + " tries to claim you, but " + ownerName + " has seen off a challenge very recently and nobody wants another fight so soon. You are still " + ownerName + "'s.", "claimantOwns": false}
	var facts:Dictionary = claimFacts(ownerID, claimantID, support)
	var outcome:Dictionary = OwnershipScript.contestOutcome(facts, module().nextRoll())
	var result:String = str(outcome["result"])
	var text:String = ""
	var claimantOwns:bool = false
	match(result):
		"postponed":
			text = claimantName + " wants to claim you, but " + ownerName + " cannot answer a challenge right now (" + str(ownerApproachBlock(ownerID)) + "). " + claimantName + " will have to try again some other time. You are still " + ownerName + "'s."
		"claimant_unable":
			text = claimantName + " tries to claim you, but is in no state to back it up. " + ownerName + " is still your owner."
		"backs_down":
			text = claimantName + " tries to claim you, takes one look at " + ownerName + " and backs down. " + ownerName + " is still your owner."
			var _fear:float = rel().adjustFeeling(claimantID, ownerID, "fear", 10.0)
		"owner_yields":
			text = ownerName + " would not fight " + claimantName + " over you and lets " + claimantName + " have you."
			claimantOwns = true
		"owner_wins":
			text = ownerName + " answers the claim and beats " + claimantName + ". " + ownerName + " is still your owner."
			module().getInjuries().applyInjury(claimantID, "trauma", 1)
			onNpcFightResult(ownerID, claimantID)
		"claimant_wins":
			text = claimantName + " challenges " + ownerName + " for you and wins. " + claimantName + " is your owner now."
			module().getInjuries().applyInjury(ownerID, "trauma", 1)
			onNpcFightResult(claimantID, ownerID)
			claimantOwns = true
	if(support == "claimant" && !claimantOwns && result != "postponed"):
		var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", -10.0)
		var _r:float = rel().adjustFeeling(ownerID, "pc", "respect", -5.0)
		text += " " + ownerName + " remembers whose side you took."
	elif(support == "owner" && !claimantOwns && result != "postponed"):
		var _t2:float = rel().adjustFeeling(ownerID, "pc", "trust", 5.0)
	if(result != "postponed"):
		s.noteDispute(claimantID, day, result)
	if(claimantOwns):
		GM.main.RS.stopSpecialRelationship(ownerID) # the old owner loses the status, with the game's own message
		var _gone:Dictionary = s.end(day, "lost_to_claimant")
	return {"result": result, "text": text, "claimantOwns": claimantOwns}

# The one gate every way of becoming the player's owner passes through (see RelationshipSystem.startSpecialRelantionship): true when the new owner may be recorded.
static func mayStartOwner(claimantID) -> bool:
	if(!isReady()):
		return true
	var _repaired:bool = repairOwners()
	if(!hasOtherOwner(claimantID)):
		return true
	var resolved:Dictionary = resolveClaim(claimantID, "none")
	if(str(resolved["text"]) != ""):
		say(str(resolved["text"]), COLOR_INFO if bool(resolved["claimantOwns"]) else COLOR_WARN)
	return bool(resolved["claimantOwns"])

# What the player sees: how the two compare, in words.
static func claimAssessment(claimantID) -> String:
	var s = svc()
	if(!s.hasOwner()):
		return ""
	var facts:Dictionary = claimFacts(s.ownerID(), claimantID, "none")
	if(!bool(facts["ownerAble"])):
		return nameOf(s.ownerID()) + " is in no state to answer a challenge right now."
	var chance:float = float(OwnershipScript.contestOutcome(facts, 0.5)["ownerChance"])
	if(chance >= 0.65):
		return nameOf(s.ownerID()) + " looks the stronger of the two."
	if(chance <= 0.35):
		return nameOf(claimantID) + " looks the stronger of the two."
	return "It could go either way."

static func willIntervene(helperID:String, attackerID:String) -> bool:
	var pawn = pawnOf(helperID)
	var attackerPawn = pawnOf(attackerID)
	if(pawn == null || attackerPawn == null || pawn.getLocation() != GM.pc.getLocation() || attackerPawn.getLocation() != GM.pc.getLocation()):
		return false
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.id != "AloneInteraction"):
		return false
	var s = svc()
	var trust:float = feeling(helperID, "pc", "trust")
	var affection:float = feeling(helperID, "pc", "affection")
	var respect:float = feeling(helperID, "pc", "respect")
	if(s.hasSlave(helperID)):
		if(slaveBlockReason(helperID) != ""):
			return false # held, badly hurt or busy with something else: they cannot step in
		var disposition:String = slaveDisposition(helperID)
		if(s.slaveRecord(helperID)["role"] == "attendant" && disposition != "defiant" && disposition != "resentful"):
			return true # the post is to watch over the player, so an attendant is there unless they are against it
		return disposition == "loyal" || (disposition == "recovering" && trust >= 10.0) || (disposition == "uncertain" && affection >= 5.0)
	var helperPower:float = GangGameScript.power(helperID)
	var attackerPower:float = GangGameScript.power(attackerID)
	if(helperPower < attackerPower * 0.6 && affection < 40.0):
		return false
	if(feeling(attackerID, helperID, "fear") < 0.0):
		return false
	var willing:bool = s.style() == StyleScript.HARSH || affection >= 0.0 || trust >= 10.0 || respect >= 20.0
	return willing

static func intervene(fight, helperID:String, attackerID:String) -> String:
	var IS = GM.main.IS
	IS.stopInteraction(fight)
	var s = svc()
	if(s.isOwner(helperID)):
		s.recordRetaliation(attackerID, today())
	GM.main.addMessage(nameOf(helperID) + " steps in front of you, and " + nameOf(attackerID) + " turns on " + ("them" if true else "") + ".")
	IS.startInteraction("GenericAttack", {"starter": helperID, "reacter": attackerID})
	return helperID

# A fight between two NPCs ended (the game reports every fight). Tracks the owner's fights: how they fared against the people they went after, and any loss that weakens their word.
static func onNpcFightResult(wonID, lostID) -> void:
	if(!isReady() || !svc().hasOwner()):
		return
	var s = svc()
	var ownerID:String = s.ownerID()
	var day:int = today()
	if(wonID == ownerID && s.isAggressor(lostID)):
		s.recordRetaliationResult(lostID, true, day)
	elif(lostID == ownerID):
		if(s.isAggressor(wonID)):
			s.recordRetaliationResult(wonID, false, day)
		else:
			s.recordOwnerLoss(day)

# The owner goes after someone who hurt the player: at most one attempt per aggressor every few days, only if credible and free, and they give up after repeated failures. The owner walks to the
# aggressor (see routineOverride) and starts an ordinary fight when they meet.
static func retaliationCandidate() -> String:
	var s = svc()
	if(!s.hasOwner() || !bool(ownerAvailability(s.ownerID())["ok"])):
		return ""
	var candidates:Array = []
	for id in s.record()["aggressors"].keys():
		if(pawnOf(id) != null && float(protectionFor(id)["credibility"]) >= 0.2): # only against someone the owner can really face
			candidates.append(id)
	return s.retaliationTarget(today(), candidates)

# When the owner and the person they hunt stand in the same room and both are free, the attempt begins. Returns true when it started.
static func retaliationTick() -> bool:
	var s = svc()
	var target:String = retaliationCandidate()
	if(target == ""):
		return false
	var ownerPawn = pawnOf(s.ownerID())
	var targetPawn = pawnOf(target)
	if(ownerPawn == null || targetPawn == null || ownerPawn.getLocation() != targetPawn.getLocation()):
		return false
	if(!ownerPawn.canBeInterrupted() || !targetPawn.canBeInterrupted()):
		return false
	s.recordRetaliation(target, today())
	GM.main.IS.startInteraction("GenericAttack", {"starter": s.ownerID(), "reacter": target})
	return true

# ---- A new owner ----
# BDCC has just made this character the player's owner (from the protection ask, the console, a debug conversion or an old event). Gives the module's record (unless the voluntary route sets it up with
# its own terms), a day of grace before the first owner visit, and one message with the terms.
static func onOwnerBegan(characterID, voluntary:bool) -> void:
	if(!isReady() || !(characterID is String) || characterID == ""):
		return
	if(!voluntary):
		reconcile()
	var slavery = GM.main.RS.getSpecialRelationship(characterID)
	if(slavery != null && slavery.get("npcOwner") != null):
		slavery.npcOwner.checkNextApproachDay(false)
		if(int(slavery.npcOwner.nextApproachDay) <= today()):
			slavery.npcOwner.nextApproachDay = today() + 1 # the first visit is never on the same day, let alone the same frame
	var _learned:bool = module().learnCell(characterID) # (the relationship's own message says who they are; the terms are shown once, on the screen that follows, and always on the Ownership page)

static func termsLines(terms:Dictionary) -> Array:
	return [
		"[b]Style:[/b] " + str(terms["styleName"]) + ". " + str(terms["describe"]).replace(str(terms["styleName"]) + ": ", ""),
		"[b]Check-ins:[/b] you report to " + (str(terms["cell"]) if str(terms["cell"]) != "" else "their cell") + " " + str(terms["checkin"]) + ", between 21:00 and 23:00.",
		"[b]Demands:[/b] " + str(terms["demands"]) + ".",
		"[b]Protection:[/b] " + str(terms["protection"]) + ". " + PoolStringArray(terms["reasons"]).join(" "),
		"[b]Minimum period:[/b] " + str(terms["days"]) + " days before you can ask to be let go or buy your way out.",
	]

# What the screen says when somebody has become the player's owner: who, and on what terms.
static func ownerStartedText(characterID) -> String:
	if(!isReady()):
		return nameOf(characterID) + " is your owner now."
	if(!svc().isOwner(characterID)):
		return "[b]" + nameOf(characterID) + "[/b] is not your owner." + (" " + nameOf(svc().ownerID()) + " is." if svc().hasOwner() else "")
	return "[b]" + nameOf(characterID) + "[/b] is your owner now.\n\n" + PoolStringArray(termsLines(termsFor(characterID))).join("\n") + "\n\n[color=#c8c8d8]They will find you; the first visit is not today. Your owner's check-ins and demands happen in person.[/color]"

# ---- Voluntary ownership ----
# Whether this character could be asked for protection. {"show", "ok", "reason"}: show false hides the choice altogether (staff, slaves, already part of something).
static func canAskProtection(npcID:String) -> Dictionary:
	if(!isReady() || npcID == "pc"):
		return {"show": false, "ok": false, "reason": ""}
	var theChar = GM.main.getCharacter(npcID)
	if(theChar == null || !theChar.isDynamicCharacter() || !theChar.isInmate() || theChar.isStaff() || theChar.isSlaveToPlayer() || theChar.hasEnslaveQuest()):
		return {"show": false, "ok": false, "reason": ""}
	var s = svc()
	if(s.hasOwner()):
		return {"show": true, "ok": false, "reason": "You already have an owner. Settle that first."}
	if(GM.main.RS.hasSpecialRelationship(npcID)):
		return {"show": false, "ok": false, "reason": ""}
	if(GM.main.PS != null):
		return {"show": true, "ok": false, "reason": "You are in no position to ask right now."}
	if(module().getGangs().isCaptive(npcID) || ownerCellRoom(npcID) == ""):
		return {"show": true, "ok": false, "reason": "They are not in a position to look after anybody."}
	var last:Dictionary = s.data()["last_release"]
	if(!last.empty() && today() - int(last.get("day", -100)) < 2):
		return {"show": true, "ok": false, "reason": "You only just got free. Give it a couple of days."}
	return {"show": true, "ok": true, "reason": ""}

# What the decision is made from (see Ownership.protectorDecision): plain numbers about the candidate, read from the game.
static func candidateFacts(npcID:String) -> Dictionary:
	var traits:Dictionary = traitsOf(npcID)
	var gangs = module().getGangs()
	var gid:String = gangs.gangOf(npcID)
	var own:String = gangs.playerGang()
	var mine:float = GangGameScript.power(npcID)
	var below:float = 0.0
	var total:float = 0.0
	for otherID in GM.main.getDynamicCharacterIDsFromPool(CharacterPool.Inmates):
		if(otherID == npcID):
			continue
		var other:float = GangGameScript.power(otherID)
		total += 1.0
		below += 1.0 if other < mine else (0.5 if other == mine else 0.0)
	var warm:bool = true
	if(own != "" && gangs.getLeader(own) == npcID):
		warm = GangGameScript.leaderMood(npcID) != "hostile" && GangGameScript.leaderMood(npcID) != "wary"
	return {
		"powerRank": below / total if total > 0.0 else 0.5,
		"gangBacking": clamp(GangGameScript.gangStrength(gid) / 6.0, 0.0, 1.0) if gid != "" else 0.0,
		"isLeader": gid != "" && gangs.getLeader(gid) == npcID,
		"subby": float(traits["subby"]),
		"trust": feeling(npcID, "pc", "trust"), "respect": feeling(npcID, "pc", "respect"), "affection": feeling(npcID, "pc", "affection"), "fear": feeling(npcID, "pc", "fear"),
		"desire": clamp(GM.main.RS.getLust(npcID, "pc"), -1.0, 1.0),
		"injury": module().getInjuries().highestSeverity(npcID),
		"captive": gangs.isCaptive(npcID),
		"ownGangLeader": own != "" && gangs.getLeader(own) == npcID,
		"ownGangMember": own != "" && gid == own,
		"ownGangWarm": warm,
		"gangHostile": gid != "" && gid != own && bool(gangs.effectiveStatus("pc", gid)["hostile"]),
		"gangEnemy": gid != "" && own != "" && gid != own && gangs.areEnemies(gid, own),
		"playerBacked": own != "" && GangGameScript.gangStrength(own) >= 6.0,
	}

# The NPC's decision (capability and willingness are separate, see Ownership.protectorDecision). Returns {"accepts", "score", "capability", "willingness", "reasons": [at most two, in their words], "hint"}.
static func protectionDecision(npcID:String) -> Dictionary:
	return OwnershipScript.protectorDecision(candidateFacts(npcID))

# The terms the NPC would set, shown before the player agrees.
static func termsFor(npcID:String) -> Dictionary:
	var styleName:String = styleFor(npcID)
	var facts:Dictionary = {"hasOwner": true, "style": styleName, "ownerPower": GangGameScript.power(npcID), "attackerPower": 0.9, "attackerFear": 0.0,
		"gangStrength": GangGameScript.gangStrength(module().getGangs().gangOf(npcID)) if module().getGangs().gangOf(npcID) != "" else 0.0, "retaliated": false, "available": true, "recentLosses": 0}
	var protection:Dictionary = OwnershipScript.protection(facts)
	return {"style": styleName, "styleName": StyleScript.nameOf(styleName), "describe": StyleScript.describe(styleName), "checkin": StyleScript.checkinText(styleName),
		"demands": StyleScript.demandsText(styleName), "protection": protection["band"], "reasons": protection["reasons"], "days": OwnershipScript.MIN_TERM_DAYS, "cell": cellLabelOf(npcID)}

# The player agrees. BDCC's own relationship is started (the same one the existing "Ask to become slave" starts) and the record notes that it was voluntary, so it cannot be undone on the spot.
static func startVoluntary(npcID:String) -> bool:
	var info:Dictionary = canAskProtection(npcID)
	if(!bool(info["ok"]) || !bool(protectionDecision(npcID)["accepts"])):
		return false
	var extender = GlobalRegistry.getGameExtender("SandboxGameExtender")
	extender.startingVoluntary = true
	GM.main.RS.startSpecialRelantionship("SoftSlavery", npcID)
	extender.startingVoluntary = false
	if(vanillaOwnerID() != npcID):
		return false
	var s = svc()
	var _begun:bool = s.begin(npcID, today(), true, styleFor(npcID), axisNow())
	var _learned:bool = module().learnCell(npcID)
	var slavery = GM.main.RS.getSpecialRelationship(npcID)
	if(slavery != null && slavery.get("npcOwner") != null):
		slavery.npcOwner.checkNextApproachDay(false) # BDCC's own first approach is days away, not now (its intro event usually sets this)
	return true

# ---- Leaving ----
static func releaseFacts() -> Dictionary:
	var s = svc()
	var ownerID:String = s.ownerID()
	var trust:float = feeling(ownerID, "pc", "trust")
	var respect:float = feeling(ownerID, "pc", "respect")
	var affection:float = feeling(ownerID, "pc", "affection")
	return {"day": today(), "trust": trust, "respect": respect, "affection": affection, "fear": feeling(ownerID, "pc", "fear"), "credits": GM.pc.getCredits(), "protection": protectionSummary()["band"],
		"gangHelp": bool(gangHelp()["available"]), "hostile": trust <= -50.0 && respect <= -30.0 && affection <= -30.0}

static func releaseRoutes() -> Array:
	var s = svc()
	if(!s.hasOwner()):
		return []
	return s.releaseRoutes(releaseFacts())

static func routeAvailable(routeID:String) -> bool:
	for route in releaseRoutes():
		if(route["id"] == routeID):
			return bool(route["available"])
	return false

static func finalPaymentFor(styleName:String) -> int:
	return {"lenient": 0, "controlling": 5, "harsh": 10}.get(styleName, 5)

# Ends the ownership in BDCC and in the record. Messages are shown by the caller.
static func releasePlayer(how:String, byOwner:bool = false) -> void:
	var s = svc()
	if(!s.hasOwner()):
		return
	var ownerID:String = s.ownerID()
	var ownerName:String = nameOf(ownerID)
	if(GM.main.RS.hasSpecialRelationshipID(ownerID, "SoftSlavery")):
		GM.main.RS.stopSpecialRelationship(ownerID)
	var _gone:Dictionary = s.end(today(), how)
	if(byOwner):
		say(ownerName + " has let you go. " + str(TextScript.releaseSpeech(how, StyleScript.CONTROLLING)), COLOR_GOOD)
	match(how):
		"negotiate":
			var _a:float = rel().adjustFeeling(ownerID, "pc", "respect", 2.0)
		"defy":
			var _f:float = rel().adjustFeeling(ownerID, "pc", "fear", 10.0)
		"gang":
			var _t:float = rel().adjustFeeling(ownerID, "pc", "trust", -25.0)
			var _af:float = rel().adjustFeeling(ownerID, "pc", "affection", -15.0)

# A negotiated release: needs the route. May ask for a last payment. Returns {"ok", "text", "needs": credits}.
static func negotiateRelease(confirm:bool) -> Dictionary:
	var s = svc()
	if(!routeAvailable("negotiate")):
		return {"ok": false, "text": TextScript.say(s.ownerID(), TextScript.releaseRefused(s.style())), "needs": 0}
	var due:int = finalPaymentFor(s.style())
	if(!confirm):
		return {"ok": false, "text": TextScript.finalPaymentText(s.style(), due), "needs": due, "asking": true}
	if(GM.pc.getCredits() < due):
		return {"ok": false, "text": "You cannot pay that yet.", "needs": due}
	var ownerID:String = s.ownerID()
	var style:String = s.style()
	GM.pc.addCredits(-due)
	releasePlayer("negotiate")
	return {"ok": true, "text": TextScript.say(ownerID, TextScript.releaseSpeech("negotiate", style)), "needs": due}

static func buyout() -> Dictionary:
	var s = svc()
	if(!routeAvailable("buyout")):
		return {"ok": false, "text": "They will not take money from you right now."}
	var cost:int = 0
	for route in releaseRoutes():
		if(route["id"] == "buyout"):
			cost = int(route["cost"])
	if(GM.pc.getCredits() < cost):
		return {"ok": false, "text": "You need " + str(cost) + " credits."}
	var ownerID:String = s.ownerID()
	var style:String = s.style()
	GM.pc.addCredits(-cost)
	releasePlayer("buyout")
	return {"ok": true, "text": TextScript.say(ownerID, TextScript.releaseSpeech("buyout", style)), "cost": cost}

static func demandRelease() -> Dictionary:
	var s = svc()
	if(!routeAvailable("defy")):
		return {"ok": false, "text": "You have not beaten them often enough for them to take you seriously."}
	var ownerID:String = s.ownerID()
	var style:String = s.style()
	releasePlayer("defy")
	return {"ok": true, "text": TextScript.say(ownerID, TextScript.releaseSpeech("defy", style))}

# Outside help: a gang member in good standing in a gang strong enough. Costs standing and treasury, and the owner takes it badly.
static func gangHelp() -> Dictionary:
	var result:Dictionary = {"available": false, "gid": "", "leader": "", "why": ""}
	if(!isReady() || !svc().hasOwner()):
		return result
	var g = module().getGangs()
	var gid:String = g.playerGang()
	if(gid == "" || g.getGang(gid).get("player", false) || g.getLeader(gid) == ""):
		result["why"] = "You are not in a gang."
		return result
	var s = svc()
	var ownerGid:String = g.gangOf(s.ownerID())
	if(ownerGid == gid):
		result["why"] = "Your owner is one of your own gang."
		return result
	if(g.getPersonal("pc", gid) < 25):
		result["why"] = "You do not stand high enough with them."
		return result
	var ownerStrength:float = float(protectionFor("")["credibility"]) * 6.0
	if(GangGameScript.gangStrength(gid) < max(3.0, ownerStrength)):
		result["why"] = "Your gang is not strong enough to face them."
		return result
	if(int(g.data()["cooldowns"].get("owner_help_day", -100)) >= today() - 3):
		result["why"] = "They already did something for you lately."
		return result
	result["available"] = true
	result["gid"] = gid
	result["leader"] = g.getLeader(gid)
	return result

static func askGangForHelp() -> Dictionary:
	var info:Dictionary = gangHelp()
	if(!bool(info["available"])):
		return {"ok": false, "text": str(info["why"])}
	var g = module().getGangs()
	var gid:String = str(info["gid"])
	var s = svc()
	var ownerGid:String = g.gangOf(s.ownerID())
	var _standing:int = g.addPersonal("pc", gid, -10.0)
	var _treasury:int = g.addTreasury(gid, -int(min(8, g.availableTreasury(gid))))
	g.data()["cooldowns"]["owner_help_day"] = today()
	if(ownerGid != "" && ownerGid != gid):
		var _h:int = g.recordHarm("pc", ownerGid, "attack")
	releasePlayer("gang")
	return {"ok": true, "text": "Your gang's people lean on " + nameOf(s.record().get("id", "")) + ". It costs you standing, and some of their treasury, and your former owner will not forget it."}

# ---- Owned NPCs ----
static func slaveFeelings(characterID) -> Dictionary:
	return {"trust": feeling(characterID, "pc", "trust"), "respect": feeling(characterID, "pc", "respect"), "fear": feeling(characterID, "pc", "fear"), "affection": feeling(characterID, "pc", "affection")}

static func slaveDisposition(characterID) -> String:
	var s = svc()
	var f:Dictionary = slaveFeelings(characterID)
	var rec:Dictionary = s.slaveRecord(characterID)
	var recovering:bool = !rec.empty() && (rec["role"] == "rest" || (int(rec["last_treat"]) >= today() - 2 && int(rec["last_treat"]) >= 0))
	return OwnershipScript.disposition(f["trust"], f["respect"], f["fear"], f["affection"], recovering)

static func slaveIsHurt(characterID) -> bool:
	return module().getInjuries().highestSeverity(characterID) > 0

static func slaveLocationText(characterID) -> String:
	var pawn = pawnOf(characterID)
	if(pawn == null):
		return "not around"
	return roomName(pawn.getLocation())

static func slaveActivityText(characterID) -> String:
	var pawn = pawnOf(characterID)
	if(pawn == null || pawn.currentInteraction == null):
		return "resting somewhere"
	var interaction = pawn.currentInteraction
	if(interaction.id == "AloneInteraction" && interaction.goal != null && interaction.goal.get("kind") != null):
		var text:String = module().getRoutineText(str(interaction.goal.kind), pawn.getLocation(), str(interaction.goal.target), "")
		return text.replace("{main.name}", "").replace("{main.his}", "their").replace("{main.he}", "they").strip_edges().trim_suffix(".")
	return "busy"

# How BDCC really lets the player get a slave (read from the game's own enslaving code: the Enslave!/Kidnap! buttons after a defeat, the collar and space checks, the breaking quest, the Alpha shortcut, Socket's cell upgrade).
static func acquisitionHelp() -> String:
	var npcSlavery = GlobalRegistry.getModule("NpcSlaveryModule")
	var space:int = int(npcSlavery.getSlavesSpace()) if npcSlavery != null else 0
	var cost:int = int(npcSlavery.getSlavesSpaceUpgradeCost()) if npcSlavery != null else 30
	var lines:Array = [
		"1. [b]Room:[/b] you need space for a slave in your cell. Talk to Socket and see the cell upgrades: the cell expansion costs " + str(cost) + " credits now (you have room for " + str(space) + "), and each further space costs 10 credits for every slave you can already keep.",
		"2. [b]Defeat them:[/b] beat an inmate in a fight (or end up with them after a defeat). An [b]Enslave![/b] button appears if they wear a collar (inmates do) and your arms are free. Pick the kind of slave to make of them.",
		"3. [b]Break them:[/b] that starts a breaking quest, with tasks listed in the personality status effect (choking them rerolls the tasks). When all of them are done the game tells you they are ready to be enslaved.",
		"4. [b]Kidnap them:[/b] after a defeat the [b]Kidnap![/b] button appears: you leash them and take them to your cell. They walk there themselves, and then wait for your instructions.",
		"5. [b]A shortcut:[/b] a submissive inmate you can already dominate (high Alpha reputation) may offer an [b]Enslave![/b] option when you talk to them.",
		"6. [b]Afterwards:[/b] talk to them and choose [b]Give instructions[/b]: their role, where they sleep at night, rewards and release.",
	]
	return PoolStringArray(lines).join("\n")

# Giving instructions needs the slave to be physically here and able to answer. It never depends on their mood for ordinary conversation, how they feel about the player, or any dice.
static func instructionsBlock(characterID) -> String:
	if(!isReady() || !svc().hasSlave(characterID)):
		return "They are not your slave."
	var pawn = pawnOf(characterID)
	if(pawn == null || pawn.getLocation() != GM.pc.getLocation()):
		return "They are not here. Instructions are given in person."
	if(module().getGangs().isCaptive(characterID)):
		return "They are being held and cannot answer you."
	var interaction = pawn.currentInteraction
	if(interaction != null && !(interaction.id in ["AloneInteraction", "Talking"])):
		return "They cannot answer you right now (" + ("unconscious" if interaction.id == "Unconscious" else "busy with something else") + ")."
	return ""

# Where a travelling slave is going ("" when they are where they are going or are not on a routine goal).
static func slaveDestinationText(characterID) -> String:
	var pawn = pawnOf(characterID)
	if(pawn == null || pawn.currentInteraction == null || pawn.currentInteraction.id != "AloneInteraction"):
		return ""
	var goal = pawn.currentInteraction.goal
	if(goal == null || goal.get("target") == null || goal.id != "SandboxRoutine"):
		return ""
	var target:String = str(goal.target)
	return roomName(target) if target != pawn.getLocation() && hasRoom(target) else ""

# Role, night arrangement and whether they are still waiting, in one line.
static func slaveArrangementText(characterID) -> String:
	var rec:Dictionary = svc().slaveRecord(characterID)
	if(rec.empty()):
		return ""
	if(rec["setup"] == "awaiting"):
		return "Awaiting instructions."
	return str(OwnershipScript.ROLE_NAMES[rec["role"]]) + "; " + str(OwnershipScript.NIGHT_NAMES[rec["night"]]).to_lower() + "."

static func slaveInjuryText(characterID) -> String:
	var severity:int = module().getInjuries().highestSeverity(characterID)
	return "none" if severity <= 0 else InjuriesScript.severityName(severity)

# Whether the slave can actually do their job now: not held, not hurt badly, not in the middle of something else.
static func slaveCanWork(characterID) -> bool:
	var pawn = pawnOf(characterID)
	if(pawn == null || module().getGangs().isCaptive(characterID)):
		return false
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.id != "AloneInteraction"):
		return false
	return module().getInjuries().highestSeverity(characterID) < InjuriesScript.MODERATE

# Why this slave cannot walk anywhere or lend a hand right now ("" when they can): not around, held by a gang, busy with something else (that includes being knocked out), badly hurt.
static func slaveBlockReason(characterID) -> String:
	var pawn = pawnOf(characterID)
	if(pawn == null):
		return "not around"
	if(module().getGangs().isCaptive(characterID) || module().getGangs().isDetained(characterID)):
		return "held"
	if(module().getInjuries().highestSeverity(characterID) >= InjuriesScript.SEVERE):
		return "badly hurt"
	if(module().isPawnBlocked(pawn)):
		return "busy"
	return ""

static func routeExists(fromRoom:String, toRoom:String) -> bool:
	if(fromRoom == toRoom):
		return true
	if(GM.world == null || !is_instance_valid(GM.world) || !hasRoom(fromRoom) || !hasRoom(toRoom)):
		return false
	var path = GM.world.calculatePath(fromRoom, toRoom)
	return path != null && path.size() >= 2

# Whether this slave can be sent to the player's cell now: "" or the reason they cannot (shown instead of the order).
static func reportProblem(characterID) -> String:
	var reason:String = slaveBlockReason(characterID)
	if(reason == "held"):
		return "They are being held and cannot come."
	if(reason == "badly hurt"):
		return "They are too badly hurt to walk over."
	if(reason == "not around"):
		return "They are not around."
	var pawn = pawnOf(characterID)
	if(!routeExists(pawn.getLocation(), str(GM.pc.getCellLocation()))):
		return "There is no way for them to get to your cell."
	return ""

# Where they are and what they are doing, for when the player is not standing in front of them (commands are given in person).
static func slaveStatusText(characterID) -> String:
	var name:String = nameOf(characterID)
	var line:String = name + " is in " + slaveLocationText(characterID) + ", " + slaveActivityText(characterID) + "."
	var destination:String = slaveDestinationText(characterID)
	if(destination != ""):
		line += " They are on the way to " + destination + "."
	line += " " + slaveArrangementText(characterID)
	var rec:Dictionary = svc().slaveRecord(characterID)
	if(!rec.empty() && !rec["report"].empty() && int(rec["report"]["day"]) == today() && rec["report"]["state"] == "pending" && !bool(rec["report"].get("refused", false))):
		line += " They are on their way to your cell this evening."
	return line + "\n\n[color=#c8c8d8]To give them an order, find them and talk to them.[/color]"

# A character has just been enslaved by the player. The pawn is where it was; here the module picks them up: they wait for instructions, and how they feel about it is worked out once from how it happened
# (see Ownership.aftermathKind). route: "free" (the game's "Enslave!" talk option), "kidnap" (the kidnap scene: the slave then walks to the player's cell) or "" (anything else, such as the console).
static func onEnslaved(characterID, hadQuest:bool, route:String) -> void:
	if(!isReady() || !(characterID is String) || characterID == ""):
		return
	reconcile([characterID])
	var s = svc()
	if(!s.hasSlave(characterID)):
		return
	if(route != ""):
		s.data()["slaves"][characterID]["wait_cell"] = true # both routes end with the kidnap scene "bring them to your cell": they then walk there on their own
	var enslaved = pawnOf(characterID)
	if(enslaved != null):
		var holdRoom:String = str(GM.pc.getCellLocation()) if (route != "" && hasRoom(str(GM.pc.getCellLocation()))) else enslaved.getLocation()
		var _held:bool = PopulationScript.directPawn(enslaved, "wait", holdRoom) # waiting starts this very moment: not one more step of whatever they were doing
	var day:int = today()
	var defeat:Dictionary = s.lastDefeat(characterID)
	var defeatKind:String = str(defeat["kind"]) if (!defeat.empty() && day - int(defeat["day"]) <= 3) else ""
	var now:Dictionary = slaveFeelings(characterID)
	var kind:String = OwnershipScript.aftermathKind(hadQuest, route, defeatKind, float(now["affection"]), float(now["trust"]))
	if(s.markAftermath(characterID, kind, day)):
		var deltas:Dictionary = OwnershipScript.aftermathDeltas(kind, defeatKind, now)
		var parts:Array = []
		for axis in ["trust", "affection", "respect", "fear", "desire"]:
			if(float(deltas[axis]) != 0.0):
				var _moved:float = rel().adjustFeeling(characterID, "pc", axis, float(deltas[axis]))
				parts.append(axis + (" +" if float(deltas[axis]) > 0.0 else " ") + str(int(deltas[axis])))
		if(!parts.empty()):
			say(nameOf(characterID) + "'s feelings about you changed (" + PoolStringArray(parts).join(", ") + ").", COLOR_GOOD if kind == "voluntary" else COLOR_BAD)
	say(nameOf(characterID) + " is awaiting your instructions. Talk to them and choose Give instructions.", COLOR_INFO)

# What a slave's role puts them at right now: {} (their ordinary day) or {"kind", "room"} for the director.
static func routineOverride(characterID, day:int, axis:int) -> Dictionary:
	if(!isReady()):
		return {}
	var s = svc()
	if(s.hasOwner() && s.ownerID() == characterID):
		var cell:String = ownerCellRoom(characterID)
		if(cell != "" && bool(ownerAvailability(characterID)["ok"]) && hasRoom(cell)):
			if(s.isCheckinPending(day) && axis >= OwnershipScript.REMINDER_AT - 900 && axis <= OwnershipScript.LATE_UNTIL):
				return {"kind": "cellrest", "room": cell}
			var d:Dictionary = s.demand()
			if(!d.empty() && str(d["type"]) == "report" && d["state"] == "active" && int(d["day"]) == day && axis >= int(d["at"]) - 900 && axis <= int(d["at"]) + 5400):
				return {"kind": "cellrest", "room": cell}
		var target:String = retaliationCandidate()
		if(target != "" && axis >= DEMAND_HOURS[0] && axis <= DEMAND_HOURS[1]):
			var targetPawn = pawnOf(target)
			if(targetPawn != null && hasRoom(targetPawn.getLocation())):
				return {"kind": "hunt", "room": targetPawn.getLocation()}
		return {}
	if(!s.hasSlave(characterID)):
		return {}
	var rec:Dictionary = s.slaveRecord(characterID)
	var disposition:String = slaveDisposition(characterID)
	if(!rec["escape"].empty() && rec["escape"]["stage"] == "attempt" && hasRoom(EXIT_ROOM)):
		return {"kind": "escape", "room": EXIT_ROOM}
	var pcCell:String = str(GM.pc.getCellLocation())
	if(!rec["report"].empty() && int(rec["report"]["day"]) == day && rec["report"]["state"] == "pending" && !bool(rec["report"].get("refused", false)) && axis >= REPORT_WINDOW[0] && axis <= REPORT_WINDOW[1] && hasRoom(pcCell)):
		var walker = pawnOf(characterID)
		if(walker != null && routeExists(walker.getLocation(), pcCell)):
			return {"kind": "report", "room": pcCell}
	var self_pawn = pawnOf(characterID)
	if(rec["setup"] == "awaiting" && self_pawn != null):
		# a new slave waits for instructions where they are (or, taken by the game's own kidnap, walks to the player's cell and waits there): no routine, no wandering off
		if(bool(rec["wait_cell"]) && hasRoom(pcCell) && routeExists(self_pawn.getLocation(), pcCell)):
			return {"kind": "wait", "room": pcCell}
		return {"kind": "wait", "room": self_pawn.getLocation()}
	if(rec["night"] == "player" && self_pawn != null && hasRoom(pcCell) && (axis >= OwnershipScript.NIGHT_START || axis < nightEnd(characterID)) && routeExists(self_pawn.getLocation(), pcCell)):
		return {"kind": "nightcell", "room": pcCell}
	var role:String = str(rec["role"])
	if(!s.roleActive(characterID, OwnershipScript.clockOf(day, axis))):
		return {} # a role just given takes over a little later, not on the spot
	if(!OwnershipScript.willDo(role, disposition)):
		return {}
	if(role == "earner" && axis >= EARN_WINDOW[0] && axis <= EARN_WINDOW[1]):
		var room:String = earnRoom(characterID, day)
		if(room != ""):
			return {"kind": "earn", "room": room}
	if(role == "attendant"):
		for window in ATTENDANT_WINDOWS():
			if(axis >= window[0] && axis <= window[1]):
				var hall:String = attendRoom()
				if(hall != ""):
					return {"kind": "attend", "room": hall}
	if(role == "rest" && axis >= REST_WINDOW[0] && axis <= REST_WINDOW[1]):
		var home:String = module().homeRoomOf(characterID)
		if(home != "" && hasRoom(home)):
			return {"kind": "cellrest", "room": home}
	return {}

# When a slave who sleeps in the player's cell gets up: when their own plan has them wake, else 07:00.
static func nightEnd(characterID) -> int:
	var plan = module().getState().routines["plans"].get(characterID, [])
	if(plan is Array && !plan.empty() && plan[0] is Array && plan[0].size() == 4 && str(plan[0][2]) == "sleep"):
		return int(plan[0][1])
	return OwnershipScript.NIGHT_END

static func ATTENDANT_WINDOWS() -> Array:
	return ATTEND_WINDOWS

static func earnRoom(characterID, day:int) -> String:
	var rooms:Array = []
	if(GM.world != null && is_instance_valid(GM.world) && GM.world.get_tree().has_group("zone_prostitution")):
		rooms = GM.world.getZoneRooms("prostitution", EARN_ROOMS)
	if(rooms.empty()):
		rooms = EARN_ROOMS
	var valid:Array = []
	for room in rooms:
		if(hasRoom(str(room))):
			valid.append(str(room))
	if(valid.empty()):
		return ""
	valid.sort()
	return str(valid[OwnershipScript.pickIndex(str(characterID) + str(day) + "spot", valid.size())])

static func attendRoom() -> String:
	var entry:Dictionary = module().getCells().getCell("pc")
	if(entry.empty()):
		return ""
	var hall:String = str(LayoutScript.HALL_ROOMS.get(entry["block"], ""))
	return hall if hasRoom(hall) else ""

# ---- The slaves' days ----
# Every time the clock moves: earners who are at their post count as having worked; once a day the day before is settled.
static func slaveTick() -> void:
	var s = svc()
	var day:int = today()
	var axis:int = axisNow()
	for id in s.slaveIDs():
		var rec:Dictionary = s.slaveRecord(id)
		if(rec["role"] == "earner" && axis >= EARN_WINDOW[0] && axis <= EARN_WINDOW[1] && slaveCanWork(id)):
			var pawn = pawnOf(id)
			var room:String = earnRoom(id, day)
			if(pawn != null && room != "" && pawn.getLocation() == room):
				s.data()["slaves"][id]["attended_day"] = day
	for id in s.slaveIDs():
		reportStep(id, day, axis)
		var waiting:Dictionary = s.slaveRecord(id)
		if(bool(waiting["wait_cell"])):
			var arriving = pawnOf(id)
			if(arriving != null && arriving.getLocation() == str(GM.pc.getCellLocation())):
				s.data()["slaves"][id]["wait_cell"] = false # arrived: they wait here now
	var last:int = int(s.data().get("tick_day", -1))
	if(last == day):
		return
	s.data()["tick_day"] = day
	if(last < 0):
		return
	for id in s.slaveIDs():
		settleSlaveDay(id, last, day)

# "Report to my cell" ends exactly once: by arriving (they are standing in the player's cell room) or by being cancelled (held, badly hurt, no way there). Being busy only delays it.
static func reportStep(characterID, day:int, axis:int) -> void:
	var s = svc()
	var rec:Dictionary = s.slaveRecord(characterID)
	var report:Dictionary = rec["report"]
	if(report.empty() || int(report["day"]) != day || report["state"] != "pending" || bool(report.get("refused", false)) || axis < REPORT_WINDOW[0] || axis > REPORT_WINDOW[1]):
		return
	var pawn = pawnOf(characterID)
	var name:String = nameOf(characterID)
	var cell:String = str(GM.pc.getCellLocation())
	var reason:String = slaveBlockReason(characterID)
	if(pawn != null && pawn.getLocation() == cell && (reason == "" || reason == "busy")):
		s.data()["slaves"][characterID]["report"]["state"] = "done"
		var _r:float = rel().adjustFeeling(characterID, "pc", "respect", 0.5)
		say(name + " has come to your cell as you asked.", COLOR_INFO)
		return
	if(reason == "busy" && pawn != null):
		s.data()["slaves"][characterID]["report"]["delayed"] = true # (unconscious or otherwise occupied: the order waits, and walks again once they are free, while the window is open)
		return
	if(reason == "held" || reason == "badly hurt" || reason == "not around" || (pawn != null && !routeExists(pawn.getLocation(), cell))):
		s.data()["slaves"][characterID]["report"]["state"] = "cancelled"
		say(name + " could not come to your cell (" + ("there is no way there" if reason == "" || reason == "busy" else reason) + ").", COLOR_WARN)

static func settleSlaveDay(characterID, oldDay:int, newDay:int) -> void:
	var s = svc()
	if(GM.main.getCharacter(characterID) == null):
		return
	var rec:Dictionary = s.slaveRecord(characterID)
	var name:String = nameOf(characterID)
	var disposition:String = slaveDisposition(characterID)
	# earner income, once a day, only for a day they really worked
	if(rec["role"] == "earner"):
		var attended:bool = int(rec["attended_day"]) == oldDay && slaveCanWork(characterID)
		var amount:int = s.creditEarnings(characterID, oldDay, attended)
		if(amount > 0):
			var _t:float = rel().adjustFeeling(characterID, "pc", "trust", -1.5)
			var _f:float = rel().adjustFeeling(characterID, "pc", "fear", 1.0)
			say(name + " brought in " + str(amount) + " credits. They are waiting for you to collect them.", COLOR_GOOD)
	# rest and a free routine mend things
	if(rec["role"] == "rest"):
		healSlave(characterID, 8)
		var _rt:float = rel().adjustFeeling(characterID, "pc", "trust", 2.0)
	elif(rec["role"] == "free" && feeling(characterID, "pc", "trust") < 40.0):
		var _ft:float = rel().adjustFeeling(characterID, "pc", "trust", 1.0)
	# the evening report
	var neglected:bool = int(rec["last_treat"]) < newDay - 3 && int(rec["since"]) < newDay - 3
	if(!rec["report"].empty() && int(rec["report"]["day"]) == oldDay && rec["report"]["state"] == "pending"):
		if(bool(rec["report"].get("delayed", false))):
			s.data()["slaves"][characterID]["report"]["state"] = "cancelled" # something kept them away through the evening: the order simply lapses, nobody is blamed
		else:
			s.data()["slaves"][characterID]["report"]["state"] = "missed"
			neglected = true
			say(name + " did not come when you called.", COLOR_WARN)
	if(rec["role"] == "earner" && disposition != "loyal"):
		neglected = true
	# escape: always telegraphed
	var step:String = s.escapeAdvance(characterID, newDay)
	if(step == "attempt"):
		say(TextScript.telegraphAttempt(name).replace("[color=red]", "").replace("[/color]", ""), COLOR_BAD)
	elif(step == "gone"):
		completeEscape(characterID)
	elif(rec["escape"].empty() && s.escapeStarts(characterID, newDay, disposition, neglected)):
		s.startEscape(characterID, newDay, "feeling " + disposition)
		say(TextScript.telegraphWarning(name, "they are " + disposition).replace("[color=orange]", "").replace("[/color]", ""), COLOR_WARN)

static func healSlave(characterID, hours:int) -> void:
	var injuries = module().getInjuries()
	var all:Dictionary = injuries.getAll(characterID)
	for type in all.keys():
		all[type]["remainingHours"] = float(all[type]["remainingHours"]) - float(hours)
		if(float(all[type]["remainingHours"]) <= 0.0):
			injuries.remove(characterID, type)

# They got away: still an ordinary inmate, with a memory of how they were kept.
static func completeEscape(characterID) -> void:
	var s = svc()
	var name:String = nameOf(characterID)
	var _removed:bool = s.removeSlave(characterID)
	var npcSlavery = GlobalRegistry.getModule("NpcSlaveryModule")
	if(npcSlavery != null):
		var _freed = npcSlavery.doFreeEnslavedCharacter(characterID)
	var _t:float = rel().adjustFeeling(characterID, "pc", "trust", -20.0)
	var _a:float = rel().adjustFeeling(characterID, "pc", "affection", -10.0)
	var _r:float = rel().adjustFeeling(characterID, "pc", "respect", -5.0)
	say(TextScript.telegraphGone(name).replace("[color=orange]", "").replace("[/color]", ""), COLOR_WARN)
	module().refreshMapBadges()

static func stopEscapeByForce(characterID) -> void:
	var s = svc()
	s.stopEscape(characterID, today())
	var _f:float = rel().adjustFeeling(characterID, "pc", "fear", 20.0)
	var _t:float = rel().adjustFeeling(characterID, "pc", "trust", -6.0)

# ---- Journal views (Side Tasks) ----
static func journalView(kind:String) -> Dictionary:
	var empty:Dictionary = {"visible": false, "title": "", "lines": []}
	if(!isReady()):
		return empty
	var s = svc()
	var day:int = today()
	var axis:int = axisNow()
	if(kind == "checkin"):
		if(!s.isCheckinPending(day)):
			return empty
		var ownerID:String = s.ownerID()
		var ownerName:String = nameOf(ownerID)
		var state:String = OwnershipScript.windowState(axis)
		var status:String = {"before": "The window opens at 21:00 (you will be reminded).", "early": "You may report in from now, the window proper opens at 21:00.", "open": "Open now, until 23:00.", "late": "Running late: they will still see you, until 00:30.", "closed": "Too late."}.get(state, "")
		var lines:Array = [status]
		if(!bool(ownerAvailability(ownerID)["ok"])):
			lines.append(ownerName + " is not available (" + str(ownerAvailability(ownerID)["why"]) + "). If they cannot be there you are excused.")
		var label:String = cellLabelOf(ownerID)
		lines.append(ownerName + " lives in " + (label if label != "" else "a cell you cannot find") + ", in the " + blockNameOf(ownerID) + ". Their cell is off the block's main hall.")
		lines.append("Report to " + ownerName + " at their cell tonight (" + TextScript.windowText() + "). Go into the cell and speak to them.")
		return {"visible": true, "title": "Check in with " + ownerName, "lines": lines}
	if(kind == "meeting"):
		if(!s.meetingDue(day) || (str(s.meeting()["purpose"]) == "demand" && s.hasDemand() && s.demand()["state"] == "offered")):
			return empty # (an offered job has its own Side Task: one entry for one obligation)
		return {"visible": true, "title": nameOf(s.ownerID()) + " wants to meet you", "lines": [meetingText()]}
	if(kind == "demand"):
		var d:Dictionary = s.demand()
		if(d.empty()):
			return empty
		var ownerName2:String = nameOf(s.ownerID())
		if(d["state"] == "offered"):
			return {"visible": true, "title": ownerName2 + " has a task for you", "lines": [ownerName2 + " wants to give you a task. Talk to them to hear about the job; they are looking for you.", meetingText() if s.hasMeeting() else ""]}
		var ctx:Dictionary = demandContext()
		var lines2:Array = []
		if(d["state"] == "ready"):
			lines2.append("Done. Report back to " + ownerName2 + " in person.")
		else:
			lines2.append("About " + str(hoursLeft(int(d["deadline"]))) + " hours remaining.")
			lines2.append(ownerName2 + " lives in " + cellLabelOf(s.ownerID()) + ", in the " + blockNameOf(s.ownerID()) + ".")
			lines2.append(TextScript.demandObjective(d, ctx) + ".")
		return {"visible": true, "title": ownerName2 + "'s demand", "lines": lines2}
	if(kind == "slave"):
		for id in s.slaveIDs():
			var rec:Dictionary = s.slaveRecord(id)
			if(rec["escape"].empty()):
				continue
			var name:String = nameOf(id)
			var lines3:Array = []
			if(rec["escape"]["stage"] == "attempt"):
				lines3.append(name + " is making for the exit. Find them before it is too late.")
				lines3.append("Last seen near the main entrance.")
			else:
				lines3.append("They have been avoiding you. Talk to them soon.")
			return {"visible": true, "title": "Your slave " + name, "lines": lines3}
	return empty

# Who the player's ownership tasks point at right now, for the map's yellow Q: [[kind, tooltip text]]. Read from the live state, exactly what the Side Tasks entries show: the owner's check-in and demand
# (somebody to beat, or the owner to hand something to or report back to), and a slave who is about to run.
static func taskMarks(characterID) -> Array:
	var marks:Array = []
	if(!isReady()):
		return marks
	var s = svc()
	if(s.hasOwner() && characterID == s.ownerID()):
		var ownerName:String = nameOf(characterID)
		var action:Dictionary = ownerAction()
		if(action["id"] != ""):
			marks.append(["contact", str(action["mark"]).replace("{owner}", ownerName)]) # (one mark: the same single action the talk menu shows)
	var demand:Dictionary = s.demand()
	if(s.hasOwner() && !demand.empty() && demand["state"] == "active" && str(demand["type"]) == "defeat" && str(demand["target"]) == characterID):
		marks.append(["target", "Defeat " + nameOf(characterID)])
	if(s.hasSlave(characterID) && !s.slaveRecord(characterID)["escape"].empty()):
		marks.append(["contact", "Talk to " + nameOf(characterID) + " before they run"])
	return marks

# ---- Texts for the ownership screen ----
static func summaryLines() -> Array:
	var lines:Array = []
	var s = svc()
	if(!s.hasOwner()):
		return lines
	var ownerID:String = s.ownerID()
	var day:int = today()
	var rec:Dictionary = s.record()
	var protection:Dictionary = protectionSummary()
	lines.append("[b]Owner:[/b] " + nameOf(ownerID))
	lines.append("[b]Style:[/b] " + StyleScript.nameOf(s.style()) + ". " + StyleScript.describe(s.style()).replace(StyleScript.nameOf(s.style()) + ": ", ""))
	var label:String = cellLabelOf(ownerID)
	lines.append("[b]Their cell:[/b] " + (label if label != "" else "none") + (" (" + blockNameOf(ownerID) + ")" if label != "" else ""))
	var pending:bool = s.isCheckinPending(day)
	lines.append("[b]Next check-in:[/b] " + TextScript.nextCheckinLine(day, int(rec["next_checkin"]), pending, OwnershipScript.windowState(axisNow()) if pending else ""))
	var d:Dictionary = s.demand()
	lines.append("[b]Active demand:[/b] " + ((("Done: ready to report to " + nameOf(ownerID) + " at any time" if d["state"] == "ready" else TextScript.demandObjective(d, demandContext())) + (" (still to be told)" if d["state"] == "offered" else "")) if !d.empty() else "none"))
	lines.append("[b]Pending meeting:[/b] " + (meetingText() if s.hasMeeting() else "none"))
	lines.append("[b]Recent warnings:[/b] " + str(s.recentMisses(day)) + (" (" + str(rec["consequence"]) + ")" if str(rec["consequence"]) != "" else ""))
	lines.append("[b]" + TextScript.protectionLine(str(protection["band"])) + "[/b] " + PoolStringArray(protection["reasons"]).join(" "))
	lines.append("[b]" + str(interventionStatus()["text"]) + "[/b]")
	lines.append("[b]Earliest release negotiation:[/b] " + ("now" if s.termEnded(day) else "day " + str(rec["term_end"])))
	return lines

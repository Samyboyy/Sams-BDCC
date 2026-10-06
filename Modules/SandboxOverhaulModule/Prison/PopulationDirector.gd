extends Reference
class_name PopulationDirector

# Keeps every inmate alive in the world, all the time. Each inmate has a pawn at all times and a stored daily plan (DailyRoutine), and the director's job is only to keep the two in step:
#
#  * Nobody is created or removed because of where the player stands. The player's position is not an input to anything here except which fights the player can see. There is no ring,
#    no radius, no spawning at the edge of the map.
#  * Each ten-minute bucket every free inmate is pointed at the segment of their plan that is current, with BDCC's goal system (GoalSandboxRoutine), and walks there room by room along
#    the real map with the normal pathfinding. Busy people (any interaction other than idling, a priority goal, slavery, a quest) are left alone and rejoin their plan when they are free.
#  * If something else in the game deletes an inmate's pawn (story scenes and vanilla goals can), the pawn is brought back in the room where the stored presence record last had them, in
#    the same activity. That is hydration: the character, the record and the plan are the truth and the pawn is how they are shown.
#  * A long time skip (sleeping, waiting) cannot be walked minute by minute, so everybody who is not busy is moved along the real path towards where their plan has them by the distance they
#    could have covered, and arrives there if they had the time. Nobody jumps to a random room.
#  * Staff are never added, removed or moved here: new staff are held to a share of the pawn limit by Module.canSpawnPawnType, and the existing ones keep their own patrols.
#
# It runs on ten-minute buckets and costs a few milliseconds. Unsaved memory lives in the extender's "director" dictionary; everything that must survive is in SandboxState.routines and presence.

const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")
const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")
const PresenceScript = preload("res://Modules/SandboxOverhaulModule/Prison/PresenceState.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

const RING_DEPTH = 2 # only used to decide which fights the player can see (see maybeIncident); never for existence
const JUMP_SECONDS = 20 * 60 # a gap longer than this since the last run is a time skip
const STEP_SECONDS = 60 # one room of walking (measured on the real map: about a minute a room, plus half a minute to set off)
const SETOFF_SECONDS = 90 # the time a pawn needs to notice its new goal (its current action, at most two minutes, finishes first) and take the first step
const EARLY_MIN = 150 # workers aim to be at their workplace two and a half to six and a half minutes before the shift starts...
const EARLY_SPAN = 240
const SAFETY_SECONDS = 2 * 60 # ...and set off two minutes sooner than the walk needs, because people stop and talk on the way: in practice they are there about four to ten minutes early
const COMMUTE_WATCH = 40 * 60 # how long before a shift somebody is looked at every tick for setting off
const SICK_PERCENT = 6 # about one worker in sixteen misses any given day
const INCIDENT_GAP_SECONDS = 3 * 3600 # at most one visible argument or fight between inmates in view every three hours
const INCIDENT_CHANCE = 0.35 # when one is due and two inmates with a quarrel are in the same room
const QUARREL_AFFECTION = -0.3 # on BDCC's -1..1 affection scale between two characters
const STUCK_LIMIT = 3 # actions in a row with no progress towards the target before the walking cache is cleared

# ---- The map ----
# Rooms within `depth` steps of a room on the same floor: {roomID: steps}. world is untyped so tests can pass a stand-in. Only for what the player can see (fights), never for existence.
static func ringOf(world, startID:String, depth:int = RING_DEPTH) -> Dictionary:
	var result:Dictionary = {}
	if(world == null || !world.hasRoomID(startID)):
		return result
	result[startID] = 0
	var queue:Array = [startID]
	while(!queue.empty()):
		var current:String = queue.pop_front()
		var steps:int = result[current]
		if(steps >= depth):
			continue
		for dir in [0, 1, 2, 3]:
			if(!world.canGoID(current, dir)):
				continue
			var nextID:String = world.applyDirectionID(current, dir)
			if(nextID == "" || result.has(nextID)):
				continue
			result[nextID] = steps + 1
			queue.append(nextID)
	return result

# ---- Facts ----
# What the plan needs to know about everybody at once: every gang's hangout, its leader and the member who keeps the leader company.
static func gangFacts(module) -> Dictionary:
	var gangs = module.getGangs()
	var info:Dictionary = {"hangouts": [], "byGang": {}}
	for gid in gangs.gangIDs():
		var hangout:String = gangs.getHangout(gid)
		if(hangout == "" || gangs.getGang(gid).get("player", false)):
			continue
		info["hangouts"].append(hangout)
		var leader:String = gangs.getLeader(gid)
		var members:Array = gangs.activeMembers(gid)
		members.erase(leader)
		members.erase("pc")
		members.sort_custom(AnchorSorter, "byHash")
		info["byGang"][gid] = {"hangout": hangout, "leader": leader, "anchor": str(members[0]) if !members.empty() else ""}
	return info

class AnchorSorter:
	static func byHash(a, b) -> bool:
		var hashA:int = CellsScript.mix(("anchor" + str(a)).hash())
		var hashB:int = CellsScript.mix(("anchor" + str(b)).hash())
		return hashA < hashB if hashA != hashB else str(a) < str(b)

static func factsFor(module, characterID, day:int, gangInfo:Dictionary = {}) -> Dictionary:
	var facts:Dictionary = {"block": "orange", "cellRoom": "", "hangout": "", "leader": false, "anchor": false, "job": "", "available": true, "avoid": [], "visitable": []}
	var entry:Dictionary = module.getCells().getCell(characterID)
	if(!entry.empty()):
		facts["block"] = entry["block"]
		facts["cellRoom"] = LayoutScript.roomID(entry["block"], entry["cell"])
	var gangs = module.getGangs()
	var gid:String = gangs.gangOf(characterID)
	var info:Dictionary = gangInfo if !gangInfo.empty() else gangFacts(module)
	var own:String = ""
	if(gid != "" && info["byGang"].has(gid)):
		var mine:Dictionary = info["byGang"][gid]
		own = mine["hangout"]
		facts["hangout"] = own
		facts["leader"] = mine["leader"] == characterID
		facts["anchor"] = mine["anchor"] == characterID
	var avoid:Array = []
	var visitable:Array = []
	for gangID in info["byGang"]:
		var room:String = info["byGang"][gangID]["hangout"]
		if(room == own):
			continue
		avoid.append(room)
		if(gid == "" && gangs.getPersonal("pc", gangID) > -40):
			visitable.append(room)
	facts["avoid"] = avoid
	facts["visitable"] = visitable
	facts["job"] = module.getNpcJobs().getJob(characterID)
	facts["available"] = module.isAvailableForWork(characterID, day)
	return facts

# The plan for an inmate today: the stored one, or a new one stored now. Plans are generated once per day for everybody (and on first sight for a newcomer).
static func planOf(module, characterID, day:int, facts:Dictionary) -> Array:
	var routines:Dictionary = module.getState().routines
	if(routines["day"] != day):
		routines["day"] = day
		routines["plans"] = {}
	if(routines["plans"].has(characterID)):
		return routines["plans"][characterID]
	var plan:Array = RoutineScript.planFor(characterID, day, facts)
	routines["plans"][characterID] = plan
	return plan

# ---- Counting ----
static func countByType(IS) -> Dictionary:
	var counts:Dictionary = {"inmate": 0, "guard": 0, "nurse": 0, "engineer": 0, "other": 0, "total": 0}
	for charID in IS.getPawns():
		var pawn = IS.getPawn(charID)
		if(pawn == null || pawn.isPlayer()):
			continue
		counts["total"] += 1
		if(pawn.isInmate()):
			counts["inmate"] += 1
		elif(pawn.isGuard()):
			counts["guard"] += 1
		elif(pawn.isNurse()):
			counts["nurse"] += 1
		elif(pawn.isEngineer()):
			counts["engineer"] += 1
		else:
			counts["other"] += 1
	return counts

static func inmatesAt(IS, roomID:String) -> int:
	var count:int = 0
	for pawn in IS.getPawnsAt(roomID):
		if(pawn != null && !pawn.isPlayer() && pawn.isInmate()):
			count += 1
	return count

static func clockOf(day:int, now:int) -> int:
	return day * 86400 + RoutineScript.axis(now) - RoutineScript.DAY_START

# ---- Getting to work ----
# Minutes before the shift a worker wants to be there: five to ten, the same for the same person and day.
static func arriveEarly(characterID, day:int) -> int:
	return EARLY_MIN + ScheduleScript.hashOf(characterID, "early" + str(day)) % (EARLY_SPAN + 1)

# How long the walk takes on the real map from one room to another.
static func commuteSeconds(world, from:String, to:String) -> int:
	if(from == to || !world.hasRoomID(from) || !world.hasRoomID(to)):
		return 0
	var path:Array = world.calculatePath(from, to)
	if(path.size() < 2):
		return 0
	return (path.size() - 1) * STEP_SECONDS + SETOFF_SECONDS

# The index of the work segment somebody should already be heading for, or -1: the segment after the current one is a shift, and it is time to set off (the walk from where they are takes
# commuteSeconds, and they want to be there a few minutes early). Somebody still asleep sets off when they wake.
static func commuteTarget(world, plan:Array, index:int, now:int, here:String, characterID, day:int) -> int:
	if(index < 0 || index + 1 >= plan.size() || str(plan[index + 1][2]) != "work" || str(plan[index][2]) == "sleep"):
		return -1
	var shiftStart:int = int(plan[index + 1][0])
	var toStart:int = shiftStart - RoutineScript.axis(now)
	if(toStart > COMMUTE_WATCH):
		return -1
	var room:String = str(plan[index + 1][3])
	if(toStart <= arriveEarly(characterID, day) + commuteSeconds(world, here, room) + SAFETY_SECONDS):
		return index + 1
	return -1

# Between the director's runs: points every worker who has just reached their setting-off time at the workplace, so nobody arrives after the shift began because the run was minutes away.
static func commutePass(module, now:int, day:int) -> void:
	if(GM.main == null || GM.world == null || !is_instance_valid(GM.world)):
		return
	var IS = GM.main.IS
	var plans:Dictionary = module.getState().routines["plans"]
	if(module.getState().routines["day"] != day):
		return
	var presence:Dictionary = module.getState().presence
	var clock:int = clockOf(day, now)
	for characterID in module.getNpcJobs().employedIDs():
		if(!plans.has(characterID) || module.isHeldAway(characterID) || module.getGangs().isCaptive(characterID)):
			continue
		var pawn = IS.getPawn(characterID)
		if(pawn == null || module.isPawnBlocked(pawn)):
			continue
		var plan:Array = plans[characterID]
		var index:int = RoutineScript.segmentIndex(plan, now)
		var target:int = commuteTarget(GM.world, plan, index, now, pawn.getLocation(), characterID, day)
		if(target < 0):
			continue
		var room:String = str(plan[target][3])
		if(!GM.world.hasRoomID(room) || isPinned(pawn, "work", room)):
			continue
		if(directPawn(pawn, "work", room)):
			updatePresence(presence, characterID, pawn, "work", room, target, "travel", clock)

# The crews of players' shifts: while the player works a shift, the coworkers who were at the workplace when it began stay and work it with them, then pack up for ten minutes and go on.
# memory["crews"][jobID] = {"ids": [...], "end": clock at which the player's shift ends}. Returns "work", "finish" or "" for this character at this clock.
static func crewKind(memory:Dictionary, characterID, clock:int) -> String:
	var crews:Dictionary = memory.get("crews", {})
	for jobID in crews:
		var crew:Dictionary = crews[jobID]
		if(!crew["ids"].has(characterID)):
			continue
		if(clock < int(crew["end"])):
			return "work"
		if(clock < int(crew["end"]) + RoutineScript.FINISH_SECONDS):
			return "finish"
	return ""

# ---- Running ----
# Runs the director if it is due (a new ten-minute bucket). Returns a summary {"ran", "hydrated", "directed", "moved", "incident", "jumped"} for tests.
static func tick(module, memory:Dictionary, force:bool = false) -> Dictionary:
	var summary:Dictionary = {"ran": false, "hydrated": [], "directed": [], "moved": [], "incident": [], "jumped": false}
	if(GM.main == null || !is_instance_valid(GM.main) || GM.pc == null || GM.world == null || !is_instance_valid(GM.world) || GM.main.IS == null):
		return summary
	if(GM.main.isInDungeon() || GM.main.PS != null):
		return summary
	var now:int = GM.main.getTime()
	var day:int = GM.main.getDays()
	var bucket:int = day * 144 + int(now / 600)
	if(!force && memory.get("bucket", -1) == bucket):
		commutePass(module, now, day) # between runs, workers still set off on time for their shift
		return summary
	memory["bucket"] = bucket
	summary["ran"] = true
	run(module, memory, summary, GM.pc.getLocation(), now, day)
	return summary

# Sets the whole prison up before the player can see it (when a game is loaded or started): every inmate gets today's plan and, if there is no record of where they are, is put where their plan has
# them right now, or at the point along the real route there that the time since their activity began allows. Pawns that already have a record keep their place. Nobody is created in view and sent
# away. The same save and the same time always give the same places. Returns the same summary as tick.
static func bootstrap(module, memory:Dictionary) -> Dictionary:
	var summary:Dictionary = {"ran": false, "hydrated": [], "directed": [], "moved": [], "incident": [], "jumped": false}
	if(GM.main == null || !is_instance_valid(GM.main) || GM.pc == null || GM.world == null || !is_instance_valid(GM.world) || GM.main.IS == null):
		return summary
	if(GM.main.isInDungeon() || GM.main.PS != null):
		return summary
	var now:int = GM.main.getTime()
	var day:int = GM.main.getDays()
	memory.clear()
	memory["bucket"] = day * 144 + int(now / 600)
	memory["bootstrap"] = true
	summary["ran"] = true
	run(module, memory, summary, GM.pc.getLocation(), now, day)
	memory.erase("bootstrap")
	return summary

# The place along the way: where a pawn with no record is at `now` when its current segment (index) began at the segment's start. They set out from the room of the segment before and have
# walked one room per STEP_SECONDS; once there was time to arrive they are at the destination.
static func bootstrapRoom(world, plan:Array, index:int, now:int, wantedRoom:String) -> String:
	if(index <= 0 || !world.hasRoomID(wantedRoom)):
		return wantedRoom
	var from:String = str(plan[index - 1][3])
	if(from == wantedRoom || !world.hasRoomID(from)):
		return wantedRoom
	var path:Array = world.calculatePath(from, wantedRoom)
	if(path.size() < 2):
		return wantedRoom
	var walked:int = int(max(0, RoutineScript.axis(now) - int(plan[index][0])) / STEP_SECONDS)
	return str(path[int(min(walked, path.size() - 1))])

static func run(module, memory:Dictionary, summary:Dictionary, pcLoc:String, now:int, day:int) -> void:
	var IS = GM.main.IS
	var world = GM.world
	var ids:Array = module.getDirectedInmateIDs()
	var jobKey:String = str(day) + ":" + str(ids.size())
	if(memory.get("jobs", "") != jobKey):
		memory["jobs"] = jobKey
		var info:Dictionary = gangFacts(module)
		var duty:Array = []
		for gid in info["byGang"]:
			duty.append(info["byGang"][gid]["leader"])
			duty.append(info["byGang"][gid]["anchor"])
		for slaveID in module.getOwnership().slaveIDs():
			duty.append(slaveID) # the player's slaves have no inmate job (they have a role instead, see Ownership/)
		var _given:int = module.getNpcJobs().ensure(ids, day, duty)
	var clock:int = clockOf(day, now)
	var elapsed:int = clock - int(memory.get("clock", clock))
	memory["clock"] = clock
	var jumped:bool = elapsed > JUMP_SECONDS
	summary["jumped"] = jumped
	var gangInfo:Dictionary = gangFacts(module)
	var sawWorking:Array = []
	var presence:Dictionary = module.getState().presence
	var gangsService = module.getGangs()
	for characterID in ids:
		if(gangsService.isCaptive(characterID)):
			holdAtGang(module, IS, world, summary, presence, characterID, clock, jumped, elapsed, bool(memory.get("bootstrap", false)))
			continue
		if(module.isHeldAway(characterID)):
			continue
		var facts:Dictionary = factsFor(module, characterID, day, gangInfo)
		var plan:Array = planOf(module, characterID, day, facts)
		if(plan.empty()):
			continue
		var index:int = RoutineScript.segmentIndex(plan, now)
		var pawnBefore = IS.getPawn(characterID)
		var commute:int = commuteTarget(world, plan, index, now, pawnBefore.getLocation() if pawnBefore != null else str(plan[index][3]), characterID, day)
		if(commute >= 0):
			index = commute # time to set off for the shift: they head for the workplace now
		var segment:Array = plan[index]
		var kind:String = str(segment[2])
		var room:String = str(segment[3])
		var crewState:String = crewKind(memory, characterID, clock)
		if(crewState != "" && EmploymentScript.isValidJob(str(facts["job"]))):
			kind = crewState
			room = str(EmploymentScript.JOBS[facts["job"]]["room"])
		var wanted:Dictionary = module.getRoutineOverride(characterID, day, RoutineScript.axis(now)) # the owner at their cell for a check-in; a slave at their post, report or escape
		if(!wanted.empty()):
			kind = str(wanted["kind"])
			room = str(wanted["room"])
		# A worker who cannot work today, or a place that does not exist on this map, is replaced by somewhere sensible, the same way every time
		if(kind == "work" && !bool(facts["available"])):
			kind = "hall"
			room = RoutineScript.roomFor("hall", characterID, day, 7, facts)
		if(room == "" || !world.hasRoomID(room)):
			kind = "cellrest" if str(facts["cellRoom"]) != "" && world.hasRoomID(str(facts["cellRoom"])) else "hall"
			room = str(facts["cellRoom"]) if kind == "cellrest" else RoutineScript.roomFor("hall", characterID, day, 3, facts)
		var pawn = IS.getPawn(characterID)
		var booting:bool = bool(memory.get("bootstrap", false))
		var hasRecord:bool = str(presence.get(characterID, {}).get("room", "")) != "" && world.hasRoomID(str(presence[characterID]["room"]))
		if(pawn == null):
			var where:String = hydrationRoom(world, presence.get(characterID, {}), plan, index, room) if (!booting || hasRecord) else bootstrapRoom(world, plan, index, now, room)
			pawn = spawnAt(IS, characterID, where)
			if(pawn == null):
				continue
			summary["hydrated"].append(characterID)
		elif(booting && !hasRecord && !module.isPawnBlocked(pawn) && (pawn.currentInteraction == null || pawn.currentInteraction.id == "AloneInteraction")):
			placeFreePawn(IS, pawn, bootstrapRoom(world, plan, index, now, room))
			summary["moved"].append(characterID)
		if(module.isPawnBlocked(pawn)):
			updatePresence(presence, characterID, pawn, kind, room, index, "busy", clock)
			continue
		if(jumped && advanceAlong(IS, world, pawn, room, elapsed)):
			summary["moved"].append(characterID)
		keepNeedsSane(pawn, kind, room)
		if(!isPinned(pawn, kind, room)):
			if(directPawn(pawn, kind, room, module.hangoutLabel(characterID) if kind == "hangout" else "")):
				summary["directed"].append(characterID)
		clearIfStuck(pawn)
		var arrived:bool = pawn.getLocation() == room
		updatePresence(presence, characterID, pawn, kind, room, index, ("sleep" if kind == "sleep" else "do") if arrived else "travel", clock)
		if(kind == "work" && arrived && pawn.getLocation() == pcLoc):
			sawWorking.append(characterID)
	for characterID in sawWorking:
		var _learned:bool = module.getNpcJobs().learn(characterID)
	var incident:Array = maybeIncident(module, IS, ringOf(world, pcLoc), memory, clock)
	if(!incident.empty()):
		summary["incident"] = incident

# A captured member or a gang's slave is kept at the holding gang's hangout all day, as a real pawn there (they are never taken off the map): "held" or "enslaved".
static func holdAtGang(module, IS, world, summary:Dictionary, presence:Dictionary, characterID, clock:int, jumped:bool, elapsed:int, booting:bool = false) -> void:
	var gangs = module.getGangs()
	var record:Dictionary = gangs.getCaptive(characterID)
	var holder:String = str(record.get("gang", ""))
	var kind:String = "enslaved" if record.get("kind", "") == "slave" else "held"
	var room:String = gangs.getHangout(holder) if holder != "" else ""
	if(room == "" || !world.hasRoomID(room)):
		room = "hall_mainentrance"
	var pawn = IS.getPawn(characterID)
	if(pawn == null):
		var last:String = str(presence.get(characterID, {}).get("room", ""))
		pawn = spawnAt(IS, characterID, last if last != "" && world.hasRoomID(last) else room)
		if(pawn == null):
			return
		summary["hydrated"].append(characterID)
	if(module.isPawnBlocked(pawn)):
		updatePresence(presence, characterID, pawn, kind, room, 0, "busy", clock)
		return
	if(booting && str(presence.get(characterID, {}).get("room", "")) == "" && (pawn.currentInteraction == null || pawn.currentInteraction.id == "AloneInteraction")):
		placeFreePawn(IS, pawn, room) # an old save with no record: they are where their holder keeps them
		summary["moved"].append(characterID)
	if(jumped && advanceAlong(IS, world, pawn, room, elapsed)):
		summary["moved"].append(characterID)
	keepNeedsSane(pawn, kind, room)
	if(!isPinned(pawn, kind, room)):
		if(directPawn(pawn, kind, room, gangs.gangName(holder))):
			summary["directed"].append(characterID)
	clearIfStuck(pawn)
	updatePresence(presence, characterID, pawn, kind, room, 0, "do" if pawn.getLocation() == room else "travel", clock)

# BDCC's own needs would otherwise pull a pawn off its plan: a tired pawn leaves the prison, a hungry one walks to the canteen at any hour. The plan has its own meals and its own beds, so the
# needs are kept under the point where they take over. (A meal in the plan satisfies hunger.)
static func keepNeedsSane(pawn, kind:String, room:String) -> void:
	pawn.tiredness = 0.0
	if(kind == "meal" && pawn.getLocation() == room):
		pawn.hunger = 0.0
	else:
		pawn.hunger = min(pawn.hunger, 0.9)

# Where to bring a deleted pawn back: the room of its record when that room exists; otherwise the place its plan puts it (the room before the current segment is where it must have come
# from), never a room chosen because of the player.
static func hydrationRoom(world, record:Dictionary, plan:Array, index:int, wantedRoom:String) -> String:
	var last:String = str(record.get("room", ""))
	if(last != "" && world.hasRoomID(last)):
		return last
	if(index > 0 && world.hasRoomID(str(plan[index - 1][3]))):
		return str(plan[index - 1][3])
	return wantedRoom

static func updatePresence(presence:Dictionary, characterID, pawn, kind:String, room:String, index:int, act:String, clock:int) -> void:
	var record:Dictionary = presence.get(characterID, PresenceScript.defaultRecord())
	var changed:bool = str(record.get("kind", "")) != kind || str(record.get("dest", "")) != room || int(record.get("seg", -1)) != index
	record["room"] = pawn.getLocation()
	record["kind"] = kind
	record["dest"] = room
	record["act"] = act
	record["seg"] = index
	if(changed):
		record["since"] = clock
	presence[characterID] = record

# Moves a free pawn along the real path towards its target by the distance `elapsed` seconds allow after the minutes the game itself simulated. Arrives if there was time. Returns whether it moved.
static func advanceAlong(IS, world, pawn, room:String, elapsed:int) -> bool:
	var steps:int = int((elapsed - 600) / STEP_SECONDS)
	var here:String = pawn.getLocation()
	if(steps <= 0 || here == room):
		return false
	var path:Array = world.calculatePath(here, room)
	if(path.size() < 2):
		return false
	var landing:String = str(path[int(min(steps, path.size() - 1))])
	if(landing == here):
		return false
	var wasDisabled:bool = IS.interactionsDisabled
	IS.interactionsDisabled = true
	pawn.setLocation(landing)
	IS.interactionsDisabled = wasDisabled
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.get("cachedTarget") != null):
		interaction.cachedTarget = "" # the walking cache starts again from where they are now
		interaction.cachedPath = []
	return true

# Moves a free pawn to a room without anything noticing on the way (used only by the bootstrap, before the player can see the prison).
static func placeFreePawn(IS, pawn, roomID:String) -> void:
	if(pawn.getLocation() == roomID):
		return
	var wasDisabled:bool = IS.interactionsDisabled
	IS.interactionsDisabled = true
	pawn.setLocation(roomID)
	IS.interactionsDisabled = wasDisabled
	var interaction = pawn.currentInteraction
	if(interaction != null && interaction.get("cachedTarget") != null):
		interaction.cachedTarget = ""
		interaction.cachedPath = []

# A pawn that has not got closer for several actions in a row keeps trying with a fresh route; it is never marked as having arrived and never teleported.
static func clearIfStuck(pawn) -> void:
	var interaction = pawn.currentInteraction
	if(interaction == null || interaction.id != "AloneInteraction" || interaction.goal == null || interaction.goal.get("stuck") == null):
		return
	if(int(interaction.goal.stuck) >= STUCK_LIMIT):
		interaction.goal.stuck = 0
		interaction.cachedTarget = ""
		interaction.cachedPath = []

# BDCC's own spawn, then a move to the wanted room with meetings held back until the pawn is in place (so nothing happens at the stairs the spawner first uses).
static func spawnAt(IS, characterID, roomID:String):
	if(IS.hasPawn(characterID)):
		return IS.getPawn(characterID)
	var wasDisabled:bool = IS.interactionsDisabled
	IS.interactionsDisabled = true
	var pawn = IS.spawnPawn(characterID)
	if(pawn != null):
		pawn.setLocation(roomID)
	IS.interactionsDisabled = wasDisabled
	if(pawn != null && !wasDisabled):
		IS.onPawnMoved(characterID, "", roomID) # now let whoever is there notice
	return pawn

# Whether the pawn already follows this plan segment.
static func isPinned(pawn, kind:String, roomID:String) -> bool:
	var interaction = pawn.currentInteraction
	if(interaction == null || interaction.id != "AloneInteraction" || interaction.goal == null):
		return false
	return interaction.goal.id == "SandboxRoutine" && interaction.goal.get("target") == roomID && interaction.goal.get("kind") == kind

# Gives the pawn the routine goal for this segment. Only a pawn that is idling can be directed (anything else is busy and is left alone).
static func directPawn(pawn, kind:String, roomID:String, label:String = "") -> bool:
	if(pawn == null || pawn.isDeleted || GM.world == null):
		return false
	var interaction = pawn.getInteraction()
	if(interaction == null || interaction.id != "AloneInteraction"):
		return false
	var goal = InteractionGoal.create("SandboxRoutine")
	if(goal == null):
		return false
	goal.kind = kind
	goal.target = roomID
	goal.gangName = label
	return interaction.switchGoalToObject(goal)

# ---- Quarrels in view ----
# Two free inmates in one room within sight of the player who have a quarrel (their gangs are enemies, or one of them cannot stand the other) may start a fight with each other, which
# BDCC's own GenericAttack plays out in front of the player: it can be watched, joined, or broken up (see Module.getFightInterruptActions). Rare, never with the player involved, never with
# someone busy. Returns [starterID, reacterID] when one started. clock: the director's clock (see clockOf).
static func maybeIncident(module, IS, ring:Dictionary, memory:Dictionary, clock:int) -> Array:
	if(clock - int(memory.get("incident_stamp", -INCIDENT_GAP_SECONDS)) < INCIDENT_GAP_SECONDS):
		return []
	var gangs = module.getGangs()
	var RS = GM.main.RS
	for roomID in ring:
		var free:Array = []
		for pawn in IS.getPawnsAt(roomID):
			if(pawn != null && !pawn.isPlayer() && pawn.isInmate() && !module.isPawnBlocked(pawn) && !module.isHeldAway(pawn.charID)):
				free.append(pawn.charID)
		free.sort()
		for first in free:
			for second in free:
				if(first >= second):
					continue
				var theirs:String = gangs.gangOf(first)
				var other:String = gangs.gangOf(second)
				var quarrel:bool = theirs != "" && other != "" && theirs != other && gangs.areEnemies(theirs, other)
				quarrel = quarrel || RS.getAffection(first, second) <= QUARREL_AFFECTION || RS.getAffection(second, first) <= QUARREL_AFFECTION
				if(!quarrel):
					continue
				memory["incident_stamp"] = clock # the chance is rolled once per due check, win or lose
				if(module.nextRoll() >= INCIDENT_CHANCE):
					return []
				var starterID:String = first if RS.getAffection(first, second) <= RS.getAffection(second, first) else second
				var reacterID:String = second if starterID == first else first
				IS.startInteraction("GenericAttack", {"starter": starterID, "reacter": reacterID})
				return [starterID, reacterID]
	return []

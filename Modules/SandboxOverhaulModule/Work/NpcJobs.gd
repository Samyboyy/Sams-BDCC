extends Reference
class_name NpcJobs

# The jobs of the other inmates. No game access, so it can be tested on its own: callers pass IDs and the day number.
#
# SandboxState.npc_jobs = {
#   "jobs":  {characterID: {"job": job id, "since": day, "moves": int}},    only employed inmates are listed; everybody else is unemployed
#   "known": {characterID: true}                                            the player has seen them work or been told their job
# }
# About two in five inmates have a job, spread over the three workplaces by their capacity. Nobody already employed is ever moved by the daily top-up; jobs only change
# through transfer() (for example after repeated workplace conflict) or when the inmate stops being eligible. The same people therefore keep turning up at the same place.

const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const ScheduleScript = preload("res://Modules/SandboxOverhaulModule/Prison/PrisonSchedule.gd")

const CAPACITY = {"mining": 6, "workshop": 5, "laundry": 4}
const EMPLOYED_SHARE = 0.4

var state

func _init(_state):
	state = _state

static func defaults() -> Dictionary:
	return {"jobs": {}, "known": {}}

static func sanitize(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(!(raw is Dictionary)):
		return result
	var jobs = raw.get("jobs")
	if(jobs is Dictionary):
		var filled:Dictionary = {}
		for characterID in jobs:
			var entry = jobs[characterID]
			if(!(characterID is String) || characterID == "" || characterID == "pc" || !(entry is Dictionary) || !EmploymentScript.isValidJob(entry.get("job"))):
				continue
			if(int(filled.get(entry["job"], 0)) >= int(CAPACITY[entry["job"]])):
				continue # never more than the workplace holds, even from a damaged save
			filled[entry["job"]] = int(filled.get(entry["job"], 0)) + 1
			result["jobs"][characterID] = {
				"job": entry["job"],
				"since": int(round(float(entry["since"]))) if ScheduleScript.isNumberValue(entry.get("since")) else 0,
				"moves": int(max(0, round(float(entry["moves"])))) if ScheduleScript.isNumberValue(entry.get("moves")) else 0,
			}
	var known = raw.get("known")
	if(known is Dictionary):
		for characterID in known:
			if((characterID is String) && characterID != "" && typeof(known[characterID]) == TYPE_BOOL && known[characterID]):
				result["known"][characterID] = true
	return result

# ---- Reading ----
func getJob(characterID) -> String:
	if(!(characterID is String) || !state.npc_jobs["jobs"].has(characterID)):
		return ""
	return str(state.npc_jobs["jobs"][characterID]["job"])

func isEmployed(characterID) -> bool:
	return getJob(characterID) != ""

# Everyone with this job, in a stable order.
func workers(jobID) -> Array:
	var result:Array = []
	if(!EmploymentScript.isValidJob(jobID)):
		return result
	for characterID in state.npc_jobs["jobs"]:
		if(state.npc_jobs["jobs"][characterID]["job"] == jobID):
			result.append(characterID)
	result.sort()
	return result

func workerCount(jobID) -> int:
	return workers(jobID).size()

func freePlaces(jobID) -> int:
	if(!EmploymentScript.isValidJob(jobID)):
		return 0
	return int(CAPACITY[jobID]) - workerCount(jobID)

# Coworkers of a character: everyone else with the same job.
func coworkers(characterID) -> Array:
	var job:String = getJob(characterID)
	var result:Array = workers(job)
	result.erase(characterID)
	return result

func getEntry(characterID) -> Dictionary:
	if(!isEmployed(characterID)):
		return {}
	return state.npc_jobs["jobs"][characterID].duplicate()

func employedIDs() -> Array:
	var ids:Array = state.npc_jobs["jobs"].keys()
	ids.sort()
	return ids

# How many of this many eligible inmates should have a job.
static func targetFor(eligibleCount:int) -> int:
	var total:int = 0
	for jobID in EmploymentScript.JOB_ORDER:
		total += int(CAPACITY[jobID])
	return int(min(total, int(ceil(float(max(0, eligibleCount)) * EMPLOYED_SHARE))))

# ---- Changing ----
# Employs a character. Refused for the player, for a full workplace and for an unknown job.
func assign(characterID, jobID, day:int) -> bool:
	if(!(characterID is String) || characterID == "" || characterID == "pc" || !EmploymentScript.isValidJob(jobID) || freePlaces(jobID) <= 0 || isEmployed(characterID)):
		return false
	state.npc_jobs["jobs"][characterID] = {"job": jobID, "since": day, "moves": 0}
	return true

func release(characterID) -> bool:
	if(!isEmployed(characterID)):
		return false
	state.npc_jobs["jobs"].erase(characterID)
	return true

# Moves an employed character to another workplace with room (or out of work with ""). The move is counted. Returns whether it happened.
func transfer(characterID, jobID, day:int) -> bool:
	if(!isEmployed(characterID)):
		return false
	if(jobID == ""):
		var moves:int = int(state.npc_jobs["jobs"][characterID]["moves"]) + 1
		state.npc_jobs["jobs"].erase(characterID)
		return moves > 0
	if(!EmploymentScript.isValidJob(jobID) || jobID == getJob(characterID) || freePlaces(jobID) <= 0):
		return false
	var entry:Dictionary = state.npc_jobs["jobs"][characterID]
	entry["job"] = jobID
	entry["since"] = day
	entry["moves"] = int(entry["moves"]) + 1
	return true

# The other workplace with room for one more, in the usual order, or "".
func nextOpenJob(exceptJob:String = "") -> String:
	for jobID in EmploymentScript.JOB_ORDER:
		if(jobID != exceptJob && freePlaces(jobID) > 0):
			return jobID
	return ""

# Brings the jobs in line with who exists. eligibleIDs: the inmates who can work (never the player). Anyone no longer eligible loses their job; then people without one
# (excludedIDs, the gang leaders and the members who keep them company, never work: the hangout is their duty and they would otherwise miss their afternoon there) are given jobs, in a stable order and always to the workplace with the most room left in proportion, until about two in five have one. Nobody already employed is moved.
# Returns how many jobs were handed out.
func ensure(eligibleIDs:Array, day:int, excludedIDs:Array = []) -> int:
	var eligible:Dictionary = {}
	for characterID in eligibleIDs:
		if(characterID is String && characterID != "" && characterID != "pc" && !excludedIDs.has(characterID)):
			eligible[characterID] = true
	for characterID in state.npc_jobs["jobs"].keys():
		if(!eligible.has(characterID)):
			state.npc_jobs["jobs"].erase(characterID)
	for characterID in state.npc_jobs["known"].keys():
		if(!eligible.has(characterID)):
			state.npc_jobs["known"].erase(characterID)
	var target:int = targetFor(eligible.size())
	var candidates:Array = []
	for characterID in eligible:
		if(!isEmployed(characterID)):
			candidates.append(characterID)
	candidates.sort_custom(self, "sortByHash")
	var given:int = 0
	for characterID in candidates:
		if(employedIDs().size() >= target):
			break
		var best:String = ""
		var bestRatio:float = 2.0
		for jobID in EmploymentScript.JOB_ORDER:
			if(freePlaces(jobID) <= 0):
				continue
			var ratio:float = float(workerCount(jobID)) / float(CAPACITY[jobID])
			if(ratio < bestRatio):
				bestRatio = ratio
				best = jobID
		if(best == "" || !assign(characterID, best, day)):
			break
		given += 1
	return given

func sortByHash(a, b) -> bool:
	var hashA:int = ScheduleScript.hashOf(a, "npcjob")
	var hashB:int = ScheduleScript.hashOf(b, "npcjob")
	if(hashA != hashB):
		return hashA < hashB
	return str(a) < str(b)

# ---- What the player knows ----
func learn(characterID) -> bool:
	if(!isEmployed(characterID) || state.npc_jobs["known"].has(characterID)):
		return false
	state.npc_jobs["known"][characterID] = true
	return true

func isKnown(characterID) -> bool:
	return isEmployed(characterID) && state.npc_jobs["known"].has(characterID)

func removeCharacter(characterID) -> void:
	if(characterID is String):
		state.npc_jobs["jobs"].erase(characterID)
		state.npc_jobs["known"].erase(characterID)

# "Works in the mines" style line for a known job, "" otherwise.
func knownJobText(characterID) -> String:
	if(!isKnown(characterID)):
		return ""
	var jobID:String = getJob(characterID)
	return str(EmploymentScript.JOBS[jobID]["name"]) + " at the " + str(EmploymentScript.JOBS[jobID]["workplace"]).to_lower()

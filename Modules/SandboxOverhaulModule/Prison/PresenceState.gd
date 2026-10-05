extends Reference
class_name PresenceState

# The saved side of persistent lives. No game access, so it can be tested on its own.
#
# SandboxState.routines = {"day": int (the prison day the plans are for, -1 none), "plans": {characterID: [[start, end, kind, room], ...]}}
#   Today's plan for each inmate, generated once when the day begins (or when an inmate first appears) and never rerolled by loading, by the player moving or by looking.
# SandboxState.presence = {characterID: {"room": where they were last seen, "kind": what they are doing, "act": "travel"|"do"|"sleep"|"busy", "dest": where they are going, "since": stamp, "seg": plan segment}}
#   One small record for every inmate, kept up to date from their pawn. It is the memory of where somebody is, so a pawn that is deleted by something else in the game is brought back
#   exactly where it was, in the same activity, and never in a room picked because the player came near.

const RoutineScript = preload("res://Modules/SandboxOverhaulModule/Prison/DailyRoutine.gd")

const ACTS = ["", "travel", "do", "sleep", "busy"]
const MAX_RECORDS = 400

static func defaultRoutines() -> Dictionary:
	return {"day": -1, "plans": {}}

static func defaultRecord() -> Dictionary:
	return {"room": "", "kind": "", "act": "", "dest": "", "since": 0, "seg": -1}

static func sanitizeRoutines(raw) -> Dictionary:
	var result:Dictionary = defaultRoutines()
	if(!(raw is Dictionary)):
		return result
	if(RoutineScript.isNumberValue(raw.get("day"))):
		result["day"] = int(round(float(raw["day"])))
	var plans = raw.get("plans")
	if(plans is Dictionary):
		for id in plans:
			if(!(id is String) || id == "" || id == "pc" || !RoutineScript.isValidPlan(plans[id])):
				continue
			var clean:Array = []
			for segment in plans[id]:
				clean.append([int(round(float(segment[0]))), int(round(float(segment[1]))), str(segment[2]), str(segment[3])])
			result["plans"][id] = clean
			if(result["plans"].size() >= MAX_RECORDS):
				break
	return result

static func sanitizePresence(raw) -> Dictionary:
	var result:Dictionary = {}
	if(!(raw is Dictionary)):
		return result
	for id in raw:
		if(!(id is String) || id == "" || id == "pc" || !(raw[id] is Dictionary)):
			continue
		var source:Dictionary = raw[id]
		var record:Dictionary = defaultRecord()
		if(source.get("room") is String):
			record["room"] = source["room"]
		if(source.get("dest") is String):
			record["dest"] = source["dest"]
		if((source.get("kind") is String) && (source["kind"] == "" || RoutineScript.KINDS.has(source["kind"]))):
			record["kind"] = source["kind"]
		if((source.get("act") is String) && ACTS.has(source["act"])):
			record["act"] = source["act"]
		if(RoutineScript.isNumberValue(source.get("since"))):
			record["since"] = int(round(float(source["since"])))
		if(RoutineScript.isNumberValue(source.get("seg"))):
			record["seg"] = int(clamp(round(float(source["seg"])), -1, 60))
		result[id] = record
		if(result.size() >= MAX_RECORDS):
			break
	return result

extends InteractionGoalBase

# Sandbox overhaul (see CORE_PATCHES.md): an inmate's planned activity from SandboxOverhaulModule's daily routine: sleep, work, a meal, the gym... Nothing in BDCC ever picks this goal
# by itself (its score is 0 and it is not in the goal lists); only the module gives it to a pawn, and it keeps the pawn on its plan with a high keep score. It walks the pawn to
# "target" one room at a time with the normal goTowards, and tells the module what to write ("{main.name} is sleeping in {main.his} cell.") from the activity it really has,
# so the text follows the pawn's state and not the clock. Without the module it is inert.

var kind:String = ""
var target:String = ""
var gangName:String = ""
var lastLoc:String = ""
var stuck:int = 0 # consecutive actions that did not move the pawn closer; the module reads it to retry or repair

func getScore(_pawn:CharacterPawn) -> float:
	return 0.0

func getKeepScore() -> float:
	return 0.95

func getText():
	var sandboxModule = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(sandboxModule == null):
		return "{main.name} is hanging out!"
	return sandboxModule.getRoutineText(kind, getLocation(), target, gangName)

func isArrived() -> bool:
	return getLocation() == target

func getActions() -> Array:
	if(isArrived()):
		return [
			{
				id = "stay",
				name = "Stay",
				desc = "Carry on with it",
				score = 1.0,
				args = {},
				time = 120, # short, so a new plan segment is noticed within two minutes
			},
		]
	return [
		{
			id = "go",
			name = "Go",
			desc = "Head there",
			score = 1.0,
			args = {},
			time = 60,
		},
	]

func doAction(_id:String, _args:Dictionary):
	if(_id == "go"):
		var before:String = getLocation()
		var _arrived = goTowards(target)
		if(getLocation() == before && before != target):
			stuck += 1
		else:
			stuck = 0
		lastLoc = getLocation()
	if(_id == "stay"):
		stuck = 0

func getAnimData() -> Array:
	if(!isArrived()):
		return [StageScene.Solo, "walk", {pc="main"}]
	return [StageScene.Solo, "stand", {pc="main"}]

func getActivityIcon():
	if(!isArrived()):
		return RoomStuff.PawnActivity.None
	if(kind == "work" || kind == "finish"):
		return RoomStuff.PawnActivity.Work
	if(kind == "meal"):
		return RoomStuff.PawnActivity.Eat
	if(kind == "shower"):
		return RoomStuff.PawnActivity.Shower
	return RoomStuff.PawnActivity.None

func saveData():
	var data = .saveData()
	data["k"] = kind
	data["t"] = target
	data["g"] = gangName
	data["l"] = lastLoc
	data["s"] = stuck
	return data

func loadData(_data):
	.loadData(_data)
	kind = SAVE.loadVar(_data, "k", "")
	target = SAVE.loadVar(_data, "t", "")
	gangName = SAVE.loadVar(_data, "g", "")
	lastLoc = SAVE.loadVar(_data, "l", "")
	stuck = SAVE.loadVar(_data, "s", 0)

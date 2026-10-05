extends RoomAction

# A button added by WorkWorldEdit. "board" and "shift" are always shown (a shift button that cannot start is disabled and says why); "upgrades" only in the player's own cell.

const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var kind:String = "board"

func _shouldShow() -> bool:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || GM.pc == null):
		return false
	if(kind == "upgrades"):
		return GM.pc.getLocation() == GM.pc.getCellLocation()
	return true

# A workplace always shows its shift button; when the shift cannot start, the button is disabled and says why. The job board is highlighted until it has been visited.
func _canRun() -> bool:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || GM.pc == null):
		return false
	if(kind == "shift"):
		var jobID:String = EmploymentScript.jobAtRoom(get_parent().roomID)
		var check:Dictionary = module.explainShift(jobID)
		if(check["ok"]):
			var job:Dictionary = EmploymentScript.JOBS[jobID]
			ActionTooltip = "Work about " + str(job["hours"]) + " hours for " + str(job["wage"]) + " credits. It costs " + str(job["stamina"]) + " stamina."
		else:
			ActionTooltip = check["reason"]
		return check["ok"]
	if(kind == "board"):
		ActionName = "Job board" if module.getEmployment().hasSeenBoard() else "Job board (new!)"
	return true

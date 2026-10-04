extends RoomAction

# A button added by WorkWorldEdit. "board" is always shown, "shift" only at the player's workplace and "upgrades" only in the player's own cell.

var kind:String = "board"

func _shouldShow() -> bool:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || GM.pc == null):
		return false
	if(kind == "upgrades"):
		return GM.pc.getLocation() == GM.pc.getCellLocation()
	if(kind == "shift"):
		return module.getEmployment().isEmployedAt(get_parent().roomID)
	return true

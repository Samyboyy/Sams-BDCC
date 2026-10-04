extends RoomAction

# A button added to a cell block room by CellsWorldEdit. Block halls always show it; a player cell only shows it to its owner.

var onlyInPlayerCell:bool = false

func _shouldShow() -> bool:
	if(onlyInPlayerCell):
		return GM.pc != null && GM.pc.getLocation() == GM.pc.getCellLocation()
	return true
